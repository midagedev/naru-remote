import Foundation

/// The closed vocabulary a diagnostic export may carry for the applied
/// server-side downscale (spec 031).
///
/// Labels rather than the scale factor itself: spec 018's own note keeps scale
/// factors tied to framebuffer dimensions out of logs and exports, and a label
/// answers the only question a report needs to answer — was the picture halved.
public enum AppleServerDownscaleRungCatalog {
    public static let full = "full"
    public static let half = "half"
    public static let unknown = "unknown"

    public static var allowed: Set<String> { [full, half, unknown] }

    public static func sanitized(_ raw: String) -> String {
        allowed.contains(raw) ? raw : unknown
    }

    /// Maps an applied rung to its label. Anything that is not one of the two
    /// rungs the policy can apply reads as `unknown` rather than being rounded
    /// into a claim.
    public static func label(forAppliedRung rung: Double) -> String {
        if rung == AppleServerDownscalePolicy.fullRung {
            return full
        }
        if rung == AppleServerDownscalePolicy.downscaledRung {
            return half
        }
        return unknown
    }
}
