# Exploitation des Collections IC

Ce guide couvre les opérations de maintenance. La création des Items et la
programmation physique restent documentées dans [`NFC_WORKFLOW.md`](NFC_WORKFLOW.md).

## Préflight

Depuis `collections/` :

```bash
mops test
python3 test/test_nfc_scripts.py -q
dfx build --ic <collection>
dfx canister --network ic --identity raygen status <collection>
dfx canister --network ic --identity raygen call <collection> getCollectionName
dfx canister --network ic --identity raygen call <collection> getCollectionItemCount
dfx canister --network ic --identity raygen call <collection> listProtectedRoutesSummary
```

Ne pas appeler les méthodes qui retournent les UID ou CMAC pour une simple
inspection. Pour un résumé des trois canisters et de leurs snapshots :

```bash
make ic-health
```

## Upgrade, un canister à la fois

Un snapshot exige un court arrêt du canister :

```bash
CANISTER=collection_bleu

dfx canister --network ic --identity raygen stop "$CANISTER"
dfx canister snapshot create --network ic --identity raygen "$CANISTER"
dfx canister --network ic --identity raygen start "$CANISTER"

dfx deploy --network ic --identity raygen "$CANISTER" \
  --mode upgrade \
  --wasm-memory-persistence keep
```

Toujours redémarrer immédiatement le canister après la création du snapshot,
même si le déploiement doit être reporté.

Après l'upgrade, relire au minimum :

```bash
dfx canister --network ic --identity raygen call "$CANISTER" getCollectionName
dfx canister --network ic --identity raygen call "$CANISTER" getCollectionItemCount
dfx canister --network ic --identity raygen call "$CANISTER" listProtectedRoutesSummary
dfx canister --network ic --identity raygen call "$CANISTER" getStoredFileCount
dfx canister --network ic --identity raygen call "$CANISTER" get_sneakerweb_claim_config
dfx canister --network ic --identity raygen call "$CANISTER" protocol_info
```

## Sauvegarde et rétention des snapshots

Les snapshots conservés sur l'IC augmentent la mémoire facturée. Politique
recommandée : un snapshot courant sur le canister, plus une ancienne version
connue et téléchargée hors canister.

```bash
dfx canister snapshot list --network ic --identity raygen "$CANISTER"

dfx canister snapshot download --network ic --identity raygen \
  --dir "$HOME/.local/share/evorev/canister-snapshots/<date>/$CANISTER" \
  "$CANISTER" <snapshot-id>

dfx canister snapshot delete --network ic --identity raygen \
  "$CANISTER" <ancien-snapshot-id>
```

Ne supprimer un snapshot qu'après téléchargement réussi et conservation de son
identifiant, sa date, sa taille et le module hash associé.

## Restauration

Une restauration détruit tout changement postérieur au snapshot. Confirmer le
snapshot et l'état à perdre avant d'exécuter :

```bash
dfx canister --network ic --identity raygen stop "$CANISTER"
dfx canister snapshot load --network ic --identity raygen \
  "$CANISTER" <snapshot-id>
dfx canister --network ic --identity raygen start "$CANISTER"
```

Relancer ensuite toutes les vérifications post-upgrade.

## Cycles

Le champ `Idle cycles burned per day` de `dfx canister status` inclut notamment
le coût de la mémoire et des snapshots. Le canister doit conserver en plus sa
réserve correspondant au `Freezing threshold`.

Contrôler les trois Collections après chaque upgrade et au moins une fois par
mois. Traiter toute autonomie estimée inférieure à 90 jours comme une alerte :
réduire d'abord les snapshots obsolètes, puis ajouter des cycles si nécessaire.
