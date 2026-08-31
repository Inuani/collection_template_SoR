#!/usr/bin/env bash

set -euo pipefail

# Usage: ./init_collection.sh [canister_name] [environment] [identity]
CANISTER_NAME=${1:-collection_monayolla}
ENVIRONMENT=${2:-local}
IDENTITY=${3:-raygen}

call_update() {
    local method=$1
    local argument=$2
    icp canister call "$CANISTER_NAME" "$method" "$argument" \
        --environment "$ENVIRONMENT" --identity "$IDENTITY" --output candid
}

echo "Initializing collection with demo items..."
echo "Canister    : $CANISTER_NAME"
echo "Environment : $ENVIRONMENT"
echo "Identity    : $IDENTITY"

echo "Adding Item 0: Hoodie #0..."
call_update addCollectionItem \
  '("Hoodie #0", "/thumb_0.webp", "/item_0.webp", "pull en lien avec l'\''événement du 30 avril", "Légendaire", vec {record{"Type"; "Sky"}; record{"Intensity"; "Light"}; record{"Mood"; "Calm"}})'

echo "Adding Item 1: Hoodie #1..."
call_update addCollectionItem \
  '("Hoodie #1", "/thumb_1.webp", "/item_1.webp", "The mysterious deep blue of ocean trenches", "Rare", vec {record{"Type"; "Ocean"}; record{"Aura"; "+100"}; record{"Forme"; "Triangle"}})'

echo "Adding Item 2: Hoodie #2..."
call_update addCollectionItem \
  '("Hoodie #2", "/thumb_2.webp", "/item2.webp", "The intense blue-black of a stormy midnight sky", "Rare", vec {record{"Type"; "Storm"}; record{"Intensity"; "Deep"}; record{"Mood"; "Mysterious"}})'

echo "Adding Item 3: Hoodie #3..."
call_update addCollectionItem \
  '("Hoodie #3", "/thumb_3.webp", "/item_3.webp", "The intense blue-black of a stormy midnight sky", "Rare", vec {record{"Type"; "Storm"}; record{"Intensity"; "Deep"}; record{"Mood"; "Mysterious"}})'

echo "Collection initialization complete."
icp canister call "$CANISTER_NAME" getCollectionItemCount '()' \
    --environment "$ENVIRONMENT" --identity "$IDENTITY" --query --output candid
