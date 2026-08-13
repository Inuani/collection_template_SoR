# Luandi System Architecture — vision produit historique

> Cette page décrit une vision produit plus large (Discord, marketplace,
> guardianship). L'architecture technique actuellement implémentée pour les
> Stitchs est documentée dans
> [`NFC_WORKFLOW.md`](NFC_WORKFLOW.md).
> Les Collections ne coordonnent plus de sessions de Stitching : le Hub
> authentifie le reader et orchestre les écritures `MeetingRecord` dans chaque
> Collection concernée.

## 1. High-Level Concept: "The Discord Centric Model"

While **Discord** is the primary interface for the *Humans*, a minimal **Web Frontend** is strictly necessary for the *Machines*.

### Why do we need a Web Frontend?
*   **Physics:** When a phone scans an NFC chip, it opens a URL in a browser. It cannot "open Discord directly" and execute a script.
*   **The Bridge:** The Web Frontend receives the scan parameters (UID, CMAC), validates them with the Canister, and then *redirects* the user to the appropriate Discord action or displays the success message.
*   **Conclusion:** The Web Frontend is the invisible "glue" that translates physical taps into Discord events.

---

## 2. Component Diagram

```mermaid
graph TD
    User[Guardian] -->|Scans| NFC[NTAG424 Chip]
    NFC -->|Opens URL| Web[Minimal Web Frontend]
    Web -->|Verifies CMAC| Canister[ICP Canister]
    
    subgraph "The Cloud"
        Web -->|Redirects to| Discord[Discord Client]
        Bot[Luandi Bot] -->|Listens to| Canister
        Bot -->|Posts to| Discord
    end
    
    subgraph "The Physical World"
        Station[Luandi Station Reader] -->|Witness Scan| Web
    end
```

---

## 3. Detailed Component Specs

### A. The "Soul" (ICP Canister)
*   **Role:** A Knitwork Hub coordinates trusted scans; each Collection remains
    authoritative for its own tags, items and local Stitch history.
*   **State:**
    *   Hub: authenticated readers (including their free-text location),
        authorized Collections, sessions and coordination records.
    *   Collection: tag bindings/counters, items and indexed `MeetingRecord`s.
*   **API:**
    *   Hub: scan/session submission, registry and retry orchestration.
    *   Collection: `prepare_meeting`, `finalize_meeting`, `confirm_meeting`,
        `get_item_meetings`.
    *   A physical NTAG scan uses the existing `ScanProof`: `proof` contains
        the raw SDM CMAC. The Collection derives `nfc/item/<item_id>` and, in
        the same `prepare_meeting` or `finalize_meeting` call, verifies the
        registered UID, CMAC and monotonic counter. There is deliberately no
        extra inter-canister validation call.
    *   The reader location is copied into every meeting; there is no separate
        `shop_id` in the Stitch V1 contract.
*   **Failure semantics:** a Collection validates its complete local batch
    before advancing any local tag counter. A prepared Collection must durably
    reserve its valid counters before the finalizer is called; this is the
    unavoidable boundary of the 1/3/5-call protocol. If a later Collection is
    temporarily unavailable, no partial Stitch is confirmed: the Hub keeps the
    meeting in `pending_sync` and retries the exact same idempotent request.
    Avoiding even that pending counter reservation would require an additional
    commit/abort phase and therefore more inter-canister calls.

### B. The "Voice" (Discord Bot)
*   **Role:** The Town Crier & Notification System.
*   **Stack:** Python (`discord.py`) or JS (`discord.js`).
*   **Responsibilities:**
    1.  **Poll/Listen:** Watches the Canister for "Public Events" (Transfers, Drops).
    2.  **Broadcast:** Posts rich embed cards to `#marketplace-feed` or `#community-news`.
    3.  **DM Machinery:** Handles private confirmations. "Are you sure you want to sell Hoodie #88?"
*   **User Mapping:** Maps `Discord_ID` <-> `Canister_Principal` (if needed, or just stores Discord ID as string in Canister).

### C. The "Bridge" (Minimal Web Frontend)
*   **Role:** The URL handler for NFC taps.
*   **Stack:** Next.js (hosted on Vercel or ICP Asset Canister).
*   **Pages:**
    *   `/scan/[uid]`: The entry point.
        *   Logic: Validate URL params -> Call Canister -> If valid, show "Profile/Action Card".
    *   `/claim/[token]`: The page shown to a Buyer after a sale.
        *   button: "Login with Discord" (OAUTH).
        *   action: Link Item to Discord User.
    *   `/station/witness`: The interface for the Shopkeeper's tablet/screen.

### D. The "Anchor" (Luandi Station)
*   **Role:** The trusted hardware at the shop.
*   **Stack:** Raspberry Pi + PN532 Reader + Python Script.
*   **Behavior:**
    *   Loops waiting for a tag.
    *   When it detects a **User Tag** (Hoodie), it sends the UID to the Frontend API.
    *   When it detects a **Master Tag** (Witness Artefact), it signs a "Witness Proof" and sends it.

---

## 4. Data Flow: "The Sale"

1.  **Drop-Off (Physical):**
    *   Shopkeeper taps `Shop_Master_Tag` on Station.
    *   Seller taps `Hoodie_Tag` on Station.
    *   *Station* sends `{witness_proof, hoodie_uid}` to *Frontend*.
    *   *Frontend* calls *Canister* `register_consignment()`.
2.  **Notification (Digital):**
    *   *Bot* sees new consignment.
    *   *Bot* posts to `#sanctuary-inventory`: "**New Drop at Galaxy Shop!** Hoodie #88 - 50 CHF".
3.  **Pickup (Physical):**
    *   Buyer pays Shop.
    *   Shopkeeper taps `Shop_Master_Tag`.
    *   Buyer taps `Hoodie_Tag`.
    *   *Station* sends `{witness_proof, hoodie_uid, release=true}` to *Frontend*.
    *   *Frontend* generates a QR code on the Station Screen.
4.  **Claim (Digital):**
    *   Buyer scans QR Code with phone.
    *   Opens `luandi.io/claim/...`
    *   Buyer logs in with Discord.
    *   *Canister* updates: `Guardian = Buyer_Discord_ID`.
