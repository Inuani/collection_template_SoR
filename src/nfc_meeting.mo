import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Result "mo:core/Result";
import Collection "collection";
import Scan "scan";

module {
    // Extract NFC parameters from URL
    public func extractNFCParams(url: Text) : {uid: Text; cmac: Text; ctr: Text} {
        let queries = Iter.toArray(Text.split(url, #char '?'));

        var uid = "";
        var cmac = "";
        var ctr = "";

        if (queries.size() >= 2) {
            let params = Iter.toArray(Text.split(queries[1], #char '&'));

            for (param in params.vals()) {
                let keyValue = Iter.toArray(Text.split(param, #char '='));
                if (keyValue.size() == 2) {
                    switch (keyValue[0]) {
                        case "uid" { uid := keyValue[1]; };
                        case "cmac" { cmac := keyValue[1]; };
                        case "ctr" { ctr := keyValue[1]; };
                        case _ {};
                    };
                };
            };
        };

        {uid = uid; cmac = cmac; ctr = ctr}
    };

    // Extract item ID from URL path - works with any pattern like /item/5, /xxx/5, /card/5, etc.
    public func extractItemIdFromUrl(url: Text) : ?Nat {
        // Split URL by '/' and look for any numeric ID after any path segment
        let parts = Iter.toArray(Text.split(url, #char '/'));

        var i = 0;
        let partsSize = parts.size();
        while (i < partsSize) {
            let part = parts[i];

            // Skip empty parts
            if (part != "") {
                // Check if next part exists and could be an ID
                if (i + 1 < partsSize) {
                    let potentialId = parts[i + 1];
                    // Remove query string if present
                    let idClean = Iter.toArray(Text.split(potentialId, #char '?'))[0];

                    // Try to parse as number
                    switch (Nat.fromText(idClean)) {
                        case (?id) {
                            // Found a valid numeric ID!
                            // Only return if the path segment before it is not a number
                            // This ensures we get the ID part, not just any number in the URL
                            switch (Nat.fromText(part)) {
                                case null {
                                    // Previous part is not a number, so this is likely the ID
                                    return ?id;
                                };
                                case (?_) {
                                    // Previous part is also a number, keep looking
                                };
                            };
                        };
                        case null {
                            // Not a number, keep looking
                        };
                    };
                };
            };
            i += 1;
        };

        null
    };

    // Check if there's an active meeting challenge in the URL
    public func extractMeetingChallenge(url: Text) : ?Text {
        let queries = Iter.toArray(Text.split(url, #char '?'));

        if (queries.size() >= 2) {
            let params = Iter.toArray(Text.split(queries[1], #char '&'));

            for (param in params.vals()) {
                let keyValue = Iter.toArray(Text.split(param, #char '='));
                if (keyValue.size() == 2 and keyValue[0] == "meeting_challenge") {
                    return ?keyValue[1];
                };
            };
        };

        null
    };

    // Generate meeting-aware redirect URL after successful NFC scan
    public func generateMeetingRedirectUrl(
        itemId: Nat,
        challenge: ?Text,
        _isNewMeeting: Bool
    ) : Text {
        switch (challenge) {
            case (?ch) {
                // Redirect to meeting session page
                "/meeting/session?challenge=" # ch # "&item=" # Nat.toText(itemId)
            };
            case null {
                // No meeting, just show item
                "/item/" # Nat.toText(itemId)
            };
        }
    };

    // Handle NFC scan for meeting system
    // Returns: #newMeeting(challenge), #joinMeeting(challenge), #error(msg), or #noMeeting
    public func handleNFCScanForMeeting(
        url: Text,
        itemId: Nat,
        collection: Collection.Collection
    ) : {
        #newMeeting: Text;        // Create new meeting, returns challenge
        #joinMeeting: Text;       // Join existing meeting, returns challenge
        #noMeeting;               // Valid scan but no meeting context
        #error: Text;             // Error message
    } {
        // Extract NFC parameters
        let nfcParams = extractNFCParams(url);

        // Check if there's an existing meeting challenge
        let existingChallenge = extractMeetingChallenge(url);

        switch (existingChallenge) {
            case (?challenge) {
                // Try to join existing meeting
                switch (collection.joinMeetingSession(challenge, itemId, nfcParams.uid, nfcParams.cmac)) {
                    case (#ok(_)) {
                        #joinMeeting(challenge)
                    };
                    case (#err(msg)) {
                        #error(msg)
                    };
                }
            };
            case null {
                // No existing meeting - check if this scan should create one
                // Create a new meeting if this is a valid NFC scan
                switch (collection.createMeetingSession(itemId, nfcParams.uid, nfcParams.cmac)) {
                    case (#ok(result)) {
                        #newMeeting(result.challenge)
                    };
                    case (#err(_msg)) {
                        // If creation fails, just show the item without meeting
                        #noMeeting
                    };
                }
            };
        }
    };

    // Generate HTML response for NFC scan result
    public func generateScanRedirectPage(
        redirectUrl: Text,
        message: Text,
        isError: Bool
    ) : Text {
        let bgColor = if (isError) { "#ef4444" } else { "#10b981" };
        let icon = if (isError) { "⚠️" } else { "✅" };

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>NFC Scan</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: " # bgColor # ";
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            text-align: center;
            padding: 2rem;
        }
        .message {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        h1 {
            font-size: 1.5rem;
            margin-bottom: 1rem;
        }
        p {
            font-size: 1rem;
            opacity: 0.9;
        }
    </style>
    <script>
        setTimeout(function() {
            window.location.href = '" # redirectUrl # "';
        }, 1500);
    </script>
</head>
<body>
    <div>
        <div class=\"message\">" # icon # "</div>
        <h1>" # message # "</h1>
        <p>Redirecting...</p>
    </div>
</body>
</html>"
    };

    // Helper to create meeting-aware NFC protection response
    public func createMeetingAwareResponse(
        url: Text,
        itemId: Nat,
        collection: Collection.Collection,
        routeCmacs: [Text],
        scanCount: Nat
    ) : ?{
        statusCode: Nat16;
        headers: [(Text, Text)];
        body: ?Blob;
    } {
        // First verify the NFC scan is valid
        let counter = Scan.scan(routeCmacs, url, scanCount);

        if (counter == 0) {
            // Invalid scan
            return null;
        };

        // Valid scan - now handle meeting logic
        let meetingResult = handleNFCScanForMeeting(url, itemId, collection);

        switch (meetingResult) {
            case (#newMeeting(challenge)) {
                let redirectUrl = generateMeetingRedirectUrl(itemId, ?challenge, true);
                let html = generateScanRedirectPage(
                    redirectUrl,
                    "Meeting Started!",
                    false
                );
                ?{
                    statusCode = 200;
                    headers = [
                        ("Content-Type", "text/html"),
                        ("Cache-Control", "no-cache, no-store, must-revalidate")
                    ];
                    body = ?Text.encodeUtf8(html);
                }
            };
            case (#joinMeeting(challenge)) {
                let redirectUrl = generateMeetingRedirectUrl(itemId, ?challenge, false);
                let html = generateScanRedirectPage(
                    redirectUrl,
                    "Joined Meeting!",
                    false
                );
                ?{
                    statusCode = 200;
                    headers = [
                        ("Content-Type", "text/html"),
                        ("Cache-Control", "no-cache, no-store, must-revalidate")
                    ];
                    body = ?Text.encodeUtf8(html);
                }
            };
            case (#noMeeting) {
                // Just show the item page
                let redirectUrl = "/item/" # Nat.toText(itemId);
                let html = generateScanRedirectPage(
                    redirectUrl,
                    "Valid Scan",
                    false
                );
                ?{
                    statusCode = 200;
                    headers = [
                        ("Content-Type", "text/html"),
                        ("Cache-Control", "no-cache, no-store, must-revalidate")
                    ];
                    body = ?Text.encodeUtf8(html);
                }
            };
            case (#error(msg)) {
                let redirectUrl = "/meeting/error?msg=" # msg;
                let html = generateScanRedirectPage(
                    redirectUrl,
                    "Error: " # msg,
                    true
                );
                ?{
                    statusCode = 200;
                    headers = [
                        ("Content-Type", "text/html"),
                        ("Cache-Control", "no-cache, no-store, must-revalidate")
                    ];
                    body = ?Text.encodeUtf8(html);
                }
            };
        }
    };


}
