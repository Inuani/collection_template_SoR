import Principal "mo:core/Principal";

import AccessControl "../src/access_control";
import Collection "../src/collection";

let initializer = Principal.fromText("aaaaa-aa");
let anotherCaller = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
let anonymous = Principal.fromText("2vxsx-fae");

// Every admin-only query/update uses this same policy: the installing identity
// succeeds, while an anonymous ingress and any other Principal are rejected.
assert (AccessControl.isInitializer(initializer, initializer));
assert (not AccessControl.isInitializer(anotherCaller, initializer));
assert (not AccessControl.isInitializer(anonymous, initializer));

assert (Collection.deletionBlockReason(7, false, false) == null);
assert (
    Collection.deletionBlockReason(7, true, false) ==
    ?"Item with ID 7 cannot be deleted while its NFC route is registered"
);
assert (
    Collection.deletionBlockReason(7, false, true) ==
    ?"Item with ID 7 cannot be deleted because it has Stitch history"
);
