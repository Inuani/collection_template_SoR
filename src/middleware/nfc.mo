import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Time "mo:core/Time";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import App "mo:liminal/App";
import HttpContext "mo:liminal/HttpContext";
import SessionMiddleware "mo:liminal/Middleware/Session";
import ProtectedRoutes "../nfc_protec_routes";
import Scan "../scan";
import InvalidScan "../utils/invalid_scan";
import Theme "../utils/theme";

module NFCMiddleware {

    // ========================================
    // NFC Utility Functions
    // ========================================

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

    // ========================================
    // NFC Protection Middleware
    // ========================================

    public func createNFCProtectionMiddleware(
        protected_routes_storage: ProtectedRoutes.RoutesStorage,
        themeManager: Theme.ThemeManager
    ) : App.Middleware {
        {
            name = "NFC Protection with Session-Based Meetings";
            handleQuery = func(context : HttpContext.HttpContext, next : App.Next) : App.QueryResult {
                if (protected_routes_storage.isProtectedRoute(context.request.url)) {
                    return #upgrade; // Force verification in update call
                };
                next();
            };
            handleUpdate = func(context : HttpContext.HttpContext, next : App.NextAsync) : async* App.HttpResponse {
                let url = context.request.url;
                if (protected_routes_storage.isProtectedRoute(url))
                {
                    let routes_array = protected_routes_storage.listProtectedRoutes();
                    for ((path, protection) in routes_array.vals())
                    {
                        if (Text.contains(url, #text path))
                        {
                            // Extract item ID from URL if this is an item route
                            let itemIdOpt = extractItemIdFromUrl(url);

                            switch (itemIdOpt) {
                                case (?itemId) {
                                    // This is an item route - verify NFC first
                                    let routeCmacs = protected_routes_storage.getRouteCmacs(path);
                                    let scanCount = protection.scan_count_;

                                    // Verify NFC signature
                                    let counter = Scan.scan(routeCmacs, url, scanCount);
                                    if (counter == 0) {
                                        // Invalid NFC scan
                                        return {
                                            statusCode = 403;
                                            headers = [("Content-Type", "text/html")];
                                            body = ?Text.encodeUtf8(InvalidScan.generateInvalidScanPage(themeManager));
                                            streamingStrategy = null;
                                        };
                                    };

                                    // Update scan count
                                    ignore protected_routes_storage.verifyRouteAccess(path, url);

                                    // Get session from context (unwrap optional)
                                    switch (context.session) {
                                        case null {
                                            // No session available - shouldn't happen with session middleware
                                            return {
                                                statusCode = 500;
                                                headers = [("Content-Type", "text/html")];
                                                body = ?Text.encodeUtf8("<html><body><h1>Session Error</h1><p>Session not available.</p></body></html>");
                                                streamingStrategy = null;
                                            };
                                        };
                                        case (?session) {
                                            // Check if session has active meeting
                                            let itemsInSession = switch (session.get("meeting_items")) {
                                                case null { [] }; // No meeting yet
                                                case (?itemsText) {
                                                    // Parse existing items
                                                    let parts = Iter.toArray(Text.split(itemsText, #char ','));
                                                    var items : [Nat] = [];
                                                    for (part in parts.vals()) {
                                                        switch (Nat.fromText(part)) {
                                                            case (?n) { items := Array.concat(items, [n]); };
                                                            case null {};
                                                        };
                                                    };
                                                    items
                                                };
                                            };

                                            // Check if item already in session
                                            let alreadyScanned = Array.find<Nat>(itemsInSession, func(id) = id == itemId);

                                            switch (alreadyScanned) {
                                                case (?_) {
                                                    // Already scanned - show error
                                                    let html = "<html><body><h1>Already Scanned</h1><p>This item is already in the meeting.</p></body></html>";
                                                    return {
                                                        statusCode = 200;
                                                        headers = [("Content-Type", "text/html")];
                                                        body = ?Text.encodeUtf8(html);
                                                        streamingStrategy = null;
                                                    };
                                                };
                                                case null {
                                                    // Add to session
                                                    let updatedItems = Array.concat(itemsInSession, [itemId]);
                                                    var itemsText = "";
                                                    var first = true;
                                                    for (id in updatedItems.vals()) {
                                                        if (not first) { itemsText #= "," };
                                                        itemsText #= Nat.toText(id);
                                                        first := false;
                                                    };
                                                    session.set("meeting_items", itemsText);

                                                    // Store/update meeting timestamp - reset timer on each new scan
                                                    session.set("meeting_start_time", Int.toText(Time.now()));

                                                    // Generate cryptographically secure finalization token
                                                    let finalizeToken = await* SessionMiddleware.generateRandomId();
                                                    session.set("finalize_token", finalizeToken);

                                                    // Redirect to meeting page
                                                    let redirectUrl = if (updatedItems.size() == 1) {
                                                        "/meeting/waiting?item=" # Nat.toText(itemId)
                                                    } else {
                                                        "/meeting/active?items=" # itemsText
                                                    };

                                                    let html = "<!DOCTYPE html><html><head><meta http-equiv='refresh' content='0;url=" # redirectUrl # "'></head><body> Scanned! Redirecting...</body></html>";

                                                    return {
                                                        statusCode = 200;
                                                        headers = [("Content-Type", "text/html")];
                                                        body = ?Text.encodeUtf8(html);
                                                        streamingStrategy = null;
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                                case null {
                                    // Not an item route - use standard verification
                                    if (not protected_routes_storage.verifyRouteAccess(path, url))
                                    {
                                        return
                                        {
                                            statusCode = 403;
                                            headers = [("Content-Type", "text/html")];
                                            body = ?Text.encodeUtf8(InvalidScan.generateInvalidScanPage(themeManager));
                                            streamingStrategy = null;
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
                await* next();
            };
        };
    };
}
