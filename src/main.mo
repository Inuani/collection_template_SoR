import Liminal "mo:liminal";
import Array "mo:core/Array";
import Principal "mo:core/Principal";
import Error "mo:core/Error";
import AssetsMiddleware "mo:liminal/Middleware/Assets";
import CORSMiddleware "middleware/cors";
import NFCMiddleware "middleware/nfc";
import HttpAssets "mo:http-assets@0";
import AssetCanister "mo:liminal/AssetCanister";
import ProtectedRoutes "nfc_protec_routes";
import Routes "routes";
import Files "files";
import Collection "collection";
import Result "mo:core/Result";
import RouterMiddleware "mo:liminal/Middleware/Router";
import Blob "mo:base/Blob";
import Theme "utils/theme";
import Buttons "utils/buttons";
import FileService "services/file_service";
import CollectionService "services/collection_service";
import AssetService "services/asset_service";
import KnitworkProtocol "knitwork_protocol";
import KnitworkStore "knitwork_store";

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

    let buttonsState = Buttons.init();
    transient let buttonsManager = Buttons.ButtonsManager(buttonsState);

    transient let fileService = FileService.make(file_storage);
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
                switch (file_storage.processStreamingCallback(t)) {
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
            NFCMiddleware.createNFCProtectionMiddleware(protected_routes_storage, file_storage),
            RouterMiddleware.new(
                Routes.routerConfig(
                    canisterId,
                    streamingCallback,
                    collection,
                    func(itemId : Nat) : [KnitworkProtocol.MeetingRecord] {
                        knitworkStore.getItemMeetings(itemId);
                    },
                    file_storage,
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

    public func upload(chunk : [Nat8]) : async () {
        fileService.upload(chunk);
    };

    public func uploadFinalize(title : Text, artist : Text, contentType : Text) : async Result.Result<Text, Text> {
        fileService.uploadFinalize(title, artist, contentType);
    };

    public query func getFileChunk(title : Text, chunkId : ChunkId) : async ?{
        chunk : [Nat8];
        totalChunks : Nat;
        contentType : Text;
        title : Text;
        artist : Text;
    } {
        fileService.getFileChunk(title, chunkId);
    };

    public query func getFileStart(title : Text) : async ?{
        chunk : [Nat8];
        totalChunks : Nat;
        contentType : Text;
        title : Text;
        artist : Text;
        nextToken : ?Files.StreamingCallbackToken;
    } {
        file_storage.getFileStart(title);
    };

    public query func listFiles() : async [(Text, Text, Text)] {
        fileService.listFiles();
    };

    public func deleteFile(title : Text) : async Bool {
        fileService.deleteFile(title);
    };

    public query func getStoredFileCount() : async Nat {
        fileService.getStoredFileCount();
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
        collectionService.deleteItem(caller, id);
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

    public query func get_meeting(
        meeting_id : Text
    ) : async ?KnitworkProtocol.MeetingRecord {
        knitworkStore.getMeeting(meeting_id);
    };

    public query func get_item_meetings(
        item_id : Nat
    ) : async [KnitworkProtocol.MeetingRecord] {
        knitworkStore.getItemMeetings(item_id);
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
        assetService.list(args);
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
        assetService.deleteAsset(caller, args);
    };

    // public shared ({ caller }) func set_asset_properties(args : HttpAssets.SetAssetPropertiesArguments) : async () {
    //     assetCanister.set_asset_properties(caller, args);
    // };

    // public shared ({ caller }) func clear(args : HttpAssets.ClearArguments) : async () {
    //     assetCanister.clear(caller, args);
    // };

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

    public shared ({ caller }) func update_route_cmacs(path : Text, uid : Text, new_cmacs : [Text]) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.updateRouteCmacs(path, uid, new_cmacs);
    };

    public shared ({ caller }) func append_route_cmacs(path : Text, uid : Text, new_cmacs : [Text]) : async () {
        assert (caller == initializer);
        ignore protected_routes_storage.appendRouteCmacs(path, uid, new_cmacs);
    };

    public query func get_route_protection(path : Text) : async ?ProtectedRoutes.ProtectedRoute {
        protected_routes_storage.getRoute(path);
    };

    public query func get_route_cmacs(path : Text, uid : Text) : async [Text] {
        protected_routes_storage.getRouteCmacs(path, uid);
    };

    public query func listProtectedRoutesSummary() : async [(Text, Nat)] {
        protected_routes_storage.listProtectedRoutesSummary();
    };

    // ============================================
    // THEME MANAGEMENT FUNCTIONS (Admin Only)
    // ============================================

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
