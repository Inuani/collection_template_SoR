import HashMap "mo:base/HashMap";
import Text "mo:core/Text";
import TextBase "mo:base/Text";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import StitchingToken "stitching_token";

module {
    public type Session = {
        items : [StitchingToken.SessionItem];
        startTime : Int;
        ttlSeconds : Nat;
        createdAt : Int;
    };

    public class PendingSessions() {
        let store = HashMap.HashMap<Text, Session>(16, TextBase.equal, TextBase.hash);

        public func put(id : Text, session : Session) {
            store.put(id, session);
        };

        public func take(id : Text, now : Int) : ?Session {
            switch (store.remove(id)) {
                case null { null };
                case (?session) {
                    let ttlNanos = Int.fromNat(session.ttlSeconds) * 1_000_000_000;
                    if (now - session.createdAt > ttlNanos) {
                        null;
                    } else {
                        ?session;
                    };
                };
            }
        };
    };
};
