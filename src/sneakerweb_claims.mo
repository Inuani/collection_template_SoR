import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Int "mo:core/Int";
import Iter "mo:core/Iter";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Sha256 "mo:sha2/Sha256";
import Text "mo:core/Text";
import Time "mo:core/Time";

module {
    // A claim only bridges the NFC update call and the PWA import. It is not a
    // user identity and it is deliberately too short-lived to become one.
    public let CLAIM_TTL_NS : Int = 120_000_000_000;
    public let PACKAGE_TTL_NS : Int = 600_000_000_000;

    public type CardConfig = {
        item_id : Nat;
        domain : Text;
        file_name : Text;
    };

    public type PendingClaim = {
        token : Text;
        claim_id : Text;
        item_id : Nat;
        domain : Text;
        file_name : Text;
        issued_at_ns : Int;
        expires_at_ns : Int;
    };

    public type PackageGrant = {
        token : Text;
        claim_id : Text;
        item_id : Nat;
        domain : Text;
        file_name : Text;
        issued_at_ns : Int;
        expires_at_ns : Int;
    };

    public type Receipt = {
        claim_id : Text;
        issuer : Text;
        item_id : Nat;
        domain : Text;
        claimed_at_ns : Int;
        package_token : Text;
        package_expires_at_ns : Int;
    };

    public type IssuedClaim = {
        token : Text;
        redirect_url : Text;
        expires_at_ns : Int;
    };

    public type IssueError = {
        #card_not_configured;
        #pwa_not_configured;
    };

    public type RedeemError = {
        #invalid_or_expired;
    };

    public type State = {
        var pwa_import_url : Text;
        var cards : [(Nat, CardConfig)];
        // Keep every filename ever configured as a private package. Removing a
        // card must not accidentally expose its still-uploaded file through a
        // legacy streaming route.
        var private_file_names : [Text];
        var pending_claims : [(Text, PendingClaim)];
        var package_grants : [(Text, PackageGrant)];
        var nonce : Nat;
    };

    public func init() : State = {
        var pwa_import_url = "";
        var cards = [];
        var private_file_names = [];
        var pending_claims = [];
        var package_grants = [];
        var nonce = 0;
    };

    let hexCharacters : [Char] = [
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
    ];

    func bytesToHex(bytes : [Nat8]) : Text {
        var characters : [Char] = [];
        for (byte in bytes.vals()) {
            let value = Nat8.toNat(byte);
            characters := Array.concat(
                characters,
                [hexCharacters[value / 16], hexCharacters[value % 16]],
            );
        };
        Text.fromArray(characters);
    };

    func hashText(value : Text) : Text {
        bytesToHex(
            Blob.toArray(
                Sha256.fromBlob(#sha256, Text.encodeUtf8(value))
            )
        );
    };

    func isLowerHexCharacter(character : Char) : Bool {
        (character >= '0' and character <= '9') or
        (character >= 'a' and character <= 'f');
    };

    public func isCardDomain(value : Text) : Bool {
        let characters = Text.toArray(value);
        if (characters.size() != 64) return false;
        for (character in characters.vals()) {
            if (not isLowerHexCharacter(character)) return false;
        };
        true;
    };

    func isLocalHttpUrl(value : Text) : Bool {
        Text.startsWith(value, #text "http://localhost:") or
        Text.startsWith(value, #text "http://127.0.0.1:") or
        Text.startsWith(value, #text "http://[::1]:");
    };

    public func isPwaImportUrl(value : Text) : Bool {
        value != "" and
        not Text.contains(value, #char '#') and
        (Text.startsWith(value, #text "https://") or isLocalHttpUrl(value));
    };

    public func isPrivateFileName(value : Text) : Bool {
        let characters = Text.toArray(value);
        if (characters.size() == 0 or characters.size() > 160) return false;
        for (character in characters.vals()) {
            let allowed =
                (character >= 'a' and character <= 'z') or
                (character >= 'A' and character <= 'Z') or
                Char.isDigit(character) or
                character == '.' or character == '_' or character == '~' or character == '-';
            if (not allowed) return false;
        };
        true;
    };

    public func itemIdFromNfcPath(path : Text) : ?Nat {
        let canonical = Text.trim(path, #char '/');
        let segments = Iter.toArray(Text.split(canonical, #char '/'));
        if (segments.size() != 3 or segments[0] != "nfc" or segments[1] != "item") {
            return null;
        };
        Nat.fromText(segments[2]);
    };

    public class Store(state : State, canisterId : Principal) {
        let issuer = Principal.toText(canisterId);

        func updateCard(config : CardConfig) {
            let withoutItem = Array.filter<(Nat, CardConfig)>(
                state.cards,
                func((itemId, _)) { itemId != config.item_id },
            );
            state.cards := Array.concat(withoutItem, [(config.item_id, config)]);
        };

        func rememberPrivateFile(fileName : Text) {
            for (configuredFileName in state.private_file_names.vals()) {
                if (configuredFileName == fileName) return;
            };
            state.private_file_names := Array.concat(state.private_file_names, [fileName]);
        };

        func removeExpired(now : Int) {
            state.pending_claims := Array.filter<(Text, PendingClaim)>(
                state.pending_claims,
                func((_, claim)) { claim.expires_at_ns > now },
            );
            state.package_grants := Array.filter<(Text, PackageGrant)>(
                state.package_grants,
                func((_, grant)) { grant.expires_at_ns > now },
            );
        };

        public func setPwaImportUrl(url : Text) : Bool {
            if (not isPwaImportUrl(url)) return false;
            state.pwa_import_url := url;
            true;
        };

        public func getPwaImportUrl() : Text {
            state.pwa_import_url;
        };

        public func configureCard(itemId : Nat, domain : Text, fileName : Text) : Bool {
            if (not isCardDomain(domain) or not isPrivateFileName(fileName)) return false;
            rememberPrivateFile(fileName);
            updateCard({ item_id = itemId; domain; file_name = fileName });
            true;
        };

        public func isPrivatePackageFile(fileName : Text) : Bool {
            switch (
                Array.find<Text>(
                    state.private_file_names,
                    func(configuredFileName) { configuredFileName == fileName },
                )
            ) {
                case (?_) true;
                case null false;
            };
        };

        public func removeCard(itemId : Nat) : Bool {
            let previousSize = state.cards.size();
            state.cards := Array.filter<(Nat, CardConfig)>(
                state.cards,
                func((configuredItemId, _)) { configuredItemId != itemId },
            );
            state.pending_claims := Array.filter<(Text, PendingClaim)>(
                state.pending_claims,
                func((_, claim)) { claim.item_id != itemId },
            );
            state.package_grants := Array.filter<(Text, PackageGrant)>(
                state.package_grants,
                func((_, grant)) { grant.item_id != itemId },
            );
            previousSize != state.cards.size();
        };

        public func getCard(itemId : Nat) : ?CardConfig {
            for ((configuredItemId, config) in state.cards.vals()) {
                if (configuredItemId == itemId) return ?config;
            };
            null;
        };

        public func listCards() : [CardConfig] {
            Array.map<(Nat, CardConfig), CardConfig>(state.cards, func((_, card)) { card });
        };

        public func canIssue(itemId : Nat) : Bool {
            state.pwa_import_url != "" and getCard(itemId) != null;
        };

        public func issueAt(
            itemId : Nat,
            uid : Text,
            counter : Nat,
            cmac : Text,
            now : Int,
        ) : { #ok : IssuedClaim; #err : IssueError } {
            let card = switch (getCard(itemId)) {
                case (?configured) configured;
                case null return #err(#card_not_configured);
            };
            if (state.pwa_import_url == "") return #err(#pwa_not_configured);

            removeExpired(now);
            state.nonce += 1;
            let token = hashText(
                "sneakerweb-nfc-claim-v1|" # issuer # "|" #
                Nat.toText(itemId) # "|" # uid # "|" # Nat.toText(counter) # "|" #
                cmac # "|" # Int.toText(now) # "|" # Nat.toText(state.nonce)
            );
            let claim : PendingClaim = {
                token;
                claim_id = hashText("sneakerweb-nfc-receipt-v1|" # token);
                item_id = itemId;
                domain = card.domain;
                file_name = card.file_name;
                issued_at_ns = now;
                expires_at_ns = now + CLAIM_TTL_NS;
            };
            state.pending_claims := Array.concat(state.pending_claims, [(token, claim)]);
            #ok({
                token;
                redirect_url = state.pwa_import_url # "#/claim/" # issuer # "/" # token;
                expires_at_ns = claim.expires_at_ns;
            });
        };

        public func issue(
            itemId : Nat,
            uid : Text,
            counter : Nat,
            cmac : Text,
        ) : { #ok : IssuedClaim; #err : IssueError } {
            issueAt(itemId, uid, counter, cmac, Time.now());
        };

        public func redeemAt(
            token : Text,
            now : Int,
        ) : { #ok : Receipt; #err : RedeemError } {
            removeExpired(now);
            let claim = switch (
                Array.find<(Text, PendingClaim)>(
                    state.pending_claims,
                    func((candidate, _)) { candidate == token },
                )
            ) {
                case (?(_, pending)) pending;
                case null return #err(#invalid_or_expired);
            };

            // Consume before returning. There is no await in this method, so a
            // second update cannot interleave and redeem the same claim.
            state.pending_claims := Array.filter<(Text, PendingClaim)>(
                state.pending_claims,
                func((candidate, _)) { candidate != token },
            );
            state.nonce += 1;
            let packageToken = hashText(
                "sneakerweb-private-package-v1|" # issuer # "|" # token # "|" #
                Int.toText(now) # "|" # Nat.toText(state.nonce)
            );
            let packageGrant : PackageGrant = {
                token = packageToken;
                claim_id = claim.claim_id;
                item_id = claim.item_id;
                domain = claim.domain;
                file_name = claim.file_name;
                issued_at_ns = now;
                expires_at_ns = now + PACKAGE_TTL_NS;
            };
            state.package_grants := Array.concat(
                state.package_grants,
                [(packageToken, packageGrant)],
            );
            #ok({
                claim_id = claim.claim_id;
                issuer;
                item_id = claim.item_id;
                domain = claim.domain;
                claimed_at_ns = claim.issued_at_ns;
                package_token = packageToken;
                package_expires_at_ns = packageGrant.expires_at_ns;
            });
        };

        public func redeem(token : Text) : { #ok : Receipt; #err : RedeemError } {
            redeemAt(token, Time.now());
        };

        public func getPackageAt(token : Text, now : Int) : ?PackageGrant {
            removeExpired(now);
            switch (
                Array.find<(Text, PackageGrant)>(
                    state.package_grants,
                    func((candidate, _)) { candidate == token },
                )
            ) {
                case (?(_, grant)) ?grant;
                case null null;
            };
        };

        public func getPackage(token : Text) : ?PackageGrant {
            getPackageAt(token, Time.now());
        };

        // Streaming callbacks are query calls and cannot clean expired state,
        // so this check is deliberately pure. Expired grants are still denied.
        public func isPackageAuthorizedAt(
            token : Text,
            fileName : Text,
            now : Int,
        ) : Bool {
            switch (
                Array.find<(Text, PackageGrant)>(
                    state.package_grants,
                    func((candidate, grant)) {
                        candidate == token and
                        grant.file_name == fileName and
                        grant.expires_at_ns > now;
                    },
                )
            ) {
                case (?_) true;
                case null false;
            };
        };

        public func isPackageAuthorized(token : Text, fileName : Text) : Bool {
            isPackageAuthorizedAt(token, fileName, Time.now());
        };

        public func pendingCountAt(now : Int) : Nat {
            removeExpired(now);
            state.pending_claims.size();
        };

        public func packageGrantCountAt(now : Int) : Nat {
            removeExpired(now);
            state.package_grants.size();
        };
    };
};
