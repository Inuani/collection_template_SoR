COLLECTION ?= collection_bleu
CANISTER_NAME ?= $(COLLECTION)
ICP_ENVIRONMENT ?= local
ICP_IDENTITY ?= raygen
CANISTER_ID = $(shell jq -r --arg name "$(CANISTER_NAME)" '.[$$name] // empty' .icp/cache/mappings/local.ids.json 2>/dev/null)
IC_CANISTER_ID = $(shell jq -r --arg name "$(CANISTER_NAME)" '.[$$name] // empty' .icp/data/mappings/ic.ids.json)
CMAC_COUNT ?= 20000
ICX_IDENTITY_PEM ?=
ICX_LOCAL_REPLICA ?= http://127.0.0.1:8000
ICX_IC_REPLICA ?= https://ic0.app
UPLOAD_PATH ?=
UPLOAD_TITLE ?= $(notdir $(UPLOAD_PATH))
UPLOAD_ARTIST ?= Unknown
DOWNLOAD_TITLE ?=
DOWNLOAD_OUTPUT ?= downloaded_file

# NFC enrollment always targets one explicit Collection. These variables are
# deliberately independent from CANISTER_NAME, which is used by the general
# development targets below.
NFC_COLLECTION ?=
NFC_ITEM_ID ?=
NFC_ROUTE ?= nfc/item/$(NFC_ITEM_ID)
NFC_ENVIRONMENT ?= local
NFC_IDENTITY ?= raygen
NFC_CMAC_COUNT ?= $(CMAC_COUNT)
NFC_BATCH_SIZE ?= 1000
NFC_KEY_MODE ?=
NFC_RANDOM_KEY ?=
NFC_PARAM ?= item_id=$(NFC_ITEM_ID)
IC_IDENTITY ?= $(ICP_IDENTITY)
IC_COLLECTIONS := collection_monayolla collection_bleu collection_heloise
# Keep an independent Principal allowlist for live NFC enrollment. This makes a
# mistyped or accidentally remapped ICP CLI alias fail before any tag/canister write.
NFC_EXPECTED_CANISTER_ID_collection_monayolla := 4623w-oqaaa-aaaak-qtrjq-cai
NFC_EXPECTED_CANISTER_ID_collection_bleu := ubnuj-uyaaa-aaaak-qudbq-cai
NFC_EXPECTED_CANISTER_ID_collection_heloise := jmp6g-oqaaa-aaaak-qug3q-cai
NFC_EXPECTED_CANISTER_ID ?= $(NFC_EXPECTED_CANISTER_ID_$(NFC_COLLECTION))
NFC_LEGACY_KEY_MODE = $(if $(filter 1 yes true,$(NFC_RANDOM_KEY)),random,$(if $(filter 0 no false,$(NFC_RANDOM_KEY)),zero,invalid))
NFC_RESOLVED_KEY_MODE = $(if $(strip $(NFC_KEY_MODE)),$(NFC_KEY_MODE),$(if $(strip $(NFC_RANDOM_KEY)),$(NFC_LEGACY_KEY_MODE),))
NFC_KEY_ARGS = $(if $(strip $(NFC_RESOLVED_KEY_MODE)),--key-mode $(NFC_RESOLVED_KEY_MODE),)
# Live aliases are pinned to their known IC Principals. Local canisters receive
# different ephemeral Principals, so the live allowlist must not be applied.
NFC_EXPECTED_ARGS = $(if $(filter ic,$(NFC_ENVIRONMENT)),$(if $(strip $(NFC_EXPECTED_CANISTER_ID)),--expected-canister-id $(NFC_EXPECTED_CANISTER_ID),),)
NFC_ARGS = --canister $(NFC_COLLECTION) --item-id $(NFC_ITEM_ID) --route $(NFC_ROUTE) --environment $(NFC_ENVIRONMENT) --identity $(NFC_IDENTITY) --cmac-count $(NFC_CMAC_COUNT) --batch-size $(NFC_BATCH_SIZE) --param $(NFC_PARAM) $(NFC_KEY_ARGS) $(NFC_EXPECTED_ARGS)

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
    OPEN_CMD := open
else ifeq ($(UNAME), Linux)
    OPEN_CMD := xdg-open
else
    OPEN_CMD := start
endif

all: check

check: ui-assets-check
	mops install --lock check
	mops test
	python3 test/test_nfc_scripts.py -q
	@for canister in $(IC_COLLECTIONS); do \
		mops check $$canister || exit 1; \
	done
	icp build

ui-assets-check:
	node scripts/generate-evorev-fonts.mjs --check

local: ui-assets-check
	icp network start -d
	icp deploy $(CANISTER_NAME) --environment local --identity $(ICP_IDENTITY)

ic: ui-assets-check
	mops check $(CANISTER_NAME)
	icp deploy $(CANISTER_NAME) --environment ic --identity $(ICP_IDENTITY) --mode upgrade --no-create
	mops deployed $(CANISTER_NAME)

url:
	@test -n "$(CANISTER_ID)" || { echo "Error: deploy $(CANISTER_NAME) locally first"; exit 2; }
	$(OPEN_CMD) http://$(CANISTER_ID).raw.localhost:8000/

open:
	@test -n "$(IC_CANISTER_ID)" || { echo "Error: missing IC mapping for $(CANISTER_NAME)"; exit 2; }
	$(OPEN_CMD) https://$(IC_CANISTER_ID).raw.icp0.io/

irl: open

.PHONY: all check ui-assets-check local ic url open irl stop-local require-nfc-collection require-nfc-item require-icx-pem require-upload-path require-download-title sync-assets-local sync-assets-ic list-assets-ic delete_asset upload_file download_file list_files file_count delete_file init_collection item-add add_item list_items item_count collection_name change_theme check_protect_routes collection_name_update button_create buttons_see_all nfc-plan nfc-program protect protect_ic ic-health reinstall

