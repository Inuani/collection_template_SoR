# Livraison privée Sneakerweb

> Procédure opérationnelle complète :
> [`../sneakerweb_xp/SNK_WORKFLOW.md`](../sneakerweb_xp/SNK_WORKFLOW.md).
> Le présent document détaille surtout la sécurité et l'implémentation côté
> Collection.

Une Collection peut associer un fichier `.snk` à un Item NFC sans publier ce
fichier comme asset HTTP. Aucun compte, Internet Identity ou clé utilisateur
n'est nécessaire.

## Flux

```text
scan NFC valide
  -> claim à usage unique
  -> redirection vers la PWA
  -> échange du claim par POST
  -> capability temporaire pour le paquet
  -> téléchargement du .snk par POST
```

Le reçu décrit une acquisition `nfc_scan`, mais ne contient ni UID ni CMAC. La
PWA conserve cette preuve locale séparément du `.snk`. Le fichier exportable
reste donc le contenu de la carte : le partager ne transfère pas la preuve
personnelle de contact avec l'objet.

## Séparation du code

- `sneakerweb_claims.mo` conserve les configurations, claims à usage unique et
  capabilities temporaires de paquets.
- `routes/sneakerweb_routes.mo` expose uniquement les deux routes POST du
  protocole PWA.
- `files.mo` stocke les octets et gère le découpage en chunks ; il ne connaît
  ni HTTP, ni NFC, ni secret.
- `middleware/nfc.mo` valide et consomme le scan avant d'émettre un claim.
- `file_access.mo` signe les liens temporaires de l'ancien lecteur de fichiers.
  Son secret interne au canister n'est pas une identité utilisateur et n'est
  pas utilisé par le flux `.snk` Sneakerweb.
- `file_views.mo` contient la vue HTML de l'ancien lecteur de fichiers.

Un `.snk` configuré reste refusé sur les routes GET historiques
`/files/<nom>` et `/api/stream/<nom>`. Il n'est livré que par
`POST /api/sneakerweb/v1/packages` avec une capability valide.

## Upgrade d'une Collection

Toujours créer un snapshot avant l'upgrade IC :

```bash
icp canister stop collection_bleu --environment ic --identity raygen
icp canister snapshot create collection_bleu --environment ic --identity raygen
icp canister start collection_bleu --environment ic --identity raygen
icp deploy collection_bleu --environment ic --identity raygen \
  --mode upgrade --no-create
```

Le premier upgrade vers cette version ajoute un secret aléatoire de 32 octets
pour les anciens liens temporaires de fichiers. Il est créé dans le canister et
n'est jamais affiché :

```bash
icp canister call collection_bleu get_file_access_status '()' --environment ic --identity raygen --query
icp canister call collection_bleu rotate_file_access_secret '()' --environment ic --identity raygen
icp canister call collection_bleu get_file_access_status '()' --environment ic --identity raygen --query
```

L'appel de rotation est réservé à l'identité qui a initialisé la Collection.
Il n'est requis qu'une fois après ce premier upgrade, sauf rotation volontaire.
Un canister non initialisé refuse ces liens sans consommer le compteur NFC. Le
flux privé Sneakerweb continue, lui, à utiliser ses propres capabilities.

## Vérifications

```bash
mops test
python3 test/test_nfc_scripts.py -q
icp build collection_bleu
```

Après un upgrade, vérifier au minimum le nom, les Items, les routes NFC, les
fichiers et la configuration Sneakerweb avant de passer au canister suivant.
