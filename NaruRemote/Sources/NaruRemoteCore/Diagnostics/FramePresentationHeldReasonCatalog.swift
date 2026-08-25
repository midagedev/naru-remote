import Foundation

/// The closed vocabulary a diagnostic export may carry for "what is holding
/// frames back" (spec 028).
///
/// Constitution §IV: diagnostic exports use a fixed safe-detail catalog, never
/// caller-provided strings. The reason is derived from `FramePresentationOutcome`
/// — a closed enum — but it arrives at the export boundary as a `String`, so it
/// is re-checked against the catalog here rather than trusted. Anything not in
/// the catalog becomes `unknown`.
public enum FramePresentationHeldReasonCatalog {
    public static let none = "none"
    public static let unknown = "unknown"

    public static var allowed: Set<String> {
        var values = Set(FramePresentationOutcome.allCases.map(\.rawValue))
        values.insert(none)
        values.insert(unknown)
        return values
    }

    public static func sanitized(_ raw: String) -> String {
        allowed.contains(raw) ? raw : unknown
    }

    /// The label for a ledger's dominant withholding reason.
    public static func label(for outcome: FramePresentationOutcome?) -> String {
        guard let outcome else {
            return none
        }
        return sanitized(outcome.rawValue)
    }
}
