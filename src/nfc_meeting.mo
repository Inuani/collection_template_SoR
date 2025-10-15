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

    // Extract item ID from URL path - only works with pattern /stitch/#
    public func extractItemIdFromUrl(url: Text) : ?Nat {
        // Split URL by '/' and look for "stitch" followed by a numeric ID
        let parts = Iter.toArray(Text.split(url, #char '/'));

        var i = 0;
        let partsSize = parts.size();
        while (i < partsSize) {
            let part = parts[i];

            // Check if this part is "stitch"
            if (part == "stitch") {
                // Check if next part exists and could be an ID
                if (i + 1 < partsSize) {
                    let potentialId = parts[i + 1];
                    // Remove query string if present
                    let idClean = Iter.toArray(Text.split(potentialId, #char '?'))[0];

                    // Try to parse as number
                    switch (Nat.fromText(idClean)) {
                        case (?id) {
                            // Found a valid numeric ID after "stitch"
                            return ?id;
                        };
                        case null {
                            // Not a number after "stitch"
                            return null;
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
        let accentColor = if (isError) { "#ef4444" } else { "#10b981" };
        let icon = if (isError) { "⚠️" } else { "✅" };

        "<!DOCTYPE html>
<html lang=\"fr\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Scan NFC</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #ffffff;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #1f2937;
            text-align: center;
            padding: 2rem;
        }
        .container {
            max-width: 400px;
            width: 100%;
        }
        .message {
            font-size: 5rem;
            margin-bottom: 2rem;
            animation: fadeIn 0.5s ease-in;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: scale(0.8); }
            to { opacity: 1; transform: scale(1); }
        }
        h1 {
            font-size: 1.5rem;
            margin-bottom: 3rem;
            font-weight: 600;
            color: #374151;
        }
        .spinner {
            width: 60px;
            height: 60px;
            margin: 0 auto 2rem;
            border: 5px solid #f3f4f6;
            border-top-color: " # accentColor # ";
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        .status {
            font-size: 0.875rem;
            color: #9ca3af;
            font-weight: 500;
        }
    </style>
    <script>
        setTimeout(function() {
            window.location.href = '" # redirectUrl # "';
        }, 1500);
    </script>
</head>
<body>
    <div class=\"container\">
        <div class=\"message\">" # icon # "</div>
        <h1>" # message # "</h1>
        <div class=\"spinner\"></div>
        <p class=\"status\">•••</p>
    </div>
</body>
</html>"
    };




}
