
import Router       "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal      "mo:liminal";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Blob "mo:core/Blob";
import Array "mo:core/Array";
// import Route "mo:liminal/Route";
import Collection "collection";
import CollectionView "collection_view";
import Home "home";
import Theme "utils/theme";
import Files "files";
import Buttons "utils/buttons";
import StitchingRoutes "stitching_routes";
import HttpAssets "mo:http-assets@0";


module Routes {
    public type StreamingCallbackResponse = {
        body : Blob;
        token : ?Blob;
    };

   public func routerConfig(
       canisterId: Text,
       streamingCallback: shared query (Blob) -> async StreamingCallbackResponse,
       collection: Collection.Collection,
       themeManager: Theme.ThemeManager,
       fileStorage: Files.FileStorage,
       buttonsManager: Buttons.ButtonsManager
   ) : Router.Config {
    {
      prefix              = null;
      identityRequirement = null;
      routes = Array.flatten([
        [Router.get("/", #query_(
          func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            Home.homePage(ctx, canisterId, collection.getCollectionName(), themeManager, buttonsManager.getAllButtons())
          }
        )),
        Router.get("/item/{id}", #query_(func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let idText = ctx.getRouteParam("id");

                   let id = switch (Nat.fromText(idText)) {
                       case (?num) num;
                       case null {
                           let html = CollectionView.generateNotFoundPage(0, themeManager);
                           return ctx.buildResponse(#notFound, #html(html));
                       };
                   };

                   let html = CollectionView.generateItemPage(collection, id, themeManager);
                   ctx.buildResponse(#ok, #html(html))
               })),
               Router.get("/collection", #query_(func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let html = CollectionView.generateCollectionPage(collection, themeManager);
                   ctx.buildResponse(#ok, #html(html))
               })),

        Router.get("/stitch/{id}", #query_(func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let idText = ctx.getRouteParam("id");

                   let id = switch (Nat.fromText(idText)) {
                       case (?num) num;
                       case null {
                           let html = CollectionView.generateNotFoundPage(0, themeManager);
                           return ctx.buildResponse(#notFound, #html(html));
                       };
                   };

                   let html = CollectionView.generateItemPage(collection, id, themeManager);
                   ctx.buildResponse(#ok, #html(html))
               })),

        ],

        // Stitching routes (extracted to separate module)
        StitchingRoutes.getStitchingRoutes(collection, themeManager),

        [

        // Streaming file access
        // Returns the first chunk directly and provides a streaming callback for the rest
        Router.get("/files/{filename}", #query_(func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            let filename = ctx.getRouteParam("filename");

            switch (fileStorage.getFileStart(filename)) {
                case (null) {
                     ctx.buildResponse(#notFound, #error(#message("File not found")))
                };
                case (?start) {
                    // Construct streaming strategy if more chunks exist
                    // Construct streaming strategy if more chunks exist
                    let strategy = switch (start.nextToken) {
                        case (null) null;
                        case (?token) ?#callback({
                            callback = streamingCallback;
                            token = Blob.fromArray(Files.tokenToBlob(token));
                        });
                    };
                    
                    {
                        statusCode = 200;
                        headers = [
                            ("Content-Type", start.contentType),
                            ("Cache-Control", "public, max-age=31536000"),
                            ("Access-Control-Allow-Origin", "*"),
                            ("Accept-Ranges", "bytes")
                        ];
                        body = ?Blob.fromArray(start.chunk);
                        streamingStrategy = strategy;
                    }
                };
            };
        })),

        Router.get("/{path}", #query_(
          func(ctx) : Liminal.HttpResponse {
            ctx.buildResponse(#notFound, #error(#message("Not found")))
          }
        )),
      ]]);
    }
  }
}
