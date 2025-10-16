import Text "mo:core/Text";
import Int "mo:core/Int";
import Time "mo:core/Time";
import Principal "mo:core/Principal";
import Debug "mo:core/Debug";
import Blob "mo:core/Blob";
import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import SHA "sha";
import JWT "mo:jwt@2";
import BaseX "mo:base-x-encoder";
import ECDSA "mo:ecdsa";

module {
    public type MintResult = {
        token : Text;
        publicKeyHex : Text;
        payload : Text;
        header : Text;
        isValid : Bool;
    };

    type EcdsaCurve = {
        #secp256k1;
    };

    type EcdsaKeyId = {
        curve : EcdsaCurve;
        name : Text;
    };

    type EcdsaPublicKeyRequest = {
        canister_id : ?Principal;
        derivation_path : [Blob];
        key_id : EcdsaKeyId;
    };

    type EcdsaPublicKeyResponse = {
        public_key : Blob;
        chain_code : Blob;
    };

    type EcdsaSignRequest = {
        message_hash : Blob;
        derivation_path : [Blob];
        key_id : EcdsaKeyId;
    };

    type EcdsaSignResponse = {
        signature : Blob;
    };

    let ic = actor "aaaaa-aa" : actor {
        ecdsa_public_key : (EcdsaPublicKeyRequest) -> async EcdsaPublicKeyResponse;
        sign_with_ecdsa : (EcdsaSignRequest) -> async EcdsaSignResponse;
    };

    let keyId : EcdsaKeyId = {
        curve = #secp256k1;
        name = "dfx_test_key";
    };

    let signWithEcdsaCycles : Nat = 26_153_846_153;
    let ecdsaPublicKeyCycles : Nat = 10_000_000_000;

    public func mintTestToken() : async MintResult {
        let headerJson = "{\"alg\":\"ES256K\",\"typ\":\"JWT\"}";

        let now = Time.now();
        let iatSeconds = now / 1_000_000_000;
        let expSeconds = iatSeconds + 300;

        let payloadJson =
            "{" #
            "\"iss\":\"bleu_travail_core\"," #
            "\"sub\":\"stitching-test\"," #
            "\"iat\":" # Int.toText(iatSeconds) # "," #
            "\"exp\":" # Int.toText(expSeconds) #
            "}";

        let headerEncoded = base64UrlEncode(Blob.toArray(Text.encodeUtf8(headerJson)));
        let payloadEncoded = base64UrlEncode(Blob.toArray(Text.encodeUtf8(payloadJson)));
        let signingInput = headerEncoded # "." # payloadEncoded;

        let signingInputBytes = Blob.toArray(Text.encodeUtf8(signingInput));
        let messageHash = SHA.sha256(signingInputBytes);
        let hashBlob = Blob.fromArray(messageHash);

        let signResponse = await (with cycles = signWithEcdsaCycles) ic.sign_with_ecdsa({
            message_hash = hashBlob;
            derivation_path = [];
            key_id = keyId;
        });

        let signatureDer = Blob.toArray(signResponse.signature);
        let signatureRaw = derToRaw(signatureDer);
        let signatureEncoded = base64UrlEncode(signatureRaw);

        let token = signingInput # "." # signatureEncoded;

        let pkResponse = await (with cycles = ecdsaPublicKeyCycles) ic.ecdsa_public_key({
            canister_id = null;
            derivation_path = [];
            key_id = keyId;
        });

        let publicKeyHex = bytesToHex(Blob.toArray(pkResponse.public_key));

        let isValid = switch (JWT.parse(token)) {
            case (#ok(_)) true;
            case (#err(err)) {
                Debug.print("JWT parse failed: " # err);
                false;
            };
        };

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
