import Foundation

/// App-level user preferences that are not tied to a single
/// `ConnectionProfile` and never carry secrets.  Stored as plain
/// JSON via `AppSettingsPersisting` (no Keychain).
///
/// Currently empty.  The first persisted setting,
/// `dismissedOnboardingChecklist`, was removed when first-run
/// onboarding was reduced to a stateless empty-state CTA derived from
/// `profiles.isEmpty` (spec FR-015).  The struct + persistence
/// pipeline are intentionally retained — the next setting toggle
/// (e.g. Phase 9 Direct Keystroke Streaming Mode default) can plug
/// in here without rebuilding the JSON read/write layer.
///
/// Forward-compat policy: every future field MUST default and decode
/// through `decodeIfPresent` so an empty `{}` JSON, a legacy file
/// missing newer keys (including the historical
/// `dismissedOnboardingChecklist` key, now silently ignored), or a
/// file written by a future build with extra keys all decode without
/// throwing.  Only add fields that are actually used — see
/// constitution §V.
public struct AppSettings: Codable, Equatable, Sendable {
    public init() {}

    public init(from decoder: Decoder) throws {
        // No fields to decode today.  Decoding still succeeds against
        // any JSON object shape (including legacy files carrying the
        // removed `dismissedOnboardingChecklist` key) so old settings
        // files keep loading silently.
        _ = try decoder.container(keyedBy: EmptyCodingKey.self)
        self.init()
    }

    public func encode(to encoder: Encoder) throws {
        // Emit `{}` so the on-disk shape stays consistent and valid
        // JSON whether or not future fields exist.
        _ = encoder.container(keyedBy: EmptyCodingKey.self)
    }

    private enum EmptyCodingKey: CodingKey {}
}
