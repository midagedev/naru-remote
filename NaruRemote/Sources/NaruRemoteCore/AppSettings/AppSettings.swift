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
/// - `keystrokeStream` (default): type the finished text as a stream of key
///   events (the proven Direct Keystroke transport). Never touches the
///   remote clipboard. ASCII/Latin is exact; non-ASCII rides X11 Unicode
///   keysyms (`0x01000000 | codepoint`) — verified live to render Korean/CJK
///   on macOS Screen Sharing regardless of the remote IME (astral-plane
///   emoji excepted). This is the reliable multilingual path.
/// - `clipboardPaste`: set the remote clipboard and paste (⌘V). Only useful
///   where the server negotiated UTF-8 clipboard; macOS Screen Sharing
///   decodes ClientCutText as Latin-1 and drops Korean/CJK, so such payloads
///   auto-route to the keystroke path instead of failing. Cost: it touches
///   the remote clipboard.
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
    /// What PiP Watch frames on (spec 034 FR-006). The mode is a preference;
    /// the drawn region it can refer to is a session fact and is not stored.
    public var pipFramingMode: PiPFramingMode
    /// Does leaving the app put a live session in a floating window
    /// (spec 036 FR-005)?
    ///
    /// Default on, because it is what was asked for — an app cannot send
    /// itself to the background, so the gesture that backgrounds it is where
    /// PiP belongs. Switchable, because a PiP window keeps streaming while
    /// backgrounded and what that costs on cellular is still unmeasured.
    public var pipEntersOnLeavingApp: Bool
    /// Does an open connection hold off the device's auto-lock (spec 039
    /// FR-003)?
    ///
    /// Default on. The canonical session here is watching a build, a test run,
    /// or an agent work for minutes at a time without touching the screen —
    /// which is precisely the input auto-lock counts as idleness. Switchable,
    /// because holding a phone awake is a battery decision and it is the
    /// user's to make; `ScreenWakePolicy` reads this.
    public var keepsScreenAwakeDuringSession: Bool

    public init(
        streamPowerMode: StreamPowerMode = .balanced,
        streamEncodingMode: StreamEncodingMode = .standard,
        startupPreflightMode: StreamStartupPreflightMode = .disabled,
        startupGlanceScaleMode: StreamStartupGlanceScaleMode = .standard045,
        composeDelivery: ComposeDeliveryMode = .keystrokeStream,
        pipFramingMode: PiPFramingMode = .currentView,
        pipEntersOnLeavingApp: Bool = true,
        keepsScreenAwakeDuringSession: Bool = true
    ) {
        self.streamPowerMode = streamPowerMode
        self.streamEncodingMode = streamEncodingMode
        self.startupPreflightMode = startupPreflightMode
        self.startupGlanceScaleMode = startupGlanceScaleMode
        self.composeDelivery = composeDelivery
        self.pipFramingMode = pipFramingMode
        self.pipEntersOnLeavingApp = pipEntersOnLeavingApp
        self.keepsScreenAwakeDuringSession = keepsScreenAwakeDuringSession
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
        ) ?? .keystrokeStream
        let pipFramingMode = try container.decodeIfPresent(
            PiPFramingMode.self,
            forKey: .pipFramingMode
        ) ?? .currentView
        let pipEntersOnLeavingApp = try container.decodeIfPresent(
            Bool.self,
            forKey: .pipEntersOnLeavingApp
        ) ?? true
        let keepsScreenAwakeDuringSession = try container.decodeIfPresent(
            Bool.self,
            forKey: .keepsScreenAwakeDuringSession
        ) ?? true
        self.init(
            streamPowerMode: streamPowerMode,
            streamEncodingMode: streamEncodingMode,
            startupPreflightMode: startupPreflightMode,
            startupGlanceScaleMode: startupGlanceScaleMode,
            composeDelivery: composeDelivery,
            pipFramingMode: pipFramingMode,
            pipEntersOnLeavingApp: pipEntersOnLeavingApp,
            keepsScreenAwakeDuringSession: keepsScreenAwakeDuringSession
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
        if composeDelivery != .keystrokeStream {
            try container.encode(composeDelivery, forKey: .composeDelivery)
        }
        if pipFramingMode != .currentView {
            try container.encode(pipFramingMode, forKey: .pipFramingMode)
        }
        if !pipEntersOnLeavingApp {
            try container.encode(pipEntersOnLeavingApp, forKey: .pipEntersOnLeavingApp)
        }
        if !keepsScreenAwakeDuringSession {
            try container.encode(
                keepsScreenAwakeDuringSession,
                forKey: .keepsScreenAwakeDuringSession
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case streamPowerMode
        case streamEncodingMode
        case startupPreflightMode
        case startupGlanceScaleMode
        case composeDelivery
        case pipFramingMode
        case pipEntersOnLeavingApp
        case keepsScreenAwakeDuringSession
    }
}
