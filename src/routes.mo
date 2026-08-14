import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Json "mo:json@1";
import Liminal "mo:liminal";
import Router "mo:liminal/Router";
import Collection "collection";
import CollectionView "collection_view";
import FileAccess "file_access";
import Files "files";
import FileRoutes "routes/file_routes";
import SneakerwebRoutes "routes/sneakerweb_routes";
import SneakerwebClaims "sneakerweb_claims";

module {
    public type StreamingCallbackResponse = {
        body : Blob;
        token : ?Blob;
    };

    func publicJsonResponse(statusCode : Nat, value : Json.Json) : Liminal.HttpResponse {
        {
            statusCode;
            headers = [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Access-Control-Allow-Origin", "*"),
                ("Cache-Control", "public, max-age=60"),
                ("X-Content-Type-Options", "nosniff"),
            ];
            body = ?Text.encodeUtf8(Json.stringify(value, null));
            streamingStrategy = null;
        };
    };

    func itemLookupJson(
        canisterId : Principal,
        collection : Collection.Collection,
        item : Collection.Item,
    ) : Json.Json {
        Json.obj([
            ("schema_version", Json.int(1)),
            (
                "collection",
                Json.obj([
                    ("principal", Json.str(Principal.toText(canisterId))),
                    ("name", Json.str(collection.getCollectionName())),
                ]),
            ),
            (
                "item",
                Json.obj([
                    ("id", Json.str(Nat.toText(item.id))),
                    ("name", Json.str(item.name)),
                ]),
            ),
        ]);
    };

    func itemLookupError(code : Text) : Json.Json {
        Json.obj([
            ("schema_version", Json.int(1)),
            ("error", Json.str(code)),
        ]);
    };

    func collectionRoutes(
        canisterId : Principal,
        collection : Collection.Collection,
        getItemMeetings : CollectionView.GetItemMeetings,
    ) : [Router.RouteConfig] {
        [
            Router.get(
                "/",
                #query_(func(ctx) {
                    ctx.buildResponse(
                        #ok,
                        #html(CollectionView.generateCollectionPage(collection, getItemMeetings)),
                    );
                }),
            ),
            Router.get(
                "/api/knitwork/v1/items/{id}",
                #query_(func(ctx) {
                    let id = switch (Nat.fromText(ctx.getRouteParam("id"))) {
                        case (?value) value;
                        case null return publicJsonResponse(400, itemLookupError("invalid_item_id"));
                    };
                    switch (collection.getItem(id)) {
                        case (?item) publicJsonResponse(200, itemLookupJson(canisterId, collection, item));
                        case null publicJsonResponse(404, itemLookupError("item_not_found"));
                    };
                }),
            ),
            Router.get(
                "/nfc/item/{id}",
                #query_(func(ctx) {
                    let id = switch (Nat.fromText(ctx.getRouteParam("id"))) {
                        case (?value) value;
                        case null return ctx.buildResponse(#notFound, #text("Objet introuvable"));
                    };
                    switch (collection.getItem(id)) {
                        case null ctx.buildResponse(#notFound, #text("Objet introuvable"));
                        case (?_) ctx.httpContext.buildRedirectResponse("/item/" # Nat.toText(id), false);
                    };
                }),
            ),
            Router.get(
                "/item/{id}",
                #query_(func(ctx) {
                    let id = switch (Nat.fromText(ctx.getRouteParam("id"))) {
                        case (?value) value;
                        case null return ctx.buildResponse(#notFound, #html(CollectionView.generateNotFoundPage(0)));
                    };
                    switch (collection.getItem(id)) {
                        case null ctx.buildResponse(#notFound, #html(CollectionView.generateNotFoundPage(id)));
                        case (?_) {
                            ctx.buildResponse(
                                #ok,
                                #html(
                                    CollectionView.generateItemPage(
                                        collection,
                                        canisterId,
                                        id,
                                        getItemMeetings(id),
                                    )
                                ),
                            );
                        };
                    };
                }),
            ),
            Router.get(
                "/collection",
                #query_(func(ctx) {
                    ctx.buildResponse(
                        #ok,
                        #html(CollectionView.generateCollectionPage(collection, getItemMeetings)),
                    );
                }),
            ),
        ];
    };

    public func routerConfig(
        canisterId : Principal,
        streamingCallback : shared query (Blob) -> async StreamingCallbackResponse,
        collection : Collection.Collection,
        getItemMeetings : CollectionView.GetItemMeetings,
        fileStorage : Files.FileStorage,
        fileAccess : FileAccess.Access,
        sneakerwebClaims : SneakerwebClaims.Store,
    ) : Router.Config {
        {
            prefix = null;
            identityRequirement = null;
            routes = Array.flatten([
                SneakerwebRoutes.routes(streamingCallback, fileStorage, sneakerwebClaims),
                collectionRoutes(canisterId, collection, getItemMeetings),
                FileRoutes.routes(streamingCallback, fileStorage, fileAccess, sneakerwebClaims),
            ]);
        };
    };
};
