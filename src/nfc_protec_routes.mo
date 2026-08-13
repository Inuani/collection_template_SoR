import Text "mo:core/Text";
import Map "mo:core/Map";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Option "mo:core/Option";
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

    public class RoutesStorage(state : State) {
        func normalizedRoutePath(path : Text) : Text {
            if (Text.startsWith(path, #text "/")) path else "/" # path;
        };

        func requestPath(url : Text) : Text {
            let parts = Iter.toArray(Text.split(url, #char '?'));
            if (parts.size() == 0) "" else parts[0];
        };

        public func routeMatches(path : Text, url : Text) : Bool {
            normalizedRoutePath(path) == requestPath(url);
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

        public func addProtectedRoute(path : Text) : Bool {
            if (Option.isNull(Map.get(routes, Text.compare, path))) {
                let new_route : ProtectedRoute = {
                    path;
                    tags = [];
                };
                Map.add(routes, Text.compare, path, new_route);
                updateState();
                true;
            } else {
                false;
            };
        };

        // This replaces updateRouteCmacs, now specific to a tag
        public func updateRouteCmacs(path : Text, uid : Text, new_cmacs : [Text]) : Bool {
            switch (Map.get(routes, Text.compare, path)) {
                case (?existing) {
                    
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

                    Map.add(
                        routes,
                        Text.compare,
                        path,
                        {
                            path = existing.path;
                            tags = newTags;
                        },
                    );
                    updateState();
                    true;
                };
                case null {
                    false;
                };
            };
        };

        public func appendRouteCmacs(path : Text, uid : Text, new_cmacs : [Text]) : Bool {
            switch (Map.get(routes, Text.compare, path)) {
                case (?existing) {
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

                    Map.add(
                        routes,
                        Text.compare,
                        path,
                        {
                            path = existing.path;
                            tags = newTags;
                        },
                    );
                    updateState();
                    true;
                };
                case null {
                    false;
                };
            };
        };

        public func getRoute(path : Text) : ?ProtectedRoute {
            Map.get(routes, Text.compare, path);
        };

        // Returns CMACs for a specific tag
        public func getRouteCmacs(path : Text, uid : Text) : [Text] {
            switch (Map.get(routes, Text.compare, path)) {
                case (?route) {
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
            switch (Map.get(routes, Text.compare, scan.path)) {
                case null { false };
                case (?route) {
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
                let tagKey = scan.path # "|" # scan.uid;
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
             switch (Map.get(routes, Text.compare, path)) {
                case (?existing) {
                    
                    switch(findTag(existing.tags, uid)) {
                        case (?currentTagData) {
                            let newTagData : TagData = {
                                cmacs_ = currentTagData.cmacs_;
                                scan_count_ = new_count;
                            };
                            let newTags = updateTagList(existing.tags, uid, newTagData);
                            Map.add(
                                routes,
                                Text.compare,
                                path,
                                {
                                    path = existing.path;
                                    tags = newTags;
                                },
                            );
                            updateState();
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
            switch (Map.get(routes, Text.compare, path)) {
                case (?route) {
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
