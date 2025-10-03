
import Router       "mo:liminal/Router";
import RouteContext "mo:liminal/RouteContext";
import Liminal      "mo:liminal";
import Text "mo:new-base/Text";
import Nat "mo:base/Nat";
import Route "mo:liminal/Route";
import BleuCollection "collection";

module Routes {
   public func routerConfig(canisterId: Text) : Router.Config {
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
                  # "        <img src='/logo.webp' alt='logo collection' style='width: 100px; height: auto; margin-bottom: 15px; display: block; margin-left: auto; margin-right: auto;'/>"
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
                           let html = BleuCollection.generateNotFoundPage(0);
                           return ctx.buildResponse(#notFound, #html(html));
                       };
                   };

                   let html = BleuCollection.generateBleuPage(id);
                   ctx.buildResponse(#ok, #html(html))
               }),
               Router.getQuery("/collection", func(ctx: RouteContext.RouteContext) : Liminal.HttpResponse {
                   let html = BleuCollection.generateCollectionPage();
                   ctx.buildResponse(#ok, #html(html))
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
