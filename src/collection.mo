import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Map "mo:core/Map";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Result "mo:core/Result";
import Theme "utils/theme";
import Time "mo:core/Time";
import Int "mo:core/Int";

module {
    // Meeting Record Type
    public type MeetingRecord = {
        meeting_id: Text;
        date: Int; // timestamp
        partner_item_ids: [Nat]; // other items in the meeting
        tokens_earned: Nat;
    };

    // Collection data - you can expand this with more properties
    public type Item = {
        id: Nat;
        name: Text;
        thumbnailUrl: Text; // Image for collection grid
        imageUrl: Text;     // Full-size image for detail page
        description: Text;
        rarity: Text;
        attributes: [(Text, Text)]; // key-value pairs for additional attributes
        token_balance: Nat; // tokens earned from meetings
        meeting_history: [MeetingRecord]; // array of past meetings
    };

    // State for persistence across upgrades
    public type State = {
        var items : [(Nat, Item)];
        var nextId : Nat;
        var collectionName : Text;
        var collectionDescription : Text;
    };

    // Initialize state
    public func init() : State = {
        var items = [];
        var nextId = 0;
        var collectionName = "Collection d'Évorev";
        var collectionDescription = "Une collection parmi d'autre ...";
    };

    public class Collection(state : State) {
        // Map for efficient lookups
        private var items = Map.fromIter<Nat, Item>(
            state.items.values(),
            Nat.compare,
        );

        private var nextId = state.nextId;

        // Update state for persistence
        private func updateState() {
            state.items := Iter.toArray(Map.entries(items));
            state.nextId := nextId;
        };

        // ============================================
        // UTILITY FUNCTIONS
        // ============================================

        // ============================================
        // ADMIN FUNCTIONS (Add/Update/Delete)
        // ============================================

        // Add a new item to the collection
        public func addItem(
            name: Text,
            thumbnailUrl: Text,
            imageUrl: Text,
            description: Text,
            rarity: Text,
            attributes: [(Text, Text)]
        ) : Nat {
            let id = nextId;
            let newItem : Item = {
                id;
                name;
                thumbnailUrl;
                imageUrl;
                description;
                rarity;
                attributes;
                token_balance = 0;
                meeting_history = [];
            };

            Map.add(items, Nat.compare, id, newItem);
            nextId += 1;
            updateState();
            id
        };

        // Update an existing item
        public func updateItem(
            id: Nat,
            name: Text,
            thumbnailUrl: Text,
            imageUrl: Text,
            description: Text,
            rarity: Text,
            attributes: [(Text, Text)]
        ) : Result.Result<(), Text> {
            switch (Map.get(items, Nat.compare, id)) {
                case null {
                    #err("Item with ID " # Nat.toText(id) # " not found")
                };
                case (?existingItem) {
                    let updatedItem : Item = {
                        id;
                        name;
                        thumbnailUrl;
                        imageUrl;
                        description;
                        rarity;
                        attributes;
                        token_balance = existingItem.token_balance; // Preserve existing balance
                        meeting_history = existingItem.meeting_history; // Preserve history
                    };
                    Map.add(items, Nat.compare, id, updatedItem);
                    updateState();
                    #ok()
                };
            };
        };

        // Delete an item
        public func deleteItem(id: Nat) : Result.Result<(), Text> {
            switch (Map.take(items, Nat.compare, id)) {
                case null {
                    #err("Item with ID " # Nat.toText(id) # " not found")
                };
                case (?_) {
                    updateState();
                    #ok()
                };
            };
        };

        // ============================================
        // QUERY FUNCTIONS
        // ============================================

        // Get a specific item by ID
        public func getItem(id: Nat): ?Item {
            Map.get(items, Nat.compare, id)
        };

        // Get all items as an array
        public func getAllItems(): [Item] {
            let itemsArray = Iter.toArray(Map.values(items));
            // Sort by ID
            Array.sort(itemsArray, func(a: Item, b: Item) : { #less; #equal; #greater } {
                if (a.id < b.id) { #less }
                else if (a.id > b.id) { #greater }
                else { #equal }
            })
        };

        // Get total count of items
        public func getItemCount(): Nat {
            Map.size(items)
        };

        // ============================================
        // TOKEN MANAGEMENT
        // ============================================


        // Add tokens to an item's balance
        public func addTokens(itemId: Nat, amount: Nat) : Result.Result<(), Text> {
            switch (Map.get(items, Nat.compare, itemId)) {
                case null {
                    #err("Item with ID " # Nat.toText(itemId) # " not found")
                };
                case (?item) {
                    let updatedItem : Item = {
                        id = item.id;
                        name = item.name;
                        thumbnailUrl = item.thumbnailUrl;
                        imageUrl = item.imageUrl;
                        description = item.description;
                        rarity = item.rarity;
                        attributes = item.attributes;
                        token_balance = item.token_balance + amount;
                        meeting_history = item.meeting_history;
                    };
                    Map.add(items, Nat.compare, itemId, updatedItem);
                    updateState();
                    #ok()
                };
            };
        };

        // Record a meeting for multiple items
        public func recordMeeting(itemIds: [Nat], meetingId: Text, tokensEarned: Nat) : Result.Result<(), Text> {
            let timestamp = Time.now();

            // Update each item with the meeting record
            for (itemId in itemIds.vals()) {
                switch (Map.get(items, Nat.compare, itemId)) {
                    case null {
                        // Skip items that don't exist
                    };
                    case (?item) {
                        // Get other participants (exclude current item)
                        let partnerIds = Array.filter<Nat>(itemIds, func(id) = id != itemId);

                        // Create meeting record
                        let meetingRecord : MeetingRecord = {
                            meeting_id = meetingId;
                            date = timestamp;
                            partner_item_ids = partnerIds;
                            tokens_earned = tokensEarned;
                        };

                        // Add to history
                        let updatedHistory = Array.concat(item.meeting_history, [meetingRecord]);

                        // Update item with new history and tokens
                        let updatedItem : Item = {
                            id = item.id;
                            name = item.name;
                            thumbnailUrl = item.thumbnailUrl;
                            imageUrl = item.imageUrl;
                            description = item.description;
                            rarity = item.rarity;
                            attributes = item.attributes;
                            token_balance = item.token_balance + tokensEarned;
                            meeting_history = updatedHistory;
                        };

                        Map.add(items, Nat.compare, itemId, updatedItem);
                    };
                };
            };

            updateState();
            #ok()
        };

        // Get item's token balance
        public func getItemBalance(itemId: Nat) : Result.Result<Nat, Text> {
            switch (Map.get(items, Nat.compare, itemId)) {
                case null {
                    #err("Item with ID " # Nat.toText(itemId) # " not found")
                };
                case (?item) {
                    #ok(item.token_balance)
                };
            };
        };

        // Get item's meeting history
        public func getItemMeetingHistory(itemId: Nat) : Result.Result<[MeetingRecord], Text> {
            switch (Map.get(items, Nat.compare, itemId)) {
                case null {
                    #err("Item with ID " # Nat.toText(itemId) # " not found")
                };
                case (?item) {
                    #ok(item.meeting_history)
                };
            };
        };

        // Admin function: List all active meetings (for debugging)


        // ============================================
        // COLLECTION SETTINGS
        // ============================================

        public func setCollectionName(name: Text) {
            state.collectionName := name;
        };

        public func setCollectionDescription(description: Text) {
            state.collectionDescription := description;
        };

        public func getCollectionName(): Text {
            state.collectionName
        };

        public func getCollectionDescription(): Text {
            state.collectionDescription
        };

        // ============================================
        // HTML GENERATION
        // ============================================

        // Generate HTML page for a specific item
        public func generateItemPage(id: Nat, themeManager: Theme.ThemeManager): Text {
            switch (getItem(id)) {
                case (?item) generateItemDetailPage(item, themeManager);
                case null generateNotFoundPage(id, themeManager);
            }
        };

        // Generate the main collection page showing all items
        public func generateCollectionPage(themeManager: Theme.ThemeManager): Text {
            let itemsGrid = generateItemsGrid();
            let primary = themeManager.getPrimary();
            let secondary = themeManager.getSecondary();

            "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>" # state.collectionName # "</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: white;
            min-height: 100vh;
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
            border-top: 4px solid " # secondary # ";
        }
        .header {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        .logo {
            width: 80px;
            height: auto;
        }
        h1 {
            color: " # primary # ";
            font-size: 3rem;
            margin: 0;
        }
        .items-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 2rem;
            margin-top: 2rem;
        }
        .item-card {
            background: white;
            border-radius: 15px;
            padding: 1.5rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            text-decoration: none;
            color: inherit;
            border-left: 3px solid " # secondary # ";
        }
        .item-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 20px 40px rgba(0,0,0,0.3);
        }
        .item-image {
            width: 100%;
            height: auto;
            max-height: 300px;
            object-fit: contain;
            border-radius: 10px;
            margin-bottom: 1rem;
        }
        .item-title {
            font-size: 1.5rem;
            font-weight: 600;
            margin-bottom: 0.5rem;
            color: #2d3748;
        }
        .item-id {
            color: #718096;
            font-size: 0.9rem;
            margin-bottom: 0.5rem;
        }
        .item-rarity {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: 500;
            margin-bottom: 0.5rem;
        }
        .rarity-common { background: #e6fffa; color: #047857; }
        .rarity-rare { background: #dbeafe; color: #1e40af; }
        .rarity-epic { background: #faf5ff; color: #7c3aed; }
        .rarity-légendaire { background: #fef3c7; color: #92400e; }
        .item-description {
            color: #4a5568;
            line-height: 1.5;
        }
        .empty-collection {
            text-align: center;
            padding: 4rem;
            color: #718096;
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"header\">
            <img src=\"/logo.webp\" alt=\"Logo\" class=\"logo\">
            <h1>" # state.collectionName # "</h1>
        </div>
        <div class=\"items-grid\">
            " # itemsGrid # "
        </div>
    </div>
</body>
</html>"
        };

        // Generate individual item page
        private func generateItemDetailPage(item: Item, themeManager: Theme.ThemeManager): Text {
            let attributesHtml = generateAttributesHtml(item.attributes);
            let rarityClass = "rarity-" # Text.toLower(item.rarity);
            let primary = themeManager.getPrimary();
            let secondary = themeManager.getSecondary();

            "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>" # item.name # " - " # state.collectionName # "</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: white;
            min-height: 100vh;
            color: #333;
            padding: 2rem;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            padding: 2rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.2);
            border-top: 4px solid " # secondary # ";
        }
        .back-link {
            display: inline-block;
            margin-bottom: 2rem;
            color: " # primary # ";
            text-decoration: none;
            font-weight: 500;
        }
        .back-link:hover {
            text-decoration: underline;
        }
        .item-header {
            text-align: center;
            margin-bottom: 2rem;
        }
        .item-title {
            font-size: 2.5rem;
            font-weight: 700;
            color: #2d3748;
            margin-bottom: 0.5rem;
        }
        .item-id {
            color: #718096;
            font-size: 1.1rem;
        }
        .item-image {
            width: 100%;
            max-width: 400px;
            height: auto;
            object-fit: contain;
            border-radius: 15px;
            margin: 0 auto 2rem auto;
            display: block;
            box-shadow: 0 10px 25px rgba(0,0,0,0.2);
        }
        .item-rarity {
            display: inline-block;
            padding: 0.5rem 1rem;
            border-radius: 25px;
            font-size: 1rem;
            font-weight: 600;
            margin-bottom: 1.5rem;
        }
        .rarity-common { background: #e6fffa; color: #047857; }
        .rarity-rare { background: #dbeafe; color: #1e40af; }
        .rarity-epic { background: #faf5ff; color: #7c3aed; }
        .rarity-légendaire { background: #fef3c7; color: #92400e; }
        .item-description {
            font-size: 1.2rem;
            line-height: 1.6;
            color: #4a5568;
            margin-bottom: 2rem;
            text-align: center;
            font-style: italic;
        }
        .attributes {
            background: #f7fafc;
            border-radius: 10px;
            padding: 1.5rem;
        }
        .attributes-title {
            font-size: 1.3rem;
            font-weight: 600;
            color: #2d3748;
            margin-bottom: 1rem;
        }
        .attribute {
            display: flex;
            justify-content: space-between;
            padding: 0.75rem 0;
            border-bottom: 1px solid #e2e8f0;
        }
        .attribute:last-child {
            border-bottom: none;
        }
        .attribute-key {
            font-weight: 500;
            color: #4a5568;
        }
        .attribute-value {
            color: #2d3748;
            font-weight: 600;
        }
        .token-section {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 15px;
            padding: 2rem;
            text-align: center;
            margin: 2rem 0;
            color: white;
        }
        .token-balance {
            font-size: 3rem;
            font-weight: 700;
            margin-bottom: 0.5rem;
        }
        .token-label {
            font-size: 1.1rem;
            opacity: 0.9;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .meeting-history {
            background: #f7fafc;
            border-radius: 10px;
            padding: 1.5rem;
            margin: 2rem 0;
        }
        .meeting-history-title {
            font-size: 1.3rem;
            font-weight: 600;
            color: #2d3748;
            margin-bottom: 1rem;
        }
        .meeting-record {
            background: white;
            border-radius: 8px;
            padding: 1rem;
            margin-bottom: 0.75rem;
            border-left: 4px solid " # secondary # ";
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }
        .meeting-record:last-child {
            margin-bottom: 0;
        }
        .meeting-date {
            font-size: 0.85rem;
            color: #718096;
            margin-bottom: 0.25rem;
        }
        .meeting-partners {
            font-weight: 500;
            color: #2d3748;
            margin-bottom: 0.25rem;
        }
        .meeting-tokens {
            color: #48bb78;
            font-weight: 600;
            font-size: 0.9rem;
        }

    </style>
</head>
<body>
    <div class=\"container\">
        <a href=\"/collection\" class=\"back-link\">← Retour à la collection</a>

        <div class=\"item-header\">
            <h1 class=\"item-title\">" # item.name # "</h1>
        </div>

        <img src=\"" # item.imageUrl # "\" alt=\"" # item.name # "\" class=\"item-image\">

        <div style=\"text-align: center;\">
            <span class=\"item-rarity " # rarityClass # "\">" # item.rarity # "</span>
        </div>

        <p class=\"item-description\">" # item.description # "</p>

        <div class=\"token-section\">
            <div class=\"token-balance\">" # Nat.toText(item.token_balance) # "</div>
            <div class=\"token-label\">Tokens Earned</div>
        </div>

        " # (if (item.meeting_history.size() > 0) {
            "<div class=\"meeting-history\">
                <h3 class=\"meeting-history-title\">Meeting History (" # Nat.toText(item.meeting_history.size()) # " meetings)</h3>
                " # generateMeetingHistoryHtml(item.meeting_history) # "
            </div>"
        } else {
            ""
        }) # "

        <div class=\"attributes\">
            <h3 class=\"attributes-title\">Attributs</h3>
            " # attributesHtml # "
        </div>
    </div>
</body>
</html>"
        };

        // Generate meeting history HTML
        private func generateMeetingHistoryHtml(history: [MeetingRecord]): Text {
            var html = "";
            for (record in history.vals()) {
                let partnersStr = if (record.partner_item_ids.size() > 0) {
                    var partners = "Met with items: ";
                    var i = 0;
                    let partnersSize = record.partner_item_ids.size();
                    while (i < partnersSize) {
                        partners #= "#" # Nat.toText(record.partner_item_ids[i]);
                        if (i + 1 < partnersSize) {
                            partners #= ", ";
                        };
                        i += 1;
                    };
                    partners
                } else {
                    "Solo meeting"
                };

                html #= "<div class=\"meeting-record\">
                    <div class=\"meeting-date\">Meeting ID: " # record.meeting_id # "</div>
                    <div class=\"meeting-partners\">" # partnersStr # "</div>
                    <div class=\"meeting-tokens\">+" # Nat.toText(record.tokens_earned) # " tokens</div>
                </div>";
            };
            html
        };

        // Generate grid of all items for collection page
        private func generateItemsGrid(): Text {
            let allItems = getAllItems();

            if (allItems.size() == 0) {
                return "<div class=\"empty-collection\"><h2>Collection vide pour l'instant!</h2></div>";
            };

            var html = "";
            for (item in allItems.vals()) {
                let rarityClass = "rarity-" # Text.toLower(item.rarity);
                html #= "<a href=\"/item/" # Nat.toText(item.id) # "\" class=\"item-card\">
                    <img src=\"" # item.thumbnailUrl # "\" alt=\"" # item.name # "\" class=\"item-image\">
                    <h3 class=\"item-title\">" # item.name # "</h3>
                    <span class=\"item-rarity " # rarityClass # "\">" # item.rarity # "</span>
                    <p class=\"item-description\">" # item.description # "</p>
                </a>";
            };
            html
        };

        // Generate HTML for attributes
        private func generateAttributesHtml(attributes: [(Text, Text)]): Text {
            var html = "";
            for ((key, value) in attributes.vals()) {
                html #= "<div class=\"attribute\">
                    <span class=\"attribute-key\">" # key # "</span>
                    <span class=\"attribute-value\">" # value # "</span>
                </div>";
            };
            html
        };

        // Generate 404 page for non-existent items
        public func generateNotFoundPage(id: Nat, themeManager: Theme.ThemeManager): Text {
            let primary = themeManager.getPrimary();
            let secondary = themeManager.getSecondary();

            "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Item Not Found</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: white;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #333;
            text-align: center;
        }
        .error-container {
            background: white;
            border-radius: 20px;
            padding: 3rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.2);
            border: 3px solid " # secondary # ";
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            color: " # primary # ";
        }
        p {
            font-size: 1.2rem;
            margin-bottom: 2rem;
            opacity: 0.8;
        }
        a {
            color: white;
            text-decoration: none;
            background: " # primary # ";
            padding: 1rem 2rem;
            border-radius: 10px;
            transition: all 0.3s ease;
        }
        a:hover {
            opacity: 0.9;
            transform: translateY(-2px);
        }
    </style>
</head>
<body>
    <div class=\"error-container\">
        <h1>Item Not Found</h1>
        <p>Sorry, Item #" # Nat.toText(id) # " doesn't exist in this collection.</p>
        <a href=\"/collection\">View Collection</a>
    </div>
</body>
</html>"
        };
    };
}
