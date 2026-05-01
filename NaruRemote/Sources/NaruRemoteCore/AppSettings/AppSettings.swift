import Foundation

/// App-level user preferences that are not tied to a single
/// `ConnectionProfile` and never carry secrets.  Stored as plain
/// JSON via `AppSettingsPersisting` (no Keychain).  Future toggles
/// (e.g. Phase 9 Direct Keystroke Streaming default) belong here.
///
/// Forward-compat policy: every field has a default and decodes
/// through `decodeIfPresent` so an empty `{}` JSON, a legacy file
/// missing newer keys, or a file written by a future build with
/// extra keys all decode without throwing.  Only add fields that
/// are actually used — see constitution §V.
public struct AppSettings: Codable, Equatable, Sendable {
    /// `true` once the user has dismissed the first-run onboarding
    /// checklist on this device.  The checklist is also hidden when
    /// `OnboardingGuide.isComplete` is `true`; this flag is the
    /// "dismiss while still incomplete" override.
    public var dismissedOnboardingChecklist: Bool

    public init(dismissedOnboardingChecklist: Bool = false) {
        self.dismissedOnboardingChecklist = dismissedOnboardingChecklist
    }

    public enum CodingKeys: String, CodingKey {
        case dismissedOnboardingChecklist
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dismissed = try container.decodeIfPresent(
            Bool.self,
            forKey: .dismissedOnboardingChecklist
        ) ?? false
        self.init(dismissedOnboardingChecklist: dismissed)
    }
}
