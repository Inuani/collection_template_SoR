import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Iter "mo:core/Iter";
import List "mo:core/List";
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Option "mo:core/Option";
import Result "mo:core/Result";
import Text "mo:core/Text";

module {
    public let CHUNK_SIZE : Nat = 2_000_000;

    public type ChunkId = Nat;
    public type FileChunk = [Nat8];

    public type StreamingCallbackToken = {
        filename : Text;
        index : Nat;
        signature : Text;
    };

    public type StreamingCallbackHttpResponse = {
        body : [Nat8];
        token : ?StreamingCallbackToken;
    };

    public type StoredFile = {
        title : Text;
        artist : Text;
        contentType : Text;
        totalChunks : Nat;
        data : [FileChunk];
    };

    // Keep this persistent layout unchanged: all deployed file data uses it.
    public type State = {
        var storedFiles : [(Text, StoredFile)];
    };

    public func init() : State = {
        var storedFiles = [];
    };

    public func isFileName(value : Text) : Bool {
        let characters = Text.toArray(value);
        if (
            characters.size() == 0 or characters.size() > 160 or
            value == "." or value == ".."
        ) return false;
        for (character in characters.vals()) {
            let allowed =
                (character >= 'a' and character <= 'z') or
                (character >= 'A' and character <= 'Z') or
                (character >= '0' and character <= '9') or
                character == '.' or character == '_' or character == '~' or character == '-';
            if (not allowed) return false;
        };
        true;
    };

    func isSignature(value : Text) : Bool {
        let characters = Text.toArray(value);
        if (characters.size() == 0 or characters.size() > 128) return false;
        for (character in characters.vals()) {
            let allowed = (character >= '0' and character <= '9') or
                (character >= 'a' and character <= 'f') or character == '.';
            if (not allowed) return false;
        };
        true;
    };

    public func chunkCountForSize(size : Nat) : Nat {
        if (size == 0) 0 else (size + CHUNK_SIZE - 1) / CHUNK_SIZE;
    };

    public func tokenToBlob(token : StreamingCallbackToken) : [Nat8] {
        let text = token.filename # "|" # Nat.toText(token.index) # "|" # token.signature;
        Blob.toArray(Text.encodeUtf8(text));
    };

    public func tokenFromBlob(bytes : [Nat8]) : ?StreamingCallbackToken {
        let text = switch (Text.decodeUtf8(Blob.fromArray(bytes))) {
            case (?value) value;
            case null return null;
        };
        let parts = Iter.toArray(Text.split(text, #char '|'));
        if (parts.size() != 3 or not isFileName(parts[0]) or not isSignature(parts[2])) return null;
        let index = switch (Nat.fromText(parts[1])) {
            case (?value) value;
            case null return null;
        };
        ?{ filename = parts[0]; index; signature = parts[2] };
    };

    public class FileStorage(state : State) {
        private var buffer = List.empty<Nat8>();
        private var storedFiles = Map.fromIter<Text, StoredFile>(
            state.storedFiles.values(),
            Text.compare,
        );

        public func upload(chunk : [Nat8]) {
            for (byte in chunk.vals()) List.add(buffer, byte);
        };

        public func uploadFinalize(
            title : Text,
            artist : Text,
            contentType : Text,
        ) : Result.Result<Text, Text> {
            if (not isFileName(title)) {
                List.clear(buffer);
                return #err("Invalid file name");
            };
            let data = List.toArray(buffer);
            if (data.size() == 0) {
                List.clear(buffer);
                return #err("Cannot store an empty file");
            };

            let totalChunks = chunkCountForSize(data.size());
            let chunks = Array.tabulate<FileChunk>(
                totalChunks,
                func(index) {
                    let start = index * CHUNK_SIZE;
                    let end = Nat.min(start + CHUNK_SIZE, data.size());
                    Array.tabulate<Nat8>(end - start, func(offset) { data[start + offset] });
                },
            );
            Map.add(
                storedFiles,
                Text.compare,
                title,
                { title; artist; contentType; totalChunks; data = chunks },
            );
            state.storedFiles := Iter.toArray(Map.entries(storedFiles));
            List.clear(buffer);
            #ok("Upload successful");
        };

        public func getFileChunk(title : Text, chunkId : ChunkId) : ?{
            chunk : [Nat8];
            totalChunks : Nat;
            contentType : Text;
            title : Text;
            artist : Text;
        } {
            switch (Map.get(storedFiles, Text.compare, title)) {
                case null null;
                case (?file) {
                    if (chunkId >= file.data.size()) return null;
                    ?{
                        chunk = file.data[chunkId];
                        totalChunks = file.totalChunks;
                        contentType = file.contentType;
                        title = file.title;
                        artist = file.artist;
                    };
                };
            };
        };

        public func hasFile(title : Text) : Bool {
            Option.isSome(Map.get(storedFiles, Text.compare, title));
        };

        public func processStreamingCallbackWithValidator(
            token : StreamingCallbackToken,
            validate : (Text, Text) -> Bool,
        ) : ?StreamingCallbackHttpResponse {
            if (not validate(token.signature, token.filename)) return null;
            switch (Map.get(storedFiles, Text.compare, token.filename)) {
                case null null;
                case (?file) {
                    if (token.index >= file.data.size()) return null;
                    let nextIndex = token.index + 1;
                    let nextToken = if (nextIndex < file.data.size()) {
                        ?{
                            filename = token.filename;
                            index = nextIndex;
                            signature = token.signature;
                        };
                    } else null;
                    ?{ body = file.data[token.index]; token = nextToken };
                };
            };
        };

        public func listFiles() : [(Text, Text, Text)] {
            Array.map<(Text, StoredFile), (Text, Text, Text)>(
                Iter.toArray(Map.entries(storedFiles)),
                func((title, file)) { (title, file.artist, file.contentType) },
            );
        };

        public func getFileStartWithSignature(title : Text, signature : Text) : ?{
            chunk : [Nat8];
            totalChunks : Nat;
            contentType : Text;
            title : Text;
            artist : Text;
            nextToken : ?StreamingCallbackToken;
        } {
            switch (Map.get(storedFiles, Text.compare, title)) {
                case null null;
                case (?file) {
                    if (file.data.size() == 0) return null;
                    let nextToken = if (file.data.size() > 1) {
                        ?{ filename = title; index = 1; signature };
                    } else null;
                    ?{
                        chunk = file.data[0];
                        totalChunks = file.totalChunks;
                        contentType = file.contentType;
                        title = file.title;
                        artist = file.artist;
                        nextToken;
                    };
                };
            };
        };

        public func deleteFile(title : Text) : Bool {
            switch (Map.take(storedFiles, Text.compare, title)) {
                case null false;
                case (?_) {
                    state.storedFiles := Iter.toArray(Map.entries(storedFiles));
                    true;
                };
            };
        };

        public func getStoredFileCount() : Nat {
            Map.size(storedFiles);
        };
    };
};
