import Text "mo:core/Text";
import Array "mo:core/Array";
import Map "mo:core/Map";
import Result "mo:core/Result";
import Iter "mo:core/Iter";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Option "mo:core/Option";
import Nat32 "mo:core/Nat32";
import Nat8 "mo:core/Nat8";
import Char "mo:core/Char";

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
        private var buffer = List.empty<Nat8>();
        private var storedFiles = Map.fromIter<Text, StoredFile>(
            state.storedFiles.values(),
            Text.compare,
        );

        public func upload(chunk : [Nat8]) {
            for (byte in chunk.vals()) {
                List.add(buffer, byte);
            };
        };

        public func uploadFinalize(title : Text, artist : Text, contentType : Text) : Result.Result<Text, Text> {
            if (Map.size(storedFiles) >= maxFiles and Option.isNull(Map.get(storedFiles, Text.compare, title))) {
                return #err("Maximum number of files reached");
            };

            let data = List.toArray(buffer);
            let totalChunks = Nat.max(1, (data.size() + chunkSize) / chunkSize);
            var chunks : [FileChunk] = [];
            var i = 0;

            while (i < data.size()) {
                let end = Nat.min(i + chunkSize, data.size());
                let chunk = Array.tabulate<Nat8>(end - i, func(j) = data[i + j]);
                chunks := Array.concat(chunks, [chunk]);
                i += chunkSize;
            };

            Map.add(
                storedFiles,
                Text.compare,
                title,
                {
                    title;
                    artist;
                    contentType;
                    totalChunks;
                    data = chunks;
                },
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
            let entries = Iter.toArray(Map.entries(storedFiles));
            Array.map<(Text, StoredFile), (Text, Text, Text)>(
                entries,
                func((title, file)) = (title, file.artist, file.contentType),
            );
        };

        public func deleteFile(title : Text) : Bool {
            switch (Map.take(storedFiles, Text.compare, title)) {
                case (null) { false };
                case (?_) {
                    state.storedFiles := Iter.toArray(Map.entries(storedFiles));
                    true;
                };
            };
        };

        public func getStoredFileCount() : Nat {
            Map.size(storedFiles);
        };

        // Get file as base64 data URL for embedding in HTML
        public func getFileAsDataUrl(title : Text) : ?Text {
            switch (Map.get(storedFiles, Text.compare, title)) {
                case (null) { null };
                case (?file) {
                    // Reconstruct full file from chunks
                    var allBytes : [Nat8] = [];
                    for (chunk in file.data.vals()) {
                        allBytes := Array.concat(allBytes, chunk);
                    };

                    // Convert to base64
                    let base64 = bytesToBase64(allBytes);

                    // Return as data URL
                    ?("data:" # file.contentType # ";base64," # base64);
                };
            };
        };

        // Helper function to convert bytes to base64
        private func bytesToBase64(bytes : [Nat8]) : Text {
            let base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            var result = "";
            var i = 0;

            while (i < bytes.size()) {
                let b1 = bytes[i];
                let b2 : Nat8 = if (i + 1 < bytes.size()) bytes[i + 1] else 0;
                let b3 : Nat8 = if (i + 2 < bytes.size()) bytes[i + 2] else 0;

                let n = (Nat32.fromNat(Nat8.toNat(b1)) << 16) |
                        (Nat32.fromNat(Nat8.toNat(b2)) << 8) |
                        Nat32.fromNat(Nat8.toNat(b3));

                let c1 = Nat32.toNat((n >> 18) & 63);
                let c2 = Nat32.toNat((n >> 12) & 63);
                let c3 = Nat32.toNat((n >> 6) & 63);
                let c4 = Nat32.toNat(n & 63);

                result #= Text.fromChar(charAt(base64Chars, c1));
                result #= Text.fromChar(charAt(base64Chars, c2));

                if (i + 1 < bytes.size()) {
                    result #= Text.fromChar(charAt(base64Chars, c3));
                } else {
                    result #= "=";
                };

                if (i + 2 < bytes.size()) {
                    result #= Text.fromChar(charAt(base64Chars, c4));
                } else {
                    result #= "=";
                };

                i += 3;
            };

            result;
        };

        private func charAt(str : Text, index : Nat) : Char {
            var i = 0;
            for (c in str.chars()) {
                if (i == index) return c;
                i += 1;
            };
            ' '; // Should never reach here with valid input
        };
    };
};
