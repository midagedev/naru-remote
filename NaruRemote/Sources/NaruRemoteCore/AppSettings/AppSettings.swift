import Foundation

/// User-visible stream pacing preference for sustained VNC sessions.
public enum StreamPowerMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Maximum responsiveness within the app's normal thermal floors.
    case balanced
    /// Slower sustained pacing intended for hot-device / long-session use.
    case powerSaver = "power-saver"

    public var toggled: StreamPowerMode {
        switch self {
        case .balanced:
            return .powerSaver
        case .powerSaver:
            return .balanced
        }
    }
}

/// App-level user preferences that are not tied to a single
/// `ConnectionProfile` and never carry secrets.  Stored as plain
/// JSON via `AppSettingsPersisting` (no Keychain).
///
/// The default JSON remains `{}`.  Non-default settings are encoded
/// explicitly so older files and missing keys keep loading as
/// product-default behavior.
///
/// Forward-compat policy: every future field MUST default and decode
/// through `decodeIfPresent` so an empty `{}` JSON, a legacy file
/// missing newer keys (including the historical
/// `dismissedOnboardingChecklist` key, now silently ignored), or a
/// file written by a future build with extra keys all decode without
/// throwing.  Only add fields that are actually used — see
/// constitution §V.
public struct AppSettings: Codable, Equatable, Sendable {
    public var streamPowerMode: StreamPowerMode

    public init(streamPowerMode: StreamPowerMode = .balanced) {
        self.streamPowerMode = streamPowerMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let streamPowerMode = try container.decodeIfPresent(
            StreamPowerMode.self,
            forKey: .streamPowerMode
        ) ?? .balanced
        self.init(streamPowerMode: streamPowerMode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if streamPowerMode != .balanced {
            try container.encode(streamPowerMode, forKey: .streamPowerMode)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case streamPowerMode
    }
}
