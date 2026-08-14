# Workflow NFC des Collections

> Pour créer et associer une carte `.snk` à un Item déjà équipé, suivre
> [`../sneakerweb_xp/SNK_WORKFLOW.md`](../sneakerweb_xp/SNK_WORKFLOW.md).
> Ce document reste la référence pour la création de l'Item et la programmation
> physique de sa puce NFC.

Le programmateur USB et la station Proof-of-Meet ont deux rôles différents :

- le programmateur D-Logic relié au PC écrit la puce NTAG 424 DNA ;
- une station enregistrée dans le Hub lit ensuite la puce, signe le scan et l'envoie au Hub.

Les trois alias IC actuellement déclarés utilisent exactement le même code :

| Alias dfx | Principal IC |
| --- | --- |
| `collection_monayolla` | `4623w-oqaaa-aaaak-qtrjq-cai` |
| `collection_bleu` | `ubnuj-uyaaa-aaaak-qudbq-cai` |
| `collection_heloise` | `jmp6g-oqaaa-aaaak-qug3q-cai` |

Un `reinstall` efface tous les Items, routes NFC, CMAC et Stitchs du canister
ciblé. Il est réservé aux remises à zéro explicitement voulues, comme la
reprise initiale du canister existant par `collection_heloise`. Après cette
initialisation, utiliser `upgrade` tant que le schéma stable reste compatible.

## Préparer une puce pour Item B0

Depuis le dossier `collections` :

```bash
make nfc-plan \
  NFC_COLLECTION=collection_bleu \
  NFC_ITEM_ID=0 \
  NFC_NETWORK=ic
```

Cette commande vérifie notamment :

- que l'alias existe dans `dfx.json` ;
- que l'alias résout le Principal attendu ;
- que l'Item existe dans la Collection ;
- le path et l'URL NDEF qui seront programmés.

Elle ne contacte pas le programmateur et ne modifie aucune donnée.

Pour exécuter réellement l'enrôlement :

```bash
make nfc-program \
  NFC_COLLECTION=collection_bleu \
  NFC_ITEM_ID=0 \
  NFC_NETWORK=ic
```

Le script propose alors deux choix :

```text
1. random - clé aléatoire unique sauvegardée dans un fichier privé (recommandé)
2. zero   - clé 00000000000000000000000000000000 (test uniquement)
```

Le choix peut aussi être indiqué directement dans la commande avec
`NFC_KEY_MODE=random` ou `NFC_KEY_MODE=zero`. Le script demande ensuite de poser
la puce, affiche la Collection et l'Item ciblés, puis demande simplement de
saisir `y` avant toute mutation. Pour B0, les valeurs sont :

```text
Collection : collection_bleu
Principal  : ubnuj-uyaaa-aaaak-qudbq-cai
Item       : 0 · Item B0
Path NFC   : /nfc/item/0
Paramètre  : item_id=0 (placé avant uid/ctr/cmac dans l'URL)
```

Le mode `zero` conserve la clé d'usine. Il valide le fonctionnement, mais ne
constitue pas une authentification sécurisée puisque cette clé est connue.

Le mode `random` génère une clé différente pour chaque puce et crée, avant la
programmation, un fichier privé dans `~/.local/share/evorev/nfc-keys/`. Le
fichier porte le nom de la Collection, l'Item et l'UID, par exemple :

```text
collection_bleu-item-0-04958CAA5E5E80.key
```

Son contenu JSON associe la clé à l'alias et au Principal de la Collection, au
réseau, au numéro et au nom de l'Item, à l'UID et à la route NFC. Le fichier est
créé avec les permissions `0600`; il contient un secret et ne doit jamais être
partagé, ajouté à Git ou supprimé tant que la puce est utilisée.

## Paths des images et entrée NFC

Ces trois valeurs sont indépendantes :

- l'entrée NFC : URL permanente écrite sur la puce ;
- `thumbnailUrl` : miniature de l'objet ;
- `imageUrl` : image principale de l'objet.

Knitwork V1 dérive obligatoirement l'entrée `nfc/item/<id>` et le paramètre
signé `item_id=<id>` depuis l'Item. Le programmeur refuse une valeur différente,
car elle pourrait ouvrir une page mais ne serait pas acceptée par le protocole
de Stitch physique. Après validation du CMAC, cette entrée redirige vers la page
publique `item/<id>`, qui reste accessible depuis la Collection et les
historiques de Stitch. Exemple :

```bash
make nfc-plan NFC_COLLECTION=collection_bleu NFC_ITEM_ID=0 NFC_ROUTE=nfc/item/0
```

Lorsqu'une carte Sneakerweb est configurée pour l'Item, cette entrée émet après
le scan valide un claim à usage unique et redirige vers la PWA. Sans carte
configurée, elle conserve son comportement de repli vers la page publique.
Le fichier `.snk` n'a pas d'URL GET permanente ; le détail du flux est décrit
dans [`SNEAKERWEB_PRIVATE_DELIVERY.md`](SNEAKERWEB_PRIVATE_DELIVERY.md).

