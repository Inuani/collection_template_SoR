import Liminal "mo:liminal";
import Principal "mo:new-base/Principal";
// import Blob "mo:new-base/Blob";
// import Result "mo:new-base/Result";
import Error "mo:new-base/Error";
import AssetsMiddleware "mo:liminal/Middleware/Assets";
import HttpAssets "mo:http-assets";
import AssetCanister "mo:liminal/AssetCanister";
import Text "mo:new-base/Text";
import ProtectedRoutes "nfc_protec_routes";
import Routes "routes";

// import Router "mo:liminal/Router";
// import RouteContext "mo:liminal/RouteContext";
import RouterMiddleware "mo:liminal/Middleware/Router";
import App "mo:liminal/App";
import HttpContext "mo:liminal/HttpContext";

shared ({ caller = initializer }) actor class Actor() = self {

    let canisterId = Principal.fromActor(self);

    stable var assetStableData = HttpAssets.init_stable_store(canisterId, initializer);
    assetStableData := HttpAssets.upgrade_stable_store(assetStableData);

    stable let protectedRoutesState = ProtectedRoutes.init();
    let protected_routes_storage = ProtectedRoutes.RoutesStorage(protectedRoutesState);

    transient let setPermissions : HttpAssets.SetPermissions = {
        commit = [initializer];
        manage_permissions = [initializer];
        prepare = [initializer];
    };
    var assetStore = HttpAssets.Assets(assetStableData, ?setPermissions);
    var assetCanister = AssetCanister.AssetCanister(assetStore);

    let assetMiddlewareConfig : AssetsMiddleware.Config = {
        store = assetStore;
    };

    func createNFCProtectionMiddleware() : App.Middleware {
        {
            name = "NFC Protection";
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
                            if (not protected_routes_storage.verifyRouteAccess(path, url))
                            {
                                return
                                {
                                    statusCode = 403;
                                    headers = [("Content-Type", "text/html")];
                                    body = ?Text.encodeUtf8("Access Denied - Invalid NFC");
                                    streamingStrategy = null;
                                };
                            };
                        };
                    };
                };
                await* next();
            };
        };
    };


    let app = Liminal.App({
        middleware = [
            createNFCProtectionMiddleware(),
            AssetsMiddleware.new(assetMiddlewareConfig),
            RouterMiddleware.new(Routes.routerConfig(Principal.toText(canisterId))),
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

};
