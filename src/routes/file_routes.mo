import Blob "mo:core/Blob";
import Liminal "mo:liminal";
import RouteContext "mo:liminal/RouteContext";
import Router "mo:liminal/Router";
import FileAccess "../file_access";
import Files "../files";
import SneakerwebClaims "../sneakerweb_claims";

module {
    public type StreamingCallbackResponse = {
        body : Blob;
        token : ?Blob;
    };

    public func routes(
        streamingCallback : shared query (Blob) -> async StreamingCallbackResponse,
        fileStorage : Files.FileStorage,
        fileAccess : FileAccess.Access,
        sneakerwebClaims : SneakerwebClaims.Store,
    ) : [Router.RouteConfig] {
        [
            Router.get(
                "/api/stream/{filename}",
                #query_(
                    func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                        let filename = ctx.getRouteParam("filename");
                        if (sneakerwebClaims.isPrivatePackageFile(filename)) {
                            return ctx.buildResponse(#forbidden, #text("Private package access required"));
                        };
                        let token = switch (ctx.getQueryParam("token")) {
                            case (?value) value;
                            case null return ctx.buildResponse(#forbidden, #text("Invalid or expired token"));
                        };
                        if (not fileAccess.validateToken(token, filename)) {
                            return ctx.buildResponse(#forbidden, #text("Invalid or expired token"));
                        };
                        switch (fileStorage.getFileStartWithSignature(filename, token)) {
                            case null ctx.buildResponse(#notFound, #error(#message("File not found")));
                            case (?start) {
                                let strategy = switch (start.nextToken) {
                                    case null null;
                                    case (?nextToken) ?#callback({
                                        callback = streamingCallback;
                                        token = Blob.fromArray(Files.tokenToBlob(nextToken));
                                    });
                                };
                                {
                                    statusCode = 200;
                                    headers = [
                                        ("Content-Type", start.contentType),
                                        ("Cache-Control", "private, no-store, max-age=0"),
                                        ("Access-Control-Allow-Origin", "*"),
                                        ("X-Content-Type-Options", "nosniff"),
                                    ];
                                    body = ?Blob.fromArray(start.chunk);
                                    streamingStrategy = strategy;
                                };
                            };
                        };
                    }
                ),
            ),
            Router.get(
                "/files/{filename}",
                #query_(
                    func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                        ctx.buildResponse(#forbidden, #text("Access via NFC required"));
                    }
                ),
            ),
        ];
    };
};
