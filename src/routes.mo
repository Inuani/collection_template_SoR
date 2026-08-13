import Router "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal "mo:liminal";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Blob "mo:core/Blob";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Principal "mo:core/Principal";
import Json "mo:json@1";
import Collection "collection";
import CollectionView "collection_view";
import Files "files";

module Routes {
    public type StreamingCallbackResponse = {
        body : Blob;
        token : ?Blob;
    };

    func publicJsonResponse(statusCode : Nat, value : Json.Json) : Liminal.HttpResponse {
        let body = Text.encodeUtf8(Json.stringify(value, null));
        {
            statusCode;
            headers = [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Access-Control-Allow-Origin", "*"),
                ("Cache-Control", "public, max-age=60"),
                ("X-Content-Type-Options", "nosniff"),
            ];
            body = ?body;
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

    public func routerConfig(
        canisterId : Principal,
        streamingCallback : shared query (Blob) -> async StreamingCallbackResponse,
        collection : Collection.Collection,
        getItemMeetings : CollectionView.GetItemMeetings,
        fileStorage : Files.FileStorage,
    ) : Router.Config {
        {
            prefix = null;
            identityRequirement = null;
            routes = Array.flatten([
                [
                    Router.get(
                        "/",
                        #query_(
                            func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                                let html = CollectionView.generateCollectionPage(collection, getItemMeetings);
                                ctx.buildResponse(#ok, #html(html));
                            }
                        ),
                    ),
                    Router.get(
                        "/api/knitwork/v1/items/{id}",
                        #query_(
                            func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                                let idText = ctx.getRouteParam("id");
                                let id = switch (Nat.fromText(idText)) {
                                    case (?value) value;
                                    case null return publicJsonResponse(400, itemLookupError("invalid_item_id"));
                                };
                                switch (collection.getItem(id)) {
                                    case (?item) publicJsonResponse(200, itemLookupJson(canisterId, collection, item));
                                    case null publicJsonResponse(404, itemLookupError("item_not_found"));
                                };
                            }
                        ),
                    ),
                    // Dedicated NFC entry. The middleware validates the tag on
                    // this exact path, then the browser is redirected to the
                    // public item page, which remains freely navigable.
                    Router.get(
                        "/nfc/item/{id}",
                        #query_(
                            func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                                let idText = ctx.getRouteParam("id");
                                let id = switch (Nat.fromText(idText)) {
                                    case (?value) value;
                                    case null return ctx.buildResponse(#notFound, #text("Objet introuvable"));
                                };
                                switch (collection.getItem(id)) {
                                    case null ctx.buildResponse(#notFound, #text("Objet introuvable"));
                                    case (?_) ctx.httpContext.buildRedirectResponse("/item/" # Nat.toText(id), false);
                                };
                            }
                        ),
                    ),
                    Router.get(
                        "/item/{id}",
                        #query_(
                            func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                                let idText = ctx.getRouteParam("id");

                                let id = switch (Nat.fromText(idText)) {
                                    case (?num) num;
                                    case null {
                                        let html = CollectionView.generateNotFoundPage(0);
                                        return ctx.buildResponse(#notFound, #html(html));
                                    };
                                };

                                switch (collection.getItem(id)) {
                                    case null {
                                        ctx.buildResponse(#notFound, #html(CollectionView.generateNotFoundPage(id)));
                                    };
                                    case (?_) {
                                        let html = CollectionView.generateItemPage(
                                            collection,
                                            canisterId,
                                            id,
                                            getItemMeetings(id),
                                        );
                                        ctx.buildResponse(#ok, #html(html));
                                    };
                                };
                            }
                        ),
                    ),
                    Router.get(
                        "/collection",
                        #query_(
                            func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                                let html = CollectionView.generateCollectionPage(collection, getItemMeetings);
                                ctx.buildResponse(#ok, #html(html));
                            }
                        ),
                    ),
                ],
                [

                    // Streaming file access
                    // Returns the first chunk directly and provides a streaming callback for the rest
                    // Streaming file access (Protected by Token)
                    Router.get(
                        "/api/stream/{filename}",
                        #query_(
                            func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                                let filename = ctx.getRouteParam("filename");
                                let token = switch (ctx.httpContext.request.url) {
                                    case (url) {
                                        var t : ?Text = null;
                                        let queries = Iter.toArray(Text.split(url, #char '?'));
                                        if (queries.size() >= 2) {
                                            let params = Iter.toArray(Text.split(queries[1], #char '&'));
                                            for (param in params.vals()) {
                                                let keyValue = Iter.toArray(Text.split(param, #char '='));
                                                if (keyValue.size() == 2 and keyValue[0] == "token") {
                                                    t := ?keyValue[1];
                                                };
                                            };
                                        };
                                        t;
                                    };
                                };

                                // Validate Token
                                let isValid = switch (token) {
                                    case (null) false;
                                    case (?t) fileStorage.validateToken(t, filename);
                                };

                                if (not isValid) {
                                    return ctx.buildResponse(#forbidden, #text("Invalid or expired token"));
                                };

                                // Serve File
                                switch (fileStorage.getFileStart(filename)) {
                                    case (null) {
                                        ctx.buildResponse(#notFound, #error(#message("File not found")));
                                    };
                                    case (?start) {
                                        let strategy = switch (start.nextToken) {
                                            case (null) null;
                                            case (?token) ?#callback({
                                                callback = streamingCallback;
                                                token = Blob.fromArray(Files.tokenToBlob(token));
                                            });
                                        };

                                        {
                                            statusCode = 200;
                                            headers = [
                                                ("Content-Type", start.contentType),
                                                ("Cache-Control", "public, max-age=31536000"),
                                                ("Access-Control-Allow-Origin", "*"),
                                                ("Accept-Ranges", "bytes"),
                                            ];
                                            body = ?Blob.fromArray(start.chunk);
                                            streamingStrategy = strategy;
                                        };
                                    };
                                };
                            }
                        ),
                    ),

                    // HTML Wrapper for Files (Protected by NFC Middleware)
                    Router.get(
                        "/files/{filename}",
                        #query_(
                            func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                                // This route is hit AFTER the middleware has validated the NFC UID.
                                // The middleware now returns the HTML directly if it validates successfully.
                                // HOWEVER, if the middleware passes through (e.g. for development or if configured that way),
                                // this route should probably also serve the HTML or just 403.

                                // Since our Middleware implementation *returns* the response on success,
                                // this route handler is effectively a fallback or for testing.

                                ctx.buildResponse(#forbidden, #text("Access via NFC required"));
                            }
                        ),
                    ),

                ],
            ]);
        };
    };
};
