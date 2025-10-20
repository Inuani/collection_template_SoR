import Text "mo:core/Text";
import Map "mo:core/Map";
import Iter "mo:core/Iter";
import Option "mo:core/Option";

module {
    public type Peer = {
        canisterIdText : Text;
        jwtVerificationKeyHex : Text;
    };

    public type State = {
        var peers : [(Text, Peer)];
    };

    public func init() : State = {
        var peers = [];
    };

    public class Registry(state : State) {
        private var peers = Map.fromIter<Text, Peer>(
            state.peers.values(),
            Text.compare,
        );

        private func updateState() {
            state.peers := Iter.toArray(Map.entries(peers));
        };

        public func upsertPeer(canisterIdText : Text, jwtVerificationKeyHex : Text) : Bool {
            switch (Map.get(peers, Text.compare, canisterIdText)) {
                case (?_) { false };
                case null {
                    Map.add(
                        peers,
                        Text.compare,
                        canisterIdText,
                        {
                            canisterIdText;
                            jwtVerificationKeyHex;
                        },
                    );
                    updateState();
                    true;
                };
            };
        };

        public func removePeer(canisterIdText : Text) : Bool {
            switch (Map.take(peers, Text.compare, canisterIdText)) {
                case null { false };
                case (?_) {
                    updateState();
                    true;
                };
            };
        };

        public func getPeer(canisterIdText : Text) : ?Peer {
            Map.get(peers, Text.compare, canisterIdText);
        };

        public func listPeers() : [Peer] {
            let entries = Iter.toArray(Map.entries(peers));
            Iter.toArray(
                Iter.map<(Text, Peer), Peer>(
                    Iter.fromArray(entries),
                    func((_, peer)) = peer,
                ),
            );
        };

        public func size() : Nat {
            Map.size(peers);
        };

        public func isAuthorized(canisterIdText : Text) : Bool {
            Option.isSome(Map.get(peers, Text.compare, canisterIdText));
        };
    };
}
