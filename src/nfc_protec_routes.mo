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

    public type State = {
        var protected_routes : [(Text, ProtectedRoute)];
    };

    public func init() : State = {
        var protected_routes = [];
    };

    public class RoutesStorage(state : State) {
        
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
                    Text.contains(url, #text path);
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
