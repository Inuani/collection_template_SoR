import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Array "mo:core/Array";
import Collection "collection";
import Theme "theme";

module {
    // Generate the meeting session page
    public func generateMeetingPage(
        _itemId: Nat,
        item: Collection.Item,
        challenge: Text,
        scannedItems: [Nat],
        expiresIn: Int,
        allItems: [Collection.Item],
        themeManager: Theme.ThemeManager
    ) : Text {
        let primary = themeManager.getPrimary();
        let secondary = themeManager.getSecondary();

        // Calculate time remaining in seconds
        let secondsRemaining = expiresIn / 1_000_000_000;

        // Generate list of scanned items
        let scannedItemsHtml = generateScannedItemsList(scannedItems, allItems);

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Meeting Session - " # item.name # "</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
            padding: 2rem;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
        }
        .meeting-card {
            background: white;
            border-radius: 20px;
            padding: 2rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.3);
            color: #333;
            margin-bottom: 1rem;
        }
        .header {
            text-align: center;
            margin-bottom: 2rem;
        }
        .header h1 {
            font-size: 2rem;
            color: " # primary # ";
            margin-bottom: 0.5rem;
        }
        .status-badge {
            display: inline-block;
            padding: 0.5rem 1rem;
            border-radius: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-weight: 600;
        }
        .timer {
            text-align: center;
            margin: 2rem 0;
            padding: 1.5rem;
            background: #f7fafc;
            border-radius: 15px;
        }
        .timer-value {
            font-size: 3rem;
            font-weight: 700;
            color: " # primary # ";
            margin-bottom: 0.5rem;
        }
        .timer-label {
            color: #718096;
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .scanned-items {
            margin: 2rem 0;
        }
        .scanned-items h2 {
            font-size: 1.3rem;
            color: #2d3748;
            margin-bottom: 1rem;
        }
        .item-list {
            list-style: none;
        }
        .item-entry {
            background: #f7fafc;
            padding: 1rem;
            margin-bottom: 0.75rem;
            border-radius: 10px;
            border-left: 4px solid " # secondary # ";
            display: flex;
            align-items: center;
            gap: 1rem;
        }
        .item-entry.current {
            border-left-color: " # primary # ";
            background: linear-gradient(90deg, rgba(102, 126, 234, 0.1) 0%, transparent 100%);
        }
        .item-icon {
            width: 50px;
            height: 50px;
            border-radius: 8px;
            object-fit: cover;
        }
        .item-info {
            flex: 1;
        }
        .item-name {
            font-weight: 600;
            color: #2d3748;
            margin-bottom: 0.25rem;
        }
        .item-id {
            color: #718096;
            font-size: 0.85rem;
        }
        .instructions {
            background: #fff5e1;
            padding: 1.5rem;
            border-radius: 10px;
            border-left: 4px solid #f59e0b;
            margin: 2rem 0;
        }
        .instructions h3 {
            color: #92400e;
            margin-bottom: 0.5rem;
            font-size: 1.1rem;
        }
        .instructions p {
            color: #78350f;
            line-height: 1.6;
        }
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
            transition: all 0.3s ease;
            text-align: center;
            text-decoration: none;
            display: block;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .btn-primary:hover:not(:disabled) {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
        }
        .btn-primary:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .btn-secondary {
            background: #e2e8f0;
            color: #4a5568;
        }
        .btn-secondary:hover {
            background: #cbd5e0;
        }
        .challenge-info {
            background: #f7fafc;
            padding: 1rem;
            border-radius: 8px;
            margin-top: 2rem;
            font-size: 0.85rem;
            color: #718096;
            word-break: break-all;
        }
        .warning {
            color: #e53e3e;
            font-weight: 600;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .success-message {
            background: #c6f6d5;
            color: #22543d;
            padding: 1rem;
            border-radius: 8px;
            border-left: 4px solid #38a169;
            margin-bottom: 1rem;
            display: none;
        }
        .qr-section {
            background: #e0e7ff;
            padding: 1.5rem;
            border-radius: 10px;
            border-left: 4px solid #6366f1;
            margin: 2rem 0;
            text-align: center;
        }
        .qr-section h3 {
            color: #3730a3;
            margin-bottom: 0.5rem;
            font-size: 1.1rem;
        }
        .qr-section p {
            color: #4338ca;
            line-height: 1.6;
            margin-bottom: 1rem;
        }
        .qr-info {
            background: white;
            padding: 1rem;
            border-radius: 8px;
            color: #1e1b4b;
            font-size: 0.9rem;
        }
    </style>
    <script>
        let secondsLeft = " # Int.toText(secondsRemaining) # ";
        const challenge = '" # challenge # "';

        function updateTimer() {
            const minutes = Math.floor(secondsLeft / 60);
            const seconds = secondsLeft % 60;
            const timerElement = document.getElementById('timer');

            if (timerElement) {
                timerElement.textContent = minutes + ':' + String(seconds).padStart(2, '0');

                if (secondsLeft <= 30) {
                    timerElement.classList.add('warning');
                }

                if (secondsLeft <= 0) {
                    timerElement.textContent = 'EXPIRED';
                    document.getElementById('finalize-btn').disabled = true;
                    document.getElementById('expired-message').style.display = 'block';
                    return;
                }
            }

            secondsLeft--;
            setTimeout(updateTimer, 1000);
        }

        function finalizeMeeting() {
            // Submit the form
            document.getElementById('finalize-form').submit();
        }

        window.onload = function() {
            updateTimer();

            // Store challenge in session storage
            sessionStorage.setItem('active_meeting_challenge', challenge);
        };
    </script>
</head>
<body>
    <div class=\"container\">
        <div class=\"meeting-card\">
            <div class=\"header\">
                <h1>🤝 Meeting Session</h1>
                <span class=\"status-badge\">Active</span>
            </div>

            <div class=\"timer\">
                <div class=\"timer-value\" id=\"timer\">--:--</div>
                <div class=\"timer-label\">Time Remaining</div>
            </div>

            <div class=\"scanned-items\">
                <h2>Items in Meeting (" # Nat.toText(scannedItems.size()) # ")</h2>
                <ul class=\"item-list\">
                    " # scannedItemsHtml # "
                </ul>
            </div>

            <div class=\"qr-section\">
                <h3>📱 Scan More Items</h3>
                <p>Have other people scan their NFC tags to join this meeting. They will automatically be added!</p>
                <div class=\"qr-info\">
                    <strong>Meeting is active for " # Int.toText(secondsRemaining) # " seconds</strong>
                </div>
            </div>

            " # (if (scannedItems.size() < 2) {
                "<div class=\"instructions\">
                    <h3>⚠️ Need More Participants</h3>
                    <p>At least 2 items are required to finalize a meeting. Each participant will earn 10 tokens!</p>
                </div>"
            } else {
                "<div class=\"instructions\" style=\"background: #d1fae5; border-left-color: #10b981;\">
                    <h3 style=\"color: #065f46;\">✅ Ready to Finalize</h3>
                    <p style=\"color: #047857;\">You have enough participants! Finalize the meeting now to distribute tokens, or scan more items to include them.</p>
                </div>"
            }) # "

            <div class=\"success-message\" id=\"expired-message\" style=\"display: none; background: #fed7d7; color: #742a2a; border-left-color: #e53e3e;\">
                ⏰ Session expired. Please start a new meeting.
            </div>

            <form id=\"finalize-form\" method=\"GET\" action=\"/meeting/finalize\" style=\"margin: 0;\">
                <input type=\"hidden\" name=\"challenge\" value=\"" # challenge # "\">
                <div class=\"actions\">
                    <a href=\"/collection\" class=\"btn btn-secondary\">Cancel</a>
                    <button id=\"finalize-btn\" type=\"submit\" class=\"btn btn-primary\" " # (if (scannedItems.size() < 2) { "disabled" } else { "" }) # ">
                        Finalize Meeting
                    </button>
                </div>
            </form>

            <div class=\"challenge-info\">
                <strong>Session ID:</strong> " # challenge # "
            </div>
        </div>
    </div>
