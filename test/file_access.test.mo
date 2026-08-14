import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";

import FileAccess "../src/file_access";

func secret(offset : Nat) : Blob {
    Blob.fromArray(
        Array.tabulate<Nat8>(
            FileAccess.SECRET_SIZE,
            func(index : Nat) : Nat8 { Nat8.fromNat((index + offset) % 256) },
        )
    );
};

let state = FileAccess.init();
let access = FileAccess.Access(state);
let now = 1_000_000_000_000 : Int;

// A fresh or upgraded canister fails closed until the installer provisions a
// random secret. Secrets of any other size are rejected.
assert (not access.isConfigured());
assert (access.generateTokenAt("card.snk", now) == null);
assert (not access.validateTokenAt("1.deadbeef", "card.snk", now));
assert (not access.installSecret(Blob.fromArray([1, 2, 3])));
assert (access.installSecret(secret(0)));
assert (access.isConfigured());

let token = switch (access.generateTokenAt("card.snk", now)) {
    case null { assert false; "" };
    case (?value) value;
};

assert (access.validateTokenAt(token, "card.snk", now));
assert (not access.validateTokenAt(token, "another.snk", now));
assert (not access.validateTokenAt(token # "0", "card.snk", now));
assert (
    access.validateTokenAt(
        token,
        "card.snk",
        now + FileAccess.TOKEN_DURATION_NS - 1,
    )
);
assert (
    not access.validateTokenAt(
        token,
        "card.snk",
        now + FileAccess.TOKEN_DURATION_NS,
    )
);
assert (
    not access.validateTokenAt(
        token,
        "card.snk",
        now - FileAccess.MAX_FUTURE_SKEW_NS - 1,
    )
);

// Rotating the canister-owned secret immediately invalidates old links.
assert (access.installSecret(secret(1)));
assert (not access.validateTokenAt(token, "card.snk", now));
