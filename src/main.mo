import Liminal "mo:liminal";
import Principal "mo:core/Principal";
import Error "mo:core/Error";
import AssetsMiddleware "mo:liminal/Middleware/Assets";
import SessionMiddleware "mo:liminal/Middleware/Session";
import HttpAssets "mo:http-assets@0";
import AssetCanister "mo:liminal/AssetCanister";
import Text "mo:core/Text";
import ProtectedRoutes "nfc_protec_routes";
import Routes "routes";
import Files "files";
import Collection "collection";
import Result "mo:core/Result";
import RouterMiddleware "mo:liminal/Middleware/Router";
import App "mo:liminal/App";
import HttpContext "mo:liminal/HttpContext";
import InvalidScan "invalid_scan";
import Theme "theme";
import Buttons "buttons";
import NFCMeeting "nfc_meeting";
import Nat "mo:core/Nat";
import Scan "scan";
import Iter "mo:core/Iter";
import Array "mo:core/Array";

shared ({ caller = initializer }) persistent actor class Actor() = self {

    transient let canisterId = Principal.fromActor(self);
    type ChunkId = Files.ChunkId;

    var assetStableData = HttpAssets.init_stable_store(canisterId, initializer);
    assetStableData := HttpAssets.upgrade_stable_store(assetStableData);

    let protectedRoutesState = ProtectedRoutes.init();
    transient let protected_routes_storage = ProtectedRoutes.RoutesStorage(protectedRoutesState);

    let fileStorageState = Files.init();
    transient let file_storage = Files.FileStorage(fileStorageState);

    let collectionState = Collection.init();
    transient let collection = Collection.Collection(collectionState);

    let themeState = Theme.init();
    transient let themeManager = Theme.ThemeManager(themeState);

    let buttonsState = Buttons.init();
    transient let buttonsManager = Buttons.ButtonsManager(buttonsState);


    transient let setPermissions : HttpAssets.SetPermissions = {
        commit = [initializer];
        manage_permissions = [initializer];
        prepare = [initializer];
    };
    transient var assetStore = HttpAssets.Assets(assetStableData, ?setPermissions);
    transient var assetCanister = AssetCanister.AssetCanister(assetStore);

    transient let assetMiddlewareConfig : AssetsMiddleware.Config = {
        store = assetStore;
    };

    func createNFCProtectionMiddleware() : App.Middleware {
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
                            let itemIdOpt = NFCMeeting.extractItemIdFromUrl(url);

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


    // Configure session middleware for meeting system
    transient let sessionStore = SessionMiddleware.buildInMemoryStore();
    transient let sessionConfig : SessionMiddleware.Config = {
        cookieName = "meeting_session";
        idleTimeout = 2 * 60; // 2 minutes in seconds
        cookieOptions = {
            path = "/";
            secure = false; // Set to true in production with HTTPS
            httpOnly = true;
            sameSite = ?#lax;
            maxAge = ?(2 * 60); // 2 minutes
        };
        store = sessionStore;
        idGenerator = SessionMiddleware.generateRandomId;
    };

    transient let app = Liminal.App({
        middleware = [
            SessionMiddleware.new(sessionConfig),
            createNFCProtectionMiddleware(),
            AssetsMiddleware.new(assetMiddlewareConfig),
            RouterMiddleware.new(Routes.routerConfig(
                Principal.toText(canisterId),
                file_storage.getFileChunk,
                collection,
                themeManager,
                file_storage,
                buttonsManager
            )),
        ];
        errorSerializer = Liminal.defaultJsonErrorSerializer;
        candidRepresentationNegotiator = Liminal.defaultCandidRepresentationNegotiator;
        logger = Liminal.buildDebugLogger(#info);
    });

    // Http server methods

    public query func http_request(request : Liminal.RawQueryHttpRequest) : async Liminal.RawQueryHttpResponse {
        app.http_request(request);
    };

    public func http_request_update(request : Liminal.RawUpdateHttpRequest) : async Liminal.RawUpdateHttpResponse {
        await* app.http_request_update(request);
    };


    public query func http_request_streaming_callback(token : HttpAssets.StreamingToken) : async HttpAssets.StreamingCallbackResponse {
        switch (assetStore.http_request_streaming_callback(token)) {
            case (#err(e)) throw Error.reject(e);
            case (#ok(response)) response;
        };
    };

    public func upload(chunk : [Nat8]) : async () {
        file_storage.upload(chunk);
      };

      public func uploadFinalize(title : Text, artist : Text, contentType : Text) : async Result.Result<Text, Text> {
        let uploadResult = file_storage.uploadFinalize(title, artist, contentType);

        switch (uploadResult) {
          case (#ok(msg)) {
            #ok(msg);
          };
          case (#err(msg)) {
            #err(msg);
          };
        };
      };

      public query func getFileChunk(title : Text, chunkId : ChunkId) : async ?{
        chunk : [Nat8];
        totalChunks : Nat;
        contentType : Text;
        title : Text;
        artist : Text;
      } {
        file_storage.getFileChunk(title, chunkId);
      };

      public query func listFiles() : async [(Text, Text, Text)] {
        file_storage.listFiles();
      };

      public func deleteFile(title : Text) : async Bool {
        file_storage.deleteFile(title);
      };

      public query func getStoredFileCount() : async Nat {
          file_storage.getStoredFileCount();
      };

      // ============================================
      // COLLECTION MANAGEMENT FUNCTIONS (Admin Only)
      // ============================================

      public shared ({ caller }) func addCollectionItem(
          name: Text,
          thumbnailUrl: Text,
          imageUrl: Text,
          description: Text,
          rarity: Text,
          attributes: [(Text, Text)]
      ) : async Nat {
          assert (caller == initializer);
          collection.addItem(name, thumbnailUrl, imageUrl, description, rarity, attributes)
      };

      public shared ({ caller }) func updateCollectionItem(
          id: Nat,
          name: Text,
          thumbnailUrl: Text,
          imageUrl: Text,
          description: Text,
          rarity: Text,
          attributes: [(Text, Text)]
      ) : async Result.Result<(), Text> {
          assert (caller == initializer);
          collection.updateItem(id, name, thumbnailUrl, imageUrl, description, rarity, attributes)
      };

      public shared ({ caller }) func deleteCollectionItem(id: Nat) : async Result.Result<(), Text> {
          assert (caller == initializer);
          collection.deleteItem(id)
      };

      public query func getCollectionItem(id: Nat) : async ?Collection.Item {
          collection.getItem(id)
      };

      public query func getAllCollectionItems() : async [Collection.Item] {
          collection.getAllItems()
      };

      public query func getCollectionItemCount() : async Nat {
          collection.getItemCount()
      };

      public shared ({ caller }) func setCollectionName(name: Text) : async () {
          assert (caller == initializer);
          collection.setCollectionName(name)
      };

      public shared ({ caller }) func setCollectionDescription(description: Text) : async () {
          assert (caller == initializer);
          collection.setCollectionDescription(description)
      };

      public query func getCollectionName() : async Text {
          collection.getCollectionName()
      };

      public query func getCollectionDescription() : async Text {
          collection.getCollectionDescription()
      };

      // ============================================
      // PROOF-OF-MEETING API FUNCTIONS
      // ============================================




      // Add tokens to an item
      public shared func addTokens(itemId: Nat, amount: Nat) : async Result.Result<(), Text> {
          collection.addTokens(itemId, amount)
      };



      // Get item's token balance
      public query func getItemBalance(itemId: Nat) : async Result.Result<Nat, Text> {
          collection.getItemBalance(itemId)
      };

      // Get item's meeting history
      public query func getItemMeetingHistory(itemId: Nat) : async Result.Result<[Collection.MeetingRecord], Text> {
          collection.getItemMeetingHistory(itemId)
      };



    assetStore.set_streaming_callback(http_request_streaming_callback);

    // public shared query func api_version() : async Nat16 {
    //     assetCanister.api_version();
    // };

    // public shared query func get(args : HttpAssets.GetArgs) : async HttpAssets.EncodedAsset {
    //     assetCanister.get(args);
    // };

    // public shared query func get_chunk(args : HttpAssets.GetChunkArgs) : async (HttpAssets.ChunkContent) {
    //     assetCanister.get_chunk(args);
    // };

    // public shared ({ caller }) func grant_permission(args : HttpAssets.GrantPermission) : async () {
    //     await* assetCanister.grant_permission(caller, args);
    // };

    // public shared ({ caller }) func revoke_permission(args : HttpAssets.RevokePermission) : async () {
    //     await* assetCanister.revoke_permission(caller, args);
    // };

    public shared query func list(args : {}) : async [HttpAssets.AssetDetails] {
        assetCanister.list(args);
    };

    // public shared ({ caller }) func store(args : HttpAssets.StoreArgs) : async () {
    //     assetCanister.store(caller, args);
    // };

    // public shared ({ caller }) func create_asset(args : HttpAssets.CreateAssetArguments) : async () {
    //     assetCanister.create_asset(caller, args);
    // };

    // public shared ({ caller }) func set_asset_content(args : HttpAssets.SetAssetContentArguments) : async () {
    //     await* assetCanister.set_asset_content(caller, args);
    // };

    // public shared ({ caller }) func unset_asset_content(args : HttpAssets.UnsetAssetContentArguments) : async () {
    //     assetCanister.unset_asset_content(caller, args);
    // };

    public shared ({ caller }) func delete_asset(args : HttpAssets.DeleteAssetArguments) : async () {
        assetCanister.delete_asset(caller, args);
    };

    // public shared ({ caller }) func set_asset_properties(args : HttpAssets.SetAssetPropertiesArguments) : async () {
    //     assetCanister.set_asset_properties(caller, args);
    // };

    // public shared ({ caller }) func clear(args : HttpAssets.ClearArguments) : async () {
    //     assetCanister.clear(caller, args);
    // };

    public shared ({ caller }) func create_batch(args : {}) : async (HttpAssets.CreateBatchResponse) {
        assetCanister.create_batch(caller, args);
    };

    public shared ({ caller }) func create_chunk(args : HttpAssets.CreateChunkArguments) : async (HttpAssets.CreateChunkResponse) {
        assetCanister.create_chunk(caller, args);
    };

    public shared ({ caller }) func create_chunks(args : HttpAssets.CreateChunksArguments) : async HttpAssets.CreateChunksResponse {
        await* assetCanister.create_chunks(caller, args);
    };

    public shared ({ caller }) func commit_batch(args : HttpAssets.CommitBatchArguments) : async () {
        await* assetCanister.commit_batch(caller, args);
    };

    // public shared ({ caller }) func propose_commit_batch(args : HttpAssets.CommitBatchArguments) : async () {
    //     assetCanister.propose_commit_batch(caller, args);
    // };

    // public shared ({ caller }) func commit_proposed_batch(args : HttpAssets.CommitProposedBatchArguments) : async () {
    //     await* assetCanister.commit_proposed_batch(caller, args);
    // };

    // public shared ({ caller }) func compute_evidence(args : HttpAssets.ComputeEvidenceArguments) : async (?Blob) {
    //     await* assetCanister.compute_evidence(caller, args);
    // };

    // public shared ({ caller }) func delete_batch(args : HttpAssets.DeleteBatchArguments) : async () {
    //     assetCanister.delete_batch(caller, args);
    // };

    // public shared func list_permitted(args : HttpAssets.ListPermitted) : async ([Principal]) {
    //     assetCanister.list_permitted(args);
    // };

    // public shared ({ caller }) func take_ownership() : async () {
    //     await* assetCanister.take_ownership(caller);
    // };

    // public shared ({ caller }) func get_configuration() : async (HttpAssets.ConfigurationResponse) {
    //     assetCanister.get_configuration(caller);
    // };

    // public shared ({ caller }) func configure(args : HttpAssets.ConfigureArguments) : async () {
    //     assetCanister.configure(caller, args);
    // };

    // public shared func certified_tree(args : {}) : async (HttpAssets.CertifiedTree) {
    //     assetCanister.certified_tree(args);
    // };
    // public shared func validate_grant_permission(args : HttpAssets.GrantPermission) : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_grant_permission(args);
    // };

    // public shared func validate_revoke_permission(args : HttpAssets.RevokePermission) : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_revoke_permission(args);
    // };

    // public shared func validate_take_ownership() : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_take_ownership();
    // };

    // public shared func validate_commit_proposed_batch(args : HttpAssets.CommitProposedBatchArguments) : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_commit_proposed_batch(args);
    // };

    // public shared func validate_configure(args : HttpAssets.ConfigureArguments) : async (Result.Result<Text, Text>) {
    //     assetCanister.validate_configure(args);
    // };

    public shared ({ caller }) func add_protected_route(path : Text) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.addProtectedRoute(path);
    };

    public shared ({ caller }) func update_route_cmacs(path : Text, new_cmacs : [Text]) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.updateRouteCmacs(path, new_cmacs);
    };

    public shared ({ caller }) func append_route_cmacs(path : Text, new_cmacs : [Text]) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.appendRouteCmacs(path, new_cmacs);
    };

    public query func get_route_protection(path : Text) : async ?ProtectedRoutes.ProtectedRoute {
        protected_routes_storage.getRoute(path);
    };

    public query func get_route_cmacs(path : Text) : async [Text] {
        protected_routes_storage.getRouteCmacs(path);
    };

    public query func listProtectedRoutesSummary() : async [(Text, Nat)] {
        protected_routes_storage.listProtectedRoutesSummary();
    };

    // ============================================
    // THEME MANAGEMENT FUNCTIONS (Admin Only)
    // ============================================

    public shared ({ caller }) func setTheme(primary: Text, secondary: Text) : async Theme.Theme {
        assert (caller == initializer);
        themeManager.setTheme(primary, secondary)
    };

    public query func getTheme() : async Theme.Theme {
        themeManager.getTheme()
    };

    public shared ({ caller }) func resetTheme() : async Theme.Theme {
        assert (caller == initializer);
        themeManager.resetTheme()
    };

    // ============================================
    // BUTTONS MANAGEMENT FUNCTIONS (Admin Only)
    // ============================================

    public shared ({ caller }) func addButton(buttonText: Text, buttonLink: Text) : async Nat {
        assert (caller == initializer);
        buttonsManager.addButton(buttonText, buttonLink)
    };

    public shared ({ caller }) func updateButton(index: Nat, buttonText: Text, buttonLink: Text) : async Bool {
        assert (caller == initializer);
        buttonsManager.updateButton(index, buttonText, buttonLink)
    };

    public shared ({ caller }) func deleteButton(index: Nat) : async Bool {
        assert (caller == initializer);
        buttonsManager.deleteButton(index)
    };

    public query func getButton(index: Nat) : async ?Buttons.Button {
        buttonsManager.getButton(index)
    };

    public query func getAllButtons() : async [Buttons.Button] {
        buttonsManager.getAllButtons()
    };

    public query func getButtonCount() : async Nat {
        buttonsManager.getButtonCount()
    };

    public shared ({ caller }) func clearAllButtons() : async () {
        assert (caller == initializer);
        buttonsManager.clearAllButtons()
    };

};
