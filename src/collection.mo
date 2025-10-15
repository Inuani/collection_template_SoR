import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Map "mo:core/Map";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Result "mo:core/Result";
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
    };
};
