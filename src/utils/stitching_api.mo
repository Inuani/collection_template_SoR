import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Result "mo:core/Result";
import StitchingToken "stitching_token";

module {
    public type JoinSessionRequest = {
        sessionId : Text;
        sessionNonce : Text;
        hostCanisterId : Text;
        participant : StitchingToken.SessionItem;
        scanTimestamp : Int;
        jwt : Text;
    };

    public type JoinSessionResponse = {
        redirectPath : Text;
        alreadyJoined : Bool;
        currentParticipants : Nat;
    };

    public type JoinSessionResult = Result.Result<JoinSessionResponse, Text>;
}
