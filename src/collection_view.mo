import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Collection "collection";

module {
    public func generateCollectionPage(
        collection : Collection.Collection
    ) : Text {
        let items = collection.getAllItems();
        let collectionName = collection.getCollectionName();
        let itemsGrid = generateItemsGrid(items);

        "<!DOCTYPE html>\n"
        # "<html lang=\"en\">\n"
        # "<head>\n"
        # "    <meta charset=\"UTF-8\">\n"
        # "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
        # "    <title>" # collectionName # "</title>\n"
        # "    <link rel=\"stylesheet\" href=\"/theme.css\">\n"
        # "</head>\n"
        # "<body>\n"
        # "    <div class=\"container\">\n"
        # "        <div class=\"header\">\n"
        # "            <img src=\"/logo.webp\" alt=\"Logo\" class=\"logo\">\n"
        # "            <h1>" # collectionName # "</h1>\n"
        # "        </div>\n"
        # "        <div class=\"items-grid\">\n"
        # "            " # itemsGrid # "\n"
        # "        </div>\n"
        # "    </div>\n"
        # "</body>\n"
        # "</html>";
    };

    public func generateItemPage(
        collection : Collection.Collection,
        id : Nat,
    ) : Text {
        switch (collection.getItem(id)) {
            case (?item) {
                let collectionName = collection.getCollectionName();
                generateItemDetailPage(item, collectionName);
            };
            case null generateNotFoundPage(id);
        };
    };

    public func generateNotFoundPage(
        id : Nat
    ) : Text {
        "<!DOCTYPE html>\n"
        # "<html lang=\"en\">\n"
        # "<head>\n"
        # "    <meta charset=\"UTF-8\">\n"
        # "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
        # "    <title>Item Not Found</title>\n"
        # "    <link rel=\"stylesheet\" href=\"/theme.css\">\n"
        # "</head>\n"
        # "<body>\n"
        # "    <div class=\"error-container\">\n"
        # "        <h1>Item Not Found</h1>\n"
        # "        <p>Sorry, Item #" # Nat.toText(id) # " doesn't exist in this collection.</p>\n"
        # "        <a href=\"/collection\">View Collection</a>\n"
        # "    </div>\n"
        # "</body>\n"
        # "</html>";
    };

    private func generateItemDetailPage(
        item : Collection.Item,
        collectionName : Text,
    ) : Text {
        let attributesHtml = generateAttributesHtml(item.attributes);
        let stitchingHistoryHtml = generateStitchingHistoryHtml(item.stitching_history);
        let rarityClass = "rarity-" # Text.toLower(item.rarity);

        "<!DOCTYPE html>\n"
        # "<html lang=\"en\">\n"
        # "<head>\n"
        # "    <meta charset=\"UTF-8\">\n"
        # "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
        # "    <title>" # item.name # " - " # collectionName # "</title>\n"
        # "    <link rel=\"stylesheet\" href=\"/theme.css\">\n"
        # "</head>\n"
        # "<body>\n"
        # "    <div class=\"item-detail-container\">\n"
        # "        <a href=\"/collection\" class=\"back-link\">Retour à la collection</a>\n"
        # "        <div class=\"item-header\">\n"
        # "            <h1 class=\"item-title\">" # item.name # "</h1>\n"
        # "            <div class=\"item-id\">Item #" # Nat.toText(item.id) # "</div>\n"
        # "        </div>\n"
        # "        <img src=\"" # item.imageUrl # "\" alt=\"" # item.name # "\" class=\"item-image\">\n"
        # "        <div class=\"item-rarity " # rarityClass # "\">" # item.rarity # "</div>\n"
        # "        <p class=\"item-description\">" # item.description # "</p>\n"
        # "        <div class=\"stats\">\n"
        # "            <div class=\"stat-card\">\n"
        # "                <span>Token balance</span>\n"
        # "                <strong>" # Nat.toText(item.token_balance) # "</strong>\n"
        # "            </div>\n"
        # "            <div class=\"stat-card\">\n"
        # "                <span>Total stitchings</span>\n"
        # "                <strong>" # Nat.toText(item.stitching_history.size()) # "</strong>\n"
        # "            </div>\n"
        # "        </div>\n"
        # "        <div class=\"attributes\">\n"
        # "            <h2 class=\"attributes-title\">Attributes</h2>\n"
        # "            " # attributesHtml # "\n"
        # "        </div>\n"
        # "        <div class=\"history\">\n"
        # "            <h2 class=\"history-title\">Stitching history</h2>\n"
        # "            " # stitchingHistoryHtml # "\n"
        # "        </div>\n"
        # "    </div>\n"
        # "</body>\n"
        # "</html>";
    };

    private func generateStitchingHistoryHtml(history : [Collection.StitchingRecord]) : Text {
        if (history.size() == 0) {
            return "<div class=\"empty-history\">No stitchings recorded yet.</div>";
        };

        var html = "";
        for (record in history.vals()) {
            let partners = formatPartners(record.partner_item_ids);
            html #= "<div class=\"stitching-record\">\n"
            # "    <div class=\"stitching-date\">Stitching ID: " # record.stitching_id # "</div>\n"
            # "    <div class=\"stitching-partners\">" # partners # "</div>\n"
            # "    <div class=\"stitching-tokens\">+" # Nat.toText(record.tokens_earned) # " tokens</div>\n"
            # "</div>";
        };
        html;
    };

    private func formatPartners(partnerIds : [Nat]) : Text {
        if (partnerIds.size() == 0) {
            return "Solo stitching";
        };

        var parts = "Stitched with items: ";
        var index = 0;
        let last = partnerIds.size();
        while (index < last) {
            if (index > 0) {
                parts #= ", ";
            };
            parts #= "#" # Nat.toText(partnerIds[index]);
            index += 1;
        };
        parts;
    };

    private func generateAttributesHtml(attributes : [(Text, Text)]) : Text {
        if (attributes.size() == 0) {
            return "<div class=\"attribute\">No attributes</div>";
        };

        var html = "";
        for ((key, value) in attributes.vals()) {
            html #= "<div class=\"attribute\">\n"
            # "    <span class=\"attribute-key\">" # key # "</span>\n"
            # "    <span class=\"attribute-value\">" # value # "</span>\n"
            # "</div>";
        };
        html;
    };

    private func generateItemsGrid(items : [Collection.Item]) : Text {
        if (items.size() == 0) {
            return "<div class=\"empty-collection\"><h2>Collection vide pour l'instant!</h2></div>";
        };

        var html = "";
        for (item in items.vals()) {
            let rarityClass = "rarity-" # Text.toLower(item.rarity);
            html #= "<a href=\"/item/" # Nat.toText(item.id) # "\" class=\"item-card\">\n"
            # "    <img src=\"" # item.thumbnailUrl # "\" alt=\"" # item.name # "\" class=\"item-image\">\n"
            # "    <h3 class=\"item-title\">" # item.name # "</h3>\n"
            # "    <span class=\"item-rarity " # rarityClass # "\">" # item.rarity # "</span>\n"
            # "    <p class=\"item-description\">" # item.description # "</p>\n"
            # "</a>";
        };
        html;
    };
};
