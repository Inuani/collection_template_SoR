import Text "mo:core/Text";
import Int "mo:core/Int";
import Time "mo:core/Time";
import Debug "mo:core/Debug";
import Blob "mo:core/Blob";
import Array "mo:core/Array";
import Nat8 "mo:core/Nat8";
import JWT "mo:jwt@2";
import Json "mo:json@1";
import BaseX "mo:base-x-encoder";
import ECDSA "mo:ecdsa";
import Sha256 "mo:sha2@0/Sha256";
import IC "mo:ic";
import ICall "mo:ic/Call";
import Nat64 "mo:core/Nat64";

module {
    public type MintResult = {
        token : Text;
        publicKeyHex : Text;
        payload : Text;
        header : Text;
        isValid : Bool;
    };

    let keyId : { name : Text; curve : IC.EcdsaCurve } = {
        curve = #secp256k1;
        name = "dfx_test_key";
    };

    public func mintUnsignedToken(unsigned : JWT.UnsignedToken) : async Text {
        let signingInput = JWT.toTextUnsigned(unsigned);
        let signingInputBytes = Blob.toArray(Text.encodeUtf8(signingInput));
        let hashBlob = Sha256.fromArray(#sha256, signingInputBytes);

        let signResponse = await ICall.signWithEcdsa({
            message_hash = hashBlob;
            derivation_path = [];
            key_id = keyId;
        });

        let signatureDer = Blob.toArray(signResponse.signature);
        let signatureRaw = derToRaw(signatureDer);
        let signatureEncoded = base64UrlEncode(signatureRaw);

        signingInput # "." # signatureEncoded;
    };

    public func mintTestToken() : async MintResult {
        let now = Time.now();
        let iatSeconds = now / 1_000_000_000;
        let expSeconds = iatSeconds + 300;

        let unsigned : JWT.UnsignedToken = {
            header = [
                ("alg", #string("ES256K")),
                ("typ", #string("JWT")),
            ];
            payload = [
                ("iss", #string("bleu_travail_core")),
                ("sub", #string("stitching-test")),
                ("iat", #number(#int(iatSeconds))),
                ("exp", #number(#int(expSeconds))),
            ];
        };

        let token = await mintUnsignedToken(unsigned);

        let publicKeyRequest = {
            canister_id = null;
            derivation_path = [];
            key_id = keyId;
        };

        let methodNameSize = Nat64.fromNat("ecdsa_public_key".size());
        let payloadSize = Nat64.fromNat(Blob.size(to_candid (publicKeyRequest)));
        let cycles = ICall.Cost.call(methodNameSize, payloadSize);

        let pkResponse = await (with cycles) IC.ic.ecdsa_public_key(publicKeyRequest);

        let publicKeyHex = bytesToHex(Blob.toArray(pkResponse.public_key));

        let isValid = switch (JWT.parse(token)) {
            case (#ok(_)) true;
            case (#err(err)) {
                Debug.print("JWT parse failed: " # err);
                false;
            };
        };

        let headerJson = Json.stringify(#object_(unsigned.header), null);
        let payloadJson = Json.stringify(#object_(unsigned.payload), null);

        {
            token = token;
            publicKeyHex = publicKeyHex;
            payload = payloadJson;
            header = headerJson;
            isValid = isValid;
        };
    };

    func base64UrlEncode(bytes : [Nat8]) : Text {
        BaseX.toBase64(bytes.vals(), #url({ includePadding = false }));
    };

    func derToRaw(der : [Nat8]) : [Nat8] {
        switch (ECDSA.signatureFromBytes(der.vals(), ECDSA.secp256k1Curve(), #der)) {
            case (#ok(signature)) {
                signature.toBytes(#raw);
            };
            case (#err(err)) {
                Debug.print("Failed to convert DER signature: " # err);
                Array.repeat<Nat8>(0, 64);
            };
        };
    };

    func bytesToHex(bytes : [Nat8]) : Text {
        BaseX.toHex(bytes.vals(), {
            isUpper = false;
            prefix = #none;
        });
    };
};
