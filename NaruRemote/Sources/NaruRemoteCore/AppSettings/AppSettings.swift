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

/// Benchmark-backed startup first-frame visible-glance scale. The default
/// keeps the current product behavior; smaller modes are opt-in so physical
/// iPhone runs can judge recognizability before promotion.
public enum StreamStartupGlanceScaleMode: String, Codable, Equatable, Sendable, CaseIterable {
    case standard045 = "standard-045"
    case minimal035 = "minimal-035"
    case glance025 = "glance-025"

    public var toggled: StreamStartupGlanceScaleMode {
        switch self {
        case .standard045:
            return .minimal035
        case .minimal035:
            return .glance025
        case .glance025:
            return .standard045
        }
    }

    public var scale: Double {
        switch self {
        case .standard045:
            return 0.45
        case .minimal035:
            return 0.35
        case .glance025:
            return 0.25
        }
    }
}

/// Benchmark-backed sustained-stream encoding experiment. The default keeps
/// the current production path; non-default cases are opt-in so physical
/// iPhone runs can reproduce live benchmark candidates before any default
/// changes.
public enum StreamEncodingMode: String, Codable, Equatable, Sendable, CaseIterable {
    case standard
    case tightFirstCursor = "tight-first-cursor"
    case localLowLatencyRGB565 = "local-low-latency-rgb565"
    case zrleCompressionZero = "zrle-compression-0"
    case zrleCompressionZeroRGB565 = "zrle-compression-0-rgb565"
    case adaptiveGoodFull = "adaptive-good-full"

    public var toggled: StreamEncodingMode {
        switch self {
        case .standard:
            return .tightFirstCursor
        case .tightFirstCursor:
            return .localLowLatencyRGB565
        case .localLowLatencyRGB565:
            return .zrleCompressionZero
        case .zrleCompressionZero:
            return .zrleCompressionZeroRGB565
        case .zrleCompressionZeroRGB565:
            return .adaptiveGoodFull
        case .adaptiveGoodFull:
            return .standard
        }
    }
}

/// How a finished Compose draft is delivered to the remote on Send.
///
/// Composition is always local (IME, multilingual, voice). Only the
/// transport to the remote differs:
///
/// - `clipboardPaste`: set the remote clipboard and paste (⌘V). Most
///   reliable for multilingual text because paste bypasses the remote
///   keyboard layout / IME entirely — the exact characters land. Cost:
///   it touches the remote clipboard.
/// - `keystrokeStream`: type the finished text as a stream of key events
///   (the proven Direct Keystroke transport). Never touches the remote
///   clipboard. ASCII/Latin is exact; non-ASCII rides X11 Unicode keysyms
///   whose acceptance is server/IME-dependent, so multilingual fidelity is
///   the user's call.
public enum ComposeDeliveryMode: String, Codable, Equatable, Sendable, CaseIterable {
    case clipboardPaste = "clipboard-paste"
    case keystrokeStream = "keystroke-stream"

    public var toggled: ComposeDeliveryMode {
        switch self {
        case .clipboardPaste:
            return .keystrokeStream
        case .keystrokeStream:
            return .clipboardPaste
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
    public var startupGlanceScaleMode: StreamStartupGlanceScaleMode
    public var composeDelivery: ComposeDeliveryMode

    public init(
        streamPowerMode: StreamPowerMode = .balanced,
        streamEncodingMode: StreamEncodingMode = .standard,
        startupPreflightMode: StreamStartupPreflightMode = .disabled,
        startupGlanceScaleMode: StreamStartupGlanceScaleMode = .standard045,
        composeDelivery: ComposeDeliveryMode = .clipboardPaste
    ) {
        self.streamPowerMode = streamPowerMode
        self.streamEncodingMode = streamEncodingMode
        self.startupPreflightMode = startupPreflightMode
        self.startupGlanceScaleMode = startupGlanceScaleMode
        self.composeDelivery = composeDelivery
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
        let startupGlanceScaleMode = try container.decodeIfPresent(
            StreamStartupGlanceScaleMode.self,
            forKey: .startupGlanceScaleMode
        ) ?? .standard045
        let composeDelivery = try container.decodeIfPresent(
            ComposeDeliveryMode.self,
            forKey: .composeDelivery
        ) ?? .clipboardPaste
        self.init(
            streamPowerMode: streamPowerMode,
            streamEncodingMode: streamEncodingMode,
            startupPreflightMode: startupPreflightMode,
            startupGlanceScaleMode: startupGlanceScaleMode,
            composeDelivery: composeDelivery
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
        if startupGlanceScaleMode != .standard045 {
            try container.encode(startupGlanceScaleMode, forKey: .startupGlanceScaleMode)
        }
        if composeDelivery != .clipboardPaste {
            try container.encode(composeDelivery, forKey: .composeDelivery)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case streamPowerMode
        case streamEncodingMode
        case startupPreflightMode
        case startupGlanceScaleMode
        case composeDelivery
    }
}
