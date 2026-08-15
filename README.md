# Collections Evorev

Ce dépôt contient les canisters ICP qui portent les Items, leurs routes NFC
NTAG 424 DNA, leurs historiques Knitwork et la livraison privée des cartes
Sneakerweb `.snk`.

Les trois canisters IC utilisent le même code Motoko :

| Alias ICP CLI | Principal IC |
| --- | --- |
| `collection_monayolla` | `4623w-oqaaa-aaaak-qtrjq-cai` |
| `collection_bleu` | `ubnuj-uyaaa-aaaak-qudbq-cai` |
| `collection_heloise` | `jmp6g-oqaaa-aaaak-qug3q-cai` |

## Déploiement ICP CLI

Les trois canisters ont été migrés le 15 août 2026 avec leurs Principals et
leur état existants. Ils utilisent ICP CLI 1.3, le recipe Motoko v5 et
`moc 1.1.0` verrouillé dans `mops.toml`. Liminal reste une dépendance Motoko du
canister (`liminal 3.1.0`) : ses routes HTTP et CORS ont été validées après les
trois upgrades.

```bash
make check
make ic COLLECTION=collection_bleu
```

La cible `ic` exécute uniquement un upgrade explicite avec `--no-create`. Elle
ne peut donc ni créer silencieusement un nouveau canister ni réinstaller celui
qui existe.

## Documentation actuelle

- [`NFC_WORKFLOW.md`](NFC_WORKFLOW.md) : créer un Item et programmer sa puce ;
- [`SNEAKERWEB_PRIVATE_DELIVERY.md`](SNEAKERWEB_PRIVATE_DELIVERY.md) : sécurité
  du claim et livraison privée du `.snk` ;
- [`OPERATIONS.md`](OPERATIONS.md) : tests, upgrade, snapshots, restauration et
  surveillance des cycles ;
- dans le dépôt frère `sneakerweb_xp`, `SNK_WORKFLOW.md` reste la procédure
  canonique pour créer, vérifier et associer une carte.

`architecture_overview.md` et `les_collections_devorev.md` décrivent une vision
produit historique plus large. Ils ne remplacent pas le code ni les guides
opérationnels ci-dessus.

## Vérifications locales

```bash
mops test
python3 test/test_nfc_scripts.py -q
mops check collection_monayolla
icp build collection_monayolla
```

Le test d'intégration Hub + Collections se trouve dans le dépôt frère
`proof_of_meet/integration/knitwork`.

## Sécurité opérateur

Toujours indiquer explicitement le canister, le réseau et l'identité. Ne jamais
publier une clé AES NFC, un UID, une table CMAC, un token de claim ou une
capability de paquet. Un `reinstall` efface l'état du canister ; il ne doit
jamais servir à une mise à jour normale.

Les builds et déploiements utilisent ICP CLI. `dfx.json` et `canister_ids.json`
restent temporairement présents uniquement pour les scripts NFC historiques ;
ils ne sont plus la source des IDs de déploiement.
