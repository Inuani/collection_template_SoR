import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Session "mo:liminal/Session";

module {
    public let stitchingTimeoutNanos : Int = 60_000_000_000;

    private let itemsKey : Text = "stitching_items";
    private let startTimeKey : Text = "stitching_start_time";
    private let finalizeTokenKey : Text = "stitching_finalize_token";

    public func getItems(sessionOpt : ?Session.Session) : [Nat] {
        switch (sessionOpt) {
            case null { [] };
            case (?session) {
                switch (session.get(itemsKey)) {
                    case null { [] };
                    case (?itemsText) parseItemIds(itemsText);
                }
            };
        }
    };

    public func itemsToText(items : [Nat]) : Text {
        if (items.size() == 0) {
            return "";
        };

        var text = "";
        var first = true;
        for (item in items.vals()) {
            if (first) {
                first := false;
            } else {
                text #= ",";
            };
            text #= Nat.toText(item);
        };
        text
    };

    public func getStartTime(sessionOpt : ?Session.Session) : ?Int {
        switch (sessionOpt) {
            case null { null };
            case (?session) {
                switch (session.get(startTimeKey)) {
                    case null { null };
                    case (?startText) Int.fromText(startText);
                }
            };
        }
    };

    public func getStartTimeText(sessionOpt : ?Session.Session) : Text {
        switch (sessionOpt) {
            case null { "0" };
            case (?session) {
                switch (session.get(startTimeKey)) {
                    case null { "0" };
                    case (?value) value;
                }
            };
        }
    };

    public func getFinalizeToken(sessionOpt : ?Session.Session) : Text {
        switch (getFinalizeTokenOpt(sessionOpt)) {
            case null "";
            case (?token) token;
        }
    };

    public func getFinalizeTokenOpt(sessionOpt : ?Session.Session) : ?Text {
        switch (sessionOpt) {
            case null { null };
            case (?session) { session.get(finalizeTokenKey) };
        }
    };

    public func hasExpired(
        sessionOpt : ?Session.Session,
        now : Int,
        timeout : Int
    ) : Bool {
        switch (getStartTime(sessionOpt)) {
            case null false;
            case (?startTime) now - startTime > timeout;
        }
    };

    public func clear(sessionOpt : ?Session.Session) {
        switch (sessionOpt) {
            case null {};
            case (?session) {
                session.remove(itemsKey);
                session.remove(startTimeKey);
                session.remove(finalizeTokenKey);
            };
        }
    };

    private func parseItemIds(itemsText : Text) : [Nat] {
        let parts = Iter.toArray(Text.split(itemsText, #char ','));
        var items : [Nat] = [];
        for (part in parts.vals()) {
            switch (Nat.fromText(part)) {
                case (?id) { items := Array.concat(items, [id]); };
                case null {};
            };
        };
        items
    };
};
