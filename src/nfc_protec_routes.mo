import Text "mo:core/Text";
import Map "mo:core/Map";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Option "mo:core/Option";
import Char "mo:core/Char";
import Nat "mo:core/Nat";
import Scan "utils/scan";

module {

    public type TagData = {
        cmacs_ : [Text];
        scan_count_ : Nat;
    };

    public type ProtectedRoute = {
        path : Text;
        tags : [(Text, TagData)]; // Map of UID -> TagData
    };

    // Transient validation/commit value used by the Stitch protocol. It is
    // deliberately not part of State, so adding it does not change the stable
    // layout of already deployed Collections.
    public type PhysicalScanAttempt = {
        path : Text;
        uid : Text;
        counter : Nat;
        cmac : Text;
    };

    public type State = {
        var protected_routes : [(Text, ProtectedRoute)];
    };

    public func init() : State = {
        var protected_routes = [];
    };

    func isAllowedRouteCharacter(character : Char) : Bool {
        (character >= 'a' and character <= 'z') or
        (character >= 'A' and character <= 'Z') or
        Char.isDigit(character) or
        character == '/' or character == '.' or character == '_' or
        character == '~' or character == '-';
    };

    // Protected route keys are stored without leading/trailing slashes. The
    // public helper is also used by the enrollment scripts' matching tests and
    // by Item lifecycle guards, so every NFC entry point uses one spelling.
    public func canonicalRoutePath(path : Text) : ?Text {
        let withoutOuterWhitespace = Text.trim(path, #predicate(Char.isWhitespace));
        let canonical = Text.trim(withoutOuterWhitespace, #char('/'));
        if (canonical == "") return null;
        for (character in canonical.chars()) {
            if (not isAllowedRouteCharacter(character)) return null;
        };
        for (segment in Text.split(canonical, #char('/'))) {
            if (segment == "" or segment == "." or segment == "..") return null;
        };
        ?canonical;
    };

    public func itemRoute(itemId : Nat) : Text {
        "nfc/item/" # Nat.toText(itemId);
    };

    public class RoutesStorage(state : State) {
        func requestPath(url : Text) : Text {
            let parts = Iter.toArray(Text.split(url, #char '?'));
            if (parts.size() == 0) "" else parts[0];
        };

        public func routeMatches(path : Text, url : Text) : Bool {
            switch (canonicalRoutePath(path), canonicalRoutePath(requestPath(url))) {
                case (?configured, ?requested) { configured == requested };
                case (_, _) { false };
            };
        };
        
        // Helper to find tag data in the list
        private func findTag(tags : [(Text, TagData)], uid : Text) : ?TagData {
            var result : ?TagData = null;
            for ((t_uid, t_data) in tags.vals()) {
                if (t_uid == uid) {
                    result := ?t_data;
                };
            };
            result
        };

        // Helper to update tag data in the list
        private func updateTagList(tags : [(Text, TagData)], uid : Text, newData : TagData) : [(Text, TagData)] {
            var found = false;
            var newTags : [(Text, TagData)] = [];
            for ((t_uid, t_data) in tags.vals()) {
                if (t_uid == uid) {
                    newTags := Array.concat(newTags, [(uid, newData)]);
                    found := true;
                } else {
                    newTags := Array.concat(newTags, [(t_uid, t_data)]);
                };
            };
            if (not found) {
                newTags := Array.concat(newTags, [(uid, newData)]);
            };
            newTags
        };

        private var routes = Map.fromIter<Text, ProtectedRoute>(
            state.protected_routes.values(),
            Text.compare,
        );

        // The fallback scan keeps old, non-canonical stable keys readable. Any
        // later mutation migrates that entry to its canonical key.
        private func findRouteEntry(path : Text) : ?(Text, ProtectedRoute) {
            let canonical = switch (canonicalRoutePath(path)) {
                case null { return null };
                case (?value) { value };
            };
            switch (Map.get(routes, Text.compare, canonical)) {
                case (?route) { return ?(canonical, route) };
                case null {};
            };
            for ((storedKey, route) in Map.entries(routes)) {
                switch (canonicalRoutePath(storedKey)) {
                    case (?storedCanonical) {
                        if (storedCanonical == canonical) return ?(storedKey, route);
                    };
                    case null {};
                };
            };
            null;
        };

        private func putCanonicalRoute(
            previousKey : Text,
            canonical : Text,
            tags : [(Text, TagData)],
        ) {
            if (previousKey != canonical) {
                ignore Map.take(routes, Text.compare, previousKey);
            };
            Map.add(
                routes,
                Text.compare,
                canonical,
                { path = canonical; tags },
            );
            updateState();
        };

        public func addProtectedRoute(path : Text) : Bool {
            let canonical = switch (canonicalRoutePath(path)) {
                case null { return false };
                case (?value) { value };
            };
            if (Option.isNull(findRouteEntry(canonical))) {
                let new_route : ProtectedRoute = {
                    path = canonical;
                    tags = [];
                };
                Map.add(routes, Text.compare, canonical, new_route);
                updateState();
                true;
            } else {
                false;
            };
        };

        // This replaces updateRouteCmacs, now specific to a tag
        public func updateRouteCmacs(path : Text, uid : Text, new_cmacs : [Text]) : Bool {
            let canonical = switch (canonicalRoutePath(path)) {
                case null { return false };
                case (?value) { value };
            };
            switch (findRouteEntry(canonical)) {
                case (?(previousKey, existing)) {
                    
                    let currentTagData = switch(findTag(existing.tags, uid)) {
                        case (?d) { d };
                        case null { 
                            // Default new tag
                            { cmacs_ = []; scan_count_ = 0 } 
                        };
                    };

                    let newTagData : TagData = {
                        cmacs_ = new_cmacs;
                        scan_count_ = currentTagData.scan_count_;
                    };

                    let newTags = updateTagList(existing.tags, uid, newTagData);

                    putCanonicalRoute(previousKey, canonical, newTags);
                    true;
                };
                case null {
                    false;
                };
            };
        };

        public func appendRouteCmacs(path : Text, uid : Text, new_cmacs : [Text]) : Bool {
            let canonical = switch (canonicalRoutePath(path)) {
                case null { return false };
                case (?value) { value };
            };
            switch (findRouteEntry(canonical)) {
                case (?(previousKey, existing)) {
                     let currentTagData = switch(findTag(existing.tags, uid)) {
                        case (?d) { d };
                        case null { 
                            { cmacs_ = []; scan_count_ = 0 } 
                        };
                    };

                    let newTagData : TagData = {
                        cmacs_ = Array.concat(currentTagData.cmacs_, new_cmacs);
                        scan_count_ = currentTagData.scan_count_;
                    };

                    let newTags = updateTagList(existing.tags, uid, newTagData);

                    putCanonicalRoute(previousKey, canonical, newTags);
                    true;
                };
                case null {
                    false;
                };
            };
        };

        public func getRoute(path : Text) : ?ProtectedRoute {
            let canonical = switch (canonicalRoutePath(path)) {
                case null { return null };
                case (?value) { value };
            };
            switch (findRouteEntry(canonical)) {
                case null { null };
                case (?(_, route)) { ?{ path = canonical; tags = route.tags } };
            };
        };

        public func hasProtectedRoute(path : Text) : Bool {
            Option.isSome(findRouteEntry(path));
        };

        // Returns CMACs for a specific tag
        public func getRouteCmacs(path : Text, uid : Text) : [Text] {
            switch (findRouteEntry(path)) {
                case (?(_, route)) {
                    switch(findTag(route.tags, uid)) {
                        case (?data) { data.cmacs_ };
                        case null { [] };
                    }
                };
                case null { [] };
            };
        };

        // Pure preflight used while validating an entire local Stitch batch.
        // It never advances the NTAG counter: callers can therefore validate
        // every scan first and commit them together only when all are valid.
        public func validatePhysicalScan(scan : PhysicalScanAttempt) : Bool {
            if (not Scan.isFixedHex(scan.uid, 14)) return false;
            switch (findRouteEntry(scan.path)) {
                case null { false };
                case (?(_, route)) {
                    switch (findTag(route.tags, scan.uid)) {
                        case null { false };
                        case (?tagData) {
                            Scan.validateCmac(
                                tagData.cmacs_,
                                scan.cmac,
                                scan.counter,
                                tagData.scan_count_,
                            );
                        };
                    };
                };
            };
        };

        // The method revalidates the complete batch before its first write.
        // Actor message execution has no await here, so no other request can
        // interleave between this preflight and the counter updates.
        public func commitPhysicalScans(scans : [PhysicalScanAttempt]) : Bool {
            var seenTags : [Text] = [];
            for (scan in scans.vals()) {
                let canonical = switch (canonicalRoutePath(scan.path)) {
                    case null { return false };
                    case (?value) { value };
                };
                let tagKey = canonical # "|" # scan.uid;
                switch (Array.find<Text>(seenTags, func(existing) { existing == tagKey })) {
                    case (?_) { return false };
                    case null {};
                };
                if (not validatePhysicalScan(scan)) return false;
                seenTags := Array.concat(seenTags, [tagKey]);
            };

            for (scan in scans.vals()) {
                if (not updateScanCount(scan.path, scan.uid, scan.counter)) {
                    // This is unreachable after the validation pass unless the
                    // in-memory route store is internally inconsistent.
                    return false;
                };
            };
            true;
        };

        public func updateScanCount(path : Text, uid : Text, new_count : Nat) : Bool {
            let canonical = switch (canonicalRoutePath(path)) {
                case null { return false };
                case (?value) { value };
            };
            switch (findRouteEntry(canonical)) {
                case (?(previousKey, existing)) {
                    
                    switch(findTag(existing.tags, uid)) {
                        case (?currentTagData) {
                            let newTagData : TagData = {
                                cmacs_ = currentTagData.cmacs_;
                                scan_count_ = new_count;
                            };
                            let newTags = updateTagList(existing.tags, uid, newTagData);
                            putCanonicalRoute(previousKey, canonical, newTags);
                            true;
                        };
                        case null { false };
                    }
                };
                case null {
                    false;
                };
            };
        };

        public func verifyRouteAccess(path : Text, url : Text) : Bool {
            switch (findRouteEntry(path)) {
                case (?(_, route)) {
                    // Extract UID from URL
                    let uidOpt = Scan.getUid(url);
                    switch(uidOpt) {
                        case (?uid) {
                             switch(findTag(route.tags, uid)) {
                                case (?tagData) {
                                    let counter = Scan.scan(tagData.cmacs_, url, tagData.scan_count_);
                                    if (counter > 0) {
                                        ignore updateScanCount(path, uid, counter);
                                        true;
                                    } else {
                                        false;
                                    };
                                };
                                case null { false }; // Tag not registered for this route
                            }
                        };
                        case null { false }; // No UID in URL
                    }
                };
                case null {
                    false;
                };
            };
        };

        public func listProtectedRoutes() : [(Text, ProtectedRoute)] {
            Iter.toArray(Map.entries(routes));
        };

        // Returns only path and total tag count
        public func listProtectedRoutesSummary() : [(Text, Nat)] {
            let entries = Iter.toArray(Map.entries(routes));
            Array.map<(Text, ProtectedRoute), (Text, Nat)>(
                entries,
                func((path, route)) : (Text, Nat) {
                    (path, route.tags.size())
                }
            )
        };

        public func isProtectedRoute(url : Text) : Bool {
            Option.isSome(Array.find<(Text, ProtectedRoute)>(
                Iter.toArray(Map.entries(routes)),
                func((path, _)) : Bool {
                    routeMatches(path, url);
                },
            ));
        };

        private func updateState() {
            state.protected_routes := Iter.toArray(Map.entries(routes));
        };

        public func getState() : State {
            state;
        };
    };
};
