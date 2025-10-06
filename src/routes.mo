
import Router       "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal      "mo:liminal";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Blob "mo:core/Blob";
// import Route "mo:liminal/Route";
import Collection "collection";

module Routes {
   public func routerConfig(
       canisterId: Text,
       getFileAsDataUrl: (Text) -> ?Text,
       getFileChunk: (Text, Nat) -> ?{
           chunk : [Nat8];
           totalChunks : Nat;
           contentType : Text;
           title : Text;
           artist : Text;
       },
       collection: Collection.Collection
   ) : Router.Config {
    {
      prefix              = null;
      identityRequirement = null;
      routes = [
        Router.getQuery("/",
          func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
            let testHtml = "<!DOCTYPE html>"
                  # "<html lang='fr'>"
                  # "<head>"
                  # "    <meta charset='UTF-8'>"
                  # "    <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
                  # "    <title>Collection d'Evorev</title>"
                  # "</head>"
                  # "<body style='font-family: Arial; text-align: center; padding: 50px;'>"
                  # "    <div style='margin-bottom: 20px;'>"
                                # "        <a href='https://discord.gg/' style='text-decoration: none;'>"
                                # "            <button style='background-color: #90EE90; color: white; padding: 12px 24px; margin: 0 10px; border: none; border-radius: 5px; cursor: pointer; font-size: 16px;'>Rejoins la communauté d'Évorev</button>"
                                # "        </a>"
                                # "        <a href='http://" # canisterId # ".raw.icp0.io/collection' style='text-decoration: none;'>"
                                # "            <button style='background-color: #90EE90; color: white; padding: 12px 24px; margin: 0 10px; border: none; border-radius: 5px; cursor: pointer; font-size: 16px;'>Voir la collection</button>"
                                # "        </a>"
                                # "    </div>"
                  # "    <div style='text-align: center; margin-bottom: 20px;'>"
                  # (switch (getFileAsDataUrl("Logo")) {
                      case (?dataUrl) "        <img src='" # dataUrl # "' alt='logo collection' style='width: 300px; height: auto; margin-bottom: 15px; display: block; margin-left: auto; margin-right: auto;'/>";
                      case null "        <!-- Image not found -->";
                  })
                  # "        <h1 style='color: #90EE90; margin: 0;'>Collection association Lo13to</h1>"
                  # "    </div>"
                  # "</body>"
                  # "</html>";
            ctx.buildResponse(#ok, #html(testHtml))
          }
        ),
        Router.getQuery("/item/{id}", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let idText = ctx.getRouteParam("id");

                   let id = switch (Nat.fromText(idText)) {
                       case (?num) num;
                       case null {
                           let html = collection.generateNotFoundPage(0);
                           return ctx.buildResponse(#notFound, #html(html));
                       };
                   };

                   let html = collection.generateItemPage(id);
                   ctx.buildResponse(#ok, #html(html))
               }),
               Router.getQuery("/collection", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let html = collection.generateCollectionPage();
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
                    // For single chunk files, serve directly as raw bytes
                    if (fileInfo.totalChunks == 1) {
                        {
                            statusCode = 200;
                            headers = [
                                ("Content-Type", fileInfo.contentType),
                                ("Cache-Control", "public, max-age=31536000")
                            ];
                            body = ?Blob.fromArray(fileInfo.chunk);
                            streamingStrategy = null;
                        }
                    } else {
                        // Multi-chunk files: return HTML that reconstructs via JavaScript
                        let html = "<!DOCTYPE html><html><head>"
                            # "<meta charset='UTF-8'>"
                            # "<meta name='viewport' content='width=device-width,initial-scale=1.0'>"
                            # "<title>" # filename # "</title>"
                            # "<style>"
                            # "body{margin:0;display:flex;justify-content:center;align-items:center;min-height:100vh;background:#f5f5f5;flex-direction:column;font-family:Arial;}"
                            # "img,audio,video{max-width:90vw;max-height:85vh;box-shadow:0 4px 12px rgba(0,0,0,0.15);border-radius:8px;}"
                            # "#status{padding:20px;text-align:center;color:#666;}"
                            # ".error{color:red;}"
                            # ".info{margin-top:20px;padding:10px 20px;background:white;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);display:none;}"
                            # "</style>"
                            # "</head><body>"
                            # "<div id='status'>Loading " # filename # "...</div>"
                            # "<div id='media'></div>"
                            # "<div class='info' id='info'></div>"
                            # "<script>"
                            # "const filename='" # filename # "';"
                            # "const totalChunks=" # Nat.toText(fileInfo.totalChunks) # ";"
                            # "const contentType='" # fileInfo.contentType # "';"
                            # "const baseUrl=window.location.protocol+'//'+window.location.host;"
                            # "async function load(){"
                            # "const status=document.getElementById('status');"
                            # "const media=document.getElementById('media');"
                            # "const info=document.getElementById('info');"
                            # "try{"
                            # "const chunks=[];"
                            # "for(let i=0;i<totalChunks;i++){"
                            # "status.textContent='Loading '+filename+'... ('+(i+1)+'/'+totalChunks+' chunks)';"
                            # "const url=baseUrl+'/files/'+filename+'/chunk/'+i;"
                            # "console.log('Fetching chunk '+i+' from:',url);"
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
                            # "console.log('Total bytes:',totalBytes);"
                            # "const blob=new Blob([combined],{type:contentType});"
                            # "const blobUrl=URL.createObjectURL(blob);"
                            # "console.log('Blob URL created:',blobUrl);"
                            # "let element;"
                            # "if(contentType.startsWith('image/')){element=document.createElement('img');}"
                            # "else if(contentType.startsWith('audio/')){element=document.createElement('audio');element.controls=true;}"
                            # "else if(contentType.startsWith('video/')){element=document.createElement('video');element.controls=true;}"
                            # "else{element=document.createElement('img');}"
                            # "element.src=blobUrl;"
                            # "element.onerror=function(){console.error('Image load failed');};"
                            # "element.onload=function(){console.log('Image loaded successfully!');};"
                            # "media.appendChild(element);"
                            # "status.style.display='none';"
                            # "const sizeKB=Math.round(totalBytes/1024);"
                            # "info.innerHTML='<strong>'+filename+'</strong> | '+sizeKB+' KB | '+totalChunks+' chunks';"
                            # "info.style.display='block';"
                            # "}catch(e){"
                            # "status.innerHTML='<div class=\"error\">Error: '+e.message+'</div>';"
                            # "console.error(e);"
                            # "}"
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
