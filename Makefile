# http://u6s2n-gx777-77774-qaaba-cai.raw.localhost:4943/api/hello/elie

# icx-asset --replica http://127.0.0.1:4943 --pem ~/.config/dfx/identity/raygen/identity.pem sync $(dfx canister id liminal) ./public

-include .env

REPLICA_URL := $(if $(filter ic,$(subst ',,$(DFX_NETWORK))),https://ic0.app,http://127.0.0.1:4943)
CANISTER_NAME := $(shell test -f .env && grep "CANISTER_ID_" .env | grep -v "INTERNET_IDENTITY\|CANISTER_ID='" | head -1 | sed 's/CANISTER_ID_\([^=]*\)=.*/\1/' | tr '[:upper:]' '[:lower:]')
CANISTER_ID := $(CANISTER_ID_$(shell echo $(CANISTER_NAME) | tr '[:lower:]' '[:upper:]'))
IC_CANISTER_ID = $(shell dfx canister id $(CANISTER_NAME) --ic)
CMAC_COUNT ?= 20000

# NFC enrollment always targets one explicit Collection. These variables are
# deliberately independent from CANISTER_NAME, which may still be used by the
# older local-development targets below.
NFC_COLLECTION ?=
NFC_ITEM_ID ?=
NFC_ROUTE ?= nfc/item/$(NFC_ITEM_ID)
NFC_NETWORK ?= local
NFC_IDENTITY ?= raygen
NFC_CMAC_COUNT ?= $(CMAC_COUNT)
NFC_BATCH_SIZE ?= 1000
NFC_RANDOM_KEY ?= 0
NFC_PARAM ?= item_id=$(NFC_ITEM_ID)
# Keep an independent Principal allowlist for live NFC enrollment. This makes a
# mistyped or accidentally remapped dfx alias fail before any tag/canister write.
NFC_EXPECTED_CANISTER_ID_collection_monayolla := 4623w-oqaaa-aaaak-qtrjq-cai
NFC_EXPECTED_CANISTER_ID_collection_bleu := ubnuj-uyaaa-aaaak-qudbq-cai
NFC_EXPECTED_CANISTER_ID_collection_heloise := jmp6g-oqaaa-aaaak-qug3q-cai
NFC_EXPECTED_CANISTER_ID ?= $(NFC_EXPECTED_CANISTER_ID_$(NFC_COLLECTION))
NFC_KEY_ARGS = $(if $(filter 1 yes true,$(NFC_RANDOM_KEY)),--random-key,)
# Live aliases are pinned to their known IC Principals. Local canisters receive
# different ephemeral Principals, so the live allowlist must not be applied.
NFC_EXPECTED_ARGS = $(if $(filter ic,$(NFC_NETWORK)),$(if $(strip $(NFC_EXPECTED_CANISTER_ID)),--expected-canister-id $(NFC_EXPECTED_CANISTER_ID),),)
NFC_ARGS = --canister $(NFC_COLLECTION) --item-id $(NFC_ITEM_ID) --route $(NFC_ROUTE) --network $(NFC_NETWORK) --identity $(NFC_IDENTITY) --cmac-count $(NFC_CMAC_COUNT) --batch-size $(NFC_BATCH_SIZE) --param $(NFC_PARAM) $(NFC_KEY_ARGS) $(NFC_EXPECTED_ARGS)

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
    OPEN_CMD := open
else ifeq ($(UNAME), Linux)
    OPEN_CMD := xdg-open
else
    OPEN_CMD := start
endif

all:
	dfx deploy $(CANISTER_NAME)

ic:
	dfx deploy $(CANISTER_NAME) --ic

url:
	$(OPEN_CMD) http://$(CANISTER_ID).raw.localhost:4943/

open:
	$(OPEN_CMD) https://$(IC_CANISTER_ID).raw.icp0.io/

irl: open

sync:
	icx-asset --replica http://127.0.0.1:4943 --pem ~/.config/dfx/identity/raygen/identity.pem sync $(CANISTER_ID) ./public

Isync:
	icx-asset --replica https://ic0.app --pem ~/.config/dfx/identity/raygen/identity.pem sync $(CANISTER_ID) ./public

.PHONY: require-nfc-collection require-nfc-item item-add nfc-plan nfc-program protect protect_ic

require-nfc-collection:
	@test -n "$(strip $(NFC_COLLECTION))" || { \
		echo "Error: NFC_COLLECTION is required (for example collection_bleu)"; \
		exit 2; \
	}

require-nfc-item:
	@test -n "$(strip $(NFC_ITEM_ID))" || { \
		echo "Error: NFC_ITEM_ID is required"; \
		exit 2; \
	}

# Interactively creates an Item in the explicitly selected Collection.
# The canister assigns the Item ID; the script prints the matching NFC command.
item-add: require-nfc-collection
	./scripts/add_item.sh $(NFC_COLLECTION) $(NFC_NETWORK) $(NFC_IDENTITY)

# Safe preflight only: no reader, tag or canister state is modified.
nfc-plan: require-nfc-collection require-nfc-item
	python3 scripts/setup_route.py $(NFC_ARGS)

# Explicit hardware/on-chain execution. The script displays the resolved
# Collection, Item, Principal and path, then requires a `y` confirmation.
nfc-program: require-nfc-collection require-nfc-item
	python3 scripts/setup_route.py $(NFC_ARGS) --execute

# Backward-compatible names. Both are intentionally plan-only now.
protect: NFC_NETWORK = local
protect: NFC_CMAC_COUNT = 200
protect: nfc-plan

protect_ic: NFC_NETWORK = ic
protect_ic: nfc-plan

reinstall:
	dfx deploy $(CANISTER_NAME) --mode reinstall

ls:
	icx-asset --replica https://ic0.app --pem ~/.config/dfx/identity/raygen/identity.pem ls $(CANISTER_ID)

delete_asset:
	dfx canister call --ic $(CANISTER_ID) delete_asset '(record { key = "/logo.webp" })'

upload_file:
	./scripts/upload_file.sh certificats/luandi_caramelo.m4a "caramelo" "Luandi" $(CANISTER_NAME) $(DFX_NETWORK)

download_file:
	./scripts/download_file.sh "ekip" img_downloaded.png $(CANISTER_NAME) $(DFX_NETWORK)

list_files:
	dfx canister call $(CANISTER_NAME) listFiles

file_count:
	dfx canister call $(CANISTER_NAME) getStoredFileCount

delete_file:
	dfx canister call $(CANISTER_NAME) deleteFile '("logo.png")'

# Collection Management
init_collection:
	chmod +x scripts/init_collection.sh
	./scripts/init_collection.sh $(CANISTER_NAME) local

# Backward-compatible alias for the interactive, explicit Collection workflow.
add_item: item-add

list_items:
	dfx canister call $(CANISTER_NAME) getAllCollectionItems

item_count:
	dfx canister call $(CANISTER_NAME) getCollectionItemCount

collection_name:
	dfx canister call $(CANISTER_NAME) getCollectionName

change_theme:
	dfx canister call $(CANISTER_NAME) setTheme '("#1E3A8A", "#3B82F6")'

check_protect_routes:
	dfx canister call --ic $(CANISTER_NAME) listProtectedRoutesSummary

collection_name_update:
	dfx canister call $(CANISTER_NAME) setCollectionName '("Luandi")'

button_create:
	dfx canister call $(CANISTER_NAME) addButton '("Instagram", "https://www.instagram.com/collections_evorev/")'

buttons_see_all:
	dfx canister call $(CANISTER_NAME) getAllButtons
