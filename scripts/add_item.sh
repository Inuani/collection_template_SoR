#!/usr/bin/env bash

set -u

# Script to add items to the collection
# Usage: ./add_item.sh <canister_alias> <network> [identity]

CANISTER_NAME=${1:-}
NETWORK=${2:-ic}
IDENTITY=${3:-raygen}

# Check if canister name is provided
if [ -z "$CANISTER_NAME" ]; then
    echo "Error: Canister name is required"
    echo "Usage: $0 <canister_alias> <network> [identity]"
    exit 1
fi

case "$NETWORK" in
    ic|local) ;;
    *)
        echo "Error: network must be 'ic' or 'local'"
        exit 1
        ;;
esac

if ! CANISTER_ID=$(dfx canister id --network "$NETWORK" --identity "$IDENTITY" "$CANISTER_NAME" 2>/dev/null); then
    echo "Error: cannot resolve '$CANISTER_NAME' on network '$NETWORK'"
    exit 1
fi

echo "Adding item to collection..."
echo "Canister: $CANISTER_NAME"
echo "Principal: $CANISTER_ID"
echo "Network: $NETWORK"
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
ATTRIBUTES="vec {"
read -r -p "Add attributes? [y/N]: " ADD_ATTRIBUTES
case "$ADD_ATTRIBUTES" in
    y|Y|yes|YES|Yes|o|O|oui|OUI|Oui)
        while true; do
            read -r -p "Attribute key (Enter to finish): " KEY
            if [ -z "$KEY" ]; then
                break
            fi
            read -r -p "Attribute value: " VALUE
            ATTRIBUTES="${ATTRIBUTES}record{\"${KEY}\"; \"${VALUE}\"};"
        done
        ;;
esac

ATTRIBUTES="${ATTRIBUTES}}"

echo ""
echo "Adding item with:"
echo "  Name: $NAME"
echo "  Thumbnail: $THUMBNAIL"
echo "  Image: $IMAGE"
echo "  Description: $DESCRIPTION"
echo "  Rarity: $RARITY"
echo ""

# Call the canister function
RESULT=$(dfx canister --network "$NETWORK" --identity "$IDENTITY" call "$CANISTER_NAME" addCollectionItem \
  "(\"$NAME\", \"$THUMBNAIL\", \"$IMAGE\", \"$DESCRIPTION\", \"$RARITY\", $ATTRIBUTES)")

if [ $? -eq 0 ]; then
    echo "✓ Item added successfully!"
    echo "Result: $RESULT"

    # Extract ID from result
    ID=$(echo $RESULT | grep -o '[0-9]*' | head -1)
    if [ -n "$ID" ]; then
        echo ""
        echo "Item ID: $ID"
        echo "View at: /item/$ID"
        echo "NFC path: /nfc/item/$ID"
        echo ""
        echo "Next safe step (plan only):"
        echo "make nfc-plan NFC_COLLECTION=$CANISTER_NAME NFC_ITEM_ID=$ID NFC_NETWORK=$NETWORK"
    fi
else
    echo "✗ Failed to add item"
    exit 1
fi
