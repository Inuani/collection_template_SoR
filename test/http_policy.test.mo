import Text "mo:core/Text";

import CORS "../src/middleware/cors";
import FileViews "../src/file_views";
import SneakerwebRoutes "../src/routes/sneakerweb_routes";
import SneakerwebClaims "../src/sneakerweb_claims";
import Theme "../src/utils/theme";

// Cross-canister public reads remain possible, but there are no credentialed
// wildcard requests and no unused write methods or authorization header.
assert (CORS.corsOptions.allowOrigins == []);
assert (CORS.corsOptions.allowMethods == [#get, #post, #options]);
assert (CORS.corsOptions.allowHeaders == ["Content-Type"]);
assert (not CORS.corsOptions.allowCredentials);

let view = FileViews.generateAudioWrapper(
    "<script>alert('x')</script>.m4a",
    "123.abcdef",
);
assert (not Text.contains(view, #text("<script>alert")));
assert (Text.contains(view, #text("&lt;script&gt;alert")));
assert (Text.contains(view, #text("/api/stream/")));

let receipt : SneakerwebClaims.Receipt = {
    claim_id = "claim-id";
    issuer = "aaaaa-aa";
    item_id = 7;
    domain = "0123456789abcdef";
    claimed_at_ns = 123;
    package_token = "package-token";
    package_expires_at_ns = 456;
};
let claimResponse = SneakerwebRoutes.claimJsonResponse(
    200,
    SneakerwebRoutes.claimReceiptJson(receipt),
);
assert (claimResponse.statusCode == 200);
let claimBody = switch (claimResponse.body) {
    case null { assert false; "" };
    case (?body) {
        switch (Text.decodeUtf8(body)) {
            case null { assert false; "" };
            case (?text) text;
        };
    };
};
assert (Text.contains(claimBody, #text("\"type\":\"proof-of-contact-claim\"")));
assert (Text.contains(claimBody, #text("\"acquisition\":\"nfc_scan\"")));
assert (Text.contains(claimBody, #text("\"transport\":\"private_post\"")));
assert (not Text.contains(claimBody, #text("uid")));

let themeState = Theme.init();
let theme = Theme.ThemeManager(themeState);
assert (theme.getTheme().primary == "#3B82F6");
assert (theme.setTheme("#111111", "#222222").secondary == "#222222");
assert (theme.getPrimary() == "#111111");
assert (theme.resetTheme().secondary == "#10B981");
