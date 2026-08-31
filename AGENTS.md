# Consignes pour les agents

Lire d'abord [`README.md`](README.md). Pour toute opération NFC, lire
intégralement [`NFC_WORKFLOW.md`](NFC_WORKFLOW.md). Pour toute livraison privée
Sneakerweb, lire aussi [`SNEAKERWEB_PRIVATE_DELIVERY.md`](SNEAKERWEB_PRIVATE_DELIVERY.md)
et le `SNK_WORKFLOW.md` du dépôt frère `sneakerweb_xp`.

- Interroger le canister avant toute écriture et toujours expliciter alias,
  réseau, identité et Item ID.
- Ne jamais afficher ou commiter une clé NFC, un UID, une table CMAC, un token
  de claim ou une capability.
- Ne jamais consommer un compteur NFC de production pour une inspection.
- Créer un snapshot avant chaque upgrade de code IC et vérifier l'état après.
- Ne jamais utiliser `reinstall` sans demande explicite de remise à zéro.
- Le code et les tests actifs priment sur les documents de vision historique.
- Pour l'interface, suivre `../social/evorev-ui/README.md` et la palette
  associée. Les fontes du canister sont générées depuis
  `assets/evorev/` avec `scripts/generate-evorev-fonts.mjs`; exécuter le
  script avec `--check` avant tout build ou upgrade.
