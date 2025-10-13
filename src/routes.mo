
import Router       "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import HttpContext  "mo:liminal/HttpContext";
import Session      "mo:liminal/Session";
import Liminal      "mo:liminal";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Blob "mo:core/Blob";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
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
        Router.getQuery("/nft/{id}", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
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
                let html = "<html><body><h1>No Meeting Session</h1><p>Please scan an NFC tag to start a meeting.</p></body></html>";
                return ctx.buildResponse(#ok, #html(html));
            };

            let firstItemId = itemsInSession[0];
            switch (collection.getItem(firstItemId)) {
                case null {
                    let html = "<html><body><h1>Error</h1><p>Item not found.</p></body></html>";
                    ctx.buildResponse(#notFound, #html(html))
                };
                case (?item) {
                    let html = Meeting.generateWaitingPage(firstItemId, item, itemsInSession, themeManager);
                    ctx.buildResponse(#ok, #html(html))
                };
            }
        }),

        // NEW: Meeting active page (multiple items scanned)
        Router.getQuery("/meeting/active", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
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

            let allItems = collection.getAllItems();
            let html = Meeting.generateActiveSessionPage(itemsInSession, allItems, themeManager);
            ctx.buildResponse(#ok, #html(html))
        }),

        // NEW: Meeting finalize (process the meeting from session)
        Router.getAsyncUpdate("/meeting/finalize_session", func(ctx: RouteContext.RouteContext) : async* Liminal.HttpResponse {
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
                let html = "<html><body><h1>Error</h1><p>Need at least 2 items to finalize a meeting.</p></body></html>";
                return ctx.buildResponse(#badRequest, #html(html));
            };

            // Award tokens to all items
            for (itemId in itemsInSession.vals()) {
                ignore collection.addTokens(itemId, 10); // 10 tokens per meeting
            };

            // Generate success message
            var itemsText = "";
            var first = true;
            for (id in itemsInSession.vals()) {
                if (not first) { itemsText #= "," };
                itemsText #= Nat.toText(id);
                first := false;
            };

            // Clear session
            switch (ctx.httpContext.session) {
                case null {};
                case (?session) {
                    session.remove("meeting_items");
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

        // Meeting session route (LEGACY - keep for backwards compatibility)
        Router.getQuery("/meeting/session", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            // Get challenge from query parameter
            let challengeOpt = ctx.getQueryParam("challenge");
            let itemIdTextOpt = ctx.getQueryParam("item");

            let challengeValue = switch (challengeOpt) {
                case (?ch) ch;
                case null {
                    let html = Meeting.generateMeetingErrorPage("Missing session challenge", themeManager);
                    return ctx.buildResponse(#badRequest, #html(html));
                };
            };

            let itemIdValue = switch (itemIdTextOpt) {
                case (?idText) Nat.fromText(idText);
                case null null;
            };

            // Get session status
            switch (collection.getMeetingSessionStatus(challengeValue)) {
                case (#err(msg)) {
                    let html = Meeting.generateMeetingErrorPage(msg, themeManager);
                    ctx.buildResponse(#notFound, #html(html))
                };
                case (#ok(status)) {
                    // Get the first item or the specified item
                    let currentItemId = switch (itemIdValue) {
                        case (?id) id;
                        case null {
                            if (status.items_scanned.size() > 0) {
                                status.items_scanned[0]
                            } else {
                                let html = Meeting.generateMeetingErrorPage("No items in session", themeManager);
                                return ctx.buildResponse(#badRequest, #html(html));
                            }
                        };
                    };

                    switch (collection.getItem(currentItemId)) {
                        case null {
                            let html = Meeting.generateMeetingErrorPage("Item not found", themeManager);
                            ctx.buildResponse(#notFound, #html(html))
                        };
                        case (?item) {
                            let allItems = collection.getAllItems();
                            let html = Meeting.generateMeetingPage(
                                currentItemId,
                                item,
                                challengeValue,
                                status.items_scanned,
                                status.expires_in,
                                allItems,
                                themeManager
                            );
                            ctx.buildResponse(#ok, #html(html))
                        };
                    }
                };
            }
        }),

        // Meeting finalization route - must be async update to actually finalize
        Router.getAsyncUpdate("/meeting/finalize", func(ctx: RouteContext.RouteContext) : async* Liminal.HttpResponse {
            let challengeOpt = ctx.getQueryParam("challenge");

            let challengeValue = switch (challengeOpt) {
                case (?ch) ch;
                case null {
                    let html = Meeting.generateMeetingErrorPage("Missing session challenge", themeManager);
                    return ctx.buildResponse(#badRequest, #html(html));
                };
            };

            // Call the finalization function
            switch (collection.finalizeMeeting(challengeValue)) {
                case (#ok(result)) {
                    // Success! Redirect to success page
                    let meetingId = result.meeting_id;
                    var itemsText = "";
                    var first = true;
                    for (itemId in result.items_rewarded.vals()) {
                        if (not first) {
                            itemsText #= ",";
                        };
                        itemsText #= Nat.toText(itemId);
                        first := false;
                    };

                    let redirectUrl = "/meeting/success?id=" # meetingId # "&items=" # itemsText;

                    return {
                        statusCode = 303; // See Other redirect
                        headers = [
                            ("Location", redirectUrl),
                            ("Content-Type", "text/html")
                        ];
                        body = ?Text.encodeUtf8("<html><body>Redirecting...</body></html>");
                        streamingStrategy = null;
                    };
                };
                case (#err(errorMsg)) {
                    // Error - show error page
                    let html = Meeting.generateMeetingErrorPage(errorMsg, themeManager);
                    ctx.buildResponse(#ok, #html(html))
                };
            }
        }),

        // Meeting success route (Updated to work with session-based system)
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
