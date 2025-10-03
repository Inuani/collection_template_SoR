import Text "mo:base/Text";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Scan "scan";

module {
    public type ProtectedRoute = {
        path : Text;
        cmacs_ : [Text];
        scan_count_ : Nat;
    };

    public type State = {
        var protected_routes : [(Text, ProtectedRoute)];
    };

    public func init() : State = {
        var protected_routes = [];
    };

    public class RoutesStorage(state : State) {
        private var routes = HashMap.fromIter<Text, ProtectedRoute>(
            state.protected_routes.vals(),
            state.protected_routes.size(),
            Text.equal,
            Text.hash,
        );

        public func addProtectedRoute(path : Text) : Bool {
            if (Option.isNull(routes.get(path))) {
                let new_route : ProtectedRoute = {
                    path;
                    cmacs_ = [];
                    scan_count_ = 0;
                };
                routes.put(path, new_route);
                updateState();
                true;
            } else {
                false;
            };
        };

        public func updateRouteCmacs(path : Text, new_cmacs : [Text]) : Bool {
            switch (routes.get(path)) {
                case (?existing) {
                    routes.put(
                        path,
                        {
                            path = existing.path;
                            cmacs_ = new_cmacs;
                            scan_count_ = existing.scan_count_;
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

        public func appendRouteCmacs(path : Text, new_cmacs : [Text]) : Bool {
            switch (routes.get(path)) {
                case (?existing) {
                    routes.put(
                        path,
                        {
                            path = existing.path;
                            cmacs_ = Array.append(existing.cmacs_, new_cmacs);
                            scan_count_ = existing.scan_count_;
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
            routes.get(path);
        };

        public func getRouteCmacs(path : Text) : [Text] {
            switch (routes.get(path)) {
                case (?route) {
                    route.cmacs_;
                };
                case null { [] };
            };
        };

        public func updateScanCount(path : Text, new_count : Nat) : Bool {
            switch (routes.get(path)) {
                case (?existing) {
                    routes.put(
                        path,
                        {
                            path = existing.path;
                            cmacs_ = existing.cmacs_;
                            scan_count_ = new_count;
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

        public func verifyRouteAccess(path : Text, url : Text) : Bool {
            switch (routes.get(path)) {
                case (?route) {
                    let counter = Scan.scan(route.cmacs_, url, route.scan_count_);
                    if (counter > 0) {
                        ignore updateScanCount(path, counter);
                        true;
                    } else {
                        false;
                    };
                };
                case null {
                    false;
                };
            };
        };

        public func listProtectedRoutes() : [(Text, ProtectedRoute)] {
            Iter.toArray(routes.entries());
        };

        public func isProtectedRoute(url : Text) : Bool {
            Option.isSome(Array.find<(Text, ProtectedRoute)>(
                Iter.toArray(routes.entries()),
                func((path, _)) : Bool {
                    Text.contains(url, #text path);
                },
            ));
        };

        private func updateState() {
            state.protected_routes := Iter.toArray(routes.entries());
        };

        public func getState() : State {
            state;
        };
    };
};