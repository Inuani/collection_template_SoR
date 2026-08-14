import Iter "mo:core/Iter";
import Text "mo:core/Text";
import App "mo:liminal/App";
import HttpContext "mo:liminal/HttpContext";
import FileAccess "../file_access";
import FileViews "../file_views";
import ProtectedRoutes "../nfc_protec_routes";
import SneakerwebClaims "../sneakerweb_claims";
import InvalidScan "../utils/invalid_scan";

module NFCMiddleware {
    func invalidScanResponse() : App.HttpResponse {
        {
            statusCode = 403;
            headers = [("Content-Type", "text/html")];
            body = ?Text.encodeUtf8(InvalidScan.generateInvalidScanPage());
            streamingStrategy = null;
        };
    };

    func invalidTokenResponse() : App.HttpResponse {
        {
            statusCode = 403;
            headers = [("Content-Type", "text/plain")];
            body = ?Text.encodeUtf8("Invalid or expired token");
            streamingStrategy = null;
        };
    };

    func claimRedirectResponse(url : Text) : App.HttpResponse {
        {
            statusCode = 303;
            headers = [
                ("Location", url),
                ("Cache-Control", "no-store"),
                ("Referrer-Policy", "no-referrer"),
            ];
            body = null;
            streamingStrategy = null;
        };
    };

    func claimIssueErrorResponse() : App.HttpResponse {
        {
            statusCode = 503;
            headers = [
                ("Content-Type", "text/plain; charset=utf-8"),
                ("Cache-Control", "no-store"),
            ];
            body = ?Text.encodeUtf8("Sneakerweb claim is not configured");
            streamingStrategy = null;
        };
    };

    func fileAccessUnavailableResponse() : App.HttpResponse {
        {
            statusCode = 503;
            headers = [
                ("Content-Type", "text/plain; charset=utf-8"),
                ("Cache-Control", "no-store"),
            ];
            body = ?Text.encodeUtf8("Temporary file access is not configured");
            streamingStrategy = null;
        };
    };

    func queryParameter(url : Text, key : Text) : ?Text {
        let parts = Iter.toArray(Text.split(url, #char '?'));
        if (parts.size() < 2) return null;
        for (parameter in Text.split(parts[1], #char '&')) {
            let keyValue = Iter.toArray(Text.split(parameter, #char '='));
            if (keyValue.size() == 2 and keyValue[0] == key) {
                return ?keyValue[1];
            };
        };
        null;
    };

    // Stateless CMAC protection for configured pages and files. Meeting and
    // session creation live exclusively in the authenticated Knitwork Hub.
    public func createNFCProtectionMiddleware(
        protectedRoutes : ProtectedRoutes.RoutesStorage,
        fileAccess : FileAccess.Access,
        sneakerwebClaims : SneakerwebClaims.Store,
    ) : App.Middleware {
        {
            name = "NFC route protection";
            handleQuery = func(context : HttpContext.HttpContext, next : App.Next) : App.QueryResult {
                if (protectedRoutes.isProtectedRoute(context.request.url)) {
                    return #upgrade;
                };
                next();
            };
            handleUpdate = func(context : HttpContext.HttpContext, next : App.NextAsync) : async* App.HttpResponse {
                let url = context.request.url;
                if (not protectedRoutes.isProtectedRoute(url)) {
                    return await* next();
                };

                for ((path, _) in protectedRoutes.listProtectedRoutes().vals()) {
                    if (protectedRoutes.routeMatches(path, url)) {
                        let pathOnly = Iter.toArray(Text.split(url, #char '?'))[0];
                        if (Text.startsWith(pathOnly, #text "/files/")) {
                            let segments = Iter.toArray(Text.split(pathOnly, #char '/'));
                            let filename = if (segments.size() == 0) { "" } else { segments[segments.size() - 1] };
                            if (sneakerwebClaims.isPrivatePackageFile(filename)) {
                                return invalidTokenResponse();
                            };
                            switch (queryParameter(url, "token")) {
                                case (?token) {
                                    if (not fileAccess.validateToken(token, filename)) {
                                        return invalidTokenResponse();
                                    };
                                    return await* next();
                                };
                                case null {
                                    // Do not consume an NFC counter while the canister is
                                    // waiting for its per-installation access secret.
                                    if (not fileAccess.isConfigured()) {
                                        return fileAccessUnavailableResponse();
                                    };
                                    if (not protectedRoutes.verifyRouteAccess(path, url)) {
                                        return invalidScanResponse();
                                    };
                                    let token = switch (fileAccess.generateToken(filename)) {
                                        case (?value) value;
                                        case null return fileAccessUnavailableResponse();
                                    };
                                    return {
                                        statusCode = 200;
                                        headers = [
                                            ("Content-Type", "text/html; charset=utf-8"),
                                            ("Cache-Control", "private, no-store, max-age=0"),
                                            ("Content-Security-Policy", "default-src 'self'; style-src 'self'; media-src 'self'; object-src 'none'; base-uri 'none'"),
                                            ("X-Content-Type-Options", "nosniff"),
                                        ];
                                        body = ?Text.encodeUtf8(FileViews.generateAudioWrapper(filename, token));
                                        streamingStrategy = null;
                                    };
                                };
                            };
                        };

                        switch (SneakerwebClaims.itemIdFromNfcPath(path)) {
                            case (?itemId) {
                                if (sneakerwebClaims.canIssue(itemId)) {
                                    let scan = switch (protectedRoutes.consumeRouteAccess(path, url)) {
                                        case (?consumed) consumed;
                                        case null return invalidScanResponse();
                                    };
                                    switch (
                                        sneakerwebClaims.issue(
                                            itemId,
                                            scan.uid,
                                            scan.counter,
                                            scan.cmac,
                                        )
                                    ) {
                                        case (#ok(claim)) {
                                            return claimRedirectResponse(claim.redirect_url);
                                        };
                                        case (#err(_)) {
                                            // Configuration was checked before consuming the
                                            // scan, so this branch only protects an invariant.
                                            return claimIssueErrorResponse();
                                        };
                                    };
                                };
                            };
                            case null {};
                        };

                        if (not protectedRoutes.verifyRouteAccess(path, url)) {
                            return invalidScanResponse();
                        };
                        return await* next();
                    };
                };
                invalidScanResponse();
            };
        };
    };
};
