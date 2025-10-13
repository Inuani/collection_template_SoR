import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Map "mo:core/Map";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Result "mo:core/Result";
import Theme "theme";
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

    // Pending Meeting Type
    public type PendingMeeting = {
        challenge: Text;
        created_at: Int;
        expires_at: Int;
        scanned_items: [Nat]; // item IDs in this session
        status: Text; // "pending" | "completed"
    };

    // Completed Meeting Type
    public type CompletedMeeting = {
        meeting_id: Text;
        item_ids: [Nat];
        completed_at: Int;
    };

    // State for persistence across upgrades
    public type State = {
        var items : [(Nat, Item)];
        var nextId : Nat;
        var collectionName : Text;
        var collectionDescription : Text;
        var pending_meetings : [(Text, PendingMeeting)];
        var completed_meetings : [(Text, CompletedMeeting)];
    };

    // Initialize state
    public func init() : State = {
        var items = [];
        var nextId = 0;
        var collectionName = "Collection d'Évorev";
        var collectionDescription = "Une collection parmi d'autre ...";
        var pending_meetings = [];
        var completed_meetings = [];
    };

    public class Collection(state : State) {
        // Map for efficient lookups
        private var items = Map.fromIter<Nat, Item>(
            state.items.values(),
            Nat.compare,
        );

        private var nextId = state.nextId;

        // Meeting session maps
        private var pendingMeetings = Map.fromIter<Text, PendingMeeting>(
            state.pending_meetings.values(),
            Text.compare,
        );

        private var completedMeetings = Map.fromIter<Text, CompletedMeeting>(
            state.completed_meetings.values(),
            Text.compare,
        );

        // Update state for persistence
        private func updateState() {
            state.items := Iter.toArray(Map.entries(items));
            state.nextId := nextId;
            state.pending_meetings := Iter.toArray(Map.entries(pendingMeetings));
            state.completed_meetings := Iter.toArray(Map.entries(completedMeetings));
        };

        // ============================================
        // UTILITY FUNCTIONS
        // ============================================

        // Generate a random UUID-like challenge
        private func generateChallenge(timestamp: Int, itemId: Nat) : Text {
            let hash1 = Int.toText(timestamp);
            let hash2 = Nat.toText(itemId);
            let combined = hash1 # "-" # hash2 # "-" # Int.toText(timestamp % 1000000);
            combined
        };

        // Check if a session is expired
        private func isExpired(expiresAt: Int, currentTime: Int) : Bool {
            currentTime > expiresAt
        };

        // Check cooldown period - same items cannot meet within 24 hours
        private func checkCooldown(itemIds: [Nat], currentTime: Int) : Bool {
            let sortedIds = Array.sort(itemIds, Nat.compare);

            // Check all completed meetings
            for ((_, meeting) in Map.entries(completedMeetings)) {
                let sortedMeetingIds = Array.sort(meeting.item_ids, Nat.compare);

                // Check if same set of items
                if (arraysEqual(sortedIds, sortedMeetingIds)) {
                    let timeDiff = currentTime - meeting.completed_at;
                    let oneDayInNanos = 86_400_000_000_000; // 24 hours in nanoseconds

                    if (timeDiff < oneDayInNanos) {
                        return false; // Still in cooldown
                    };
                };
            };
            true // No cooldown
        };

        // Helper to compare arrays
        private func arraysEqual(a: [Nat], b: [Nat]) : Bool {
            if (a.size() != b.size()) {
                return false;
            };

            var i = 0;
            while (i < a.size()) {
                if (a[i] != b[i]) {
                    return false;
                };
                i += 1;
            };
            true
        };

        // Clean up expired sessions
        private func cleanupExpiredSessions(currentTime: Int) {
            let entries = Iter.toArray(Map.entries(pendingMeetings));
            for ((challenge, meeting) in entries.vals()) {
                if (isExpired(meeting.expires_at, currentTime) and meeting.status == "pending") {
                    ignore Map.delete(pendingMeetings, Text.compare, challenge);
                };
            };
            updateState();
        };

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
        // PROOF-OF-MEETING FUNCTIONS
        // ============================================

        // Find any active meeting that doesn't include this item
        private func findActiveMeeting(itemId: Nat, currentTime: Int) : ?Text {
            for ((challenge, meeting) in Map.entries(pendingMeetings)) {
                if (meeting.status == "pending" and not isExpired(meeting.expires_at, currentTime)) {
                    // Check if item is not already in this meeting
                    var alreadyInMeeting = false;
                    for (existingId in meeting.scanned_items.vals()) {
                        if (existingId == itemId) {
                            alreadyInMeeting := true;
                        };
                    };

                    if (not alreadyInMeeting) {
                        return ?challenge;
                    };
                };
            };
            null
        };

        // Create a new meeting session OR join existing one
        public func createMeetingSession(itemId: Nat, _nfcUid: Text, _cmac: Text) : Result.Result<{challenge: Text}, Text> {
            // Verify item exists
            switch (Map.get(items, Nat.compare, itemId)) {
                case null {
                    return #err("Item with ID " # Nat.toText(itemId) # " not found");
                };
                case (?_item) {
                    let currentTime = Time.now();

                    // Clean up expired sessions first
                    cleanupExpiredSessions(currentTime);

                    // Check if there's an active meeting this item can join
                    switch (findActiveMeeting(itemId, currentTime)) {
                        case (?existingChallenge) {
                            // Join the existing meeting instead of creating new one
                            switch (Map.get(pendingMeetings, Text.compare, existingChallenge)) {
                                case (?meeting) {
                                    let updatedItems = Array.concat(meeting.scanned_items, [itemId]);
                                    let updatedMeeting : PendingMeeting = {
                                        challenge = meeting.challenge;
                                        created_at = meeting.created_at;
                                        expires_at = meeting.expires_at;
                                        scanned_items = updatedItems;
                                        status = meeting.status;
                                    };

                                    Map.add(pendingMeetings, Text.compare, existingChallenge, updatedMeeting);
                                    updateState();

                                    return #ok({challenge = existingChallenge});
                                };
                                case null {
                                    // Shouldn't happen, but fall through to create new meeting
                                };
                            };
                        };
                        case null {
                            // No active meeting found, create a new one
                        };
                    };

                    // Generate challenge for new meeting
                    let challenge = generateChallenge(currentTime, itemId);

                    // Create pending meeting (expires in 2 minutes)
                    let twoMinutesInNanos = 120_000_000_000; // 2 minutes in nanoseconds
                    let expiresAt = currentTime + twoMinutesInNanos;

                    let pendingMeeting : PendingMeeting = {
                        challenge = challenge;
                        created_at = currentTime;
                        expires_at = expiresAt;
                        scanned_items = [itemId];
                        status = "pending";
                    };

                    Map.add(pendingMeetings, Text.compare, challenge, pendingMeeting);
                    updateState();

                    #ok({challenge = challenge})
                };
            };
        };

        // Join an existing meeting session
        public func joinMeetingSession(challenge: Text, itemId: Nat, _nfcUid: Text, _cmac: Text) : Result.Result<{items_in_session: [Nat]}, Text> {
            // Verify item exists
            switch (Map.get(items, Nat.compare, itemId)) {
                case null {
                    return #err("Item with ID " # Nat.toText(itemId) # " not found");
                };
                case (?_item) {
                    let currentTime = Time.now();

                    // Get pending meeting
                    switch (Map.get(pendingMeetings, Text.compare, challenge)) {
                        case null {
                            return #err("Meeting session not found or expired");
                        };
                        case (?meeting) {
                            // Check if expired
                            if (isExpired(meeting.expires_at, currentTime)) {
                                return #err("Meeting session has expired");
                            };

                            // Check if already completed
                            if (meeting.status != "pending") {
                                return #err("Meeting session already completed");
                            };

                            // Check if item already in session
                            for (existingId in meeting.scanned_items.vals()) {
                                if (existingId == itemId) {
                                    return #err("Item already scanned in this session");
                                };
                            };

                            // Add item to session
                            let updatedItems = Array.concat(meeting.scanned_items, [itemId]);
                            let updatedMeeting : PendingMeeting = {
                                challenge = meeting.challenge;
                                created_at = meeting.created_at;
                                expires_at = meeting.expires_at;
                                scanned_items = updatedItems;
                                status = meeting.status;
                            };

                            Map.add(pendingMeetings, Text.compare, challenge, updatedMeeting);
                            updateState();

                            #ok({items_in_session = updatedItems})
                        };
                    };
                };
            };
        };

        // Finalize a meeting and distribute tokens
        public func finalizeMeeting(challenge: Text) : Result.Result<{meeting_id: Text; items_rewarded: [Nat]}, Text> {
            let currentTime = Time.now();

            // Get pending meeting
            switch (Map.get(pendingMeetings, Text.compare, challenge)) {
                case null {
                    return #err("Meeting session not found");
                };
                case (?meeting) {
                    // Check if expired
                    if (isExpired(meeting.expires_at, currentTime)) {
                        return #err("Meeting session has expired");
                    };

                    // Check if already completed
                    if (meeting.status != "pending") {
                        return #err("Meeting already finalized");
                    };

                    // Must have at least 2 items
                    if (meeting.scanned_items.size() < 2) {
                        return #err("Need at least 2 items to finalize meeting");
                    };

                    // Check cooldown period
                    if (not checkCooldown(meeting.scanned_items, currentTime)) {
                        return #err("These items have met too recently. Please wait 24 hours.");
                    };

                    // Generate unique meeting ID
                    let meetingId = "meeting-" # Int.toText(currentTime) # "-" # Nat.toText(meeting.scanned_items.size());

                    // Reward each item
                    let tokensPerMeeting = 10;

                    for (itemId in meeting.scanned_items.vals()) {
                        switch (Map.get(items, Nat.compare, itemId)) {
                            case null { /* Skip if item not found */ };
                            case (?item) {
                                // Get partner items (all items except this one)
                                let partnerItems = Array.filter<Nat>(meeting.scanned_items, func(id) { id != itemId });

                                // Create meeting record
                                let meetingRecord : MeetingRecord = {
                                    meeting_id = meetingId;
                                    date = currentTime;
                                    partner_item_ids = partnerItems;
                                    tokens_earned = tokensPerMeeting;
                                };

                                // Update item with new balance and history
                                let updatedItem : Item = {
                                    id = item.id;
                                    name = item.name;
                                    thumbnailUrl = item.thumbnailUrl;
                                    imageUrl = item.imageUrl;
                                    description = item.description;
                                    rarity = item.rarity;
                                    attributes = item.attributes;
                                    token_balance = item.token_balance + tokensPerMeeting;
                                    meeting_history = Array.concat(item.meeting_history, [meetingRecord]);
                                };

                                Map.add(items, Nat.compare, itemId, updatedItem);
                            };
                        };
                    };

                    // Mark meeting as completed
                    let completedMeeting : CompletedMeeting = {
                        meeting_id = meetingId;
                        item_ids = meeting.scanned_items;
                        completed_at = currentTime;
                    };

                    Map.add(completedMeetings, Text.compare, meetingId, completedMeeting);

                    // Update pending meeting status
                    let finalizedMeeting : PendingMeeting = {
                        challenge = meeting.challenge;
                        created_at = meeting.created_at;
                        expires_at = meeting.expires_at;
                        scanned_items = meeting.scanned_items;
                        status = "completed";
                    };

                    Map.add(pendingMeetings, Text.compare, challenge, finalizedMeeting);
                    updateState();

                    #ok({meeting_id = meetingId; items_rewarded = meeting.scanned_items})
                };
            };
        };

        // Get meeting session status
        public func getMeetingSessionStatus(challenge: Text) : Result.Result<{items_scanned: [Nat]; expires_in: Int; ready_to_finalize: Bool}, Text> {
            let currentTime = Time.now();

            switch (Map.get(pendingMeetings, Text.compare, challenge)) {
                case null {
                    return #err("Meeting session not found");
                };
                case (?meeting) {
                    let expiresIn = meeting.expires_at - currentTime;
                    let readyToFinalize = meeting.scanned_items.size() >= 2 and not isExpired(meeting.expires_at, currentTime);

                    #ok({
                        items_scanned = meeting.scanned_items;
                        expires_in = expiresIn;
                        ready_to_finalize = readyToFinalize;
                    })
                };
            };
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
        public func listActiveMeetings() : [(Text, {
            challenge: Text;
            created_at: Int;
            expires_at: Int;
            scanned_items: [Nat];
            status: Text;
        })] {
            let currentTime = Time.now();
            var activeMeetings : [(Text, PendingMeeting)] = [];

            for ((challenge, meeting) in Map.entries(pendingMeetings)) {
                if (meeting.status == "pending" and not isExpired(meeting.expires_at, currentTime)) {
                    activeMeetings := Array.concat(activeMeetings, [(challenge, meeting)]);
                };
            };

            activeMeetings
        };

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
