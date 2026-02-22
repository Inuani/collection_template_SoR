import Liminal "mo:liminal";
import RouteContext "mo:liminal/RouteContext";
import Text "mo:core/Text";
import Buttons "utils/buttons";

module {
    public func homePage(
        ctx : RouteContext.RouteContext,
        canisterId : Text,
        collectionName : Text,
        buttons : [Buttons.Button],
    ) : Liminal.HttpResponse {

        // Add collection button first
        var buttonsHtml = "        <a href='http://" # canisterId # ".raw.icp0.io/collection' class='home-button primary' style='text-decoration: none; display: inline-block; margin: 10px;'>Voir la collection</a>";

        // Generate custom buttons HTML dynamically
        for (btn in buttons.vals()) {
            buttonsHtml #= "        <a href='" # btn.link # "' class='home-button primary' style='text-decoration: none; display: inline-block; margin: 10px;'>" # btn.text # "</a>";
        };

        let testHtml = "<!DOCTYPE html>\n"
        # "<html lang='fr'>\n"
        # "<head>\n"
        # "    <meta charset='UTF-8'>\n"
        # "    <meta name='viewport' content='width=device-width, initial-scale=1.0'>\n"
        # "    <title>Collection d'Evorev</title>\n"
        # "    <link rel='stylesheet' href='/theme.css'>\n"
        # "</head>\n"
        # "<body class='home-body'>\n"
        # "    <div class='home-header-container'>\n"
        # "        <img src='/logo.webp' alt='logo collection'/>\n"
        # "        <h1>" # collectionName # "</h1>\n"
        # "    </div>\n"
        # "    <div>\n"
        # buttonsHtml # "\n"
        # "    </div>\n"
        # "</body>\n"
        # "</html>";
        ctx.buildResponse(#ok, #html(testHtml));
    };
};
