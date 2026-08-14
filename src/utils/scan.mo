import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Char "mo:core/Char";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Sha256 "mo:sha2/Sha256";
import Blob "mo:core/Blob";

module {
    func hexDigitToNat(char : Char) : ?Nat {
        if (Char.toNat32(char) >= Char.toNat32('0') and Char.toNat32(char) <= Char.toNat32('9')) {
            ?(Nat32.toNat(Char.toNat32(char)) - 48);
        } else if (Char.toNat32(char) >= Char.toNat32('A') and Char.toNat32(char) <= Char.toNat32('F')) {
            ?(Nat32.toNat(Char.toNat32(char)) - 55);
        } else if (Char.toNat32(char) >= Char.toNat32('a') and Char.toNat32(char) <= Char.toNat32('f')) {
            ?(Nat32.toNat(Char.toNat32(char)) - 87);
        } else {
            null;
        };
    };

    public func hexToNat(hexString : Text) : Nat {
        var result : Nat = 0;
        for (char in hexString.chars()) {
            switch (hexDigitToNat(char)) {
                case (?digit) { result := result * 16 + digit };
                case null { assert (false) };
            };
        };
        return result;
    };

    // NTAG 424 uses little-endian bytes inside its cryptographic session-key
    // derivation, but its contactless ASCII mirror is MSB-first. The first
    // scan is therefore rendered in the URL as "000001".
    public func asciiCounterToNat(hexString : Text) : ?Nat {
        let chars = Text.toArray(hexString);
        if (chars.size() != 6) return null;

        var result : Nat = 0;
        var offset : Nat = 0;
        while (offset < 6) {
            let high = switch (hexDigitToNat(chars[offset])) {
                case (?digit) digit;
                case null return null;
            };
            let low = switch (hexDigitToNat(chars[offset + 1])) {
                case (?digit) digit;
                case null return null;
            };
            result := (result * 256) + (high * 16) + low;
            offset += 2;
        };
        ?result;
    };

    public func isFixedHex(value : Text, expectedSize : Nat) : Bool {
        let characters = Text.toArray(value);
        if (characters.size() != expectedSize) return false;
        for (character in characters.vals()) {
            switch (hexDigitToNat(character)) {
                case (?_) {};
                case null { return false };
            };
        };
        true;
    };

    public func subText(value : Text, indexStart : Nat, indexEnd : Nat) : Text {
        if (indexStart == 0 and indexEnd >= value.size()) {
            return value;
        } else if (indexStart >= value.size()) {
            return "";
        };

        var indexEndValid = indexEnd;
        if (indexEnd > value.size()) {
            indexEndValid := value.size();
        };

        var result : Text = "";
        var iter = Iter.toArray<Char>(value.chars());
        for (index in Nat.rangeInclusive(indexStart, indexEndValid - 1)) {
            result := result # Char.toText(iter[index]);
        };

        result;
    };

    func queryParameter(url : Text, key : Text) : ?Text {
        let full_query = Iter.toArray(Text.split(url, #char '?'));
        if (full_query.size() != 2) {
            return null;
        };
        let queries = Iter.toArray(Text.split(full_query[1], #char '&'));
        for (parameter in queries.vals()) {
            let pair = Iter.toArray(Text.split(parameter, #char '='));
            if (pair.size() == 2 and pair[0] == key) {
                return ?pair[1];
            };
        };
        null;
    };

    public func validateCmac(
        cmacs : [Text],
        cmac : Text,
        counter : Nat,
        scan_count : Nat,
    ) : Bool {
        if (not isFixedHex(cmac, 16)) return false;
        if (counter == 0 or counter > cmacs.size() or counter <= scan_count) {
            return false;
        };
        if (not isFixedHex(cmacs[counter - 1], 64)) return false;
        let sha = Blob.toArray(
            Sha256.fromArray(
                #sha256,
                Array.map(
                    Text.toArray(cmac),
                    func(c : Char) : Nat8 {
                        Nat8.fromNat(Nat32.toNat(Char.toNat32(c)));
                    },
                ),
            )
        );

        for (i in Nat.rangeInclusive(0, sha.size() - 1)) {
            if (Nat8.toNat(sha[i]) != hexToNat(subText(cmacs[counter - 1], i * 2, i * 2 + 2))) {
                return false;
            };
        };

        true;
    };

    public func scan(cmacs : [Text], url : Text, scan_count : Nat) : Nat {
        let cmac = switch (queryParameter(url, "cmac")) {
            case (?value) value;
            case null return 0;
        };
        let counterText = switch (queryParameter(url, "ctr")) {
            case (?value) value;
            case null return 0;
        };
        let counter = switch (asciiCounterToNat(counterText)) {
            case (?value) value;
            case null return 0;
        };

        if (validateCmac(cmacs, cmac, counter, scan_count)) counter else 0;
    };
    public func getUid(url : Text) : ?Text {
        queryParameter(url, "uid");
    };

    public func getCmac(url : Text) : ?Text {
        queryParameter(url, "cmac");
    };
};
