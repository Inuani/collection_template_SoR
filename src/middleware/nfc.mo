import Iter "mo:core/Iter";
import Text "mo:core/Text";
import App "mo:liminal/App";
import HttpContext "mo:liminal/HttpContext";
import Files "../files";
import ProtectedRoutes "../nfc_protec_routes";
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
        fileStorage : Files.FileStorage,
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
                            switch (queryParameter(url, "token")) {
                                case (?token) {
                                    if (not fileStorage.validateToken(token, filename)) {
                                        return invalidTokenResponse();
                                    };
                                    return await* next();
                                };
                                case null {
                                    if (not protectedRoutes.verifyRouteAccess(path, url)) {
                                        return invalidScanResponse();
                                    };
                                    let token = fileStorage.generateToken(filename);
                                    return {
                                        statusCode = 200;
                                        headers = [("Content-Type", "text/html")];
                                        body = ?Text.encodeUtf8(fileStorage.generateHTMLWrapper(filename, token));
                                        streamingStrategy = null;
                                    };
                                };
                            };
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
