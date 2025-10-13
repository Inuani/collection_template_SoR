import Liminal "mo:liminal";
import RouteContext "mo:liminal/RouteContext";
import Text "mo:core/Text";
import Theme "theme";

module Home {
    public func homePage(
        ctx: RouteContext.RouteContext,
        canisterId: Text,
        collectionName: Text,
        themeManager: Theme.ThemeManager
    ) : Liminal.HttpResponse {
        let primary = themeManager.getPrimary();

        let testHtml = "<!DOCTYPE html>"
              # "<html lang='fr'>"
              # "<head>"
              # "    <meta charset='UTF-8'>"
              # "    <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
              # "    <title>Collection d'Evorev</title>"
              # "</head>"
              # "<body style='font-family: Arial; text-align: center; padding: 50px; background: white;'>"
              # "    <style>"
              # "        .header-container { display: flex; flex-direction: row; align-items: center; justify-content: center; gap: 20px; margin-bottom: 40px; }"
              # "        .header-container img { width: 150px; height: auto; }"
              # "        .header-container h1 { color: " # primary # "; margin: 0; }"
              # "        @media (max-width: 768px) {"
              # "            .header-container { flex-direction: column; gap: 15px; }"
              # "        }"
              # "    </style>"
              # "    <div class='header-container'>"
              # "        <img src='/logo.webp' alt='logo collection'/>"
              # "        <h1>" # collectionName # "</h1>"
              # "    </div>"
              # "    <div style='margin-bottom: 20px;'>"
              # "        <a href='https://discord.gg/' style='text-decoration: none; display: inline-block; margin: 10px;'>"
              # "            <button style='background-color: " # primary # "; color: white; padding: 12px 24px; border: none; border-radius: 5px; cursor: pointer; font-size: 16px;'>Rejoins la communauté d'Évorev</button>"
              # "        </a>"
              # "        <a href='http://" # canisterId # ".raw.icp0.io/collection' style='text-decoration: none; display: inline-block; margin: 10px;'>"
              # "            <button style='background-color: " # primary # "; color: white; padding: 12px 24px; border: none; border-radius: 5px; cursor: pointer; font-size: 16px;'>Voir la collection</button>"
              # "        </a>"
              # "    </div>"
              # "</body>"
              # "</html>";
        ctx.buildResponse(#ok, #html(testHtml))
    }
}
