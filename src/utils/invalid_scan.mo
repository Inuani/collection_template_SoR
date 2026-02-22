// src/invalid_scan.mo
module {

    public func generateInvalidScanPage() : Text {
        "<!DOCTYPE html>
<html lang=\"fr\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Scan Invalide - Collection Ordre d'Évorev</title>
    <link rel=\"stylesheet\" href=\"/theme.css\">
</head>
<body>
    <div class=\"error-container\">
        <div class=\"error-icon\">
            <svg fill=\"#e53e3e\" width=\"40\" height=\"40\" viewBox=\"0 0 20 20\">
                <path fill-rule=\"evenodd\" d=\"M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z\" clip-rule=\"evenodd\"/>
            </svg>
        </div>
        <h1 class=\"error-title\">Scan Invalide</h1>
        <p class=\"error-message\">
            Désolé, ce lien n'est pas valide ou a expiré.
            <br><br>
            Veuillez scanner le NFC tag du vêtement pour accéder à ce contenu.
        </p>
        <div>
            <a href=\"/collection\" class=\"back-button\">
                Voir la Collection
            </a>
            <a href=\"/\" class=\"secondary-button\">
                Accueil
            </a>
        </div>
    </div>
</body>
</html>";
    };

};
