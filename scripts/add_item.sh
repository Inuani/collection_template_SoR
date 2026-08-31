#!/usr/bin/env bash

set -euo pipefail

# Script to add items to the collection
# Usage: ./add_item.sh <canister_alias> <environment> [identity]

CANISTER_NAME=${1:-}
ENVIRONMENT=${2:-local}
IDENTITY=${3:-raygen}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Check if canister name is provided
if [ -z "$CANISTER_NAME" ]; then
    echo "Error: Canister name is required"
    echo "Usage: $0 <canister_alias> <environment> [identity]"
    exit 1
fi

case "$ENVIRONMENT" in
    ic|local) ;;
    *)
        echo "Error: environment must be 'ic' or 'local'"
        exit 1
        ;;
esac

if ! command -v icp >/dev/null 2>&1; then
    echo "Error: icp is not available"
    exit 1
fi

if ! CANISTER_ID=$(icp canister status "$CANISTER_NAME" --environment "$ENVIRONMENT" --identity "$IDENTITY" --id-only 2>/dev/null); then
    echo "Error: cannot resolve '$CANISTER_NAME' in environment '$ENVIRONMENT'"
    exit 1
fi

echo "Adding item to collection..."
echo "Canister: $CANISTER_NAME"
echo "Principal: $CANISTER_ID"
echo "Environment: $ENVIRONMENT"
echo "Identity: $IDENTITY"
echo ""

# Prompt for item details
read -r -p "Item name: " NAME
read -r -p "Thumbnail URL (e.g., /item0_thumb.webp): " THUMBNAIL
read -r -p "Image URL (e.g., /item0.webp): " IMAGE
read -r -p "Description (optional, Enter to skip): " DESCRIPTION
read -r -p "Rarity [Unique]: " RARITY
RARITY=${RARITY:-Unique}

echo ""
ATTRIBUTE_ARGUMENTS=()
read -r -p "Add attributes? [y/N]: " ADD_ATTRIBUTES
case "$ADD_ATTRIBUTES" in
    y|Y|yes|YES|Yes|o|O|oui|OUI|Oui)
        while true; do
            read -r -p "Attribute key (Enter to finish): " KEY
            if [ -z "$KEY" ]; then
                break
            fi
            read -r -p "Attribute value: " VALUE
            ATTRIBUTE_ARGUMENTS+=("$KEY" "$VALUE")
        done
        ;;
esac

echo ""
echo "Adding item with:"
echo "  Name: $NAME"
echo "  Thumbnail: $THUMBNAIL"
echo "  Image: $IMAGE"
echo "  Description: $DESCRIPTION"
echo "  Rarity: $RARITY"
echo ""

ARGUMENT=$(python3 "$SCRIPT_DIR/candid_values.py" item-argument \
    "$NAME" "$THUMBNAIL" "$IMAGE" "$DESCRIPTION" "$RARITY" \
    "${ATTRIBUTE_ARGUMENTS[@]}") || exit 1

# JSON output makes the returned Nat unambiguous. Text fields are rendered by
# candid_values.py so quotes, backslashes and newlines cannot alter the call.
if RESULT=$(icp canister call "$CANISTER_NAME" addCollectionItem "$ARGUMENT" \
    --environment "$ENVIRONMENT" --identity "$IDENTITY" --output candid); then
    echo "✓ Item added successfully!"
    echo "Result: $RESULT"

    if ! ID=$(python3 "$SCRIPT_DIR/candid_values.py" parse-nat "$RESULT"); then
        echo "✗ Item was added, but its returned ID could not be decoded safely"
        exit 1
    fi
    echo ""
    echo "Item ID: $ID"
    echo "View at: /item/$ID"
    echo "NFC path: /nfc/item/$ID"
    echo ""
    echo "Next safe step (plan only):"
    echo "make nfc-plan NFC_COLLECTION=$CANISTER_NAME NFC_ITEM_ID=$ID NFC_ENVIRONMENT=$ENVIRONMENT"
else
    echo "✗ Failed to add item"
    exit 1
fi
