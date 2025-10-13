import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Array "mo:core/Array";
import Collection "collection";
import Theme "theme";

module {

    // Generate error page for meeting issues
    public func generateMeetingErrorPage(
        errorMessage: Text,
        themeManager: Theme.ThemeManager
    ) : Text {
        let primary = themeManager.getPrimary();

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Meeting Error</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
            min-height: 100vh;
            color: white;
            padding: 2rem;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            max-width: 500px;
            width: 100%;
        }
        .error-card {
            background: white;
            border-radius: 20px;
            padding: 3rem 2rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.3);
            color: #333;
            text-align: center;
        }
        .icon {
            font-size: 4rem;
            margin-bottom: 1rem;
        }
        h1 {
            font-size: 2rem;
            color: #dc2626;
            margin-bottom: 1rem;
        }
        .error-message {
            background: #fee2e2;
            color: #991b1b;
            padding: 1.5rem;
            border-radius: 10px;
            border-left: 4px solid #dc2626;
            margin: 2rem 0;
            text-align: left;
        }
        .btn {
            padding: 1rem 2rem;
            border: none;
            border-radius: 10px;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            background: " # primary # ";
            color: white;
            text-decoration: none;
            display: inline-block;
            margin-top: 1rem;
        }
        .btn:hover {
            opacity: 0.9;
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"error-card\">
            <div class=\"icon\">⚠️</div>
            <h1>Meeting Error</h1>

            <div class=\"error-message\">
                " # errorMessage # "
            </div>

            <a href=\"/collection\" class=\"btn\">Back to Collection</a>
        </div>
    </div>
</body>
</html>"
    };

    // Helper: Generate list of scanned items
    private func generateScannedItemsList(scannedItemIds: [Nat], allItems: [Collection.Item]) : Text {
        var html = "";

        for (itemId in scannedItemIds.vals()) {
            // Find the item
            let itemOpt = Array.find<Collection.Item>(allItems, func(item) { item.id == itemId });

            switch (itemOpt) {
                case (?item) {
                    let isCurrent = itemId == scannedItemIds[0];
                    html #= "<li class=\"item-entry" # (if (isCurrent) { " current" } else { "" }) # "\">
                        <img src=\"" # item.thumbnailUrl # "\" alt=\"" # item.name # "\" class=\"item-icon\">
                        <div class=\"item-info\">
                            <div class=\"item-name\">" # item.name # (if (isCurrent) { " (You)" } else { "" }) # "</div>
                            <div class=\"item-id\">Item #" # Nat.toText(item.id) # "</div>
                        </div>
                    </li>";
                };
                case null {
                    html #= "<li class=\"item-entry\">
                        <div class=\"item-info\">
                            <div class=\"item-name\">Item #" # Nat.toText(itemId) # "</div>
                            <div class=\"item-id\">Details unavailable</div>
                        </div>
                    </li>";
                };
            };
        };

        html
    };

    // Helper: Generate list of rewarded items
    private func generateRewardedItemsList(itemIds: [Nat], allItems: [Collection.Item]) : Text {
        var html = "";

        for (itemId in itemIds.vals()) {
            let itemOpt = Array.find<Collection.Item>(allItems, func(item) { item.id == itemId });

            switch (itemOpt) {
                case (?item) {
                    html #= "<div class=\"item-entry\">
                        <img src=\"" # item.thumbnailUrl # "\" alt=\"" # item.name # "\" class=\"item-icon\">
                        <div class=\"item-info\">
                            <div class=\"item-name\">" # item.name # "</div>
                            <div class=\"item-tokens\">+10 tokens</div>
                        </div>
                    </div>";
                };
                case null {
                    html #= "<div class=\"item-entry\">
                        <div class=\"item-info\">
                            <div class=\"item-name\">Item #" # Nat.toText(itemId) # "</div>
                            <div class=\"item-tokens\">+10 tokens</div>
                        </div>
                    </div>";
                };
            };
        };

        html
    };

    // NEW: Generate waiting page for first scan (session-based)
    public func generateWaitingPage(
        itemId: Nat,
        item: Collection.Item,
        itemsInSession: [Nat],
        themeManager: Theme.ThemeManager
    ) : Text {
        let primary = themeManager.getPrimary();

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Meeting Started - Waiting</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
            padding: 2rem;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container { max-width: 600px; width: 100%; }
        .card {
            background: white;
            border-radius: 20px;
            padding: 2rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.3);
            color: #333;
            text-align: center;
        }
        .icon { font-size: 4rem; margin-bottom: 1rem; }
        h1 { font-size: 2rem; color: " # primary # "; margin-bottom: 1rem; }
        .item-name { font-size: 1.3rem; color: #718096; margin-bottom: 2rem; }
        .pulse {
            width: 100px;
            height: 100px;
            margin: 2rem auto;
            background: " # primary # ";
            border-radius: 50%;
            animation: pulse 2s ease-in-out infinite;
        }
        @keyframes pulse {
            0%, 100% { transform: scale(1); opacity: 0.7; }
            50% { transform: scale(1.2); opacity: 1; }
        }
        .instructions {
            background: #f7fafc;
            padding: 1.5rem;
            border-radius: 10px;
            margin: 2rem 0;
            text-align: left;
        }
        .instructions h3 { color: #2d3748; margin-bottom: 0.5rem; }
        .instructions p { color: #718096; line-height: 1.6; }
        .btn {
            display: inline-block;
            padding: 1rem 2rem;
            background: #e2e8f0;
            color: #4a5568;
            border-radius: 10px;
            text-decoration: none;
            font-weight: 600;
            margin-top: 1rem;
        }
        .btn:hover { background: #cbd5e0; }
    </style>
    <script>
        setInterval(() => {
            fetch('/meeting/active?items=" # Nat.toText(itemId) # "')
                .then(r => r.text())
                .then(html => {
                    if (html.includes('Meeting Active')) {
                        window.location.reload();
                    }
                })
                .catch(e => console.log('Polling...'));
        }, 2000);
    </script>
</head>
<body>
    <div class=\"container\">
        <div class=\"card\">
            <div class=\"icon\">✅</div>
            <h1>Meeting Started!</h1>
            <div class=\"item-name\">" # item.name # "</div>

            <div class=\"pulse\"></div>

            <div class=\"instructions\">
                <h3>📱 Waiting for more items...</h3>
                <p>Have other participants scan their NFC tags now. They will automatically join this meeting session!</p>
                <p style=\"margin-top: 1rem;\"><strong>Items in session: " # Nat.toText(itemsInSession.size()) # "</strong></p>
                <p style=\"margin-top: 0.5rem; font-size: 0.9rem;\">Need at least 2 items to finalize the meeting.</p>
            </div>

            <a href=\"/collection\" class=\"btn\">Cancel</a>
        </div>
    </div>
</body>
</html>"
    };

    // NEW: Generate active session page with multiple items (session-based)
    public func generateActiveSessionPage(
        itemsInSession: [Nat],
        allItems: [Collection.Item],
        themeManager: Theme.ThemeManager
    ) : Text {
        let primary = themeManager.getPrimary();

        // Generate list of scanned items
        var itemsHtml = "";
        for (itemId in itemsInSession.vals()) {
            let itemOpt = Array.find<Collection.Item>(allItems, func(i) = i.id == itemId);
            switch (itemOpt) {
                case (?item) {
                    itemsHtml #= "<div class=\"item-entry\">
                        <div class=\"item-icon\" style=\"background: " # primary # "; color: white; display: flex; align-items: center; justify-content: center; font-weight: 700;\">" # Nat.toText(item.id) # "</div>
                        <div class=\"item-info\">
                            <div class=\"item-name\">" # item.name # "</div>
                            <div style=\"color: #718096; font-size: 0.9rem;\">Ready to receive 10 tokens</div>
                        </div>
                    </div>";
                };
                case null {};
            };
        };

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Meeting Active</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #10b981 0%, #059669 100%);
            min-height: 100vh;
            color: white;
            padding: 2rem;
        }
        .container { max-width: 600px; margin: 0 auto; }
        .card {
            background: white;
            border-radius: 20px;
            padding: 2rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.3);
            color: #333;
        }
        .header { text-align: center; margin-bottom: 2rem; }
        .header h1 { font-size: 2rem; color: " # primary # "; margin-bottom: 0.5rem; }
        .status-badge {
            display: inline-block;
            padding: 0.5rem 1rem;
            border-radius: 20px;
            background: linear-gradient(135deg, #10b981 0%, #059669 100%);
            color: white;
            font-weight: 600;
        }
        .items-section {
            background: #f7fafc;
            padding: 1.5rem;
            border-radius: 15px;
            margin: 2rem 0;
        }
        .items-section h2 { color: #2d3748; margin-bottom: 1rem; font-size: 1.2rem; }
        .item-entry {
            background: white;
            padding: 1rem;
            margin-bottom: 0.75rem;
            border-radius: 10px;
            border-left: 4px solid " # primary # ";
            display: flex;
            align-items: center;
            gap: 1rem;
        }
        .item-entry:last-child { margin-bottom: 0; }
        .item-icon {
            width: 50px;
            height: 50px;
            border-radius: 8px;
            font-size: 1.2rem;
        }
        .item-info { flex: 1; }
        .item-name { font-weight: 600; color: #2d3748; }
        .instructions {
            background: #d1fae5;
            border-left: 4px solid #10b981;
            padding: 1.5rem;
            border-radius: 10px;
            margin: 2rem 0;
        }
        .instructions h3 { color: #065f46; margin-bottom: 0.5rem; }
        .instructions p { color: #047857; line-height: 1.6; }
        .actions {
            display: flex;
            gap: 1rem;
            margin-top: 2rem;
        }
        .btn {
            flex: 1;
            padding: 1rem 2rem;
            border: none;
            border-radius: 10px;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            text-decoration: none;
            display: block;
            text-align: center;
            transition: all 0.3s ease;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
        }
        .btn-secondary {
            background: #e2e8f0;
            color: #4a5568;
        }
        .btn-secondary:hover { background: #cbd5e0; }
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"card\">
            <div class=\"header\">
                <h1>Meeting Active</h1>
                <span class=\"status-badge\">✅ Ready to Finalize</span>
            </div>

            <div class=\"items-section\">
                <h2>Participants (" # Nat.toText(itemsInSession.size()) # " items)</h2>
                " # itemsHtml # "
            </div>

            <div class=\"instructions\">
                <h3>🎉 Ready to Finalize!</h3>
                <p>You have enough participants! Click \"Finalize Meeting\" to distribute 10 tokens to each item.</p>
                <p style=\"margin-top: 0.5rem;\">Or scan more NFC tags to add more participants to this meeting.</p>
            </div>

            <div class=\"actions\">
                <a href=\"/collection\" class=\"btn btn-secondary\">Cancel</a>
                <a href=\"/meeting/finalize_session\" class=\"btn btn-primary\">Finalize Meeting</a>
            </div>
        </div>
    </div>
</body>
</html>"
    };

    // NEW: Generate success page (session-based, simpler)
    public func generateSessionSuccessPage(
        itemIds: [Nat],
        allItems: [Collection.Item],
        themeManager: Theme.ThemeManager
    ) : Text {
        let primary = themeManager.getPrimary();

        // Generate list of rewarded items
        var itemsHtml = "";
        for (itemId in itemIds.vals()) {
            let itemOpt = Array.find<Collection.Item>(allItems, func(i) = i.id == itemId);
            switch (itemOpt) {
                case (?item) {
                    itemsHtml #= "<div class=\"item-entry\">
                        <div class=\"item-icon\" style=\"background: " # primary # "; color: white; display: flex; align-items: center; justify-content: center; font-weight: 700;\">" # Nat.toText(item.id) # "</div>
                        <div class=\"item-info\">
                            <div class=\"item-name\">" # item.name # "</div>
                            <div class=\"item-tokens\">+10 Tokens</div>
                        </div>
                    </div>";
                };
                case null {};
            };
        };

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Meeting Success!</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #10b981 0%, #059669 100%);
            min-height: 100vh;
            color: white;
            padding: 2rem;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container { max-width: 600px; width: 100%; }
        .card {
            background: white;
            border-radius: 20px;
            padding: 3rem 2rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.3);
            color: #333;
            text-align: center;
        }
        .icon {
            font-size: 5rem;
            margin-bottom: 1rem;
            animation: celebrate 1s ease-in-out;
        }
        @keyframes celebrate {
            0%, 100% { transform: scale(1) rotate(0deg); }
            25% { transform: scale(1.2) rotate(-10deg); }
            50% { transform: scale(1.1) rotate(10deg); }
            75% { transform: scale(1.2) rotate(-10deg); }
        }
        h1 { font-size: 2.5rem; color: " # primary # "; margin-bottom: 0.5rem; }
        .subtitle { font-size: 1.2rem; color: #718096; margin-bottom: 2rem; }
        .reward-badge {
            display: inline-block;
            padding: 1rem 2rem;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 50px;
            font-size: 1.5rem;
            font-weight: 700;
            margin: 1rem 0 2rem 0;
        }
        .items-rewarded {
            background: #f7fafc;
            padding: 1.5rem;
            border-radius: 15px;
            margin: 2rem 0;
            text-align: left;
        }
        .items-rewarded h2 { color: #2d3748; margin-bottom: 1rem; font-size: 1.2rem; }
        .item-entry {
            background: white;
            padding: 1rem;
            margin-bottom: 0.75rem;
            border-radius: 10px;
            border-left: 4px solid " # primary # ";
            display: flex;
            align-items: center;
            gap: 1rem;
        }
        .item-entry:last-child { margin-bottom: 0; }
        .item-icon {
            width: 50px;
            height: 50px;
            border-radius: 8px;
        }
        .item-info { flex: 1; }
        .item-name { font-weight: 600; color: #2d3748; margin-bottom: 0.25rem; }
        .item-tokens { color: #10b981; font-weight: 700; }
        .actions {
            display: flex;
            gap: 1rem;
            margin-top: 2rem;
        }
        .btn {
            flex: 1;
            padding: 1rem 2rem;
            border: none;
            border-radius: 10px;
            font-size: 1rem;
            font-weight: 600;
            text-decoration: none;
            display: block;
            text-align: center;
            transition: all 0.3s ease;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
        }
        .btn-secondary {
            background: #e2e8f0;
            color: #4a5568;
        }
        .btn-secondary:hover { background: #cbd5e0; }
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"card\">
            <div class=\"icon\">🎉</div>
            <h1>Meeting Completed!</h1>
            <p class=\"subtitle\">Tokens distributed to all participants</p>

            <div class=\"reward-badge\">+10 Tokens Each</div>

            <div class=\"items-rewarded\">
                <h2>Participants (" # Nat.toText(itemIds.size()) # " items)</h2>
                " # itemsHtml # "
            </div>

            <div class=\"actions\">
                <a href=\"/collection\" class=\"btn btn-secondary\">View Collection</a>
                <a href=\"/\" class=\"btn btn-primary\">Home</a>
            </div>
        </div>
    </div>
</body>
</html>"
    };
}
