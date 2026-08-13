import Array "mo:core/Array";
import Principal "mo:core/Principal";

import Store "../src/knitwork_store";
import Protocol "../src/knitwork_protocol";
import ProtectedRoutes "../src/nfc_protec_routes";

let firstHash = "7e5a8f651d633f11b0b13929954a579b60e2d0ab32d23b550cc90aa96bf44a28";
let validCmac = "8252B9CD8D6A36F9";
let uid0 = "04958CAA5E5E80";
let uid1 = "04AAAAAAAAAAAA";

let collectionPrincipal = Principal.fromText("aaaaa-aa");
let finalizerPrincipal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
let trustedHub = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
let otherCaller = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");
let handoffHash = "0000000000000000000000000000000000000000000000000000000000000000";

func bridge(
    routes : ProtectedRoutes.RoutesStorage,
    state : Store.State,
) : Store.Store {
    Store.Store(
        state,
        collectionPrincipal,
        func(itemId : Nat) : Bool { itemId <= 1 },
        func(scan : Store.PhysicalScanAttempt) : Bool {
            routes.validatePhysicalScan({
                path = scan.path;
                uid = scan.uid;
                counter = scan.counter;
                cmac = scan.cmac;
            });
        },
        func(scans : [Store.PhysicalScanAttempt]) : Bool {
            routes.commitPhysicalScans(
                Array.map<Store.PhysicalScanAttempt, ProtectedRoutes.PhysicalScanAttempt>(
                    scans,
                    func(scan) {
                        {
                            path = scan.path;
                            uid = scan.uid;
                            counter = scan.counter;
                            cmac = scan.cmac;
                        };
                    },
                )
            );
        },
    );
};

func event(meetingId : Text, localItemIds : [Nat]) : Protocol.MeetingEvent {
    var participants : [Protocol.ObjectRef] = [];
    for (itemId in localItemIds.vals()) {
        participants := Array.concat(
            participants,
            [{ collection = collectionPrincipal; item_id = itemId }],
        );
    };
    participants := Array.concat(
        participants,
        [{ collection = finalizerPrincipal; item_id = 99 }],
    );
    {
        meeting_id = meetingId;
        participants;
        reader_id = "reader-1";
        location = "lieu_1";
        first_scan_at_ns = 1_000_000_000;
        last_scan_at_ns = 2_000_000_000;
        confirmed_at_ns = 3_000_000_000;
    };
};

func scan(scanId : Text, itemId : Nat, uid : Text, cmac : Text) : Protocol.ScanProof {
    {
        scan_id = scanId;
        item_id = itemId;
        uid;
        counter = 1;
        proof = cmac;
        observed_at_ns = 1_500_000_000;
    };
};

func request(meetingId : Text, scans : [Protocol.ScanProof], localItemIds : [Nat]) : Protocol.PrepareMeetingRequest {
    {
        event = event(meetingId, localItemIds);
        scans;
        expected_finalizer = finalizerPrincipal;
        handoff_hash = handoffHash;
    };
};

func routeCounter(
    routes : ProtectedRoutes.RoutesStorage,
    path : Text,
    uid : Text,
) : Nat {
    switch (routes.getRoute(path)) {
        case null { 999 };
        case (?route) {
            for ((tagUid, tag) in route.tags.vals()) {
                if (tagUid == uid) return tag.scan_count_;
            };
            999;
        };
    };
};

// One valid physical scan is consumed inside the existing prepare call.
let routes = ProtectedRoutes.RoutesStorage({ var protected_routes = [] });
assert (routes.addProtectedRoute("nfc/item/0"));
assert (routes.updateRouteCmacs("nfc/item/0", uid0, [firstHash]));
let state = Store.init();
let store = bridge(routes, state);
store.setTrustedHub(?trustedHub);
let firstRequest = request("physical-meeting-1", [scan("physical-scan-1", 0, uid0, validCmac)], [0]);

