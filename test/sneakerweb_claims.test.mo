import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Claims "../src/sneakerweb_claims";

let issuer = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
let domain = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

assert (Claims.isCardDomain(domain));
assert (not Claims.isCardDomain("ABCDEF" # domain));
assert (Claims.isPwaImportUrl("https://app.proof-of-meet.xyz/"));
assert (Claims.isPwaImportUrl("http://127.0.0.1:4173/"));
assert (not Claims.isPwaImportUrl("http://example.com/"));
assert (not Claims.isPwaImportUrl("https://example.com/#already-used"));
assert (Claims.isPrivateFileName("coat.snk"));
assert (not Claims.isPrivateFileName("/cards/coat.snk"));
assert (not Claims.isPrivateFileName("coat|token.snk"));
assert (Claims.itemIdFromNfcPath("nfc/item/42") == ?42);
assert (Claims.itemIdFromNfcPath("/nfc/item/42/") == ?42);
assert (Claims.itemIdFromNfcPath("item/42") == null);

let state = Claims.init();
let store = Claims.Store(state, issuer);
assert (not store.canIssue(7));
assert (store.setPwaImportUrl("https://app.proof-of-meet.xyz/"));
assert (store.configureCard(7, domain, "coat.snk"));
assert (store.canIssue(7));
assert (store.isPrivatePackageFile("coat.snk"));
assert (not store.isPrivatePackageFile("public-audio.m4a"));

let issuedAt = 1_000_000_000_000 : Int;
var token = "";
var claimId = "";
var packageToken = "";
var packageExpiresAt = 0 : Int;
switch (store.issueAt(7, "04958CAA5E5E80", 1, "8252B9CD8D6A36F9", issuedAt)) {
    case (#err(_)) { assert false };
    case (#ok(claim)) {
        token := claim.token;
        assert (token.size() == 64);
        assert (
            claim.redirect_url ==
            "https://app.proof-of-meet.xyz/#/claim/" # Principal.toText(issuer) # "/" # token
        );
        assert (claim.expires_at_ns == issuedAt + Claims.CLAIM_TTL_NS);
    };
};
assert (store.pendingCountAt(issuedAt) == 1);

switch (store.redeemAt(token, issuedAt + 1)) {
    case (#err(_)) { assert false };
    case (#ok(receipt)) {
        claimId := receipt.claim_id;
        assert (claimId.size() == 64);
        assert (receipt.issuer == Principal.toText(issuer));
        assert (receipt.item_id == 7);
        assert (receipt.domain == domain);
        assert (receipt.claimed_at_ns == issuedAt);
        packageToken := receipt.package_token;
        packageExpiresAt := receipt.package_expires_at_ns;
        assert (packageToken.size() == 64);
        assert (packageExpiresAt == issuedAt + 1 + Claims.PACKAGE_TTL_NS);
        // The receipt ID is not the bearer token that was consumed.
        assert (receipt.claim_id != token);
        assert (receipt.package_token != token);
        assert (receipt.package_token != receipt.claim_id);
    };
};
assert (store.packageGrantCountAt(issuedAt + 2) == 1);
switch (store.getPackageAt(packageToken, issuedAt + 2)) {
    case null { assert false };
    case (?grant) {
        assert (grant.file_name == "coat.snk");
        assert (grant.domain == domain);
        assert (grant.claim_id == claimId);
    };
};
assert (store.isPackageAuthorizedAt(packageToken, "coat.snk", issuedAt + 2));
assert (not store.isPackageAuthorizedAt(packageToken, "other.snk", issuedAt + 2));
assert (not store.isPackageAuthorizedAt(packageToken, "coat.snk", packageExpiresAt));

// The exact bearer token cannot be redeemed a second time.
switch (store.redeemAt(token, issuedAt + 2)) {
    case (#err(#invalid_or_expired)) {};
    case (#ok(_)) { assert false };
};
assert (store.pendingCountAt(issuedAt + 2) == 0);

// Expiration is enforced even when no cleanup call happened in between.
var expiredToken = "";
switch (store.issueAt(7, "04958CAA5E5E80", 2, "1111111111111111", issuedAt)) {
    case (#err(_)) { assert false };
    case (#ok(claim)) { expiredToken := claim.token };
};
switch (store.redeemAt(expiredToken, issuedAt + Claims.CLAIM_TTL_NS)) {
    case (#err(#invalid_or_expired)) {};
    case (#ok(_)) { assert false };
};

// Reconfiguring a card replaces the old mapping and removing it clears claims.
assert (store.configureCard(7, "f" # Text.trimStart(domain, #char '0'), "new.snk"));
switch (store.getCard(7)) {
    case null { assert false };
    case (?card) {
        assert (card.domain == ("f" # Text.trimStart(domain, #char '0')));
    };
};
assert (store.removeCard(7));
assert (not store.canIssue(7));
// Removing the mapping does not downgrade a still-stored package to public.
assert (store.isPrivatePackageFile("coat.snk"));
assert (store.isPrivatePackageFile("new.snk"));
assert (store.packageGrantCountAt(issuedAt + 2) == 0);
assert (not store.removeCard(7));
