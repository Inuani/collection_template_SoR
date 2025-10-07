import Liminal "mo:liminal";
import RouteContext "mo:liminal/RouteContext";
import Text "mo:core/Text";

module Home {
    public func homePage(
        ctx: RouteContext.RouteContext,
        canisterId: Text,
        collectionName: Text
    ) : Liminal.HttpResponse {
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
              # "        <img src='/logo.webp' alt='logo collection' style='width: 300px; height: auto; margin-bottom: 15px; display: block; margin-left: auto; margin-right: auto;'/>"
              # "        <h1 style='color: #90EE90; margin: 0;'>" # collectionName # "</h1>"
              # "    </div>"
              # "</body>"
              # "</html>";
        ctx.buildResponse(#ok, #html(testHtml))
    }
}
