import Scan "../src/utils/scan";
import ProtectedRoutes "../src/nfc_protec_routes";

assert (Scan.asciiCounterToNat("000001") == ?1);
assert (Scan.asciiCounterToNat("000100") == ?256);
assert (Scan.asciiCounterToNat("FFFFFF") == ?16_777_215);
assert (Scan.asciiCounterToNat("0001") == null);
assert (Scan.asciiCounterToNat("ZZ0000") == null);

let firstHash = "7e5a8f651d633f11b0b13929954a579b60e2d0ab32d23b550cc90aa96bf44a28";
let firstUrl = "/item/0?uid=04958CAA5E5E80&ctr=000001&cmac=8252B9CD8D6A36F9&item_id=0";

// The final available proof is valid; the previous implementation rejected it
// because it compared the counter with the table size using >=.
assert (Scan.scan([firstHash], firstUrl, 0) == 1);
assert (Scan.scan([firstHash], firstUrl, 1) == 0);

// Query argument ordering does not affect validation.
assert (
    Scan.scan(
        [firstHash],
        "/item/0?item_id=0&cmac=8252B9CD8D6A36F9&uid=04958CAA5E5E80&ctr=000001",
        0,
    ) == 1
);

assert (Scan.getUid(firstUrl) == ?"04958CAA5E5E80");
assert (Scan.isFixedHex("04958CAA5E5E80", 14));
assert (not Scan.isFixedHex("04958CAA5E5E8Z", 14));
assert (Scan.validateCmac([firstHash], "8252B9CD8D6A36F9", 1, 0));
assert (not Scan.validateCmac([firstHash], "8252B9CD8D6A36F9", 1, 1));
assert (not Scan.validateCmac([firstHash], "not-a-cmac", 1, 0));

let routes = ProtectedRoutes.RoutesStorage({ var protected_routes = [] });
assert (routes.addProtectedRoute("nfc/item/0"));
assert (ProtectedRoutes.canonicalRoutePath(" /nfc/item/0/ ") == ?"nfc/item/0");
assert (ProtectedRoutes.canonicalRoutePath("nfc//item/0") == null);
assert (ProtectedRoutes.canonicalRoutePath("nfc/item/../0") == null);
assert (ProtectedRoutes.canonicalRoutePath("nfc/item/0?uid=X") == null);
assert (ProtectedRoutes.canonicalRoutePath("nfc/itém/0") == null);
assert (ProtectedRoutes.itemRoute(0) == "nfc/item/0");
assert (not routes.addProtectedRoute("/nfc/item/0/"));
assert (routes.hasProtectedRoute("/nfc/item/0/"));
assert (routes.isProtectedRoute("/nfc/item/0?uid=X"));
assert (routes.isProtectedRoute("/nfc/item/0/?uid=X"));
assert (not routes.isProtectedRoute("/item/0"));
assert (not routes.isProtectedRoute("/nfc/item/00?uid=X"));
assert (not routes.isProtectedRoute("/prefix/nfc/item/0?uid=X"));

assert (routes.updateRouteCmacs("nfc/item/0", "04958CAA5E5E80", [firstHash]));
assert (routes.getRouteCmacs("/nfc/item/0/", "04958CAA5E5E80") == [firstHash]);
let physicalScan : ProtectedRoutes.PhysicalScanAttempt = {
    path = "nfc/item/0";
    uid = "04958CAA5E5E80";
    counter = 1;
    cmac = "8252B9CD8D6A36F9";
};
assert (routes.validatePhysicalScan(physicalScan));

let equivalentPathScan : ProtectedRoutes.PhysicalScanAttempt = {
    path = "/nfc/item/0/";
    uid = physicalScan.uid;
    counter = physicalScan.counter;
    cmac = physicalScan.cmac;
};
// Canonical aliases cannot submit the same physical tag twice in one batch.
assert (not routes.commitPhysicalScans([physicalScan, equivalentPathScan]));
assert (routes.validatePhysicalScan(physicalScan));

// Validation is pure; only the explicit batch commit consumes the counter.
assert (routes.validatePhysicalScan(physicalScan));
assert (routes.commitPhysicalScans([physicalScan]));
assert (not routes.validatePhysicalScan(physicalScan));

// A rejected batch performs no partial counter update.
let atomicRoutes = ProtectedRoutes.RoutesStorage({ var protected_routes = [] });
assert (atomicRoutes.addProtectedRoute("nfc/item/0"));
assert (atomicRoutes.addProtectedRoute("nfc/item/1"));
assert (atomicRoutes.updateRouteCmacs("nfc/item/0", "04958CAA5E5E80", [firstHash]));
assert (atomicRoutes.updateRouteCmacs("nfc/item/1", "04AAAAAAAAAAAA", [firstHash]));
let otherPhysicalScan : ProtectedRoutes.PhysicalScanAttempt = {
    path = "nfc/item/1";
    uid = "04AAAAAAAAAAAA";
    counter = 1;
    cmac = "0000000000000000";
};
assert (not atomicRoutes.commitPhysicalScans([physicalScan, otherPhysicalScan]));
assert (atomicRoutes.validatePhysicalScan(physicalScan));
