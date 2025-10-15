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
import Meeting "meeting";
import MeetingSession "utils/meeting_session";

module MeetingRoutes {
    // Returns all meeting-related routes
    public func getMeetingRoutes(
        collection: Collection.Collection,
        themeManager: Theme.ThemeManager
    ) : [Router.RouteConfig] {
        return [
            // Meeting waiting page (first scan - waiting for more items)
            Router.getQuery("/meeting/waiting", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                Debug.print("[ROUTE] /meeting/waiting accessed");
                let _itemIdTextOpt = ctx.getQueryParam("item");

                // Get items from session (unwrap optional)
                let sessionOpt = ctx.httpContext.session;
                let itemsInSession = MeetingSession.getItems(sessionOpt);

                if (itemsInSession.size() == 0) {
                    Debug.print("[Waiting Page] No items in session - showing error");
                    let html = "<html><body><h1>No Meeting Session</h1><p>Please scan an NFC tag to start a meeting.</p></body></html>";
                    return ctx.buildResponse(#ok, #html(html));
                };

                Debug.print("[Waiting Page] Items in session: " # Nat.toText(itemsInSession.size()));

                // Check if meeting has expired (1 minute window)
                switch (sessionOpt) {
                    case null { Debug.print("[Waiting Page] No session found"); };
                    case (?_) {};
                };
                let now = Time.now();
                let meetingExpired = MeetingSession.hasExpired(sessionOpt, now, MeetingSession.meetingTimeoutNanos);
                switch (MeetingSession.getStartTime(sessionOpt)) {
                    case null {
                        Debug.print("[Waiting Page] Timer check skipped - missing or invalid start time");
                    };
                    case (?startTime) {
                        let elapsedSeconds = (now - startTime) / 1_000_000_000;
                        Debug.print("[Waiting Page] Timer check - Elapsed: " # Int.toText(elapsedSeconds) # "s, Expired: " # (if (meetingExpired) { "YES" } else { "NO" }));
                    };
                };

                // If meeting expired and we have 2+ items, auto-finalize
                if (meetingExpired and itemsInSession.size() >= 2) {
                    Debug.print("[Waiting Page] AUTO-FINALIZING MEETING - Items: " # Nat.toText(itemsInSession.size()));

                    // Generate unique meeting ID using timestamp
                    let meetingId = "meeting_" # Int.toText(Time.now());

                    // Record the meeting (awards tokens AND updates history)
                    ignore collection.recordMeeting(itemsInSession, meetingId, 10);

                    // Build items text for redirect
                    let itemsText = MeetingSession.itemsToText(itemsInSession);

                    // Clear session (including token)
                    MeetingSession.clear(sessionOpt);

                    // Redirect to success page
                    return {
                        statusCode = 303;
                        headers = [("Location", "/meeting/success?items=" # itemsText)];
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
                        // Get meeting start time from session to pass to frontend
                        let meetingStartTime = MeetingSession.getStartTimeText(sessionOpt);

                        // Get finalize token from session to pass to frontend
                        let finalizeToken = MeetingSession.getFinalizeToken(sessionOpt);

                        let html = Meeting.generateWaitingPage(item, itemsInSession, meetingStartTime, finalizeToken, themeManager);
                        ctx.buildResponse(#ok, #html(html))
                    };
                }
            }),

            // Meeting active page (multiple items scanned)
            Router.getQuery("/meeting/active", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                Debug.print("[ROUTE] /meeting/active accessed");
                // Get items from session (unwrap optional)
                let sessionOpt = ctx.httpContext.session;
                let itemsInSession = MeetingSession.getItems(sessionOpt);

                if (itemsInSession.size() < 2) {
                    return {
                        statusCode = 303;
                        headers = [("Location", "/meeting/waiting?item=" # Nat.toText(itemsInSession[0]))];
                        body = null;
                        streamingStrategy = null;
                    };
                };

                // Check if meeting has expired (1 minute window)
                switch (sessionOpt) {
                    case null { Debug.print("[Active Page] No session found"); };
                    case (?_) {};
                };
                let now = Time.now();
                let meetingExpired = MeetingSession.hasExpired(sessionOpt, now, MeetingSession.meetingTimeoutNanos);
                switch (MeetingSession.getStartTime(sessionOpt)) {
                    case null {
                        Debug.print("[Active Page] Timer check skipped - missing or invalid start time");
                    };
                    case (?startTime) {
                        let elapsedSeconds = (now - startTime) / 1_000_000_000;
                        Debug.print("[Active Page] Timer check - Elapsed: " # Int.toText(elapsedSeconds) # "s, Expired: " # (if (meetingExpired) { "YES" } else { "NO" }));
                    };
                };

                // If meeting expired, auto-finalize
                if (meetingExpired) {
                    Debug.print("[Active Page] AUTO-FINALIZING MEETING - Items: " # Nat.toText(itemsInSession.size()));

                    // Generate unique meeting ID using timestamp
                    let meetingId = "meeting_" # Int.toText(Time.now());

                    // Record the meeting (awards tokens AND updates history)
                    ignore collection.recordMeeting(itemsInSession, meetingId, 10);

                    // Build items text for redirect
                    let itemsText = MeetingSession.itemsToText(itemsInSession);

                    // Clear session (including token for one-time use)
                    MeetingSession.clear(sessionOpt);
                    Debug.print("[FINALIZE] Session cleared - token deleted");

                    // Redirect to success page
                    return {
                        statusCode = 303;
                        headers = [("Location", "/meeting/success?items=" # itemsText)];
                        body = null;
                        streamingStrategy = null;
                    };
                };

                let allItems = collection.getAllItems();
                // Get meeting start time from session to pass to frontend
                let meetingStartTime = MeetingSession.getStartTimeText(sessionOpt);

                // Get finalize token from session to pass to frontend
                let finalizeToken = MeetingSession.getFinalizeToken(sessionOpt);

                let html = Meeting.generateActiveSessionPage(itemsInSession, allItems, meetingStartTime, finalizeToken, themeManager);
                ctx.buildResponse(#ok, #html(html))
            }),

            // Meeting finalize (process the meeting from session)
            Router.getAsyncUpdate("/meeting/finalize_session", func(ctx: RouteContext.RouteContext) : async* Liminal.HttpResponse {
                Debug.print("[FINALIZE] Endpoint called");

                // 1. Verify token first
                let urlToken = ctx.getQueryParam("token");
                let isManual = ctx.getQueryParam("manual");

                Debug.print("[FINALIZE] URL token: " # (switch(urlToken) { case null "NONE"; case (?t) t }));
                Debug.print("[FINALIZE] Manual flag: " # (switch(isManual) { case null "false"; case (?_) "true" }));

                let sessionOpt = ctx.httpContext.session;
                let sessionToken = MeetingSession.getFinalizeTokenOpt(sessionOpt);

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
                        let html = "<html><body><h1>Error</h1><p>Meeting already finalized or session expired.</p></body></html>";
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
                let itemsInSession = MeetingSession.getItems(sessionOpt);

                if (itemsInSession.size() < 2) {
                    Debug.print("[FINALIZE] REJECTED - Less than 2 items");
                    let html = "<html><body><h1>Error</h1><p>Need at least 2 items to finalize a meeting.</p></body></html>";
                    return ctx.buildResponse(#badRequest, #html(html));
                };

                Debug.print("[FINALIZE] Items count: " # Nat.toText(itemsInSession.size()));

                // 3. Check timer for auto-finalization (skip for manual)
                if (isManual == null) {
                    // This is auto-finalization - verify timer expired
                    Debug.print("[FINALIZE] Auto-finalization - checking timer");

                    let meetingStartTime = MeetingSession.getStartTime(sessionOpt);

                    switch (meetingStartTime) {
                        case null {
                            Debug.print("[FINALIZE] REJECTED - No start time in session");
                            let html = "<html><body><h1>Error</h1><p>Meeting start time not found.</p></body></html>";
                            return ctx.buildResponse(#badRequest, #html(html));
                        };
                        case (?startTime) {
                            let elapsed = Time.now() - startTime;
                            let elapsedSeconds = elapsed / 1_000_000_000;

                            Debug.print("[FINALIZE] Timer elapsed: " # Int.toText(elapsedSeconds) # " seconds");

                            // Allow if >= 59 seconds (account for clock skew)
                            let minThreshold = MeetingSession.meetingTimeoutNanos - 1_000_000_000;
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

                // 4. All checks passed - finalize meeting
                Debug.print("[FINALIZE] All checks passed - finalizing meeting");

                // Generate unique meeting ID using timestamp
                let meetingId = "meeting_" # Int.toText(Time.now());

                // Record the meeting (awards tokens AND updates history)
                ignore collection.recordMeeting(itemsInSession, meetingId, 10);

                Debug.print("[FINALIZE] Tokens awarded and history recorded ✓");

                // Generate success message
                let itemsText = MeetingSession.itemsToText(itemsInSession);

                // Clear session (including token)
                MeetingSession.clear(sessionOpt);

                // Redirect to success page
                let redirectUrl = "/meeting/success?items=" # itemsText;
                return {
                    statusCode = 303;
                    headers = [
                        ("Location", redirectUrl),
                        ("Content-Type", "text/html")
                    ];
                    body = ?Text.encodeUtf8("<html><body>Meeting finalized! Redirecting...</body></html>");
                    streamingStrategy = null;
                };
            }),

            // Meeting success route (session-based system)
            Router.getQuery("/meeting/success", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
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
                let html = Meeting.generateSessionSuccessPage(itemIds, allItems, themeManager);
                ctx.buildResponse(#ok, #html(html))
            }),

            // Meeting error route
            Router.getQuery("/meeting/error", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                let errorMsgOpt = ctx.getQueryParam("msg");

                let errorMsg = switch (errorMsgOpt) {
                    case (?msg) msg;
                    case null "An unknown error occurred";
                };

                let html = Meeting.generateMeetingErrorPage(errorMsg, themeManager);
                ctx.buildResponse(#ok, #html(html))
            }),
        ]
    };
}
