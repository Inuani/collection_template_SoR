import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Float "mo:core/Float";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Text "mo:core/Text";
import Json "mo:json@1";
import JWT "mo:jwt@2";
import Identity "mo:liminal/Identity";
import Random "mo:base/Random";
import Blob "mo:core/Blob";
import BaseX "mo:base-x-encoder";

module {
    public type SessionItem = {
        canisterId : Text;
        itemId : Nat;
    };

    public type StitchingState = {
        items : [SessionItem];
        startTime : ?Int;
        sessionId : ?Text;
        issuedAt : ?Int;
        expiresAt : ?Int;
    };

    public type ClaimInput = {
        issuer : Text;
        subject : Text;
        sessionId : Text;
        items : [SessionItem];
        startTime : Int;
        now : Int;
        ttlSeconds : Nat;
    };

    public type StitchingClaims = {
        issuer : Text;
        subject : Text;
        sessionId : Text;
        items : [SessionItem];
        startTime : Int;
        issuedAt : Int;
        expiresAt : Int;
    };

    public let defaultIssuer : Text = "collection_d_evorev";
    public let defaultSubjectPrefix : Text = "stitching-session";
    public let tokenCookieName : Text = "stitching_jwt";
    public let stitchingTimeoutNanos : Int = 60_000_000_000;

    public func empty() : StitchingState {
        {
            items = [];
            startTime = null;
            sessionId = null;
            issuedAt = null;
            expiresAt = null;
        }
    };

    public func itemsToText(items : [SessionItem]) : Text {
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
            text #= encodeSessionItem(item);
        };
        text
    };

    public func itemsFromText(text : Text) : [SessionItem] {
        if (text.size() == 0) {
            return [];
        };

        let parts = Iter.toArray(Text.split(text, #char ','));
        var parsed : [SessionItem] = [];
        for (entry in parts.vals()) {
            switch (decodeSessionItem(entry)) {
                case (?value) {
                    parsed := Array.concat(parsed, [value]);
                };
                case null {};
            };
        };
        parsed
    };

    public func fromIdentity(identityOpt : ?Identity.Identity) : ?StitchingState {
        switch (identityOpt) {
            case null { null };
            case (?identity) {
                switch (identity.kind) {
                    case (#jwt(token)) { parseJWT(token) };
                };
            };
        }
    };

    public func parseJWT(token : JWT.Token) : ?StitchingState {
        let items = parseItems(JWT.getPayloadValue(token, "items"));
        let startTime = parseInt(JWT.getPayloadValue(token, "start_time"));
        let sessionId = parseText(JWT.getPayloadValue(token, "session_id"));
        let issuedAt = parseInt(JWT.getPayloadValue(token, "iat"));
        let expiresAt = parseInt(JWT.getPayloadValue(token, "exp"));

        if (items == null and startTime == null and sessionId == null) {
            return null;
        };

        ?{
            items = switch (items) { case null { [] }; case (?value) value };
            startTime = startTime;
            sessionId = sessionId;
            issuedAt = issuedAt;
            expiresAt = expiresAt;
        };
    };

    public func generateSessionId() : async Text {
        let entropy = await Random.blob();
        let bytes = Blob.toArray(entropy);
        BaseX.toHex(bytes.vals(), { isUpper = false; prefix = #none });
    };

    public func buildClaims(input : ClaimInput) : StitchingClaims {
        let issuedAtSeconds = input.now / 1_000_000_000;
        let ttlInt = Int.fromNat(input.ttlSeconds);
        let expiresAtSeconds = issuedAtSeconds + ttlInt;

        {
            issuer = input.issuer;
            subject = input.subject;
            sessionId = input.sessionId;
            items = input.items;
            startTime = input.startTime;
            issuedAt = issuedAtSeconds;
            expiresAt = expiresAtSeconds;
        };
    };

    public func toUnsignedToken(claims : StitchingClaims) : JWT.UnsignedToken {
        let itemsJson = Array.map<SessionItem, Json.Json>(
            claims.items,
            func(item : SessionItem) : Json.Json {
                #object_([
                    ("canister_id", #string(item.canisterId)),
                    ("item_id", #number(#int(Int.fromNat(item.itemId)))),
                ]);
            },
        );

        let payloadBase : [(Text, Json.Json)] = [
            ("iss", #string(claims.issuer)),
            ("sub", #string(claims.subject)),
            ("session_id", #string(claims.sessionId)),
            ("iat", #number(#int(claims.issuedAt))),
            ("exp", #number(#int(claims.expiresAt))),
            ("items", #array(itemsJson)),
            ("start_time", #string(Int.toText(claims.startTime))),
        ];

        {
            header = [
                ("alg", #string("ES256K")),
                ("typ", #string("JWT")),
            ];
            payload = payloadBase;
        };
    };

    func parseItems(valueOpt : ?Json.Json) : ?[SessionItem] {
        switch (valueOpt) {
            case null { null };
            case (?value) {
                switch (value) {
                    case (#array(itemsJson)) {
                        var parsed : [SessionItem] = [];
                        for (entry in itemsJson.vals()) {
                            switch (parseSessionItem(entry)) {
                                case (?sessionItem) {
                                    parsed := Array.concat(parsed, [sessionItem]);
                                };
                                case null {};
                            };
                        };
                        ?parsed;
                    };
                    case (_) { null };
                };
            };
        }
    };

    func parseSessionItem(value : Json.Json) : ?SessionItem {
        switch (value) {
            case (#object_(fields)) {
                var canisterId : ?Text = null;
                var itemId : ?Nat = null;
                for ((key, val) in fields.vals()) {
                    switch (key) {
                        case "canister_id" {
                            canisterId := parseText(?val);
                        };
                        case "item_id" {
                            itemId := parseNat(val);
                        };
                        case _ {};
                    };
                };
                switch (canisterId, itemId) {
                    case (?cid, ?iid) {
                        ?{
                            canisterId = cid;
                            itemId = iid;
                        };
                    };
                    case _ { null };
                };
            };
            case (#number(_)) {
                switch (parseNat(value)) {
                    case (?iid) {
                        ?{
                            canisterId = "";
                            itemId = iid;
                        };
                    };
                    case null null;
                };
            };
            case (#string(text)) {
                decodeSessionItem(text);
            };
            case _ { null };
        };
    };

    func encodeSessionItem(item : SessionItem) : Text {
        let jsonValue : Json.Json = #object_([
            ("cid", #string(item.canisterId)),
            ("id", #number(#int(Int.fromNat(item.itemId))))
        ]);
        let jsonText = Json.stringify(jsonValue, null);
        let jsonBytes = Blob.toArray(Text.encodeUtf8(jsonText));
        BaseX.toBase64(jsonBytes.vals(), #url({ includePadding = false }));
    };

    func decodeSessionItem(value : Text) : ?SessionItem {
        let decodedFromBase64 : ?SessionItem = switch (BaseX.fromBase64(value)) {
            case (#ok(bytes)) {
                let jsonTextOpt = Text.decodeUtf8(Blob.fromArray(bytes));
                switch (jsonTextOpt) {
                    case (?jsonText) parseSessionItemJson(jsonText);
                    case null null;
                };
            };
            case (#err(_)) null;
        };

        switch (decodedFromBase64) {
            case (?sessionItem) return ?sessionItem;
            case null {};
        };

        decodeSessionItemLegacy(value);
    };

    func parseSessionItemJson(jsonText : Text) : ?SessionItem {
        switch (Json.parse(jsonText)) {
            case (#ok(#object_(fields))) {
                var cid : ?Text = null;
                var itemId : ?Nat = null;

                for ((key, value) in fields.vals()) {
                    if (key == "cid") {
                        switch (parseText(?value)) {
                            case (?text) { cid := ?text; };
                            case null {};
                        };
                    } else if (key == "id") {
                        switch (parseNat(value)) {
                            case (?natVal) { itemId := ?natVal; };
                            case null {};
                        };
                    };
                };

                switch (cid, itemId) {
                    case (?foundCid, ?foundItemId) {
                        ?{
                            canisterId = foundCid;
                            itemId = foundItemId;
                        };
                    };
                    case (?_, null) {
                        null;
                    };
                    case (null, ?foundItemId) {
                        ?{
                            canisterId = "";
                            itemId = foundItemId;
                        };
                    };
                    case (null, null) null;
                };
            };
            case (_) null;
        };
    };

    func decodeSessionItemLegacy(value : Text) : ?SessionItem {
        func parseWithSeparator(sep : Char) : ?SessionItem {
            let parts = Iter.toArray(Text.split(value, #char sep));
            if (parts.size() != 2) { return null; };
            switch (Nat.fromText(parts[1])) {
                case (?itemId) {
                    ?{
                        canisterId = parts[0];
                        itemId = itemId;
                    };
                };
                case null null;
            };
        };

        switch (parseWithSeparator('_')) {
            case (?result) return ?result;
            case null {};
        };

        switch (parseWithSeparator(':')) {
            case (?result) return ?result;
            case null {};
        };

        switch (Nat.fromText(value)) {
            case (?itemId) {
                ?{
                    canisterId = "";
                    itemId = itemId;
                };
            };
            case null null;
        };
    };

    func parseNat(value : Json.Json) : ?Nat {
        switch (parseInt(?value)) {
            case null { null };
            case (?intVal) {
                if (intVal < 0) { return null };
                ?Nat.fromInt(intVal);
            };
        }
    };

    func parseInt(valueOpt : ?Json.Json) : ?Int {
        switch (valueOpt) {
            case null { null };
            case (?value) {
                switch (value) {
                    case (#number(num)) {
                        switch (num) {
                            case (#int(i)) ?i;
                            case (#float(f)) ?Float.toInt(f);
                        };
                    };
                    case (#string(text)) {
                        Int.fromText(text);
                    };
                    case (_) { null };
                };
            };
        }
    };

    func parseText(valueOpt : ?Json.Json) : ?Text {
        switch (valueOpt) {
            case null { null };
            case (?value) {
                switch (value) {
                    case (#string(text)) ?text;
                    case (_) null;
                };
            };
        }
    };
};
