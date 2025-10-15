import Nat "mo:core/Nat";
import Text "mo:core/Text";
import Result "mo:core/Result";
import Collection "../collection";

module {
    public type Service = {
        addTokens : (Nat, Nat) -> Result.Result<(), Text>;
        recordStitching : ([Nat], Text, Nat) -> Result.Result<(), Text>;
        getItemBalance : (Nat) -> Result.Result<Nat, Text>;
        getItemStitchingHistory : (Nat) -> Result.Result<[Collection.StitchingRecord], Text>;
    };

    public func make(collection : Collection.Collection) : Service {
        {
            addTokens = func (itemId : Nat, amount : Nat) : Result.Result<(), Text> {
                collection.addTokens(itemId, amount);
            };
            recordStitching = func (itemIds : [Nat], stitchingId : Text, tokensEarned : Nat) : Result.Result<(), Text> {
                collection.recordStitching(itemIds, stitchingId, tokensEarned);
            };
            getItemBalance = func (itemId : Nat) : Result.Result<Nat, Text> {
                collection.getItemBalance(itemId);
            };
            getItemStitchingHistory = func (itemId : Nat) : Result.Result<[Collection.StitchingRecord], Text> {
                collection.getItemStitchingHistory(itemId);
            };
        }
    };
};
