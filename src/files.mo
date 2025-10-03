import Text "mo:base/Text";
import Array "mo:base/Array";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";
import Option "mo:base/Option";

module {

    public type ChunkId = Nat;
    public type FileChunk = [Nat8];

    public type StoredFile = {
        title : Text;
        artist : Text;
        contentType : Text;
        totalChunks : Nat;
        data : [FileChunk];
    };

    public type State = {
        var storedFiles : [(Text, StoredFile)];
    };

    public func init() : State = {
        var storedFiles = [];
    };

    public class FileStorage(state : State) {
        private let maxFiles : Nat = 10;
        private let chunkSize : Nat = 2000000;
        private var buffer = Buffer.Buffer<Nat8>(0);
        private var storedFiles : HashMap.HashMap<Text, StoredFile> = HashMap.fromIter<Text, StoredFile>(
            state.storedFiles.vals(),
            state.storedFiles.size(),
            Text.equal,
            Text.hash,
        );

        public func upload(chunk : [Nat8]) {
            for (byte in chunk.vals()) {
                buffer.add(byte);
            };
        };

        public func uploadFinalize(title : Text, artist : Text, contentType : Text) : Result.Result<Text, Text> {
            if (storedFiles.size() >= maxFiles and Option.isNull(storedFiles.get(title))) {
                return #err("Maximum number of files reached");
            };

            let data = Buffer.toArray(buffer);
            let totalChunks = Nat.max(1, (data.size() + chunkSize) / chunkSize);
            var chunks : [FileChunk] = [];
            var i = 0;

            while (i < data.size()) {
                let end = Nat.min(i + chunkSize, data.size());
                let chunk = Array.tabulate<Nat8>(end - i, func(j) = data[i + j]);
                chunks := Array.append(chunks, [chunk]);
                i += chunkSize;
            };

            storedFiles.put(
                title,
                {
                    title;
                    artist;
                    contentType;
                    totalChunks;
                    data = chunks;
                },
            );

            state.storedFiles := Iter.toArray(storedFiles.entries());
            buffer.clear();
            #ok("Upload successful");
        };

        public func getFileChunk(title : Text, chunkId : ChunkId) : ?{
            chunk : [Nat8];
            totalChunks : Nat;
            contentType : Text;
            title : Text;
            artist : Text;
        } {
            switch (storedFiles.get(title)) {
                case (null) { null };
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

        public func listFiles() : [(Text, Text, Text)] {
            let entries = Iter.toArray(storedFiles.entries());
            Array.map<(Text, StoredFile), (Text, Text, Text)>(
                entries,
                func((title, file)) = (title, file.artist, file.contentType),
            );
        };

        public func deleteFile(title : Text) : Bool {
            switch (storedFiles.remove(title)) {
                case (null) { false };
                case (?_) {
                    state.storedFiles := Iter.toArray(storedFiles.entries());
                    true;
                };
            };
        };

        public func getStoredFileCount() : Nat {
            storedFiles.size();
        };
    };
};
