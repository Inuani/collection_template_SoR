import Router       "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal      "mo:liminal";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Time "mo:core/Time";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Debug "mo:core/Debug";
import Collection "collection";
import Theme "utils/theme";
import Stitching "stitching";
import StitchingToken "utils/stitching_token";

module StitchingRoutes {
    let stitchingTimeoutNanos : Int = StitchingToken.stitchingTimeoutNanos;

    func getStitchingState(ctx: RouteContext.RouteContext) : ?StitchingToken.StitchingState {
        StitchingToken.fromIdentity(ctx.httpContext.getIdentity());
    };

    func hasExpired(state: StitchingToken.StitchingState, now: Int) : Bool {
        switch (state.startTime) {
            case null false;
            case (?start) now - start > stitchingTimeoutNanos;
        }
    };

    func getStartTimeText(state: StitchingToken.StitchingState) : Text {
        switch (state.startTime) {
            case null "0";
            case (?value) Int.toText(value);
        }
    };

    func getFinalizeToken(state: StitchingToken.StitchingState) : Text {
        switch (state.finalizeToken) {
            case null "";
            case (?token) token;
        }
    };

    func clearJwtCookieHeader() : (Text, Text) {
        (
            "Set-Cookie",
            StitchingToken.tokenCookieName # "=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        );
    };

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

                let stateOpt = getStitchingState(ctx);

                let state = switch (stateOpt) {
                    case null {
                        Debug.print("[Waiting Page] No JWT state - showing error");
                        let html = "<html><body><h1>No Stitching Session</h1><p>Please scan an NFC tag to start a stitching.</p></body></html>";
                        return ctx.buildResponse(#ok, #html(html));
                    };
                    case (?value) value;
                };

                let itemsInSession = state.items;

                if (itemsInSession.size() == 0) {
                    Debug.print("[Waiting Page] No items in JWT state - showing error");
                    let html = "<html><body><h1>No Stitching Session</h1><p>Please scan an NFC tag to start a stitching.</p></body></html>";
                    return ctx.buildResponse(#ok, #html(html));
                };

                Debug.print("[Waiting Page] Items in session: " # Nat.toText(itemsInSession.size()));

                let now = Time.now();
                let stitchingExpired = hasExpired(state, now);
                switch (state.startTime) {
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

                    let itemsText = StitchingToken.itemsToText(itemsInSession);

                    // Redirect to success page
                    return {
                        statusCode = 303;
                        headers = [
                            ("Location", "/stitching/success?items=" # itemsText),
                            clearJwtCookieHeader(),
                        ];
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
                        let stitchingStartTime = getStartTimeText(state);

                        // Get finalize token from session to pass to frontend
                        let finalizeToken = getFinalizeToken(state);

                        let html = Stitching.generateWaitingPage(item, itemsInSession, stitchingStartTime, finalizeToken, themeManager);
                        ctx.buildResponse(#ok, #html(html))
                    };
                }
            }),

            // Stitching active page (multiple items scanned)
            Router.getQuery("/stitching/active", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                Debug.print("[ROUTE] /stitching/active accessed");
                let stateOpt = getStitchingState(ctx);

                let state = switch (stateOpt) {
                    case null {
                        return {
                            statusCode = 303;
                            headers = [("Location", "/stitching/waiting")];
                            body = null;
                            streamingStrategy = null;
                        };
                    };
                    case (?value) value;
                };

                let itemsInSession = state.items;

                if (itemsInSession.size() == 0) {
                    return {
                        statusCode = 303;
                        headers = [("Location", "/stitching/waiting")];
                        body = null;
                        streamingStrategy = null;
                    };
                };

                if (itemsInSession.size() < 2) {
                    return {
                        statusCode = 303;
                        headers = [("Location", "/stitching/waiting?item=" # Nat.toText(itemsInSession[0]))];
                        body = null;
                        streamingStrategy = null;
                    };
                };

                let now = Time.now();
                let stitchingExpired = hasExpired(state, now);
                switch (state.startTime) {
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

                    let itemsText = StitchingToken.itemsToText(itemsInSession);

                    // Redirect to success page
                    return {
                        statusCode = 303;
                        headers = [
                            ("Location", "/stitching/success?items=" # itemsText),
                            clearJwtCookieHeader(),
                        ];
                        body = null;
                        streamingStrategy = null;
                    };
                };

                let allItems = collection.getAllItems();
                // Get stitching start time from session to pass to frontend
                let stitchingStartTime = getStartTimeText(state);

                // Get finalize token from session to pass to frontend
                let finalizeToken = getFinalizeToken(state);

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

                let stateOpt = getStitchingState(ctx);

                let state = switch (stateOpt) {
                    case null {
                        Debug.print("[FINALIZE] REJECTED - No JWT state available");
                        let html = "<html><body><h1>Error</h1><p>Stitching state not found.</p></body></html>";
                        return ctx.buildResponse(#unauthorized, #html(html));
                    };
                    case (?value) value;
                };

                let sessionToken = state.finalizeToken;

                Debug.print("[FINALIZE] Session token: " # (switch(sessionToken) { case null "NONE"; case (?t) t }));

                // Check if tokens match
                switch (urlToken, sessionToken) {
                    case (null, _) {
                        Debug.print("[FINALIZE] REJECTED - No token in URL");
                        let html = "<html><body><h1>Error</h1><p>Missing finalization token.</p></body></html>";
                        return ctx.buildResponse(#unauthorized, #html(html));
                    };
                    case (_, null) {
                        Debug.print("[FINALIZE] REJECTED - No token in JWT (already used or expired)");
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
                let itemsInSession = state.items;

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

                    let stitchingStartTime = state.startTime;

                    switch (stitchingStartTime) {
                        case null {
                            Debug.print("[FINALIZE] REJECTED - No start time in JWT state");
                            let html = "<html><body><h1>Error</h1><p>Stitching start time not found.</p></body></html>";
                            return ctx.buildResponse(#badRequest, #html(html));
                        };
                        case (?startTime) {
                            let elapsed = Time.now() - startTime;
                            let elapsedSeconds = elapsed / 1_000_000_000;

                            Debug.print("[FINALIZE] Timer elapsed: " # Int.toText(elapsedSeconds) # " seconds");

                            // Allow if >= 59 seconds (account for clock skew)
                            let minThreshold = stitchingTimeoutNanos - 1_000_000_000;
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

                // Redirect to success page
                let redirectUrl = "/stitching/success?items=" # StitchingToken.itemsToText(itemsInSession);
                return {
                    statusCode = 303;
                    headers = [
                        ("Location", redirectUrl),
                        ("Content-Type", "text/html"),
                        clearJwtCookieHeader(),
                    ];
                    body = ?Text.encodeUtf8("<html><body>Stitching finalized! Redirecting...</body></html>");
                    streamingStrategy = null;
                };
            }),

            // Stitching success route (JWT-based)
            Router.getQuery("/stitching/success", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                let itemsTextOpt = ctx.getQueryParam("items");

                let itemsText = switch (itemsTextOpt) {
                    case (?items) items;
                    case null "";
                };

                let rawParts = Iter.toArray(Text.split(itemsText, #char ','));
                var itemIds : [Nat] = [];
                for (part in rawParts.vals()) {
                    switch (Nat.fromText(part)) {
                        case (?id) { itemIds := Array.concat(itemIds, [id]); };
                        case null {};
                    };
                };

                if (itemIds.size() == 0) {
                    let html = "<html><body><h1>No Stitching Data</h1><p>We couldn't find stitching information. Please rescan the NFC tags.</p></body></html>";
                    return {
                        statusCode = 200;
                        headers = [
                            ("Content-Type", "text/html"),
                            clearJwtCookieHeader(),
                        ];
                        body = ?Text.encodeUtf8(html);
                        streamingStrategy = null;
                    };
                };

                let allItems = collection.getAllItems();
                let html = Stitching.generateSessionSuccessPage(itemIds, allItems, themeManager);
                {
                    statusCode = 200;
                    headers = [
                        ("Content-Type", "text/html"),
                        clearJwtCookieHeader(),
                    ];
                    body = ?Text.encodeUtf8(html);
                    streamingStrategy = null;
                }
            }),

            // Stitching error route
            Router.getQuery("/stitching/error", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                let stateOpt = StitchingToken.fromIdentity(ctx.httpContext.getIdentity());

                let errorMsg = switch (stateOpt) {
                    case (?state) {
                        if (state.items.size() >= 2) {
                            "We had trouble finalizing the stitching. Please try again."
                        } else if (state.items.size() == 1) {
                            "One participant was detected, but we need at least two items."
                        } else {
                            "No stitching data found. Please scan an NFC tag to start."
                        }
                    };
                    case null "No stitching data found. Please scan an NFC tag to start.";
                };

                let html = Stitching.generateStitchingErrorPage(errorMsg, themeManager);
                return {
                    statusCode = 200;
                    headers = [
                        ("Content-Type", "text/html"),
                        clearJwtCookieHeader(),
                    ];
                    body = ?Text.encodeUtf8(html);
                    streamingStrategy = null;
                };
            }),
        ]
    };
}
