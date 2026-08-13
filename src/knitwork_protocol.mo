import Principal "mo:core/Principal";

module {
    public let protocolMajor : Nat = 1;
    public let protocolMinor : Nat = 1;
    public let maxItems : Nat = 3;
    public let maxCollections : Nat = 3;
    public let stitchWindowNanos : Int = 10_000_000_000;

    public type Result<T> = {
        #ok : T;
        #err : Text;
    };

    public type ObjectRef = {
        collection : Principal;
        item_id : Nat;
    };

    // `proof` contains the raw NTAG 424 SDM CMAC. UID-to-item binding and
    // monotonic counter enforcement remain Collection-owned.
    public type ScanProof = {
        scan_id : Text;
        uid : Text;
        item_id : Nat;
        counter : Nat;
        proof : Text;
        observed_at_ns : Int;
    };

    public type MeetingEvent = {
        meeting_id : Text;
        participants : [ObjectRef];
        reader_id : Text;
        location : Text;
        first_scan_at_ns : Int;
        last_scan_at_ns : Int;
        confirmed_at_ns : Int;
    };

    public type MeetingStatus = {
        #pending;
        #confirmed;
    };

    public type MeetingRecord = {
        event : MeetingEvent;
        local_item_ids : [Nat];
        status : MeetingStatus;
    };

    public type PreparedReceipt = {
        meeting_id : Text;
        receipt_id : Text;
        objects : [ObjectRef];
    };

    public type PreparedPeer = {
        collection : Principal;
        receipt_id : Text;
        handoff_token : Text;
    };

    public type PrepareMeetingRequest = {
        event : MeetingEvent;
        scans : [ScanProof];
        expected_finalizer : Principal;
        handoff_hash : Text;
    };

    public type FinalizeMeetingRequest = {
        event : MeetingEvent;
        scans : [ScanProof];
        prepared_peers : [PreparedPeer];
    };

    public type ConfirmMeetingRequest = {
        event : MeetingEvent;
        handoff_token : Text;
    };

    public type ProtocolInfo = {
        protocol_major : Nat;
        protocol_minor : Nat;
        collection : Principal;
        trusted_hub : ?Principal;
        capabilities : [Text];
        max_items : Nat;
        max_collections : Nat;
        stitch_window_ns : Int;
    };

    public type PrepareResult = Result<PreparedReceipt>;
    public type MeetingResult = Result<MeetingRecord>;
    public type UnitResult = Result<()>;
};
