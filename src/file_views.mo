import Text "mo:core/Text";
import EvorevFonts "ui/evorev_fonts";
import EvorevTheme "ui/evorev_theme";

module {
    func escapeHtml(value : Text) : Text {
        var escaped = Text.replace(value, #text("&"), "&amp;");
        escaped := Text.replace(escaped, #text("<"), "&lt;");
        escaped := Text.replace(escaped, #text(">"), "&gt;");
        escaped := Text.replace(escaped, #text("\""), "&quot;");
        Text.replace(escaped, #text("'"), "&#39;");
    };

    public func generateAudioWrapper(filename : Text, token : Text) : Text {
        let safeFilename = escapeHtml(filename);
        let streamUrl = escapeHtml("/api/stream/" # filename # "?token=" # token);
        "<!doctype html><html lang=\"fr\"><head>"
        # "<meta charset=\"utf-8\">"
        # "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        # "<title>" # safeFilename # "</title>"
        # "<style>" # EvorevFonts.css # EvorevTheme.css # "</style>"
        # "</head><body><main class=\"error-container\">"
        # "<h1 class=\"item-title\">" # safeFilename # "</h1>"
        # "<audio controls autoplay><source src=\"" # streamUrl # "\" type=\"audio/mp4\"></audio>"
        # "<p>Accès temporaire validé pour 120 secondes.</p>"
        # "</main></body></html>";
    };
};
