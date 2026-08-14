import Blob "mo:core/Blob";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Text "mo:core/Text";
import Json "mo:json@1";
import Liminal "mo:liminal";
import RouteContext "mo:liminal/RouteContext";
import Router "mo:liminal/Router";
import Files "../files";
import SneakerwebClaims "../sneakerweb_claims";

module {
    public type StreamingCallbackResponse = {
        body : Blob;
        token : ?Blob;
    };

    public func claimJsonResponse(statusCode : Nat, value : Json.Json) : Liminal.HttpResponse {
        {
            statusCode;
            headers = [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Cache-Control", "no-store"),
                ("Pragma", "no-cache"),
                ("X-Content-Type-Options", "nosniff"),
            ];
            body = ?Text.encodeUtf8(Json.stringify(value, null));
            streamingStrategy = null;
        };
    };

    public func claimReceiptJson(receipt : SneakerwebClaims.Receipt) : Json.Json {
        Json.obj([
            ("schema_version", Json.int(1)),
            ("type", Json.str("proof-of-contact-claim")),
            ("acquisition", Json.str("nfc_scan")),
            ("claim_id", Json.str(receipt.claim_id)),
            ("claimed_at_ns", Json.str(Int.toText(receipt.claimed_at_ns))),
            (
                "issuer",
                Json.obj([
                    ("canister", Json.str(receipt.issuer)),
                    ("item_id", Json.str(Nat.toText(receipt.item_id))),
                ]),
            ),
            ("card", Json.obj([("domain", Json.str(receipt.domain))])),
            (
                "package",
                Json.obj([
                    ("transport", Json.str("private_post")),
                    ("token", Json.str(receipt.package_token)),
                    ("expires_at_ns", Json.str(Int.toText(receipt.package_expires_at_ns))),
                ]),
            ),
        ]);
    };

    public func claimErrorJson() : Json.Json {
        Json.obj([
            ("schema_version", Json.int(1)),
            ("error", Json.str("invalid_or_expired_claim")),
        ]);
    };

    public func packageErrorJson() : Json.Json {
        Json.obj([
            ("schema_version", Json.int(1)),
            ("error", Json.str("invalid_or_expired_package_access")),
        ]);
    };

    public func routes(
        streamingCallback : shared query (Blob) -> async StreamingCallbackResponse,
        fileStorage : Files.FileStorage,
        sneakerwebClaims : SneakerwebClaims.Store,
    ) : [Router.RouteConfig] {
        [
            Router.post(
                "/api/sneakerweb/v1/claims/{token}",
                #update(
                    #sync(
                        func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                            switch (sneakerwebClaims.redeem(ctx.getRouteParam("token"))) {
                                case (#ok(receipt)) claimJsonResponse(200, claimReceiptJson(receipt));
                                case (#err(_)) claimJsonResponse(404, claimErrorJson());
                            };
                        }
                    )
                ),
            ),
            Router.post(
                "/api/sneakerweb/v1/packages",
                #update(
                    #sync(
                        func(ctx : RouteContext.RouteContext) : Liminal.HttpResponse {
                            let token = switch (ctx.parseUtf8Body()) {
                                case (?value) value;
                                case null return claimJsonResponse(400, packageErrorJson());
                            };
                            let grant = switch (sneakerwebClaims.getPackage(token)) {
                                case (?value) value;
                                case null return claimJsonResponse(404, packageErrorJson());
                            };
                            let start = switch (
                                fileStorage.getFileStartWithSignature(grant.file_name, grant.token)
                            ) {
                                case (?value) value;
                                case null return claimJsonResponse(404, packageErrorJson());
                            };
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
                                    ("Content-Type", "application/octet-stream"),
                                    ("Content-Disposition", "attachment; filename=\"sneakerweb-card.snk\""),
                                    ("Cache-Control", "private, no-store, max-age=0"),
                                    ("Pragma", "no-cache"),
                                    ("X-Content-Type-Options", "nosniff"),
                                ];
                                body = ?Blob.fromArray(start.chunk);
                                streamingStrategy = strategy;
                            };
                        }
                    )
                ),
            ),
        ];
    };
};