</body>
</html>"
    };

    // Generate the meeting success page
    public func generateMeetingSuccessPage(
        meetingId: Text,
        itemsRewarded: [Nat],
        allItems: [Collection.Item],
        themeManager: Theme.ThemeManager
    ) : Text {
        let primary = themeManager.getPrimary();
        let secondary = themeManager.getSecondary();

        let itemsHtml = generateRewardedItemsList(itemsRewarded, allItems);

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Meeting Completed!</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
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
        .container {
            max-width: 600px;
            width: 100%;
        }
        .success-card {
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
        h1 {
            font-size: 2.5rem;
            color: " # primary # ";
            margin-bottom: 0.5rem;
        }
        .subtitle {
            font-size: 1.2rem;
            color: #718096;
            margin-bottom: 2rem;
        }
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
        .items-rewarded h2 {
            color: #2d3748;
            margin-bottom: 1rem;
            font-size: 1.2rem;
        }
        .item-entry {
            background: white;
            padding: 1rem;
            margin-bottom: 0.75rem;
            border-radius: 10px;
            border-left: 4px solid " # secondary # ";
            display: flex;
            align-items: center;
            gap: 1rem;
        }
        .item-entry:last-child {
            margin-bottom: 0;
        }
        .item-icon {
            width: 50px;
            height: 50px;
            border-radius: 8px;
            object-fit: cover;
        }
        .item-info {
            flex: 1;
        }
        .item-name {
            font-weight: 600;
            color: #2d3748;
            margin-bottom: 0.25rem;
        }
        .item-tokens {
            color: #10b981;
            font-weight: 700;
        }
        .meeting-id {
            background: #f7fafc;
            padding: 1rem;
            border-radius: 8px;
            font-size: 0.85rem;
            color: #718096;
            margin: 2rem 0;
            word-break: break-all;
        }
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
            transition: all 0.3s ease;
            text-decoration: none;
            display: block;
            text-align: center;
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
        .btn-secondary:hover {
            background: #cbd5e0;
        }
    </style>
    <script>
        window.onload = function() {
            // Clear session storage
            sessionStorage.removeItem('active_meeting_challenge');
            sessionStorage.removeItem('meeting_challenge');
            sessionStorage.removeItem('meeting_finalized');
        };
    </script>
</head>
<body>
    <div class=\"container\">
        <div class=\"success-card\">
            <div class=\"icon\">🎉</div>
            <h1>Meeting Completed!</h1>
            <p class=\"subtitle\">Tokens have been distributed to all participants</p>

            <div class=\"reward-badge\">
                +10 Tokens Each
            </div>

            <div class=\"items-rewarded\">
                <h2>Participants (" # Nat.toText(itemsRewarded.size()) # " items)</h2>
                " # itemsHtml # "
            </div>

            <div class=\"meeting-id\">
                <strong>Meeting ID:</strong> " # meetingId # "
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
}