// The caller Principal is enforced before NFC state is touched.
switch (store.prepareMeeting(otherCaller, firstRequest)) {
    case (#err(_)) {};
    case (#ok(_)) { assert false };
};
assert (routeCounter(routes, "nfc/item/0", uid0) == 0);

switch (store.prepareMeeting(trustedHub, firstRequest)) {
    case (#ok(receipt)) {
        assert (receipt.meeting_id == "physical-meeting-1");
        assert (receipt.objects.size() == 1);
    };
    case (#err(_)) { assert false };
};
assert (routeCounter(routes, "nfc/item/0", uid0) == 1);

// Exact retry returns the durable receipt without attempting to consume the
// already committed NTAG counter a second time.
switch (store.prepareMeeting(trustedHub, firstRequest)) {
    case (#ok(receipt)) { assert (receipt.meeting_id == "physical-meeting-1") };
    case (#err(_)) { assert false };
};
assert (routeCounter(routes, "nfc/item/0", uid0) == 1);

// scan_id is globally bound to the original meeting; a new scan_id cannot
// replay the same/lower physical counter either.
switch (
    store.prepareMeeting(
        trustedHub,
        request("physical-meeting-2", [scan("physical-scan-1", 0, uid0, validCmac)], [0]),
    )
) {
    case (#err(_)) {};
    case (#ok(_)) { assert false };
};
switch (
    store.prepareMeeting(
        trustedHub,
        request("physical-meeting-3", [scan("physical-scan-2", 0, uid0, validCmac)], [0]),
    )
) {
    case (#err(_)) {};
    case (#ok(_)) { assert false };
};

// An invalid member rejects the complete local batch, leaving the valid
// member's counter untouched. The canonical route is derived from item_id.
let atomicRoutes = ProtectedRoutes.RoutesStorage({ var protected_routes = [] });
assert (atomicRoutes.addProtectedRoute("nfc/item/0"));
assert (atomicRoutes.addProtectedRoute("nfc/item/1"));
assert (atomicRoutes.updateRouteCmacs("nfc/item/0", uid0, [firstHash]));
assert (atomicRoutes.updateRouteCmacs("nfc/item/1", uid1, [firstHash]));
let atomicState = Store.init();
let atomicStore = bridge(atomicRoutes, atomicState);
atomicStore.setTrustedHub(?trustedHub);
let invalidBatch = request(
    "physical-meeting-batch",
    [
        scan("physical-batch-0", 0, uid0, validCmac),
        scan("physical-batch-1", 1, uid1, "0000000000000000"),
    ],
    [0, 1],
);
switch (atomicStore.prepareMeeting(trustedHub, invalidBatch)) {
    case (#err(_)) {};
    case (#ok(_)) { assert false };
};
assert (routeCounter(atomicRoutes, "nfc/item/0", uid0) == 0);

// The same physical validation path is used when this Collection is the
// finalizer (including the one-call, single-Collection Stitch case).
let finalizerRoutes = ProtectedRoutes.RoutesStorage({ var protected_routes = [] });
assert (finalizerRoutes.addProtectedRoute("nfc/item/0"));
assert (finalizerRoutes.addProtectedRoute("nfc/item/1"));
assert (finalizerRoutes.updateRouteCmacs("nfc/item/0", uid0, [firstHash]));
assert (finalizerRoutes.updateRouteCmacs("nfc/item/1", uid1, [firstHash]));
let finalizerState = Store.init();
let finalizerStore = bridge(finalizerRoutes, finalizerState);
finalizerStore.setTrustedHub(?trustedHub);
let localEvent : Protocol.MeetingEvent = {
    meeting_id = "physical-local-finalizer";
    participants = [
        { collection = collectionPrincipal; item_id = 0 },
        { collection = collectionPrincipal; item_id = 1 },
    ];
    reader_id = "reader-1";
    location = "lieu_1";
    first_scan_at_ns = 1_000_000_000;
    last_scan_at_ns = 2_000_000_000;
    confirmed_at_ns = 3_000_000_000;
};
let finalizerRequest : Protocol.FinalizeMeetingRequest = {
    event = localEvent;
    scans = [
        scan("physical-finalizer-0", 0, uid0, validCmac),
        scan("physical-finalizer-1", 1, uid1, validCmac),
    ];
    prepared_peers = [];
};
switch (finalizerStore.beginFinalize(trustedHub, finalizerRequest)) {
    case (#ok(record)) { assert (record.status == #pending) };
    case (#err(_)) { assert false };
};
assert (routeCounter(finalizerRoutes, "nfc/item/0", uid0) == 1);
assert (routeCounter(finalizerRoutes, "nfc/item/1", uid1) == 1);
switch (finalizerStore.beginFinalize(trustedHub, finalizerRequest)) {
    case (#ok(record)) { assert (record.status == #pending) };
    case (#err(_)) { assert false };
};
assert (routeCounter(finalizerRoutes, "nfc/item/0", uid0) == 1);
assert (routeCounter(atomicRoutes, "nfc/item/1", uid1) == 0);

// item_id is not trusted as a routing hint: moving a valid UID/CMAC to the
// other Item derives the other route and fails that route's UID binding.
switch (
    atomicStore.prepareMeeting(
        trustedHub,
        request(
            "physical-meeting-wrong-item",
            [scan("physical-wrong-item", 1, uid0, validCmac)],
            [1],
        ),
    )
) {
    case (#err(_)) {};
    case (#ok(_)) { assert false };
};
assert (routeCounter(atomicRoutes, "nfc/item/0", uid0) == 0);

// One physical UID cannot stand for two different local objects in a batch.
let duplicateUidBatch = request(
    "physical-meeting-duplicate-uid",
    [
        scan("physical-duplicate-0", 0, uid0, validCmac),
        scan("physical-duplicate-1", 1, uid0, validCmac),
    ],
    [0, 1],
);
switch (atomicStore.prepareMeeting(trustedHub, duplicateUidBatch)) {
    case (#err(_)) {};
    case (#ok(_)) { assert false };
};
assert (routeCounter(atomicRoutes, "nfc/item/0", uid0) == 0);
