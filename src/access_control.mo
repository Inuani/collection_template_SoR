import Principal "mo:core/Principal";

module {
    public func isInitializer(caller : Principal, initializer : Principal) : Bool {
        Principal.equal(caller, initializer);
    };
};
