import EvorevFonts "../ui/evorev_fonts";
import EvorevTheme "../ui/evorev_theme";

module {

    public func generateInvalidScanPage() : Text {
        "<!doctype html><html lang=\"fr\"><head><meta charset=\"utf-8\">" #
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" #
        "<title>Scan invalide · Collection d'Évorev</title><style>" #
        EvorevFonts.css # EvorevTheme.css # "</style></head><body>" #
        "<main class=\"error-container\"><div class=\"error-icon\">" #
        "<svg fill=\"#ff7a00\" width=\"40\" height=\"40\" viewBox=\"0 0 20 20\" aria-hidden=\"true\">" #
        "<path fill-rule=\"evenodd\" d=\"M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z\" clip-rule=\"evenodd\"/>" #
        "</svg></div><h1 class=\"error-title\">Scan invalide</h1>" #
        "<p class=\"error-message\">Ce lien n'est pas valide ou a expiré.<br><br>Veuillez scanner à nouveau le tag NFC du vêtement.</p>" #
        "<div><a href=\"/collection\" class=\"back-button\">Voir la Collection</a>" #
        "<a href=\"/\" class=\"secondary-button\">Accueil</a></div></main></body></html>";
    };

};
