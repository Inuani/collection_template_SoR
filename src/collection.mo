import Text "mo:base/Text";
import Nat "mo:base/Nat";

module {
    // Collection data - you can expand this with more properties
    public type Item = {
        id: Nat;
        name: Text;
        thumbnailUrl: Text; // Image for collection grid
        imageUrl: Text;     // Full-size image for detail page
        description: Text;
        rarity: Text;
        attributes: [(Text, Text)]; // key-value pairs for additional attributes
    };

    // Mock data for your collection - replace with your actual data source
    private let itemCollection: [Item] = [
        {
            id = 0;
            name = "Hoodie #0";
            thumbnailUrl = "/item0_thumb.webp";
            imageUrl = "/item0.webp";
            description = "pull en lien avec l'événement du 30 avril";
            rarity = "Légendaire";
            attributes = [("Type", "Sky"), ("Intensity", "Light"), ("", "Calm")];
        },
        {
            id = 1;
            name = "Hoodie #1";
            thumbnailUrl = "/item1_thumb.webp";
            imageUrl = "/item1.webp";
            description = "The mysterious deep blue of ocean trenches";
            rarity = "Rare";
            attributes = [("Type", "Ocean"), ("Aura", "+100"), ("Forme", "Triangle")];
        },
        {
            id = 2;
            name = "Hoodie #2";
            thumbnailUrl = "/item2_thumb.webp";
            imageUrl = "/item2.webp";
            description = "The intense blue-black of a stormy midnight sky";
            rarity = "Rare";
            attributes = [("Type", "Storm"), ("Intensity", "Deep"), ("Mood", "Mysterious")];
        },
        {
            id = 3;
            name = "Hoodie #3";
            thumbnailUrl = "/item3_thumb.webp";
            imageUrl = "/item3.webp";
            description = "The intense blue-black of a stormy midnight sky";
            rarity = "Rare";
            attributes = [("Type", "Storm"), ("Intensity", "Deep"), ("Mood", "Mysterious")];
        }
    ];

    // Get a specific item by ID
    public func getItem(id: Nat): ?Item {
        if (id < itemCollection.size()) {
            ?itemCollection[id]
        } else {
            null
        }
    };

    // Generate HTML page for a specific item
    public func generateItemPage(id: Nat): Text {
        switch (getItem(id)) {
            case (?item) generateItemDetailPage(item);
            case null generateNotFoundPage(id);
        }
    };

    // Generate the main collection page showing all items
    public func generateCollectionPage(): Text {
        let itemsGrid = generateItemsGrid();

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Collection association LO13TO</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: white;
            min-height: 100vh;
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }
        h1 {
            text-align: center;
            color: #333;
            font-size: 3rem;
            margin-bottom: 2rem;
        }
        .items-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 2rem;
            margin-top: 2rem;
        }
        .item-card {
            background: white;
            border-radius: 15px;
            padding: 1.5rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            text-decoration: none;
            color: inherit;
        }
        .item-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 20px 40px rgba(0,0,0,0.3);
        }
        .item-image {
            width: 100%;
            height: auto;
            max-height: 300px;
            object-fit: contain;
            border-radius: 10px;
            margin-bottom: 1rem;
        }
        .item-title {
            font-size: 1.5rem;
            font-weight: 600;
            margin-bottom: 0.5rem;
            color: #2d3748;
        }
        .item-id {
            color: #718096;
            font-size: 0.9rem;
            margin-bottom: 0.5rem;
        }
        .item-rarity {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: 500;
            margin-bottom: 0.5rem;
        }
        .rarity-common { background: #e6fffa; color: #047857; }
        .rarity-rare { background: #dbeafe; color: #1e40af; }
        .rarity-epic { background: #faf5ff; color: #7c3aed; }
        .item-description {
            color: #4a5568;
            line-height: 1.5;
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <h1>Collection de l'Ordre d'Évorev</h1>
        <div class=\"items-grid\">
            " # itemsGrid # "
        </div>
    </div>
</body>
</html>"
    };

    // Generate individual item page
    private func generateItemDetailPage(item: Item): Text {
        let attributesHtml = generateAttributesHtml(item.attributes);
        let rarityClass = "rarity-" # Text.toLowercase(item.rarity);

        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>" # item.name # " - Collection association LO13TO</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: white;
            min-height: 100vh;
            color: #333;
            padding: 2rem;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            padding: 2rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.2);
        }
        .back-link {
            display: inline-block;
            margin-bottom: 2rem;
            color: #667eea;
            text-decoration: none;
            font-weight: 500;
        }
        .back-link:hover {
            text-decoration: underline;
        }
        .item-header {
            text-align: center;
            margin-bottom: 2rem;
        }
        .item-title {
            font-size: 2.5rem;
            font-weight: 700;
            color: #2d3748;
            margin-bottom: 0.5rem;
        }
        .item-id {
            color: #718096;
            font-size: 1.1rem;
        }
        .item-image {
            width: 100%;
            max-width: 400px;
            height: auto;
            object-fit: contain;
            border-radius: 15px;
            margin: 0 auto 2rem auto;
            display: block;
            box-shadow: 0 10px 25px rgba(0,0,0,0.2);
        }
        .item-rarity {
            display: inline-block;
            padding: 0.5rem 1rem;
            border-radius: 25px;
            font-size: 1rem;
            font-weight: 600;
            margin-bottom: 1.5rem;
        }
        .rarity-common { background: #e6fffa; color: #047857; }
        .rarity-rare { background: #dbeafe; color: #1e40af; }
        .rarity-epic { background: #faf5ff; color: #7c3aed; }
        .item-description {
            font-size: 1.2rem;
            line-height: 1.6;
            color: #4a5568;
            margin-bottom: 2rem;
            text-align: center;
            font-style: italic;
        }
        .attributes {
            background: #f7fafc;
            border-radius: 10px;
            padding: 1.5rem;
        }
        .attributes-title {
            font-size: 1.3rem;
            font-weight: 600;
            color: #2d3748;
            margin-bottom: 1rem;
        }
        .attribute {
            display: flex;
            justify-content: space-between;
            padding: 0.75rem 0;
            border-bottom: 1px solid #e2e8f0;
        }
        .attribute:last-child {
            border-bottom: none;
        }
        .attribute-key {
            font-weight: 500;
            color: #4a5568;
        }
        .attribute-value {
            color: #2d3748;
            font-weight: 600;
        }
        .authentication-status {
            background: #f0fff4;
            border: 2px solid #68d391;
            border-radius: 10px;
            padding: 1.5rem;
            margin: 2rem 0;
            text-align: center;
        }
        .auth-title {
            font-size: 1.2rem;
            font-weight: 600;
            color: #2f855a;
            margin-bottom: 0.5rem;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .auth-icon {
            width: 20px;
            height: 20px;
            margin-right: 8px;
        }
        .auth-message {
            color: #276749;
            font-size: 1rem;
            line-height: 1.5;
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <a href=\"/collection\" class=\"back-link\">← Retour à la collection</a>

        <div class=\"item-header\">
            <h1 class=\"item-title\">" # item.name # "</h1>
        </div>

        <img src=\"" # item.imageUrl # "\" alt=\"" # item.name # "\" class=\"item-image\">

        <div style=\"text-align: center;\">
            <span class=\"item-rarity " # rarityClass # "\">" # item.rarity # "</span>
        </div>

        <p class=\"item-description\">" # item.description # "</p>

        <div class=\"authentication-status\">
            <div class=\"auth-title\">
                <svg class=\"auth-icon\" fill=\"#2f855a\" viewBox=\"0 0 20 20\">
                    <path d=\"M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z\"/>
                </svg>
                Authentification Vérifiée
            </div>
            <p class=\"auth-message\">
                Cet article est authentique et vérifié.
                <br>ID de vérification: #" # Nat.toText(item.id) # "-" # item.rarity # "
            </p>
        </div>

        <div class=\"attributes\">
            <h3 class=\"attributes-title\">Attributes</h3>
            " # attributesHtml # "
        </div>
    </div>
</body>
</html>"
    };

    // Generate grid of all items for collection page
    private func generateItemsGrid(): Text {
        var html = "";
        for (item in itemCollection.vals()) {
            let rarityClass = "rarity-" # Text.toLowercase(item.rarity);
            html #= "<a href=\"/item/" # Nat.toText(item.id) # "\" class=\"item-card\">
                <img src=\"" # item.thumbnailUrl # "\" alt=\"" # item.name # "\" class=\"item-image\">
                <h3 class=\"item-title\">" # item.name # "</h3>
                <span class=\"item-rarity " # rarityClass # "\">" # item.rarity # "</span>
                <p class=\"item-description\">" # item.description # "</p>
            </a>";
        };
        html
    };

    // Generate HTML for attributes
    private func generateAttributesHtml(attributes: [(Text, Text)]): Text {
        var html = "";
        for ((key, value) in attributes.vals()) {
            html #= "<div class=\"attribute\">
                <span class=\"attribute-key\">" # key # "</span>
                <span class=\"attribute-value\">" # value # "</span>
            </div>";
        };
        html
    };

    // Generate 404 page for non-existent items
    public func generateNotFoundPage(id: Nat): Text {
        "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Item Not Found</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: white;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #333;
            text-align: center;
        }
        .error-container {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 3rem;
            box-shadow: 0 20px 50px rgba(0,0,0,0.2);
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        p {
            font-size: 1.2rem;
            margin-bottom: 2rem;
            opacity: 0.8;
        }
        a {
            color: #333;
            text-decoration: none;
            background: #f0f0f0;
            padding: 1rem 2rem;
            border-radius: 10px;
            transition: all 0.3s ease;
        }
        a:hover {
            background: #e0e0e0;
            transform: translateY(-2px);
        }
    </style>
</head>
<body>
    <div class=\"error-container\">
        <h1>Item Not Found</h1>
        <p>Sorry, Item #" # Nat.toText(id) # " doesn't exist in this collection.</p>
        <a href=\"/collection\">View Collection</a>
    </div>
</body>
</html>"
    };
}
