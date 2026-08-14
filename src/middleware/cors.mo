import CORS "mo:liminal/CORS";
import App "mo:liminal/App";
import HttpContext "mo:liminal/HttpContext";
import Array "mo:core/Array";

module {
    // Public Knitwork lookups intentionally support arbitrary Collection
    // origins. No endpoint uses cookies, so credentials stay disabled and the
    // allowed surface is limited to the methods and header actually required.
    public let corsOptions : CORS.Options = {
        allowOrigins = []; // Empty means all origins in Liminal.
        allowMethods = [#get, #post, #options];
        allowHeaders = ["Content-Type"];
        maxAge = ?86400;
        allowCredentials = false;
        exposeHeaders = [];
    };

    public func createCORSMiddleware() : App.Middleware {
        {
            name = "CORS";
            handleQuery = func(context : HttpContext.HttpContext, next : App.Next) : App.QueryResult {
                // Handle CORS preflight and regular requests
                switch (CORS.handlePreflight(context, corsOptions)) {
                    case (#complete(response)) {
                        return #response(response);
                    };
                    case (#next({ corsHeaders = _ })) {
                        // Continue to next middleware
                        next();
                    };
                };
            };
            handleUpdate = func(context : HttpContext.HttpContext, next : App.NextAsync) : async* App.HttpResponse {
                // Handle CORS for update calls
                switch (CORS.handlePreflight(context, corsOptions)) {
                    case (#complete(response)) {
                        return response;
                    };
                    case (#next({ corsHeaders })) {
                        // Continue to next middleware
                        let response = await* next();
                        // Add CORS headers to response
                        let updatedHeaders = Array.concat(response.headers, corsHeaders);
                        return {
                            statusCode = response.statusCode;
                            headers = updatedHeaders;
                            body = response.body;
                            streamingStrategy = response.streamingStrategy;
                        };
                    };
                };
            };
        };
    };
}
