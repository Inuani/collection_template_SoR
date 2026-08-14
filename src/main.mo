import Liminal "mo:liminal";
import Array "mo:core/Array";
import Principal "mo:core/Principal";
import Random "mo:core/Random";
import Error "mo:core/Error";
import AssetsMiddleware "mo:liminal/Middleware/Assets";
import CORSMiddleware "middleware/cors";
import NFCMiddleware "middleware/nfc";
import HttpAssets "mo:http-assets@0";
import AssetCanister "mo:liminal/AssetCanister";
import ProtectedRoutes "nfc_protec_routes";
import Routes "routes";
import FileAccess "file_access";
import Files "files";
import Collection "collection";
import Result "mo:core/Result";
import RouterMiddleware "mo:liminal/Middleware/Router";
import Blob "mo:base/Blob";
import Theme "utils/theme";
import Buttons "utils/buttons";
import CollectionService "services/collection_service";
import AssetService "services/asset_service";
import KnitworkProtocol "knitwork_protocol";
import KnitworkStore "knitwork_store";
import AccessControl "access_control";
import SneakerwebClaims "sneakerweb_claims";

shared ({ caller = initializer }) persistent actor class Actor() = self {

    transient let canisterId = Principal.fromActor(self);
    type ChunkId = Files.ChunkId;

    var assetStableData = HttpAssets.init_stable_store(canisterId, initializer);
    assetStableData := HttpAssets.upgrade_stable_store(assetStableData);

    let protectedRoutesState = ProtectedRoutes.init();
    transient let protected_routes_storage = ProtectedRoutes.RoutesStorage(protectedRoutesState);

    let sneakerwebClaimsState = SneakerwebClaims.init();
    transient let sneakerwebClaims = SneakerwebClaims.Store(sneakerwebClaimsState, canisterId);

    let fileStorageState = Files.init();
    transient let file_storage = Files.FileStorage(fileStorageState);

    // This secret is generated inside the canister and survives upgrades. It
    // replaces the repository-wide static key formerly used by file URLs.
    let fileAccessState = FileAccess.init();
    transient let fileAccess = FileAccess.Access(fileAccessState);

    let collectionState = Collection.init();
    transient let collection = Collection.Collection(collectionState);

    let knitworkState = KnitworkStore.init();
    transient let knitworkStore = KnitworkStore.Store(
        knitworkState,
        canisterId,
        func(itemId : Nat) : Bool {
            switch (collection.getItem(itemId)) {
                case (?_) { true };
                case null { false };
            };
        },
        func(scan : KnitworkStore.PhysicalScanAttempt) : Bool {
            protected_routes_storage.validatePhysicalScan({
                path = scan.path;
                uid = scan.uid;
                counter = scan.counter;
                cmac = scan.cmac;
            });
        },
        func(scans : [KnitworkStore.PhysicalScanAttempt]) : Bool {
            protected_routes_storage.commitPhysicalScans(
                Array.map<KnitworkStore.PhysicalScanAttempt, ProtectedRoutes.PhysicalScanAttempt>(
                    scans,
                    func(scan) {
                        {
                            path = scan.path;
                            uid = scan.uid;
                            counter = scan.counter;
                            cmac = scan.cmac;
                        };
                    },
                )
            );
        },
    );

    type KnitworkPeer = actor {
        confirm_meeting : (KnitworkProtocol.ConfirmMeetingRequest) -> async KnitworkProtocol.MeetingResult;
    };

    // Preserved for the Collection theme feature.
    let themeState = Theme.init();
    transient let themeManager = Theme.ThemeManager(themeState);

    let buttonsState = Buttons.init();
    transient let buttonsManager = Buttons.ButtonsManager(buttonsState);

    transient let collectionService = CollectionService.make(initializer, collection);

    transient let setPermissions : HttpAssets.SetPermissions = {
        commit = [initializer];
        manage_permissions = [initializer];
        prepare = [initializer];
    };
    transient var assetStore = HttpAssets.Assets(assetStableData, ?setPermissions);
    transient var assetCanister = AssetCanister.AssetCanister(assetStore);
    transient let assetService = AssetService.make(assetCanister);

    transient let assetMiddlewareConfig : AssetsMiddleware.Config = {
        store = assetStore;
    };

    // Liminal compatible streaming callback
    // Types:
    // Token: Blob
    // Response: { body: Blob; token: ?Blob } (non-optional async result)
    public type StreamingCallbackResponse = {
        body : Blob;
        token : ?Blob;
    };

    public query func streamingCallback(token : Blob) : async StreamingCallbackResponse {
        switch (Files.tokenFromBlob(Blob.toArray(token))) {
            case (null) { ({ body = Blob.fromArray([]); token = null }) };
            case (?t) {
                switch (
                    file_storage.processStreamingCallbackWithValidator(
                        t,
                        func(signature : Text, filename : Text) : Bool {
                            if (sneakerwebClaims.isPackageAuthorized(signature, filename)) {
                                true;
                            } else if (sneakerwebClaims.isPrivatePackageFile(filename)) {
                                false;
                            } else {
                                fileAccess.validateToken(signature, filename);
                            };
                        },
                    )
                ) {
                    case (null) ({ body = Blob.fromArray([]); token = null });
                    case (?res) {
                        let nextToken = switch (res.token) {
                            case (null) null;
                            case (?nt) ?Blob.fromArray(Files.tokenToBlob(nt));
                        };
                        ({
                            body = Blob.fromArray(res.body);
                            token = nextToken;
                        });
                    };
                };
            };
        };
    };

    transient let app = Liminal.App({
        middleware = [
            CORSMiddleware.createCORSMiddleware(),
            NFCMiddleware.createNFCProtectionMiddleware(
                protected_routes_storage,
                fileAccess,
                sneakerwebClaims,
            ),
            RouterMiddleware.new(
                Routes.routerConfig(
                    canisterId,
                    streamingCallback,
                    collection,
                    func(itemId : Nat) : [KnitworkProtocol.MeetingRecord] {
                        knitworkStore.getItemMeetings(itemId);
                    },
                    file_storage,
                    fileAccess,
                    sneakerwebClaims,
                )
            ),
            AssetsMiddleware.new(assetMiddlewareConfig),
        ];
        errorSerializer = Liminal.defaultJsonErrorSerializer;
        candidRepresentationNegotiator = Liminal.defaultCandidRepresentationNegotiator;
        logger = Liminal.buildDebugLogger(#info);
        urlNormalization = {
            usernameIsCaseSensitive = false;
            pathIsCaseSensitive = false;
            queryKeysAreCaseSensitive = false;
            removeEmptyPathSegments = true;
            resolvePathDotSegments = true;
            preserveTrailingSlash = false;
        };
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

    public shared ({ caller }) func upload(chunk : [Nat8]) : async () {
        assert AccessControl.isInitializer(caller, initializer);
        file_storage.upload(chunk);
    };

    public shared ({ caller }) func uploadFinalize(title : Text, artist : Text, contentType : Text) : async Result.Result<Text, Text> {
        assert AccessControl.isInitializer(caller, initializer);
        file_storage.uploadFinalize(title, artist, contentType);
    };

    public shared query ({ caller }) func getFileChunk(title : Text, chunkId : ChunkId) : async ?{
        chunk : [Nat8];
        totalChunks : Nat;
        contentType : Text;
        title : Text;
        artist : Text;
    } {
        assert AccessControl.isInitializer(caller, initializer);
        file_storage.getFileChunk(title, chunkId);
    };

    public shared query ({ caller }) func getFileStart(title : Text) : async ?{
        chunk : [Nat8];
        totalChunks : Nat;
        contentType : Text;
        title : Text;
        artist : Text;
        nextToken : ?Files.StreamingCallbackToken;
    } {
        assert AccessControl.isInitializer(caller, initializer);
        switch (fileAccess.generateToken(title)) {
            case null null;
            case (?signature) file_storage.getFileStartWithSignature(title, signature);
        };
    };

    public shared query ({ caller }) func listFiles() : async [(Text, Text, Text)] {
        assert AccessControl.isInitializer(caller, initializer);
        file_storage.listFiles();
    };

    public shared ({ caller }) func deleteFile(title : Text) : async Bool {
        assert AccessControl.isInitializer(caller, initializer);
        file_storage.deleteFile(title);
    };

    public shared query ({ caller }) func getStoredFileCount() : async Nat {
        assert AccessControl.isInitializer(caller, initializer);
        file_storage.getStoredFileCount();
    };

    public shared ({ caller }) func rotate_file_access_secret() : async () {
        assert AccessControl.isInitializer(caller, initializer);
        let secret = await Random.blob();
        assert fileAccess.installSecret(secret);
    };

    public shared query ({ caller }) func get_file_access_status() : async {
        configured : Bool;
    } {
        assert AccessControl.isInitializer(caller, initializer);
        { configured = fileAccess.isConfigured() };
    };

    // ============================================
    // COLLECTION MANAGEMENT FUNCTIONS (Admin Only)
    // ============================================

    public shared ({ caller }) func addCollectionItem(
        name : Text,
        thumbnailUrl : Text,
        imageUrl : Text,
        description : Text,
        rarity : Text,
        attributes : [(Text, Text)],
    ) : async Nat {
        collectionService.addItem(caller, name, thumbnailUrl, imageUrl, description, rarity, attributes);
    };

    public shared ({ caller }) func updateCollectionItem(
        id : Nat,
        name : Text,
        thumbnailUrl : Text,
        imageUrl : Text,
        description : Text,
        rarity : Text,
        attributes : [(Text, Text)],
    ) : async Result.Result<(), Text> {
        collectionService.updateItem(caller, id, name, thumbnailUrl, imageUrl, description, rarity, attributes);
    };

    public shared ({ caller }) func deleteCollectionItem(id : Nat) : async Result.Result<(), Text> {
        assert AccessControl.isInitializer(caller, initializer);
        switch (collectionService.getItem(id)) {
            case null {
                return #err("Item with ID " # debug_show (id) # " not found");
            };
            case (?_) {};
        };
        switch (
            Collection.deletionBlockReason(
                id,
                protected_routes_storage.hasProtectedRoute(ProtectedRoutes.itemRoute(id)),
                knitworkStore.getItemMeetings(id).size() > 0,
            )
        ) {
            case (?message) { return #err(message) };
            case null {};
        };
        switch (collectionService.deleteItem(caller, id)) {
            case (#ok()) {
                ignore sneakerwebClaims.removeCard(id);
                #ok();
            };
            case (#err(message)) { #err(message) };
        };
    };

    public query func getCollectionItem(id : Nat) : async ?Collection.PublicItem {
        switch (collectionService.getItem(id)) {
            case (?item) ?Collection.toPublicItem(item);
            case null null;
        };
    };

    public query func getAllCollectionItems() : async [Collection.PublicItem] {
        Array.map<Collection.Item, Collection.PublicItem>(
            collectionService.getAllItems(),
            Collection.toPublicItem,
        );
    };

    public query func getCollectionItemCount() : async Nat {
        collectionService.getItemCount();
    };

    public shared ({ caller }) func setCollectionName(name : Text) : async () {
        collectionService.setCollectionName(caller, name);
    };

    public shared ({ caller }) func setCollectionDescription(description : Text) : async () {
        collectionService.setCollectionDescription(caller, description);
    };

    public query func getCollectionName() : async Text {
        collectionService.getCollectionName();
    };

    public query func getCollectionDescription() : async Text {
        collectionService.getCollectionDescription();
    };

    // ============================================
    // KNITWORK COLLECTION PROTOCOL V1
    // ============================================

    public query func protocol_info() : async KnitworkProtocol.ProtocolInfo {
        knitworkStore.protocolInfo();
    };

    public query func get_trusted_hub() : async ?Principal {
        knitworkStore.getTrustedHub();
    };

    public shared ({ caller }) func set_trusted_hub(
        hub : ?Principal
    ) : async KnitworkProtocol.UnitResult {
        if (caller != initializer) {
            return #err("caller is not the Collection initializer");
        };
        switch (hub) {
            case (?principal) {
                if (Principal.isAnonymous(principal)) {
                    return #err("trusted Hub cannot be anonymous");
                };
            };
            case null {};
        };
        knitworkStore.setTrustedHub(hub);
        #ok();
    };

    public shared ({ caller }) func prepare_meeting(
        request : KnitworkProtocol.PrepareMeetingRequest
    ) : async KnitworkProtocol.PrepareResult {
        knitworkStore.prepareMeeting(caller, request);
    };

    public shared ({ caller }) func finalize_meeting(
        request : KnitworkProtocol.FinalizeMeetingRequest
    ) : async KnitworkProtocol.MeetingResult {
        let localRecord = switch (knitworkStore.beginFinalize(caller, request)) {
            case (#err(message)) { return #err(message) };
            case (#ok(record)) { record };
        };

        switch (localRecord.status) {
            case (#confirmed) { return #ok(localRecord) };
            case (#pending) {};
        };

        // The pending local record is durable before the first await. Retrying
        // this method safely replays confirmations with the same meeting_id.
        for (peer in request.prepared_peers.vals()) {
            let peerActor : KnitworkPeer = actor (Principal.toText(peer.collection));
            let confirmation : KnitworkProtocol.MeetingResult = try {
                await peerActor.confirm_meeting({
                    event = request.event;
                    handoff_token = peer.handoff_token;
                });
            } catch (error) {
                return #err(
                    "peer confirmation rejected by " #
                    Principal.toText(peer.collection) #
                    ": " # Error.message(error)
                );
            };

            switch (confirmation) {
                case (#err(message)) {
                    return #err(
                        "peer confirmation failed for " #
                        Principal.toText(peer.collection) #
                        ": " # message
                    );
                };
                case (#ok(record)) {
                    switch (
                        knitworkStore.validatePeerConfirmation(
                            peer.collection,
                            request.event,
                            record,
                        )
                    ) {
                        case (#ok()) {};
                        case (#err(message)) {
                            return #err(
                                "invalid peer confirmation from " #
                                Principal.toText(peer.collection) #
                                ": " # message
                            );
                        };
                    };
                };
            };
        };

        knitworkStore.completeFinalization(request.event);
    };

    public shared ({ caller }) func confirm_meeting(
        request : KnitworkProtocol.ConfirmMeetingRequest
    ) : async KnitworkProtocol.MeetingResult {
        knitworkStore.confirmMeeting(caller, request);
    };

    public shared query ({ caller }) func get_meeting(
        meeting_id : Text
    ) : async ?KnitworkProtocol.MeetingRecord {
        assert AccessControl.isInitializer(caller, initializer);
        knitworkStore.getMeeting(meeting_id);
    };

    public shared query ({ caller }) func get_item_meetings(
        item_id : Nat
    ) : async [KnitworkProtocol.MeetingRecord] {
        assert AccessControl.isInitializer(caller, initializer);
        knitworkStore.getItemMeetings(item_id);
    };

    assetStore.set_streaming_callback(http_request_streaming_callback);

    public shared query func list(args : {}) : async [HttpAssets.AssetDetails] {
        assetService.list(args);
    };

    public shared ({ caller }) func delete_asset(args : HttpAssets.DeleteAssetArguments) : async () {
        assetService.deleteAsset(caller, args);
    };

    public shared ({ caller }) func create_batch(args : {}) : async (HttpAssets.CreateBatchResponse) {
        assetService.createBatch(caller, args);
    };

    public shared ({ caller }) func create_chunk(args : HttpAssets.CreateChunkArguments) : async (HttpAssets.CreateChunkResponse) {
        assetService.createChunk(caller, args);
    };

    public shared ({ caller }) func create_chunks(args : HttpAssets.CreateChunksArguments) : async HttpAssets.CreateChunksResponse {
        await assetService.createChunks(caller, args);
    };

    public shared ({ caller }) func commit_batch(args : HttpAssets.CommitBatchArguments) : async () {
        await assetService.commitBatch(caller, args);
    };

    public shared ({ caller }) func add_protected_route(path : Text) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.addProtectedRoute(path);
    };

    public shared ({ caller }) func update_route_cmacs(path : Text, uid : Text, new_cmacs : [Text]) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.updateRouteCmacs(path, uid, new_cmacs);
    };

    public shared ({ caller }) func append_route_cmacs(path : Text, uid : Text, new_cmacs : [Text]) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.appendRouteCmacs(path, uid, new_cmacs);
    };

    public shared query ({ caller }) func get_route_protection(path : Text) : async ?ProtectedRoutes.ProtectedRoute {
        assert AccessControl.isInitializer(caller, initializer);
        protected_routes_storage.getRoute(path);
    };

    public shared query ({ caller }) func get_route_cmacs(path : Text, uid : Text) : async [Text] {
        assert AccessControl.isInitializer(caller, initializer);
        protected_routes_storage.getRouteCmacs(path, uid);
    };

    public query func listProtectedRoutesSummary() : async [(Text, Nat)] {
        protected_routes_storage.listProtectedRoutesSummary();
    };

    // ============================================
    // SNEAKERWEB NFC CLAIMS (no user identity)
    // ============================================

    public shared ({ caller }) func set_sneakerweb_pwa_url(
        url : Text
    ) : async Result.Result<(), Text> {
        assert AccessControl.isInitializer(caller, initializer);
        if (sneakerwebClaims.setPwaImportUrl(url)) {
            #ok();
        } else {
            #err("PWA URL must use HTTPS (or localhost for development) and contain no fragment");
        };
    };

    public shared ({ caller }) func configure_sneakerweb_card(
        item_id : Nat,
        domain : Text,
        file_name : Text,
    ) : async Result.Result<(), Text> {
        assert AccessControl.isInitializer(caller, initializer);
        switch (collection.getItem(item_id)) {
            case null { return #err("Item with ID " # debug_show (item_id) # " not found") };
            case (?_) {};
        };
        if (not file_storage.hasFile(file_name)) {
            return #err("Private file '" # file_name # "' not found; upload it before configuring the card");
        };
        if (sneakerwebClaims.configureCard(item_id, domain, file_name)) {
            #ok();
        } else {
            #err("domain must be lowercase SHA-256 hex and file_name must use only letters, digits, dot, dash, underscore, or tilde");
        };
    };

    public shared ({ caller }) func remove_sneakerweb_card(
        item_id : Nat
    ) : async Bool {
        assert AccessControl.isInitializer(caller, initializer);
        sneakerwebClaims.removeCard(item_id);
    };

    public shared query ({ caller }) func get_sneakerweb_claim_config() : async {
        pwa_import_url : Text;
        cards : [SneakerwebClaims.CardConfig];
    } {
        assert AccessControl.isInitializer(caller, initializer);
        {
            pwa_import_url = sneakerwebClaims.getPwaImportUrl();
            cards = sneakerwebClaims.listCards();
        };
    };

    // ============================================
    // THEME MANAGEMENT FUNCTIONS (Admin Only)
    // ============================================

    public shared ({ caller }) func setTheme(primary : Text, secondary : Text) : async Theme.Theme {
        assert AccessControl.isInitializer(caller, initializer);
        themeManager.setTheme(primary, secondary);
    };

    public query func getTheme() : async Theme.Theme {
        themeManager.getTheme();
    };

    public shared ({ caller }) func resetTheme() : async Theme.Theme {
        assert AccessControl.isInitializer(caller, initializer);
        themeManager.resetTheme();
    };

    public shared ({ caller }) func addButton(buttonText : Text, buttonLink : Text) : async Nat {
        assert (caller == initializer);
        buttonsManager.addButton(buttonText, buttonLink);
    };

    public shared ({ caller }) func updateButton(index : Nat, buttonText : Text, buttonLink : Text) : async Bool {
        assert (caller == initializer);
        buttonsManager.updateButton(index, buttonText, buttonLink);
    };

    public shared ({ caller }) func deleteButton(index : Nat) : async Bool {
        assert (caller == initializer);
        buttonsManager.deleteButton(index);
    };

    public query func getButton(index : Nat) : async ?Buttons.Button {
        buttonsManager.getButton(index);
    };

    public query func getAllButtons() : async [Buttons.Button] {
        buttonsManager.getAllButtons();
    };

    public query func getButtonCount() : async Nat {
        buttonsManager.getButtonCount();
    };

    public shared ({ caller }) func clearAllButtons() : async () {
        assert (caller == initializer);
        buttonsManager.clearAllButtons();
    };

};
