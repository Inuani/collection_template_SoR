import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Float "mo:core/Float";
import Array "mo:core/Array";
import Text "mo:core/Text";
import Json "mo:json@1";
import JWT "mo:jwt@2";
import Identity "mo:liminal/Identity";
import Random "mo:base/Random";
import Blob "mo:core/Blob";
import BaseX "mo:base-x-encoder";

module {
    public type StitchingState = {
        items : [Nat];
        startTime : ?Int;
        sessionId : ?Text;
        issuedAt : ?Int;
        expiresAt : ?Int;
    };

    public type ClaimInput = {
        issuer : Text;
        subject : Text;
        sessionId : Text;
        items : [Nat];
        startTime : Int;
        now : Int;
        ttlSeconds : Nat;
    };

    public type StitchingClaims = {
        issuer : Text;
        subject : Text;
        sessionId : Text;
        items : [Nat];
        startTime : Int;
        issuedAt : Int;
        expiresAt : Int;
    };

    public let defaultIssuer : Text = "bleu_travail_core";
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
        let itemsJson = Array.map<Nat, Json.Json>(
            claims.items,
            func(id : Nat) : Json.Json {
                let idInt = Int.fromNat(id);
                #number(#int(idInt));
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

    func parseItems(valueOpt : ?Json.Json) : ?[Nat] {
        switch (valueOpt) {
            case null { null };
            case (?value) {
                switch (value) {
                    case (#array(itemsJson)) {
                        var parsed : [Nat] = [];
                        for (entry in itemsJson.vals()) {
                            switch (parseNat(entry)) {
                                case (?id) { parsed := Array.concat(parsed, [id]); };
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
