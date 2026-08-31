import Nat "mo:core/Nat";
import Text "mo:core/Text";

import Collection "../src/collection";
import CollectionView "../src/collection_view";
import KnitworkProtocol "../src/knitwork_protocol";
import EvorevFonts "../src/ui/evorev_fonts";
import EvorevTheme "../src/ui/evorev_theme";

let state = Collection.init();
let collection = Collection.Collection(state);
collection.setCollectionName("Collection <Évorev>");
let _itemId = collection.addItem(
    "Capuche & fil",
    "/api/file/preview.webp",
    "/api/file/image.webp",
    "Une carte de test.",
    "Unique",
    [("Couleur", "Bleu")],
);

let noMeetings = func(_id : Nat) : [KnitworkProtocol.MeetingRecord] { [] };
let collectionPage = CollectionView.generateCollectionPageForTest(collection, noMeetings);

assert (Text.contains(EvorevFonts.css, #text "Providence Sans"));
assert (Text.contains(EvorevFonts.css, #text "Sketchbook Notes"));
assert (Text.contains(EvorevTheme.css, #text "Providence Sans"));
assert (Text.contains(EvorevTheme.css, #text "Sketchbook Notes"));
assert (Text.contains(collectionPage, #text "font-family:var(--font-display)"));
assert (Text.contains(collectionPage, #text "#1116a3"));
assert (Text.contains(collectionPage, #text "#ffd6f7"));
assert (Text.contains(collectionPage, #text "#b3ffc1"));
assert (Text.contains(collectionPage, #text "#b3fffc"));
assert (Text.contains(collectionPage, #text "#f7ffb3"));
assert (Text.contains(collectionPage, #text "#ebff00"));
assert (Text.contains(collectionPage, #text "Collection &lt;Évorev&gt;"));
assert (not Text.contains(collectionPage, #text "radial-gradient"));
assert (not Text.contains(collectionPage, #text "Georgia"));
assert (Text.contains(collectionPage, #text "Capuche &amp; fil"));
