# Les Collections d'Evorev: A Marketplace for Autonomous Artifacts

## 1. Core Vision: A Web of Trust for Objects (WoT) & Social Network

"Les Collections d'Evorev" is a dual-layered system:
1.  **Structure:** A **Web of Trust (WoT)** where trust is transitive (Shops vouch for items, items vouch for meetings).
2.  **Experience:** A **Social Network for Objects** built on top of that trust, where interactions create a public history.

### The Philosophy
*   **Object-First Identity:** The primary "User" of the platform is the **Garment** (e.g., Hoodie #88), not the human owner.
*   **Guardians vs. Owners:** Humans are temporary **Guardians** who carry the object for a chapter of its life.
*   **The "CV" of the Cloth:** Value is derived from the object's history (where it has been, who it has met, what events it attended), not just its physical condition.
*   **Physical Authenticity:** All digital interactions are anchored by **NFC Scans** at specific physical locations.

### The Physical Tether (Constraint)
A crucial rule of the system is that **Digital Ownership cannot be transferred remotely.**
*   If Alice gives Bob a hoodie in a park, Bob has the *fabric*, but Alice remains the *Guardian*.
*   To transfer the "Soul" (Digital Guardian rights), they **MUST** visit a Sanctuary (Shop) and scan it on a Witness Reader.
*   **Why?** This enforces the business model (fees are paid at the shop) and ensures the history is verified by a trusted location.

### Where is the Network Visible?
The "Social Network" is not a single feed like Facebook. It is visible in two places:
1.  **The Object's Profile (The "CV"):**
    *   Every time an object is scanned, its public profile page (`luandi.io/item/88`) updates.
    *   **The Feed:** This page lists the "Life Events": *"Stitched with Cap #42"*, *"Witnessed at Galaxy Bar"*, *"Transferred to new Guardian"*. This chronological list *is* the social feed of the object.
2.  **The Community Pulse (Discord):**
    *   The Discord server acts as the "Town Square."
    *   A bot broadcasts major events "Trust Events" (invisible blockchain actions made visible).
    *   **The Broadcasts:**
        *   *📍 "The Wanderer": Hoodie #88 just checked in at Galaxy Bar!* (Proof of Location)
        *   *🧵 "The Bond": Cap #42 stitched with T-Shirt #10.* (Stitch)
        *   *🤝 "The Pass": Hoodie #88 was adopted by a new Guardian.* (Proof of Transfer)
        *   *💎 " The Drop": New Artifact Consigned at The Sanctuary!* (Proof of Listing)
    *   This makes the invisible life of objects visible to the human community.

---

## 2. The Architecture: Hybrid Web2 + Web3

We use a hybrid approach to balance the permanent truth of the blockchain with the flexibility of modern social tools (Discord).

### A. The "Soul" (Web3 - ICP Canister)
*   **Role:** The Hub authenticates the reader and coordinates the operation;
    every participating Collection is the source of truth for its own object's
    copy of the confirmed meeting.
*   **Data Stored:** 
    *   Authenticity (NFC CMACs/Keys).
    *   `MeetingRecord` history (which globally identified objects met, at which
        reader location, and when).
    *   Current Guardian Link (Session-based or explicit).
*   **Function:** A Collection validates its own tag; the Hub then obtains a
    confirmed write in every Collection involved in the meeting.

### B. The "Voice" (Web2 - Discord + Minimal Frontend)
*   **The Interface:** No traditional login (email/password). Access is granted by **Scanning the Item**.
*   **The Marketplace Feed:** A Discord Bot posts updates when items change status to "For Sale."
*   **Communication:** Buyers and Sellers coordinate via Discord DMs, keeping the platform social and community-focused.

---

## 3. The Workflows: How Exchange Happens

We support two primary modes of exchange, both anchored by **Physical Witness Points** (readers located at trusted shops/bars).

### Mode A: The Handshake (Peer-to-Peer)
*Best for: Active Community Members meeting up.*

**Phase 1: The Meetup**
1.  **Agreement**: Seller and Buyer agree on Discord to meet at the Shop (a neutral ground).
2.  **The Verification**: They go to the Shop's Scanner.

**Phase 2: The Witness Event**
1.  **The Trio Scan**:
    *   Seller scans **Hoodie #88**.
    *   Shopkeeper (or Machine) provides the **Witness Scan** (Proving Location).
    *   Buyer scans **Nothing yet** (just observes).
2.  **The Exchange**:
    *   Buyer hands over cash/Twint to Seller.
    *   Seller clicks "Release to New Guardian" on the screen.

**Phase 3: The Claim**
1.  **The Claim Scan**:
    *   Buyer scans **Hoodie #88**.
    *   System links Hoodie to Buyer's session.
    *   **Result**: Transfer Complete. Hoodie history updates: *"Met a Witness at Shop X during transfer."*

### Mode B: The Sanctuary (Consignment)
*Best for: Passive Sellers who want the Shop to handle the sale.*

**Phase 1: The Drop-Off (Seller -> Shop)**
1.  **Arrival**: Seller brings the item (e.g., Hoodie #88) to the Shop.
2.  **The Intake Scan**: 
    *   Shopkeeper scans the **Shop Witness Artefact** on the Reader.
    *   Seller scans **Hoodie #88** on the Reader.
3.  **The Contract**: 
    *   System recognizes "Stitching with a Sanctuary Witness."
    *   Seller confirms: "Release Guardianship to Sanctuary."
    *   **Result**: The Shop becomes the Custodian. The Hoodie is digitally "locked" to the shop's location.
4.  **The Display**: 
    *   Physical: Hoodie hangs on the rack.
    *   Digital: Hoodie appears in the "Sanctuary Inventory" on Discord/Web. Status: *Waiting for Adopter*.

**Phase 2: The Adoption (Shop -> Buyer)**
1.  **Discovery**: Buyer walks in, sees the Hoodie physically or digitally.
2.  **The Transaction**: Buyer pays the Shop (Cash/Twint). Shop takes their cut (if any).
3.  **The Release Scan**:
    *   Shopkeeper scans **Shop Witness Artefact**.
    *   Buyer scans **Hoodie #88**.
4.  **The Bond**:
    *   System prompts: "Sanctuary Releasing Guardian Rights."
    *   Buyer accepts on their phone.
    *   **Result**: Buyer becomes the new Guardian. Hoodie history updates: *"Adopted from Sanctuary X."*

---

## 4. The "Stitching" Mechanic (Socializing)

The platform incentivizes meeting up *even without selling*.

*   **Meeting of Minds:** Two or three distinct objects can be scanned together,
    with less than ten seconds strictly between the first and last scan.
*   **Shared Proof:** The same `meeting_id`, full participant list and reader
    location are written in every participating Collection.
*   **Extensibility:** XP or venue reputation can later be derived from confirmed
    meetings; they are not part of the current V1 consensus record.

---

## 6. Business Model & Revenue
The platform sustains itself through a transparent markup system.

### The Pricing Breakdown
When an item is consigned to a "Sanctuary" (Shop), the final sale price is composed of three parts.

1.  **Seller Base Price (A):** The amount the Seller wants to receive (e.g., 50 CHF).
2.  **Sanctuary Markup (B):** The Shop's fee for hosting/witnessing (e.g., +10 CHF).
3.  **Evorev Platform Fee (C):** A fixed fee or % for the network/protocol (e.g., +5 CHF).

**Final Tag Price = A + B + C** (e.g., 65 CHF)

### The Flow of Funds
Since payment happens off-platform (Cash/Twint at the Shop):
1.  **Trust:** The Shop collects the full amount (65 CHF).
2.  **Settlement:**
    *   Shop pays Seller their share (50 CHF).
    *   Shop keeps their share (10 CHF).
    *   **Debt to Evorev:** The Shop "owes" Evorev 5 CHF. This is tracked by the Canister.
3.  **Invoice:** Periodically (e.g., monthly), Evorev invoices the Shop based on the recorded on-chain sales history.

---

## 7. Technical Stack Summary

*   **Hardware:** 
    *   **NTAG424 DNA Chips** (in garments).
    *   **Luandi Station** (Raspberry Pi/ESP32 + NFC Reader) for venues.
*   **Software:**
    *   **ICP Canister (Motoko):** Logic, Auth, History.
    *   **Discord Bot (Python/JS):** Notifications, Role Management.
    *   **Web App (Next.js):** Minimal interface for Profile View & "Claim" actions (accessed via NFC URL).
