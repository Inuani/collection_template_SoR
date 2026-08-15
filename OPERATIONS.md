# Exploitation des Collections IC

Ce guide couvre les opérations de maintenance. La création des Items et la
programmation physique restent documentées dans [`NFC_WORKFLOW.md`](NFC_WORKFLOW.md).

## Préflight

Depuis `collections/` :

```bash
mops install --lock check
mops test
python3 test/test_nfc_scripts.py -q
mops check <collection>
icp build <collection>
icp canister status <collection> --environment ic --identity raygen
icp canister call <collection> getCollectionName '()' --environment ic --identity raygen --query
icp canister call <collection> getCollectionItemCount '()' --environment ic --identity raygen --query
icp canister call <collection> listProtectedRoutesSummary '()' --environment ic --identity raygen --query
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

icp canister stop "$CANISTER" --environment ic --identity raygen
icp canister snapshot create "$CANISTER" --environment ic --identity raygen
icp canister start "$CANISTER" --environment ic --identity raygen

icp deploy "$CANISTER" --environment ic --identity raygen \
  --mode upgrade --no-create
mops deployed "$CANISTER"
```

La commande équivalente du projet, après création du snapshot, est :

```bash
make ic COLLECTION="$CANISTER"
```

Elle conserve le garde-fou `--mode upgrade --no-create`.

Toujours redémarrer immédiatement le canister après la création du snapshot,
même si le déploiement doit être reporté.

Après l'upgrade, relire au minimum :

```bash
icp canister call "$CANISTER" getCollectionName '()' --environment ic --identity raygen --query
icp canister call "$CANISTER" getCollectionItemCount '()' --environment ic --identity raygen --query
icp canister call "$CANISTER" listProtectedRoutesSummary '()' --environment ic --identity raygen --query
icp canister call "$CANISTER" getStoredFileCount '()' --environment ic --identity raygen --query
icp canister call "$CANISTER" get_sneakerweb_claim_config '()' --environment ic --identity raygen --query
icp canister call "$CANISTER" protocol_info '()' --environment ic --identity raygen --query
```

## Sauvegarde et rétention des snapshots

Les snapshots conservés sur l'IC augmentent la mémoire facturée. Politique
recommandée : un snapshot courant sur le canister, plus une ancienne version
connue et téléchargée hors canister.

```bash
icp canister snapshot list "$CANISTER" --environment ic --identity raygen

icp canister snapshot download "$CANISTER" <snapshot-id> \
  --environment ic --identity raygen \
  --output "$HOME/.local/share/evorev/canister-snapshots/<date>/$CANISTER"

icp canister snapshot delete "$CANISTER" <ancien-snapshot-id> \
  --environment ic --identity raygen
```

Ne supprimer un snapshot qu'après téléchargement réussi et conservation de son
identifiant, sa date, sa taille et le module hash associé.

## Restauration

Une restauration détruit tout changement postérieur au snapshot. Confirmer le
snapshot et l'état à perdre avant d'exécuter :

```bash
icp canister stop "$CANISTER" --environment ic --identity raygen
icp canister snapshot restore "$CANISTER" <snapshot-id> \
  --environment ic --identity raygen
icp canister start "$CANISTER" --environment ic --identity raygen
```

Relancer ensuite toutes les vérifications post-upgrade.

## Cycles

Le champ `Idle cycles burned per day` de `icp canister status` inclut notamment
le coût de la mémoire et des snapshots. Le canister doit conserver en plus sa
réserve correspondant au `Freezing threshold`.

Contrôler les trois Collections après chaque upgrade et au moins une fois par
mois. Traiter toute autonomie estimée inférieure à 90 jours comme une alerte :
réduire d'abord les snapshots obsolètes, puis ajouter des cycles si nécessaire.
