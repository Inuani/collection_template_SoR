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
import Collection "collection";
import Time "mo:core/Time";
import Sha "utils/sha";
import Int "mo:core/Int";
import Blob "mo:core/Blob";

module {

    public type ChunkId = Nat;
    public type FileChunk = [Nat8];

    public type StreamingCallbackToken = {
        filename : Text;
        index : Nat;
        signature : Text; // Token/Signature for validation
    };

    public type StreamingCallbackHttpResponse = {
        body : [Nat8];
        token : ?StreamingCallbackToken;
    };

    // Helper to serialize token to Blob (for HttpAssets compatibility)
    // In a real app, use a proper serializer like candid or similar
    // For now, we'll just keep the types distinct and let the router handle conversion if needed
    // or use a simple text-based encoding if required by the interface.
    // simpler: The interface in main.mo should use the specific type if Liminal allows,
    // otherwise we need to encode. Liminal's StreamingStrategy uses `token : Any`.
    // The previous error showed `token : Blob`.
    // So we need to convert our Token to Blob.

    public func tokenToBlob(t : StreamingCallbackToken) : [Nat8] {
        let text = t.filename # "|" # Nat.toText(t.index) # "|" # t.signature;
        Blob.toArray(Text.encodeUtf8(text));
    };

    public func tokenFromBlob(b : [Nat8]) : ?StreamingCallbackToken {
        let text = switch (Text.decodeUtf8(Blob.fromArray(b))) {
            case null return null;
            case (?t) t;
        };
        let parts = Iter.toArray(Text.split(text, #char '|'));
        if (parts.size() != 3) return null;

        let index = switch (Nat.fromText(parts[1])) {
            case null return null;
            case (?n) n;
        };

        ?{
            filename = parts[0];
            index = index;
            signature = parts[2];
        };
    };

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

        // Logic for handling the streaming callback
        public func processStreamingCallback(token : StreamingCallbackToken) : ?StreamingCallbackHttpResponse {
            // 1. Validate signature
            if (not validateToken(token.signature, token.filename)) {
                return null;
            };

            // 2. Fetch chunk
            switch (Map.get(storedFiles, Text.compare, token.filename)) {
                case (null) return null;
                case (?file) {
                    if (token.index >= file.data.size()) return null;

                    let chunk = file.data[token.index];
                    let nextIndex = token.index + 1;

                    let nextToken : ?StreamingCallbackToken = if (nextIndex < file.data.size()) {
                        ?{
                            filename = token.filename;
                            index = nextIndex;
                            signature = token.signature; // Reuse signature (valid for duration)
                        };
                    } else {
                        null;
                    };

                    ?{
                        body = chunk;
                        token = nextToken;
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

        // Get the first chunk and next token for streaming
        public func getFileStart(title : Text) : ?{
            chunk : [Nat8];
            totalChunks : Nat;
            contentType : Text;
            title : Text;
            artist : Text;
            nextToken : ?StreamingCallbackToken;
        } {
            switch (Map.get(storedFiles, Text.compare, title)) {
                case (null) { null };
                case (?file) {
                    if (file.data.size() == 0) return null;

                    let chunk = file.data[0];
                    let signature = generateToken(title); // Generate fresh token for the stream

                    let nextToken : ?StreamingCallbackToken = if (file.data.size() > 1) {
                        ?{
                            filename = title;
                            index = 1;
                            signature = signature;
                        };
                    } else {
                        null;
                    };

                    ?{
                        chunk = chunk;
                        totalChunks = file.totalChunks;
                        contentType = file.contentType;
                        title = file.title;
                        artist = file.artist;
                        nextToken = nextToken;
                    };
                };
            };
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

                let n = (Nat32.fromNat(Nat8.toNat(b1)) << 16) | (Nat32.fromNat(Nat8.toNat(b2)) << 8) | Nat32.fromNat(Nat8.toNat(b3));

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

        // Stateless Token Generation (Timestamp + Signature)
        // -------------------------------------------------------------------------
        private let secret = "LUANDI_SECRET_KEY_QM9"; // Rotate this in production!
        private let tokenDuration = 60_000_000_000; // 1 minute in nanoseconds

        public func generateHTMLWrapper(filename : Text, token : Text, themeManager : Theme.ThemeManager) : Text {
            let theme = themeManager.getTheme();
            "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Now Playing: " # filename # "</title>
    <style>
        body {
            background-color: " # theme.colors.background # ";
            color: " # theme.colors.text # ";
            font-family: " # theme.typography.fontFamily # ", sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
        }
        .container {
            text-align: center;
            padding: 2rem;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 16px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
            box-shadow: 0 4px 30px rgba(0, 0, 0, 0.1);
            max-width: 90%;
            width: 400px;
        }
        h2 {
            margin-bottom: 1.5rem;
            font-weight: 600;
        }
        audio {
            width: 100%;
            margin-bottom: 1.5rem;
            border-radius: 8px;
        }
        .timer-container {
            font-size: 0.9rem;
            opacity: 0.8;
            margin-top: 1rem;
        }
        #timer {
            font-weight: bold;
            color: " # theme.colors.primary # ";
        }
        .status {
            margin-top: 0.5rem;
            font-size: 0.8rem;
            color: #888;
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <h2>" # filename # "</h2>
        <audio controls autoplay>
            <source src=\"/api/stream/" # filename # "?token=" # token # "\" type=\"audio/mp4\">
            Your browser does not support the audio element.
        </audio>
        <div class=\"timer-container\">
            Access expires in: <span id=\"timer\">60</span>s
        </div>
        <div class=\"status\">Secure Stream Active</div>
    </div>

    <script>
        // Simple countdown timer
        let timeLeft = 60;
        const timerElement = document.getElementById('timer');

        const countdown = setInterval(() => {
            timeLeft--;
            timerElement.textContent = timeLeft;

            if (timeLeft <= 0) {
                clearInterval(countdown);
                timerElement.textContent = \"Expired\";
                document.querySelector('.status').textContent = \"Session Expired. Please scan again.\";
                document.querySelector('.status').style.color = \"red\";
            }
        }, 1000);
    </script>
</body>
</html>";
        };

        public func generateToken(filename : Text) : Text {
            let now = Time.now();
            let timestamp = Int.toText(now);

            // Generate signature: Hash(filename + timestamp + secret)
            let input = filename # timestamp # secret;
            let sha = Sha.sha256(
                Array.map(
                    Text.toArray(input),
                    func(c : Char) : Nat8 {
                        Nat8.fromNat(Nat32.toNat(Char.toNat32(c)));
                    },
                )
            );

            let signatureBase64 = bytesToBase64(sha);
            let signatureSafe = Text.replace(
                Text.replace(
                    Text.replace(signatureBase64, #text "+", "-"),
                    #text "/",
                    "_",
                ),
                #text "=",
                "",
            );

            timestamp # "." # signatureSafe;
        };

        public func validateToken(signature : Text, expectedFilename : Text) : Bool {
            let parts = Iter.toArray(Text.split(signature, #char '.'));
            if (parts.size() != 2) return false;

            let timestampText = parts[0];
            let providedSignature = parts[1];

            // 1. Check expiration
            switch (Int.fromText(timestampText)) {
                case (null) return false;
                case (?timestamp) {
                    let now = Time.now();
                    // Check if token is too old OR from the future (allow 1 minute skew)
                    if (now > timestamp + tokenDuration or timestamp > now + 60_000_000_000) {
                        return false;
                    };
                };
            };

            // 2. Verify signature
            // Reconstruct input using the EXPECTED filename
            let input = expectedFilename # timestampText # secret;
            let sha = Sha.sha256(
                Array.map(
                    Text.toArray(input),
                    func(c : Char) : Nat8 {
                        Nat8.fromNat(Nat32.toNat(Char.toNat32(c)));
                    },
                )
            );

            let expectedSignatureBase64 = bytesToBase64(sha);
            let expectedSignatureSafe = Text.replace(
                Text.replace(
                    Text.replace(expectedSignatureBase64, #text "+", "-"),
                    #text "/",
                    "_",
                ),
                #text "=",
                "",
            );

            providedSignature == expectedSignatureSafe;
        };

        private func charAt(str : Text, index : Nat) : Char {
            var i = 0;
            for (c in str.chars()) {
                if (i == index) return c;
                i += 1;
            };
            ' '; // Should never reach here with valid input
        };

        // Generate HTML page for file display
        public func generateFilePage(
            filename : Text,
            fileInfo : {
                chunk : [Nat8];
                totalChunks : Nat;
                contentType : Text;
                title : Text;
                artist : Text;
            },
            collection : Collection.Collection,
        ) : Text {
            // Extract item number from filename (e.g., certificat_0 -> 0)
            let itemNumberText = Text.replace(filename, #text("certificat_"), "");

            // Get item name from collection
            let itemDisplay = switch (Nat.fromText(itemNumberText)) {
                case (?itemId) {
                    switch (collection.getItem(itemId)) {
                        case (?item) item.name;
                        case null itemNumberText;
                    };
                };
                case null itemNumberText;
            };

            // Generate HTML based on file size (single chunk vs multi-chunk)
            if (fileInfo.totalChunks == 1) {
                generateSingleChunkPage(filename, itemNumberText, itemDisplay, fileInfo);
            } else {
                generateMultiChunkPage(filename, itemNumberText, itemDisplay, fileInfo);
            };
        };

        // Generate page for single chunk files (< 2MB)
        private func generateSingleChunkPage(
            filename : Text,
            itemNumberText : Text,
            itemDisplay : Text,
            fileInfo : {
                chunk : [Nat8];
                totalChunks : Nat;
                contentType : Text;
                title : Text;
                artist : Text;
            },
        ) : Text {
            "<!DOCTYPE html><html><head>"
            # "<meta charset='UTF-8'>"
            # "<meta name='viewport' content='width=device-width,initial-scale=1.0'>"
            # "<title>" # filename # "</title>"
            # "<style>"
            # "*{margin:0;padding:0;box-sizing:border-box;}"
            # "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#fff;min-height:100vh;display:flex;flex-direction:column;}"
            # ".container{flex:1;display:flex;flex-direction:column;width:100%;max-width:100vw;padding:20px;}"
            # ".back-link{display:inline-block;margin-bottom:1rem;color:#2563eb;text-decoration:none;font-weight:500;}"
            # ".back-link:hover{text-decoration:underline;}"
            # ".certificate-text{text-align:center;margin-bottom:1rem;font-size:16px;color:#1f2937;}"
            # ".media-container{flex:1;display:flex;justify-content:center;align-items:center;background:#fff;}"
            # "#media{width:100%;height:100%;display:flex;justify-content:center;align-items:center;}"
            # "img{max-width:100%;max-height:calc(100vh - 120px);width:auto;height:auto;object-fit:contain;display:block;}"
            # "audio,video{max-width:100%;}"
            # "</style>"
            # "</head><body>"
            # "<div class='container'>"
            # "<a href='/item/" # itemNumberText # "' class='back-link'>Retour à " # itemDisplay # "</a>"
            # "<div class='certificate-text'>Scan valide - certificat d'authenticité pour l'item " # itemDisplay # " :</div>"
            # "<div class='media-container'><div id='media'></div></div>"
            # "</div>"
            # "<script>"
            # "const filename='" # filename # "';"
            # "const contentType='" # fileInfo.contentType # "';"
            # "const baseUrl=window.location.protocol+'//'+window.location.host;"
            # "async function load(){"
            # "const media=document.getElementById('media');"
            # "try{"
            # "const url=baseUrl+'/files/'+filename+'/chunk/0';"
            # "const response=await fetch(url);"
            # "if(!response.ok)throw new Error('Failed to load: HTTP '+response.status);"
            # "const arrayBuffer=await response.arrayBuffer();"
            # "const bytes=new Uint8Array(arrayBuffer);"
            # "const blob=new Blob([bytes],{type:contentType});"
            # "const blobUrl=URL.createObjectURL(blob);"
            # "let element;"
            # "if(contentType.startsWith('image/')){element=document.createElement('img');}"
            # "else if(contentType.startsWith('audio/')){element=document.createElement('audio');element.controls=true;}"
            # "else if(contentType.startsWith('video/')){element=document.createElement('video');element.controls=true;}"
            # "else{element=document.createElement('img');}"
            # "element.src=blobUrl;"
            # "media.appendChild(element);"
            # "}catch(e){console.error(e);}"
            # "}"
            # "load();"
            # "</script>"
            # "</body></html>";
        };

        // Generate page for multi-chunk files (> 2MB)
        private func generateMultiChunkPage(
            filename : Text,
            itemNumberText : Text,
            itemDisplay : Text,
            fileInfo : {
                chunk : [Nat8];
                totalChunks : Nat;
                contentType : Text;
                title : Text;
                artist : Text;
            },
        ) : Text {
            "<!DOCTYPE html><html><head>"
            # "<meta charset='UTF-8'>"
            # "<meta name='viewport' content='width=device-width,initial-scale=1.0'>"
            # "<title>" # filename # "</title>"
            # "<style>"
            # "*{margin:0;padding:0;box-sizing:border-box;}"
            # "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#fff;min-height:100vh;display:flex;flex-direction:column;}"
            # ".container{flex:1;display:flex;flex-direction:column;width:100%;max-width:100vw;padding:20px;}"
            # ".back-link{display:inline-block;margin-bottom:1rem;color:#2563eb;text-decoration:none;font-weight:500;}"
            # ".back-link:hover{text-decoration:underline;}"
            # ".certificate-text{text-align:center;margin-bottom:1rem;font-size:16px;color:#1f2937;}"
            # ".media-container{flex:1;display:flex;justify-content:center;align-items:center;background:#fff;}"
            # "#media{width:100%;height:100%;display:flex;justify-content:center;align-items:center;}"
            # "img{max-width:100%;max-height:calc(100vh - 120px);width:auto;height:auto;object-fit:contain;display:block;}"
            # "audio,video{max-width:100%;}"
            # "</style>"
            # "</head><body>"
            # "<div class='container'>"
            # "<a href='/item/" # itemNumberText # "' class='back-link'>Retour à " # itemDisplay # "</a>"
            # "<div class='certificate-text'>Scan valide - certificat d'authenticité pour l'item " # itemDisplay # " :</div>"
            # "<div class='media-container'><div id='media'></div></div>"
            # "</div>"
            # "<script>"
            # "const filename='" # filename # "';"
            # "const totalChunks=" # Nat.toText(fileInfo.totalChunks) # ";"
            # "const contentType='" # fileInfo.contentType # "';"
            # "const baseUrl=window.location.protocol+'//'+window.location.host;"
            # "async function load(){"
            # "const media=document.getElementById('media');"
            # "try{"
            # "const chunks=[];"
            # "for(let i=0;i<totalChunks;i++){"
            # "const url=baseUrl+'/files/'+filename+'/chunk/'+i;"
            # "const response=await fetch(url);"
            # "if(!response.ok)throw new Error('Chunk '+i+' failed: HTTP '+response.status);"
            # "const arrayBuffer=await response.arrayBuffer();"
            # "const bytes=new Uint8Array(arrayBuffer);"
            # "chunks.push(bytes);"
            # "}"
            # "const totalBytes=chunks.reduce((acc,chunk)=>acc+chunk.length,0);"
            # "const combined=new Uint8Array(totalBytes);"
            # "let offset=0;"
            # "for(const chunk of chunks){combined.set(chunk,offset);offset+=chunk.length;}"
            # "const blob=new Blob([combined],{type:contentType});"
            # "const blobUrl=URL.createObjectURL(blob);"
            # "let element;"
            # "if(contentType.startsWith('image/')){element=document.createElement('img');}"
            # "else if(contentType.startsWith('audio/')){element=document.createElement('audio');element.controls=true;}"
            # "else if(contentType.startsWith('video/')){element=document.createElement('video');element.controls=true;}"
            # "else{element=document.createElement('img');}"
            # "element.src=blobUrl;"
            # "media.appendChild(element);"
            # "}catch(e){console.error(e);}"
            # "}"
            # "load();"
            # "</script>"
            # "</body></html>";
        };
    };
};
