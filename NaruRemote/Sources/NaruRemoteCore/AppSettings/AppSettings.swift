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

/// Explicit experiment gate for app-side startup stream warm-up.
public enum StreamStartupPreflightMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Do not consume any hidden post-first-frame updates.
    case disabled
    /// After the first visible frame, consume one hidden incremental update.
    case oneHiddenFrame = "one-hidden-frame"

    public var toggled: StreamStartupPreflightMode {
        switch self {
        case .disabled:
            return .oneHiddenFrame
        case .oneHiddenFrame:
            return .disabled
        }
    }

    public var requestedHiddenFrameCount: Int {
        switch self {
        case .disabled:
            return 0
        case .oneHiddenFrame:
            return 1
        }
    }
}

/// Benchmark-backed sustained-stream encoding experiment. The default keeps
/// the current production path; non-default cases are opt-in so physical
/// iPhone runs can reproduce live benchmark candidates before any default
/// changes.
public enum StreamEncodingMode: String, Codable, Equatable, Sendable, CaseIterable {
    case standard
    case zrleCompressionZero = "zrle-compression-0"
    case adaptiveGoodFull = "adaptive-good-full"

    public var toggled: StreamEncodingMode {
        switch self {
        case .standard:
            return .zrleCompressionZero
        case .zrleCompressionZero:
            return .adaptiveGoodFull
        case .adaptiveGoodFull:
            return .standard
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
    public var streamEncodingMode: StreamEncodingMode
    public var startupPreflightMode: StreamStartupPreflightMode

    public init(
        streamPowerMode: StreamPowerMode = .balanced,
        streamEncodingMode: StreamEncodingMode = .standard,
        startupPreflightMode: StreamStartupPreflightMode = .disabled
    ) {
        self.streamPowerMode = streamPowerMode
        self.streamEncodingMode = streamEncodingMode
        self.startupPreflightMode = startupPreflightMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let streamPowerMode = try container.decodeIfPresent(
            StreamPowerMode.self,
            forKey: .streamPowerMode
        ) ?? .balanced
        let startupPreflightMode = try container.decodeIfPresent(
            StreamStartupPreflightMode.self,
            forKey: .startupPreflightMode
        ) ?? .disabled
        let streamEncodingMode = try container.decodeIfPresent(
            StreamEncodingMode.self,
            forKey: .streamEncodingMode
        ) ?? .standard
        self.init(
            streamPowerMode: streamPowerMode,
            streamEncodingMode: streamEncodingMode,
            startupPreflightMode: startupPreflightMode
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if streamPowerMode != .balanced {
            try container.encode(streamPowerMode, forKey: .streamPowerMode)
        }
        if streamEncodingMode != .standard {
            try container.encode(streamEncodingMode, forKey: .streamEncodingMode)
        }
        if startupPreflightMode != .disabled {
            try container.encode(startupPreflightMode, forKey: .startupPreflightMode)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case streamPowerMode
        case streamEncodingMode
        case startupPreflightMode
    }
}
