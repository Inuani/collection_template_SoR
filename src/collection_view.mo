import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Collection "collection";
import KnitworkProtocol "knitwork_protocol";

module {
    public type GetItemMeetings = (Nat) -> [KnitworkProtocol.MeetingRecord];

    let styles = "
        /* Evorev UI v1: visual tokens mirror sneakerweb_xp/web/styles.css. */
        :root{--ink:#171313;--paper:#f6efdd;--orange:#ff5c35;--acid:#d8ff38;--blue:#3155ff;--pink:#ffb2d8;--muted:#766e62;--white:#fff}
        *{box-sizing:border-box}html{min-width:320px;background:var(--paper)}body{min-height:100vh;margin:0;color:var(--ink);font-family:Arial Narrow,Liberation Sans Narrow,sans-serif;background:radial-gradient(circle at 1px 1px,rgba(23,19,19,.13) 1px,transparent 1.2px) 0 0/15px 15px,linear-gradient(125deg,rgba(255,92,53,.15),transparent 35%),var(--paper)}
        a{color:inherit}a:focus-visible{outline:4px solid var(--blue);outline-offset:4px}.shell{width:min(1280px,calc(100% - 40px));margin:0 auto;padding:clamp(42px,7vw,92px) 0 90px}.shell>header{padding-bottom:clamp(28px,5vw,52px);border-bottom:4px solid var(--ink)}
        .eyebrow{display:inline-block;margin:0 0 16px;padding:5px 9px;border:2px solid var(--ink);background:var(--acid);font-size:.72rem;font-weight:950;letter-spacing:.14em;text-transform:uppercase}h1,h2,h3{font-family:Georgia,Times New Roman,serif}h1{margin:0;font-size:clamp(3.4rem,9vw,8rem);font-weight:400;letter-spacing:-.07em;line-height:.86}.lede{max-width:760px;margin:24px 0 0;color:var(--ink);font-size:clamp(1.05rem,2vw,1.35rem);font-weight:800;line-height:1.45}
        .topline{display:flex;justify-content:space-between;align-items:center;gap:16px;margin-bottom:34px}.back{display:inline-flex;align-items:center;min-height:46px;padding:9px 14px;border:3px solid var(--ink);background:var(--white);box-shadow:5px 5px 0 var(--ink);font-size:.78rem;font-weight:950;letter-spacing:.06em;text-decoration:none;text-transform:uppercase;transition:transform 120ms ease,box-shadow 120ms ease}.back:hover{transform:translate(3px,3px);box-shadow:2px 2px 0 var(--ink)}
        .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,290px),1fr));gap:clamp(28px,4vw,48px);margin-top:42px}.item-card{display:block;overflow:hidden;border:4px solid var(--ink);background:var(--orange);box-shadow:10px 10px 0 var(--ink);text-decoration:none;transition:transform 120ms ease,box-shadow 120ms ease}.item-card:nth-child(3n+2){background:var(--pink)}.item-card:nth-child(3n+3){background:var(--acid)}.item-card:hover{transform:translate(5px,5px);box-shadow:5px 5px 0 var(--ink)}
        .media{position:relative;display:grid;place-items:center;min-height:300px;overflow:hidden;border-bottom:4px solid var(--ink);background:linear-gradient(135deg,var(--blue),var(--pink))}.media img{position:absolute;width:100%;height:100%;object-fit:cover}.media-fallback{color:var(--white);font-family:Georgia,Times New Roman,serif;font-size:9rem;font-style:italic;line-height:1;text-shadow:4px 4px 0 var(--ink)}.card-body{min-height:240px;padding:22px}.item-number,.stitch-count,.pill{display:inline-flex;align-items:center;min-height:28px;padding:5px 8px;border:2px solid var(--ink);background:var(--white);font-size:.66rem;font-weight:950;letter-spacing:.055em;line-height:1;text-transform:uppercase}.stitch-count{margin-left:6px;background:var(--acid)}.card-body h2{margin:20px 0 10px;font-size:clamp(1.9rem,4vw,2.7rem);font-weight:400;letter-spacing:-.045em;line-height:.95}.description{margin:0;color:var(--ink);font-size:.92rem;font-weight:750;line-height:1.5}.rarity{display:table;margin-top:20px;padding-top:9px;border-top:3px solid var(--ink);font-size:.72rem;font-weight:950;letter-spacing:.09em;text-transform:uppercase}
        .hero{display:grid;grid-template-columns:minmax(0,1.05fr) minmax(300px,.95fr);gap:clamp(24px,4vw,46px);margin-top:28px}.hero-copy,.panel{border:4px solid var(--ink);background:var(--orange);box-shadow:10px 10px 0 var(--ink)}.hero-copy{padding:clamp(28px,5vw,58px)}.hero-copy h1{font-size:clamp(3.2rem,7vw,7rem)}.hero-copy .description{max-width:700px;margin-top:24px;font-size:clamp(1rem,2vw,1.25rem);font-weight:800}.hero .media{min-height:440px;border:4px solid var(--ink);box-shadow:10px 10px 0 var(--ink)}
        .meta-row{display:flex;flex-wrap:wrap;gap:8px;margin-top:30px}.pill{background:var(--white)}.pill.stitch{background:var(--acid)}.section{margin-top:clamp(62px,9vw,110px)}.section-title{margin-bottom:24px;padding-bottom:14px;border-bottom:4px solid var(--ink)}.section-title h2{margin:0;font-size:clamp(2.6rem,6vw,5rem);font-weight:400;letter-spacing:-.055em;line-height:.9}
        .attributes{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:18px}.attribute{padding:18px 20px;border:3px solid var(--ink);background:var(--white);box-shadow:5px 5px 0 var(--ink)}.attribute:nth-child(3n+1){background:var(--acid)}.attribute:nth-child(3n+2){background:var(--pink)}.attribute-key{display:block;font-size:.7rem;font-weight:950;letter-spacing:.1em;text-transform:uppercase}.attribute-value{display:block;margin-top:8px;font-family:Georgia,Times New Roman,serif;font-size:1.35rem;font-weight:700}
        .stitches{display:grid;gap:24px}.stitch-card{padding:clamp(22px,4vw,34px);border:4px solid var(--ink);background:var(--white);box-shadow:8px 8px 0 var(--ink)}.stitch-card:nth-child(even){background:var(--pink)}.stitch-title{margin:0;font-size:clamp(1.65rem,4vw,2.5rem);font-weight:400;letter-spacing:-.035em;line-height:1.05}.stitch-title strong,.stitch-title span{display:block}.stitch-title span{margin-top:6px;font-family:Arial Narrow,Liberation Sans Narrow,sans-serif;font-size:.5em;font-weight:900;letter-spacing:.08em;text-transform:uppercase}.sync-status{display:table;margin-top:14px;padding:5px 8px;border:2px solid var(--ink);background:var(--orange);font-size:.68rem;font-weight:950;letter-spacing:.06em;text-transform:uppercase}
        .partners{display:flex;flex-wrap:wrap;gap:12px;margin-top:22px}.partner{display:inline-flex;align-items:center;min-height:44px;padding:10px 15px;border:2px solid var(--ink);background:var(--acid);box-shadow:4px 4px 0 var(--ink);font-weight:900;text-decoration:none;transition:transform 120ms ease,box-shadow 120ms ease}.partner:hover{transform:translate(2px,2px);box-shadow:2px 2px 0 var(--ink)}.partner strong{font-size:.95rem;overflow-wrap:anywhere}.stitch-meta{display:flex;flex-wrap:wrap;gap:8px;margin:24px 0 0;padding-top:16px;border-top:2px solid var(--ink);font-size:.82rem;font-weight:800}.stitch-meta strong{font-weight:950}.meta-separator{opacity:.55}
        .empty{padding:clamp(32px,6vw,64px);border:4px dashed var(--ink);background:var(--white);font-weight:850;text-align:center}.empty h2{margin:0;font-size:clamp(2rem,5vw,4rem);font-weight:400}.error{max-width:700px;margin:12vh auto;padding:clamp(28px,6vw,58px);background:var(--pink)}
        @media(max-width:760px){.shell{width:min(100% - 32px,1280px);padding-top:34px}.hero{grid-template-columns:1fr}.hero .media{min-height:340px}.topline{align-items:flex-start;flex-direction:column}.item-card,.hero-copy,.hero .media,.stitch-card{box-shadow:7px 7px 0 var(--ink)}h1{font-size:clamp(3.2rem,17vw,5.5rem)}}
        @media(max-width:480px){.grid{grid-template-columns:1fr}.card-body{min-height:0}.item-number,.stitch-count{margin:0 5px 6px 0}.hero-copy{padding:26px 22px}.hero .media{min-height:280px}.media-fallback{font-size:7rem}}
        @media(prefers-reduced-motion:reduce){*,*::before,*::after{transition-duration:.01ms!important;scroll-behavior:auto!important}}
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