## Ajouter une nouvelle pièce

Créer d'abord l'Item et conserver l'identifiant réellement retourné :

```bash
make item-add NFC_COLLECTION=collection_bleu NFC_NETWORK=ic
```

Le numéro n'est pas choisi manuellement : la Collection attribue le prochain
ID disponible et la commande affiche ensuite le path `nfc/item/<ID>` ainsi que
la commande `nfc-plan` correspondante. La description est facultative, les
attributs sont ignorés par défaut et la rareté vaut `Unique` si elle est laissée
vide.

Une pièce ne peut plus être supprimée tant que sa route NFC existe ou qu'un
historique de Stitch lui est associé. Cette protection évite de conserver une
puce ou un historique pointant vers un Item absent ; une remise à zéro complète
reste une opération explicite par `reinstall`.

Puis prévisualiser et programmer sa puce :

```bash
make nfc-plan NFC_COLLECTION=collection_bleu NFC_ITEM_ID=<ID_RETOURNE> NFC_NETWORK=ic
make nfc-program NFC_COLLECTION=collection_bleu NFC_ITEM_ID=<ID_RETOURNE> NFC_NETWORK=ic
```

Le même workflow s'applique à Heloise en sélectionnant explicitement son
alias :

```bash
make item-add NFC_COLLECTION=collection_heloise NFC_NETWORK=ic
make nfc-plan NFC_COLLECTION=collection_heloise NFC_ITEM_ID=<ID_RETOURNE> NFC_NETWORK=ic
make nfc-program NFC_COLLECTION=collection_heloise NFC_ITEM_ID=<ID_RETOURNE> NFC_NETWORK=ic
```

## État actuel de l'intégration Stitch

Ce workflow programme le SDM, charge les preuves CMAC dans la bonne Collection
et protège l'entrée NFC dédiée avant sa redirection vers la fiche publique. Le
reader réel signe ensuite `uid`, `ctr`, `cmac`, le Principal de la Collection,
le path, `item_id` et l'horodatage, puis envoie cette enveloppe au Hub.

Le bridge physique est déployé sur le Hub et les trois Collections
`collection_monayolla`, `collection_bleu` et `collection_heloise`. Le Hub
authentifie le reader, vérifie son statut, son lieu, la fraîcheur de l'enveloppe
et l'inscription de la Collection. Il regroupe ensuite deux ou trois scans
effectués par le même reader dans une fenêtre strictement inférieure à
10 secondes.

Le Hub transmet le `uid`, le compteur et le CMAC dans les appels existants
`prepare_meeting` et `finalize_meeting`. Il n'existe volontairement aucun appel
`validate_tag_scan` supplémentaire : chaque Collection valide elle-même la
route `nfc/item/<id>`, l'association UID/Item, le hash du CMAC et la monotonie
du compteur avant de consommer celui-ci et d'enregistrer le Stitch. Les chemins
nominaux restent donc à 1, 3 ou 5 appels inter-canisters selon le nombre de
Collections participantes.

Pour un test à deux objets, scanner les deux puces nettement en moins de
9 secondes, puis attendre environ 15 secondes après le premier scan : la
session reste ouverte jusqu'à la fin de la fenêtre, avec une courte marge de
réception. Avec trois objets, le troisième scan ferme immédiatement la session.
La LED verte du reader indique actuellement la mise en file locale, pas encore
la confirmation finale du Stitch ; vérifier le résultat sur les pages Item.

Pour exercer le chemin maximal à cinq appels inter-canisters, scanner un objet
de chacune des trois Collections. Le Hub effectue alors deux `prepare_meeting`,
un `finalize_meeting`, puis deux `confirm_meeting`.

Les anciennes cibles `protect` et `protect_ic` restent disponibles, mais sont
désormais des alias de prévisualisation uniquement. Elles ne programment plus
une puce implicitement. `NFC_COLLECTION` est toujours obligatoire, et
`NFC_ITEM_ID` l'est pour chaque opération NFC. Sans `NFC_NETWORK`, les commandes
ciblent `local` ; un ciblage de l'IC doit donc rester visible avec
`NFC_NETWORK=ic`.

Les méthodes Candid qui exposent les tables CMAC complètes, les records de
Stitch bruts (incluant l'identifiant interne du reader) et l'ancien stockage de
fichiers sont réservées à l'identité qui a initialisé la Collection. Les scripts
opérateur transmettent donc explicitement `NFC_IDENTITY` (par défaut `raygen`) ;
un appel anonyme est rejeté. Les pages HTTP continuent d'utiliser directement
le store interne et n'exposent que le lieu, l'heure et les objets stitchés.
