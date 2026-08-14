import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Int "mo:core/Int";
import Iter "mo:core/Iter";
import Nat32 "mo:core/Nat32";
import Nat8 "mo:core/Nat8";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Hmac "mo:hmac";

module {
    public let TOKEN_DURATION_NS : Int = 120_000_000_000;
    public let MAX_FUTURE_SKEW_NS : Int = 60_000_000_000;
    public let SECRET_SIZE : Nat = 32;

    public type State = {
        var secret : Blob;
    };

    public func init() : State = {
        var secret = "";
    };

    func bytesToHex(bytes : Blob) : Text {
        let alphabet = Text.toArray("0123456789abcdef");
        var result = "";
        for (byte in bytes.vals()) {
            let value = Nat32.fromNat(Nat8.toNat(byte));
            result #= Text.fromChar(alphabet[Nat32.toNat(value >> 4)]);
            result #= Text.fromChar(alphabet[Nat32.toNat(value & 0x0f)]);
        };
        result;
    };

    func signaturesEqual(left : Text, right : Text) : Bool {
        let leftCharacters = Text.toArray(left);
        let rightCharacters = Text.toArray(right);
        if (leftCharacters.size() != rightCharacters.size()) return false;

        var difference : Nat32 = 0;
        for (index in leftCharacters.keys()) {
            difference |= Char.toNat32(leftCharacters[index]) ^ Char.toNat32(rightCharacters[index]);
        };
        difference == 0;
    };

    public class Access(state : State) {
        public func isConfigured() : Bool {
            state.secret.size() == SECRET_SIZE;
        };

        public func installSecret(secret : Blob) : Bool {
            if (secret.size() != SECRET_SIZE) return false;
            state.secret := secret;
            true;
        };

        public func generateToken(filename : Text) : ?Text {
            generateTokenAt(filename, Time.now());
        };

        public func generateTokenAt(filename : Text, now : Int) : ?Text {
            if (not isConfigured() or now < 0) return null;
            let timestamp = Int.toText(now);
            let message = "collection-file-access-v2|" # filename # "|" # timestamp;
            let signature = Hmac.generate(
                Blob.toArray(state.secret),
                Text.encodeUtf8(message).vals(),
                #sha256,
            );
            ?(timestamp # "." # bytesToHex(signature));
        };

        public func validateToken(token : Text, expectedFilename : Text) : Bool {
            validateTokenAt(token, expectedFilename, Time.now());
        };

        public func validateTokenAt(token : Text, expectedFilename : Text, now : Int) : Bool {
            if (not isConfigured() or now < 0) return false;
            let parts = Iter.toArray(Text.split(token, #char '.'));
            if (parts.size() != 2) return false;
            let timestampText = parts[0];
            let signature = parts[1];
            if (signature.size() != 64) return false;

            let timestamp = switch (Int.fromText(timestampText)) {
                case (?value) value;
                case null return false;
            };
            if (
                timestamp < 0 or
                now >= timestamp + TOKEN_DURATION_NS or
                timestamp > now + MAX_FUTURE_SKEW_NS
            ) {
                return false;
            };

            switch (generateTokenAt(expectedFilename, timestamp)) {
                case null false;
                case (?expected) {
                    let expectedParts = Iter.toArray(Text.split(expected, #char '.'));
                    expectedParts.size() == 2 and signaturesEqual(signature, expectedParts[1]);
                };
            };
        };
    };
};
