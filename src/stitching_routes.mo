import Router       "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal      "mo:liminal";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Time "mo:core/Time";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Debug "mo:core/Debug";
import Collection "collection";
import Theme "utils/theme";
import Stitching "stitching";
import StitchingSession "utils/stitching_session";

module StitchingRoutes {
    // Returns all stitching-related routes
    public func getStitchingRoutes(
        collection: Collection.Collection,
        themeManager: Theme.ThemeManager
    ) : [Router.RouteConfig] {
        return [
            // Stitching waiting page (first scan - waiting for more items)
            Router.getQuery("/stitching/waiting", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                Debug.print("[ROUTE] /stitching/waiting accessed");
                let _itemIdTextOpt = ctx.getQueryParam("item");

                // Get items from session (unwrap optional)
                let sessionOpt = ctx.httpContext.session;
                let itemsInSession = StitchingSession.getItems(sessionOpt);

                if (itemsInSession.size() == 0) {
                    Debug.print("[Waiting Page] No items in session - showing error");
                    let html = "<html><body><h1>No Stitching Session</h1><p>Please scan an NFC tag to start a stitching.</p></body></html>";
                    return ctx.buildResponse(#ok, #html(html));
                };

                Debug.print("[Waiting Page] Items in session: " # Nat.toText(itemsInSession.size()));

                // Check if stitching has expired (1 minute window)
                switch (sessionOpt) {
                    case null { Debug.print("[Waiting Page] No session found"); };
                    case (?_) {};
                };
                let now = Time.now();
                let stitchingExpired = StitchingSession.hasExpired(sessionOpt, now, StitchingSession.stitchingTimeoutNanos);
                switch (StitchingSession.getStartTime(sessionOpt)) {
                    case null {
                        Debug.print("[Waiting Page] Timer check skipped - missing or invalid start time");
                    };
                    case (?startTime) {
                        let elapsedSeconds = (now - startTime) / 1_000_000_000;
                        Debug.print("[Waiting Page] Timer check - Elapsed: " # Int.toText(elapsedSeconds) # "s, Expired: " # (if (stitchingExpired) { "YES" } else { "NO" }));
                    };
                };

                // If stitching expired and we have 2+ items, auto-finalize
                if (stitchingExpired and itemsInSession.size() >= 2) {
                    Debug.print("[Waiting Page] AUTO-FINALIZING MEETING - Items: " # Nat.toText(itemsInSession.size()));

                    // Generate unique stitching ID using timestamp
                    let stitchingId = "stitching_" # Int.toText(Time.now());

                    // Record the stitching (awards tokens AND updates history)
                    ignore collection.recordStitching(itemsInSession, stitchingId, 10);

                    // Build items text for redirect
                    let itemsText = StitchingSession.itemsToText(itemsInSession);

                    // Clear session (including token)
                    StitchingSession.clear(sessionOpt);

                    // Redirect to success page
                    return {
                        statusCode = 303;
                        headers = [("Location", "/stitching/success?items=" # itemsText)];
                        body = null;
                        streamingStrategy = null;
                    };
                };

                let firstItemId = itemsInSession[0];
                switch (collection.getItem(firstItemId)) {
                    case null {
                        let html = "<html><body><h1>Error</h1><p>Item not found.</p></body></html>";
                        ctx.buildResponse(#notFound, #html(html))
                    };
                    case (?item) {
                        // Get stitching start time from session to pass to frontend
                        let stitchingStartTime = StitchingSession.getStartTimeText(sessionOpt);

                        // Get finalize token from session to pass to frontend
                        let finalizeToken = StitchingSession.getFinalizeToken(sessionOpt);

                        let html = Stitching.generateWaitingPage(item, itemsInSession, stitchingStartTime, finalizeToken, themeManager);
                        ctx.buildResponse(#ok, #html(html))
                    };
                }
            }),

            // Stitching active page (multiple items scanned)
            Router.getQuery("/stitching/active", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                Debug.print("[ROUTE] /stitching/active accessed");
                // Get items from session (unwrap optional)
                let sessionOpt = ctx.httpContext.session;
                let itemsInSession = StitchingSession.getItems(sessionOpt);

                if (itemsInSession.size() < 2) {
                    return {
                        statusCode = 303;
                        headers = [("Location", "/stitching/waiting?item=" # Nat.toText(itemsInSession[0]))];
                        body = null;
                        streamingStrategy = null;
                    };
                };

                // Check if stitching has expired (1 minute window)
                switch (sessionOpt) {
                    case null { Debug.print("[Active Page] No session found"); };
                    case (?_) {};
                };
                let now = Time.now();
                let stitchingExpired = StitchingSession.hasExpired(sessionOpt, now, StitchingSession.stitchingTimeoutNanos);
                switch (StitchingSession.getStartTime(sessionOpt)) {
                    case null {
                        Debug.print("[Active Page] Timer check skipped - missing or invalid start time");
                    };
                    case (?startTime) {
                        let elapsedSeconds = (now - startTime) / 1_000_000_000;
                        Debug.print("[Active Page] Timer check - Elapsed: " # Int.toText(elapsedSeconds) # "s, Expired: " # (if (stitchingExpired) { "YES" } else { "NO" }));
                    };
                };

                // If stitching expired, auto-finalize
                if (stitchingExpired) {
                    Debug.print("[Active Page] AUTO-FINALIZING MEETING - Items: " # Nat.toText(itemsInSession.size()));

                    // Generate unique stitching ID using timestamp
                    let stitchingId = "stitching_" # Int.toText(Time.now());

                    // Record the stitching (awards tokens AND updates history)
                    ignore collection.recordStitching(itemsInSession, stitchingId, 10);

                    // Build items text for redirect
                    let itemsText = StitchingSession.itemsToText(itemsInSession);

                    // Clear session (including token for one-time use)
                    StitchingSession.clear(sessionOpt);
                    Debug.print("[FINALIZE] Session cleared - token deleted");

                    // Redirect to success page
                    return {
                        statusCode = 303;
                        headers = [("Location", "/stitching/success?items=" # itemsText)];
                        body = null;
                        streamingStrategy = null;
                    };
                };

                let allItems = collection.getAllItems();
                // Get stitching start time from session to pass to frontend
                let stitchingStartTime = StitchingSession.getStartTimeText(sessionOpt);

                // Get finalize token from session to pass to frontend
                let finalizeToken = StitchingSession.getFinalizeToken(sessionOpt);

                let html = Stitching.generateActiveSessionPage(itemsInSession, allItems, stitchingStartTime, finalizeToken, themeManager);
                ctx.buildResponse(#ok, #html(html))
            }),

            // Stitching finalize (process the stitching from session)
            Router.getAsyncUpdate("/stitching/finalize_session", func(ctx: RouteContext.RouteContext) : async* Liminal.HttpResponse {
                Debug.print("[FINALIZE] Endpoint called");

                // 1. Verify token first
                let urlToken = ctx.getQueryParam("token");
                let isManual = ctx.getQueryParam("manual");

                Debug.print("[FINALIZE] URL token: " # (switch(urlToken) { case null "NONE"; case (?t) t }));
                Debug.print("[FINALIZE] Manual flag: " # (switch(isManual) { case null "false"; case (?_) "true" }));

                let sessionOpt = ctx.httpContext.session;
                let sessionToken = StitchingSession.getFinalizeTokenOpt(sessionOpt);

                Debug.print("[FINALIZE] Session token: " # (switch(sessionToken) { case null "NONE"; case (?t) t }));

                // Check if tokens match
                switch (urlToken, sessionToken) {
                    case (null, _) {
                        Debug.print("[FINALIZE] REJECTED - No token in URL");
                        let html = "<html><body><h1>Error</h1><p>Missing finalization token.</p></body></html>";
                        return ctx.buildResponse(#unauthorized, #html(html));
                    };
                    case (_, null) {
                        Debug.print("[FINALIZE] REJECTED - No token in session (already used or expired)");
                        let html = "<html><body><h1>Error</h1><p>Stitching already finalized or session expired.</p></body></html>";
                        return ctx.buildResponse(#unauthorized, #html(html));
                    };
                    case (?urlT, ?sessionT) {
                        if (urlT != sessionT) {
                            Debug.print("[FINALIZE] REJECTED - Token mismatch");
                            let html = "<html><body><h1>Error</h1><p>Invalid finalization token.</p></body></html>";
                            return ctx.buildResponse(#unauthorized, #html(html));
                        };
                        Debug.print("[FINALIZE] Token verified ✓");
                    };
                };

                // 2. Get items from session (unwrap optional)
                let itemsInSession = StitchingSession.getItems(sessionOpt);

                if (itemsInSession.size() < 2) {
                    Debug.print("[FINALIZE] REJECTED - Less than 2 items");
                    let html = "<html><body><h1>Error</h1><p>Need at least 2 items to finalize a stitching.</p></body></html>";
                    return ctx.buildResponse(#badRequest, #html(html));
                };

                Debug.print("[FINALIZE] Items count: " # Nat.toText(itemsInSession.size()));

                // 3. Check timer for auto-finalization (skip for manual)
                if (isManual == null) {
                    // This is auto-finalization - verify timer expired
                    Debug.print("[FINALIZE] Auto-finalization - checking timer");

                    let stitchingStartTime = StitchingSession.getStartTime(sessionOpt);

                    switch (stitchingStartTime) {
                        case null {
                            Debug.print("[FINALIZE] REJECTED - No start time in session");
                            let html = "<html><body><h1>Error</h1><p>Stitching start time not found.</p></body></html>";
                            return ctx.buildResponse(#badRequest, #html(html));
                        };
                        case (?startTime) {
                            let elapsed = Time.now() - startTime;
                            let elapsedSeconds = elapsed / 1_000_000_000;

                            Debug.print("[FINALIZE] Timer elapsed: " # Int.toText(elapsedSeconds) # " seconds");

                            // Allow if >= 59 seconds (account for clock skew)
                            let minThreshold = StitchingSession.stitchingTimeoutNanos - 1_000_000_000;
                            if (elapsed < minThreshold) {
                                Debug.print("[FINALIZE] REJECTED - Timer not expired yet");
                                let html = "<html><body><h1>Too Soon</h1><p>Please wait for the timer to complete, or use the manual finalize button.</p></body></html>";
                                return ctx.buildResponse(#badRequest, #html(html));
                            };

                            Debug.print("[FINALIZE] Timer check passed ✓");
                        };
                    };
                } else {
                    Debug.print("[FINALIZE] Manual finalization - skipping timer check");
                };

                // 4. All checks passed - finalize stitching
                Debug.print("[FINALIZE] All checks passed - finalizing stitching");

                // Generate unique stitching ID using timestamp
                let stitchingId = "stitching_" # Int.toText(Time.now());

                // Record the stitching (awards tokens AND updates history)
                ignore collection.recordStitching(itemsInSession, stitchingId, 10);

                Debug.print("[FINALIZE] Tokens awarded and history recorded ✓");

                // Generate success message
                let itemsText = StitchingSession.itemsToText(itemsInSession);

                // Clear session (including token)
                StitchingSession.clear(sessionOpt);

                // Redirect to success page
                let redirectUrl = "/stitching/success?items=" # itemsText;
                return {
                    statusCode = 303;
                    headers = [
                        ("Location", redirectUrl),
                        ("Content-Type", "text/html")
                    ];
                    body = ?Text.encodeUtf8("<html><body>Stitching finalized! Redirecting...</body></html>");
                    streamingStrategy = null;
                };
            }),

            // Stitching success route (session-based system)
            Router.getQuery("/stitching/success", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                let itemsTextOpt = ctx.getQueryParam("items");

                let itemsText = switch (itemsTextOpt) {
                    case (?items) items;
                    case null "";
                };

                // Parse item IDs
                let itemStrings = Iter.toArray(Text.split(itemsText, #char ','));
                var itemIds : [Nat] = [];

                for (itemStr in itemStrings.vals()) {
                    switch (Nat.fromText(itemStr)) {
                        case (?id) {
                            itemIds := Array.concat(itemIds, [id]);
                        };
                        case null {};
                    };
                };

                let allItems = collection.getAllItems();
                let html = Stitching.generateSessionSuccessPage(itemIds, allItems, themeManager);
                ctx.buildResponse(#ok, #html(html))
            }),

            // Stitching error route
            Router.getQuery("/stitching/error", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                let errorMsgOpt = ctx.getQueryParam("msg");

                let errorMsg = switch (errorMsgOpt) {
                    case (?msg) msg;
                    case null "An unknown error occurred";
                };

                let html = Stitching.generateStitchingErrorPage(errorMsg, themeManager);
                ctx.buildResponse(#ok, #html(html))
            }),
        ]
    };
}
