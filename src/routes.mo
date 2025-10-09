
import Router       "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal      "mo:liminal";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Blob "mo:core/Blob";
// import Route "mo:liminal/Route";
import Collection "collection";
import Home "home";
import Theme "theme";

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
       themeManager: Theme.ThemeManager
   ) : Router.Config {
    {
      prefix              = null;
      identityRequirement = null;
      routes = [
        Router.getQuery("/",
          func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            Home.homePage(ctx, canisterId, collection.getCollectionName(), themeManager)
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
                    // Extract item number from filename (e.g., certificat_0 -> 0)
                    let itemNumberText = Text.replace(filename, #text("certificat_"), "");

                    // Get item name from collection
                    let itemDisplay = switch (Nat.fromText(itemNumberText)) {
                        case (?itemId) {
                            switch (collection.getItem(itemId)) {
                                case (?item) item.name;
                                case null itemNumberText;
                            };
                        };
                        case null itemNumberText;
                    };

                    // For single chunk files, display in HTML page with certificate text
                    if (fileInfo.totalChunks == 1) {
                        let html = "<!DOCTYPE html><html><head>"
                            # "<meta charset='UTF-8'>"
                            # "<meta name='viewport' content='width=device-width,initial-scale=1.0'>"
                            # "<title>" # filename # "</title>"
                            # "<style>"
                            # "*{margin:0;padding:0;box-sizing:border-box;}"
                            # "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#fff;min-height:100vh;display:flex;flex-direction:column;}"
                            # ".container{flex:1;display:flex;flex-direction:column;width:100%;max-width:100vw;padding:20px;}"
                            # ".back-link{display:inline-block;margin-bottom:1rem;color:#2563eb;text-decoration:none;font-weight:500;}"
                            # ".back-link:hover{text-decoration:underline;}"
                            # ".certificate-text{text-align:center;margin-bottom:1rem;font-size:16px;color:#1f2937;}"
                            # ".media-container{flex:1;display:flex;justify-content:center;align-items:center;background:#fff;}"
                            # "#media{width:100%;height:100%;display:flex;justify-content:center;align-items:center;}"
                            # "img{max-width:100%;max-height:calc(100vh - 120px);width:auto;height:auto;object-fit:contain;display:block;}"
                            # "audio,video{max-width:100%;}"
                            # "</style>"
                            # "</head><body>"
                            # "<div class='container'>"
                            # "<a href='/item/" # itemNumberText # "' class='back-link'>Retour à la collection</a>"
                            # "<div class='certificate-text'>Scan valide - certificat d'authenticité pour l'item " # itemDisplay # " :</div>"
                            # "<div class='media-container'><div id='media'></div></div>"
                            # "</div>"
                            # "<script>"
                            # "const filename='" # filename # "';"
                            # "const contentType='" # fileInfo.contentType # "';"
                            # "const baseUrl=window.location.protocol+'//'+window.location.host;"
                            # "async function load(){"
                            # "const media=document.getElementById('media');"
                            # "try{"
                            # "const url=baseUrl+'/files/'+filename+'/chunk/0';"
                            # "const response=await fetch(url);"
                            # "if(!response.ok)throw new Error('Failed to load: HTTP '+response.status);"
                            # "const arrayBuffer=await response.arrayBuffer();"
                            # "const bytes=new Uint8Array(arrayBuffer);"
                            # "const blob=new Blob([bytes],{type:contentType});"
                            # "const blobUrl=URL.createObjectURL(blob);"
                            # "let element;"
                            # "if(contentType.startsWith('image/')){element=document.createElement('img');}"
                            # "else if(contentType.startsWith('audio/')){element=document.createElement('audio');element.controls=true;}"
                            # "else if(contentType.startsWith('video/')){element=document.createElement('video');element.controls=true;}"
                            # "else{element=document.createElement('img');}"
                            # "element.src=blobUrl;"
                            # "media.appendChild(element);"
                            # "}catch(e){console.error(e);}"
                            # "}"
                            # "load();"
                            # "</script>"
                            # "</body></html>";

                        ctx.buildResponse(#ok, #html(html))
                    } else {
                        // Multi-chunk files: return HTML that reconstructs via JavaScript

                        let html = "<!DOCTYPE html><html><head>"
                            # "<meta charset='UTF-8'>"
                            # "<meta name='viewport' content='width=device-width,initial-scale=1.0'>"
                            # "<title>" # filename # "</title>"
                            # "<style>"
                            # "*{margin:0;padding:0;box-sizing:border-box;}"
                            # "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#fff;min-height:100vh;display:flex;flex-direction:column;}"
                            # ".container{flex:1;display:flex;flex-direction:column;width:100%;max-width:100vw;padding:20px;}"
                            # ".back-link{display:inline-block;margin-bottom:1rem;color:#2563eb;text-decoration:none;font-weight:500;}"
                            # ".back-link:hover{text-decoration:underline;}"
                            # ".certificate-text{text-align:center;margin-bottom:1rem;font-size:16px;color:#1f2937;}"
                            # ".media-container{flex:1;display:flex;justify-content:center;align-items:center;background:#fff;}"
                            # "#media{width:100%;height:100%;display:flex;justify-content:center;align-items:center;}"
                            # "img{max-width:100%;max-height:calc(100vh - 120px);width:auto;height:auto;object-fit:contain;display:block;}"
                            # "audio,video{max-width:100%;}"
                            # "</style>"
                            # "</head><body>"
                            # "<div class='container'>"
                            # "<a href='/item/" # itemNumberText # "' class='back-link'>Retour à la collection</a>"
                            # "<div class='certificate-text'>Scan valide - certificat d'authenticité pour l'item " # itemDisplay # " :</div>"
                            # "<div class='media-container'><div id='media'></div></div>"
                            # "</div>"
                            # "<script>"
                            # "const filename='" # filename # "';"
                            # "const totalChunks=" # Nat.toText(fileInfo.totalChunks) # ";"
                            # "const contentType='" # fileInfo.contentType # "';"
                            # "const baseUrl=window.location.protocol+'//'+window.location.host;"
                            # "async function load(){"
                            # "const media=document.getElementById('media');"
                            # "try{"
                            # "const chunks=[];"
                            # "for(let i=0;i<totalChunks;i++){"
                            # "const url=baseUrl+'/files/'+filename+'/chunk/'+i;"
                            # "const response=await fetch(url);"
                            # "if(!response.ok)throw new Error('Chunk '+i+' failed: HTTP '+response.status);"
                            # "const arrayBuffer=await response.arrayBuffer();"
                            # "const bytes=new Uint8Array(arrayBuffer);"
                            # "chunks.push(bytes);"
                            # "}"
                            # "const totalBytes=chunks.reduce((acc,chunk)=>acc+chunk.length,0);"
                            # "const combined=new Uint8Array(totalBytes);"
                            # "let offset=0;"
                            # "for(const chunk of chunks){combined.set(chunk,offset);offset+=chunk.length;}"
                            # "const blob=new Blob([combined],{type:contentType});"
                            # "const blobUrl=URL.createObjectURL(blob);"
                            # "let element;"
                            # "if(contentType.startsWith('image/')){element=document.createElement('img');}"
                            # "else if(contentType.startsWith('audio/')){element=document.createElement('audio');element.controls=true;}"
                            # "else if(contentType.startsWith('video/')){element=document.createElement('video');element.controls=true;}"
                            # "else{element=document.createElement('img');}"
                            # "element.src=blobUrl;"
                            # "media.appendChild(element);"
                            # "}catch(e){console.error(e);}"
                            # "}"

                            # "load();"
                            # "</script>"
                            # "</body></html>";
                        ctx.buildResponse(#ok, #html(html))
                    };
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
