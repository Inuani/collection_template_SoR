import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Iter "mo:core/Iter";
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Sha256 "mo:sha2/Sha256";
import Text "mo:core/Text";

import Protocol "knitwork_protocol";

module {
    type Result<T> = Protocol.Result<T>;

    public type ValidatedScan = {
        meeting_id : Text;
        scan : Protocol.ScanProof;
        object_ref : Protocol.ObjectRef;
    };

    public type PendingMeeting = {
        event : Protocol.MeetingEvent;
        scans : [Protocol.ScanProof];
        local_item_ids : [Nat];
        expected_finalizer : Principal;
        handoff_hash : Text;
        receipt_id : Text;
    };

    public type FinalizationRequest = {
        event : Protocol.MeetingEvent;
        scans : [Protocol.ScanProof];
        prepared_peers : [Protocol.PreparedPeer];
    };

    // Transient bridge to the existing NTAG route store. Physical CMACs are
    // not duplicated in Knitwork's stable state; only the canonical ScanProof
    // is persisted after the route counter has been committed.
    public type PhysicalScanAttempt = {
        path : Text;
        uid : Text;
        counter : Nat;
        cmac : Text;
    };

    public type State = {
        var trusted_hub : ?Principal;
        var validated_scans : [(Text, ValidatedScan)];
        var pending_meetings : [(Text, PendingMeeting)];
        var finalization_requests : [(Text, FinalizationRequest)];
        var meetings : [(Text, Protocol.MeetingRecord)];
        var item_meeting_ids : [(Nat, [Text])];
    };

    public func init() : State = {
        var trusted_hub = null;
        var validated_scans = [];
        var pending_meetings = [];
        var finalization_requests = [];
        var meetings = [];
        var item_meeting_ids = [];
    };

    type BatchPlan = {
        local_objects : [Protocol.ObjectRef];
        new_scans : [ValidatedScan];
        physical_scans : [PhysicalScanAttempt];
    };

    let hexCharacters : [Char] = [
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
    ];

    func bytesToHex(bytes : [Nat8]) : Text {
        var characters : [Char] = [];
        for (byte in bytes.vals()) {
            let value = Nat8.toNat(byte);
            characters := Array.concat(
                characters,
                [hexCharacters[value / 16], hexCharacters[value % 16]],
            );
        };
        Text.fromArray(characters);
    };

    public func hashText(value : Text) : Text {
        bytesToHex(
            Blob.toArray(
                Sha256.fromBlob(#sha256, Text.encodeUtf8(value))
            )
        );
    };

    func sameObject(left : Protocol.ObjectRef, right : Protocol.ObjectRef) : Bool {
        Principal.equal(left.collection, right.collection) and left.item_id == right.item_id;
    };

    func sameObjects(left : [Protocol.ObjectRef], right : [Protocol.ObjectRef]) : Bool {
        if (left.size() != right.size()) {
            return false;
        };

        var index = 0;
        while (index < left.size()) {
            if (not sameObject(left[index], right[index])) {
                return false;
            };
            index += 1;
        };
        true;
    };

    func sameEvent(left : Protocol.MeetingEvent, right : Protocol.MeetingEvent) : Bool {
        left.meeting_id == right.meeting_id and
        sameObjects(left.participants, right.participants) and
        left.reader_id == right.reader_id and
        left.location == right.location and
        left.first_scan_at_ns == right.first_scan_at_ns and
        left.last_scan_at_ns == right.last_scan_at_ns and
        left.confirmed_at_ns == right.confirmed_at_ns;
    };

    func sameScan(left : Protocol.ScanProof, right : Protocol.ScanProof) : Bool {
        left.scan_id == right.scan_id and
        left.uid == right.uid and
        left.item_id == right.item_id and
        left.counter == right.counter and
        left.proof == right.proof and
        left.observed_at_ns == right.observed_at_ns;
    };

    func sameScans(left : [Protocol.ScanProof], right : [Protocol.ScanProof]) : Bool {
        if (left.size() != right.size()) {
            return false;
        };
        var index = 0;
        while (index < left.size()) {
            if (not sameScan(left[index], right[index])) {
                return false;
            };
            index += 1;
        };
        true;
    };

    func samePreparedPeer(left : Protocol.PreparedPeer, right : Protocol.PreparedPeer) : Bool {
        Principal.equal(left.collection, right.collection) and
        left.receipt_id == right.receipt_id and
        left.handoff_token == right.handoff_token;
    };

    func samePreparedPeers(left : [Protocol.PreparedPeer], right : [Protocol.PreparedPeer]) : Bool {
        if (left.size() != right.size()) {
            return false;
        };
        var index = 0;
        while (index < left.size()) {
            if (not samePreparedPeer(left[index], right[index])) {
                return false;
            };
            index += 1;
        };
        true;
    };

    func compareObject(left : Protocol.ObjectRef, right : Protocol.ObjectRef) : {
        #less;
        #equal;
        #greater;
    } {
        switch (Text.compare(Principal.toText(left.collection), Principal.toText(right.collection))) {
            case (#less) { #less };
            case (#greater) { #greater };
            case (#equal) {
                if (left.item_id < right.item_id) {
                    #less;
                } else if (left.item_id > right.item_id) {
                    #greater;
                } else {
                    #equal;
                };
            };
        };
    };

    public class Store(
        state : State,
        collectionPrincipal : Principal,
        itemExists : Nat -> Bool,
        validatePhysicalScan : PhysicalScanAttempt -> Bool,
        commitPhysicalScans : [PhysicalScanAttempt] -> Bool,
    ) {
        let validatedScans = Map.fromIter<Text, ValidatedScan>(
            state.validated_scans.vals(),
            Text.compare,
        );
        let pendingMeetings = Map.fromIter<Text, PendingMeeting>(
            state.pending_meetings.vals(),
            Text.compare,
        );
        let finalizationRequests = Map.fromIter<Text, FinalizationRequest>(
            state.finalization_requests.vals(),
            Text.compare,
        );
        let meetings = Map.fromIter<Text, Protocol.MeetingRecord>(
            state.meetings.vals(),
            Text.compare,
        );
        let itemMeetingIds = Map.fromIter<Nat, [Text]>(
            state.item_meeting_ids.vals(),
            Nat.compare,
        );

        func persist() {
            state.validated_scans := Iter.toArray(Map.entries(validatedScans));
            state.pending_meetings := Iter.toArray(Map.entries(pendingMeetings));
            state.finalization_requests := Iter.toArray(Map.entries(finalizationRequests));
            state.meetings := Iter.toArray(Map.entries(meetings));
            state.item_meeting_ids := Iter.toArray(Map.entries(itemMeetingIds));
        };

        func isTrustedHub(caller : Principal) : Bool {
            switch (state.trusted_hub) {
                case (?hub) { Principal.equal(caller, hub) };
                case null { false };
            };
        };

        func physicalRoute(itemId : Nat) : Text {
            "nfc/item/" # Nat.toText(itemId);
        };

        func containsPrincipal(values : [Principal], value : Principal) : Bool {
            switch (
                Array.find<Principal>(
                    values,
                    func(existing : Principal) : Bool {
                        Principal.equal(existing, value);
                    },
                )
            ) {
                case (?_) { true };
                case null { false };
            };
        };

        func containsNat(values : [Nat], value : Nat) : Bool {
            switch (Array.find<Nat>(values, func(existing : Nat) : Bool { existing == value })) {
                case (?_) { true };
                case null { false };
            };
        };

        func validateEvent(event : Protocol.MeetingEvent) : Result<[Protocol.ObjectRef]> {
            if (event.meeting_id == "") {
                return #err("meeting_id cannot be empty");
            };
            if (event.reader_id == "") {
                return #err("reader_id cannot be empty");
            };
            if (event.location == "") {
                return #err("location snapshot cannot be empty");
            };
            if (event.participants.size() < 2 or event.participants.size() > Protocol.maxItems) {
                return #err("a V1 meeting must contain two or three items");
            };
            if (event.last_scan_at_ns < event.first_scan_at_ns) {
                return #err("last_scan_at_ns precedes first_scan_at_ns");
            };
            if (event.last_scan_at_ns - event.first_scan_at_ns >= Protocol.stitchWindowNanos) {
                return #err("scan window must be strictly less than 10 seconds");
            };
            if (event.confirmed_at_ns < event.last_scan_at_ns) {
                return #err("confirmed_at_ns precedes the last scan");
            };

            var collections : [Principal] = [];
            var localObjects : [Protocol.ObjectRef] = [];
            var index = 0;
            while (index < event.participants.size()) {
                let participant = event.participants[index];

                var duplicateIndex = 0;
                while (duplicateIndex < index) {
                    if (sameObject(event.participants[duplicateIndex], participant)) {
                        return #err("meeting participants must be distinct");
                    };
                    duplicateIndex += 1;
                };

                if (index > 0) {
                    switch (compareObject(event.participants[index - 1], participant)) {
                        case (#less) {};
                        case (_) {
                            return #err("meeting participants must use canonical principal/item order");
                        };
                    };
                };

                if (not containsPrincipal(collections, participant.collection)) {
                    collections := Array.concat(collections, [participant.collection]);
                };
                if (Principal.equal(participant.collection, collectionPrincipal)) {
                    localObjects := Array.concat(localObjects, [participant]);
                };
                index += 1;
            };

            if (collections.size() > Protocol.maxCollections) {
                return #err("a V1 meeting supports at most three Collections");
            };
            if (localObjects.size() == 0) {
                return #err("meeting has no item in this Collection");
            };
            #ok(localObjects);
        };

        func validateBatch(
            event : Protocol.MeetingEvent,
            scans : [Protocol.ScanProof],
        ) : Result<BatchPlan> {
            let localObjects = switch (validateEvent(event)) {
                case (#err(message)) { return #err(message) };
                case (#ok(objects)) { objects };
            };

            if (scans.size() != localObjects.size()) {
                return #err("one scan is required for every local participant");
            };

            var seenItems : [Nat] = [];
            var seenScanIds : [Text] = [];
            var seenUids : [Text] = [];
            var newScans : [ValidatedScan] = [];
            var physicalScans : [PhysicalScanAttempt] = [];
            var scanIndex = 0;

            for (scan in scans.vals()) {
                if (scan.scan_id == "" or scan.uid == "" or scan.proof == "") {
                    return #err("scan_id, uid and proof cannot be empty");
                };
                if (scan.counter == 0) {
                    return #err("scan counters start at one");
                };
                if (scan.observed_at_ns < event.first_scan_at_ns or scan.observed_at_ns > event.last_scan_at_ns) {
                    return #err("scan timestamp is outside the meeting window");
                };
                if (containsNat(seenItems, scan.item_id)) {
                    return #err("a local item can only appear once in a meeting");
                };
                switch (Array.find<Text>(seenScanIds, func(value : Text) : Bool { value == scan.scan_id })) {
                    case (?_) { return #err("scan_id is duplicated in the request") };
                    case null {};
                };
                switch (Array.find<Text>(seenUids, func(value : Text) : Bool { value == scan.uid })) {
                    case (?_) { return #err("a tag UID can only appear once in a local scan batch") };
                    case null {};
                };

                let objectRef : Protocol.ObjectRef = {
                    collection = collectionPrincipal;
                    item_id = scan.item_id;
                };
                if (not sameObject(localObjects[scanIndex], objectRef)) {
                    return #err("scans must follow canonical local participant order");
                };

                switch (Map.get(validatedScans, Text.compare, scan.scan_id)) {
                    case (?validated) {
                        if (validated.meeting_id != event.meeting_id or not sameScan(validated.scan, scan)) {
                            return #err("scan_id was already used with different data");
                        };
                    };
                    case null {
                        if (not itemExists(scan.item_id)) {
                            return #err("bound item does not exist");
                        };
                        let physicalScan : PhysicalScanAttempt = {
                            path = physicalRoute(scan.item_id);
                            uid = scan.uid;
                            counter = scan.counter;
                            cmac = scan.proof;
                        };
                        if (not validatePhysicalScan(physicalScan)) {
                            return #err(
                                "physical scan failed route, UID, CMAC or counter validation"
                            );
                        };
                        physicalScans := Array.concat(physicalScans, [physicalScan]);
                        newScans := Array.concat(
                            newScans,
                            [{ meeting_id = event.meeting_id; scan; object_ref = objectRef }],
                        );
                    };
                };

                seenItems := Array.concat(seenItems, [scan.item_id]);
                seenScanIds := Array.concat(seenScanIds, [scan.scan_id]);
                seenUids := Array.concat(seenUids, [scan.uid]);
                scanIndex += 1;
            };

            for (localObject in localObjects.vals()) {
                if (not containsNat(seenItems, localObject.item_id)) {
                    return #err("a local participant is missing its scan");
                };
            };

            #ok({
                local_objects = localObjects;
                new_scans = newScans;
                physical_scans = physicalScans;
            });
        };

        func commitScans(plan : BatchPlan) : Bool {
            if (not commitPhysicalScans(plan.physical_scans)) return false;

            for (validated in plan.new_scans.vals()) {
                Map.add(validatedScans, Text.compare, validated.scan.scan_id, validated);
            };
            true;
        };

        func itemIds(objects : [Protocol.ObjectRef]) : [Nat] {
            Array.map<Protocol.ObjectRef, Nat>(objects, func(objectRef) { objectRef.item_id });
        };

        func indexMeeting(meetingId : Text, localItemIds : [Nat]) {
            for (itemId in localItemIds.vals()) {
                let existing = switch (Map.get(itemMeetingIds, Nat.compare, itemId)) {
                    case (?ids) { ids };
                    case null { [] };
                };
                switch (Array.find<Text>(existing, func(id) { id == meetingId })) {
                    case (?_) {};
                    case null {
                        Map.add(
                            itemMeetingIds,
                            Nat.compare,
                            itemId,
                            Array.concat(existing, [meetingId]),
                        );
                    };
                };
            };
        };

        func putMeeting(record : Protocol.MeetingRecord) {
            Map.add(meetings, Text.compare, record.event.meeting_id, record);
            indexMeeting(record.event.meeting_id, record.local_item_ids);
        };

        func validatePreparedPeers(
            event : Protocol.MeetingEvent,
            peers : [Protocol.PreparedPeer],
        ) : Result<()> {
            var remoteCollections : [Principal] = [];
            for (participant in event.participants.vals()) {
                if (
                    not Principal.equal(participant.collection, collectionPrincipal) and
                    not containsPrincipal(remoteCollections, participant.collection)
                ) {
                    remoteCollections := Array.concat(remoteCollections, [participant.collection]);
                };
            };

            if (peers.size() != remoteCollections.size()) {
                return #err("prepared_peers must contain every remote Collection exactly once");
            };

            var seen : [Principal] = [];
            for (peer in peers.vals()) {
                if (Principal.equal(peer.collection, collectionPrincipal)) {
                    return #err("the finalizer cannot prepare itself as a peer");
                };
                if (peer.receipt_id == "" or peer.handoff_token == "") {
                    return #err("prepared peer receipt and handoff token cannot be empty");
                };
                let expectedReceiptId = hashText(
                    "knitwork-receipt-v1|" #
                    event.meeting_id # "|" #
                    Principal.toText(peer.collection) # "|" #
                    hashText(peer.handoff_token)
                );
                if (peer.receipt_id != expectedReceiptId) {
                    return #err("prepared peer receipt does not match its handoff token");
                };
                if (containsPrincipal(seen, peer.collection)) {
                    return #err("prepared peer Collection is duplicated");
                };
                if (not containsPrincipal(remoteCollections, peer.collection)) {
                    return #err("prepared peer is not a participant Collection");
                };
                seen := Array.concat(seen, [peer.collection]);
            };
            #ok();
        };

        public func validatePeerConfirmation(
            peerCollection : Principal,
            event : Protocol.MeetingEvent,
            record : Protocol.MeetingRecord,
        ) : Result<()> {
            switch (record.status) {
                case (#pending) {
                    return #err("peer returned a pending meeting after confirmation");
                };
                case (#confirmed) {};
            };
            if (not sameEvent(record.event, event)) {
                return #err("peer confirmed a different meeting event");
            };

            var expectedItemIds : [Nat] = [];
            for (participant in event.participants.vals()) {
                if (Principal.equal(participant.collection, peerCollection)) {
                    expectedItemIds := Array.concat(expectedItemIds, [participant.item_id]);
                };
            };
            if (expectedItemIds.size() == 0) {
                return #err("peer Collection is not present in the meeting event");
            };
            if (record.local_item_ids.size() != expectedItemIds.size()) {
                return #err("peer confirmed a different local item set");
            };
            var index = 0;
            while (index < expectedItemIds.size()) {
                if (record.local_item_ids[index] != expectedItemIds[index]) {
                    return #err("peer confirmed a different local item set");
                };
                index += 1;
            };
            #ok();
        };

        public func protocolInfo() : Protocol.ProtocolInfo {
            {
                protocol_major = Protocol.protocolMajor;
                protocol_minor = Protocol.protocolMinor;
                collection = collectionPrincipal;
                trusted_hub = state.trusted_hub;
                capabilities = [
                    "tag_validation_v1",
                    "meeting_v1",
                    "batch_validation_v1",
                    "physical_ntag424_v1",
                ];
                max_items = Protocol.maxItems;
                max_collections = Protocol.maxCollections;
                stitch_window_ns = Protocol.stitchWindowNanos;
            };
        };

        public func getTrustedHub() : ?Principal {
            state.trusted_hub;
        };

        public func setTrustedHub(hub : ?Principal) {
            state.trusted_hub := hub;
        };

        public func prepareMeeting(
            caller : Principal,
            request : Protocol.PrepareMeetingRequest,
        ) : Protocol.PrepareResult {
            if (not isTrustedHub(caller)) {
                return #err("caller is not the trusted Hub");
            };
            if (Principal.equal(request.expected_finalizer, collectionPrincipal)) {
                return #err("prepared Collection cannot also be the finalizer");
            };
            if (request.handoff_hash.size() != 64) {
                return #err("handoff_hash must be a lowercase SHA-256 hex digest");
            };
            switch (
                Array.find<Protocol.ObjectRef>(
                    request.event.participants,
                    func(objectRef) {
                        Principal.equal(objectRef.collection, request.expected_finalizer);
                    },
                )
            ) {
                case null { return #err("expected finalizer is not a participant Collection") };
                case (?_) {};
            };

            switch (Map.get(pendingMeetings, Text.compare, request.event.meeting_id)) {
                case (?pending) {
                    if (
                        not sameEvent(pending.event, request.event) or
                        not sameScans(pending.scans, request.scans) or
                        not Principal.equal(pending.expected_finalizer, request.expected_finalizer) or
                        pending.handoff_hash != request.handoff_hash
                    ) {
                        return #err("meeting_id already has a different preparation");
                    };
                    return #ok({
                        meeting_id = request.event.meeting_id;
                        receipt_id = pending.receipt_id;
                        objects = Array.map<Nat, Protocol.ObjectRef>(
                            pending.local_item_ids,
                            func(itemId) { { collection = collectionPrincipal; item_id = itemId } },
                        );
                    });
                };
                case null {};
            };

            switch (Map.get(meetings, Text.compare, request.event.meeting_id)) {
                case (?_) { return #err("meeting_id is already used") };
                case null {};
            };

            let plan = switch (validateBatch(request.event, request.scans)) {
                case (#err(message)) { return #err(message) };
                case (#ok(value)) { value };
            };
            let localItemIds = itemIds(plan.local_objects);
            let receiptId = hashText(
                "knitwork-receipt-v1|" #
                request.event.meeting_id # "|" #
                Principal.toText(collectionPrincipal) # "|" #
                request.handoff_hash
            );

            if (not commitScans(plan)) {
                return #err("physical scan counters could not be committed");
            };
            Map.add(
                pendingMeetings,
                Text.compare,
                request.event.meeting_id,
                {
                    event = request.event;
                    scans = request.scans;
                    local_item_ids = localItemIds;
                    expected_finalizer = request.expected_finalizer;
                    handoff_hash = request.handoff_hash;
                    receipt_id = receiptId;
                },
            );
            putMeeting({
                event = request.event;
                local_item_ids = localItemIds;
                status = #pending;
            });
            persist();

            #ok({
                meeting_id = request.event.meeting_id;
                receipt_id = receiptId;
                objects = plan.local_objects;
            });
        };

        public func beginFinalize(
            caller : Principal,
            request : Protocol.FinalizeMeetingRequest,
        ) : Protocol.MeetingResult {
            if (not isTrustedHub(caller)) {
                return #err("caller is not the trusted Hub");
            };
            switch (validatePreparedPeers(request.event, request.prepared_peers)) {
                case (#err(message)) { return #err(message) };
                case (#ok()) {};
            };

            switch (Map.get(finalizationRequests, Text.compare, request.event.meeting_id)) {
                case (?existingRequest) {
                    if (
                        not sameEvent(existingRequest.event, request.event) or
                        not sameScans(existingRequest.scans, request.scans) or
                        not samePreparedPeers(existingRequest.prepared_peers, request.prepared_peers)
                    ) {
                        return #err("meeting_id already has a different finalization request");
                    };
                    switch (Map.get(meetings, Text.compare, request.event.meeting_id)) {
                        case (?existing) { return #ok(existing) };
                        case null { return #err("finalization request has no local meeting state") };
                    };
                };
                case null {
                    switch (Map.get(meetings, Text.compare, request.event.meeting_id)) {
                        case (?_) {
                            if (Map.get(pendingMeetings, Text.compare, request.event.meeting_id) != null) {
                                return #err("this Collection was prepared and cannot finalize the same meeting");
                            };
                            return #err("meeting_id is already used");
                        };
                        case null {};
                    };
                };
            };

            let plan = switch (validateBatch(request.event, request.scans)) {
                case (#err(message)) { return #err(message) };
                case (#ok(value)) { value };
            };
            let record : Protocol.MeetingRecord = {
                event = request.event;
                local_item_ids = itemIds(plan.local_objects);
                status = #pending;
            };
            if (not commitScans(plan)) {
                return #err("physical scan counters could not be committed");
            };
            Map.add(
                finalizationRequests,
                Text.compare,
                request.event.meeting_id,
                {
                    event = request.event;
                    scans = request.scans;
                    prepared_peers = request.prepared_peers;
                },
            );
            putMeeting(record);
            persist();
            #ok(record);
        };

        public func completeFinalization(event : Protocol.MeetingEvent) : Protocol.MeetingResult {
            switch (Map.get(meetings, Text.compare, event.meeting_id)) {
                case null { #err("finalizer meeting state was not found") };
                case (?existing) {
                    if (not sameEvent(existing.event, event)) {
                        return #err("meeting_id already has a different event");
                    };
                    let confirmed : Protocol.MeetingRecord = {
                        event = existing.event;
                        local_item_ids = existing.local_item_ids;
                        status = #confirmed;
                    };
                    putMeeting(confirmed);
                    persist();
                    #ok(confirmed);
                };
            };
        };

        public func confirmMeeting(
            caller : Principal,
            request : Protocol.ConfirmMeetingRequest,
        ) : Protocol.MeetingResult {
            let pending = switch (Map.get(pendingMeetings, Text.compare, request.event.meeting_id)) {
                case null { return #err("prepared meeting was not found") };
                case (?value) { value };
            };
            if (not Principal.equal(caller, pending.expected_finalizer)) {
                return #err("caller is not the expected finalizer");
            };
            if (not sameEvent(pending.event, request.event)) {
                return #err("meeting event does not match its preparation");
            };
            if (hashText(request.handoff_token) != pending.handoff_hash) {
                return #err("handoff token is invalid");
            };

            let existing = switch (Map.get(meetings, Text.compare, request.event.meeting_id)) {
                case null { return #err("local meeting state was not found") };
                case (?value) { value };
            };
            if (not sameEvent(existing.event, request.event)) {
                return #err("meeting_id already has a different event");
            };

            let confirmed : Protocol.MeetingRecord = {
                event = existing.event;
                local_item_ids = existing.local_item_ids;
                status = #confirmed;
            };
            putMeeting(confirmed);
            persist();
            #ok(confirmed);
        };

        public func getMeeting(meetingId : Text) : ?Protocol.MeetingRecord {
            Map.get(meetings, Text.compare, meetingId);
        };

        public func getItemMeetings(itemId : Nat) : [Protocol.MeetingRecord] {
            let ids = switch (Map.get(itemMeetingIds, Nat.compare, itemId)) {
                case (?values) { values };
                case null { [] };
            };
            var records : [Protocol.MeetingRecord] = [];
            for (id in ids.vals()) {
                switch (Map.get(meetings, Text.compare, id)) {
                    case (?record) { records := Array.concat(records, [record]) };
                    case null {};
                };
            };
            records;
        };
    };
};
