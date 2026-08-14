import Blob "mo:core/Blob";
import Text "mo:core/Text";

import Files "../src/files";

assert (Files.isFileName("heloise-card-1.snk"));
assert (Files.isFileName("audio_track~final.m4a"));
assert (not Files.isFileName(""));
assert (not Files.isFileName("."));
assert (not Files.isFileName(".."));
assert (not Files.isFileName("../private.snk"));
assert (not Files.isFileName("folder/card.snk"));
assert (not Files.isFileName("héloise.snk"));

assert (Files.chunkCountForSize(0) == 0);
assert (Files.chunkCountForSize(1) == 1);
assert (Files.chunkCountForSize(Files.CHUNK_SIZE) == 1);
assert (Files.chunkCountForSize(Files.CHUNK_SIZE + 1) == 2);
assert (Files.chunkCountForSize(Files.CHUNK_SIZE * 2) == 2);

let serializedToken : Files.StreamingCallbackToken = {
    filename = "card.snk";
    index = 3;
    signature = "123.abcdef";
};
assert (
    Files.tokenFromBlob(Files.tokenToBlob(serializedToken)) == ?serializedToken
);
assert (Files.tokenFromBlob(Blob.toArray(Text.encodeUtf8("../x|0|abc"))) == null);
assert (Files.tokenFromBlob(Blob.toArray(Text.encodeUtf8("x|not-a-number|abc"))) == null);

let state = Files.init();
let storage = Files.FileStorage(state);
storage.upload([1, 2]);
storage.upload([3, 4]);
switch (storage.uploadFinalize("card.snk", "Héloïse", "application/octet-stream")) {
    case (#err(_)) { assert false };
    case (#ok(message)) { assert (message == "Upload successful") };
};
assert (storage.getStoredFileCount() == 1);
assert (state.storedFiles.size() == 1);
assert (storage.hasFile("card.snk"));
assert (storage.listFiles() == [("card.snk", "Héloïse", "application/octet-stream")]);
switch (storage.getFileChunk("card.snk", 0)) {
    case null { assert false };
    case (?file) {
        assert (file.chunk == [1, 2, 3, 4]);
        assert (file.totalChunks == 1);
    };
};
assert (storage.getFileChunk("card.snk", 1) == null);
assert (storage.getFileStartWithSignature("missing.snk", "abc") == null);

// Invalid and empty uploads do not create catalog entries or leak a pending
// upload into the next file.
storage.upload([9]);
switch (storage.uploadFinalize("../bad.snk", "", "application/octet-stream")) {
    case (#ok(_)) { assert false };
    case (#err(message)) { assert (message == "Invalid file name") };
};
switch (storage.uploadFinalize("empty.snk", "", "application/octet-stream")) {
    case (#ok(_)) { assert false };
    case (#err(message)) { assert (message == "Cannot store an empty file") };
};
assert (storage.getStoredFileCount() == 1);

let streamState : Files.State = {
    var storedFiles = [
        (
            "two.bin",
            {
                title = "two.bin";
                artist = "test";
                contentType = "application/octet-stream";
                totalChunks = 2;
                data = [[10, 11], [12, 13]];
            },
        ),
    ];
};
let streamStorage = Files.FileStorage(streamState);
let nextToken = switch (streamStorage.getFileStartWithSignature("two.bin", "abc")) {
    case null { assert false; { filename = ""; index = 0; signature = "" } };
    case (?start) {
        assert (start.chunk == [10, 11]);
        switch (start.nextToken) {
            case null { assert false; { filename = ""; index = 0; signature = "" } };
            case (?token) token;
        };
    };
};
assert (
    streamStorage.processStreamingCallbackWithValidator(
        nextToken,
        func(signature : Text, filename : Text) : Bool {
            signature == "abc" and filename == "two.bin";
        },
    ) == ?{ body = [12, 13]; token = null }
);
assert (
    streamStorage.processStreamingCallbackWithValidator(
        nextToken,
        func(_ : Text, _ : Text) : Bool { false },
    ) == null
);
assert (streamStorage.deleteFile("two.bin"));
assert (not streamStorage.deleteFile("two.bin"));
assert (streamState.storedFiles.size() == 0);
