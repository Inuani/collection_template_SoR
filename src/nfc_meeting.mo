import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Result "mo:core/Result";
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




}