require-icx-pem:
	@test -n "$(strip $(ICX_IDENTITY_PEM))" || { \
		echo "Error: ICX_IDENTITY_PEM must point to an explicitly exported operator PEM"; \
		exit 2; \
	}
	@test -f "$(ICX_IDENTITY_PEM)" || { echo "Error: PEM not found: $(ICX_IDENTITY_PEM)"; exit 2; }

sync-assets-local: require-icx-pem
	@test -n "$(CANISTER_ID)" || { echo "Error: deploy $(CANISTER_NAME) locally first"; exit 2; }
	icx-asset --replica $(ICX_LOCAL_REPLICA) --pem "$(ICX_IDENTITY_PEM)" sync $(CANISTER_ID) ./public

sync-assets-ic: require-icx-pem
	@test -n "$(IC_CANISTER_ID)" || { echo "Error: missing IC mapping for $(CANISTER_NAME)"; exit 2; }
	icx-asset --replica $(ICX_IC_REPLICA) --pem "$(ICX_IDENTITY_PEM)" sync $(IC_CANISTER_ID) ./public

list-assets-ic: require-icx-pem
	@test -n "$(IC_CANISTER_ID)" || { echo "Error: missing IC mapping for $(CANISTER_NAME)"; exit 2; }
	icx-asset --replica $(ICX_IC_REPLICA) --pem "$(ICX_IDENTITY_PEM)" ls $(IC_CANISTER_ID)

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
	./scripts/add_item.sh $(NFC_COLLECTION) $(NFC_ENVIRONMENT) $(NFC_IDENTITY)

# Safe preflight only: no reader, tag or canister state is modified.
nfc-plan: require-nfc-collection require-nfc-item
	python3 scripts/setup_route.py $(NFC_ARGS)

# Explicit hardware/on-chain execution. The script displays the resolved
# Collection, Item, Principal and path, then requires a `y` confirmation.
nfc-program: require-nfc-collection require-nfc-item
	python3 scripts/setup_route.py $(NFC_ARGS) --execute

# Backward-compatible names. Both are intentionally plan-only now.
protect: NFC_ENVIRONMENT = local
protect: NFC_CMAC_COUNT = 200
protect: nfc-plan

protect_ic: NFC_ENVIRONMENT = ic
protect_ic: nfc-plan

# Read-only production summary. It intentionally avoids methods that disclose
# UID or CMAC material.
ic-health:
	@for canister in $(IC_COLLECTIONS); do \
		echo "== $$canister =="; \
		icp canister status $$canister --environment ic --identity $(IC_IDENTITY); \
		icp canister snapshot list $$canister --environment ic --identity $(IC_IDENTITY); \
	done

reinstall:
	@echo "ERROR: reinstall is forbidden for stateful Collection canisters; use 'make ic COLLECTION=<alias>'." >&2
	@exit 2

stop-local:
	./scripts/stop-local-network.sh 8000

delete_asset:
	icp canister call $(CANISTER_NAME) delete_asset '(record { key = "/logo.webp" })' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --output candid

require-upload-path:
	@test -n "$(strip $(UPLOAD_PATH))" || { echo "Error: UPLOAD_PATH is required"; exit 2; }

upload_file: require-upload-path
	./scripts/upload_file.sh "$(UPLOAD_PATH)" "$(UPLOAD_TITLE)" "$(UPLOAD_ARTIST)" $(CANISTER_NAME) $(ICP_ENVIRONMENT) $(ICP_IDENTITY)

require-download-title:
	@test -n "$(strip $(DOWNLOAD_TITLE))" || { echo "Error: DOWNLOAD_TITLE is required"; exit 2; }

download_file: require-download-title
	./scripts/download_file.sh "$(DOWNLOAD_TITLE)" "$(DOWNLOAD_OUTPUT)" $(CANISTER_NAME) $(ICP_ENVIRONMENT) $(ICP_IDENTITY)

list_files:
	icp canister call $(CANISTER_NAME) listFiles '()' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --query --output candid

file_count:
	icp canister call $(CANISTER_NAME) getStoredFileCount '()' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --query --output candid

delete_file:
	icp canister call $(CANISTER_NAME) deleteFile '("logo.png")' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --output candid

# Collection Management
init_collection:
	./scripts/init_collection.sh $(CANISTER_NAME) $(ICP_ENVIRONMENT) $(ICP_IDENTITY)

# Backward-compatible alias for the interactive, explicit Collection workflow.
add_item: item-add

list_items:
	icp canister call $(CANISTER_NAME) getAllCollectionItems '()' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --query --output candid

item_count:
	icp canister call $(CANISTER_NAME) getCollectionItemCount '()' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --query --output candid

collection_name:
	icp canister call $(CANISTER_NAME) getCollectionName '()' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --query --output candid

change_theme:
	icp canister call $(CANISTER_NAME) setTheme '("#1E3A8A", "#3B82F6")' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --output candid

check_protect_routes:
	icp canister call $(CANISTER_NAME) listProtectedRoutesSummary '()' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --query --output candid

collection_name_update:
	icp canister call $(CANISTER_NAME) setCollectionName '("Luandi")' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --output candid

button_create:
	icp canister call $(CANISTER_NAME) addButton '("Instagram", "https://www.instagram.com/collections_evorev/")' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --output candid

buttons_see_all:
	icp canister call $(CANISTER_NAME) getAllButtons '()' --environment $(ICP_ENVIRONMENT) --identity $(ICP_IDENTITY) --query --output candid
