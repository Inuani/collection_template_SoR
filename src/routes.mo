
import Router       "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import HttpContext  "mo:liminal/HttpContext";
import Session      "mo:liminal/Session";
import Liminal      "mo:liminal";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Time "mo:core/Time";
import Blob "mo:core/Blob";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Debug "mo:core/Debug";
// import Route "mo:liminal/Route";
import Collection "collection";
import Home "home";
import Theme "theme";
import Files "files";
import Buttons "buttons";
import Meeting "meeting";
import Result "mo:core/Result";

module Routes {
   public func routerConfig(
       canisterId: Text,
       getFileChunk: (Text, Nat) -> ?{
           chunk : [Nat8];
           totalChunks : Nat;
           contentType : Text;
           title : Text;
           artist : Text;
       },
       collection: Collection.Collection,
       themeManager: Theme.ThemeManager,
       fileStorage: Files.FileStorage,
       buttonsManager: Buttons.ButtonsManager
   ) : Router.Config {
    {
      prefix              = null;
      identityRequirement = null;
      routes = [
        Router.getQuery("/",
          func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            Home.homePage(ctx, canisterId, collection.getCollectionName(), themeManager, buttonsManager.getAllButtons())
          }
        ),
        Router.getQuery("/item/{id}", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let idText = ctx.getRouteParam("id");

                   let id = switch (Nat.fromText(idText)) {
                       case (?num) num;
                       case null {
                           let html = collection.generateNotFoundPage(0, themeManager);
                           return ctx.buildResponse(#notFound, #html(html));
                       };
                   };

                   let html = collection.generateItemPage(id, themeManager);
                   ctx.buildResponse(#ok, #html(html))
               }),
               Router.getQuery("/collection", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let html = collection.generateCollectionPage(themeManager);
                   ctx.buildResponse(#ok, #html(html))
               }),

        // Example: Alternative route pattern /nft/{id} (works the same as /item/{id})
        Router.getQuery("/stitch/{id}", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let idText = ctx.getRouteParam("id");

                   let id = switch (Nat.fromText(idText)) {
                       case (?num) num;
                       case null {
                           let html = collection.generateNotFoundPage(0, themeManager);
                           return ctx.buildResponse(#notFound, #html(html));
                       };
                   };

                   let html = collection.generateItemPage(id, themeManager);
                   ctx.buildResponse(#ok, #html(html))
               }),

        // NEW: Meeting waiting page (first scan - waiting for more items)
        Router.getQuery("/meeting/waiting", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            Debug.print("[ROUTE] /meeting/waiting accessed");
            let _itemIdTextOpt = ctx.getQueryParam("item");

            // Get items from session (unwrap optional)
            let itemsInSession = switch (ctx.httpContext.session) {
                case null { [] };
                case (?session) {
                    switch (session.get("meeting_items")) {
                        case null { [] };
                        case (?itemsText) {
                            let parts = Iter.toArray(Text.split(itemsText, #char ','));
                            var items : [Nat] = [];
                            for (part in parts.vals()) {
                                switch (Nat.fromText(part)) {
                                    case (?n) { items := Array.concat(items, [n]); };
                                    case null {};
                                };
                            };
                            items
                        };
                    };
                };
            };

            if (itemsInSession.size() == 0) {
                Debug.print("[Waiting Page] No items in session - showing error");
                let html = "<html><body><h1>No Meeting Session</h1><p>Please scan an NFC tag to start a meeting.</p></body></html>";
                return ctx.buildResponse(#ok, #html(html));
            };

            Debug.print("[Waiting Page] Items in session: " # Nat.toText(itemsInSession.size()));

            // Check if meeting has expired (1 minute = 60 seconds = 60_000_000_000 nanoseconds)
            let meetingExpired = switch (ctx.httpContext.session) {
                case null {
                    Debug.print("[Waiting Page] No session found");
                    false
                };
                case (?session) {
                    switch (session.get("meeting_start_time")) {
                        case null {
                            Debug.print("[Waiting Page] No meeting_start_time in session");
                            false
                        };
                        case (?startTimeText) {
                            switch (Int.fromText(startTimeText)) {
                                case null {
                                    Debug.print("[Waiting Page] Invalid timestamp format: " # startTimeText);
                                    false
                                };
                                case (?startTime) {
                                    let elapsed = Time.now() - startTime;
                                    let oneMinuteInNanos : Int = 60_000_000_000;
                                    let elapsedSeconds = elapsed / 1_000_000_000;
                                    Debug.print("[Waiting Page] Timer check - Elapsed: " # Int.toText(elapsedSeconds) # "s, Expired: " # (if (elapsed > oneMinuteInNanos) { "YES" } else { "NO" }));
                                    elapsed > oneMinuteInNanos
                                };
                            };
                        };
                    };
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
                var itemsText = "";
                var first = true;
                for (id in itemsInSession.vals()) {
                    if (not first) { itemsText #= "," };
                    itemsText #= Nat.toText(id);
                    first := false;
                };

                // Clear session (including token)
                switch (ctx.httpContext.session) {
                    case null {};
                    case (?session) {
                        session.remove("meeting_items");
                        session.remove("meeting_start_time");
                        session.remove("finalize_token");
                    };
                };

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
                    let meetingStartTime = switch (ctx.httpContext.session) {
                        case null { "0" };
                        case (?session) {
                            switch (session.get("meeting_start_time")) {
                                case null { "0" };
                                case (?time) { time };
                            };
                        };
                    };

                    // Get finalize token from session to pass to frontend
                    let finalizeToken = switch (ctx.httpContext.session) {
                        case null { "" };
                        case (?session) {
                            switch (session.get("finalize_token")) {
                                case null { "" };
                                case (?token) { token };
                            };
                        };
                    };

                    let html = Meeting.generateWaitingPage(item, itemsInSession, meetingStartTime, finalizeToken, themeManager);
                    ctx.buildResponse(#ok, #html(html))
                };
            }
        }),

        // NEW: Meeting active page (multiple items scanned)
        Router.getQuery("/meeting/active", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            Debug.print("[ROUTE] /meeting/active accessed");
            // Get items from session (unwrap optional)
            let itemsInSession = switch (ctx.httpContext.session) {
                case null { [] };
                case (?session) {
                    switch (session.get("meeting_items")) {
                        case null { [] };
                        case (?itemsText) {
                            let parts = Iter.toArray(Text.split(itemsText, #char ','));
                            var items : [Nat] = [];
                            for (part in parts.vals()) {
                                switch (Nat.fromText(part)) {
                                    case (?n) { items := Array.concat(items, [n]); };
                                    case null {};
                                };
                            };
                            items
                        };
                    };
                };
            };

            if (itemsInSession.size() < 2) {
                return {
                    statusCode = 303;
                    headers = [("Location", "/meeting/waiting?item=" # Nat.toText(itemsInSession[0]))];
                    body = null;
                    streamingStrategy = null;
                };
            };

            // Check if meeting has expired (1 minute = 60 seconds = 60_000_000_000 nanoseconds)
            let meetingExpired = switch (ctx.httpContext.session) {
                case null {
                    Debug.print("[Active Page] No session found");
                    false
                };
                case (?session) {
                    switch (session.get("meeting_start_time")) {
                        case null {
                            Debug.print("[Active Page] No meeting_start_time in session");
                            false
                        };
                        case (?startTimeText) {
                            switch (Int.fromText(startTimeText)) {
                                case null {
                                    Debug.print("[Active Page] Invalid timestamp format: " # startTimeText);
                                    false
                                };
                                case (?startTime) {
                                    let elapsed = Time.now() - startTime;
                                    let oneMinuteInNanos : Int = 60_000_000_000;
                                    let elapsedSeconds = elapsed / 1_000_000_000;
                                    Debug.print("[Active Page] Timer check - Elapsed: " # Int.toText(elapsedSeconds) # "s, Expired: " # (if (elapsed > oneMinuteInNanos) { "YES" } else { "NO" }));
                                    elapsed > oneMinuteInNanos
                                };
                            };
                        };
                    };
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
                var itemsText = "";
                var first = true;
                for (id in itemsInSession.vals()) {
                    if (not first) { itemsText #= "," };
                    itemsText #= Nat.toText(id);
                    first := false;
                };

                // Clear session (including token for one-time use)
                switch (ctx.httpContext.session) {
                    case null {};
                    case (?session) {
                        session.remove("meeting_items");
                        session.remove("meeting_start_time");
                        session.remove("finalize_token"); // One-time use!
                        Debug.print("[FINALIZE] Session cleared - token deleted");
                    };
                };

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
            let meetingStartTime = switch (ctx.httpContext.session) {
                case null { "0" };
                case (?session) {
                    switch (session.get("meeting_start_time")) {
                        case null { "0" };
                        case (?time) { time };
                    };
                };
            };

            // Get finalize token from session to pass to frontend
            let finalizeToken = switch (ctx.httpContext.session) {
                case null { "" };
                case (?session) {
                    switch (session.get("finalize_token")) {
                        case null { "" };
                        case (?token) { token };
                    };
                };
            };

            let html = Meeting.generateActiveSessionPage(itemsInSession, allItems, meetingStartTime, finalizeToken, themeManager);
            ctx.buildResponse(#ok, #html(html))
        }),

        // NEW: Meeting finalize (process the meeting from session)
        Router.getAsyncUpdate("/meeting/finalize_session", func(ctx: RouteContext.RouteContext) : async* Liminal.HttpResponse {
            Debug.print("[FINALIZE] Endpoint called");

            // 1. Verify token first
            let urlToken = ctx.getQueryParam("token");
            let isManual = ctx.getQueryParam("manual");

            Debug.print("[FINALIZE] URL token: " # (switch(urlToken) { case null "NONE"; case (?t) t }));
            Debug.print("[FINALIZE] Manual flag: " # (switch(isManual) { case null "false"; case (?_) "true" }));

            let sessionToken = switch (ctx.httpContext.session) {
                case null { null };
                case (?session) { session.get("finalize_token") };
            };

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
            let itemsInSession = switch (ctx.httpContext.session) {
                case null { [] };
                case (?session) {
                    switch (session.get("meeting_items")) {
                        case null { [] };
                        case (?itemsText) {
                            let parts = Iter.toArray(Text.split(itemsText, #char ','));
                            var items : [Nat] = [];
                            for (part in parts.vals()) {
                                switch (Nat.fromText(part)) {
                                    case (?n) { items := Array.concat(items, [n]); };
                                    case null {};
                                };
                            };
                            items
                        };
                    };
                };
            };

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

                let meetingStartTime = switch (ctx.httpContext.session) {
                    case null { null };
                    case (?session) {
                        switch (session.get("meeting_start_time")) {
                            case null { null };
                            case (?timeText) { Int.fromText(timeText) };
                        };
                    };
                };

                switch (meetingStartTime) {
                    case null {
                        Debug.print("[FINALIZE] REJECTED - No start time in session");
                        let html = "<html><body><h1>Error</h1><p>Meeting start time not found.</p></body></html>";
                        return ctx.buildResponse(#badRequest, #html(html));
                    };
                    case (?startTime) {
                        let elapsed = Time.now() - startTime;
                        let elapsedSeconds = elapsed / 1_000_000_000;
                        let oneMinuteInNanos : Int = 60_000_000_000;

                        Debug.print("[FINALIZE] Timer elapsed: " # Int.toText(elapsedSeconds) # " seconds");

                        // Allow if >= 59 seconds (account for clock skew)
                        if (elapsed < (oneMinuteInNanos - 1_000_000_000)) {
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
            var itemsText = "";
            var first = true;
            for (id in itemsInSession.vals()) {
                if (not first) { itemsText #= "," };
                itemsText #= Nat.toText(id);
                first := false;
            };

            // Clear session (including token)
            switch (ctx.httpContext.session) {
                case null {};
                case (?session) {
                    session.remove("meeting_items");
                    session.remove("meeting_start_time");
                    session.remove("finalize_token");
                };
            };

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

        // Serve individual file chunks as raw bytes for reconstruction
        // MUST come before /files/{filename} route to match correctly
        Router.getQuery("/files/{filename}/chunk/{chunkId}", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            let filename = ctx.getRouteParam("filename");
            let chunkIdText = ctx.getRouteParam("chunkId");

            switch (Nat.fromText(chunkIdText)) {
                case (?chunkId) {
                    switch (getFileChunk(filename, chunkId)) {
                        case (?chunkData) {
                            {
                                statusCode = 200;
                                headers = [
                                    ("Content-Type", "application/octet-stream"),
                                    ("Cache-Control", "public, max-age=31536000")
                                ];
                                body = ?Blob.fromArray(chunkData.chunk);
                                streamingStrategy = null;
                            }
                        };
                        case null {
                            ctx.buildResponse(#notFound, #error(#message("Chunk not found")))
                        };
                    }
                };
                case null {
                    ctx.buildResponse(#badRequest, #error(#message("Invalid chunk ID")))
                };
            }

        }),

        // Serve backend-stored files with NFC protection support
        // Works with query parameters for NFC: /files/filename?uid=...&cmac=...&ctr=...
        Router.getQuery("/files/{filename}", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            let filename = ctx.getRouteParam("filename");

            // Get first chunk to check if file exists
            switch (getFileChunk(filename, 0)) {
                case (?fileInfo) {
                    // Generate HTML page using files.mo
                    let html = fileStorage.generateFilePage(filename, fileInfo, collection);
                    ctx.buildResponse(#ok, #html(html))
                };
                case null {
                    ctx.buildResponse(#notFound, #error(#message("File not found")))
                };
            };
        }),

        Router.getQuery("/{path}",
          func(ctx) : Liminal.HttpResponse {
            ctx.buildResponse(#notFound, #error(#message("Not found")))
          }
        ),
      ];
    }
  }
}
