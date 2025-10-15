import Nat "mo:core/Nat";
import Text "mo:core/Text";
import Result "mo:core/Result";
import Collection "../collection";

module {
    public type Service = {
        addTokens : (Nat, Nat) -> Result.Result<(), Text>;
        recordMeeting : ([Nat], Text, Nat) -> Result.Result<(), Text>;
        getItemBalance : (Nat) -> Result.Result<Nat, Text>;
        getItemMeetingHistory : (Nat) -> Result.Result<[Collection.MeetingRecord], Text>;
    };

    public func make(collection : Collection.Collection) : Service {
        {
            addTokens = func (itemId : Nat, amount : Nat) : Result.Result<(), Text> {
                collection.addTokens(itemId, amount);
            };
            recordMeeting = func (itemIds : [Nat], meetingId : Text, tokensEarned : Nat) : Result.Result<(), Text> {
                collection.recordMeeting(itemIds, meetingId, tokensEarned);
            };
            getItemBalance = func (itemId : Nat) : Result.Result<Nat, Text> {
                collection.getItemBalance(itemId);
            };
            getItemMeetingHistory = func (itemId : Nat) : Result.Result<[Collection.MeetingRecord], Text> {
                collection.getItemMeetingHistory(itemId);
            };
        }
    };
};
