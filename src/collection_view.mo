import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Collection "collection";
import KnitworkProtocol "knitwork_protocol";

module {
    public type GetItemMeetings = (Nat) -> [KnitworkProtocol.MeetingRecord];

    let styles = "
        :root{--ink:#17211b;--muted:#66736b;--paper:#f4f2eb;--card:#fff;--line:#dfe4de;--green:#165c3a;--lime:#cbea87;--amber:#f1bd62}
        *{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif}
        a{color:inherit}.shell{width:min(1080px,calc(100% - 32px));margin:0 auto;padding:38px 0 70px}.eyebrow{margin:0 0 8px;color:var(--green);font-size:.76rem;font-weight:800;letter-spacing:.16em;text-transform:uppercase}
        h1{margin:0;font-size:clamp(2rem,7vw,4.3rem);line-height:.96;letter-spacing:-.055em}.lede{max-width:670px;margin:18px 0 0;color:var(--muted);font-size:1.05rem;line-height:1.65}
        .topline{display:flex;justify-content:space-between;align-items:center;gap:16px;margin-bottom:38px}.back{font-weight:750;text-decoration:none}.back:hover{text-decoration:underline}
        .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:18px;margin-top:34px}.item-card{display:block;overflow:hidden;border:1px solid var(--line);border-radius:22px;background:var(--card);text-decoration:none;box-shadow:0 10px 30px rgba(23,33,27,.05);transition:transform .18s ease,box-shadow .18s ease}.item-card:hover{transform:translateY(-3px);box-shadow:0 16px 38px rgba(23,33,27,.09)}
        .media{position:relative;display:grid;place-items:center;min-height:210px;overflow:hidden;background:linear-gradient(135deg,#dce9dd,#edf0df)}.media img{position:absolute;width:100%;height:100%;object-fit:cover}.media-fallback{font-size:3rem;font-weight:900;color:var(--green);opacity:.82}.card-body{padding:20px}.item-number,.stitch-count,.pill{display:inline-flex;align-items:center;border-radius:999px;padding:6px 10px;font-size:.72rem;font-weight:800}.item-number{background:#eef1ed;color:var(--muted)}.stitch-count{margin-left:6px;background:var(--lime);color:#21472e}.card-body h2{margin:15px 0 6px;font-size:1.35rem}.description{margin:0;color:var(--muted);line-height:1.55}.rarity{margin-top:16px;color:var(--green);font-size:.78rem;font-weight:800;text-transform:uppercase;letter-spacing:.08em}
        .hero{display:grid;grid-template-columns:minmax(0,1.05fr) minmax(280px,.95fr);gap:28px;margin-top:28px}.hero-copy,.panel{border:1px solid var(--line);border-radius:26px;background:var(--card);box-shadow:0 12px 34px rgba(23,33,27,.055)}.hero-copy{padding:clamp(24px,5vw,46px)}.hero-copy h1{font-size:clamp(2.2rem,6vw,4.8rem)}.hero-copy .description{margin-top:20px;font-size:1.05rem}.hero .media{min-height:390px;border-radius:26px;border:1px solid var(--line)}
        .meta-row{display:flex;flex-wrap:wrap;gap:8px;margin-top:24px}.pill{background:#eef1ed}.pill.stitch{background:var(--lime)}.section{margin-top:34px}.section-title{margin-bottom:15px}.section-title h2{margin:0;font-size:1.45rem}
        .attributes{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.attribute{padding:16px 18px;border:1px solid var(--line);border-radius:16px;background:var(--card)}.attribute-key{display:block;color:var(--muted);font-size:.75rem;font-weight:800;text-transform:uppercase;letter-spacing:.08em}.attribute-value{display:block;margin-top:5px;font-weight:750}
        .stitches{display:grid;gap:12px}.stitch-card{padding:clamp(20px,4vw,28px);border:1px solid var(--line);border-radius:22px;background:var(--card);box-shadow:0 8px 24px rgba(23,33,27,.045)}.stitch-title{margin:0;font-size:clamp(1.2rem,3vw,1.55rem);line-height:1.25}.stitch-title strong,.stitch-title span{display:block}.stitch-title span{margin-top:4px;color:var(--muted);font-size:.82em;font-weight:600}.sync-status{display:inline-block;margin-top:10px;color:#784d00;font-size:.72rem;font-weight:800}
        .partners{display:flex;flex-wrap:wrap;gap:9px;margin-top:16px}.partner{display:inline-flex;align-items:center;min-height:44px;padding:10px 15px;border:1px solid #cbd8cc;border-radius:999px;background:#f7faf6;text-decoration:none;transition:border-color .18s ease,background .18s ease}.partner:hover{border-color:var(--green);background:#eef6ec}.partner strong{font-size:.95rem;overflow-wrap:anywhere}
        .stitch-meta{display:flex;flex-wrap:wrap;gap:7px;margin:17px 0 0;color:var(--muted);font-size:.82rem}.stitch-meta strong{color:var(--ink);font-weight:700}.meta-separator{color:#a2aaa4}.empty{padding:30px;border:1px dashed #b8c0b9;border-radius:18px;color:var(--muted);text-align:center}.error{max-width:650px;margin:12vh auto;padding:34px}
        @media(max-width:760px){.hero{grid-template-columns:1fr}.hero .media{min-height:280px}.topline{align-items:flex-start;flex-direction:column}}
    ";

    func escapeHtml(value : Text) : Text {
        var escaped = Text.replace(value, #text("&"), "&amp;");
        escaped := Text.replace(escaped, #text("<"), "&lt;");
        escaped := Text.replace(escaped, #text(">"), "&gt;");
        escaped := Text.replace(escaped, #text("\""), "&quot;");
        Text.replace(escaped, #text("'"), "&#39;");
    };

    func scripts() : Text {
        "<script>(function(){" #
        "document.querySelectorAll('time[data-stitch-ns]').forEach(function(el){" #
        "var ns=Number(el.dataset.stitchNs);if(Number.isFinite(ns)){" #
        "el.textContent=new Intl.DateTimeFormat('fr-CH',{dateStyle:'long',timeStyle:'short'}).format(new Date(ns/1000000));}});" #
        "var cache=new Map();" #
        "function apiUrl(principal,itemId){var port=window.location.port?':'+window.location.port:'';" #
        "if(window.location.hostname.endsWith('.raw.localhost')){return window.location.protocol+'//'+principal+'.raw.localhost'+port+'/api/knitwork/v1/items/'+itemId;}" #
        "return 'https://'+principal+'.raw.icp0.io/api/knitwork/v1/items/'+itemId;}" #
        "function loadObject(principal,itemId){var key=principal+':'+itemId;if(cache.has(key)){return cache.get(key);}" #
        "var request=(async function(){var controller=new AbortController();var timer=setTimeout(function(){controller.abort();},4000);" #
        "try{var response=await fetch(apiUrl(principal,itemId),{mode:'cors',credentials:'omit',signal:controller.signal});" #
        "if(!response.ok){throw new Error('object lookup failed');}var data=await response.json();" #
        "if(!data||data.schema_version!==1||!data.collection||!data.item||data.collection.principal!==principal||String(data.item.id)!==itemId||typeof data.item.name!=='string'){throw new Error('invalid object lookup');}" #
        "return data;}finally{clearTimeout(timer);}})();cache.set(key,request);return request;}" #
        "document.querySelectorAll('[data-stitch-partner=remote]').forEach(function(card){var principal=card.dataset.collection;var itemId=card.dataset.itemId;" #
        "loadObject(principal,itemId).then(function(data){var objectName=data.item.name.trim();" #
        "if(objectName){card.querySelector('[data-object-name]').textContent=objectName;}}).catch(function(){});});" #
        "})();</script>";
    };

    func document(title : Text, body : Text) : Text {
        "<!doctype html><html lang=\"fr\"><head><meta charset=\"utf-8\">" #
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" #
        "<title>" # escapeHtml(title) # "</title><style>" # styles # "</style></head>" #
        "<body>" # body # scripts() # "</body></html>";
    };

    func initial(value : Text) : Text {
        switch (value.chars().next()) {
            case (?character) Text.toUpper(Text.fromChar(character));
            case null "?";
        };
    };

    func media(imageUrl : Text, name : Text) : Text {
        let image = if (imageUrl.size() == 0) { "" } else {
            "<img src=\"" # escapeHtml(imageUrl) # "\" alt=\"" # escapeHtml(name) # "\" onerror=\"this.remove()\">";
        };
        "<div class=\"media\"><div class=\"media-fallback\">" # escapeHtml(initial(name)) # "</div>" # image # "</div>";
    };

    func stitchCounts(records : [KnitworkProtocol.MeetingRecord]) : (Nat, Nat) {
        var confirmed = 0;
        var pending = 0;
        for (record in records.vals()) {
            switch (record.status) {
                case (#confirmed) confirmed += 1;
                case (#pending) pending += 1;
            };
        };
        (confirmed, pending);
    };

    func stitchCountLabel(count : Nat) : Text {
        if (count == 1) {
            "1 Stitch";
        } else {
            Nat.toText(count) # " Stitchs";
        };
    };

    func pendingCountLabel(count : Nat) : Text {
        if (count == 1) "1 Stitch en cours de synchronisation" else Nat.toText(count) # " Stitchs en cours de synchronisation";
    };

    public func generateCollectionPage(
        collection : Collection.Collection,
        getItemMeetings : GetItemMeetings,
    ) : Text {
        let collectionName = collection.getCollectionName();
        let body = "<main class=\"shell\"><header><p class=\"eyebrow\">Collection</p>" #
            "<h1>" # escapeHtml(collectionName) # "</h1>" #
            "<p class=\"lede\">Chaque objet construit son réseau par ses Stitchs. Chaque lien est authentifié et inscrit dans les Collections participantes.</p></header>" #
            "<section class=\"grid\">" # generateItemsGrid(collection.getAllItems(), getItemMeetings) # "</section></main>";
        document(collectionName, body);
    };

    public func generateItemPage(
        collection : Collection.Collection,
        currentCanister : Principal,
        id : Nat,
        meetings : [KnitworkProtocol.MeetingRecord],
    ) : Text {
        switch (collection.getItem(id)) {
            case (?item) generateItemDetailPage(collection, currentCanister, item, meetings);
            case null generateNotFoundPage(id);
        };
    };

    public func generateNotFoundPage(id : Nat) : Text {
        document(
            "Objet introuvable",
            "<main class=\"shell error panel\"><p class=\"eyebrow\">Erreur 404</p><h1>Objet introuvable</h1>" #
            "<p class=\"lede\">L'objet #" # Nat.toText(id) # " n'existe pas dans cette Collection.</p>" #
            "<p><a class=\"back\" href=\"/collection\">← Retour à la Collection</a></p></main>",
        );
    };

    func generateItemDetailPage(
        collection : Collection.Collection,
        currentCanister : Principal,
        item : Collection.Item,
        meetings : [KnitworkProtocol.MeetingRecord],
    ) : Text {
        let collectionName = collection.getCollectionName();
        let (confirmedCount, pendingCount) = stitchCounts(meetings);
        let pendingPill = if (pendingCount == 0) { "" } else {
            "<span class=\"pill\">" # pendingCountLabel(pendingCount) # "</span>";
        };
        let body = "<main class=\"shell\"><div class=\"topline\"><a class=\"back\" href=\"/collection\">← " #
            escapeHtml(collectionName) # "</a></div>" #
            "<section class=\"hero\"><div class=\"hero-copy\">" #
            "<h1>" # escapeHtml(item.name) # "</h1><p class=\"description\">" # escapeHtml(item.description) # "</p>" #
            "<div class=\"meta-row\"><span class=\"pill\">" # escapeHtml(item.rarity) # "</span>" #
            "<span class=\"pill stitch\">" # stitchCountLabel(confirmedCount) # "</span>" # pendingPill # "</div></div>" #
            media(item.imageUrl, item.name) # "</section>" #
            "<section class=\"section\"><div class=\"section-title\"><h2>Attributs</h2></div><div class=\"attributes\">" #
            generateAttributesHtml(item.attributes) # "</div></section>" #
            "<section class=\"section\"><div class=\"section-title\"><h2>Stitchs</h2></div><div class=\"stitches\">" #
            generateStitchHistoryHtml(collection, currentCanister, item, meetings) # "</div></section></main>";
        document(item.name # " · " # collectionName, body);
    };

    func generateStitchHistoryHtml(
        collection : Collection.Collection,
        currentCanister : Principal,
        currentItem : Collection.Item,
        meetings : [KnitworkProtocol.MeetingRecord],
    ) : Text {
        if (meetings.size() == 0) {
            return "<div class=\"empty\">Cet objet n'a encore aucun Stitch.</div>";
        };

        var html = "";
        for (record in meetings.vals()) {
            let pendingStatus = switch (record.status) {
                case (#confirmed) "";
                case (#pending) "<span class=\"sync-status\">Synchronisation en cours</span>";
            };
            html #= "<article class=\"stitch-card\"><h3 class=\"stitch-title\"><strong>" # escapeHtml(currentItem.name) #
                "</strong><span>a stitché avec</span></h3>" # pendingStatus # "<div class=\"partners\">" #
                generatePartnersHtml(collection, currentCanister, currentItem.id, record.event.participants) # "</div>" #
                "<p class=\"stitch-meta\"><strong>" # escapeHtml(record.event.location) # "</strong><span class=\"meta-separator\">·</span>" #
                "<time data-stitch-ns=\"" # Int.toText(record.event.last_scan_at_ns) # "\">Date en cours de chargement…</time></p></article>";
        };
        html;
    };

    func generatePartnersHtml(
        collection : Collection.Collection,
        currentCanister : Principal,
        currentItemId : Nat,
        participants : [KnitworkProtocol.ObjectRef],
    ) : Text {
        var html = "";
        for (participant in participants.vals()) {
            if (not (Principal.equal(participant.collection, currentCanister) and participant.item_id == currentItemId)) {
                let sameCollection = Principal.equal(participant.collection, currentCanister);
                let itemIdText = Nat.toText(participant.item_id);
                let participantLabel = if (sameCollection) {
                    switch (collection.getItem(participant.item_id)) {
                        case (?item) item.name;
                        case null "Item #" # itemIdText;
                    };
                } else {
                    "Item #" # itemIdText;
                };
                let principalText = Principal.toText(participant.collection);
                let href = if (sameCollection) {
                    "/item/" # itemIdText;
                } else {
                    "https://" # principalText # ".raw.icp0.io/item/" # itemIdText;
                };
                let remoteData = if (sameCollection) { "" } else {
                    " data-stitch-partner=\"remote\" data-collection=\"" # principalText # "\" data-item-id=\"" # itemIdText # "\"";
                };
                html #= "<a class=\"partner\" href=\"" # href # "\"" # remoteData # ">" #
                    "<strong data-object-name>" # escapeHtml(participantLabel) # "</strong></a>";
            };
        };
        html;
    };

    func generateAttributesHtml(attributes : [(Text, Text)]) : Text {
        if (attributes.size() == 0) {
            return "<div class=\"attribute\"><span class=\"attribute-value\">Aucun attribut</span></div>";
        };
        var html = "";
        for ((key, value) in attributes.vals()) {
            html #= "<div class=\"attribute\"><span class=\"attribute-key\">" # escapeHtml(key) # "</span>" #
                "<span class=\"attribute-value\">" # escapeHtml(value) # "</span></div>";
        };
        html;
    };

    func generateItemsGrid(items : [Collection.Item], getItemMeetings : GetItemMeetings) : Text {
        if (items.size() == 0) {
            return "<div class=\"empty\"><h2>Cette Collection est vide.</h2></div>";
        };
        var html = "";
        for (item in items.vals()) {
            let (confirmedCount, pendingCount) = stitchCounts(getItemMeetings(item.id));
            let pendingBadge = if (pendingCount == 0) { "" } else {
                "<span class=\"stitch-count\">" # Nat.toText(pendingCount) # " en cours</span>";
            };
            html #= "<a href=\"/item/" # Nat.toText(item.id) # "\" class=\"item-card\">" # media(item.thumbnailUrl, item.name) #
                "<div class=\"card-body\"><span class=\"item-number\">Objet #" # Nat.toText(item.id) # "</span>" #
                "<span class=\"stitch-count\">" # stitchCountLabel(confirmedCount) # "</span>" # pendingBadge # "<h2>" # escapeHtml(item.name) # "</h2>" #
                "<p class=\"description\">" # escapeHtml(item.description) # "</p><div class=\"rarity\">" # escapeHtml(item.rarity) # "</div></div></a>";
        };
        html;
    };
};
