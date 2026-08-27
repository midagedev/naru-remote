import Combine
import Foundation
import NaruRemoteCore

#if canImport(VideoToolbox)
import VideoToolbox
#endif

/// Wall-clock milliseconds elapsed since `start`, clamped to ≥ 0. Shared by
/// the outbound-input dispatcher and the app model's frame/stream timing so
/// the rounding/clamping is defined once. Module-internal so
/// `OutboundInputEventDispatcher` (its own file) can reuse it.
func elapsedMilliseconds(since start: Date) -> Int {
    max(0, Int((Date().timeIntervalSince(start) * 1000).rounded()))
}

private struct PendingPointerMove {
    let command: RFBPointerCommand
    let pointerClient: RFBPointerEventClient
    let streamID: UUID?
    let sessionID: RemoteSession.ID?
    let profileID: ConnectionProfile.ID?
    let allowsBestEffort: Bool
}

private struct PendingPointerInputFramebufferUpdateNudge: Sendable {
    let sender: any RFBFramebufferUpdateRequestSending
    let streamID: UUID
    let sessionID: RemoteSession.ID
    let profileID: ConnectionProfile.ID
    let region: RFBFramebufferUpdateRegion?
}

private enum FrameDeliveryInteractionReason: Hashable {
    case composeFocus
    case viewportGesture
    case transientInteraction
}

private struct DeferredViewportInteractionFrame {
    let frame: RFBFramePumpFrame
    let serverInit: RFBServerInit
    let profile: ConnectionProfile
    let sessionID: RemoteSession.ID
    let streamID: UUID
}

private struct RemoteClipboardTextClientBox: @unchecked Sendable {
    let client: any RemoteClipboardTextClient
    private let identity: ObjectIdentifier

    init(client: any RemoteClipboardTextClient) {
        self.client = client
        self.identity = ObjectIdentifier(client)
    }

    func matches(_ other: (any RemoteClipboardTextClient)?) -> Bool {
        guard let other else { return false }
        return ObjectIdentifier(other) == identity
    }
}

private struct HelperTextInsertClientBox: @unchecked Sendable {
    let client: any HelperTextInsertClient
    private let identity: ObjectIdentifier

    init(client: any HelperTextInsertClient) {
        self.client = client
        self.identity = ObjectIdentifier(client)
    }

    func matches(_ other: (any HelperTextInsertClient)?) -> Bool {
        guard let other else { return false }
        return ObjectIdentifier(other) == identity
    }
}

private struct ComposeRouteDiagnosticSnapshot {
    var plannedPath: TextInjectionPath?
    var utf8ClipboardSupport: RemoteClipboardUTF8Support?
    var routeBlocker: DiagnosticComposeRouteBlocker?
    var helperProfileID: ConnectionProfile.ID?
}

/// Fixed, privacy-safe failures for profile mutations.  Raw persistence or
/// Keychain errors never cross into the UI; the editor can safely render this
/// catalog while leaving the user's form in place for a retry.
public enum ProfilePersistenceFailure: Equatable, Sendable {
    case profileSave
    case profileRemoval
    case passwordSave
    case passwordRemoval
    case helperTokenSave
    case helperTokenRemoval
    case helperVideoTokenSave
    case helperVideoTokenRemoval
    case credentialRestore

    public var safeMessage: String {
        switch self {
        case .profileSave:
            "Profile could not be saved on this device."
        case .profileRemoval:
            "Profile could not be removed on this device."
        case .passwordSave:
            "Password could not be saved on this device."
        case .passwordRemoval:
            "Password could not be removed on this device."
        case .helperTokenSave:
            "Helper token could not be saved on this device."
        case .helperTokenRemoval:
            "Helper token could not be removed on this device."
        case .helperVideoTokenSave:
            "Helper video token could not be saved on this device."
        case .helperVideoTokenRemoval:
            "Helper video token could not be removed on this device."
        case .credentialRestore:
            "Profile could not be saved, and saved credentials could not be restored on this device."
        }
    }
}

/// Completion handed back to profile-mutation UI.  `succeeded` means the
/// profile store write (or the explicit nil-store fixture path) completed;
/// callers must not dismiss an editor before receiving it.
public enum ProfilePersistenceResult: Equatable, Sendable {
    case succeeded
    case failed(ProfilePersistenceFailure)

    public var failure: ProfilePersistenceFailure? {
        guard case .failed(let failure) = self else {
            return nil
        }
        return failure
    }
}

/// One process-local undo record for a Keychain mutation performed while a
/// profile write is still provisional. Values never leave this call stack,
/// are never logged, and are discarded immediately after commit/rollback.
private struct CredentialMutationRollback {
    let credentialRef: String
    let previousValue: String?
}

/// Serializes profile + Keychain transactions across MainActor suspension
/// points. `@MainActor` alone permits reentrancy at every `await`; without a
/// gate, overlapping add/edit/delete calls can observe and roll back each
/// other's provisional credential mutations.
private actor ProfilePersistenceMutationGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}

@MainActor
public final class NaruRemoteAppModel: ObservableObject {
    public typealias HelperVideoStartStream = @Sendable (
        ConnectionProfile,
        String,
        String,
        HelperVideoStartStreamRequestBody,
        Int
    ) async throws -> HelperVideoStreamNetworkStartResult
    public typealias HelperVideoOpenStream = @Sendable (
        ConnectionProfile,
        String,
        String,
        HelperVideoStartStreamRequestBody
    ) -> HelperVideoStreamNetworkEvents
    public typealias HelperVideoRendererFactory = @MainActor @Sendable () -> any HelperVideoAccessUnitRendering
    public typealias HelperVideoStreamOutcomeHandler = @Sendable (
        RemoteSession.ID,
        ConnectionProfile.ID,
        HelperVideoStreamSessionOutcome
    ) async -> Void

    /// macOS Screen Sharing and other VNC servers apply ClientCutText
    /// asynchronously from key events. Keep the Send button responsive,
    /// but give the remote clipboard enough time to adopt the payload
    /// before the paste shortcut arrives.
    private static let remoteClipboardPasteSettleDelay: TimeInterval = 0.30

    /// Fixed positive status shown when the helper text bridge natively
    /// inserted the composed text and reported it landed (QW3). The
    /// clipboard/keystroke paths cannot confirm delivery, so they keep the
    /// honest `.unknown` "confirmation unavailable" copy; only a
    /// `nativeInsert` result with a `.sent` status earns this. Fixed string
    /// (never composed content), so DiagnosticExport still relies on the
    /// enum-`rawValue` safe catalog rather than this message.
    nonisolated static let helperNativeInsertConfirmedMessage = "Inserted into the remote app."
    @Published public private(set) var profiles: [ConnectionProfile]
    @Published public var selectedProfileID: ConnectionProfile.ID?
    @Published public private(set) var session: RemoteSession?
    @Published public private(set) var diagnosticRun: ConnectionDiagnosticRun?
    @Published public private(set) var diagnosticExportRelayForTesting: String?
    /// Per-profile cache of the most recent diagnostic verdict
    /// (UX punch-list #109).  Memory-only — diagnostic results from
    /// yesterday do not reflect today's network state, so the dict
    /// is intentionally not persisted across app launches.  Populated
    /// at every site that finishes a `ConnectionDiagnosticRun` (the
    /// "running" placeholder run from `runConnectionChecks()` does
    /// NOT update the cache — only finished runs do, per
    /// `ConnectionDiagnosticRun.verdict`'s `.unknown` semantics).
    @Published public private(set) var lastDiagnosticVerdict: [ConnectionProfile.ID: DiagnosticVerdict] = [:]
    @Published public private(set) var composeDraft: ComposeDraft?
    @Published public private(set) var latestInjectionAttempt: TextInjectionAttempt?
    private var latestComposeSendPreparation: ComposeSendPreparationReport?
    @Published public private(set) var pipWatchSession: PiPWatchSession?
    public private(set) var latestFramebuffer: RFBRawFramebuffer?
    public private(set) var inputCoordinateSpace: RemoteFramebufferCoordinateSpace?
    /// Damage rectangles paired with `latestFramebuffer`.  Populated
    /// whenever a streaming frame arrives from a damage-tracking pump
    /// source (`RFBFramePumpFrame.dirtyRectangles`); cleared on
    /// disconnect, profile changes, and full-frame fallback paths so
    /// the renderer falls back to a full-frame upload when the pairing
    /// no longer applies.
    public private(set) var latestFrameDirtyRectangles: [RFBFrameDamageRect]?
    public private(set) var latestFrameChangedPixelCount: Int?
    public private(set) var sessionStreamStats = SessionStreamStats()
    private var pendingAsyncAppFrameApplyMilliseconds: Int?
    /// Most recent server-provided cursor shape from the RFB Cursor
    /// pseudo-encoding. Cleared with framebuffer/session state and never
    /// persisted or exported; the view may use it to draw the trackpad
    /// cursor with server fidelity.
    public private(set) var latestServerCursor: RFBServerCursor?
    @Published public private(set) var profilePreviews: [ConnectionProfile.ID: ProfilePreviewThumbnail]
    @Published public private(set) var profileReachability: [ConnectionProfile.ID: ProfileReachabilityState]
    @Published public private(set) var helperTextBridgeState: [ConnectionProfile.ID: HelperTextBridgeProfileState]
    @Published public private(set) var visualTransportMode: VisualTransportMode
    @Published public private(set) var helperVideoProfileState: [ConnectionProfile.ID: HelperVideoProfileState]
    @Published public private(set) var helperVideoStreamDescriptor: HelperVideoStreamDescriptor?
    @Published public private(set) var helperVideoStreamHealth: HelperVideoStreamHealth
    @Published public private(set) var helperVideoVisualSelectionFailureReason:
        HelperVideoVisualSelectionFailureReason?
    /// Pending remote→local clipboard review.  Set when an incoming
    /// `ServerCutText` payload arrives on the active connection,
    /// cleared on Accept, Dismiss, or profile change.  See
    /// `IncomingClipboardBanner`.
    @Published public private(set) var pendingIncomingClipboard: IncomingClipboardReview?
    /// App-level user preferences not tied to a single
    /// `ConnectionProfile`.  Loaded eagerly in `init` and
    /// re-published when a setting toggle writes through
    /// `settingsPersistence`.  Contains only non-secret viewer
    /// preferences; credentials and target identity never live here.
    @Published public private(set) var appSettings: AppSettings
    /// Frame pixels are intentionally isolated from the app-model
    /// `ObservableObject`. A live desktop frame should invalidate only the
    /// viewport subtree, not the whole shell and input dock on every update.
    public let frameStore: SessionFrameStore

    /// Direct Keystroke Streaming Mode state (the named §I "MAY"
    /// exception per `specs/002-direct-keystroke-mode/spec.md`).
    /// Resets on every disconnect / fresh connect / profile change
    /// per FR-014 — Direct mode never persists across sessions or
    /// app launches.
    @Published public private(set) var directKeystrokeMode: DirectKeystrokeMode = .init()

    /// Sticky-modifier state for the Direct Keystroke special-keys
    /// page (Ctrl / Shift / Alt / Cmd).  Each slot is independently
    /// `idle | armed | locked` per `StickyModifiers`.
    /// Resets in lockstep with `directKeystrokeMode` — disconnect,
    /// fresh connect, profile change, and `toggleDirectKeystrokeMode`
    /// off all clear the state (FR-012).
    @Published public private(set) var stickyModifierState: StickyModifiers = .init()

    /// Live type-through mode state (spec 009 / spec 011). Peer to
    /// `directKeystrokeMode`; resets on every fresh session (FR-016)
    /// and seals on the FR-011 transitions. Spec 011 promotes Type
    /// (= Live type-through) to the default dock mode on session
    /// activation, so this starts `isActive` when the first frame of a
    /// fresh session lands unless the user already picked a mode.
    @Published public private(set) var liveTypeThroughMode: LiveTypeThroughMode = .init()

    /// Whether the Type (type-through) default has been applied for the
    /// current session (spec 011 US1). One-shot per session activation so
    /// later frames / reconnects inside the same session never flip the
    /// user's explicit mode choice.
    private var hasAppliedTypeThroughDefaultForCurrentSession = false

    /// Whether the user explicitly chose a dock mode for the current
    /// session (spec 011 US1). Suppresses the one-shot Type default when
    /// the session activates.
    private var hasUserSelectedDockModeThisSession = false

    /// Authoritative local mirror of the current Live editing line
    /// (spec 009). The dock editor renders from this in Live mode; the
    /// model clears it on a sealed/committed line so the next line starts
    /// clean. Memory-only, never exported (SP-002).
    @Published public private(set) var liveFieldText: String = ""

    /// How many ⌫ taps this session fell through to a plain remote
    /// `BackSpace` because the Live window had nothing of its own left to
    /// un-type (spec 035 FR-007). A count only — never what was deleted
    /// (constitution §IV). Reset with the rest of the Live state on a fresh
    /// session; asking a session for this is how "the mirror was behind"
    /// becomes a number instead of a guess.
    public private(set) var liveBackspacePassThroughCount: Int = 0

    /// The in-memory reconciliation mirror for the open Live editing
    /// window (spec 009 `LiveEditingWindow`). Pure value type; sealed and
    /// discarded on the FR-011 events. Raw delivered text is process-local
    /// and never persisted or exported (SP-002).
    private var liveWindow = LiveTypeThroughWindow()

    /// Whether a Live delivery chunk is in flight. Single-in-flight per
    /// window (FR-008): while set, further commits coalesce into the
    /// window's pending buffer and drain when the chunk completes.
    private var liveChunkInFlight = false

    /// Waiters for spec 012 US2-3: strip/quick-key emission waits for
    /// the current helper/clipboard insert to finish, then emits or
    /// drops. Resumed from `completeLiveInsert` / live-state reset.
    private var liveInsertFlushWaiters: [CheckedContinuation<Bool, Never>] = []

    /// `liveWindow.deliveredText` as it was immediately before the in-flight
    /// chunk's optimistic `takePending()` fold. On a failed async delivery the
    /// window is rolled back to this baseline so the failed chunk re-enters the
    /// retained tail instead of silently vanishing (FR-015).
    private var liveInFlightBaseline: String?

    /// Coarse connection-quality bucket (Good / Fair / Poor) derived
    /// from frame round-trip latency while a session is active
    /// (spec 003 US4 / FR-012).  `.unknown` until the first frame's
    /// latency is sampled; reset on disconnect / fresh connect.
    /// Constitution §IV: only the bucket is published — the underlying
    /// latency value is never persisted, logged, or exported.
    @Published public private(set) var connectionQuality: ConnectionQuality = .unknown

    /// How a one-finger gesture on the remote screen is interpreted
    /// (spec 003 US3 / T014).  `.directTouch` preserves tap-where-you-
    /// touch; `.trackpad` is Google-Remote-Desktop-style relative
    /// cursor control.  Reset to `.productDefault` on every disconnect /
    /// fresh connect / profile change so the mode never leaks across
    /// sessions.  Constitution §I: switching modes is a LOCAL transform
    /// only — no RFB PointerEvent is emitted by the toggle itself.
    @Published public private(set) var pointerControlMode: PointerControlMode = .productDefault

    /// Cursor position for trackpad mode, in remote framebuffer pixels.
    /// Hidden in direct-touch mode and reset on every
    /// disconnect / fresh connect / profile change.  Constitution §IV:
    /// the cursor position is published for the overlay but never
    /// logged, persisted, or exported.
    /// Viewport-local mirror for SwiftUI overlays. New UI that needs cursor
    /// samples should observe this store directly instead of the app model.
    public let trackpadCursorStore: TrackpadCursorStore
    public var trackpadCursor: TrackpadCursor {
        trackpadCursorStore.cursor
    }

    /// Rolling estimator smoothing per-frame round-trip latency into
    /// `connectionQuality` so a single slow frame does not flip the
    /// indicator.  Memory-only; reset alongside `connectionQuality`.
    private var connectionQualityEstimator = ConnectionQualityEstimator()
    /// Last quality bucket used to re-advertise adaptive encodings on
    /// the active stream. Memory-only and reset with the quality
    /// estimator so a fresh session starts from the conservative
    /// first-frame profile.
    private var lastAdaptiveEncodingQuality: ConnectionQuality?
    /// Non-blocking `SetEncodings` renegotiation task. The main actor
    /// observes only the coarse quality bucket; the control write runs
    /// off-main so a slow socket cannot freeze the viewer chrome.
    private var adaptiveEncodingRenegotiationTask: Task<Void, Never>?

    private let connectorFactory: @Sendable () -> RFBFirstFrameConnecting
    private let streamConnectorFactory: @Sendable (
        RFBEncodingPreference,
        RFBPixelFormat?
    ) -> RFBFirstFrameConnecting
    private let streamConnectorFactoryAppliesPreferences: Bool
    private let reachabilityProbeTimeout: TimeInterval
    private let reachabilityProbeMaximumConcurrency: Int
    private let frameStreamConfiguration: RFBFramePumpConfiguration
    private let reconnectPolicy: ReconnectPolicy
    private var profileStore: ConnectionProfileStore?
    private let profilePersistenceMutationGate = ProfilePersistenceMutationGate()
    private var profilePreviewStore: (any ProfilePreviewStore)?
    private let credentialStore: ConnectionCredentialStoreProtocol?
    private let settingsPersistence: AppSettingsPersisting?
    private let pipWatchController: (any PiPWatchControlling)?
    private let localClipboardWriter: (any LocalClipboardWriting)?
    private let helperTextInsertClient: (any HelperTextInsertClient)?
    private let helperVideoStartStream: HelperVideoStartStream?
    private let helperVideoOpenStream: HelperVideoOpenStream?
    private let helperVideoRendererFactory: HelperVideoRendererFactory?
    private let helperVideoMaxServerFrames: Int
    private let helperVideoStreamOutcomeHandler: HelperVideoStreamOutcomeHandler?
    private let streamStartupPreflightPolicyOverride: SessionStreamStartupPreflightPolicy?
    private let incomingClipboardReceiveTimeout: TimeInterval
    private let thermalStateProvider: @Sendable () -> SessionStreamThermalState
    private let lowPowerModeProvider: @Sendable () -> Bool
    private let hevcDecodeSupportProvider: @Sendable () -> Bool
    private let networkPathConditionsProvider: @Sendable () -> NetworkPathConditions
    /// Test seam for observing app-level pacing decisions without
    /// sleeping in real time. `nil` keeps production cancellation on
    /// the direct `Task.sleep` path.
    private let streamPacingSleepOverride: (@Sendable (TimeInterval) async throws -> Void)?
    /// Test seam for frame-application pacing. Production keeps the direct
    /// worker sleep path; tests can gate the sleep to prove input-aware
    /// cadence is applied before a content frame enters MainActor work.
    private let frameApplicationSleepOverride: (@Sendable (TimeInterval) async throws -> Void)?
    private let allowsAdaptiveEncodingRenegotiation: Bool
    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    public let pipLayerHost: PiPLayerHost
    /// Automatic PiP framing (spec 034). Reset whenever a session or the mode
    /// changes, so a new session never inherits the last one's framing.
    public let helperVideoLayerHost: HelperVideoLayerHost
    #endif
    private var activeTextClient: RemoteClipboardTextClient?
    private var activePointerClient: RFBPointerEventClient?
    private var activeFramebufferUpdateRequestSender: (any RFBFramebufferUpdateRequestSending)?
    /// Capability-protocol view of the active streaming client that
    /// owns RFB `KeyEvent` emission (RFC 6143 §7.5.4).  Set in
    /// lockstep with `activeTextClient` and `activePointerClient`
    /// at every connect site; cleared at every disconnect /
    /// profile-change / error path.  `KeystrokeEmitter` below holds
    /// a strong reference for the duration of the active session.
    private var activeKeyEventClient: (any RFBKeyEventClient)?
    /// Direct-mode keystroke emitter bound to
    /// `activeKeyEventClient`.  Rebuilt on every fresh connect so
    /// stale references from a previous session cannot leak into a
    /// new one.  `nil` outside an active session — `tapDirectKey(_:)`
    /// drops emissions silently when there is no emitter (matches
    /// `spec.md` IN-003 "drop silently when not `.active`").
    private var keystrokeEmitter: KeystrokeEmitter?
    /// Last `(x, y)` coordinate that `sendPointerMoveTo(...)` actually
    /// emitted on the wire for the currently active stream.  Used as a
    /// throttle anchor: a subsequent move whose framebuffer-coord delta
    /// from this anchor is `< 1` pixel is suppressed so a single-finger
    /// pan does not flood the wire while the gesture pipeline runs at
    /// the screen refresh rate.  Cleared on connect / disconnect /
    /// profile change so a stale anchor from a previous session can
    /// never suppress the first real move of the next drag.
    private var lastEmittedDragCoord: (x: UInt16, y: UInt16)?
    /// Latest drag-move event waiting for a short coalescing window.
    /// High-refresh touch streams can outpace VNC writes; keeping only
    /// the newest unsent move prevents stale pointer positions from
    /// piling up behind Network.framework back-pressure while down/up
    /// edges remain strictly ordered.
    private var pendingPointerMove: PendingPointerMove?
    private var pointerMoveFlushTask: Task<Void, Never>?
    private var pendingPointerInputFramebufferUpdateNudge: PendingPointerInputFramebufferUpdateNudge?
    private var pointerInputFramebufferUpdateNudgeTask: Task<Void, Never>?
    private var lastPointerInputFramebufferUpdateNudgeAt: Date?
    /// Latest visual trackpad cursor waiting for a frame-sized publish
    /// window. The Metal host applies cursor/auto-pan feedback
    /// immediately; this coalesces SwiftUI overlay state so touch
    /// samples do not rebuild the app chrome faster than the display can
    /// show it.
    private var pendingTrackpadCursor: TrackpadCursor?
    private var trackpadCursorPublishTask: Task<Void, Never>?
    private var resolvedTrackpadCursor: TrackpadCursor = TrackpadCursor()
    /// Direct button-drag keeps a 120 Hz-class wire cadence because the
    /// remote object under the pointer is actively being dragged.
    private static let directPointerMoveCoalescingDelay: Duration = .milliseconds(8)
    /// Trackpad mode has immediate local cursor feedback, so the wire can
    /// stay near display cadence instead of racing touch samples. This keeps
    /// VNC writes from competing with the UIKit/Metal pan loop on iPhone.
    private static let trackpadPointerMoveCoalescingDelay: Duration = .milliseconds(16)
    private static let pointerInputFramebufferUpdateNudgeMinimumInterval: TimeInterval =
        StreamPressurePacingDefaults.transientInputContentFrameIntervalSeconds
    private static let pointerInputFramebufferUpdateNudgeWriteTimeout: TimeInterval = 0.25
    /// Published SwiftUI cursor snapshots are only a mirror; the Metal
    /// host paints the hot cursor immediately from the gesture result.
    private static let trackpadCursorPublishDelay: Duration = .milliseconds(16)
    /// Owns pointer wire serialization outside MainActor. Pointer move/drag
    /// traffic can be bursty while a user pans or uses trackpad mode, so it
    /// deliberately does not share a queue with keystrokes.
    private let pointerInputDispatcher: OutboundInputEventDispatcher
    /// Owns key wire serialization outside MainActor. Keyboard input must
    /// remain responsive even when pointer movement is backlogged or times out.
    private let keyInputDispatcher: OutboundInputEventDispatcher
    private var activeFramePump: RFBFramePump?
    private var activeFrameStreamTask: Task<Void, Never>?
    private var activeFrameApplicationTask: Task<Void, Never>?
    private var activeFrameApplicationQueue: SessionStreamFrameApplicationQueue?
    private var activeFrameStreamID: UUID?
    private var mainActorResponsivenessTask: Task<Void, Never>?
    private var mainActorResponsivenessMonitorID: UUID?
    private var activeHelperVideoStreamTask: Task<Void, Never>?
    private var activeHelperVideoStreamID: UUID?
    private var frameDeliveryInteractionReasons: Set<FrameDeliveryInteractionReason> = []
    private var transientFrameDeliveryInteractionTask: Task<Void, Never>?
    private var transientFrameDeliveryInteractionExpiresAt: ContinuousClock.Instant?
    private var streamPacingWakeGeneration: UInt64 = 0
    private var pendingFocusedInputConnectionQuality: ConnectionQuality?
    private var pendingFocusedInputHelperVideoHealth: HelperVideoStreamHealth?
    private var pendingFocusedInputIncomingClipboard: IncomingClipboardReview?
    private var isFocusedInputSendFeedbackClearPending = false
    private var viewportInteractionFrameStrategy: ViewportInteractionFrameStrategy?
    private var isViewportInteractionActive: Bool {
        viewportInteractionFrameStrategy != nil
    }
    private var latestViewportTransform: ViewportTransform?
    private var latestViewportSize: CGSize?
    private let viewportRequestRegionPolicy = ViewportRequestRegionPolicy(
        fullHeartbeatInterval: 10,
        fullFallbackTimeoutStreak: 0
    )
    private var appleServerDownscalePolicy = AppleServerDownscalePolicy()
    private var appliedServerDownscaleRung: Double = AppleServerDownscalePolicy.fullRung
    private var viewportDisplayPixelsPerPoint: CGFloat?
    /// Last framebuffer width known to be UNSCALED — the pointer input
    /// space screensharingd keeps while ScaleFactor is applied
    /// (live-measured 2026-08-20). Maintained by
    /// `pointerBatchMappedForServerDownscale` via the pure shape detector
    /// in `AppleServerDownscalePolicy.pointerCoordinateMapping`.
    private var serverDownscaleUnscaledFramebufferWidth: Int?
    private var deferredViewportInteractionFrame: DeferredViewportInteractionFrame?
    private var lastViewportInteractionFramePublishedAt: Date?
    private var viewportInteractionStartedAt: Date?
    private var activeIncomingClipboardTask: Task<Void, Never>?
    /// Last profile + credential pair we successfully started a
    /// streaming session against.  Captured at stream start so an
    /// auto-reconnect cycle can restart with the SAME profile and
    /// credentialRef without prompting the user again.  Cleared on
    /// user-initiated disconnect, profile change, and exhaustion.
    private var activeStreamProfile: ConnectionProfile?
    private var activeStreamCredential: RFBConnectionCredential?
    /// Number of consecutive reconnect attempts that have started in
    /// the current "drop" window.  Reset to `0` once a fresh frame
    /// arrives post-reconnect (see `applyStreamFrame`).
    private var reconnectAttempts: Int = 0
    /// Pending reconnect sleep + restart task.  Holding the handle
    /// lets profile change / `disconnect()` cancel the wait so a
    /// dropped session does not "wake up" against a stale profile.
    private var pendingReconnectTask: Task<Void, Never>?
    /// Set by `disconnect()` (and by no other path).  When `true`,
    /// `handleStreamFailure` skips reconnect scheduling entirely so
    /// the user's explicit teardown is honored.  Reset by every
    /// fresh user-initiated `connectSelectedProfile()`.
    ///
    /// Exposed `internal` (read-only) so `@testable` tests can assert
    /// that user-initiated disconnect latched the no-auto-reconnect
    /// guard without poking private state via reflection.  External
    /// callers cannot mutate this flag — the only setters remain
    /// `disconnect()` and `connectSelectedProfile()`.
    internal private(set) var explicitlyDisconnected: Bool = false
    private var lastPreviewPublishAt: [ConnectionProfile.ID: Date] = [:]
    private var lastPreviewSaveAt: [ConnectionProfile.ID: Date] = [:]
    private static let previewPublishMinimumInterval: TimeInterval = 1
    private static let previewSaveMinimumInterval: TimeInterval = 5
    private static let mainActorResponsivenessProbeIntervalSeconds: TimeInterval = 0.25
    static let transientFrameDeliveryInteractionPriorityDuration: Duration = .milliseconds(150)
    // Wake granularity while a pacing delay is pending. Kept near one
    // display refresh so an input nudge (pointer/keystroke) re-arms the
    // request loop within a frame instead of waiting up to a coarse poll.
    private static let streamPacingWakePollIntervalSeconds: TimeInterval = 1.0 / 60.0
    // Active content-frame request backpressure. `0` = "request the next
    // frame as fast as the round-trip + decode allow" — the fluid
    // macOS-Screen-Sharing-like path. The application worker
    // (`SessionFrameApplicationWorkerPacing`) is the single rate
    // authority that caps how often decoded frames are *applied*, so the
    // request loop no longer needs its own steady-state floor; stacking a
    // second cap here only added latency. Thermal/pressure pacing can
    // still raise this dynamically.
    public static let defaultActiveFrameInterval: TimeInterval = 0
    public static let defaultIdleFrameInterval: TimeInterval = 0.05
    public static let defaultFrameStreamConfiguration = RFBFramePumpConfiguration(
        requestTimeout: 8,
        // RFB is demand-driven, so this is the app's default active
        // request backpressure. Thermal floors can still raise it.
        frameInterval: defaultActiveFrameInterval,
        // Static screens should not busy-loop empty incremental requests.
        idleFrameInterval: defaultIdleFrameInterval,
        // Opportunistic only: the pump stays on request/response until
        // adaptive SetEncodings advertises ContinuousUpdates and the
        // transport reports that message 150 is safe for this session.
        updateMode: .continuousUpdates,
        // When ContinuousUpdates is unavailable (e.g. Apple Screen
        // Sharing), keep 3 incremental requests parked on the server so it
        // never idles during the request→response round-trip. Ignored once
        // ContinuousUpdates negotiates (that transport already decouples
        // request/response).
        //
        // The numbers this used to cite (depth 1 → 3.2 content fps, depth 3 →
        // 5.2) came from a debug-built benchmark, and debug ZRLE decode
        // dominates everything downstream of it — see spec 025. Re-measured
        // 2026-08-21 with a release build, eight 15 s runs per arm against live
        // Screen Sharing under an identical stimulus: depth 1 median 7.7
        // content fps (range 5.1–11.6), depth 3 median 8.6 (range 5.3–10.9),
        // update latency 31 ms average in both. The ranges overlap completely
        // and depth 1 wins 41% of pairwise comparisons, so **depth makes no
        // measurable difference here**. 3 is kept because it is what has
        // shipped and it is not worse; a single-run difference in either
        // direction is noise and is not grounds to change it.
        requestPipelineDepth: 3
    )
    private var reachabilityProbeTask: Task<Void, Never>?
    private var reachabilityProbeGeneration = UUID()
    private var helperTextBridgeProbeTask: Task<Void, Never>?
    private var helperTextBridgeProbeGeneration = UUID()
    @Published public private(set) var profilePersistenceError: String?
    /// Most recent `AppSettingsPersisting` failure, if any.  We do
    /// not crash on settings persistence errors — settings are
    /// non-critical and a stale in-memory `appSettings` is still
    /// safe to use until the next launch.  See ROADMAP Phase 7.
    @Published public private(set) var settingsPersistenceError: String?
    private var hasScheduledActiveDiagnosticExportForTesting = false
    private var activeDiagnosticExportTaskForTesting: Task<Void, Never>?

    public init(
        snapshot: NaruRemoteAppSnapshot = NaruRemoteAppSnapshot(),
        profileStore: ConnectionProfileStore? = nil,
        profilePreviewStore: (any ProfilePreviewStore)? = nil,
        credentialStore: ConnectionCredentialStoreProtocol? = nil,
        settingsPersistence: AppSettingsPersisting? = nil,
        frameStreamConfiguration: RFBFramePumpConfiguration = NaruRemoteAppModel.defaultFrameStreamConfiguration,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        connectorFactory: (@Sendable () -> RFBFirstFrameConnecting)? = nil,
        streamConnectorFactory: (@Sendable (
            RFBEncodingPreference,
            RFBPixelFormat?
        ) -> RFBFirstFrameConnecting)? = nil,
        reachabilityProbeTimeout: TimeInterval = 2,
        reachabilityProbeMaximumConcurrency: Int = 2,
        pipWatchController: (any PiPWatchControlling)? = nil,
        localClipboardWriter: (any LocalClipboardWriting)? = nil,
        helperTextInsertClient: (any HelperTextInsertClient)? = nil,
        helperVideoStartStream: HelperVideoStartStream? = nil,
        helperVideoOpenStream: HelperVideoOpenStream? = nil,
        helperVideoRendererFactory: HelperVideoRendererFactory? = nil,
        helperVideoMaxServerFrames: Int = 16,
        helperVideoStreamOutcomeHandler: HelperVideoStreamOutcomeHandler? = nil,
        streamStartupPreflightPolicy: SessionStreamStartupPreflightPolicy? = nil,
        incomingClipboardReceiveTimeout: TimeInterval = 30,
        thermalStateProvider: @escaping @Sendable () -> SessionStreamThermalState = {
            SessionStreamThermalState(ProcessInfo.processInfo.thermalState)
        },
        lowPowerModeProvider: @escaping @Sendable () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        },
        hevcDecodeSupportProvider: @escaping @Sendable () -> Bool = {
            #if canImport(VideoToolbox)
            VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
            #else
            false
            #endif
        },
        networkPathConditionsProvider: @escaping @Sendable () -> NetworkPathConditions = {
            NetworkPathConditionsMonitor.shared.current
        },
        streamPacingSleep: (@Sendable (TimeInterval) async throws -> Void)? = nil,
        frameApplicationSleep: (@Sendable (TimeInterval) async throws -> Void)? = nil,
        outboundInputEventTimeout: Duration = .milliseconds(2_500),
        allowsAdaptiveEncodingRenegotiation: Bool = false
    ) {
        // Profiles are no longer loaded synchronously from
        // `profileStore` here — the store is now an `actor`, so its
        // `allProfiles()` call is async.  Callers that want disk-backed
        // profiles must invoke `loadStoredProfiles()` after
        // construction (the iOS shell does this in a `.task` modifier).
        let initialProfiles = snapshot.profiles

        // Settings are non-critical and are no longer loaded
        // synchronously from `settingsPersistence` here — the
        // in-memory persistence is now an `actor`, so its `load()`
        // call is async (mirroring the profile store migration in
        // PR #17).  Callers that want disk-backed settings must
        // invoke `loadStoredSettings()` after construction (the iOS
        // shell does this in a `.task` modifier).  In the interim
        // the model uses defaults; that's the same behavior as the
        // no-persistence path, so existing snapshot/preview entry
        // points keep working.
        self.profiles = initialProfiles
        self.selectedProfileID = snapshot.selectedProfileID ?? initialProfiles.first?.id
        self.session = snapshot.session
        self.diagnosticRun = snapshot.diagnosticRun
        self.lastDiagnosticVerdict = snapshot.lastDiagnosticVerdict
        self.composeDraft = snapshot.composeDraft
        self.latestInjectionAttempt = snapshot.latestInjectionAttempt
        self.pipWatchSession = snapshot.pipWatchSession
        self.latestFramebuffer = snapshot.latestFramebuffer
        self.inputCoordinateSpace = snapshot.inputCoordinateSpace
        self.latestFrameDirtyRectangles = snapshot.latestFrameDirtyRectangles
        self.latestFrameChangedPixelCount = snapshot.latestFrameChangedPixelCount
        self.sessionStreamStats = snapshot.sessionStreamStats
        self.latestServerCursor = snapshot.latestServerCursor
        // The Live dock state was on the snapshot and silently dropped here, so
        // no fixture could put the app in Type mode with a delivery tier
        // chosen. That is a large part of why `KeyboardUpDockHeightUITests`
        // measured a one-row dock while the founder's device showed three
        // (spec 035 FR-005): the configuration that grows the dock was
        // unreachable. Both fields default to inactive/empty, so adopting them
        // changes nothing for any caller that does not set them.
        self.liveTypeThroughMode = snapshot.liveTypeThroughMode
        self.liveFieldText = snapshot.liveFieldText
        self.frameStore = SessionFrameStore(
            state: SessionFrameState(
                framebuffer: snapshot.latestFramebuffer,
                dirtyRectangles: snapshot.latestFrameDirtyRectangles,
                changedPixelCount: snapshot.latestFrameChangedPixelCount,
                serverCursor: snapshot.latestServerCursor
            )
        )
        self.trackpadCursorStore = TrackpadCursorStore()
        self.profilePreviews = snapshot.profilePreviews
        self.profileReachability = snapshot.profileReachability
        self.helperTextBridgeState = snapshot.helperTextBridgeState
        self.visualTransportMode = snapshot.visualTransportMode
        self.helperVideoProfileState = snapshot.helperVideoProfileState
        self.helperVideoStreamDescriptor = snapshot.helperVideoStreamDescriptor
        self.helperVideoStreamHealth = snapshot.helperVideoStreamHealth
        self.helperVideoVisualSelectionFailureReason = snapshot.helperVideoVisualSelectionFailureReason
        self.appSettings = AppSettings()
        self.settingsPersistenceError = nil
        self.profileStore = profileStore
        self.profilePreviewStore = profilePreviewStore
        self.credentialStore = credentialStore
        self.settingsPersistence = settingsPersistence
        self.frameStreamConfiguration = frameStreamConfiguration
        self.reconnectPolicy = reconnectPolicy
        let firstFrameConnectorFactory = connectorFactory ?? {
            RFBNetworkClient()
        }
        self.connectorFactory = firstFrameConnectorFactory
        if let streamConnectorFactory {
            self.streamConnectorFactory = streamConnectorFactory
            self.streamConnectorFactoryAppliesPreferences = true
        } else if let connectorFactory {
            self.streamConnectorFactory = { _, _ in
                connectorFactory()
            }
            self.streamConnectorFactoryAppliesPreferences = false
        } else {
            self.streamConnectorFactory = { encodingPreference, pixelFormatPreference in
                RFBNetworkClient(
                    encodingPreference: encodingPreference,
                    pixelFormatPreference: pixelFormatPreference
                )
            }
            self.streamConnectorFactoryAppliesPreferences = true
        }
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        let defaultHelperVideoLayerHost = HelperVideoLayerHost()
        #endif
        self.reachabilityProbeTimeout = reachabilityProbeTimeout
        self.reachabilityProbeMaximumConcurrency = max(1, reachabilityProbeMaximumConcurrency)
        self.pipWatchController = pipWatchController
        self.localClipboardWriter = localClipboardWriter
        self.helperTextInsertClient = helperTextInsertClient
        self.helperVideoStartStream = helperVideoStartStream ?? Self.defaultHelperVideoStartStream()
        self.helperVideoOpenStream = helperVideoOpenStream
            ?? (helperVideoStartStream == nil ? Self.defaultHelperVideoOpenStream() : nil)
        self.helperVideoMaxServerFrames = max(helperVideoMaxServerFrames, 1)
        self.helperVideoStreamOutcomeHandler = helperVideoStreamOutcomeHandler
        if let helperVideoRendererFactory {
            self.helperVideoRendererFactory = helperVideoRendererFactory
        } else {
            #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
            self.helperVideoRendererFactory = {
                defaultHelperVideoLayerHost.renderer
            }
            #else
            self.helperVideoRendererFactory = nil
            #endif
        }
        self.streamStartupPreflightPolicyOverride = streamStartupPreflightPolicy
        self.incomingClipboardReceiveTimeout = incomingClipboardReceiveTimeout
        self.thermalStateProvider = thermalStateProvider
        self.lowPowerModeProvider = lowPowerModeProvider
        self.hevcDecodeSupportProvider = hevcDecodeSupportProvider
        self.networkPathConditionsProvider = networkPathConditionsProvider
        self.streamPacingSleepOverride = streamPacingSleep
        self.frameApplicationSleepOverride = frameApplicationSleep
        self.pointerInputDispatcher = OutboundInputEventDispatcher(
            timeout: outboundInputEventTimeout
        )
        self.keyInputDispatcher = OutboundInputEventDispatcher(
            timeout: outboundInputEventTimeout
        )
        self.allowsAdaptiveEncodingRenegotiation = allowsAdaptiveEncodingRenegotiation
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        self.pipLayerHost = PiPLayerHost()
        self.helperVideoLayerHost = defaultHelperVideoLayerHost
        #endif
    }

    private static func defaultHelperVideoStartStream() -> HelperVideoStartStream? {
        #if canImport(Network)
        return { profile, pairingSecret, pairingFingerprint, requestBody, maxServerFrames in
            let client = HelperVideoStreamNetworkClient(
                host: profile.host,
                port: UInt16(naruHelperVideoStreamDefaultPort),
                profileFingerprint: pairingFingerprint,
                pairingSecret: pairingSecret,
                transportProtection: .authenticatedPrivateProfile
            )
            return try await client.startStream(requestBody, maxServerFrames: maxServerFrames)
        }
        #else
        return nil
        #endif
    }

    private static func defaultHelperVideoOpenStream() -> HelperVideoOpenStream? {
        #if canImport(Network)
        return { profile, pairingSecret, pairingFingerprint, requestBody in
            let client = HelperVideoStreamNetworkClient(
                host: profile.host,
                port: UInt16(naruHelperVideoStreamDefaultPort),
                profileFingerprint: pairingFingerprint,
                pairingSecret: pairingSecret,
                transportProtection: .authenticatedPrivateProfile
            )
            return client.streamEvents(requestBody)
        }
        #else
        return nil
        #endif
    }

    /// Late-attach a `ConnectionProfileStore` after construction.
    /// The iOS shell uses this because the store's initializer is
    /// `async` (its persistence layer is now an `actor`) but the
    /// `@StateObject` factory that constructs the model is sync.
    /// Attaching a second store is a no-op so a stray double-attach
    /// from a flaky simulator launch cannot replace the live store.
    public func attachProfileStore(_ store: ConnectionProfileStore) async {
        guard profileStore == nil else {
            return
        }
        profileStore = store
        await loadStoredProfiles()
    }

    /// Loads disk-backed profiles from the injected
    /// `ConnectionProfileStore` and merges them into the model state.
    /// Called from the iOS shell's `.task` modifier on first appear so
    /// startup is non-blocking.  No-op if no `profileStore` was
    /// injected, if a snapshot's profiles are already populated, or if
    /// the user has already started adding profiles in this session.
    public func loadStoredProfiles() async {
        guard let profileStore else {
            return
        }
        guard profiles.isEmpty else {
            return
        }
        let storedProfiles = await profileStore.allProfiles()
        guard !storedProfiles.isEmpty else {
            return
        }
        // Re-check: a fast user could have added a profile while we
        // were awaiting the store.  Don't clobber that.
        guard profiles.isEmpty else {
            return
        }
        profiles = storedProfiles
        for profile in storedProfiles {
            publishInitialHelperTextBridgeState(for: profile)
            publishInitialHelperVideoState(for: profile)
        }
        if selectedProfileID == nil {
            selectedProfileID = storedProfiles.first?.id
        }
        await loadStoredProfilePreviews()
        refreshProfileReachability()
    }

    public func attachProfilePreviewStore(_ store: any ProfilePreviewStore) async {
        guard profilePreviewStore == nil else {
            return
        }
        profilePreviewStore = store
        await loadStoredProfilePreviews()
    }

    public func loadStoredProfilePreviews() async {
        guard let profilePreviewStore else {
            return
        }
        let profileIDs = Set(profiles.map(\.id))
        guard !profileIDs.isEmpty else {
            profilePreviews = [:]
            return
        }

        var loadedPreviews: [ConnectionProfile.ID: ProfilePreviewThumbnail] = [:]
        for profileID in profileIDs {
            if let thumbnail = try? await profilePreviewStore.loadThumbnail(for: profileID) {
                loadedPreviews[profileID] = thumbnail
            }
        }

        profilePreviews = profilePreviews
            .filter { profileIDs.contains($0.key) }
            .merging(loadedPreviews) { _, loaded in loaded }
    }

    public func refreshProfileReachability() {
        startReachabilityProbes(for: profiles)
        startHelperTextBridgeProbes(for: profiles)
    }

    /// Loads disk-backed `AppSettings` from the injected
    /// `AppSettingsPersisting` and merges them into the model
    /// state.  Mirrors `loadStoredProfiles()`: called from the iOS
    /// shell's `.task` modifier on first appear so startup is
    /// non-blocking.  A load failure surfaces through
    /// `settingsPersistenceError` rather than being thrown — settings
    /// are non-critical and a stale in-memory `appSettings` is still
    /// safe to use until the next launch (see ROADMAP Phase 7).
    /// No-op if no `settingsPersistence` was injected or if the
    /// user has already toggled a setting in this session.
    public func loadStoredSettings() async {
        guard !Self.testSkipsSettingsStoreLoad() else {
            return
        }
        guard let settingsPersistence else {
            return
        }
        // If the user has already toggled a setting in this session
        // (e.g. dismissed the onboarding checklist) before the
        // background load finishes, do not clobber that with whatever
        // was on disk at launch.
        guard appSettings == AppSettings() else {
            return
        }

        do {
            let loaded = try await settingsPersistence.load()
            guard appSettings == AppSettings() else {
                return
            }
            appSettings = loaded
            settingsPersistenceError = nil
        } catch {
            settingsPersistenceError = "Settings could not be loaded on this device."
        }
    }

    public func setStreamPowerMode(_ mode: StreamPowerMode) {
        var updated = appSettings
        updated.streamPowerMode = mode
        guard updated != appSettings else {
            return
        }

        appSettings = updated
        persistAppSettings(updated)
    }

    public func toggleStreamPowerMode() {
        setStreamPowerMode(appSettings.streamPowerMode.toggled)
    }

    public func setComposeDeliveryMode(_ mode: ComposeDeliveryMode) {
        var updated = appSettings
        updated.composeDelivery = mode
        guard updated != appSettings else {
            return
        }

        appSettings = updated
        persistAppSettings(updated)
    }

    public func toggleComposeDeliveryMode() {
        setComposeDeliveryMode(appSettings.composeDelivery.toggled)
    }

    // MARK: - PiP framing (spec 034)

    /// What PiP frames on. Persisted, because it is a preference; the region
    /// `chosenRegion` refers to is not, because it names a place on one
    /// desktop layout (FR-006).
    public var pipFramingMode: PiPFramingMode {
        appSettings.pipFramingMode
    }

    public func setPiPFramingMode(_ mode: PiPFramingMode) {
        var updated = appSettings
        updated.pipFramingMode = mode
        guard updated != appSettings else {
            return
        }

        appSettings = updated
        persistAppSettings(updated)
        applyPiPFramingForActiveWatch()
    }

    /// The mode that will actually be used.
    ///
    /// The mode is persisted and the region is not, so a user who drew a region
    /// yesterday relaunches into `chosenRegion` with nothing to frame. That
    /// behaves as `currentView`, and the menu has to say `currentView` — the
    /// first capture of the framing menu showed no selection at all, which is
    /// how this was found.
    public var effectivePiPFramingMode: PiPFramingMode {
        if appSettings.pipFramingMode == .chosenRegion, pipChosenRegion == nil {
            return .currentView
        }
        return appSettings.pipFramingMode
    }

    /// The region the user drew, this session. Nil means none drawn yet, in
    /// which case `chosenRegion` behaves like `currentView`.
    @Published public private(set) var pipChosenRegion: PiPFramingTarget?

    /// Was PiP up when the region picker opened? (spec 038 FR-007)
    @Published public private(set) var pipResumesAfterRegionChoice = false

    /// Opens the region picker, closing the PiP window first if one is up.
    ///
    /// While PiP watches, the in-app viewport draws through the very
    /// `AVSampleBufferDisplayLayer` the system has taken for the floating
    /// window, so the in-app copy is blank — and "Choose region…" dropped the
    /// user onto a picker over an empty screen with nothing to aim at. Closing
    /// the window gives the picture back.
    ///
    /// It is also the only way the choice can take effect: framing is imposed
    /// at entry because PiP is watch-only, so a region chosen while a window is
    /// already open would not have been applied to it anyway.
    public func beginChoosingPiPRegion() {
        pipResumesAfterRegionChoice = isPiPWatchEngaged
        guard pipResumesAfterRegionChoice else {
            return
        }
        stopPiPWatch()
    }

    /// Closes the picker and re-opens PiP if this call closed it — with
    /// whatever framing is now selected, which for a completed pick is the
    /// region just drawn.
    public func endChoosingPiPRegion() {
        guard pipResumesAfterRegionChoice else {
            return
        }
        pipResumesAfterRegionChoice = false
        startPiPWatch()
    }

    public func setPiPChosenRegion(_ region: PiPFramingTarget?) {
        pipChosenRegion = region
        guard region != nil else {
            return
        }
        applyPiPFramingForActiveWatch()
    }

    // MARK: - PiP automatic entry (spec 036)

    /// Does leaving the app open the floating window by itself (FR-005)?
    ///
    /// An app cannot send itself to the background, so a button that tries to
    /// is the wrong shape for what was asked. This is the platform's own
    /// answer, and it makes the gesture the trigger.
    public var pipEntersOnLeavingApp: Bool {
        appSettings.pipEntersOnLeavingApp
    }

    public func setPiPEntersOnLeavingApp(_ enabled: Bool) {
        var updated = appSettings
        updated.pipEntersOnLeavingApp = enabled
        guard updated != appSettings else {
            return
        }

        appSettings = updated
        persistAppSettings(updated)
        refreshPiPAutomaticEntry()
    }

    // MARK: - Screen wake (spec 039)

    /// Does an open connection hold off auto-lock (FR-003)?
    public var keepsScreenAwakeDuringSession: Bool {
        appSettings.keepsScreenAwakeDuringSession
    }

    public func setKeepsScreenAwakeDuringSession(_ enabled: Bool) {
        var updated = appSettings
        updated.keepsScreenAwakeDuringSession = enabled
        guard updated != appSettings else {
            return
        }

        appSettings = updated
        persistAppSettings(updated)
    }

    /// The one answer, derived — never assigned.
    ///
    /// `isAppForeground` is the caller's, because the scene phase belongs to
    /// the scene; everything else the model already knows. Exposed as a
    /// function rather than folded into the applier so `swift test` can pin
    /// the decision for every session state without a UIKit application.
    public func screenWakeResolution(isAppForeground: Bool) -> ScreenWakeResolution {
        ScreenWakePolicy.resolve(
            sessionState: session?.state,
            hasFramebuffer: latestFramebuffer != nil,
            isAppForeground: isAppForeground,
            userKeepsScreenAwake: appSettings.keepsScreenAwakeDuringSession
        )
    }

    /// Keeps a live session's PiP controller built and its automatic-entry
    /// policy current (FR-002/FR-004).
    ///
    /// Preparation used to happen inside `startPiPWatch`, so before the first
    /// tap there was no controller at all — and with no controller there is
    /// nothing for the system to start automatically when the app leaves the
    /// foreground. Idempotent per layer host (spec 032 FR-001): this changes
    /// when preparation happens, not how many controllers exist.
    public func refreshPiPAutomaticEntry() {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        guard let pipWatchController, pipWatchController.isSupported else {
            return
        }
        guard canStartPiPWatch || isPiPWatchEngaged else {
            return
        }
        guard prepareController(pipWatchController) else {
            return
        }
        if let automatic = pipWatchController as? any PiPWatchAutomaticEntryControlling {
            automatic.setStartsAutomaticallyFromInline(appSettings.pipEntersOnLeavingApp)
        }
        #endif
    }

    /// Single entry point the Compose & Send UI calls. Routes the finished
    /// draft through the user-selected delivery transport (Settings →
    /// Compose delivery): keystroke-stream (default — Unicode-keysym
    /// type-through, the verified multilingual path on macOS Screen Sharing)
    /// or clipboard-paste (only reliable where the server negotiated UTF-8
    /// clipboard; Korean/CJK auto-falls back to keystroke otherwise).
    public func sendComposedTextUsingPreferredDelivery(
        _ text: String,
        submittingWithReturn: Bool = false
    ) {
        // Spec 015 v1.1 FR-010: the Compose Send button submits — the draft
        // leaves with a trailing Return. On the keystroke path the transcoder
        // turns it into a real Return keypress (0xFF0D); on the clipboard and
        // helper paths it is a trailing newline in the payload, which a
        // terminal executes and a GUI editor renders as a line break.
        let payload = submittingWithReturn
            ? Self.composeSubmitPayload(for: text)
            : text
        switch appSettings.composeDelivery {
        case .clipboardPaste:
            sendComposedText(payload)
        case .keystrokeStream:
            sendComposedTextAsKeystrokes(payload)
        }
    }

    /// One trailing Return, never two: a draft the user already ended with a
    /// newline submits as-is, and an empty draft stays empty so the send
    /// paths keep rejecting it instead of running a bare Enter.
    nonisolated static func composeSubmitPayload(for text: String) -> String {
        guard !text.isEmpty, !text.hasSuffix("\n") else {
            return text
        }
        return text + "\n"
    }

    public func setStreamEncodingMode(_ mode: StreamEncodingMode) {
        var updated = appSettings
        updated.streamEncodingMode = mode
        guard updated != appSettings else {
            return
        }

        appSettings = updated
        persistAppSettings(updated)
    }

    public func toggleStreamEncodingMode() {
        setStreamEncodingMode(appSettings.streamEncodingMode.toggled)
    }

    public func setStartupPreflightMode(_ mode: StreamStartupPreflightMode) {
        var updated = appSettings
        updated.startupPreflightMode = mode
        guard updated != appSettings else {
            return
        }

        appSettings = updated
        persistAppSettings(updated)
    }

    public func toggleStartupPreflightMode() {
        setStartupPreflightMode(appSettings.startupPreflightMode.toggled)
    }

    public func setStartupGlanceScaleMode(_ mode: StreamStartupGlanceScaleMode) {
        var updated = appSettings
        updated.startupGlanceScaleMode = mode
        guard updated != appSettings else {
            return
        }

        appSettings = updated
        persistAppSettings(updated)
    }

    public func toggleStartupGlanceScaleMode() {
        setStartupGlanceScaleMode(appSettings.startupGlanceScaleMode.toggled)
    }

    public var canUseStartupGlanceScaleMode: Bool {
        usesViewportAwareInitialRequestRegion
    }

    /// XCUITest hook for physical-device candidate gates. Unlike the user
    /// setters above, this does not persist to disk; it keeps a launched test
    /// candidate isolated from whichever settings the phone had before.
    public func applyAppSettingsOverrideForTesting(_ settings: AppSettings) {
        appSettings = settings
    }

    /// Settings are non-critical. The in-memory value flips first so
    /// the current session honors the user's choice immediately; disk
    /// failures are surfaced as safe UI state instead of breaking the
    /// active VNC stream.
    private func persistAppSettings(_ settings: AppSettings) {
        guard let settingsPersistence else {
            return
        }

        Task { [weak self, settingsPersistence, settings] in
            do {
                try await settingsPersistence.save(settings)
                await MainActor.run {
                    self?.settingsPersistenceError = nil
                }
            } catch {
                await MainActor.run {
                    self?.settingsPersistenceError = "Settings could not be saved on this device."
                }
            }
        }
    }

    public var snapshot: NaruRemoteAppSnapshot {
        NaruRemoteAppSnapshot(
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            session: session,
            diagnosticRun: diagnosticRun,
            composeDraft: composeDraft,
            latestInjectionAttempt: latestInjectionAttempt,
            pipWatchSession: pipWatchSession,
            latestFramebuffer: latestFramebuffer,
            inputCoordinateSpace: inputCoordinateSpace,
            latestFrameDirtyRectangles: latestFrameDirtyRectangles,
            latestFrameChangedPixelCount: latestFrameChangedPixelCount,
            sessionStreamStats: sessionStreamStats,
            latestServerCursor: latestServerCursor,
            profilePreviews: profilePreviews,
            profileReachability: profileReachability,
            helperTextBridgeState: helperTextBridgeState,
            visualTransportMode: visualTransportMode,
            helperVideoProfileState: helperVideoProfileState,
            helperVideoStreamDescriptor: helperVideoStreamDescriptor,
            helperVideoStreamHealth: helperVideoStreamHealth,
            helperVideoVisualSelectionFailureReason: helperVideoVisualSelectionFailureReason,
            directKeystrokeMode: directKeystrokeMode,
            liveTypeThroughMode: liveTypeThroughMode,
            liveFieldText: liveFieldText,
            stickyModifierState: stickyModifierState,
            isRemoteInputAccessoryPanelExpanded: isRemoteInputAccessoryPanelExpanded,
            lastDiagnosticVerdict: lastDiagnosticVerdict
        )
    }

    public var selectedProfile: ConnectionProfile? {
        snapshot.selectedProfile
    }

    private func helperTextBridgeState(for profileID: ConnectionProfile.ID?) -> HelperTextBridgeProfileState? {
        guard let profileID else {
            return nil
        }
        if let state = helperTextBridgeState[profileID] {
            return state
        }
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            return HelperTextBridgeProfileState()
        }
        return Self.initialHelperTextBridgeState(for: profile)
    }

    private func setHelperTextBridgeState(_ state: HelperTextBridgeProfileState, for profileID: ConnectionProfile.ID) {
        helperTextBridgeState[profileID] = state
    }

    private func helperVideoState(for profileID: ConnectionProfile.ID?) -> HelperVideoProfileState {
        guard let profileID else {
            return HelperVideoProfileState()
        }
        if let state = helperVideoProfileState[profileID] {
            return state
        }
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            return HelperVideoProfileState()
        }
        return Self.initialHelperVideoState(for: profile) ?? HelperVideoProfileState()
    }

    public func setHelperVideoProfileState(
        _ state: HelperVideoProfileState,
        for profileID: ConnectionProfile.ID,
        sessionID: RemoteSession.ID? = nil
    ) {
        if let sessionID {
            guard isCurrentHelperVideoCallback(sessionID: sessionID, profileID: profileID) else {
                return
            }
        }
        helperVideoProfileState[profileID] = state
        guard profileID == session?.profileID,
              visualTransportMode == .helperVideo,
              state.shouldUseVNCVisualFallback
        else {
            return
        }
        fallbackToVNCVisualTransport(
            health: HelperVideoStreamHealth(
                state: .fallbackToVNC,
                fallbackCountBucket: .one
            ),
            profileID: profileID
        )
    }

    @discardableResult
    public func selectHelperVideoVisualTransport(
        descriptor: HelperVideoStreamDescriptor = HelperVideoStreamDescriptor(),
        health: HelperVideoStreamHealth = HelperVideoStreamHealth(state: .starting)
    ) -> Bool {
        if let failureReason = helperVideoVisualSelectionFailureReason(for: health) {
            helperVideoVisualSelectionFailureReason = failureReason
            return false
        }

        helperVideoStreamDescriptor = descriptor
        pendingFocusedInputHelperVideoHealth = nil
        helperVideoStreamHealth = health
        helperVideoVisualSelectionFailureReason = nil
        visualTransportMode = .helperVideo
        return true
    }

    private func helperVideoVisualSelectionFailureReason(
        for health: HelperVideoStreamHealth
    ) -> HelperVideoVisualSelectionFailureReason? {
        guard let activeSession = session else {
            return .noActiveSession
        }
        guard selectedProfileID == activeSession.profileID else {
            return .profileMismatch
        }
        guard activeSession.state.acceptsSessionScopedMediaCallbacks else {
            return .sessionInactive
        }
        guard let activeProfile = profiles.first(where: { $0.id == activeSession.profileID }) else {
            return .helperVideoUnavailable
        }
        guard activeProfile.hostKind != .advancedManualPublicEndpoint else {
            return .privateNetworkRequired
        }
        let profileState = helperVideoState(for: activeSession.profileID)
        guard profileState.canAttemptHelperVideoStream else {
            if profileState.availability == .revoked || profileState.lastFailureCode == .revoked {
                return .helperVideoRevoked
            }
            return .helperVideoUnavailable
        }
        guard !health.shouldUseVNCVisualFallback else {
            return .streamHealthRequiresVNCFallback
        }
        return nil
    }

    public func updateHelperVideoStreamHealth(
        _ health: HelperVideoStreamHealth,
        sessionID: RemoteSession.ID? = nil,
        profileID: ConnectionProfile.ID? = nil
    ) {
        guard isCurrentHelperVideoCallback(sessionID: sessionID, profileID: profileID) else {
            return
        }
        guard health.shouldUseVNCVisualFallback else {
            publishHelperVideoStreamHealth(health)
            return
        }
        fallbackToVNCVisualTransport(
            health: health,
            profileID: session?.profileID ?? selectedProfileID
        )
    }

    private func fallbackToVNCVisualTransport(
        health: HelperVideoStreamHealth,
        profileID: ConnectionProfile.ID?
    ) {
        pendingFocusedInputHelperVideoHealth = nil
        visualTransportMode = .vncFramebuffer
        helperVideoStreamDescriptor = nil
        helperVideoStreamHealth = HelperVideoStreamHealth(
            state: .fallbackToVNC,
            startupBand: health.startupBand,
            sustainedUpdateBand: health.sustainedUpdateBand,
            decodePressure: health.decodePressure,
            fallbackCountBucket: health.fallbackCountBucket == .none ? .one : health.fallbackCountBucket
        )
        helperVideoVisualSelectionFailureReason = .streamHealthRequiresVNCFallback

        guard let profileID else {
            return
        }
        var state = helperVideoProfileState[profileID] ?? HelperVideoProfileState()
        state.lastFailureCode = .fallbackToVNC
        state.lastCheckedBucket = .recent
        helperVideoProfileState[profileID] = state
    }

    private func resetVisualTransportState() {
        pendingFocusedInputHelperVideoHealth = nil
        visualTransportMode = .vncFramebuffer
        helperVideoStreamDescriptor = nil
        helperVideoStreamHealth = HelperVideoStreamHealth()
        helperVideoVisualSelectionFailureReason = nil
    }

    public func disableHelperVideo(for profileID: ConnectionProfile.ID? = nil) async {
        guard let profileID = profileID ?? selectedProfileID else {
            return
        }

        var state = helperVideoState(for: profileID)
        state.isEnabled = false
        state.availability = .disabled
        state.lastFailureCode = .disabled
        state.lastCheckedBucket = .recent
        helperVideoProfileState[profileID] = state
        fallbackHelperVideoVisualOnlyIfActive(
            profileID: profileID,
            reason: .helperVideoUnavailable
        )
        await persistHelperVideoProfilePreference(
            for: profileID,
            isEnabled: false,
            isRevoked: false
        )
    }

    public func revokeHelperVideo(for profileID: ConnectionProfile.ID? = nil) async {
        guard let profileID = profileID ?? selectedProfileID else {
            return
        }

        var state = helperVideoState(for: profileID)
        state.isEnabled = false
        state.pairingFingerprint = nil
        state.availability = .revoked
        state.lastFailureCode = .revoked
        state.lastCheckedBucket = .recent
        helperVideoProfileState[profileID] = state
        fallbackHelperVideoVisualOnlyIfActive(
            profileID: profileID,
            reason: .helperVideoRevoked
        )
        await persistHelperVideoProfilePreference(
            for: profileID,
            isEnabled: false,
            isRevoked: true
        )
    }

    private func persistHelperVideoProfilePreference(
        for profileID: ConnectionProfile.ID,
        isEnabled: Bool,
        isRevoked: Bool
    ) async {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        let existingConfiguration = profiles[index].helperVideo
        var profileToSave = profiles[index]
        profileToSave.helperVideo = HelperVideoConnectionConfiguration(
            isEnabled: isEnabled,
            isRevoked: isRevoked,
            pairingSecretRef: existingConfiguration?.pairingSecretRef,
            pairingFingerprint: existingConfiguration?.pairingFingerprint
                ?? helperVideoProfileState[profileID]?.pairingFingerprint
        )
        profiles[index] = profileToSave

        do {
            try await profileStore?.save(profileToSave)
        } catch {
            profilePersistenceError = "Profile could not be saved on this device."
            return
        }

        if isRevoked,
           let pairingSecretRef = existingConfiguration?.pairingSecretRef {
            do {
                try await credentialStore?.deletePassword(for: pairingSecretRef)
            } catch {
                profilePersistenceError = "Helper video token could not be removed on this device."
            }
        }
    }

    private func fallbackHelperVideoVisualOnlyIfActive(
        profileID: ConnectionProfile.ID,
        reason: HelperVideoVisualSelectionFailureReason
    ) {
        guard profileID == session?.profileID,
              visualTransportMode == .helperVideo
        else {
            return
        }
        pendingFocusedInputHelperVideoHealth = nil
        visualTransportMode = .vncFramebuffer
        helperVideoStreamDescriptor = nil
        helperVideoStreamHealth = HelperVideoStreamHealth(
            state: .fallbackToVNC,
            fallbackCountBucket: .one
        )
        helperVideoVisualSelectionFailureReason = reason
    }

    private func isCurrentHelperVideoCallback(
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) -> Bool {
        if let sessionID {
            guard let currentSession = session,
                  currentSession.id == sessionID,
                  currentSession.state.acceptsSessionScopedMediaCallbacks
            else {
                return false
            }
        }
        if let profileID {
            guard let currentSession = session,
                  currentSession.profileID == profileID,
                  selectedProfileID == profileID
            else {
                return false
            }
        }
        return true
    }

    public func disableHelperTextBridge(for profileID: ConnectionProfile.ID? = nil) {
        guard let profileID = profileID ?? selectedProfileID else {
            return
        }

        var state = helperTextBridgeState[profileID] ?? HelperTextBridgeProfileState()
        state.isEnabled = false
        state.availability = .disabled
        state.lastFailureCode = .disabled
        state.lastCheckedBucket = .recent
        state.capabilitySummary = nil
        helperTextBridgeState[profileID] = state
    }

    public func revokeHelperTextBridge(for profileID: ConnectionProfile.ID? = nil) {
        guard let profileID = profileID ?? selectedProfileID else {
            return
        }

        var state = helperTextBridgeState[profileID] ?? HelperTextBridgeProfileState()
        state.isEnabled = false
        state.pairingFingerprint = nil
        state.availability = .revoked
        state.lastFailureCode = .revoked
        state.lastCheckedBucket = .recent
        state.capabilitySummary = nil
        helperTextBridgeState[profileID] = state
    }

    public var canStartPiPWatch: Bool {
        #if DEBUG
        // Screenshot/UITest hook. `isPictureInPictureSupported()` is false on
        // the simulator (spec 032), so without this the PiP control and its
        // framing menu cannot be captured or driven on any runner here. It
        // relaxes only *availability of the affordance* — starting still goes
        // through the same unsupported path and reports unavailable.
        if forcesPiPWatchAvailabilityForTesting {
            return snapshot.isPiPWatchAvailable
        }
        #endif
        return snapshot.isPiPWatchAvailable && (pipWatchController?.isSupported ?? false)
    }

    #if DEBUG
    private var forcesPiPWatchAvailabilityForTesting = false

    public func setForcesPiPWatchAvailabilityForTesting(_ forced: Bool) {
        guard forced != forcesPiPWatchAvailabilityForTesting else {
            return
        }
        forcesPiPWatchAvailabilityForTesting = forced
        objectWillChange.send()
    }
    #endif

    public var pipWatchStatusText: String {
        if pipWatchSession != nil {
            return snapshot.pipWatchStatusText
        }

        guard snapshot.isPiPWatchAvailable else {
            return snapshot.pipWatchStatusText
        }

        guard let pipWatchController else {
            return "PiP renderer pending"
        }

        return pipWatchController.isSupported ? snapshot.pipWatchStatusText : "PiP unavailable on device"
    }

    public func selectProfile(id: ConnectionProfile.ID) {
        if selectedProfileID != id {
            cancelPendingReconnect()
            resetFrameDeliveryInteractionState()
            stopHelperVideoStreamBootstrap()
            stopFrameStream()
            stopIncomingClipboardReceive()
            clearIncomingClipboardReviewState()
            activeTextClient = nil
            activePointerClient = nil
            activeFramebufferUpdateRequestSender = nil
            activeKeyEventClient = nil
            keystrokeEmitter = nil
            directKeystrokeMode = .init()
            stickyModifierState = .init()
            resetLiveTypeThroughState()
            resetPointerControl()
            lastEmittedDragCoord = nil
            activeStreamProfile = nil
            activeStreamCredential = nil
            reconnectAttempts = 0
            resetConnectionQuality()
            latestViewportTransform = nil
            resetAppleServerDownscaleState()
            clearSessionFrame()
            resetSessionStreamStats()
            resetVisualTransportState()
            diagnosticRun = nil
            latestInjectionAttempt = nil
            latestComposeSendPreparation = nil
            clearPiPWatchSession()
            let newSession = RemoteSession(profileID: id)
            session = newSession
            composeDraft = ComposeDraft(sessionID: newSession.id)
        }
        selectedProfileID = id
    }

    private func withSerializedProfileMutation<Result>(
        _ operation: @MainActor () async -> Result
    ) async -> Result {
        await profilePersistenceMutationGate.acquire()
        let result = await operation()
        await profilePersistenceMutationGate.release()
        return result
    }

    private func profilePersistenceFailed(
        _ failure: ProfilePersistenceFailure
    ) -> ProfilePersistenceResult {
        profilePersistenceError = failure.safeMessage
        return .failed(failure)
    }

    private func applyCredentialMutation(
        _ newValue: String?,
        credentialRef: String,
        failure: ProfilePersistenceFailure,
        rollbackJournal: inout [CredentialMutationRollback]
    ) async -> ProfilePersistenceFailure? {
        guard let credentialStore else {
            // A nil credential store is an explicit no-Keychain fixture path
            // for deletions. New secret material still cannot be accepted.
            return newValue == nil ? nil : failure
        }

        let previousValue: String?
        do {
            previousValue = try await credentialStore.password(for: credentialRef)
        } catch {
            return failure
        }

        // Record the undo value before attempting the mutation. The concrete
        // Keychain store replaces an item with delete-then-add, so even a
        // throwing save can have changed the prior entry and needs recovery.
        rollbackJournal.append(
            CredentialMutationRollback(
                credentialRef: credentialRef,
                previousValue: previousValue
            )
        )

        do {
            if let newValue {
                try await credentialStore.savePassword(newValue, for: credentialRef)
            } else {
                try await credentialStore.deletePassword(for: credentialRef)
            }
        } catch {
            return failure
        }
        return nil
    }

    private func rollbackCredentialMutations(
        _ rollbackJournal: [CredentialMutationRollback]
    ) async -> Bool {
        guard let credentialStore else {
            return true
        }

        var restoredAll = true
        for mutation in rollbackJournal.reversed() {
            do {
                if let previousValue = mutation.previousValue {
                    try await credentialStore.savePassword(
                        previousValue,
                        for: mutation.credentialRef
                    )
                } else {
                    try await credentialStore.deletePassword(for: mutation.credentialRef)
                }
            } catch {
                // Continue restoring the remaining entries. The caller gets a
                // fixed catalog failure; raw Keychain errors and values never
                // enter UI state or logs.
                restoredAll = false
            }
        }
        return restoredAll
    }

    private func profilePersistenceFailed(
        _ failure: ProfilePersistenceFailure,
        rollingBack rollbackJournal: [CredentialMutationRollback]
    ) async -> ProfilePersistenceResult {
        let restoredAll = await rollbackCredentialMutations(rollbackJournal)
        return profilePersistenceFailed(restoredAll ? failure : .credentialRestore)
    }

    @discardableResult
    public func addProfile(
        _ profile: ConnectionProfile,
        password: String? = nil,
        helperPairingSecret: String? = nil,
        helperVideoPairingSecret: String? = nil
    ) async -> ProfilePersistenceResult {
        await withSerializedProfileMutation {
            await addProfileTransaction(
                profile,
                password: password,
                helperPairingSecret: helperPairingSecret,
                helperVideoPairingSecret: helperVideoPairingSecret
            )
        }
    }

    private func addProfileTransaction(
        _ profile: ConnectionProfile,
        password: String?,
        helperPairingSecret: String?,
        helperVideoPairingSecret: String?
    ) async -> ProfilePersistenceResult {
        profilePersistenceError = nil
        var profileToSave = profile
        var credentialRollbackJournal: [CredentialMutationRollback] = []
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedPassword, !trimmedPassword.isEmpty {
            let credentialRef = profileToSave.credentialRef ?? Self.credentialReference(for: profileToSave.id)
            if let failure = await applyCredentialMutation(
                trimmedPassword,
                credentialRef: credentialRef,
                failure: .passwordSave,
                rollbackJournal: &credentialRollbackJournal
            ) {
                return await profilePersistenceFailed(
                    failure,
                    rollingBack: credentialRollbackJournal
                )
            }
            profileToSave.credentialRef = credentialRef
        }

        if let failure = await applyHelperPairingSecretUpdate(
            helperPairingSecret,
            to: &profileToSave,
            existingProfile: nil,
            rollbackJournal: &credentialRollbackJournal
        ) {
            return await profilePersistenceFailed(
                failure,
                rollingBack: credentialRollbackJournal
            )
        }
        if let failure = await applyHelperVideoPairingSecretUpdate(
            helperVideoPairingSecret,
            to: &profileToSave,
            existingProfile: nil,
            rollbackJournal: &credentialRollbackJournal
        ) {
            return await profilePersistenceFailed(
                failure,
                rollingBack: credentialRollbackJournal
            )
        }

        // A nil store is an explicit in-memory fixture path and therefore a
        // successful persistence boundary.  With a real store, do not publish
        // the profile or dismiss its editor until the durable write completes.
        if let profileStore {
            do {
                try await profileStore.save(profileToSave)
            } catch {
                return await profilePersistenceFailed(
                    .profileSave,
                    rollingBack: credentialRollbackJournal
                )
            }
        }

        if let index = profiles.firstIndex(where: { $0.id == profileToSave.id }) {
            profiles[index] = profileToSave
        } else {
            profiles.append(profileToSave)
        }
        publishInitialHelperTextBridgeState(for: profileToSave)
        publishInitialHelperVideoState(for: profileToSave)
        refreshProfileReachability()

        selectedProfileID = profileToSave.id
        if session == nil || session?.profileID != profileToSave.id {
            cancelPendingReconnect()
            resetFrameDeliveryInteractionState()
            stopFrameStream()
            stopIncomingClipboardReceive()
            clearIncomingClipboardReviewState()
            let newSession = RemoteSession(profileID: profileToSave.id)
            session = newSession
            composeDraft = ComposeDraft(sessionID: newSession.id)
            diagnosticRun = nil
            latestInjectionAttempt = nil
            latestComposeSendPreparation = nil
            clearPiPWatchSession()
            clearSessionFrame()
            resetSessionStreamStats()
            resetVisualTransportState()
            activeTextClient = nil
            activePointerClient = nil
            activeFramebufferUpdateRequestSender = nil
            activeKeyEventClient = nil
            keystrokeEmitter = nil
            directKeystrokeMode = .init()
            stickyModifierState = .init()
            resetLiveTypeThroughState()
            resetPointerControl()
            lastEmittedDragCoord = nil
            activeStreamProfile = nil
            activeStreamCredential = nil
            reconnectAttempts = 0
        }
        return .succeeded
    }

    /// Replace the saved record for an existing profile.  The
    /// `password` argument controls the keychain side of the edit:
    ///
    /// - `nil`        — leave the existing keychain credential
    ///                   untouched.  Used when the editor's "Replace
    ///                   password" toggle is off.
    /// - `""`         — explicitly clear the credential.  Treated as
    ///                   the user wiping their saved password; the
    ///                   profile's `credentialRef` is dropped and the
    ///                   keychain entry is deleted (delete-of-missing
    ///                   is success, see constitution §IV).
    /// - non-empty    — save the new password through the credential
    ///                   store and ensure `credentialRef` is set.
    ///
    /// Editing the active profile keeps the session/selection in
    /// place (the user is iterating on the same target).  If the
    /// profile id is unknown, this is a no-op so a stale UI never
    /// resurrects a deleted profile.
    @discardableResult
    public func editProfile(
        _ profile: ConnectionProfile,
        password: String?,
        helperPairingSecret: String? = nil,
        helperVideoPairingSecret: String? = nil
    ) async -> ProfilePersistenceResult {
        await withSerializedProfileMutation {
            await editProfileTransaction(
                profile,
                password: password,
                helperPairingSecret: helperPairingSecret,
                helperVideoPairingSecret: helperVideoPairingSecret
            )
        }
    }

    private func editProfileTransaction(
        _ profile: ConnectionProfile,
        password: String?,
        helperPairingSecret: String?,
        helperVideoPairingSecret: String?
    ) async -> ProfilePersistenceResult {
        profilePersistenceError = nil

        guard let existingProfile = profiles.first(where: { $0.id == profile.id }) else {
            // Preserve the established stale-editor no-op behavior. There is
            // nothing left to persist, so treating it as complete is safer
            // than resurrecting a profile that another path deleted.
            return .succeeded
        }

        var profileToSave = profile
        var credentialRollbackJournal: [CredentialMutationRollback] = []
        if profileToSave.helperVideo == nil {
            // The current profile editor does not own helper-video
            // disable/revoke controls. Preserve that opt-in unless a dedicated
            // helper-video path changes it.
            profileToSave.helperVideo = existingProfile.helperVideo
        }

        if let password {
            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPassword.isEmpty {
                // Explicit clear: drop the credentialRef and remove
                // the keychain entry if one exists.  The credential
                // store treats a missing entry as success so the
                // user never sees a "couldn't delete" error for a
                // password that was never saved.
                if let existingRef = existingProfile.credentialRef ?? profileToSave.credentialRef {
                    if let failure = await applyCredentialMutation(
                        nil,
                        credentialRef: existingRef,
                        failure: .passwordRemoval,
                        rollbackJournal: &credentialRollbackJournal
                    ) {
                        return await profilePersistenceFailed(
                            failure,
                            rollingBack: credentialRollbackJournal
                        )
                    }
                }
                profileToSave.credentialRef = nil
            } else {
                let credentialRef = profileToSave.credentialRef ?? Self.credentialReference(for: profileToSave.id)
                if let failure = await applyCredentialMutation(
                    trimmedPassword,
                    credentialRef: credentialRef,
                    failure: .passwordSave,
                    rollbackJournal: &credentialRollbackJournal
                ) {
                    return await profilePersistenceFailed(
                        failure,
                        rollingBack: credentialRollbackJournal
                    )
                }
                profileToSave.credentialRef = credentialRef
            }
        } else {
            // `nil` means the credential is outside this edit. Preserve the
            // durable reference even if a non-UI caller supplied a partial
            // profile without it, so the unchanged Keychain item is not
            // orphaned by the profile write.
            profileToSave.credentialRef = existingProfile.credentialRef
        }

        if let failure = await applyHelperPairingSecretUpdate(
            helperPairingSecret,
            to: &profileToSave,
            existingProfile: existingProfile,
            rollbackJournal: &credentialRollbackJournal
        ) {
            return await profilePersistenceFailed(
                failure,
                rollingBack: credentialRollbackJournal
            )
        }
        if let failure = await applyHelperVideoPairingSecretUpdate(
            helperVideoPairingSecret,
            to: &profileToSave,
            existingProfile: existingProfile,
            rollbackJournal: &credentialRollbackJournal
        ) {
            return await profilePersistenceFailed(
                failure,
                rollingBack: credentialRollbackJournal
            )
        }

        // Keep the currently rendered profile unchanged until the durable
        // store confirms the replacement. A nil store is the intentional
        // in-memory fixture path and counts as success.
        if let profileStore {
            do {
                try await profileStore.save(profileToSave)
            } catch {
                return await profilePersistenceFailed(
                    .profileSave,
                    rollingBack: credentialRollbackJournal
                )
            }
        }

        if let index = profiles.firstIndex(where: { $0.id == profileToSave.id }) {
            profiles[index] = profileToSave
        }
        publishInitialHelperTextBridgeState(for: profileToSave)
        publishInitialHelperVideoState(for: profileToSave)
        refreshProfileReachability()
        return .succeeded
    }

    private func publishInitialHelperTextBridgeState(for profile: ConnectionProfile) {
        guard let state = Self.initialHelperTextBridgeState(for: profile) else {
            helperTextBridgeState.removeValue(forKey: profile.id)
            return
        }
        helperTextBridgeState[profile.id] = state
    }

    private func publishInitialHelperVideoState(for profile: ConnectionProfile) {
        guard let state = Self.initialHelperVideoState(for: profile) else {
            helperVideoProfileState.removeValue(forKey: profile.id)
            return
        }
        helperVideoProfileState[profile.id] = state
    }

    nonisolated private static func initialHelperVideoState(
        for profile: ConnectionProfile
    ) -> HelperVideoProfileState? {
        guard let configuration = profile.helperVideo else {
            return nil
        }
        guard !configuration.isRevoked else {
            return HelperVideoProfileState(
                isEnabled: false,
                pairingFingerprint: nil,
                availability: .revoked,
                lastFailureCode: .revoked,
                lastCheckedBucket: .recent
            )
        }
        guard profile.hostKind != .advancedManualPublicEndpoint else {
            return HelperVideoProfileState(
                isEnabled: false,
                pairingFingerprint: configuration.pairingFingerprint,
                availability: .privateNetworkRequired,
                lastFailureCode: .privateNetworkRequired,
                lastCheckedBucket: .recent
            )
        }
        guard configuration.isEnabled else {
            return HelperVideoProfileState(
                isEnabled: false,
                pairingFingerprint: configuration.pairingFingerprint,
                availability: .disabled,
                lastFailureCode: .disabled,
                lastCheckedBucket: .recent
            )
        }
        guard configuration.pairingSecretRef != nil else {
            return HelperVideoProfileState(
                isEnabled: false,
                pairingFingerprint: configuration.pairingFingerprint,
                availability: .notConfigured,
                lastFailureCode: .notConfigured,
                lastCheckedBucket: .never
            )
        }
        return HelperVideoProfileState(
            isEnabled: true,
            pairingFingerprint: configuration.pairingFingerprint,
            availability: .checking,
            lastFailureCode: nil,
            lastCheckedBucket: .never
        )
    }

    private func startHelperVideoStreamIfConfigured(
        profile: ConnectionProfile,
        sessionID: RemoteSession.ID
    ) {
        stopHelperVideoStreamBootstrap()
        guard isCurrentHelperVideoCallback(sessionID: sessionID, profileID: profile.id) else {
            return
        }
        guard let configuration = profile.helperVideo,
              configuration.isEnabled,
              !configuration.isRevoked
        else {
            return
        }
        guard profile.hostKind != .advancedManualPublicEndpoint else {
            markHelperVideoBootstrapFailure(
                .privateNetworkRequired,
                profileID: profile.id,
                sessionID: sessionID,
                pairingFingerprint: configuration.pairingFingerprint
            )
            return
        }
        guard let secretRef = configuration.pairingSecretRef,
              let pairingFingerprint = configuration.pairingFingerprint,
              !pairingFingerprint.isEmpty
        else {
            markHelperVideoBootstrapFailure(
                .notConfigured,
                profileID: profile.id,
                sessionID: sessionID,
                pairingFingerprint: configuration.pairingFingerprint
            )
            return
        }
        let currentState = helperVideoState(for: profile.id)
        guard Self.shouldAttemptHelperVideoBootstrap(
            configuration: configuration,
            state: currentState
        ) else {
            return
        }
        guard let credentialStore else {
            markHelperVideoBootstrapFailure(
                .notConfigured,
                profileID: profile.id,
                sessionID: sessionID,
                pairingFingerprint: pairingFingerprint
            )
            return
        }
        guard helperVideoStartStream != nil || helperVideoOpenStream != nil else {
            markHelperVideoBootstrapFailure(
                .transportFailed,
                profileID: profile.id,
                sessionID: sessionID,
                pairingFingerprint: pairingFingerprint
            )
            return
        }
        guard let helperVideoRendererFactory else {
            markHelperVideoBootstrapFailure(
                .codecUnsupported,
                profileID: profile.id,
                sessionID: sessionID,
                pairingFingerprint: pairingFingerprint
            )
            return
        }

        let bootstrapID = UUID()
        activeHelperVideoStreamID = bootstrapID
        markHelperVideoBootstrapChecking(
            profileID: profile.id,
            sessionID: sessionID,
            pairingFingerprint: pairingFingerprint
        )
        activeHelperVideoStreamTask = Task.detached(priority: .userInitiated) { [weak self, credentialStore, profile, secretRef, pairingFingerprint, sessionID, bootstrapID, helperVideoStartStream, helperVideoOpenStream, helperVideoRendererFactory] in
            defer {
                Task { @MainActor [weak self] in
                    self?.clearHelperVideoStreamBootstrap(id: bootstrapID)
                }
            }

            guard await Self.isCurrentHelperVideoBootstrap(
                self,
                id: bootstrapID,
                sessionID: sessionID,
                profileID: profile.id
            ) else {
                return
            }

            let pairingSecret: String
            do {
                guard let loadedSecret = try await credentialStore.password(for: secretRef),
                      !loadedSecret.isEmpty
                else {
                    await self?.markHelperVideoBootstrapFailure(
                        .notConfigured,
                        profileID: profile.id,
                        sessionID: sessionID,
                        pairingFingerprint: pairingFingerprint
                    )
                    return
                }
                pairingSecret = loadedSecret
            } catch {
                await self?.markHelperVideoBootstrapFailure(
                    .notConfigured,
                    profileID: profile.id,
                    sessionID: sessionID,
                    pairingFingerprint: pairingFingerprint
                )
                return
            }

            guard !Task.isCancelled else {
                return
            }
            await self?.runLoadedHelperVideoStreamBootstrap(
                profile: profile,
                sessionID: sessionID,
                bootstrapID: bootstrapID,
                pairingSecret: pairingSecret,
                pairingFingerprint: pairingFingerprint,
                startStream: helperVideoStartStream,
                openStream: helperVideoOpenStream,
                rendererFactory: helperVideoRendererFactory
            )
        }
    }

    private static func shouldAttemptHelperVideoBootstrap(
        configuration: HelperVideoConnectionConfiguration,
        state: HelperVideoProfileState
    ) -> Bool {
        guard configuration.isEnabled, !configuration.isRevoked else {
            return false
        }
        switch state.availability {
        case .checking, .available, .unreachable, .failed:
            return true
        case .notConfigured, .disabled, .permissionMissing, .codecUnsupported, .revoked,
             .privateNetworkRequired:
            return false
        }
    }

    private func runLoadedHelperVideoStreamBootstrap(
        profile: ConnectionProfile,
        sessionID: RemoteSession.ID,
        bootstrapID: UUID,
        pairingSecret: String,
        pairingFingerprint: String,
        startStream: HelperVideoStartStream?,
        openStream: HelperVideoOpenStream?,
        rendererFactory: HelperVideoRendererFactory
    ) async {
        guard isCurrentHelperVideoBootstrap(
            id: bootstrapID,
            sessionID: sessionID,
            profileID: profile.id
        ) else {
            return
        }

        markHelperVideoBootstrapReady(
            profileID: profile.id,
            sessionID: sessionID,
            pairingFingerprint: pairingFingerprint
        )
        let runner: HelperVideoStreamSessionRunner
        if let openStream {
            runner = HelperVideoStreamSessionRunner(
                eventStream: { requestBody in
                    openStream(
                        profile,
                        pairingSecret,
                        pairingFingerprint,
                        requestBody
                    )
                },
                renderer: rendererFactory(),
                maxServerFrames: helperVideoMaxServerFrames
            )
        } else if let startStream {
            runner = HelperVideoStreamSessionRunner(
                startStream: { requestBody, maxServerFrames in
                    try await startStream(
                        profile,
                        pairingSecret,
                        pairingFingerprint,
                        requestBody,
                        maxServerFrames
                    )
                },
                renderer: rendererFactory(),
                maxServerFrames: helperVideoMaxServerFrames
            )
        } else {
            markHelperVideoBootstrapFailure(
                .transportFailed,
                profileID: profile.id,
                sessionID: sessionID,
                pairingFingerprint: pairingFingerprint
            )
            return
        }
        let outcome = await runner.start(
            sessionID: sessionID,
            profileID: profile.id,
            model: self,
            requestBody: helperVideoStartRequestBody()
        )
        await helperVideoStreamOutcomeHandler?(sessionID, profile.id, outcome)
    }

    private func helperVideoStartRequestBody() -> HelperVideoStartStreamRequestBody {
        HelperVideoStartRequestPolicy(
            streamPowerMode: appSettings.streamPowerMode,
            isSystemLowPowerModeEnabled: lowPowerModeProvider(),
            thermalState: thermalStateProvider(),
            isNetworkConstrained: networkPathConditionsProvider().isConstrained,
            deviceSupportsHEVCDecode: hevcDecodeSupportProvider()
        ).requestBody
    }

    private func markHelperVideoBootstrapChecking(
        profileID: ConnectionProfile.ID,
        sessionID: RemoteSession.ID,
        pairingFingerprint: String
    ) {
        var state = helperVideoProfileState[profileID] ?? HelperVideoProfileState()
        state.isEnabled = true
        state.pairingFingerprint = pairingFingerprint
        state.availability = .checking
        state.lastFailureCode = nil
        state.lastCheckedBucket = .recent
        setHelperVideoProfileState(state, for: profileID, sessionID: sessionID)
    }

    private func markHelperVideoBootstrapReady(
        profileID: ConnectionProfile.ID,
        sessionID: RemoteSession.ID,
        pairingFingerprint: String
    ) {
        var state = helperVideoProfileState[profileID] ?? HelperVideoProfileState()
        state.isEnabled = true
        state.pairingFingerprint = pairingFingerprint
        state.availability = .available
        state.lastFailureCode = nil
        state.lastCheckedBucket = .recent
        setHelperVideoProfileState(state, for: profileID, sessionID: sessionID)
    }

    private func markHelperVideoBootstrapFailure(
        _ failureCode: HelperVideoFailureCode,
        profileID: ConnectionProfile.ID,
        sessionID: RemoteSession.ID,
        pairingFingerprint: String?
    ) {
        var state = helperVideoProfileState[profileID] ?? HelperVideoProfileState()
        state.isEnabled = failureCode != .disabled && failureCode != .revoked
        state.pairingFingerprint = pairingFingerprint
        state.availability = Self.helperVideoAvailability(for: failureCode)
        state.lastFailureCode = failureCode
        state.lastCheckedBucket = .recent
        setHelperVideoProfileState(state, for: profileID, sessionID: sessionID)
    }

    private static func helperVideoAvailability(
        for failureCode: HelperVideoFailureCode
    ) -> HelperVideoAvailability {
        switch failureCode {
        case .notConfigured:
            return .notConfigured
        case .disabled:
            return .disabled
        case .permissionMissing:
            return .permissionMissing
        case .codecUnsupported:
            return .codecUnsupported
        case .revoked:
            return .revoked
        case .privateNetworkRequired:
            return .privateNetworkRequired
        case .transportFailed, .transportProtectionRequired:
            return .unreachable
        case .authFailed, .streamStalled, .decoderRejected, .fallbackToVNC:
            return .failed
        }
    }

    private static func isCurrentHelperVideoBootstrap(
        _ model: NaruRemoteAppModel?,
        id: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) async -> Bool {
        await MainActor.run {
            model?.isCurrentHelperVideoBootstrap(
                id: id,
                sessionID: sessionID,
                profileID: profileID
            ) ?? false
        }
    }

    private func isCurrentHelperVideoBootstrap(
        id: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) -> Bool {
        activeHelperVideoStreamID == id
            && isCurrentHelperVideoCallback(sessionID: sessionID, profileID: profileID)
    }

    private func clearHelperVideoStreamBootstrap(id: UUID) {
        guard activeHelperVideoStreamID == id else {
            return
        }
        activeHelperVideoStreamTask = nil
        activeHelperVideoStreamID = nil
    }

    private func stopHelperVideoStreamBootstrap() {
        activeHelperVideoStreamTask?.cancel()
        activeHelperVideoStreamTask = nil
        activeHelperVideoStreamID = nil
    }

    nonisolated private static func initialHelperTextBridgeState(
        for profile: ConnectionProfile
    ) -> HelperTextBridgeProfileState? {
        guard let configuration = profile.helperTextBridge else {
            return nil
        }
        guard configuration.isEnabled else {
            return HelperTextBridgeProfileState(
                isEnabled: false,
                pairingFingerprint: configuration.pairingFingerprint,
                availability: .disabled,
                lastFailureCode: .disabled,
                lastCheckedBucket: .recent
            )
        }
        guard configuration.pairingSecretRef != nil else {
            return HelperTextBridgeProfileState(
                isEnabled: false,
                pairingFingerprint: configuration.pairingFingerprint,
                availability: .notConfigured,
                lastFailureCode: .notConfigured,
                lastCheckedBucket: .never
            )
        }
        return HelperTextBridgeProfileState(
            isEnabled: true,
            pairingFingerprint: configuration.pairingFingerprint,
            availability: .checking,
            lastFailureCode: nil,
            lastCheckedBucket: .never
        )
    }

    private func applyHelperPairingSecretUpdate(
        _ helperPairingSecret: String?,
        to profile: inout ConnectionProfile,
        existingProfile: ConnectionProfile?,
        rollbackJournal: inout [CredentialMutationRollback]
    ) async -> ProfilePersistenceFailure? {
        guard let helperPairingSecret else {
            return nil
        }

        let trimmedSecret = helperPairingSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingRef = existingProfile?.helperTextBridge?.pairingSecretRef

        guard !trimmedSecret.isEmpty else {
            if let existingRef {
                if let failure = await applyCredentialMutation(
                    nil,
                    credentialRef: existingRef,
                    failure: .helperTokenRemoval,
                    rollbackJournal: &rollbackJournal
                ) {
                    return failure
                }
            }
            return nil
        }

        guard var configuration = profile.helperTextBridge else {
            return .helperTokenSave
        }

        let secretRef = configuration.pairingSecretRef
            ?? Self.helperPairingSecretReference(for: profile.id)
        if let failure = await applyCredentialMutation(
            trimmedSecret,
            credentialRef: secretRef,
            failure: .helperTokenSave,
            rollbackJournal: &rollbackJournal
        ) {
            return failure
        }
        if let existingRef, existingRef != secretRef,
           let failure = await applyCredentialMutation(
               nil,
               credentialRef: existingRef,
               failure: .helperTokenRemoval,
               rollbackJournal: &rollbackJournal
           ) {
            return failure
        }

        configuration.pairingSecretRef = secretRef
        profile.helperTextBridge = configuration
        return nil
    }

    private func applyHelperVideoPairingSecretUpdate(
        _ helperVideoPairingSecret: String?,
        to profile: inout ConnectionProfile,
        existingProfile: ConnectionProfile?,
        rollbackJournal: inout [CredentialMutationRollback]
    ) async -> ProfilePersistenceFailure? {
        guard let helperVideoPairingSecret else {
            return nil
        }

        let trimmedSecret = helperVideoPairingSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingRef = existingProfile?.helperVideo?.pairingSecretRef

        guard !trimmedSecret.isEmpty else {
            if let existingRef {
                if let failure = await applyCredentialMutation(
                    nil,
                    credentialRef: existingRef,
                    failure: .helperVideoTokenRemoval,
                    rollbackJournal: &rollbackJournal
                ) {
                    return failure
                }
            }
            return nil
        }

        guard var configuration = profile.helperVideo else {
            return .helperVideoTokenSave
        }

        let secretRef = configuration.pairingSecretRef
            ?? Self.helperVideoPairingSecretReference(for: profile.id)
        if let failure = await applyCredentialMutation(
            trimmedSecret,
            credentialRef: secretRef,
            failure: .helperVideoTokenSave,
            rollbackJournal: &rollbackJournal
        ) {
            return failure
        }
        if let existingRef, existingRef != secretRef,
           let failure = await applyCredentialMutation(
               nil,
               credentialRef: existingRef,
               failure: .helperVideoTokenRemoval,
               rollbackJournal: &rollbackJournal
           ) {
            return failure
        }

        configuration.pairingSecretRef = secretRef
        profile.helperVideo = configuration
        return nil
    }

    /// Remove a saved profile and its Keychain credentials as one provisional
    /// mutation. Keychain delete-of-missing is success; any credential/store
    /// failure restores prior credentials and keeps the published profile so
    /// the user can retry safely.
    ///
    /// If the deleted profile was the active one, the session,
    /// frame stream, incoming-clipboard review, diagnostics, and
    /// PiP watch state are all torn down and `selectedProfileID` is
    /// cleared so no stale UI references the missing profile.
    @discardableResult
    public func deleteProfile(id: ConnectionProfile.ID) async -> ProfilePersistenceResult {
        await withSerializedProfileMutation {
            await deleteProfileTransaction(id: id)
        }
    }

    private func deleteProfileTransaction(
        id: ConnectionProfile.ID
    ) async -> ProfilePersistenceResult {
        profilePersistenceError = nil

        guard let removedProfile = profiles.first(where: { $0.id == id }) else {
            return .succeeded
        }

        let wasActive = selectedProfileID == id || session?.profileID == id
        var credentialRollbackJournal: [CredentialMutationRollback] = []

        // Credential removal is provisional until the profile store commits.
        // If any Keychain delete or the durable profile delete fails, restore
        // every prior value in reverse order and leave the row/session intact
        // so the shell's retry action remains meaningful.
        let credentialMutations: [(String?, ProfilePersistenceFailure)] = [
            (removedProfile.credentialRef, .passwordRemoval),
            (removedProfile.helperTextBridge?.pairingSecretRef, .helperTokenRemoval),
            (removedProfile.helperVideo?.pairingSecretRef, .helperVideoTokenRemoval)
        ]
        for (credentialRef, failure) in credentialMutations {
            guard let credentialRef else { continue }
            if let mutationFailure = await applyCredentialMutation(
                nil,
                credentialRef: credentialRef,
                failure: failure,
                rollbackJournal: &credentialRollbackJournal
            ) {
                return await profilePersistenceFailed(
                    mutationFailure,
                    rollingBack: credentialRollbackJournal
                )
            }
        }

        // A nil store is the explicit in-memory fixture path. With a real
        // store, durable removal is the transaction commit point.
        if let profileStore {
            do {
                _ = try await profileStore.deleteProfile(id: id)
            } catch {
                return await profilePersistenceFailed(
                    .profileRemoval,
                    rollingBack: credentialRollbackJournal
                )
            }
        }

        profiles.removeAll { $0.id == id }
        // Drop any cached verdict for the deleted profile so the
        // sidebar dot doesn't outlive the row (UX punch-list #109).
        lastDiagnosticVerdict.removeValue(forKey: id)
        profilePreviews.removeValue(forKey: id)
        lastPreviewPublishAt.removeValue(forKey: id)
        lastPreviewSaveAt.removeValue(forKey: id)
        profileReachability.removeValue(forKey: id)

        helperTextBridgeState.removeValue(forKey: id)
        helperVideoProfileState.removeValue(forKey: id)

        do {
            try await profilePreviewStore?.deleteThumbnail(for: id)
        } catch {
            // Preview deletion is best-effort local cleanup. The
            // profile itself is already gone and the in-memory
            // thumbnail cache was cleared above.
        }

        if wasActive {
            cancelPendingReconnect()
            resetFrameDeliveryInteractionState()
            stopHelperVideoStreamBootstrap()
            stopFrameStream()
            stopIncomingClipboardReceive()
            clearIncomingClipboardReviewState()
            activeTextClient = nil
            activePointerClient = nil
            activeFramebufferUpdateRequestSender = nil
            activeKeyEventClient = nil
            keystrokeEmitter = nil
            directKeystrokeMode = .init()
            stickyModifierState = .init()
            resetLiveTypeThroughState()
            resetPointerControl()
            lastEmittedDragCoord = nil
            activeStreamProfile = nil
            activeStreamCredential = nil
            reconnectAttempts = 0
            session = nil
            composeDraft = nil
            diagnosticRun = nil
            latestInjectionAttempt = nil
            latestComposeSendPreparation = nil
            clearSessionFrame()
            resetSessionStreamStats()
            resetVisualTransportState()
            clearPiPWatchSession()
            selectedProfileID = nil
        }
        return .succeeded
    }

    /// Build a `DiagnosticExport` from the current diagnostic state.
    /// Returns an empty export (header-only when rendered) when no
    /// run has been started yet.  This is the single entry point the
    /// shell uses to compose share-sheet text — bypassing it would
    /// risk leaking caller-provided raw details (constitution §IV).
    public func makeDiagnosticExport() -> DiagnosticExport {
        let streamPerformance = sessionStreamStats.diagnosticStreamPerformanceReport
        let viewerStreamPowerMode = appSettings.streamPowerMode
        let viewerStreamEncodingMode = appSettings.streamEncodingMode
        let viewerStartupPreflightMode = appSettings.startupPreflightMode
        let viewerStartupGlanceScaleMode = appSettings.startupGlanceScaleMode
        let composeRoute = composeRouteDiagnosticSnapshot()
        let helperVideo = helperVideoDiagnosticReport()
        let input = DiagnosticInputReport(
            composeDraft: composeDraft,
            latestInjectionAttempt: latestInjectionAttempt,
            directKeystrokeModeActive: directKeystrokeMode.isActive,
            composePlannedPath: composeRoute.plannedPath,
            composeUTF8ClipboardSupport: composeRoute.utf8ClipboardSupport,
            composeRouteBlocker: composeRoute.routeBlocker,
            latestComposeSendPreparation: latestComposeSendPreparation,
            helperTextBridgeState: helperTextBridgeState(for: composeRoute.helperProfileID),
            liveBackspacePassThroughCount: liveBackspacePassThroughCount
        )
        let sustainedSessionAssessment = DiagnosticSustainedSessionAssessment.assess(
            streamPerformance: streamPerformance,
            input: input,
            contentFramesPerSecond: sessionStreamStats.contentFramesPerSecond
        )
        let pipWatch = pipWatchDiagnosticReport()
        guard let run = diagnosticRun else {
            return DiagnosticExport(
                run: ConnectionDiagnosticRun(
                    profileID: selectedProfileID ?? UUID(),
                    stages: []
                ),
                streamPerformance: streamPerformance,
                viewerStreamPowerMode: viewerStreamPowerMode,
                viewerStreamEncodingMode: viewerStreamEncodingMode,
                viewerStartupPreflightMode: viewerStartupPreflightMode,
                viewerStartupGlanceScaleMode: viewerStartupGlanceScaleMode,
                input: input,
                helperVideo: helperVideo,
                sustainedSessionAssessment: sustainedSessionAssessment,
                pipWatch: pipWatch
            )
        }
        return DiagnosticExport(
            run: run,
            streamPerformance: streamPerformance,
            viewerStreamPowerMode: viewerStreamPowerMode,
            viewerStreamEncodingMode: viewerStreamEncodingMode,
            viewerStartupPreflightMode: viewerStartupPreflightMode,
            viewerStartupGlanceScaleMode: viewerStartupGlanceScaleMode,
            input: input,
            helperVideo: helperVideo,
            sustainedSessionAssessment: sustainedSessionAssessment,
            pipWatch: pipWatch
        )
    }

    /// Spec 032 FR-006 — the lifecycle counts, from the controller that owns
    /// them. Absent when the controller cannot report a lifecycle, rather than
    /// reported as zeros that would read as "PiP was never asked for".
    private func pipWatchDiagnosticReport() -> DiagnosticPiPWatchReport? {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        guard let reporting = pipWatchController as? any PiPWatchLifecycleReporting else {
            return nil
        }
        return DiagnosticPiPWatchReport(lifecycle: reporting.lifecycle)
        #else
        return nil
        #endif
    }

    private func helperVideoDiagnosticReport() -> DiagnosticHelperVideoReport? {
        let profileID = session?.profileID ?? selectedProfileID
        guard profileID != nil else {
            return nil
        }
        return DiagnosticHelperVideoReport(
            profileState: helperVideoState(for: profileID),
            streamDescriptor: helperVideoStreamDescriptor,
            streamHealth: helperVideoStreamHealth
        )
    }

    private func composeRouteDiagnosticSnapshot() -> ComposeRouteDiagnosticSnapshot {
        let profileID = session?.profileID ?? selectedProfileID
        let utf8Support = activeTextClient?.utf8ClipboardSupport
        let helperState = helperTextBridgeState(for: profileID)
        let profile = profileID.flatMap { id in
            profiles.first { $0.id == id }
        }
        let payloadEncoding = composeDraft.map { TextInjectionPayloadEncoding.classify($0.text) }

        guard let draft = composeDraft else {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: nil,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: .emptyDraft,
                helperProfileID: profileID
            )
        }

        guard !directKeystrokeMode.isActive else {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: nil,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: .directModeActive,
                helperProfileID: profileID
            )
        }

        guard !draft.text.isEmpty else {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: nil,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: .emptyDraft,
                helperProfileID: profileID
            )
        }

        if let helperState,
           let helperTextInsertClient,
           Self.canRouteThroughHelperTextBridge(
                state: helperState,
                client: helperTextInsertClient
            ) {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: .helperTextBridge,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: DiagnosticComposeRouteBlocker.none,
                helperProfileID: profileID
            )
        }

        if let profile,
           let helperState,
           Self.canRouteThroughStoredHelperTextBridge(
                state: helperState,
                profile: profile
           ) {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: .helperTextBridge,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: DiagnosticComposeRouteBlocker.none,
                helperProfileID: profileID
            )
        }

        guard let utf8Support else {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: nil,
                utf8ClipboardSupport: nil,
                routeBlocker: .noActiveTextClient,
                helperProfileID: profileID
            )
        }

        guard payloadEncoding == .utf8ExtensionRequired else {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: .vncClipboardPaste,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: DiagnosticComposeRouteBlocker.none,
                helperProfileID: profileID
            )
        }

        if utf8Support == .supported {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: .vncClipboardPaste,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: DiagnosticComposeRouteBlocker.none,
                helperProfileID: profileID
            )
        }

        if let profile,
           let helperState,
           Self.canAttemptStoredHelperTextBridge(
                state: helperState,
                profile: profile
           ) {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: .helperTextBridge,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: DiagnosticComposeRouteBlocker.none,
                helperProfileID: profileID
            )
        }

        if utf8Support == .unknown {
            return ComposeRouteDiagnosticSnapshot(
                plannedPath: .vncClipboardPaste,
                utf8ClipboardSupport: utf8Support,
                routeBlocker: DiagnosticComposeRouteBlocker.none,
                helperProfileID: profileID
            )
        }

        return ComposeRouteDiagnosticSnapshot(
            plannedPath: nil,
            utf8ClipboardSupport: utf8Support,
            routeBlocker: Self.diagnosticComposeRouteBlocker(
                for: Self.helperFailureCode(
                    state: helperState,
                    client: helperTextInsertClient
                )
            ),
            helperProfileID: profileID
        )
    }

    public func runConnectionChecks() {
        guard let profile = selectedProfile else {
            return
        }

        diagnosticRun = ConnectionDiagnosticRun(
            profileID: profile.id,
            context: Self.diagnosticContext(
                for: profile,
                trigger: .manualChecks,
                timeout: nil
            ),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "Private profile is selected."
                ),
                DiagnosticStageResult(
                    stage: .tcp,
                    status: .running,
                    safeTitle: "Checking VNC port",
                    safeDetail: "Attempting a TCP/RFB first-frame check."
                )
            ]
        )
        // The placeholder "running" run is intentionally not finished
        // — its verdict resolves to `.unknown`, which is exactly what
        // the sidebar should show until the network attempt resolves.
        recordDiagnosticVerdict(for: profile.id, from: diagnosticRun)
    }

    /// One-shot DNS+TCP+RFB-handshake against an arbitrary
    /// `(host, port[, password])` triple supplied from the profile
    /// editor's "Test" affordance.  The triple is NOT a persisted
    /// `ConnectionProfile` — this is a verify-then-save flow, so the
    /// user can prove a target before the keychain credential is
    /// stored (UX punch-list #102, constitution §III "Verification
    /// Before Confidence").
    ///
    /// Side-effect-free with respect to model state: this DOES NOT
    /// touch `session`, `diagnosticRun`, `lastDiagnosticVerdict`,
    /// `latestFramebuffer`, `composeDraft`, or any active stream.
    /// The view consumes the returned `ProfileEditorTestOutcome` and
    /// renders `safeMessage` directly under the form.
    ///
    /// Constitution §IV: the rendered message is sourced exclusively
    /// from `DiagnosticMessageCatalog` — raw `RFBNetworkClientError`
    /// strings never reach the UI.
    public func runProfileEditorReachabilityTest(
        host: String,
        port: Int,
        password: String? = nil
    ) async -> ProfileEditorTestOutcome {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return ProfileEditorTestOutcome(
                verdict: .failed,
                safeMessage: "Host is required."
            )
        }
        guard (1...65535).contains(port), let portValue = UInt16(exactly: port) else {
            return ProfileEditorTestOutcome(
                verdict: .failed,
                safeMessage: "Port must be between 1 and 65535."
            )
        }

        let credential: RFBConnectionCredential
        if let password, !password.isEmpty {
            credential = .vncPassword(password)
        } else {
            credential = .none
        }

        let connector = connectorFactory()
        let endpoint = "\(trimmedHost):\(port)"

        do {
            _ = try await Task.detached {
                try Self.connectAndReadFirstFrame(
                    connector: connector,
                    host: trimmedHost,
                    port: portValue,
                    credential: credential,
                    timeout: 8
                )
            }.value
            // No throw → handshake completed.  When the user supplied
            // a password the handshake exercised the auth path; when
            // they did not, the server accepted the no-auth route.
            let result = DiagnosticMessageCatalog.reachabilitySuccess(
                host: trimmedHost,
                port: port,
                requiresAuthentication: credential != .none
            )
            return ProfileEditorTestOutcome(
                verdict: .passed,
                safeMessage: "\(result.safeTitle) — \(result.safeDetail)"
            )
        } catch let error as RFBNetworkClientError {
            // Map the wire-error to a safe-catalog stage and surface
            // the catalog's safe text — never `error.localizedDescription`.
            let stage = Self.stage(for: error)
            // Special-case: a no-auth probe against a server that
            // requires authentication is a positive reachability
            // signal — the host exists and the VNC service is up;
            // the user just needs to enter a password.  Surface this
            // as `.passed`/"requires VNC password" so the editor's
            // outcome line matches the spec example.
            if case .authenticationRequired = error, credential == .none {
                let result = DiagnosticMessageCatalog.reachabilitySuccess(
                    host: trimmedHost,
                    port: port,
                    requiresAuthentication: true
                )
                return ProfileEditorTestOutcome(
                    verdict: .passed,
                    safeMessage: "\(result.safeTitle) — \(result.safeDetail)"
                )
            }
            let failure = DiagnosticMessageCatalog.failure(for: stage)
            return ProfileEditorTestOutcome(
                verdict: .failed,
                safeMessage: "\(endpoint) — \(failure.safeDetail)"
            )
        } catch let error as RFBProtocolDecoderError {
            // Wrong-password against macOS Screen Sharing surfaces as
            // `RFBProtocolDecoderError.securityFailed(1)` from
            // `parseSecurityResult`.  Without this branch the catch-all
            // below would mis-stage that as `.rfbHandshake` — the
            // exact misleading message this PR fixes.
            let stage = Self.stage(for: error)
            let failure = DiagnosticMessageCatalog.failure(for: stage)
            return ProfileEditorTestOutcome(
                verdict: .failed,
                safeMessage: "\(endpoint) — \(failure.safeDetail)"
            )
        } catch {
            // Any other error (timeout, IO failure) falls through to
            // a generic handshake-failed catalog entry.
            let failure = DiagnosticMessageCatalog.failure(for: .rfbHandshake)
            return ProfileEditorTestOutcome(
                verdict: .failed,
                safeMessage: "\(endpoint) — \(failure.safeDetail)"
            )
        }
    }

    /// Map an `RFBNetworkClientError` to the closest safe-catalog
    /// stage so the profile-editor "Test" outcome line reuses the
    /// existing localized strings.  Constitution §IV: callers MUST
    /// NOT pipe `error.localizedDescription` to the UI — they must
    /// re-derive the displayed string from
    /// `DiagnosticMessageCatalog.failure(for:)`.
    nonisolated private static func stage(for error: RFBNetworkClientError) -> DiagnosticStage {
        switch error {
        case .invalidPort, .connectTimedOut, .timedOut, .connectionFailed, .writeTimedOut, .writeFailed, .notConnected:
            return .tcp
        case .readTimedOut,
             .incompleteTranscript,
             .unsupportedFramebufferEncoding,
             .continuousUpdatesNotConfirmed,
             .unsupportedBestEffortPointerMask:
            return .rfbHandshake
        case .authenticationRequired, .unsupportedSecurityTypes:
            return .authentication
        }
    }

    /// Map an `RFBProtocolDecoderError` to the closest safe-catalog
    /// stage.  In particular, `.securityFailed` (status != 0 from the
    /// server's SecurityResult) means the supplied VNC password was
    /// rejected — that is an authentication failure, NOT a generic
    /// "handshake failed".  All other decoder errors mean the server
    /// produced bytes we could not parse against the RFB spec, so they
    /// surface as `.rfbHandshake` (our closest existing stage).
    nonisolated private static func stage(for error: RFBProtocolDecoderError) -> DiagnosticStage {
        switch error {
        case .securityFailed:
            return .authentication
        case .insufficientData,
             .invalidProtocolVersion,
             .unexpectedMessageType,
             .truncatedServerCutText,
             .invalidServerCutTextEncoding,
             .malformedExtendedServerCutText,
             .desktopNameTooLong,
             .serverCutTextPayloadTooLarge:
            return .rfbHandshake
        }
    }

    /// Generic `Error` overload: routes through the typed mappings
    /// above when the error is recognized, otherwise falls back to
    /// `.rfbHandshake` so the user still gets a catalog message
    /// (constitution §IV) and never `error.localizedDescription`.
    nonisolated private static func stage(for error: Error) -> DiagnosticStage {
        if let networkError = error as? RFBNetworkClientError {
            return stage(for: networkError)
        }
        if let decoderError = error as? RFBProtocolDecoderError {
            return stage(for: decoderError)
        }
        return .rfbHandshake
    }

    private struct ReachabilityProbeResult: Sendable {
        let generation: UUID
        let profileID: ConnectionProfile.ID
        let state: ProfileReachabilityState
    }

    private struct HelperTextBridgeProbeResult: Sendable {
        let generation: UUID
        let profileID: ConnectionProfile.ID
        let state: HelperTextBridgeProfileState
    }

    private func startReachabilityProbes(for probeProfiles: [ConnectionProfile]) {
        reachabilityProbeTask?.cancel()
        let generation = UUID()
        reachabilityProbeGeneration = generation
        let profileIDs = Set(probeProfiles.map(\.id))
        profileReachability = profileReachability.filter { profileIDs.contains($0.key) }
        guard !probeProfiles.isEmpty else {
            return
        }

        for profile in probeProfiles {
            profileReachability[profile.id] = .checking
        }

        let connectorFactory = connectorFactory
        let credentialStore = credentialStore
        let timeout = reachabilityProbeTimeout
        let maximumConcurrency = min(reachabilityProbeMaximumConcurrency, probeProfiles.count)

        reachabilityProbeTask = Task { [weak self, probeProfiles, generation, connectorFactory, credentialStore, timeout, maximumConcurrency] in
            await withTaskGroup(of: ReachabilityProbeResult.self) { group in
                var nextIndex = 0

                for _ in 0..<maximumConcurrency {
                    let profile = probeProfiles[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await Self.probeReachability(
                            profile: profile,
                            generation: generation,
                            connectorFactory: connectorFactory,
                            credentialStore: credentialStore,
                            timeout: timeout
                        )
                    }
                }

                while let result = await group.next() {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }

                    self?.applyReachabilityResult(result)

                    if nextIndex < probeProfiles.count {
                        let profile = probeProfiles[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await Self.probeReachability(
                                profile: profile,
                                generation: generation,
                                connectorFactory: connectorFactory,
                                credentialStore: credentialStore,
                                timeout: timeout
                            )
                        }
                    }
                }
            }
        }
    }

    private func applyReachabilityResult(_ result: ReachabilityProbeResult) {
        guard reachabilityProbeGeneration == result.generation else {
            return
        }
        guard profiles.contains(where: { $0.id == result.profileID }) else {
            return
        }
        profileReachability[result.profileID] = result.state
    }

    nonisolated private static func probeReachability(
        profile: ConnectionProfile,
        generation: UUID,
        connectorFactory: @escaping @Sendable () -> RFBFirstFrameConnecting,
        credentialStore: ConnectionCredentialStoreProtocol?,
        timeout: TimeInterval
    ) async -> ReachabilityProbeResult {
        let credential = await reachabilityCredential(for: profile, credentialStore: credentialStore)
        let connector = connectorFactory()

        do {
            _ = try await Task.detached {
                try Self.connectAndReadFirstFrame(
                    connector: connector,
                    host: profile.host,
                    port: UInt16(profile.port),
                    credential: credential,
                    timeout: timeout
                )
            }.value
            return ReachabilityProbeResult(generation: generation, profileID: profile.id, state: .reachable)
        } catch {
            return ReachabilityProbeResult(
                generation: generation,
                profileID: profile.id,
                state: reachabilityFailureState(for: error)
            )
        }
    }

    nonisolated private static func reachabilityCredential(
        for profile: ConnectionProfile,
        credentialStore: ConnectionCredentialStoreProtocol?
    ) async -> RFBConnectionCredential {
        guard let credentialRef = profile.credentialRef else {
            return .none
        }
        guard let credentialStore,
              let password = try? await credentialStore.password(for: credentialRef),
              !password.isEmpty
        else {
            return .none
        }
        return .vncPassword(password)
    }

    nonisolated private static func reachabilityFailureState(for error: Error) -> ProfileReachabilityState {
        let failedStage = stage(for: error)
        if failedStage == .authentication {
            return .needsPassword
        }
        return .unreachable(failedStage: failedStage)
    }

    private func startHelperTextBridgeProbes(for probeProfiles: [ConnectionProfile]) {
        helperTextBridgeProbeTask?.cancel()
        let generation = UUID()
        helperTextBridgeProbeGeneration = generation

        var helperProfiles: [ConnectionProfile] = []
        for profile in probeProfiles {
            guard let initialState = Self.initialHelperTextBridgeState(for: profile) else {
                continue
            }
            let currentState = helperTextBridgeState[profile.id]

            if let currentState,
               Self.isUserBlockedHelperTextBridgeState(currentState) {
                continue
            }

            guard let configuration = profile.helperTextBridge else {
                continue
            }
            guard configuration.isEnabled, configuration.pairingSecretRef != nil else {
                helperTextBridgeState[profile.id] = initialState
                continue
            }

            if let currentState,
               Self.shouldKeepHelperTextBridgeStateDuringProbe(
                    currentState,
                    for: profile
               ) {
                helperTextBridgeState[profile.id] = currentState
            } else {
                helperTextBridgeState[profile.id] = initialState
            }
            helperProfiles.append(profile)
        }

        guard !helperProfiles.isEmpty else {
            return
        }

        guard let credentialStore else {
            for profile in helperProfiles {
                helperTextBridgeState[profile.id] = Self.helperTextBridgeProbeState(
                    for: profile,
                    failureCode: .notConfigured
                )
            }
            return
        }

        let timeout = reachabilityProbeTimeout
        let maximumConcurrency = min(reachabilityProbeMaximumConcurrency, helperProfiles.count)
        helperTextBridgeProbeTask = Task { [weak self, helperProfiles, generation, credentialStore, timeout, maximumConcurrency] in
            await withTaskGroup(of: HelperTextBridgeProbeResult.self) { group in
                var nextIndex = 0

                for _ in 0..<maximumConcurrency {
                    let profile = helperProfiles[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await Self.probeHelperTextBridge(
                            profile: profile,
                            generation: generation,
                            credentialStore: credentialStore,
                            timeout: timeout
                        )
                    }
                }

                while let result = await group.next() {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }

                    self?.applyHelperTextBridgeProbeResult(result)

                    if nextIndex < helperProfiles.count {
                        let profile = helperProfiles[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await Self.probeHelperTextBridge(
                                profile: profile,
                                generation: generation,
                                credentialStore: credentialStore,
                                timeout: timeout
                            )
                        }
                    }
                }
            }
        }
    }

    private func applyHelperTextBridgeProbeResult(_ result: HelperTextBridgeProbeResult) {
        guard helperTextBridgeProbeGeneration == result.generation else {
            return
        }
        guard profiles.contains(where: { $0.id == result.profileID }) else {
            return
        }
        if let current = helperTextBridgeState[result.profileID],
           Self.isUserBlockedHelperTextBridgeState(current),
           !Self.isUserBlockedHelperTextBridgeState(result.state) {
            return
        }
        helperTextBridgeState[result.profileID] = result.state
    }

    nonisolated private static func probeHelperTextBridge(
        profile: ConnectionProfile,
        generation: UUID,
        credentialStore: ConnectionCredentialStoreProtocol,
        timeout: TimeInterval
    ) async -> HelperTextBridgeProbeResult {
        guard let configuration = profile.helperTextBridge else {
            return HelperTextBridgeProbeResult(
                generation: generation,
                profileID: profile.id,
                state: HelperTextBridgeProfileState()
            )
        }
        guard configuration.isEnabled else {
            return HelperTextBridgeProbeResult(
                generation: generation,
                profileID: profile.id,
                state: helperTextBridgeProbeState(for: profile, failureCode: .disabled)
            )
        }
        guard let secretRef = configuration.pairingSecretRef else {
            return HelperTextBridgeProbeResult(
                generation: generation,
                profileID: profile.id,
                state: helperTextBridgeProbeState(for: profile, failureCode: .notConfigured)
            )
        }

        let secret: String
        do {
            guard let loadedSecret = try await credentialStore.password(for: secretRef),
                  !loadedSecret.isEmpty
            else {
                return HelperTextBridgeProbeResult(
                    generation: generation,
                    profileID: profile.id,
                    state: helperTextBridgeProbeState(for: profile, failureCode: .notConfigured)
                )
            }
            secret = loadedSecret
        } catch {
            return HelperTextBridgeProbeResult(
                generation: generation,
                profileID: profile.id,
                state: helperTextBridgeProbeState(for: profile, failureCode: .notConfigured)
            )
        }

        guard let port = UInt16(exactly: configuration.port) else {
            return HelperTextBridgeProbeResult(
                generation: generation,
                profileID: profile.id,
                state: helperTextBridgeProbeState(for: profile, failureCode: .unreachable)
            )
        }

        let client = NaruHelperNetworkTextInsertClient(
            host: configuration.resolvedHost(fallback: profile.host),
            port: port,
            pairingSecret: secret,
            timeout: timeout
        )

        do {
            let capability = try await client.capability(
                profilePairingFingerprint: configuration.pairingFingerprint
            )
            return HelperTextBridgeProbeResult(
                generation: generation,
                profileID: profile.id,
                state: helperTextBridgeProbeState(
                    for: profile,
                    capability: capability
                )
            )
        } catch {
            return HelperTextBridgeProbeResult(
                generation: generation,
                profileID: profile.id,
                state: helperTextBridgeProbeState(
                    for: profile,
                    failureCode: helperFailureCode(from: error)
                )
            )
        }
    }

    nonisolated private static func shouldKeepHelperTextBridgeStateDuringProbe(
        _ state: HelperTextBridgeProfileState,
        for profile: ConnectionProfile
    ) -> Bool {
        guard let configuration = profile.helperTextBridge,
              configuration.isEnabled,
              configuration.pairingSecretRef != nil,
              state.isEnabled,
              state.pairingFingerprint == configuration.pairingFingerprint
        else {
            return false
        }
        return state.availability != .checking
    }

    nonisolated private static func diagnosticContext(
        for profile: ConnectionProfile,
        trigger: DiagnosticRunTrigger,
        timeout: TimeInterval?
    ) -> DiagnosticRunContext {
        let normalizedHost = profile.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedTarget = "\(normalizedHost):\(profile.port)"
        return DiagnosticRunContext(
            targetFingerprint: DiagnosticFingerprint.sha256Token(normalizedTarget),
            profileHostKind: profile.hostKind.rawValue,
            configuredPort: profile.port,
            hasCredentialReference: profile.credentialRef != nil,
            trigger: trigger,
            probeTimeoutSeconds: timeout.map { ($0 * 1000).rounded() / 1000 }
        )
    }

    nonisolated private static func diagnosticFailureMetadata(for error: Error) -> DiagnosticStageMetadata {
        DiagnosticStageMetadata(failureCode: diagnosticFailureCode(for: error))
    }

    nonisolated private static func diagnosticFailureCode(for error: Error) -> String {
        if let networkError = error as? RFBNetworkClientError {
            switch networkError {
            case .invalidPort:
                return "network.invalidPort"
            case .connectTimedOut:
                return "network.connectTimedOut"
            case .timedOut:
                return "network.timedOut"
            case .readTimedOut:
                return "network.readTimedOut"
            case .incompleteTranscript:
                return "rfb.incompleteTranscript"
            case .connectionFailed:
                return "network.connectionFailed"
            case .writeTimedOut:
                return "network.writeTimedOut"
            case .writeFailed:
                return "network.writeFailed"
            case .authenticationRequired:
                return "rfb.authenticationRequired"
            case .unsupportedSecurityTypes:
                return "rfb.unsupportedSecurityTypes"
            case .unsupportedFramebufferEncoding:
                return "rfb.unsupportedFramebufferEncoding"
            case .notConnected:
                return "network.notConnected"
            case .continuousUpdatesNotConfirmed:
                return "rfb.continuousUpdatesNotConfirmed"
            case .unsupportedBestEffortPointerMask:
                return "rfb.unsupportedBestEffortPointerMask"
            }
        }

        if let decoderError = error as? RFBProtocolDecoderError {
            switch decoderError {
            case .securityFailed:
                return "rfb.securityFailed"
            case .insufficientData:
                return "rfb.insufficientData"
            case .invalidProtocolVersion:
                return "rfb.invalidProtocolVersion"
            case .unexpectedMessageType:
                return "rfb.unexpectedMessageType"
            case .truncatedServerCutText:
                return "rfb.truncatedServerCutText"
            case .invalidServerCutTextEncoding:
                return "rfb.invalidServerCutTextEncoding"
            case .malformedExtendedServerCutText:
                return "rfb.malformedExtendedServerCutText"
            case .desktopNameTooLong:
                return "rfb.desktopNameTooLong"
            case .serverCutTextPayloadTooLarge:
                return "rfb.serverCutTextPayloadTooLarge"
            }
        }

        if error is AppCredentialError {
            return "credential.passwordMissing"
        }

        return "error.unknown"
    }

    /// Stamps the per-profile verdict cache for #109's leading status
    /// dot.  Centralizing the write here means every diagnostic
    /// completion path (success, failure, credential failure,
    /// reconnect drop) flows through the same safe-catalog-derived
    /// verdict — no caller can pipe a freeform string into the
    /// sidebar (constitution §IV).  Pass `nil` to clear the entry
    /// (e.g. on profile change / disconnect-clears-state paths).
    private func recordDiagnosticVerdict(
        for profileID: ConnectionProfile.ID,
        from run: ConnectionDiagnosticRun?
    ) {
        emitDiagnosticExportForTestingIfRequested(run)
        guard let run else {
            lastDiagnosticVerdict.removeValue(forKey: profileID)
            return
        }
        lastDiagnosticVerdict[profileID] = run.verdict
    }

    private func emitDiagnosticExportForTestingIfRequested(_ run: ConnectionDiagnosticRun?) {
#if DEBUG
        guard ProcessInfo.processInfo.environment["NARU_TEST_LOG_DIAGNOSTIC_EXPORT"] == "1",
              run?.finishedAt != nil
        else {
            return
        }

        emitDiagnosticExportForTesting(buildVersion: "test-device")
#endif
    }

    public func emitDiagnosticExportForTesting(buildVersion: String?) {
#if DEBUG
        guard ProcessInfo.processInfo.environment["NARU_TEST_LOG_DIAGNOSTIC_EXPORT"] == "1" else {
            return
        }

        let payload = makeDiagnosticExport().renderCollectionJSON(
            buildVersion: buildVersion ?? "test-device",
            now: Date()
        )
        if ProcessInfo.processInfo.environment["NARU_TEST_EXPOSE_DIAGNOSTIC_EXPORT_RELAY"] == "1" {
            diagnosticExportRelayForTesting = payload
        }
        print("NARU_DIAGNOSTIC_EXPORT_BEGIN")
        print(payload)
        print("NARU_DIAGNOSTIC_EXPORT_END")
#endif
    }

    private func scheduleActiveDiagnosticExportForTestingIfRequested() {
#if DEBUG
        guard !hasScheduledActiveDiagnosticExportForTesting,
              ProcessInfo.processInfo.environment["NARU_TEST_LOG_DIAGNOSTIC_EXPORT"] == "1",
              let rawDelay = ProcessInfo.processInfo
                .environment["NARU_TEST_EMIT_DIAGNOSTIC_EXPORT_AFTER_ACTIVE_SECONDS"],
              let delaySeconds = TimeInterval(rawDelay),
              delaySeconds >= 0
        else {
            return
        }

        hasScheduledActiveDiagnosticExportForTesting = true
        activeDiagnosticExportTaskForTesting = Task { [weak self] in
            if delaySeconds > 0 {
                do {
                    try await Task.sleep(for: .milliseconds(Int((delaySeconds * 1_000).rounded())))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self, self.hasScheduledActiveDiagnosticExportForTesting else {
                    return
                }
                self.emitDiagnosticExportForTesting(buildVersion: "test-device")
                self.activeDiagnosticExportTaskForTesting = nil
            }
        }
#endif
    }

    private static func testSkipsSettingsStoreLoad() -> Bool {
#if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_SKIP_SETTINGS_STORE_LOAD"],
              !raw.isEmpty
        else { return false }
        return raw != "0" && raw.lowercased() != "false"
#else
        false
#endif
    }

    private func connectionCredential(for profile: ConnectionProfile) async throws -> RFBConnectionCredential {
        guard let credentialRef = profile.credentialRef else {
            return .none
        }

        guard let password = try await credentialStore?.password(for: credentialRef),
              !password.isEmpty
        else {
            throw AppCredentialError.passwordMissing
        }

        return .vncPassword(password)
    }

    private func credentialFailureDiagnosticRun(
        profile: ConnectionProfile,
        startedAt: Date
    ) -> ConnectionDiagnosticRun {
        ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: startedAt,
            finishedAt: Date(),
            context: Self.diagnosticContext(
                for: profile,
                trigger: .credentialLookup,
                timeout: nil
            ),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "Private profile is selected."
                ),
                DiagnosticStageResult(
                    stage: .authentication,
                    status: .failed,
                    safeTitle: "Credential unavailable",
                    safeDetail: "Saved VNC password could not be loaded from this device.",
                    nextAction: "Update the profile password.",
                    metadata: DiagnosticStageMetadata(failureCode: "credential.passwordMissing")
                )
            ]
        )
    }

    private static func credentialReference(for profileID: ConnectionProfile.ID) -> String {
        "vnc-password:\(profileID.uuidString)"
    }

    private static func helperPairingSecretReference(for profileID: ConnectionProfile.ID) -> String {
        "helper-token:\(profileID.uuidString)"
    }

    private static func helperVideoPairingSecretReference(for profileID: ConnectionProfile.ID) -> String {
        "helper-video-token:\(profileID.uuidString)"
    }

    /// Treat a connection-grid tap as one MainActor-owned intent: select the
    /// requested profile and start that exact profile's connection attempt.
    /// The expected-ID gate prevents an intervening selection from turning
    /// this tap into a connection to a different machine.
    public func connectProfile(id: ConnectionProfile.ID) async {
        guard profiles.contains(where: { $0.id == id }) else {
            return
        }

        selectProfile(id: id)
        await connectSelectedProfile(expectedProfileID: id)
    }

    public func connectSelectedProfile() async {
        await connectSelectedProfile(expectedProfileID: selectedProfileID)
    }

    private func connectSelectedProfile(
        expectedProfileID: ConnectionProfile.ID?
    ) async {
        guard let expectedProfileID,
              selectedProfileID == expectedProfileID,
              let profile = profiles.first(where: { $0.id == expectedProfileID })
        else {
            return
        }

        // Fresh user-initiated connect attempt: clear any pending
        // auto-reconnect, drop the explicit-disconnect latch, and
        // reset the bounded attempt counter so a future drop gets a
        // fresh `maxAttempts` budget.
        cancelPendingReconnect()
        resetFrameDeliveryInteractionState()
        explicitlyDisconnected = false
        reconnectAttempts = 0
        activeStreamProfile = nil
        activeStreamCredential = nil
        resetConnectionQuality()
        resetPointerControl()
        cancelOutboundInputEventQueues()
        stopHelperVideoStreamBootstrap()
        resetVisualTransportState()

        runConnectionChecks()
        startHelperTextBridgeProbes(for: [profile])
        let diagnosticStartedAt = diagnosticRun?.startedAt ?? Date()
        var nextSession = RemoteSession(
            profileID: profile.id,
            state: .connecting,
            hudMessage: "Connecting to \(profile.endpoint)"
        )
        session = nextSession
        composeDraft = ComposeDraft(sessionID: nextSession.id)
        latestComposeSendPreparation = nil
        resetSessionStreamStats()
        resetPreviewThrottle(for: profile.id)

        let credential: RFBConnectionCredential
        do {
            credential = try await connectionCredential(for: profile)
        } catch {
            guard isCurrentConnectionAttempt(
                sessionID: nextSession.id,
                profileID: profile.id
            ) else {
                return
            }
            nextSession.markFailed("Credential unavailable")
            session = nextSession
            activeTextClient = nil
            activePointerClient = nil
            activeFramebufferUpdateRequestSender = nil
            activeKeyEventClient = nil
            keystrokeEmitter = nil
            directKeystrokeMode = .init()
            stickyModifierState = .init()
            resetLiveTypeThroughState()
            resetPointerControl()
            lastEmittedDragCoord = nil
            cancelOutboundInputEventQueues()
            clearSessionFrame()
            resetSessionStreamStats()
            diagnosticRun = credentialFailureDiagnosticRun(
                profile: profile,
                startedAt: diagnosticStartedAt
            )
            recordDiagnosticVerdict(for: profile.id, from: diagnosticRun)
            return
        }

        // Keychain access is an actor-reentrant await. The user may have
        // disconnected, selected another profile, or started a newer retry
        // while the credential was loading; never launch transport work for
        // an attempt that no longer owns the visible session.
        guard isCurrentConnectionAttempt(
            sessionID: nextSession.id,
            profileID: profile.id
        ) else {
            return
        }

        startHelperVideoStreamIfConfigured(profile: profile, sessionID: nextSession.id)

        let initialEncodingPreference = initialStreamEncodingPreference()
        let initialPixelFormatPreference = initialStreamPixelFormatPreference()
        let connector = streamConnectorFactory(
            initialEncodingPreference,
            initialPixelFormatPreference
        )
        stopFrameStream()
        stopIncomingClipboardReceive()
        clearIncomingClipboardReviewState()
        if let streamingClient = connector as? any RFBStreamingClient {
            startFrameStream(
                streamingClient,
                profile: profile,
                session: nextSession,
                credential: credential,
                shouldRenegotiateConfiguredSustainedEncodings: !streamConnectorFactoryAppliesPreferences
            )
            return
        }

        let requestTimeout = frameStreamConfiguration.requestTimeout
        Task {
            do {
                let connectionResult = try await Task.detached {
                    try Self.connectAndReadFirstFrame(
                        connector: connector,
                        host: profile.host,
                        port: UInt16(profile.port),
                        credential: credential,
                        timeout: requestTimeout
                    )
                }.value

                // The non-streaming connector has no streamID, so mirror the
                // streaming path's freshness contract with the immutable
                // attempt session/profile pair plus the explicit-disconnect
                // latch before publishing any first-frame success state.
                guard isCurrentConnectionAttempt(
                    sessionID: nextSession.id,
                    profileID: profile.id
                ) else {
                    return
                }

                nextSession.markFirstFrameReceived(at: connectionResult.frameCapturedAt)
                if let framebuffer = connectionResult.framebuffer {
                    publishSessionFrame(
                        framebuffer: framebuffer,
                        dirtyRectangles: nil,
                        changedPixelCount: nil,
                        serverCursor: nil
                    )
                    cachePreview(
                        framebuffer: framebuffer,
                        for: profile.id,
                        capturedAt: connectionResult.frameCapturedAt,
                        forceDiskSave: true
                    )
                }
                resetSessionStreamStats()
                let textClient = connector as? RemoteClipboardTextClient
                activeTextClient = textClient
                activePointerClient = connector as? RFBPointerEventClient
                activeFramebufferUpdateRequestSender = connector as? (any RFBFramebufferUpdateRequestSending)
                setInputCoordinateSpace(from: connectionResult.serverInit)
                let keyEventClient = connector as? (any RFBKeyEventClient)
                activeKeyEventClient = keyEventClient
                keystrokeEmitter = keyEventClient.map { KeystrokeEmitter(client: $0) }
                lastEmittedDragCoord = nil
                if textClient != nil {
                    startIncomingClipboardReceive(receive: Self.makeReceive(connector: connector))
                }
                session = nextSession
                promoteTypeThroughDefaultOnSessionActivationIfNeeded()
                diagnosticRun = ConnectionDiagnosticRun(
                    profileID: profile.id,
                    startedAt: diagnosticStartedAt,
                    finishedAt: Date(),
                    context: Self.diagnosticContext(
                        for: profile,
                        trigger: .connect,
                        timeout: requestTimeout
                    ),
                    stages: [
                        DiagnosticStageResult(
                            stage: .dns,
                            status: .passed,
                            safeTitle: "Profile ready",
                            safeDetail: "Private profile is selected."
                        ),
                        DiagnosticStageResult(
                            stage: .tcp,
                            status: .passed,
                            safeTitle: "VNC port reached",
                            safeDetail: "TCP connection succeeded."
                        ),
                        DiagnosticStageResult(
                            stage: .rfbHandshake,
                            status: .passed,
                            safeTitle: "VNC handshake complete",
                            safeDetail: "RFB no-auth first-frame path completed."
                        ),
                        DiagnosticStageResult(
                            stage: .firstFrame,
                            status: .passed,
                            safeTitle: "First frame received",
                            safeDetail: "\(connectionResult.serverInit.width)x\(connectionResult.serverInit.height) remote framebuffer is available."
                        )
                    ]
                )
                recordDiagnosticVerdict(for: profile.id, from: diagnosticRun)
            } catch {
                // A late failure is just as stale as a late success. In
                // particular it must not replace the closed session after a
                // Back/Disconnect action or a newer profile/retry session.
                guard isCurrentConnectionAttempt(
                    sessionID: nextSession.id,
                    profileID: profile.id
                ) else {
                    return
                }
                stopHelperVideoStreamBootstrap()
                activeTextClient = nil
                activePointerClient = nil
                activeFramebufferUpdateRequestSender = nil
                lastEmittedDragCoord = nil
                stopIncomingClipboardReceive()
                clearSessionFrame()
                resetSessionStreamStats()
                // Derive the actual failed stage from the error so the
                // user sees an actionable message — not a hardcoded
                // "VNC handshake failed" / "Connection failed" pair
                // regardless of whether the cause was TCP unreachable,
                // wrong password, or a real handshake mismatch
                // (constitution §IV).
                let failedStage = Self.stage(for: error)
                let failure = DiagnosticMessageCatalog.failure(
                    for: failedStage,
                    metadata: Self.diagnosticFailureMetadata(for: error)
                )
                nextSession.markFailed(failure.safeTitle)
                session = nextSession
                diagnosticRun = ConnectionDiagnosticRun(
                    profileID: profile.id,
                    startedAt: diagnosticStartedAt,
                    finishedAt: Date(),
                    context: Self.diagnosticContext(
                        for: profile,
                        trigger: .connect,
                        timeout: requestTimeout
                    ),
                    stages: [
                        DiagnosticStageResult(
                            stage: .dns,
                            status: .passed,
                            safeTitle: "Profile ready",
                            safeDetail: "Private profile is selected."
                        ),
                        failure
                    ]
                )
                recordDiagnosticVerdict(for: profile.id, from: diagnosticRun)
            }
        }
    }

    private func startFrameStream(
        _ streamingClient: any RFBStreamingClient,
        profile: ConnectionProfile,
        session pendingSession: RemoteSession,
        credential: RFBConnectionCredential,
        shouldRenegotiateConfiguredSustainedEncodings: Bool
    ) {
        let streamID = UUID()
        let pump = RFBFramePump(source: streamingClient)
        let configuration = frameStreamConfiguration
        let frameApplicationQueue = SessionStreamFrameApplicationQueue()
        activeFrameStreamID = streamID
        // New RFB session is always full scale. Reset here in addition to
        // the transform-nil sites so reconnect cannot inherit a 0.5 rung
        // and skip the next downscale (no-repeat-rung).
        resetAppleServerDownscaleState()
        activeFramePump = pump
        activeFrameApplicationQueue = frameApplicationQueue
        startFrameApplicationWorker(frameApplicationQueue)
        startMainActorResponsivenessMonitor(
            streamID: streamID,
            sessionID: pendingSession.id,
            profileID: profile.id
        )
        resetPreviewThrottle(for: profile.id)
        // Capture the profile + credential on every fresh stream
        // start so a later drop can reconnect against the same
        // pair.  This is intentionally written every start (not
        // only on the FIRST attempt) so a profile edit between
        // user-initiated connects is honored on the next drop.
        activeStreamProfile = profile
        activeStreamCredential = credential

        activeFrameStreamTask = Task.detached(priority: .userInitiated) { [weak self, frameApplicationQueue] in
            guard let self else {
                return
            }
            defer {
                Task.detached(priority: .utility) {
                    pump.stopContinuousUpdatesIfNeeded(timeout: configuration.requestTimeout)
                }
                Task.detached(priority: .utility) {
                    await frameApplicationQueue.close()
                }
            }

            var completedInitialHandshake = false
            var emptyUpdateStreak = 0
            // Scoped to this frame-stream task. Reconnect starts a new
            // stream task, so client-pressure history never crosses sessions.
            var streamPressurePacingState = SessionStreamPressurePacingState()
            do {
                let serverInit = try streamingClient.connectSession(
                    host: profile.host,
                    port: UInt16(profile.port),
                    credential: credential,
                    timeout: configuration.requestTimeout
                )
                completedInitialHandshake = true

                guard await self.isCurrentStream(streamID, sessionID: pendingSession.id, profileID: profile.id) else {
                    return
                }

                await self.bindActiveStreamingClients(streamingClient, serverInit: serverInit)
                if shouldRenegotiateConfiguredSustainedEncodings {
                    await self.renegotiateConfiguredSustainedEncodingsIfNeeded(
                        transportControl: streamingClient as? any RFBTransportControlClient,
                        requestTimeout: configuration.requestTimeout
                    )
                }
                // Constitution §I: outgoing compose-and-send is the primary
                // text path; incoming server clipboard is secondary. It is
                // drained inside the loop below rather than by a second reader:
                // `receiveServerCutText` issues its own `readExactly(8)`, and
                // running that concurrently with the frame pump's
                // `requestFramebufferUpdate` raced on the same NWConnection and
                // split an FBUpdate header (`00 00 00 01 00 00 00 00`) between
                // the two, surfacing as `unexpectedMessageType` out of
                // `parseFramebufferUpdateHeader`. The frame loop already
                // dispatches by msg_type, so it keeps what it decodes.

                while await self.shouldRequestAnotherFrame(configuration: configuration, pump: pump) {
                    if Task.isCancelled {
                        pump.cancel()
                        return
                    }
                    let requestTimeout = configuration.requestTimeout
                    // Sample the request→frame round-trip so the
                    // connection-quality chip reflects real latency
                    // (spec 003 US4).  Wall-clock around the detached
                    // pump call is a reasonable proxy; the value is fed
                    // to the estimator and then discarded — never
                    // logged (constitution §IV).
                    let requestStart = Date()
                    let isIncrementalRequest = pump.deliveredFrameCount > 0
                    let requestRegion = isIncrementalRequest
                        ? await self.currentViewportRequestRegion(
                            incrementalRequestIndex: pump.deliveredFrameCount
                        )
                        : nil
                    if isIncrementalRequest,
                       let scaler = streamingClient as? any RFBServerScalingClient
                    {
                        let advertisedAppleSecurity = scaler.serverAdvertisedAppleSecurity
                        if let rung = await self.requestedAppleServerDownscaleRung(
                            serverAdvertisedAppleSecurity: advertisedAppleSecurity,
                            fallbackFramebufferWidth: serverInit.width,
                            fallbackFramebufferHeight: serverInit.height
                        ) {
                            do {
                                try scaler.sendAppleScaleFactor(rung, timeout: 2)
                                await self.noteAppliedServerDownscaleRung(rung)
                            } catch {
                                // Non-fatal: leave appliedServerDownscaleRung
                                // unchanged. The next incremental tick
                                // re-evaluates.
                            }
                        }
                    }
                    let initialRequestRegion = isIncrementalRequest
                        ? nil
                        : await self.currentViewportInitialRequestRegion(serverInit: serverInit)
                    let maybeFrame = try pump.nextFrame(
                        requestTimeout: requestTimeout,
                        updateMode: configuration.updateMode,
                        requestRegion: requestRegion,
                        initialRequestRegion: initialRequestRegion,
                        requestPipelineDepth: configuration.requestPipelineDepth
                    )
                    let roundTripMilliseconds = Date().timeIntervalSince(requestStart) * 1000
                    guard let frame = maybeFrame else {
                        return
                    }
                    if !frame.transportIdleTimedOut {
                        await self.recordFrameLatency(
                            milliseconds: roundTripMilliseconds,
                            streamID: streamID,
                            sessionID: pendingSession.id,
                            profileID: profile.id,
                            transportControl: streamingClient as? any RFBTransportControlClient,
                            requestTimeout: requestTimeout
                        )
                    }

                    guard await self.isCurrentStream(streamID, sessionID: pendingSession.id, profileID: profile.id) else {
                        pump.cancel()
                        return
                    }

                    // The frame loop is the only reader on this connection, so
                    // a ServerCutText the server interleaved with the frames
                    // was decoded in there. Drain it here rather than running a
                    // second reader — that is what used to split an update
                    // header between two tasks and is why this path shipped
                    // with the incoming clipboard disabled.
                    if let incomingClipboardText = streamingClient.takeIncomingClipboardText() {
                        await self.recordIncomingClipboardFromStream(
                            incomingClipboardText,
                            streamID: streamID,
                            sessionID: pendingSession.id,
                            profileID: profile.id
                        )
                    }

                    let thermalState = await self.currentSessionStreamThermalState()

                    // An empty incremental update (zero changed pixels)
                    // means the connection is alive but framebuffer
                    // pixels did not change; the server polled empty
                    // instead of holding the request. Cursor
                    // pseudo-encoding updates can still carry a real
                    // server cursor shape without pixel damage, so keep
                    // that memory-only overlay current while still
                    // skipping framebuffer publish + GPU upload + PiP
                    // forward. Content frames take the full apply path.
                    let isEmptyUpdate = frame.isIncremental && frame.changedPixelCount == 0
                    emptyUpdateStreak = isEmptyUpdate ? emptyUpdateStreak + 1 : 0
                    let droppedFrameApplicationWorkCount = await frameApplicationQueue.enqueue(
                        StreamFrameApplicationWork(
                            frame: frame,
                            serverInit: serverInit,
                            profile: profile,
                            sessionID: pendingSession.id,
                            streamID: streamID,
                            isEmptyUpdate: isEmptyUpdate
                        )
                    )

                    let previousAppFrameApplyMilliseconds = await self.consumeAsyncAppFrameApplyMilliseconds()
                    streamPressurePacingState.recordFrameApplicationBacklogDrop(
                        droppedFrameApplicationWorkCount
                    )
                    streamPressurePacingState.record(
                        frame: frame,
                        appFrameApplyMilliseconds: previousAppFrameApplyMilliseconds
                    )
                    let usesAdaptiveClientPressurePacing = streamPressurePacingState
                        .usesAdaptivePowerSaverPacing
                    if !frame.isIncremental {
                        await self.scheduleActiveDiagnosticExportForTestingIfRequested()
                        let startupPreflightResult = await self.performStartupPreflightFrames(
                            policy: await self.currentStreamStartupPreflightPolicy(),
                            configuration: configuration,
                            pump: pump,
                            streamID: streamID,
                            sessionID: pendingSession.id,
                            profileID: profile.id
                        )
                        await self.recordSessionStreamStartupPreflight(startupPreflightResult)
                    }
                    let streamPacingWakeGeneration = await self.streamPacingWakeGeneration
                    let pacingDecision = await self.recordSessionStreamStatsAndPacingDecision(
                        for: frame,
                        configuration: configuration,
                        thermalState: thermalState,
                        usesAdaptiveClientPressurePacing: usesAdaptiveClientPressurePacing,
                        appFrameApplyMilliseconds: nil,
                        isEmptyUpdate: isEmptyUpdate,
                        emptyUpdateStreak: emptyUpdateStreak
                    )
                    if pacingDecision.delay > 0 {
                        try await self.sleepForStreamPacing(
                            pacingDecision,
                            streamID: streamID,
                            sessionID: pendingSession.id,
                            profileID: profile.id,
                            wakeGeneration: streamPacingWakeGeneration
                        )
                    }
                }
            } catch is CancellationError {
                pump.cancel()
            } catch {
                await self.handleStreamFailure(
                    profile: profile,
                    sessionID: pendingSession.id,
                    streamID: streamID,
                    error: error,
                    completedInitialHandshake: completedInitialHandshake
                )
            }
        }
    }

    private func bindActiveStreamingClients(_ streamingClient: any RFBStreamingClient, serverInit: RFBServerInit) {
        activeTextClient = streamingClient
        activePointerClient = streamingClient
        activeFramebufferUpdateRequestSender = streamingClient as? (any RFBFramebufferUpdateRequestSending)
        activeKeyEventClient = streamingClient
        keystrokeEmitter = KeystrokeEmitter(client: streamingClient)
        setInputCoordinateSpace(from: serverInit)
        lastEmittedDragCoord = nil
    }

    private func currentSessionStreamThermalState() -> SessionStreamThermalState {
        thermalStateProvider()
    }

    private func startMainActorResponsivenessMonitor(
        streamID: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) {
        let monitorID = UUID()
        let probeInterval = Duration.seconds(Self.mainActorResponsivenessProbeIntervalSeconds)
        mainActorResponsivenessMonitorID = monitorID
        mainActorResponsivenessTask?.cancel()
        mainActorResponsivenessTask = Task(priority: .utility) { @MainActor [weak self] in
            while !Task.isCancelled {
                let expectedWakeAt = Date().addingTimeInterval(
                    Self.mainActorResponsivenessProbeIntervalSeconds
                )
                do {
                    try await Task.sleep(for: probeInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                guard let self,
                      self.mainActorResponsivenessMonitorID == monitorID,
                      self.isCurrentStream(streamID, sessionID: sessionID, profileID: profileID)
                else {
                    return
                }
                self.recordMainActorResponsivenessDelay(
                    milliseconds: elapsedMilliseconds(since: expectedWakeAt)
                )
            }
        }
    }

    private func stopMainActorResponsivenessMonitor() {
        mainActorResponsivenessTask?.cancel()
        mainActorResponsivenessTask = nil
        mainActorResponsivenessMonitorID = nil
    }

    private func sleepForStreamPacing(
        _ decision: SessionStreamPacingDecision,
        streamID: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        wakeGeneration: UInt64
    ) async throws {
        let delay = decision.delay
        if let streamPacingSleepOverride {
            // Tests own the full sleep interval through this hook; production
            // wake polling stays on the path below.
            try await streamPacingSleepOverride(delay)
            return
        }

        let pollInterval = Self.streamPacingWakePollIntervalSeconds
        let deadline = Date().addingTimeInterval(delay)
        while true {
            guard isCurrentStream(streamID, sessionID: sessionID, profileID: profileID),
                  shouldContinueStreamPacingSleep(
                    decision,
                    wakeGeneration: wakeGeneration
                  )
            else {
                return
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                return
            }
            try await Task.sleep(for: .seconds(min(remaining, pollInterval)))
        }
    }

    private func shouldContinueStreamPacingSleep(
        _ decision: SessionStreamPacingDecision,
        wakeGeneration: UInt64
    ) -> Bool {
        guard streamPacingWakeGeneration == wakeGeneration else {
            return false
        }
        guard decision.usesHelperVideoPrimaryVNCSamplingPacing else {
            return true
        }
        return isHelperVideoHealthyPrimaryVisualTransport
    }

    private var isHelperVideoHealthyPrimaryVisualTransport: Bool {
        visualTransportMode == .helperVideo
            && helperVideoStreamDescriptor != nil
            && helperVideoStreamHealth.state == .healthy
    }

    private func publishSessionFrame(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]?,
        changedPixelCount: Int?,
        serverCursor: RFBServerCursor?
    ) {
        latestFramebuffer = framebuffer
        setInputCoordinateSpace(width: framebuffer.width, height: framebuffer.height)
        latestFrameDirtyRectangles = dirtyRectangles
        latestFrameChangedPixelCount = changedPixelCount.map { max($0, 0) }
        if let serverCursor {
            latestServerCursor = serverCursor
        }
        frameStore.publish(
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            serverCursor: latestServerCursor
        )
    }

    private func publishServerCursor(_ serverCursor: RFBServerCursor) {
        latestServerCursor = serverCursor
        frameStore.publishServerCursor(serverCursor)
    }

    private func clearSessionFrame() {
        latestFramebuffer = nil
        inputCoordinateSpace = nil
        latestFrameDirtyRectangles = nil
        latestFrameChangedPixelCount = nil
        latestServerCursor = nil
        frameStore.clear()
    }

    private func setInputCoordinateSpace(from serverInit: RFBServerInit) {
        setInputCoordinateSpace(width: serverInit.width, height: serverInit.height)
    }

    private func setInputCoordinateSpace(width: Int, height: Int) {
        inputCoordinateSpace = RemoteFramebufferCoordinateSpace(width: width, height: height)
        centerTrackpadCursorIfUnplaced()
    }

    /// Place the trackpad cursor the moment the remote coordinate space
    /// becomes known (spec 023 FR-002). Trackpad is the product default,
    /// so a fresh session would otherwise start with an invisible cursor
    /// parked at the framebuffer origin and the user's first drag would
    /// walk the remote pointer out of the top-left corner.
    ///
    /// Only an *unplaced* cursor is moved: a later coordinate-space
    /// update (a DesktopSize resize, a scale round-trip) must never
    /// teleport a cursor the user has already positioned. Constitution
    /// §IV: the position is published to the view and never logged.
    private func centerTrackpadCursorIfUnplaced() {
        guard pointerControlMode.isTrackpad,
              !resolvedTrackpadCursor.isVisible
        else {
            return
        }
        publishTrackpadCursor(.centered(in: currentFramebufferSize), immediately: true)
    }

    private func currentInputCoordinateSpace() -> RemoteFramebufferCoordinateSpace? {
        if let inputCoordinateSpace {
            return inputCoordinateSpace
        }
        if let latestFramebuffer,
           let coordinateSpace = RemoteFramebufferCoordinateSpace(
            width: latestFramebuffer.width,
            height: latestFramebuffer.height
           ) {
            return coordinateSpace
        }
        return nil
    }

    private func recordSessionStreamStatsAndPacingDecision(
        for frame: RFBFramePumpFrame,
        configuration: RFBFramePumpConfiguration,
        thermalState: SessionStreamThermalState,
        usesAdaptiveClientPressurePacing: Bool,
        appFrameApplyMilliseconds: Int?,
        isEmptyUpdate: Bool,
        emptyUpdateStreak: Int
    ) -> SessionStreamPacingDecision {
        recordSessionStreamStats(
            for: frame,
            thermalState: thermalState,
            usesAdaptiveClientPressurePacing: usesAdaptiveClientPressurePacing,
            appFrameApplyMilliseconds: appFrameApplyMilliseconds
        )
        let usesPowerSaverPacing = lowPowerModeProvider()
            || appSettings.streamPowerMode == .powerSaver
            || usesAdaptiveClientPressurePacing
        let frameDeliveryPriority = frameDeliveryPriority(for: frameDeliveryInteractionReasons)
        let usesActiveInputPacing = frameDeliveryPriority == .textInput
            || (frameDeliveryPriority == .viewportNavigation && !isViewportInteractionActive)
        let activeInputPacingInterval = usesActiveInputPacing
            ? SessionFrameApplicationWorkerPacing.contentFrameMinimumInterval(
                for: frameDeliveryPriority
            )
            : nil
        let usesViewportInteractionPacing = frameDeliveryPriority == .viewportNavigation
            && isViewportInteractionActive
        let helperVideoPrimaryVNCSamplingInterval = isHelperVideoHealthyPrimaryVisualTransport
            ? StreamPressurePacingDefaults.helperVideoPrimaryVNCFallbackSamplingIntervalSeconds
            : nil
        let viewportInteractionContentFrameInterval = isEmptyUpdate
            ? StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds
            : Self.viewportInteractionContentFrameInterval(
                for: frame,
                currentFramebuffer: latestFramebuffer,
                frameStrategy: viewportInteractionFrameStrategy
            )

        // Adaptive pacing: request the next content frame as fast as the
        // configured active cap allows; back off only when local pressure,
        // thermal state, or viewport interaction asks for breathing room.
        let pacingDecision = isEmptyUpdate
            ? SessionStreamPacingPolicy.decision(
                for: .emptyUpdate,
                configuredDelay: configuration.idleFrameInterval,
                thermalState: thermalState,
                usesPowerSaverPacing: usesPowerSaverPacing,
                activeInputPacingInterval: activeInputPacingInterval,
                usesViewportInteractionPacing: usesViewportInteractionPacing,
                helperVideoPrimaryVNCSamplingInterval: helperVideoPrimaryVNCSamplingInterval,
                emptyUpdateStreak: emptyUpdateStreak
            )
            : SessionStreamPacingPolicy.decision(
                for: .contentFrame,
                configuredDelay: configuration.frameInterval,
                thermalState: thermalState,
                usesPowerSaverPacing: usesPowerSaverPacing,
                activeInputPacingInterval: activeInputPacingInterval,
                usesViewportInteractionPacing: usesViewportInteractionPacing,
                helperVideoPrimaryVNCSamplingInterval: helperVideoPrimaryVNCSamplingInterval,
                viewportInteractionContentFrameInterval: viewportInteractionContentFrameInterval
            )
        recordSessionStreamPacingDecision(pacingDecision)
        return pacingDecision
    }

    private func cachePreview(
        framebuffer: RFBRawFramebuffer,
        for profileID: ConnectionProfile.ID,
        capturedAt: Date,
        forceDiskSave: Bool
    ) {
        let shouldPublish: Bool
        if forceDiskSave {
            shouldPublish = true
        } else if let lastPublishedAt = lastPreviewPublishAt[profileID] {
            shouldPublish = capturedAt.timeIntervalSince(lastPublishedAt)
                >= Self.previewPublishMinimumInterval
        } else {
            shouldPublish = true
        }

        guard shouldPublish else {
            return
        }

        lastPreviewPublishAt[profileID] = capturedAt
        let shouldSave: Bool
        let storeForSave = profilePreviewStore
        if forceDiskSave {
            shouldSave = true
        } else if let lastSavedAt = lastPreviewSaveAt[profileID] {
            shouldSave = capturedAt.timeIntervalSince(lastSavedAt) >= Self.previewSaveMinimumInterval
        } else {
            shouldSave = true
        }

        if shouldSave {
            lastPreviewSaveAt[profileID] = capturedAt
        }

        // Thumbnail sampling walks framebuffer pixels. Keep it off MainActor so
        // the first visible frame cannot stall gestures or soft-keyboard input.
        let thumbnailTask = Task.detached(priority: .utility) {
            ProfilePreviewThumbnail(
                framebuffer: framebuffer,
                capturedAt: capturedAt
            )
        }

        Task { [weak self, storeForSave, profileID, shouldSave, thumbnailTask] in
            guard let thumbnail = await thumbnailTask.value else {
                return
            }
            guard let self else {
                return
            }
            guard self.profiles.contains(where: { $0.id == profileID }) else {
                return
            }
            self.profilePreviews[profileID] = thumbnail
            if shouldSave, let storeForSave {
                try? await storeForSave.saveThumbnail(thumbnail, for: profileID)
            }
        }
    }

    private func shouldRequestAnotherFrame(
        configuration: RFBFramePumpConfiguration,
        pump: RFBFramePump
    ) -> Bool {
        guard let maxFrames = configuration.maxFrames else {
            return true
        }

        return pump.deliveredFrameCount < maxFrames
    }

    private func currentStreamStartupPreflightPolicy() -> SessionStreamStartupPreflightPolicy {
        if let streamStartupPreflightPolicyOverride {
            return streamStartupPreflightPolicyOverride
        }
        return SessionStreamStartupPreflightPolicy(mode: appSettings.startupPreflightMode)
    }

    private func performStartupPreflightFrames(
        policy: SessionStreamStartupPreflightPolicy,
        configuration: RFBFramePumpConfiguration,
        pump: RFBFramePump,
        streamID: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) async -> SessionStreamStartupPreflightResult {
        guard policy.hiddenFrameCount > 0 else {
            return .notRequested
        }

        let requestTimeout = min(
            configuration.requestTimeout,
            policy.requestTimeout
        )
        guard requestTimeout > 0 else {
            return SessionStreamStartupPreflightResult(
                requestedHiddenFrameCount: policy.hiddenFrameCount,
                consumedHiddenFrameCount: 0,
                outcome: .failed
            )
        }

        var consumedHiddenFrameCount = 0
        for _ in 0..<policy.hiddenFrameCount {
            if Task.isCancelled {
                pump.cancel()
                return SessionStreamStartupPreflightResult(
                    requestedHiddenFrameCount: policy.hiddenFrameCount,
                    consumedHiddenFrameCount: consumedHiddenFrameCount,
                    outcome: .cancelled
                )
            }
            guard isCurrentStream(streamID, sessionID: sessionID, profileID: profileID) else {
                pump.cancel()
                return SessionStreamStartupPreflightResult(
                    requestedHiddenFrameCount: policy.hiddenFrameCount,
                    consumedHiddenFrameCount: consumedHiddenFrameCount,
                    outcome: .staleSession
                )
            }
            do {
                // `nextFrame` derives incremental=true from sequence > 1;
                // updateMode only selects request/response vs continuous transport.
                let frameTask = Task.detached(priority: Task.currentPriority) {
                    try pump.nextFrame(
                        requestTimeout: requestTimeout,
                        updateMode: configuration.updateMode
                    )
                }
                let hiddenFrame = try await withTaskCancellationHandler {
                    try await frameTask.value
                } onCancel: {
                    frameTask.cancel()
                    pump.cancel()
                }
                guard hiddenFrame != nil else {
                    return SessionStreamStartupPreflightResult(
                        requestedHiddenFrameCount: policy.hiddenFrameCount,
                        consumedHiddenFrameCount: consumedHiddenFrameCount,
                        outcome: .cancelled
                    )
                }
                consumedHiddenFrameCount += 1
            } catch RFBNetworkClientError.timedOut {
                return SessionStreamStartupPreflightResult(
                    requestedHiddenFrameCount: policy.hiddenFrameCount,
                    consumedHiddenFrameCount: consumedHiddenFrameCount,
                    outcome: .timedOut
                )
            } catch RFBNetworkClientError.readTimedOut {
                return SessionStreamStartupPreflightResult(
                    requestedHiddenFrameCount: policy.hiddenFrameCount,
                    consumedHiddenFrameCount: consumedHiddenFrameCount,
                    outcome: .timedOut
                )
            } catch is CancellationError {
                pump.cancel()
                return SessionStreamStartupPreflightResult(
                    requestedHiddenFrameCount: policy.hiddenFrameCount,
                    consumedHiddenFrameCount: consumedHiddenFrameCount,
                    outcome: .cancelled
                )
            } catch {
                return SessionStreamStartupPreflightResult(
                    requestedHiddenFrameCount: policy.hiddenFrameCount,
                    consumedHiddenFrameCount: consumedHiddenFrameCount,
                    outcome: .failed
                )
            }
        }
        return SessionStreamStartupPreflightResult(
            requestedHiddenFrameCount: policy.hiddenFrameCount,
            consumedHiddenFrameCount: consumedHiddenFrameCount,
            outcome: .consumed
        )
    }

    private func resetSessionStreamStats() {
        sessionStreamStats = SessionStreamStats()
        pendingAsyncAppFrameApplyMilliseconds = nil
        hasScheduledActiveDiagnosticExportForTesting = false
        activeDiagnosticExportTaskForTesting?.cancel()
        activeDiagnosticExportTaskForTesting = nil
    }

    private func resetPreviewThrottle(for profileID: ConnectionProfile.ID) {
        lastPreviewPublishAt.removeValue(forKey: profileID)
    }

    private func recordSessionStreamStats(
        for frame: RFBFramePumpFrame,
        thermalState: SessionStreamThermalState,
        usesAdaptiveClientPressurePacing: Bool,
        appFrameApplyMilliseconds: Int?
    ) {
        sessionStreamStats.record(
            frame: frame,
            thermalState: thermalState,
            usesAdaptiveClientPressurePacing: usesAdaptiveClientPressurePacing,
            appFrameApplyMilliseconds: appFrameApplyMilliseconds
        )
    }

    private func recordSessionStreamPacingDecision(_ decision: SessionStreamPacingDecision) {
        sessionStreamStats.recordPacingDecision(decision)
    }

    private func recordSessionStreamStartupPreflight(_ result: SessionStreamStartupPreflightResult) {
        sessionStreamStats.recordStartupPreflight(result)
    }

    public func recordRendererUploadTiming(milliseconds: Int) {
        sessionStreamStats.recordRendererUploadTiming(milliseconds: milliseconds)
    }

    private func recordAppFrameApplyTiming(milliseconds: Int) {
        let clampedMilliseconds = max(milliseconds, 0)
        sessionStreamStats.recordAppFrameApplyTiming(milliseconds: clampedMilliseconds)
        pendingAsyncAppFrameApplyMilliseconds = clampedMilliseconds
    }

    private func recordMainActorResponsivenessDelay(milliseconds: Int) {
        sessionStreamStats.recordMainActorResponsivenessDelay(milliseconds: milliseconds)
    }

    private func consumeAsyncAppFrameApplyMilliseconds() -> Int? {
        let milliseconds = pendingAsyncAppFrameApplyMilliseconds
        pendingAsyncAppFrameApplyMilliseconds = nil
        return milliseconds
    }

    /// Spec 028. Stores the latest frame presentation ledger so the perf HUD
    /// and the diagnostic export can say why the picture is not updating.
    public func recordFramePresentationLedger(_ ledger: FramePresentationLedger) {
        sessionStreamStats.recordFramePresentationLedger(ledger)
    }

    public func recordViewportRedrawDiagnostics(_ diagnostics: ViewportRedrawDiagnostics) {
        sessionStreamStats.recordViewportRedrawDiagnostics(diagnostics)
    }

    public func setComposeInputEditingActive(_ isActive: Bool) {
        setFrameDeliveryInteractionReason(.composeFocus, active: isActive)
        // Local keyboard focus loss seals the open Live window (FR-011): the
        // mirror is only valid while the field owns focus, so resumed typing
        // opens a fresh forward-only window and no delete crosses the seal.
        if !isActive, liveTypeThroughMode.isActive {
            sealLiveWindow(reason: .focusLost)
        }
    }

    func markTransientFrameDeliveryInteractionActivityForTesting() {
        markTransientFrameDeliveryInteractionActivity()
    }

    private func markTransientFrameDeliveryInteractionActivity() {
        streamPacingWakeGeneration &+= 1
        setFrameDeliveryInteractionReason(.transientInteraction, active: true)
        transientFrameDeliveryInteractionExpiresAt =
            ContinuousClock.now + Self.transientFrameDeliveryInteractionPriorityDuration
        guard transientFrameDeliveryInteractionTask == nil else {
            return
        }
        transientFrameDeliveryInteractionTask = Task { @MainActor [weak self] in
            while true {
                guard let self,
                      let expiresAt = self.transientFrameDeliveryInteractionExpiresAt
                else {
                    return
                }

                let now = ContinuousClock.now
                if now < expiresAt {
                    do {
                        try await Task.sleep(for: now.duration(to: expiresAt))
                    } catch {
                        return
                    }
                    continue
                }

                self.transientFrameDeliveryInteractionExpiresAt = nil
                self.transientFrameDeliveryInteractionTask = nil
                self.setFrameDeliveryInteractionReason(.transientInteraction, active: false)
                return
            }
        }
    }

    private func setFrameDeliveryInteractionReason(
        _ reason: FrameDeliveryInteractionReason,
        active: Bool
    ) {
        let wasFocusedInputActive = isFocusedInputChromeCoalescingActive
        let didChange: Bool
        if active {
            didChange = frameDeliveryInteractionReasons.insert(reason).inserted
        } else {
            didChange = frameDeliveryInteractionReasons.remove(reason) != nil
        }
        guard didChange else {
            return
        }
        frameStore.setDeliveryPriority(frameDeliveryPriority(for: frameDeliveryInteractionReasons))
        if !wasFocusedInputActive && isFocusedInputChromeCoalescingActive {
            deferFocusedInputChromeUpdates()
        }
        if wasFocusedInputActive && !isFocusedInputChromeCoalescingActive {
            flushFocusedInputChromeUpdates()
        }
    }

    private func frameDeliveryPriority(
        for reasons: Set<FrameDeliveryInteractionReason>
    ) -> SessionFrameDeliveryPriority {
        if reasons.contains(.composeFocus) {
            return .textInput
        }
        if reasons.contains(.viewportGesture) || reasons.contains(.transientInteraction) {
            return .viewportNavigation
        }
        return .visual
    }

    private var isFocusedInputChromeCoalescingActive: Bool {
        frameDeliveryInteractionReasons.contains(.composeFocus)
    }

    private func publishConnectionQuality(_ quality: ConnectionQuality) {
        guard isFocusedInputChromeCoalescingActive else {
            pendingFocusedInputConnectionQuality = nil
            if connectionQuality != quality {
                connectionQuality = quality
            }
            return
        }

        guard connectionQuality != quality else {
            pendingFocusedInputConnectionQuality = nil
            return
        }
        pendingFocusedInputConnectionQuality = quality
    }

    private func publishHelperVideoStreamHealth(_ health: HelperVideoStreamHealth) {
        guard isFocusedInputChromeCoalescingActive else {
            pendingFocusedInputHelperVideoHealth = nil
            helperVideoStreamHealth = health
            return
        }

        guard helperVideoStreamHealth != health else {
            pendingFocusedInputHelperVideoHealth = nil
            return
        }
        pendingFocusedInputHelperVideoHealth = health
    }

    private func flushFocusedInputChromeUpdates() {
        if let quality = pendingFocusedInputConnectionQuality {
            pendingFocusedInputConnectionQuality = nil
            if connectionQuality != quality {
                connectionQuality = quality
            }
        }

        if let health = pendingFocusedInputHelperVideoHealth {
            pendingFocusedInputHelperVideoHealth = nil
            helperVideoStreamHealth = health
        }

        if let review = pendingFocusedInputIncomingClipboard {
            pendingFocusedInputIncomingClipboard = nil
            pendingIncomingClipboard = review
        }

        if isFocusedInputSendFeedbackClearPending {
            clearComposeSendFeedbackState()
        }
    }

    private func cancelFocusedInputChromeUpdates() {
        pendingFocusedInputConnectionQuality = nil
        pendingFocusedInputHelperVideoHealth = nil
        pendingFocusedInputIncomingClipboard = nil
        isFocusedInputSendFeedbackClearPending = false
    }

    private func deferFocusedInputChromeUpdates() {
        if let review = pendingIncomingClipboard {
            pendingIncomingClipboard = nil
            pendingFocusedInputIncomingClipboard = review
        }
    }

    private func clearIncomingClipboardReviewState() {
        pendingIncomingClipboard = nil
        pendingFocusedInputIncomingClipboard = nil
    }

    private func clearComposeSendFeedbackAfterLocalEdit() {
        guard latestInjectionAttempt != nil || latestComposeSendPreparation != nil else {
            isFocusedInputSendFeedbackClearPending = false
            return
        }
        guard isFocusedInputChromeCoalescingActive else {
            clearComposeSendFeedbackState()
            return
        }
        isFocusedInputSendFeedbackClearPending = true
    }

    private func clearComposeSendFeedbackState() {
        latestInjectionAttempt = nil
        latestComposeSendPreparation = nil
        isFocusedInputSendFeedbackClearPending = false
    }

    public func recordOutboundInputEvent(
        queueDelayMilliseconds: Int,
        operationMilliseconds: Int,
        timedOut: Bool = false
    ) {
        sessionStreamStats.recordOutboundInputEvent(
            queueDelayMilliseconds: queueDelayMilliseconds,
            operationMilliseconds: operationMilliseconds,
            timedOut: timedOut
        )
    }

    public func setViewportInteractionActive(
        _ isActive: Bool,
        frameStrategy: ViewportInteractionFrameStrategy = .liveRemoteFrames
    ) {
        if isActive {
            setFrameDeliveryInteractionReason(.viewportGesture, active: true)
            if isViewportInteractionActive {
                viewportInteractionFrameStrategy = frameStrategy
                return
            }
            viewportInteractionFrameStrategy = frameStrategy
            viewportInteractionStartedAt = Date()
            lastViewportInteractionFramePublishedAt = nil
            return
        }

        guard isViewportInteractionActive else {
            setFrameDeliveryInteractionReason(.viewportGesture, active: false)
            return
        }
        viewportInteractionFrameStrategy = nil
        viewportInteractionStartedAt = nil
        lastViewportInteractionFramePublishedAt = nil
        setFrameDeliveryInteractionReason(.viewportGesture, active: false)
        flushDeferredViewportInteractionFrame()
    }

    public func updateViewportTransform(_ transform: ViewportTransform) {
        latestViewportTransform = transform
        latestViewportSize = transform.viewSize
    }

    public func updateViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }
        latestViewportSize = size
    }

    public func updateViewportDisplayPixelScale(_ scale: CGFloat) {
        guard scale > 0 else {
            return
        }
        viewportDisplayPixelsPerPoint = scale
    }

    /// Clears the Apple ScaleFactor ladder. Called both when
    /// `latestViewportTransform` is niled (profile change / disconnect)
    /// and when a new stream starts (streamID bump): a fresh RFB session
    /// is always full scale, so hysteresis and the applied rung must not
    /// leak across sessions.
    private func resetAppleServerDownscaleState() {
        appleServerDownscalePolicy.reset()
        appliedServerDownscaleRung = AppleServerDownscalePolicy.fullRung
        serverDownscaleUnscaledFramebufferWidth = nil
    }

    /// Single-owner outbound pointer-coordinate mapping (spec 018):
    /// pointer commands are computed in the framebuffer the view renders
    /// (the scaled one once the DesktopSize resize lands), but the
    /// server's pointer input space stays the unscaled framebuffer.
    /// Every pointer send flows through `enqueuePointerCommands`, so this
    /// is the one place coordinates leave the scaled space.
    private func pointerBatchMappedForServerDownscale(
        _ batch: RFBPointerCommandBatch
    ) -> RFBPointerCommandBatch {
        let mapping = AppleServerDownscalePolicy.pointerCoordinateMapping(
            knownUnscaledWidth: serverDownscaleUnscaledFramebufferWidth,
            currentWidth: latestFramebuffer?.width
        )
        serverDownscaleUnscaledFramebufferWidth = mapping.unscaledWidthToStore
        guard mapping.multiplier != 1, !batch.isEmpty else {
            return batch
        }
        switch batch {
        case .none:
            return batch
        case let .one(command):
            return .one(AppleServerDownscalePolicy.mappedPointerCommand(command, multiplier: mapping.multiplier))
        case let .two(first, second):
            return .two(
                AppleServerDownscalePolicy.mappedPointerCommand(first, multiplier: mapping.multiplier),
                AppleServerDownscalePolicy.mappedPointerCommand(second, multiplier: mapping.multiplier)
            )
        case let .many(commands):
            return .many(commands.map {
                AppleServerDownscalePolicy.mappedPointerCommand($0, multiplier: mapping.multiplier)
            })
        }
    }

    /// Spec 031. Whether the app may ask the server to halve its framebuffer.
    ///
    /// Only where the user has asked for less data. The downscale was a
    /// compensation for slowness, and the slowness turned out to be spec 030's
    /// viewport-scoped request defect — Apple answered those in 540-787 ms
    /// instead of 33 ms. **The measurements that showed 5.66-7.08 content fps
    /// after that fix were taken at full 3024x1964 resolution**, because the
    /// live benchmark never sends ScaleFactor at all, so the pixels were being
    /// spent on a problem that no longer exists.
    ///
    /// The policy's "visually lossless" rule is an inequality over framebuffer
    /// pixels per device pixel, and it had never been checked against a phone
    /// screen — constitution §III requires that before such a claim counts. On
    /// build 9 the founder looked at it: "해상도 너무 낮은데... 왜 이렇게
    /// 뭉개지지". The margin explains it. After halving, 1512 framebuffer pixels
    /// cover about 1290 device pixels, so any zoom at all magnifies a
    /// half-resolution source through one bilinear tap.
    ///
    /// Power saver and Low Data Mode keep it, which turns the trade into
    /// something the user chose rather than something the app inferred.
    private var mayRequestAppleServerDownscale: Bool {
        appSettings.streamPowerMode == .powerSaver || lowPowerModeProvider()
    }

    private func requestedAppleServerDownscaleRung(
        serverAdvertisedAppleSecurity: Bool,
        fallbackFramebufferWidth: Int,
        fallbackFramebufferHeight: Int
    ) -> Double? {
        guard mayRequestAppleServerDownscale else {
            // Restore full resolution if a previous mode had halved it, then
            // stay quiet.
            if appliedServerDownscaleRung != AppleServerDownscalePolicy.fullRung {
                appleServerDownscalePolicy.reset()
                return AppleServerDownscalePolicy.fullRung
            }
            return nil
        }
        let liveWidth = latestFramebuffer?.width ?? fallbackFramebufferWidth
        let liveHeight = latestFramebuffer?.height ?? fallbackFramebufferHeight
        return appleServerDownscalePolicy.requestedRung(
            transform: latestViewportTransform,
            liveFramebufferWidth: liveWidth,
            liveFramebufferHeight: liveHeight,
            displayPixelsPerPoint: viewportDisplayPixelsPerPoint,
            serverAdvertisedAppleSecurity: serverAdvertisedAppleSecurity,
            currentAppliedRung: appliedServerDownscaleRung
        )
    }

    private func noteAppliedServerDownscaleRung(_ rung: Double) {
        appliedServerDownscaleRung = rung
        // Spec 031: make the rung readable from a diagnostic export. Its absence
        // is why the founder's soft-picture report could not be attributed
        // without a direct RFB probe.
        sessionStreamStats.recordAppleServerDownscaleRung(rung)
        // Capture the unscaled pointer-space baseline at the moment the
        // downscale is requested — the framebuffer is still unscaled here
        // (the DesktopSize resize lands later), and pointer traffic alone
        // cannot establish it (a first tap after the resize would adopt
        // the scaled width as truth and land at half position).
        if rung != AppleServerDownscalePolicy.fullRung,
           let unscaledWidth = latestFramebuffer?.width
        {
            serverDownscaleUnscaledFramebufferWidth = unscaledWidth
        }
    }

    private func currentViewportRequestRegion(
        incrementalRequestIndex: Int
    ) -> RFBFramebufferUpdateRegion? {
        guard usesViewportAwareIncrementalRequestRegions else {
            return nil
        }
        guard let latestViewportTransform else {
            return nil
        }
        return viewportRequestRegionPolicy.requestRegion(
            for: latestViewportTransform,
            incrementalRequestIndex: incrementalRequestIndex
        )
    }

    private func currentViewportInitialRequestRegion(
        serverInit: RFBServerInit
    ) -> RFBFramebufferUpdateRegion? {
        guard usesViewportAwareInitialRequestRegion else {
            return nil
        }
        guard let latestViewportTransform else {
            return currentViewportInitialRequestRegionFromLastViewSize(serverInit: serverInit)
        }
        guard Int(latestViewportTransform.framebufferSize.width.rounded(.down)) == serverInit.width,
              Int(latestViewportTransform.framebufferSize.height.rounded(.down)) == serverInit.height
        else {
            return currentViewportInitialRequestRegionFromLastViewSize(serverInit: serverInit)
        }
        return latestViewportTransform.visibleFramebufferUpdateRegion(
            expansionMarginPixels: 0,
            minimumSavingsPermille: viewportRequestRegionPolicy.minimumSavingsPermille
        )?.centeredScaled(by: appSettings.startupGlanceScaleMode.scale)
    }

    private func currentViewportInitialRequestRegionFromLastViewSize(
        serverInit: RFBServerInit
    ) -> RFBFramebufferUpdateRegion? {
        guard let latestViewportSize,
              latestViewportSize.width > 0,
              latestViewportSize.height > 0,
              serverInit.width > 0,
              serverInit.height > 0
        else {
            return nil
        }

        let framebufferSize = CGSize(width: serverInit.width, height: serverInit.height)
        let fitScale = min(
            latestViewportSize.width / framebufferSize.width,
            latestViewportSize.height / framebufferSize.height
        )
        guard fitScale > 0 else {
            return nil
        }
        let fillScale = max(
            latestViewportSize.width / framebufferSize.width,
            latestViewportSize.height / framebufferSize.height
        )
        let transform = ViewportTransform(
            framebufferSize: framebufferSize,
            viewSize: latestViewportSize,
            zoomScale: max(1, fillScale / fitScale)
        )
        return transform.visibleFramebufferUpdateRegion(
            expansionMarginPixels: 0,
            minimumSavingsPermille: viewportRequestRegionPolicy.minimumSavingsPermille
        )?.centeredScaled(by: appSettings.startupGlanceScaleMode.scale)
    }

    /// Spec 017 (2026-08-19, founder direction): every stream profile scopes
    /// *incremental* requests to the visible viewport once the user zooms in.
    /// Un-zoomed sessions are untouched — `ViewportRequestRegionPolicy`
    /// returns nil (full request) when the visible region saves under 10% —
    /// and D94's starvation risk stays covered by the every-10th full-request
    /// heartbeat. Previously this was the RGB565 lanes' opt-in (D106); the
    /// promotion is the incremental gate only.
    /// Spec 030. Whether *incremental* framebuffer update requests are scoped to
    /// the visible viewport.
    ///
    /// Off. Measured 2026-08-25 against live Apple Screen Sharing, release build,
    /// no network conditioning, one axis at a time with an identical stimulus:
    /// a viewport-scoped request is answered in 540–787 ms on average with a p95
    /// sitting at the client's idle timeout, while a full-frame request is
    /// answered in 33 ms with a p95 of 119–133 ms. Content frame rate across
    /// three repeats: 0.49–0.74 scoped against 5.66–7.08 full. The ranges do not
    /// come close to overlapping, and no other axis moved the result —
    /// client-pressure pacing, empty-update backoff and stimulus rate were all
    /// within noise of the scoped baseline.
    ///
    /// The obvious alternative explanation was tested rather than assumed: a
    /// region that never changes would also sit at the idle timeout, and the
    /// benchmark's region is a centred crop while its stimulus sits at the top
    /// left. Moving the stimulus into the centre of the region did not close the
    /// gap (0.83 fps scoped against 3.82 full).
    ///
    /// Commit 09f28915 had already corrected spec 017's ground truth to "Apple
    /// does not reliably clip region requests under load". This is that finding
    /// with its price attached, and the price was the whole frame rate — an
    /// iPhone showing a wide desktop is always looking at a crop, so the scoped
    /// path was the normal one and not a zoomed-in edge case.
    ///
    /// The machinery stays because this is one server family on one machine, and
    /// spec 017's bandwidth argument is untested rather than refuted.
    private var usesViewportAwareIncrementalRequestRegions: Bool {
        false
    }


    private var usesViewportAwareRequestRegions: Bool {
        guard appSettings.streamPowerMode != .powerSaver,
              !lowPowerModeProvider()
        else {
            return false
        }
        return true
    }

    /// The *initial* request stays full-frame outside the opt-in RGB565
    /// lanes: a region-scoped first frame leaves never-delivered framebuffer
    /// area unpainted until damage happens to land there, and that
    /// glance-startup trade was only measured for those lanes (D110). This is
    /// also what `canUseStartupGlanceScaleMode` keys on.
    private var usesViewportAwareInitialRequestRegion: Bool {
        guard usesViewportAwareRequestRegions else {
            return false
        }
        switch appSettings.streamEncodingMode {
        case .localLowLatencyRGB565, .zrleCompressionZeroRGB565:
            return true
        case .standard, .tightFirstCursor, .zrleCompressionZero, .adaptiveGoodFull:
            return false
        }
    }

    private func startFrameApplicationWorker(_ queue: SessionStreamFrameApplicationQueue) {
        activeFrameApplicationTask?.cancel()
        let workerPacing = SessionFrameApplicationWorkerPacing()
        activeFrameApplicationTask = Task.detached(priority: .userInitiated) { [weak self, queue] in
            var lastContentFrameAppliedAt: Date?
            while !Task.isCancelled,
                  let work = await queue.next(preferControlUpdates: lastContentFrameAppliedAt != nil)
            {
                let contentFrameMinimumInterval = await self?
                    .currentFrameApplicationContentFrameMinimumInterval()
                    ?? SessionFrameApplicationWorkerPacing.defaultContentFrameMinimumInterval
                let pacingDelay = workerPacing.delay(
                    before: work,
                    lastContentFrameAppliedAt: lastContentFrameAppliedAt,
                    now: Date(),
                    contentFrameMinimumInterval: contentFrameMinimumInterval
                )
                if pacingDelay > 0 {
                    if let frameApplicationSleepOverride = await self?
                        .currentFrameApplicationSleepOverride()
                    {
                        try? await frameApplicationSleepOverride(pacingDelay)
                    } else {
                        try? await Task.sleep(for: .seconds(pacingDelay))
                    }
                    if Task.isCancelled {
                        return
                    }
                }
                let workToApply = await queue.latestContentWork(replacing: work)
                await self?.applyStreamFrameApplication(workToApply)
                if !workToApply.isEmptyUpdate {
                    lastContentFrameAppliedAt = Date()
                }
                await Task.yield()
            }
        }
    }

    private func currentFrameApplicationContentFrameMinimumInterval() -> TimeInterval {
        SessionFrameApplicationWorkerPacing.contentFrameMinimumInterval(
            for: frameDeliveryPriority(for: frameDeliveryInteractionReasons)
        )
    }

    private func currentFrameApplicationSleepOverride() -> (
        @Sendable (TimeInterval) async throws -> Void
    )? {
        frameApplicationSleepOverride
    }

    private func applyStreamFrameApplication(_ work: StreamFrameApplicationWork) {
        guard isCurrentStream(work.streamID, sessionID: work.sessionID, profileID: work.profile.id) else {
            return
        }

        let appFrameApplyStart = Date()
        if work.isEmptyUpdate, let serverCursor = work.frame.serverCursor {
            noteServerCursorUpdate(
                serverCursor,
                sessionID: work.sessionID,
                profile: work.profile,
                streamID: work.streamID,
                capturedAt: work.frame.capturedAt
            )
        } else if work.isEmptyUpdate {
            noteStreamLiveness(
                sessionID: work.sessionID,
                profile: work.profile,
                streamID: work.streamID,
                capturedAt: work.frame.capturedAt
            )
        } else {
            applyStreamFrame(
                work.frame,
                serverInit: work.serverInit,
                profile: work.profile,
                sessionID: work.sessionID,
                streamID: work.streamID
            )
        }

        guard isCurrentStream(work.streamID, sessionID: work.sessionID, profileID: work.profile.id) else {
            return
        }
        recordAppFrameApplyTiming(milliseconds: elapsedMilliseconds(since: appFrameApplyStart))
    }

    private func applyStreamFrame(
        _ frame: RFBFramePumpFrame,
        serverInit: RFBServerInit,
        profile: ConnectionProfile,
        sessionID: RemoteSession.ID,
        streamID: UUID
    ) {
        guard isCurrentStream(streamID, sessionID: sessionID, profileID: profile.id) else {
            return
        }

        if isViewportInteractionActive,
           latestFramebuffer != nil,
           !shouldPublishFrameDuringViewportInteraction(frame) {
            deferViewportInteractionFrame(
                frame,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
            return
        }
        if isViewportInteractionActive {
            lastViewportInteractionFramePublishedAt = frame.capturedAt
        }

        let activeSession: RemoteSession
        if var updatedSession = session {
            if !updatedSession.hasReceivedFrame || updatedSession.state != .active {
                updatedSession.markFirstFrameReceived(at: frame.capturedAt)
                session = updatedSession
                promoteTypeThroughDefaultOnSessionActivationIfNeeded()
            }
            activeSession = updatedSession
        } else {
            var updatedSession = RemoteSession(profileID: profile.id)
            updatedSession.markFirstFrameReceived(at: frame.capturedAt)
            session = updatedSession
            promoteTypeThroughDefaultOnSessionActivationIfNeeded()
            activeSession = updatedSession
        }
        // A frame arriving after a reconnect window means the new
        // attempt succeeded — drop the attempt counter so a future
        // drop gets a fresh `maxAttempts` budget.
        reconnectAttempts = 0
        cachePreview(
            framebuffer: frame.framebuffer,
            for: profile.id,
            capturedAt: frame.capturedAt,
            forceDiskSave: !frame.isIncremental
        )
        // Only forward damage rectangles for incremental frames.  The
        // first frame in a stream is non-incremental and the renderer
        // must perform a full upload (its texture has just been
        // allocated for these dimensions); pass nil so the dirty-rect
        // path is bypassed for that frame.
        publishSessionFrame(
            framebuffer: frame.framebuffer,
            dirtyRectangles: frame.isIncremental ? frame.dirtyRectangles : nil,
            changedPixelCount: frame.isIncremental ? frame.changedPixelCount : nil,
            serverCursor: frame.serverCursor
        )
        // Do not feed the PiP sample-buffer layer during ordinary foreground
        // viewing. That path converts the full framebuffer to video samples and
        // must stay out of the live gesture/input critical path unless PiP is
        // actually active.
        updatePiPWatchFrameIfNeeded(
            framebuffer: frame.framebuffer,
            sessionID: activeSession.id,
            capturedAt: frame.capturedAt,
            changeActivity: frame.changeActivity,
            dirtyRectangles: frame.isIncremental ? frame.dirtyRectangles : nil
        )

        if !frame.isIncremental {
            diagnosticRun = ConnectionDiagnosticRun(
                profileID: profile.id,
                startedAt: diagnosticRun?.startedAt ?? Date(),
                finishedAt: Date(),
                context: Self.diagnosticContext(
                    for: profile,
                    trigger: .connect,
                    timeout: frameStreamConfiguration.requestTimeout
                ),
                stages: [
                    DiagnosticStageResult(
                        stage: .dns,
                        status: .passed,
                        safeTitle: "Profile ready",
                        safeDetail: "Private profile is selected."
                    ),
                    DiagnosticStageResult(
                        stage: .tcp,
                        status: .passed,
                        safeTitle: "VNC port reached",
                        safeDetail: "TCP connection succeeded."
                    ),
                    DiagnosticStageResult(
                        stage: .rfbHandshake,
                        status: .passed,
                        safeTitle: "VNC handshake complete",
                        safeDetail: "RFB streaming path completed."
                    ),
                    DiagnosticStageResult(
                        stage: .firstFrame,
                        status: .passed,
                        safeTitle: "First frame received",
                        safeDetail: "\(serverInit.width)x\(serverInit.height) remote framebuffer is available."
                    )
                ]
            )
            recordDiagnosticVerdict(for: profile.id, from: diagnosticRun)
        }
    }

    /// Liveness-only bookkeeping for an empty incremental update.  The
    /// connection delivered a (zero-change) frame, so any prior
    /// reconnect succeeded and the attempt budget can reset, but there
    /// is nothing new to draw, so the expensive `latestFramebuffer` /
    /// PiP / GPU-upload path is intentionally left untouched and an idle
    /// screen costs almost nothing.  Gated on the stream still being
    /// current so a straggler frame from a torn-down stream is ignored.
    private func noteStreamLiveness(
        sessionID: RemoteSession.ID,
        profile: ConnectionProfile,
        streamID: UUID,
        capturedAt: Date
    ) {
        guard isCurrentStream(streamID, sessionID: sessionID, profileID: profile.id) else {
            return
        }
        if reconnectAttempts != 0 {
            reconnectAttempts = 0
        }
        // Defensive: post-reconnect the first delivered frame is always
        // non-incremental (a fresh pump starts at sequence 1), so an
        // empty update should never be the frame that clears a
        // "reconnecting" banner; but if it ever is, honor liveness.
        if var updatedSession = session, !updatedSession.hasReceivedFrame {
            updatedSession.markFirstFrameReceived(at: capturedAt)
            session = updatedSession
            promoteTypeThroughDefaultOnSessionActivationIfNeeded()
        }
    }

    private func flushDeferredViewportInteractionFrame() {
        guard let deferred = deferredViewportInteractionFrame else {
            return
        }
        deferredViewportInteractionFrame = nil
        applyStreamFrame(
            deferred.frame,
            serverInit: deferred.serverInit,
            profile: deferred.profile,
            sessionID: deferred.sessionID,
            streamID: deferred.streamID
        )
    }

    private func deferViewportInteractionFrame(
        _ frame: RFBFramePumpFrame,
        serverInit: RFBServerInit,
        profile: ConnectionProfile,
        sessionID: RemoteSession.ID,
        streamID: UUID
    ) {
        deferredViewportInteractionFrame = DeferredViewportInteractionFrame(
            frame: frame,
            serverInit: serverInit,
            profile: profile,
            sessionID: sessionID,
            streamID: streamID
        )
    }

    private func shouldPublishFrameDuringViewportInteraction(_ frame: RFBFramePumpFrame) -> Bool {
        guard viewportInteractionFrameStrategy?.allowsLiveFramebufferPublication == true else {
            return false
        }

        let uploadPlan = ViewportInteractionFramePublishPolicy.uploadPlan(
            for: frame,
            currentFramebuffer: latestFramebuffer
        )
        return ViewportInteractionFramePublishPolicy.shouldPublish(
            uploadPlan: uploadPlan,
            capturedAt: frame.capturedAt,
            lastPublishedAt: lastViewportInteractionFramePublishedAt,
            interactionStartedAt: viewportInteractionStartedAt
        )
    }

    private static func viewportInteractionContentFrameInterval(
        for frame: RFBFramePumpFrame,
        currentFramebuffer: RFBRawFramebuffer?,
        frameStrategy: ViewportInteractionFrameStrategy?
    ) -> TimeInterval {
        guard frameStrategy?.allowsLiveFramebufferPublication == true else {
            return ViewportInteractionFramePublishPolicy.fullUploadContentFrameIntervalSeconds
        }

        let uploadPlan = ViewportInteractionFramePublishPolicy.uploadPlan(
            for: frame,
            currentFramebuffer: currentFramebuffer
        )
        return ViewportInteractionFramePublishPolicy.contentFrameInterval(for: uploadPlan)
    }

    /// Memory-only update for the RFB Cursor pseudo-encoding when no
    /// framebuffer pixels changed. This keeps trackpad mode aligned
    /// with the server-provided cursor shape without republishing the
    /// same framebuffer or forwarding another PiP frame.
    private func noteServerCursorUpdate(
        _ serverCursor: RFBServerCursor,
        sessionID: RemoteSession.ID,
        profile: ConnectionProfile,
        streamID: UUID,
        capturedAt: Date
    ) {
        guard isCurrentStream(streamID, sessionID: sessionID, profileID: profile.id) else {
            return
        }
        publishServerCursor(serverCursor)
        noteStreamLiveness(
            sessionID: sessionID,
            profile: profile,
            streamID: streamID,
            capturedAt: capturedAt
        )
    }

    /// Fold one frame round-trip latency sample into the
    /// connection-quality estimator and republish the bucket.  Gated
    /// on the stream still being current so a straggler sample from a
    /// torn-down stream cannot perturb a fresh session's quality.
    /// Constitution §IV: the millisecond value is consumed here and
    /// never stored or logged — only the coarse bucket survives.
    private func recordFrameLatency(
        milliseconds: Double,
        streamID: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        transportControl: (any RFBTransportControlClient)? = nil,
        requestTimeout: TimeInterval = 2
    ) {
        guard isCurrentStream(streamID, sessionID: sessionID, profileID: profileID) else {
            return
        }
        connectionQualityEstimator.record(latencyMilliseconds: milliseconds)
        let bucket = connectionQualityEstimator.quality
        let currentOrPendingQuality = pendingFocusedInputConnectionQuality ?? connectionQuality
        if currentOrPendingQuality != bucket {
            publishConnectionQuality(bucket)
            renegotiateAdaptiveEncodingsIfNeeded(
                for: bucket,
                transportControl: transportControl,
                requestTimeout: requestTimeout
            )
        }
    }

    private func renegotiateConfiguredSustainedEncodingsIfNeeded(
        transportControl: (any RFBTransportControlClient)?,
        requestTimeout: TimeInterval
    ) async {
        guard let transportControl,
              let preference = configuredSustainedEncodingPreference()
        else {
            return
        }

        let timeout = min(max(requestTimeout, 0.1), 2)
        // `RFBTransportControlClient` is `Sendable`; production
        // `RFBNetworkClient` protects its mutable connection lifecycle
        // with its client lock. The write is synchronous and bounded by
        // `timeout`, so keep it off the MainActor and treat failure as
        // a non-fatal optimization miss.
        try? await Task.detached(priority: .utility) {
            try transportControl.renegotiateEncodings(
                preference,
                timeout: timeout
            )
        }.value
    }

    private func configuredSustainedEncodingPreference() -> RFBEncodingPreference? {
        if appSettings.streamPowerMode == .powerSaver
            || lowPowerModeProvider()
            || networkPathConditionsProvider().isConstrained
        {
            return .powerSaverSustained
        }

        switch appSettings.streamEncodingMode {
        case .standard:
            return nil
        case .tightFirstCursor:
            return .tightFirstCursor
        case .localLowLatencyRGB565:
            return .localLowLatency
        case .zrleCompressionZero:
            return RFBEncodingPreference(zrle: true, compressionLevel: 0)
        case .zrleCompressionZeroRGB565:
            return RFBEncodingPreference(zrle: true, compressionLevel: 0)
        case .adaptiveGoodFull:
            return RFBEncodingPreference.adaptive(
                supported: .full,
                requestedPseudoEncodings: .withServerCursorAndPacingExtensions,
                connectionQuality: .good
            )
        }
    }

    private func initialStreamEncodingPreference() -> RFBEncodingPreference {
        configuredSustainedEncodingPreference() ?? .localLowLatency
    }

    private func initialStreamPixelFormatPreference() -> RFBPixelFormat? {
        guard appSettings.streamPowerMode != .powerSaver,
              !lowPowerModeProvider(),
              !networkPathConditionsProvider().isConstrained
        else {
            return nil
        }

        switch appSettings.streamEncodingMode {
        case .standard, .tightFirstCursor, .zrleCompressionZero, .adaptiveGoodFull:
            return nil
        case .localLowLatencyRGB565, .zrleCompressionZeroRGB565:
            return .rgb565In32LittleEndian
        }
    }

    /// Optional spec-004 adaptive re-advertisement. Connection-quality
    /// buckets are always tracked for UI/diagnostics, but production
    /// sessions stay on the benchmark-backed `localLowLatency`
    /// request/response profile until live benchmark/device evidence is
    /// strong enough to enable automatic adaptive/continuous-update
    /// renegotiation by default.
    /// When opted in, failures are deliberately non-fatal: the frame
    /// pump will surface a real connection failure on the next
    /// read/write, and this optimization must not tear down an otherwise
    /// usable session.
    private func renegotiateAdaptiveEncodingsIfNeeded(
        for bucket: ConnectionQuality,
        transportControl: (any RFBTransportControlClient)?,
        requestTimeout: TimeInterval
    ) {
        guard allowsAdaptiveEncodingRenegotiation,
              bucket != .unknown,
              lastAdaptiveEncodingQuality != bucket,
              let transportControl
        else {
            return
        }

        lastAdaptiveEncodingQuality = bucket
        let preference = RFBEncodingPreference.adaptive(
            supported: .full,
            requestedPseudoEncodings: .withServerCursorAndPacingExtensions,
            connectionQuality: bucket
        )
        let timeout = min(max(requestTimeout, 0.1), 2)
        adaptiveEncodingRenegotiationTask?.cancel()
        adaptiveEncodingRenegotiationTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else {
                return
            }
            try? transportControl.renegotiateEncodings(preference, timeout: timeout)
        }
    }

    /// Clear the connection-quality estimator and republished bucket.
    /// Called on disconnect / fresh connect / profile change so a new
    /// session starts at `.unknown` rather than inheriting the prior
    /// session's quality.
    private func resetConnectionQuality() {
        adaptiveEncodingRenegotiationTask?.cancel()
        adaptiveEncodingRenegotiationTask = nil
        lastAdaptiveEncodingQuality = nil
        connectionQualityEstimator.reset()
        pendingFocusedInputConnectionQuality = nil
        publishConnectionQuality(.unknown)
    }

    /// Reset pointer-control mode + trackpad cursor to the product
    /// default.  Called alongside `resetConnectionQuality()` /
    /// `activePointerClient = nil` on every disconnect / fresh connect /
    /// profile change so the trackpad mode and cursor position never
    /// leak across sessions (spec 003 T014).  Constitution §IV: the
    /// cursor position is dropped here, never logged or persisted.
    private func resetPointerControl() {
        pointerControlMode = .productDefault
        publishTrackpadCursor(TrackpadCursor(), immediately: true)
    }

    /// Test/fixture seam: publish a connection-quality bucket directly,
    /// without a live latency stream.  The production path
    /// (`recordFrameLatency`) is private and only fires while a real
    /// frame round-trip is timed, which the UX-audit fixtures and unit
    /// tests cannot reach.  This mirrors `recordIncomingClipboard` as
    /// the canonical post-init mutation hook for a synthetic state.
    /// Constitution §IV: a quality *bucket* is a coarse, non-sensitive
    /// signal — no raw latency value is stored or exported.
    public func seedConnectionQualityForTesting(_ quality: ConnectionQuality) {
        publishConnectionQuality(quality)
    }

    public var isComposeInputEditingActiveForTesting: Bool {
        isFocusedInputChromeCoalescingActive
    }

    public var frameApplicationContentFrameMinimumIntervalForTesting: TimeInterval {
        currentFrameApplicationContentFrameMinimumInterval()
    }

    public func publishFirstFrameForTesting(_ framebuffer: RFBRawFramebuffer) {
        guard var currentSession = session else {
            return
        }
        currentSession.markFirstFrameReceived()
        session = currentSession
        promoteTypeThroughDefaultOnSessionActivationIfNeeded()
        publishSessionFrame(
            framebuffer: framebuffer,
            dirtyRectangles: nil,
            changedPixelCount: framebuffer.width * framebuffer.height,
            serverCursor: nil
        )
    }

    private func handleStreamFailure(
        profile: ConnectionProfile,
        sessionID: RemoteSession.ID,
        streamID: UUID,
        error: Error,
        completedInitialHandshake: Bool = false
    ) {
        guard isCurrentStream(streamID, sessionID: sessionID, profileID: profile.id) else {
            return
        }
        deferredViewportInteractionFrame = nil
        lastViewportInteractionFramePublishedAt = nil
        viewportInteractionStartedAt = nil

        activeTextClient = nil
        activePointerClient = nil
        activeFramebufferUpdateRequestSender = nil
        inputCoordinateSpace = nil
        activeKeyEventClient = nil
        keystrokeEmitter = nil
        directKeystrokeMode = .init()
        stickyModifierState = .init()
        resetLiveTypeThroughState()
        resetPointerControl()
        lastEmittedDragCoord = nil
        cancelOutboundInputEventQueues()
        stopIncomingClipboardReceive()

        var updatedSession = session ?? RemoteSession(profileID: profile.id)
        if updatedSession.hasReceivedFrame {
            // Bounded auto-reconnect on a streaming drop: only when
            // the user has not explicitly disconnected and we still
            // have attempts left in the policy.  Constitution §I:
            // we never replay a buffered Compose & Send draft on
            // reconnect — the send path requires a fresh user tap.
            if !explicitlyDisconnected,
               let savedProfile = activeStreamProfile,
               savedProfile.id == profile.id,
               let savedCredential = activeStreamCredential,
               reconnectAttempts < reconnectPolicy.maxAttempts
            {
                let nextAttempt = reconnectAttempts + 1
                reconnectAttempts = nextAttempt
                updatedSession.markReconnecting(
                    attempt: nextAttempt,
                    of: reconnectPolicy.maxAttempts
                )
                session = updatedSession
                scheduleReconnect(
                    after: reconnectPolicy.backoffForAttempt(nextAttempt),
                    profile: savedProfile,
                    credential: savedCredential,
                    sessionID: sessionID
                )
                return
            }

            // Reconnect not available (or attempts exhausted).
            // Surface a safe-catalog diagnostic stage failure — the
            // user sees the catalog message, NOT a raw error
            // (constitution §IV).
            updatedSession.markFailed("Connection lost. Please reconnect.")
            clearSessionFrame()
            resetSessionStreamStats()
            stopHelperVideoStreamBootstrap()
            resetVisualTransportState()
            session = updatedSession
            activeStreamProfile = nil
            activeStreamCredential = nil
            reconnectAttempts = 0
            diagnosticRun = ConnectionDiagnosticRun(
                profileID: profile.id,
                startedAt: diagnosticRun?.startedAt ?? Date(),
                finishedAt: Date(),
                context: Self.diagnosticContext(
                    for: profile,
                    trigger: .streamDrop,
                    timeout: frameStreamConfiguration.requestTimeout
                ),
                stages: [
                    DiagnosticStageResult(
                        stage: .dns,
                        status: .passed,
                        safeTitle: "Profile ready",
                        safeDetail: "Private profile is selected."
                    ),
                    DiagnosticStageResult(
                        stage: .firstFrame,
                        status: .failed,
                        safeTitle: "Connection lost",
                        safeDetail: "The remote frame stream stopped responding.",
                        nextAction: "Check the remote computer and reconnect.",
                        metadata: Self.diagnosticFailureMetadata(for: error)
                    )
                ]
            )
            recordDiagnosticVerdict(for: profile.id, from: diagnosticRun)
            return
        }

        // Initial connect (no frame ever delivered) failed — derive
        // the actual stage from the error so a wrong-password,
        // unreachable-port, or genuine handshake mismatch each get
        // their own actionable catalog message instead of a hardcoded
        // "VNC handshake failed" / "Connection failed" pair
        // (constitution §IV).
        let failedStage = completedInitialHandshake ? .firstFrame : Self.stage(for: error)
        let failure = DiagnosticMessageCatalog.failure(
            for: failedStage,
            metadata: Self.diagnosticFailureMetadata(for: error)
        )
        updatedSession.markFailed(failure.safeTitle)
        clearSessionFrame()
        resetSessionStreamStats()
        stopHelperVideoStreamBootstrap()
        resetVisualTransportState()
        session = updatedSession
        activeStreamProfile = nil
        activeStreamCredential = nil
        reconnectAttempts = 0
        diagnosticRun = ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: diagnosticRun?.startedAt ?? Date(),
            finishedAt: Date(),
            context: Self.diagnosticContext(
                for: profile,
                trigger: .connect,
                timeout: frameStreamConfiguration.requestTimeout
            ),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "Private profile is selected."
                ),
                failure
            ]
        )
        recordDiagnosticVerdict(for: profile.id, from: diagnosticRun)
    }

    /// Schedule the next reconnect attempt.  Sleeps `backoff` then
    /// — if the profile is still selected, the session id still
    /// matches, no fresh user-initiated connect has fired, and the
    /// user has not explicitly disconnected — re-runs the
    /// connect-and-stream path against `profile`/`credential`.  The
    /// new attempt allocates its OWN `streamID` inside
    /// `startFrameStream`, so any in-flight task from the previous
    /// drop self-cancels via the `isCurrentStream` triple-check.
    ///
    /// Cancellation of the pending sleep happens through
    /// `cancelPendingReconnect()` (profile change, user
    /// disconnect, fresh connect).
    private func scheduleReconnect(
        after backoff: Duration,
        profile: ConnectionProfile,
        credential: RFBConnectionCredential,
        sessionID: RemoteSession.ID
    ) {
        pendingReconnectTask?.cancel()
        let streamConnectorFactory = self.streamConnectorFactory
        let streamConnectorFactoryAppliesPreferences = self.streamConnectorFactoryAppliesPreferences
        pendingReconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: backoff)
            } catch {
                return
            }
            if Task.isCancelled {
                return
            }
            guard let self else {
                return
            }
            await self.runScheduledReconnect(
                profile: profile,
                credential: credential,
                sessionID: sessionID,
                streamConnectorFactory: streamConnectorFactory,
                streamConnectorFactoryAppliesPreferences: streamConnectorFactoryAppliesPreferences
            )
        }
    }

    /// Body of a fired reconnect.  Re-checks every cancellation
    /// gate that could have flipped during the backoff sleep before
    /// touching network state, then re-uses the streaming
    /// connect path with a NEW `streamID`.  Non-streaming
    /// connectors (pure first-frame) are not eligible for
    /// auto-reconnect — that path never enters `handleStreamFailure`.
    private func runScheduledReconnect(
        profile: ConnectionProfile,
        credential: RFBConnectionCredential,
        sessionID: RemoteSession.ID,
        streamConnectorFactory: @Sendable (
            RFBEncodingPreference,
            RFBPixelFormat?
        ) -> RFBFirstFrameConnecting,
        streamConnectorFactoryAppliesPreferences: Bool
    ) async {
        // Gate checks: any of these flipping means a profile change,
        // an explicit disconnect, or a fresh user connect raced past
        // us — drop the attempt silently.
        guard !explicitlyDisconnected else { return }
        guard selectedProfileID == profile.id else { return }
        guard session?.id == sessionID else { return }

        let initialEncodingPreference = initialStreamEncodingPreference()
        let initialPixelFormatPreference = initialStreamPixelFormatPreference()
        let connector = streamConnectorFactory(
            initialEncodingPreference,
            initialPixelFormatPreference
        )
        guard let streamingClient = connector as? any RFBStreamingClient else {
            // Auto-reconnect requires a streaming-capable
            // connector — degrade to "Connection lost" rather than
            // looping with a connector that cannot stream.
            var updatedSession = session ?? RemoteSession(profileID: profile.id)
            updatedSession.markFailed("Connection lost. Please reconnect.")
            session = updatedSession
            activeStreamProfile = nil
            activeStreamCredential = nil
            reconnectAttempts = 0
            return
        }

        guard let pendingSession = session else { return }

        // Stop the previous (already-broken) stream's bookkeeping
        // before starting the next attempt.  `startFrameStream`
        // assigns a fresh `streamID` so any straggler frame task
        // self-cancels via `isCurrentStream`.
        stopFrameStream()
        startFrameStream(
            streamingClient,
            profile: profile,
            session: pendingSession,
            credential: credential,
            shouldRenegotiateConfiguredSustainedEncodings: !streamConnectorFactoryAppliesPreferences
        )
    }

    private func cancelPendingReconnect() {
        pendingReconnectTask?.cancel()
        pendingReconnectTask = nil
    }

    private func resetFrameDeliveryInteractionState() {
        transientFrameDeliveryInteractionTask?.cancel()
        transientFrameDeliveryInteractionTask = nil
        transientFrameDeliveryInteractionExpiresAt = nil
        cancelFocusedInputChromeUpdates()
        frameDeliveryInteractionReasons.removeAll()
        viewportInteractionFrameStrategy = nil
        deferredViewportInteractionFrame = nil
        lastViewportInteractionFramePublishedAt = nil
        viewportInteractionStartedAt = nil
        frameStore.setDeliveryPriority(.visual)
    }

    /// User-initiated disconnect.  Tears down the active stream,
    /// any pending reconnect sleep, and the session HUD.  The
    /// `explicitlyDisconnected` latch stays set until the next
    /// fresh `connectSelectedProfile()` call so a late-firing
    /// stream failure callback does not schedule a reconnect on
    /// the user's behalf.
    ///
    /// Also clears the rendered framebuffer so a torn-down session
    /// does not leave a stale frame on screen — once the user has
    /// explicitly ended the session, showing yesterday's pixels would
    /// be misleading.  The selected profile and the persisted profile
    /// list are intentionally retained: the user disconnected from
    /// *this session*, not from *this profile*.
    public func disconnect() {
        explicitlyDisconnected = true
        cancelPendingReconnect()
        resetFrameDeliveryInteractionState()
        stopHelperVideoStreamBootstrap()
        stopFrameStream()
        stopIncomingClipboardReceive()
        clearIncomingClipboardReviewState()
        activeTextClient = nil
        activePointerClient = nil
        activeFramebufferUpdateRequestSender = nil
        activeKeyEventClient = nil
        keystrokeEmitter = nil
        directKeystrokeMode = .init()
        stickyModifierState = .init()
        resetLiveTypeThroughState()
        lastEmittedDragCoord = nil
        activeStreamProfile = nil
        activeStreamCredential = nil
        reconnectAttempts = 0
        latestViewportTransform = nil
        resetAppleServerDownscaleState()
        clearSessionFrame()
        resetSessionStreamStats()
        resetVisualTransportState()
        resetConnectionQuality()
        resetPointerControl()
        if var current = session {
            current.state = .closed
            current.hudMessage = "Disconnected"
            current.lastError = nil
            session = current
        }
    }

    private func isCurrentStream(
        _ streamID: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) -> Bool {
        activeFrameStreamID == streamID &&
            session?.id == sessionID &&
            selectedProfileID == profileID
    }

    /// Freshness gate for the legacy non-streaming first-frame path. The
    /// streaming path deliberately keeps its stronger stream/session/profile
    /// triple-check in `isCurrentStream`.
    private func isCurrentConnectionAttempt(
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) -> Bool {
        !explicitlyDisconnected &&
            session?.id == sessionID &&
            selectedProfileID == profileID
    }

    private func stopFrameStream() {
        stopMainActorResponsivenessMonitor()
        activeFrameStreamTask?.cancel()
        activeFramePump?.cancel()
        let frameApplicationQueue = activeFrameApplicationQueue
        activeFrameApplicationTask?.cancel()
        activeFrameStreamTask = nil
        activeFramePump = nil
        activeFrameApplicationTask = nil
        activeFrameApplicationQueue = nil
        activeFrameStreamID = nil
        viewportInteractionFrameStrategy = nil
        deferredViewportInteractionFrame = nil
        lastViewportInteractionFramePublishedAt = nil
        viewportInteractionStartedAt = nil
        cancelOutboundInputEventQueues()
        if let frameApplicationQueue {
            Task.detached(priority: .utility) {
                await frameApplicationQueue.close()
            }
        }
    }

    private func cancelOutboundInputEventQueues() {
        pointerMoveFlushTask?.cancel()
        pointerMoveFlushTask = nil
        pendingPointerMove = nil
        cancelPointerInputFramebufferUpdateNudge()
        pointerInputDispatcher.cancelAll()
        keyInputDispatcher.cancelAll()
    }

    private func cancelPointerInputEventQueue() {
        pointerMoveFlushTask?.cancel()
        pointerMoveFlushTask = nil
        pendingPointerMove = nil
        cancelPointerInputFramebufferUpdateNudge()
        pointerInputDispatcher.cancelAll()
    }

    private func cancelKeyInputEventQueue() {
        keyInputDispatcher.cancelAll()
    }

    /// Begin a long-lived receive loop that pulls `ServerCutText`
    /// payloads off the active connection and surfaces each one as a
    /// pending review the user must Accept before the local
    /// pasteboard is touched.
    ///
    /// Behavior on a payload arriving while a previous review is
    /// still pending: REPLACE the previous review with the latest
    /// arrival.  A queue could leak older context across user
    /// attention shifts; replacing keeps the visible review aligned
    /// with the most recent remote copy.
    private func startIncomingClipboardReceive(receive: @escaping @Sendable (TimeInterval) -> IncomingClipboardReceiveResult) {
        stopIncomingClipboardReceive()

        let timeout = incomingClipboardReceiveTimeout

        activeIncomingClipboardTask = Task { [weak self] in
            while !Task.isCancelled {
                let result = await Task.detached {
                    receive(timeout)
                }.value

                if Task.isCancelled {
                    return
                }

                guard let self else {
                    return
                }

                switch result {
                case .text(let text):
                    self.recordIncomingClipboard(text)
                case .unsupported:
                    return
                case .transientError:
                    continue
                }
            }
        }
    }

    private func stopIncomingClipboardReceive() {
        activeIncomingClipboardTask?.cancel()
        activeIncomingClipboardTask = nil
    }

    /// Builds a `Sendable` receive closure for the long-lived
    /// `RFBStreamingClient` path.  Captures only the Sendable
    /// streaming client so the closure can cross actor boundaries
    /// into a detached task.
    nonisolated private static func makeReceive(
        streamingClient: any RFBStreamingClient
    ) -> @Sendable (TimeInterval) -> IncomingClipboardReceiveResult {
        return { timeout in
            do {
                let text = try streamingClient.receiveServerCutText(timeout: timeout)
                return .text(text)
            } catch let error as TextInjectionError {
                if case .clipboardUnavailable = error {
                    return .unsupported
                }
                return .transientError
            } catch {
                return .transientError
            }
        }
    }

    /// Builds a `Sendable` receive closure for the legacy
    /// first-frame connector path.  The receive surface is optional
    /// on this protocol, so the closure short-circuits to
    /// `.unsupported` when the connector does not adopt
    /// `RemoteClipboardTextClient`.
    nonisolated private static func makeReceive(
        connector: any RFBFirstFrameConnecting
    ) -> @Sendable (TimeInterval) -> IncomingClipboardReceiveResult {
        return { timeout in
            guard let textClient = connector as? RemoteClipboardTextClient else {
                return .unsupported
            }
            do {
                let text = try textClient.receiveServerCutText(timeout: timeout)
                return .text(text)
            } catch let error as TextInjectionError {
                if case .clipboardUnavailable = error {
                    return .unsupported
                }
                return .transientError
            } catch {
                return .transientError
            }
        }
    }

    /// Surfaces a fresh `ServerCutText` arrival as a pending review.
    /// Public so deterministic tests can drive the receive surface
    /// without spinning the live receive loop.  Discards empty
    /// payloads — the protocol allows them but they would render an
    /// empty banner with no useful preview.
    /// Records clipboard text drained from the streaming connection, after
    /// re-checking that the stream it came from is still the current one — a
    /// profile switch mid-flight must not hand the user another machine's copy.
    private func recordIncomingClipboardFromStream(
        _ text: String,
        streamID: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) {
        guard isCurrentStream(streamID, sessionID: sessionID, profileID: profileID) else {
            return
        }
        recordIncomingClipboard(text)
    }

    public func recordIncomingClipboard(_ text: String, at date: Date = Date()) {
        guard !text.isEmpty else {
            return
        }
        // REPLACE policy: a newer arrival supersedes a still-pending
        // older review.  See `startIncomingClipboardReceive` for
        // rationale.
        let review = IncomingClipboardReview(text: text, arrivedAt: date)
        if isFocusedInputChromeCoalescingActive {
            pendingFocusedInputIncomingClipboard = review
            return
        }
        pendingFocusedInputIncomingClipboard = nil
        pendingIncomingClipboard = review
    }

    /// User reviewed the preview and accepted the remote copy.
    /// Writes the *full* text through the injected
    /// `LocalClipboardWriting` boundary and clears the review.
    public func acceptIncomingClipboard() {
        guard let review = pendingIncomingClipboard else {
            return
        }
        localClipboardWriter?.write(review.text)
        clearIncomingClipboardReviewState()
    }

    /// User dismissed the review.  Nothing is written to the local
    /// pasteboard.  The full `text` is dropped on the floor.
    public func dismissIncomingClipboard() {
        clearIncomingClipboardReviewState()
    }

    // MARK: - Pointer control mode

    /// Current framebuffer size in pixels, or a sensible default when
    /// no frame has arrived yet.  Used to center the trackpad cursor on a
    /// mode switch and to clamp relative cursor moves.
    private var currentFramebufferSize: CGSize {
        if let inputCoordinateSpace {
            return inputCoordinateSpace.size
        }
        guard let framebuffer = latestFramebuffer else {
            return CGSize(width: 1280, height: 720)
        }
        return CGSize(width: framebuffer.width, height: framebuffer.height)
    }

    /// Flip between direct-touch and trackpad pointer control.
    /// Constitution §I: switching modes is a LOCAL transform only — no
    /// RFB PointerEvent is emitted here.  Entering trackpad mode centers
    /// the cursor on the live framebuffer (or a default when no frame
    /// has arrived); leaving it hides the cursor.
    public func togglePointerControlMode() {
        switch pointerControlMode {
        case .directTouch:
            pointerControlMode = .trackpad
            publishTrackpadCursor(.centered(in: currentFramebufferSize), immediately: true)
        case .trackpad:
            pointerControlMode = .directTouch
            var hiddenCursor = resolvedTrackpadCursor
            hiddenCursor.isVisible = false
            publishTrackpadCursor(hiddenCursor, immediately: true)
        }
    }

    /// Resolve a trackpad-mode gesture sampled from the viewport view
    /// into a moved cursor and any RFB pointer commands, then
    /// dispatch the commands on the wire.  No-op when there is no live
    /// pointer client or remote coordinate space.  Viewport auto-pan remains LOCAL
    /// (constitution §I), while trackpad cursor movement reaches the
    /// remote OS as coalesced buttonless pointer moves. Constitution
    /// §IV: the cursor position / deltas are consumed here and never
    /// logged or persisted.
    ///
    public func handleTrackpadGesture(_ gesture: PointerGesture, viewSize: CGSize) {
        guard let framebuffer = latestFramebuffer, let session else {
            return
        }
        let framebufferSize = CGSize(width: framebuffer.width, height: framebuffer.height)
        let transform = ViewportTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize
        )
        _ = handleTrackpadGesture(
            gesture,
            transform: transform,
            session: session,
            cursor: resolvedTrackpadCursor
        )
    }

    /// Zoom-aware variant used by the SwiftUI viewport.  The view owns
    /// the current local zoom/pan state, so it passes the exact
    /// `ViewportTransform` sampled with the gesture.  The returned
    /// transform carries local-only auto-pan updates back to the view
    /// when the cursor nears an edge while zoomed (spec 003 FR-011).
    @discardableResult
    public func handleTrackpadGesture(
        _ gesture: PointerGesture,
        transform: ViewportTransform,
        cursor: TrackpadCursor? = nil
    ) -> SessionViewportTrackpadGestureResult? {
        guard let session else {
            return nil
        }
        return handleTrackpadGesture(
            gesture,
            transform: transform,
            session: session,
            cursor: cursor ?? resolvedTrackpadCursor
        )
    }

    @discardableResult
    private func handleTrackpadGesture(
        _ gesture: PointerGesture,
        transform: ViewportTransform,
        session: RemoteSession,
        cursor: TrackpadCursor
    ) -> SessionViewportTrackpadGestureResult {
        markTransientFrameDeliveryInteractionActivity()
        let resolver = PointerGestureResolver(mode: .trackpad)
        let outcome = resolver.resolve(gesture, transform: transform, cursor: cursor)
        let result = SessionViewportTrackpadGestureResult(
            transform: outcome.transform,
            cursor: outcome.cursor
        )
        let isContinuousDrag: Bool
        if case .dragChanged = gesture {
            isContinuousDrag = true
        } else if case .pressDragChanged = gesture {
            isContinuousDrag = true
        } else {
            isContinuousDrag = false
        }
        publishTrackpadCursor(outcome.cursor, immediately: !isContinuousDrag)

        guard !outcome.commandBatch.isEmpty,
              let pointerClient = activePointerClient
        else {
            return result
        }

        let streamID = activeFrameStreamID
        let sessionID = session.id
        let profileID = selectedProfileID
        if Self.isBestEffortCursorFollowGesture(gesture),
           let command = outcome.commandBatch.singleButtonlessPointerMove {
            enqueueCoalescedPointerMove(
                command,
                pointerClient: pointerClient,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID,
                coalescingDelay: Self.trackpadPointerMoveCoalescingDelay,
                allowsBestEffort: true,
                sendsImmediatelyWhenIdle: Self.shouldSendBestEffortPointerMoveImmediatelyWhenIdle(gesture)
            )
            return result
        }

        flushPendingPointerMove()
        enqueuePointerCommands(
            outcome.commandBatch,
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
        return result
    }

    private static func isBestEffortCursorFollowGesture(_ gesture: PointerGesture) -> Bool {
        if case .dragChanged = gesture {
            return true
        }
        if case .hoverMoved = gesture {
            return true
        }
        return false
    }

    private static func shouldSendBestEffortPointerMoveImmediatelyWhenIdle(_ gesture: PointerGesture) -> Bool {
        if case .hoverMoved = gesture {
            return true
        }
        return false
    }

    // MARK: - Direct Keystroke Streaming Mode

    /// Toggle Direct Keystroke Mode on / off.  Resets `page` to
    /// `.qwerty` on every entry (FR-001 / spec User Story 1
    /// "fresh entry = familiar layout").  Does NOT touch the
    /// `hasShownEntryWarningThisSession` flag — the FR-009 entry
    /// warning is dismissed by the user calling
    /// `dismissDirectModeEntryWarning()` after they tap "Got it"
    /// in the SwiftUI confirmation dialog.
    ///
    /// Mode-switch state preservation (US-4 / FR-011 / FR-012):
    ///
    /// - The active `composeDraft` is intentionally NOT touched
    ///   here.  The user may be alternating between writing a
    ///   Korean message in Compose and dropping into Direct for
    ///   a quick `git status`; the partial draft survives the
    ///   round-trip in both directions.
    /// - Toggling OUT of Direct mode (`isActive: true → false`)
    ///   resets `stickyModifierState` to its default.  This is
    ///   FR-012's "all sticky modifier state cleared" rule, and
    ///   the `.init()` form also drops the struct's internal
    ///   `lastTapAt` map so a stale double-tap context cannot
    ///   bleed across a mode bounce.
    /// - Toggling INTO Direct mode does not perturb sticky
    ///   state — entries always start from whatever idle slate
    ///   the prior toggle-out / connect / profile-change reset
    ///   has already produced.
    public func toggleDirectKeystrokeMode() {
        let newActive = !directKeystrokeMode.isActive
        markTransientFrameDeliveryInteractionActivity()
        directKeystrokeMode = DirectKeystrokeMode(
            isActive: newActive,
            page: .qwerty,
            inputSurface: directKeystrokeMode.inputSurface,
            hasShownEntryWarningThisSession: directKeystrokeMode.hasShownEntryWarningThisSession
        )
        if !newActive {
            // FR-012 — sticky state must not survive a mode
            // bounce.  Re-initializing the whole struct also
            // clears the internal `lastTapAt` so the next entry
            // starts with a fresh single-tap window.
            stickyModifierState = .init()
        }
    }

    /// Switch which page of the custom soft keyboard is rendered
    /// (FR-002).  Page swap MUST NOT emit a `KeyEvent` — this
    /// method updates state only.
    public func setDirectKeystrokePage(_ page: KeyboardPage) {
        directKeystrokeMode = DirectKeystrokeMode(
            isActive: directKeystrokeMode.isActive,
            page: page,
            inputSurface: directKeystrokeMode.inputSurface,
            hasShownEntryWarningThisSession: directKeystrokeMode.hasShownEntryWarningThisSession
        )
    }

    /// Switch which local input surface Direct mode uses. The
    /// default `.customKeyboard` preserves FR-001; `.systemKeyboard`
    /// and `.hardwareKeyboard` are explicit opt-ins for native iOS
    /// typing feel and Bluetooth-keyboard screen-space recovery.
    public func setDirectKeystrokeInputSurface(_ inputSurface: DirectKeystrokeInputSurface) {
        guard directKeystrokeMode.inputSurface != inputSurface else {
            return
        }
        markTransientFrameDeliveryInteractionActivity()
        directKeystrokeMode = DirectKeystrokeMode(
            isActive: directKeystrokeMode.isActive,
            page: directKeystrokeMode.page,
            inputSurface: inputSurface,
            hasShownEntryWarningThisSession: directKeystrokeMode.hasShownEntryWarningThisSession
        )
    }

    /// Called by the SwiftUI warning dialog after the user taps
    /// "Got it".  Closes FR-009 (one-time-per-session warning) —
    /// subsequent toggles in the same session do not re-show the
    /// dialog.  Resets to `false` on every disconnect / new
    /// connect / profile change.
    public func dismissDirectModeEntryWarning() {
        directKeystrokeMode = DirectKeystrokeMode(
            isActive: directKeystrokeMode.isActive,
            page: directKeystrokeMode.page,
            inputSurface: directKeystrokeMode.inputSurface,
            hasShownEntryWarningThisSession: true
        )
    }

    // MARK: - Dock mode selection (spec 011)

    /// The two Remote Input Dock modes (spec 011): **Type**
    /// (type-through — the surface Live type-through shipped as, spec
    /// 009) and **Compose** (buffered local composition). The legacy
    /// third mode Direct Keystroke (spec 002) is retired as a user
    /// surface; its sticky modifiers and hardware-key responder live
    /// on inside the accessory strip and Type mode.
    public enum RemoteInputDockMode: String, Sendable, Equatable, CaseIterable {
        case compose
        case live
    }

    /// The currently active dock mode. Type (Live) is the default for
    /// an active session (spec 011 US1); Compose is the buffered
    /// opt-in.
    public var remoteInputDockMode: RemoteInputDockMode {
        if liveTypeThroughMode.isActive { return .live }
        return .compose
    }

    /// Is the compact dock's accessory key panel revealed (spec 015)?
    /// Collapsed is the default: with the keyboard up, one row of chrome is
    /// all the founder's terminal posture can afford (the pre-015 stack
    /// measured 368pt — 42% of an iPhone 17 Pro screen). The flag lives here
    /// rather than in the dock view because the compose-reveal placement swap
    /// recreates that view, and the panel must survive it (FR-004). Never
    /// persisted: a new session starts collapsed.
    @Published public private(set) var isRemoteInputAccessoryPanelExpanded = false

    /// Reveal or hide the accessory key panel. Hiding it also stops any
    /// in-flight key repeat's owner from being off-screen with a held key —
    /// the strip's own `onDisappear` does that, so this stays a pure toggle.
    public func setRemoteInputAccessoryPanelExpanded(_ expanded: Bool) {
        guard expanded != isRemoteInputAccessoryPanelExpanded else { return }
        markTransientFrameDeliveryInteractionActivity()
        isRemoteInputAccessoryPanelExpanded = expanded
    }

    /// One-tap switch between the two dock modes. Switching is
    /// non-destructive (FR-012): the Compose draft is untouched, and
    /// leaving Type seals its window so no delete crosses the seal
    /// (FR-011). Resets the per-window Live state when entering Type.
    public func setRemoteInputDockMode(_ mode: RemoteInputDockMode) {
        // Record explicit intent even when re-selecting the active mode —
        // a pre-connect Compose tap must suppress the Type default
        // promotion even though Compose is already the resting mode.
        hasUserSelectedDockModeThisSession = true
        guard mode != remoteInputDockMode else { return }
        markTransientFrameDeliveryInteractionActivity()

        // Leaving Type seals the current window; delivered text stays at the
        // remote and only marked/uncommitted text is discarded (FR-011/FR-012).
        if liveTypeThroughMode.isActive, mode != .live {
            sealLiveWindow(reason: .modeSwitch)
            deactivateLiveTypeThroughMode()
        }

        switch mode {
        case .compose:
            if directKeystrokeMode.isActive {
                deactivateDirectKeystrokeModeClearingStickyState()
            }
        case .live:
            if directKeystrokeMode.isActive {
                deactivateDirectKeystrokeModeClearingStickyState()
            }
            activateLiveTypeThroughMode()
        }
    }

    /// Promote Type (type-through) to the active dock mode the first
    /// time a fresh session reaches `.active` (spec 011 US1 — founder
    /// D3). One-shot per session: explicit user mode choices — including
    /// a pre-connect choice made on the detail surface — and subsequent
    /// frames/reconnects inside the same session are never overridden.
    private func promoteTypeThroughDefaultOnSessionActivationIfNeeded() {
        guard session?.state == .active,
              !hasAppliedTypeThroughDefaultForCurrentSession
        else {
            return
        }
        hasAppliedTypeThroughDefaultForCurrentSession = true
        // The pre-activation choice flag is consumed here — after the
        // activation decision, later mode picks are tracked fresh.
        defer { hasUserSelectedDockModeThisSession = false }
        guard !hasUserSelectedDockModeThisSession,
              !liveTypeThroughMode.isActive,
              !directKeystrokeMode.isActive
        else {
            return
        }
        activateLiveTypeThroughMode()
    }

    private func deactivateDirectKeystrokeModeClearingStickyState() {
        directKeystrokeMode = DirectKeystrokeMode(
            isActive: false,
            page: .qwerty,
            inputSurface: directKeystrokeMode.inputSurface,
            hasShownEntryWarningThisSession: directKeystrokeMode.hasShownEntryWarningThisSession
        )
        // FR-012 (spec 002): sticky modifiers never survive a mode change.
        stickyModifierState = .init()
    }

    private func activateLiveTypeThroughMode() {
        resolveLiveInsertFlushWaiters(succeeded: false)
        liveWindow = LiveTypeThroughWindow()
        liveChunkInFlight = false
        liveInFlightBaseline = nil
        liveFieldText = ""
        liveTypeThroughMode = LiveTypeThroughMode(
            isActive: true,
            selectedTier: nil,
            lastStatus: .idle,
            lastSealReason: nil,
            hasShownEntryDisclosureThisSession: liveTypeThroughMode.hasShownEntryDisclosureThisSession
        )
    }

    private func deactivateLiveTypeThroughMode() {
        resolveLiveInsertFlushWaiters(succeeded: false)
        liveWindow = LiveTypeThroughWindow()
        liveChunkInFlight = false
        liveInFlightBaseline = nil
        liveFieldText = ""
        liveTypeThroughMode = LiveTypeThroughMode(
            isActive: false,
            selectedTier: nil,
            lastStatus: liveTypeThroughMode.lastStatus,
            lastSealReason: liveTypeThroughMode.lastSealReason,
            hasShownEntryDisclosureThisSession: liveTypeThroughMode.hasShownEntryDisclosureThisSession
        )
    }

    /// Full reset applied at every fresh session start / disconnect /
    /// profile change, in lockstep with the Direct-mode reset. Also
    /// drops any open Live window and re-arms the one-shot Type default
    /// (spec 011 US1) for the next session activation. A pre-activation
    /// user mode choice deliberately survives this reset — the promotion
    /// consumes it at activation.
    private func resetLiveTypeThroughState() {
        resolveLiveInsertFlushWaiters(succeeded: false)
        liveWindow = LiveTypeThroughWindow()
        liveChunkInFlight = false
        liveInFlightBaseline = nil
        liveFieldText = ""
        liveBackspacePassThroughCount = 0
        liveTypeThroughMode = .composeDefault
        hasAppliedTypeThroughDefaultForCurrentSession = false
        // Spec 015 FR-004: the keyboard-up dock is one row per session start.
        isRemoteInputAccessoryPanelExpanded = false
    }

    /// Marks the per-session Live transport disclosure as shown (peer to
    /// Direct's one-time-per-session entry warning). Reset on new session.
    public func markLiveTypeThroughEntryDisclosureShown() {
        guard !liveTypeThroughMode.hasShownEntryDisclosureThisSession else { return }
        liveTypeThroughMode.hasShownEntryDisclosureThisSession = true
    }

    /// Feed a committed-text snapshot from the Live editor (marked/composing
    /// range already excluded — FR-002) plus whether marked text is present.
    /// Reconciles the current window and dispatches the resulting insert /
    /// delete deltas (US1/US3). No Send tap — commit is the trigger.
    public func liveCommit(committedText: String, hasMarkedText: Bool) {
        guard liveTypeThroughMode.isActive, session?.state == .active else {
            return
        }
        markTransientFrameDeliveryInteractionActivity()
        openFreshLiveWindowIfSealed()
        liveWindow.commit(committedText: committedText, hasMarkedText: hasMarkedText)
        // Keep the model's authoritative line mirror in step with the editor
        // when not composing, so a later model-driven clear has a correct
        // baseline. Never rewrite the field while marked text is present —
        // that would disrupt the IME (T015 protection).
        if !hasMarkedText, liveFieldText != committedText {
            liveFieldText = committedText
        }
        dispatchLivePendingWork()
    }

    /// Delete one grapheme backward from the current Live line (the reused
    /// ⌫ action button, D1).
    ///
    /// While this window holds graphemes it delivered, the delete is a local
    /// un-type and the mirror stays truthful — that is spec 009's diff-driven
    /// reconciliation and it is unchanged.
    ///
    /// At the window start it used to do **nothing** (spec 009 FR-011 clamped
    /// it and set `liveReachedWindowStart`), which is what the founder reported
    /// on build 11 as "Type mode's backspace doesn't work": the mirror is empty
    /// on entering Type mode and again after every Return, so in a terminal
    /// session the key was inert exactly when it was reached for. Spec 035
    /// FR-006/D1 narrows FR-011 to what it was actually protecting — a
    /// *diff-driven bulk* delete may not cross a seal — and lets one explicit
    /// keypress through as one remote `BackSpace`, which is what the identical
    /// control in Compose mode has always sent.
    public func liveDeleteBackward() {
        guard liveTypeThroughMode.isActive, session?.state == .active else {
            return
        }
        markTransientFrameDeliveryInteractionActivity()
        openFreshLiveWindowIfSealed()
        guard !liveFieldText.isEmpty else {
            // One key, one BackSpace (FR-007) — never the clamped count, which
            // is the bulk delete FR-011 exists to stop.
            liveBackspacePassThroughCount += 1
            emitLiveControlKey(
                .backspace,
                repeatCount: 1,
                streamID: activeFrameStreamID,
                sessionID: session?.id,
                profileID: selectedProfileID
            )
            return
        }
        liveFieldText = String(liveFieldText.dropLast())
        liveWindow.commit(committedText: liveFieldText, hasMarkedText: false)
        dispatchLivePendingWork()
    }

    /// Commit a line boundary (the reused ↵ action button, or a Return from
    /// the soft keyboard). Flushes pending inserts, delivers a remote Return
    /// key, seals the window, and opens a fresh window for the next line
    /// (FR-010).
    public func liveNewline() {
        guard liveTypeThroughMode.isActive, session?.state == .active else {
            return
        }
        markTransientFrameDeliveryInteractionActivity()
        openFreshLiveWindowIfSealed()
        liveWindow.commit(committedText: liveFieldText, hasMarkedText: false)
        liveWindow.newline()
        dispatchLivePendingWork()
    }

    private func openFreshLiveWindowIfSealed() {
        guard liveWindow.isSealed else { return }
        liveWindow = LiveTypeThroughWindow()
        liveTypeThroughMode.selectedTier = nil
    }

    /// Seal the current Live window on an FR-011 event. Retains any
    /// not-yet-delivered tail locally so nothing is lost (FR-015); the
    /// delivered portion stays at the remote and a fresh forward-only window
    /// opens on the next commit.
    public func sealLiveWindow(reason: LiveWindowSealReason, status: LiveDeliveryStatus? = nil) {
        guard liveTypeThroughMode.isActive, !liveWindow.isSealed else {
            return
        }
        let retainedTail = liveWindow.retainedTail
        liveWindow.seal(reason: reason)
        liveTypeThroughMode.lastSealReason = reason
        if let status {
            liveTypeThroughMode.lastStatus = status
        }
        liveFieldText = retainedTail
    }

    /// Seal the Live window on a pointer/trackpad interaction that could move
    /// the remote insertion point (FR-011). Called from the pointer send
    /// entrypoints.
    private func sealLiveWindowForPointerInteraction() {
        guard liveTypeThroughMode.isActive, !liveWindow.isSealed else {
            return
        }
        sealLiveWindow(reason: .pointerInteraction)
    }

    private func currentLiveCapabilities() -> LiveDeliveryLadder.Capabilities {
        let profileID = session?.profileID ?? selectedProfileID
        let helperState = helperTextBridgeState(for: profileID)
        let helperReachable: Bool
        if let helperState,
           let helperTextInsertClient,
           Self.canRouteThroughHelperTextBridge(state: helperState, client: helperTextInsertClient) {
            helperReachable = true
        } else {
            helperReachable = false
        }
        let utf8Confirmed = activeTextClient?.utf8ClipboardSupport == .supported
        return LiveDeliveryLadder.Capabilities(
            helperReachable: helperReachable,
            utf8ClipboardConfirmed: utf8Confirmed
        )
    }

    private func isCurrentLiveTarget(
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) -> Bool {
        liveTypeThroughMode.isActive
            && activeFrameStreamID == streamID
            && session?.id == sessionID
            && selectedProfileID == profileID
    }

    /// Drain the coalesced pending batch and deliver it: deletes and the
    /// line boundary ride the VNC key lane (FR-005/FR-009/FR-010); the
    /// insert delta rides the window's locked insert tier (FR-004/FR-006).
    /// Single-in-flight for the async helper/clipboard tiers (FR-008).
    private func dispatchLivePendingWork() {
        guard liveTypeThroughMode.isActive, !liveChunkInFlight, liveWindow.hasPendingWork else {
            return
        }

        let pendingOps = liveWindow.pendingOperations
        let insertPayload = pendingOps.reduce(into: "") { accumulator, op in
            if case let .insert(text) = op {
                accumulator += text
            }
        }

        var insertTier: LiveTypeThroughAdapterTier?
        if !insertPayload.isEmpty {
            let kind = LiveInsertPayloadKind.classify(insertPayload)
            if let locked = liveTypeThroughMode.selectedTier {
                insertTier = locked
            } else if let chosen = LiveDeliveryLadder.insertTier(
                for: kind,
                capabilities: currentLiveCapabilities()
            ) {
                insertTier = chosen
                liveTypeThroughMode.selectedTier = chosen
            } else {
                // Unreachable since spec 011 (the keysym stream is a universal
                // fallback), kept as a defensive retain.
                sealLiveWindow(reason: .adapterFailure, status: .retainedFailure)
                return
            }
        }

        // Snapshot the pre-fold mirror: a failed async delivery rolls back to
        // this baseline so the failed chunk is retained, not vanished (FR-015).
        let preFoldBaseline = liveWindow.deliveredText
        let ops = liveWindow.takePending()
        var deleteCount = 0
        var insertText = ""
        var hasNewline = false
        for op in ops {
            switch op {
            case let .deleteBackward(count):
                deleteCount += count
            case let .insert(text):
                insertText += text
            case .newline:
                hasNewline = true
            }
        }

        let streamID = activeFrameStreamID
        let sessionID = session?.id
        let profileID = selectedProfileID

        // Deletes ride the VNC key lane, ahead of any insert (FR-007).
        if deleteCount > 0 {
            emitLiveControlKey(
                .backspace,
                repeatCount: deleteCount,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            )
        }

        switch insertTier {
        case .helperNativeInsert:
            liveInFlightBaseline = preFoldBaseline
            fireLiveAsyncInsertAfterKeyLaneDeletes(
                deleteCount: deleteCount,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            ) { [weak self] in
                self?.deliverLiveInsertThroughHelper(
                    insertText,
                    emitReturnAfter: hasNewline,
                    streamID: streamID,
                    sessionID: sessionID,
                    profileID: profileID
                )
            }
        case .clipboardChunk:
            liveInFlightBaseline = preFoldBaseline
            fireLiveAsyncInsertAfterKeyLaneDeletes(
                deleteCount: deleteCount,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            ) { [weak self] in
                self?.deliverLiveInsertThroughClipboard(
                    insertText,
                    emitReturnAfter: hasNewline,
                    streamID: streamID,
                    sessionID: sessionID,
                    profileID: profileID
                )
            }
        case .keyEvent:
            deliverLiveInsertThroughKeyEvents(
                insertText,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            )
            finishLiveKeyLaneBatch(
                hasNewline: hasNewline,
                status: .asciiLastResort,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            )
        case .none:
            // Delete-only and/or newline-only batch: no insert tier involved.
            finishLiveKeyLaneBatch(
                hasNewline: hasNewline,
                status: liveTypeThroughMode.lastStatus,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            )
        }
    }

    private func finishLiveKeyLaneBatch(
        hasNewline: Bool,
        status: LiveDeliveryStatus,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) {
        if hasNewline {
            emitLiveControlKey(
                .return,
                repeatCount: 1,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            )
        }
        liveTypeThroughMode.lastStatus = status
        if hasNewline {
            openFreshLiveWindowAfterNewline()
        } else {
            dispatchLivePendingWork()
        }
    }

    private func openFreshLiveWindowAfterNewline() {
        liveWindow = LiveTypeThroughWindow()
        liveTypeThroughMode.selectedTier = nil
        liveFieldText = ""
    }

    /// Cross-lane order barrier: a same-batch async insert (helper/clipboard)
    /// must not overtake the batch's BackSpaces, which ride the serialized key
    /// lane and can stall behind MainActor work. When the batch carried
    /// deletes, hold the single-in-flight gate and fire the insert from a
    /// no-op key-lane entry that runs only after every previously enqueued
    /// key event has flushed to the socket (FR-007).
    private func fireLiveAsyncInsertAfterKeyLaneDeletes(
        deleteCount: Int,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?,
        fire: @escaping @MainActor () -> Void
    ) {
        guard deleteCount > 0 else {
            fire()
            return
        }
        liveChunkInFlight = true
        liveTypeThroughMode.lastStatus = .delivering
        keyInputDispatcher.enqueue(
            operation: {
                await MainActor.run { fire() }
            },
            validate: { [weak self, streamID, sessionID, profileID] in
                await MainActor.run {
                    guard let self else {
                        return false
                    }
                    return self.activeFrameStreamID == streamID
                        && self.session?.id == sessionID
                        && self.selectedProfileID == profileID
                }
            },
            record: { _, _, _ in },
            handleFailure: { _, _, _ in }
        )
    }

    private func emitLiveControlKey(
        _ named: KeysymMapping.NamedKey,
        repeatCount: Int,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) {
        guard let emitter = keystrokeEmitter, repeatCount > 0 else {
            return
        }
        let keysym = KeysymMapping.keysym(for: named)
        for _ in 0..<repeatCount {
            enqueueKeyEventEmission(
                emitter: emitter,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            ) {
                try await emitter.emit(keysym: keysym, modifiers: [])
            }
        }
    }

    /// ASCII last-resort insert tier: each printable ASCII scalar rides the
    /// VNC key lane as its identity keysym (FR-004 tier 3). Unicode never
    /// reaches this path — the ladder routes it to helper/clipboard or
    /// retains it (FR-005).
    private func deliverLiveInsertThroughKeyEvents(
        _ text: String,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) {
        guard let emitter = keystrokeEmitter, !text.isEmpty else {
            return
        }
        // Same scalar-level transcoding as Compose keystrokeStream (spec 011):
        // ASCII rides its Latin-1 keysym, Hangul/CJK ride the X11 Unicode
        // keysym convention `0x01000000 | scalar` — live-verified to render on
        // macOS Screen Sharing (2026-07-13). Return scalars inside the insert
        // payload stay inserts here; the line boundary emits its own Return.
        for scalar in text.unicodeScalars {
            guard let keysym = TextKeystrokeTranscoder.keysym(for: scalar) else {
                continue
            }
            enqueueKeyEventEmission(
                emitter: emitter,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            ) {
                try await emitter.emit(keysym: keysym, modifiers: [])
            }
        }
    }

    /// Primary insert tier: helper `nativeInsert` (the only path with
    /// observed delivery confirmation, FR-004/FR-013). One request per
    /// coalesced chunk; single-in-flight so further commits coalesce.
    private func deliverLiveInsertThroughHelper(
        _ text: String,
        emitReturnAfter: Bool,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) {
        guard let helperTextInsertClient, let sessionID else {
            sealLiveWindow(reason: .adapterFailure, status: .retainedFailure)
            return
        }
        liveChunkInFlight = true
        liveTypeThroughMode.lastStatus = .delivering
        let helperBox = HelperTextInsertClientBox(client: helperTextInsertClient)
        let metadata = HelperTextInsertRequestMetadata(
            sessionID: sessionID,
            payloadEncoding: TextInjectionPayloadEncoding.classify(text),
            payloadSizeBucket: HelperTextPayloadSizeBucket.bucket(utf8ByteCount: text.utf8.count)
        )
        Task.detached(priority: .userInitiated) { [weak self, helperBox, metadata, text] in
            do {
                let result = try await helperBox.client.insertText(text, metadata: metadata)
                await self?.completeLiveInsert(
                    succeeded: result.status == .sent,
                    status: .deliveredObserved,
                    emitReturnAfter: emitReturnAfter,
                    streamID: streamID,
                    sessionID: sessionID,
                    profileID: profileID
                )
            } catch {
                await self?.completeLiveInsert(
                    succeeded: false,
                    status: .deliveredObserved,
                    emitReturnAfter: emitReturnAfter,
                    streamID: streamID,
                    sessionID: sessionID,
                    profileID: profileID
                )
            }
        }
    }

    /// Disclosed degraded insert tier (founder D2): chunked VNC clipboard +
    /// paste. Overwrites the remote general clipboard and carries the
    /// ~0.30 s settle; single-in-flight with coalescing (FR-008/FR-014).
    private func deliverLiveInsertThroughClipboard(
        _ text: String,
        emitReturnAfter: Bool,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) {
        guard let activeTextClient else {
            sealLiveWindow(reason: .adapterFailure, status: .retainedFailure)
            return
        }
        liveChunkInFlight = true
        liveTypeThroughMode.lastStatus = .delivering
        let clientBox = RemoteClipboardTextClientBox(client: activeTextClient)
        let settleDelay = Self.remoteClipboardPasteSettleDelay
        Task.detached(priority: .userInitiated) { [weak self, clientBox, text] in
            do {
                try clientBox.client.setClipboardText(text)
                if settleDelay > 0 {
                    let nanoseconds = UInt64((settleDelay * 1_000_000_000).rounded())
                    try? await Task.sleep(nanoseconds: nanoseconds)
                }
                try clientBox.client.sendPasteCommand(.commandV)
                await self?.completeLiveInsert(
                    succeeded: true,
                    status: .unconfirmedClipboard,
                    emitReturnAfter: emitReturnAfter,
                    streamID: streamID,
                    sessionID: sessionID,
                    profileID: profileID
                )
            } catch {
                await self?.completeLiveInsert(
                    succeeded: false,
                    status: .unconfirmedClipboard,
                    emitReturnAfter: emitReturnAfter,
                    streamID: streamID,
                    sessionID: sessionID,
                    profileID: profileID
                )
            }
        }
    }

    private func completeLiveInsert(
        succeeded: Bool,
        status: LiveDeliveryStatus,
        emitReturnAfter: Bool,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) {
        liveChunkInFlight = false
        let preFoldBaseline = liveInFlightBaseline
        liveInFlightBaseline = nil
        guard isCurrentLiveTarget(streamID: streamID, sessionID: sessionID, profileID: profileID) else {
            resolveLiveInsertFlushWaiters(succeeded: false)
            return
        }
        guard succeeded else {
            // Insert-adapter failure: the dispatch fold optimistically counted
            // this chunk as delivered — roll the mirror back to the pre-fold
            // baseline first so the failed chunk re-enters the retained tail
            // (FR-015), then seal and surface a safe failure rather than
            // silently retrying on another tier (FR-006).
            if let preFoldBaseline {
                liveWindow.rollBackDelivery(toPreDispatchBaseline: preFoldBaseline)
            }
            if liveWindow.isSealed {
                // A pointer/focus seal landed while this chunk was in flight
                // and its retention trusted the fold. Re-retain against the
                // rolled-back mirror and surface the failure the seal masked.
                liveFieldText = liveWindow.retainedTail
                liveTypeThroughMode.lastStatus = .retainedFailure
            } else {
                sealLiveWindow(reason: .adapterFailure, status: .retainedFailure)
            }
            resolveLiveInsertFlushWaiters(succeeded: false)
            return
        }
        liveTypeThroughMode.lastStatus = status
        if emitReturnAfter {
            emitLiveControlKey(
                .return,
                repeatCount: 1,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            )
            openFreshLiveWindowAfterNewline()
            resolveLiveInsertFlushWaiters(succeeded: true)
            return
        }
        // Drain any commits that coalesced while this chunk was in flight.
        dispatchLivePendingWork()
        resolveLiveInsertFlushWaiters(succeeded: true)
    }

    /// Drive a logical key event from the custom soft keyboard.
    ///
    /// - `.pageToggle` swaps QWERTY ↔ special-keys page; never
    ///   emits a `KeyEvent` (FR-002).
    /// - `.character`/`.named` emit a wire `KeyEvent` wrapped by
    ///   the currently-active sticky modifier set.  After a
    ///   successful (or attempted) emission, armed modifiers are
    ///   consumed; locked modifiers stay locked (FR-005).
    /// - `.modifier(_)` taps a sticky-modifier slot through the
    ///   `StickyModifiers` state machine.  No `KeyEvent` is
    ///   emitted; the slot transitions
    ///   idle → armed → locked → idle per the 400 ms double-tap
    ///   window.
    /// - `.clearModifiers` is the FR-013 panic clear; resets all
    ///   four sticky slots to idle and emits no `KeyEvent`.
    ///
    /// `KeyEvent`s are dropped silently when there is no active
    /// session (`spec.md` IN-003) — `keystrokeEmitter` is `nil`
    /// outside an active stream.  Direct mode being inactive
    /// (`directKeystrokeMode.isActive == false`) also drops the
    /// emission so a stale view-tree tap during a transition
    /// cannot leak through.  Sticky-modifier taps and clear DO
    /// update state even when no session exists — the user can
    /// pre-arm modifiers before the wire is up.
    ///
    /// Per `contracts/keystroke-emitter.md`, throws from the
    /// emitter are surfaced via `try?` here; on throw, sticky-
    /// armed state is still consumed so the user is not stranded
    /// with phantom-armed modifiers after a partial wire write.
    public func tapDirectKey(_ key: DirectKey) async {
        markTransientFrameDeliveryInteractionActivity()
        switch key {
        case .pageToggle:
            setDirectKeystrokePage(directKeystrokeMode.page == .qwerty ? .special : .qwerty)
            return

        case .modifier(let modifier):
            // Sticky-modifier taps update state regardless of
            // active-session presence — the user may pre-arm a
            // modifier before the wire is up; we just won't have
            // anywhere to emit until they tap a non-modifier key
            // with an emitter present.
            stickyModifierState.tap(modifier, at: ContinuousClock.now)
            return

        case .clearModifiers:
            stickyModifierState.clear()
            return

        case .character(let character):
            guard directKeystrokeMode.isActive,
                  let emitter = keystrokeEmitter,
                  let keysym = KeysymMapping.keysym(for: character)
            else {
                return
            }
            let modifiers = Set(stickyModifierState.activeModifiers)
            enqueueKeyEventEmission(
                emitter: emitter,
                streamID: activeFrameStreamID,
                sessionID: session?.id,
                profileID: selectedProfileID
            ) {
                try await emitter.emit(keysym: keysym, modifiers: modifiers)
            }
            stickyModifierState.consume()

        case .named(let namedKey):
            guard directKeystrokeMode.isActive,
                  let emitter = keystrokeEmitter
            else {
                return
            }
            let keysym = KeysymMapping.keysym(for: namedKey)
            let modifiers = Set(stickyModifierState.activeModifiers)
            enqueueKeyEventEmission(
                emitter: emitter,
                streamID: activeFrameStreamID,
                sessionID: session?.id,
                profileID: selectedProfileID
            ) {
                try await emitter.emit(keysym: keysym, modifiers: modifiers)
            }
            stickyModifierState.consume()
        }
    }

    /// Drive a hardware-keyboard press / release through the wire.
    ///
    /// Called from `DirectKeystrokeResponderView.pressesBegan` /
    /// `pressesEnded` for each `UIPress` whose `UIKey.keyCode`
    /// resolved to a known X11 keysym.  Each call sends exactly
    /// ONE `KeyEvent` (down OR up) on the wire — `KeystrokeEmitter`
    /// does NOT wrap the press with modifier-down/up because the
    /// OS already reports each modifier key as its own UIPress.
    /// Wrapping would double-press the modifier.
    ///
    /// A hardware Ctrl-c sequence therefore reaches the wire as
    /// four discrete calls — Ctrl down → c down → c up → Ctrl up
    /// — which is byte-identical to the on-screen Ctrl-c envelope
    /// emitted by `tapDirectKey(.character("c"))` while
    /// `StickyModifiers[.control] == .armed` (SC-005).
    ///
    /// Drops silently when:
    /// - Direct mode is not active (FR-007 — hardware path only
    ///   fires when the user has opted into Direct mode).
    /// - There is no active session (`keystrokeEmitter` is `nil`
    ///   outside an active stream — `spec.md` IN-003 fallback).
    ///
    /// **Sticky state is not touched** — `consume()`
    /// is the soft-keyboard "tap once → arm → consume" UX.  The
    /// hardware path's modifiers come from `UIKey.modifierFlags` and
    /// are already physically held by the user; consuming sticky
    /// state on every hardware press would erase a pre-armed sticky
    /// modifier the user pre-armed via the on-screen keyboard.
    public func handleHardwareKey(
        keysym: UInt32,
        modifiers: Set<DirectKeystrokeModifier>,
        isDown: Bool
    ) async {
        // Spec 011: the hardware path belongs to Type (type-through)
        // mode — the successor of Direct's hardware surface. Stale
        // press events that arrive during a mode toggle (e.g. the user
        // releases a key just after switching) drop silently rather
        // than leaking a press onto the wire.
        guard liveTypeThroughMode.isActive,
              let emitter = keystrokeEmitter
        else {
            return
        }
        markTransientFrameDeliveryInteractionActivity()
        // `modifiers` is presently informational (matches what
        // `UIKey.modifierFlags` reported on the press).  We do not
        // wrap here — every hardware UIPress emits exactly one
        // `KeyEvent`; the OS-reported modifier UIPresses fire
        // their own `handleHardwareKey` calls and produce the
        // adjacent modifier-down / modifier-up `KeyEvent`s
        // directly.  We pass `modifiers` through the signature so
        // future paths (e.g. `UIKeyCommand` shortcuts where iOS
        // does NOT report the modifier as its own UIPress) can
        // reuse `KeystrokeEmitter.emitHardware(keysym:modifiers:)`
        // for wrapping without changing this caller surface.
        _ = modifiers
        enqueueKeyEventEmission(
            emitter: emitter,
            streamID: activeFrameStreamID,
            sessionID: session?.id,
            profileID: selectedProfileID
        ) {
            try await emitter.emitHardware(keysym: keysym, isDown: isDown)
        }
    }

    /// Send a discrete terminal-control key (Esc / Tab / Ctrl-C /
    /// arrows) from **Compose mode** without switching to Direct
    /// Keystroke mode (spec 003 US5 / FR-013).
    ///
    /// This is the convenience bridge for a terminal / AI-CLI user
    /// who is composing multilingual text but needs to fire one
    /// control key — the founder's exact ICP.  It:
    ///
    /// - Emits through the same `KeystrokeEmitter` as Direct mode, so
    ///   the wire envelope is identical (Ctrl-C → `Ctrl down → c down
    ///   → c up → Ctrl up`).
    /// - Does **not** touch `composeDraft` — the partial multilingual
    ///   message the user is building survives untouched (the strip is
    ///   orthogonal to the compose buffer).
    /// - Does **not** read or consume `stickyModifierState` — sticky
    ///   modifiers are a Direct-mode affordance; the quick key carries
    ///   its own fixed modifier set.
    /// - Drops silently when there is no active session
    ///   (`keystrokeEmitter == nil`, matching `spec.md` IN-003).
    ///
    /// Constitution §IV: the keysym is NOT logged anywhere persistent;
    /// the diagnostic safe-detail catalog is unaffected.
    public func sendComposeQuickKey(_ key: ComposeQuickKey) async {
        guard keystrokeEmitter != nil else {
            return
        }
        let flushed = await flushPendingLiveInsertBeforeControl()
        guard FlushBarrier.shouldEmitAfterFlush(succeeded: flushed),
              let emitter = keystrokeEmitter
        else {
            return
        }
        markTransientFrameDeliveryInteractionActivity()
        let emission = key.emission
        enqueueKeyEventEmission(
            emitter: emitter,
            streamID: activeFrameStreamID,
            sessionID: session?.id,
            profileID: selectedProfileID
        ) {
            try await emitter.emit(
                keysym: emission.keysym,
                modifiers: emission.modifiers
            )
        }
    }

    /// Send a discrete remote key from the shared accessory strip
    /// (spec 011 US2) — the orca-style key row above the editor in
    /// both Type and Compose modes.
    ///
    /// Unlike the retired Compose quick keys, strip emissions wrap in
    /// the caller's active sticky modifiers (armed or locked) and
    /// consume armed slots after the emission, mirroring the retired
    /// Direct soft-keyboard envelope exactly (⌃ arm + `c` →
    /// `Ctrl down → c down → c up → Ctrl up`).
    ///
    /// Drops silently when there is no active session
    /// (`keystrokeEmitter == nil`). Constitution §IV: the keysym is
    /// never logged; the diagnostic safe-detail catalog is unaffected.
    public func sendAccessoryKey(_ key: AccessoryKey) async {
        guard keystrokeEmitter != nil else {
            return
        }
        let flushed = await flushPendingLiveInsertBeforeControl()
        guard FlushBarrier.shouldEmitAfterFlush(succeeded: flushed),
              let emitter = keystrokeEmitter
        else {
            return
        }
        markTransientFrameDeliveryInteractionActivity()
        let modifiers = Set(stickyModifierState.activeModifiers)
        enqueueKeyEventEmission(
            emitter: emitter,
            streamID: activeFrameStreamID,
            sessionID: session?.id,
            profileID: selectedProfileID
        ) {
            try await emitter.emit(keysym: key.keysym, modifiers: modifiers)
        }
        stickyModifierState.consume()
    }

    /// Spec 012 US2-3 model layer: wait for an in-flight helper/clipboard
    /// insert (and drain any not-yet-dispatched live work) before a
    /// strip/quick-key keysym is enqueued. Key-lane inserts share
    /// `OutboundInputEventDispatcher`, so once they are enqueued the
    /// control naturally follows. Flush failure drops the control and
    /// leaves sticky / draft state untouched.
    private func flushPendingLiveInsertBeforeControl() async -> Bool {
        guard liveTypeThroughMode.isActive else {
            return true
        }
        while liveWindow.hasPendingWork || liveChunkInFlight {
            if liveWindow.hasPendingWork, !liveChunkInFlight {
                dispatchLivePendingWork()
            }
            if liveChunkInFlight {
                let succeeded = await waitForCurrentLiveInsertChunk()
                if !succeeded {
                    return false
                }
            } else if liveWindow.hasPendingWork {
                // Key-lane-only batch: already enqueued ahead of us.
                break
            }
        }
        return keystrokeEmitter != nil
    }

    private func waitForCurrentLiveInsertChunk() async -> Bool {
        if !liveChunkInFlight {
            return true
        }
        return await withCheckedContinuation { continuation in
            liveInsertFlushWaiters.append(continuation)
        }
    }

    private func resolveLiveInsertFlushWaiters(succeeded: Bool) {
        let waiters = liveInsertFlushWaiters
        liveInsertFlushWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: succeeded)
        }
    }

    /// Send a Mac-aware session control through the normal VNC
    /// `KeyEvent` path. These controls are documented macOS keyboard
    /// shortcuts, not private ARD commands, so they preserve the
    /// existing VNC-only fallback surface and do not touch Compose
    /// draft state or Direct-mode sticky modifiers.
    public func sendMacSessionControl(_ control: MacSessionControl) async {
        guard let emitter = keystrokeEmitter else {
            return
        }
        markTransientFrameDeliveryInteractionActivity()
        let emission = control.emission
        enqueueKeyEventEmission(
            emitter: emitter,
            streamID: activeFrameStreamID,
            sessionID: session?.id,
            profileID: selectedProfileID
        ) {
            try await emitter.emit(
                keysym: emission.keysym,
                modifiers: emission.modifiers
            )
        }
    }

    private func enqueueKeyEventEmission(
        emitter: KeystrokeEmitter,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        keyInputDispatcher.enqueue(
            operation: operation,
            validate: { [weak self, emitter, streamID, sessionID, profileID] in
                await MainActor.run {
                    guard let self else {
                        return false
                    }
                    return self.activeFrameStreamID == streamID
                        && self.session?.id == sessionID
                        && self.selectedProfileID == profileID
                        && self.keystrokeEmitter === emitter
                }
            },
            record: { [weak self, emitter, streamID, sessionID, profileID] queueDelayMilliseconds, operationMilliseconds, timedOut in
                await MainActor.run {
                    guard let self,
                          self.activeFrameStreamID == streamID,
                          self.session?.id == sessionID,
                          self.selectedProfileID == profileID,
                          self.keystrokeEmitter === emitter
                    else {
                        return
                    }
                    self.recordOutboundInputEvent(
                        queueDelayMilliseconds: queueDelayMilliseconds,
                        operationMilliseconds: operationMilliseconds,
                        timedOut: timedOut
                    )
                }
            },
            handleFailure: { [weak self, emitter, streamID, sessionID, profileID] queueDelayMilliseconds, operationMilliseconds, timedOut in
                await MainActor.run {
                    guard let self,
                          self.activeFrameStreamID == streamID,
                          self.session?.id == sessionID,
                          self.selectedProfileID == profileID,
                          self.keystrokeEmitter === emitter
                    else {
                        return
                    }
                    self.recordOutboundInputEvent(
                        queueDelayMilliseconds: queueDelayMilliseconds,
                        operationMilliseconds: operationMilliseconds,
                        timedOut: timedOut
                    )
                    self.cancelKeyInputEventQueue()
                }
            }
        )
    }

    nonisolated private static func connectAndReadFirstFrame(
        connector: any RFBFirstFrameConnecting,
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> ConnectionResult {
        if let streamingClient = connector as? any RFBStreamingClient {
            let serverInit = try streamingClient.connectSession(
                host: host,
                port: port,
                credential: credential,
                timeout: timeout
            )
            let pump = RFBFramePump(source: streamingClient)
            var firstFrame: RFBFramePumpFrame?
            _ = try pump.run(
                configuration: RFBFramePumpConfiguration(maxFrames: 1, requestTimeout: timeout)
            ) { frame in
                firstFrame = frame
                return .stop
            }

            guard let firstFrame else {
                throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
            }

            return ConnectionResult(
                serverInit: serverInit,
                framebuffer: firstFrame.framebuffer,
                frameCapturedAt: firstFrame.capturedAt
            )
        }

        let serverInit: RFBServerInit
        if let authenticatedConnector = connector as? any RFBAuthenticatedFirstFrameConnecting {
            serverInit = try authenticatedConnector.connectFirstFrame(
                host: host,
                port: port,
                credential: credential,
                timeout: timeout
            )
        } else {
            guard credential == .none else {
                throw RFBNetworkClientError.authenticationRequired([RFBSecurityType.vncAuthentication.rawValue])
            }

            serverInit = try connector.connectNoAuthFirstFrame(
                host: host,
                port: port,
                timeout: timeout
            )
        }

        return ConnectionResult(
            serverInit: serverInit,
            framebuffer: nil,
            frameCapturedAt: Date()
        )
    }

    public func updateComposeDraftText(_ text: String) {
        guard var draft = composeDraft else {
            return
        }
        guard draft.text != text else {
            return
        }

        if draft.sendState == .sending {
            var nextDraft = ComposeDraft(sessionID: draft.sessionID)
            nextDraft.updateText(text)
            composeDraft = nextDraft
            clearComposeSendFeedbackAfterLocalEdit()
            return
        }

        draft.updateText(text)
        composeDraft = draft
        clearComposeSendFeedbackAfterLocalEdit()
    }

    public func recordComposeSendPreparation(_ report: ComposeSendPreparationReport) {
        isFocusedInputSendFeedbackClearPending = false
        latestComposeSendPreparation = report
    }

    /// Deliver the finished Compose draft as a stream of `KeyEvent`s
    /// instead of clobbering the remote clipboard with a paste.
    ///
    /// This is the default Compose & Send delivery: local composition
    /// (IME, multilingual, voice, etc.) is unchanged — only the transport
    /// to the remote switches from "set clipboard + ⌘V" to "type the
    /// finished text". It reuses the exact proven `KeystrokeEmitter`
    /// transport the Direct Keystroke keyboard uses (so what lands is what
    /// already lands for on-screen keys), and never touches the remote
    /// clipboard.
    ///
    /// Falls back to `sendComposedText` (clipboard / helper routing) when
    /// there is no active key-event transport, or when the text contains a
    /// scalar the transcoder can't represent as a keysym — so configured
    /// Helper bridges and edge-case payloads still work.
    ///
    /// Non-ASCII scalars ride the X11 Unicode keysym convention
    /// (`0x01000000 | scalar`). Verified live against macOS Screen Sharing:
    /// Korean/CJK render regardless of the remote IME (astral-plane emoji,
    /// e.g. U+1F600, is the known exception). Other servers are expected to
    /// honor X11 Unicode keysyms but remain unverified per target.
    public func sendComposedTextAsKeystrokes(_ text: String) {
        guard var draft = composeDraft else {
            return
        }
        guard draft.sendState != .sending else {
            return
        }

        isFocusedInputSendFeedbackClearPending = false
        draft.updateText(text)
        let now = Date()
        let payloadEncoding = TextInjectionPayloadEncoding.classify(draft.text)

        guard !draft.text.isEmpty else {
            let message = TextInjectionError.emptyDraft.localizedDescription
            draft.markFailed(reason: message, at: now)
            composeDraft = draft
            latestInjectionAttempt = TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .keystrokeStream,
                payloadEncoding: payloadEncoding,
                startedAt: now,
                finishedAt: now,
                status: .failed,
                safeMessage: message
            )
            return
        }

        // No key-event transport (or a Helper is the configured route) —
        // defer to the existing clipboard/helper routing unchanged.
        guard let emitter = keystrokeEmitter else {
            sendComposedText(text)
            return
        }

        // The transcoder owns text → keysym mapping (Return/Tab + the X11
        // Unicode convention). A control scalar it can't represent drops to
        // the clipboard path rather than silently losing characters.
        let transcoding = TextKeystrokeTranscoder.transcode(draft.text)
        guard transcoding.canEmit, !transcoding.events.isEmpty else {
            sendComposedText(text)
            return
        }

        let streamID = activeFrameStreamID
        let sessionID = session?.id
        let profileID = selectedProfileID

        markTransientFrameDeliveryInteractionActivity()
        draft.markSending(path: .keystrokeStream, at: now)
        composeDraft = draft

        for event in transcoding.events {
            enqueueKeyEventEmission(
                emitter: emitter,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            ) {
                try await emitter.emit(keysym: event.keysym, modifiers: [])
            }
        }

        // Key events are enqueued reliably on the wire; remote rendering of
        // Unicode keysyms is unconfirmable, so report like the paste path:
        // dispatched, not confirmed.
        let message = "Typed \(transcoding.usesUnicodeKeysyms ? "as keystrokes (Unicode)" : "as keystrokes")"
        draft.markUnknown(message: message, at: now)
        composeDraft = draft
        latestInjectionAttempt = TextInjectionAttempt(
            draftID: draft.id,
            sessionID: draft.sessionID,
            path: .keystrokeStream,
            payloadEncoding: payloadEncoding,
            startedAt: now,
            finishedAt: now,
            status: .unknown,
            safeMessage: message
        )
    }

    public func sendComposedText(_ text: String, pasteCommand: PasteCommand = .commandV) {
        guard var draft = composeDraft else {
            return
        }

        guard draft.sendState != .sending else {
            return
        }

        isFocusedInputSendFeedbackClearPending = false
        draft.updateText(text)
        let now = Date()
        let payloadEncoding = TextInjectionPayloadEncoding.classify(draft.text)

        guard !draft.text.isEmpty else {
            let message = TextInjectionError.emptyDraft.localizedDescription
            draft.markFailed(reason: message, at: now)
            composeDraft = draft
            latestInjectionAttempt = TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .vncClipboardPaste,
                pasteCommand: pasteCommand,
                payloadEncoding: payloadEncoding,
                startedAt: now,
                finishedAt: now,
                status: .failed,
                safeMessage: message
            )
            return
        }

        let utf8Support = activeTextClient?.utf8ClipboardSupport ?? .unknown
        let transferMode = TextClipboardTransferMode.selected(utf8Support: utf8Support)
        let profileID = session?.profileID ?? selectedProfileID
        let helperState = helperTextBridgeState(for: profileID)
        let profile = profileID.flatMap { id in
            profiles.first { $0.id == id }
        }
        if let profileID,
           let helperState,
           let helperTextInsertClient,
           Self.canRouteThroughHelperTextBridge(
                state: helperState,
                client: helperTextInsertClient
           ) {
            sendComposedTextThroughHelper(
                draft: draft,
                payloadEncoding: payloadEncoding,
                transferMode: transferMode,
                utf8Support: utf8Support,
                profileID: profileID,
                helperState: helperState,
                helperTextInsertClient: helperTextInsertClient,
                now: now
            )
            return
        }
        if let profile,
           let helperState,
           Self.canRouteThroughStoredHelperTextBridge(
                state: helperState,
                profile: profile
           ) {
            sendComposedTextThroughStoredHelper(
                draft: draft,
                payloadEncoding: payloadEncoding,
                transferMode: transferMode,
                utf8Support: utf8Support,
                profile: profile,
                helperState: helperState,
                pasteCommand: pasteCommand,
                now: now
            )
            return
        }
        if payloadEncoding == .utf8ExtensionRequired,
           utf8Support != .supported,
           let profile,
           let helperState,
           Self.canAttemptStoredHelperTextBridge(
                state: helperState,
                profile: profile
           ) {
            sendComposedTextThroughStoredHelper(
                draft: draft,
                payloadEncoding: payloadEncoding,
                transferMode: transferMode,
                utf8Support: utf8Support,
                profile: profile,
                helperState: helperState,
                pasteCommand: pasteCommand,
                now: now
            )
            return
        }

        guard let activeTextClient else {
            let message = TextInjectionError
                .clipboardUnavailable("Connect to a remote session before sending text.")
                .localizedDescription
            draft.markFailed(reason: message, at: now)
            composeDraft = draft
            latestInjectionAttempt = TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .vncClipboardPaste,
                pasteCommand: pasteCommand,
                payloadEncoding: payloadEncoding,
                startedAt: now,
                finishedAt: now,
                status: .failed,
                safeMessage: message
            )
            return
        }

        // Clipboard cannot carry this payload to this server (Korean/CJK/emoji
        // to a server without negotiated UTF-8 clipboard — e.g. macOS Screen
        // Sharing, which decodes ClientCutText as Latin-1 and drops the text).
        // The Unicode-keysym keystroke path DOES deliver it — verified live
        // against macOS Screen Sharing that it renders `0x01000000 | codepoint`
        // keysyms into the literal characters. Route there rather than failing,
        // but only when the keystroke transport exists and can represent the
        // whole payload; otherwise fall through to the honest error below.
        // (No loop risk: `sendComposedTextAsKeystrokes` only falls back to this
        // method when the emitter is absent or the transcoder can't emit, both
        // of which are excluded by these guards.)
        if payloadEncoding == .utf8ExtensionRequired,
           utf8Support != .supported,
           keystrokeEmitter != nil,
           TextKeystrokeTranscoder.transcode(draft.text).canEmit {
            sendComposedTextAsKeystrokes(text)
            return
        }

        if let message = TextInjectionClipboardPolicy.unsupportedPayloadMessage(
            payloadEncoding: payloadEncoding,
            utf8Support: utf8Support
        ) {
            let helperFailureCode = Self.helperFailureCode(
                state: helperState,
                client: helperTextInsertClient
            )
            let helperAwareMessage = Self.helperUnavailableMessage(
                vncMessage: message,
                helperFailureCode: helperFailureCode
            )
            if let profileID {
                setHelperTextBridgeState(
                    Self.updatedHelperTextBridgeState(
                        helperState ?? HelperTextBridgeProfileState(),
                        failureCode: helperFailureCode
                    ),
                    for: profileID
                )
            }
            draft.markFailed(reason: helperAwareMessage, at: now)
            composeDraft = draft
            latestInjectionAttempt = TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .vncClipboardPaste,
                pasteCommand: pasteCommand,
                payloadEncoding: payloadEncoding,
                clipboardTransferMode: transferMode,
                utf8ClipboardSupport: utf8Support,
                startedAt: now,
                finishedAt: now,
                status: .failed,
                remoteClipboardRestore: .unsupported,
                safeMessage: helperAwareMessage
            )
            return
        }

        let draftForSend = draft
        draft.markSending(path: .vncClipboardPaste, at: now)
        composeDraft = draft
        latestInjectionAttempt = TextInjectionAttempt(
            draftID: draft.id,
            sessionID: draft.sessionID,
            path: .vncClipboardPaste,
            pasteCommand: pasteCommand,
            payloadEncoding: payloadEncoding,
            clipboardTransferMode: transferMode,
            utf8ClipboardSupport: utf8Support,
            startedAt: now,
            status: .unknown,
            remoteClipboardRestore: .unsupported,
            safeMessage: "Sending through vncClipboardPaste"
        )

        let draftID = draft.id
        let sessionID = draft.sessionID
        let clientBox = RemoteClipboardTextClientBox(client: activeTextClient)
        let pasteSettleDelay = Self.remoteClipboardPasteSettleDelay

        Task.detached(priority: .userInitiated) { [
            weak self,
            clientBox,
            draftForSend,
            pasteCommand,
            now,
            transferMode,
            utf8Support
        ] in
            var sendingDraft = draftForSend
            var attempt = TextInjectionAttempt(
                draftID: sendingDraft.id,
                sessionID: sendingDraft.sessionID,
                path: .vncClipboardPaste,
                pasteCommand: pasteCommand,
                payloadEncoding: TextInjectionPayloadEncoding.classify(sendingDraft.text),
                clipboardTransferMode: transferMode,
                utf8ClipboardSupport: utf8Support,
                startedAt: now,
                remoteClipboardRestore: .unsupported
            )
            sendingDraft.markSending(path: .vncClipboardPaste, at: now)

            switch await Self.textInjectionCurrentness(
                self,
                draftID: draftID,
                sessionID: sessionID,
                clientBox: clientBox
            ) {
            case .current:
                break
            case .staleDraft:
                await Self.cancelTextInjection(
                    self,
                    draft: sendingDraft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID,
                    reason: .draftChanged
                )
                return
            case .staleSession:
                await Self.cancelTextInjection(
                    self,
                    draft: sendingDraft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID
                )
                return
            }

            do {
                try clientBox.client.setClipboardText(sendingDraft.text)
                attempt.clipboardSetStatus = .succeeded
            } catch {
                let message = Self.safeClipboardFailureMessage(from: error)
                sendingDraft.markFailed(reason: message, at: now)
                attempt.finishedAt = now
                attempt.status = .failed
                attempt.clipboardSetStatus = .failed
                attempt.safeMessage = message
                await Self.finishTextInjection(
                    self,
                    draft: sendingDraft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID
                )
                return
            }

            if pasteSettleDelay > 0 {
                let nanoseconds = UInt64((pasteSettleDelay * 1_000_000_000).rounded())
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            switch await Self.textInjectionCurrentness(
                self,
                draftID: draftID,
                sessionID: sessionID,
                clientBox: clientBox
            ) {
            case .current:
                break
            case .staleDraft:
                await Self.cancelTextInjection(
                    self,
                    draft: sendingDraft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID,
                    reason: .draftChanged
                )
                return
            case .staleSession:
                await Self.cancelTextInjection(
                    self,
                    draft: sendingDraft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID
                )
                return
            }

            do {
                try clientBox.client.sendPasteCommand(pasteCommand)
                attempt.pasteCommandStatus = .succeeded
            } catch {
                let message = Self.safePasteFailureMessage(from: error)
                sendingDraft.markFailed(reason: message, at: now)
                attempt.finishedAt = now
                attempt.status = .failed
                attempt.pasteCommandStatus = .failed
                attempt.safeMessage = message
                await Self.finishTextInjection(
                    self,
                    draft: sendingDraft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID
                )
                return
            }

            let message = attempt.payloadEncoding?.unconfirmedPasteMessage(
                transferMode: attempt.clipboardTransferMode,
                utf8Support: attempt.utf8ClipboardSupport
            )
                ?? "Paste command sent; remote app confirmation unavailable."
            sendingDraft.markPasteDispatched(message: message, at: now)
            attempt.finishedAt = now
            attempt.status = .unknown
            attempt.safeMessage = message
            await Self.finishTextInjection(
                self,
                draft: sendingDraft,
                attempt: attempt,
                draftID: draftID,
                sessionID: sessionID
            )
        }
    }

    private func sendComposedTextThroughHelper(
        draft: ComposeDraft,
        payloadEncoding: TextInjectionPayloadEncoding,
        transferMode: TextClipboardTransferMode,
        utf8Support: RemoteClipboardUTF8Support,
        profileID: ConnectionProfile.ID,
        helperState: HelperTextBridgeProfileState,
        helperTextInsertClient: any HelperTextInsertClient,
        now: Date
    ) {
        var sendingDraft = draft
        let metadata = HelperTextInsertRequestMetadata(
            sessionID: sendingDraft.sessionID,
            payloadEncoding: payloadEncoding,
            payloadSizeBucket: HelperTextPayloadSizeBucket.bucket(
                utf8ByteCount: sendingDraft.text.utf8.count
            )
        )
        let helperBox = HelperTextInsertClientBox(client: helperTextInsertClient)
        let draftID = sendingDraft.id
        let sessionID = sendingDraft.sessionID

        sendingDraft.markSending(path: .helperTextBridge, at: now)
        composeDraft = sendingDraft
        latestInjectionAttempt = TextInjectionAttempt(
            draftID: sendingDraft.id,
            sessionID: sendingDraft.sessionID,
            path: .helperTextBridge,
            payloadEncoding: payloadEncoding,
            clipboardTransferMode: transferMode,
            utf8ClipboardSupport: utf8Support,
            startedAt: now,
            status: .unknown,
            remoteClipboardRestore: .notAttempted,
            safeMessage: "Sending through helperTextBridge"
        )

        Task.detached(priority: .userInitiated) { [weak self, helperBox, sendingDraft, metadata, now, profileID, helperState] in
            var draft = sendingDraft
            var attempt = TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .helperTextBridge,
                payloadEncoding: metadata.payloadEncoding,
                clipboardTransferMode: transferMode,
                utf8ClipboardSupport: utf8Support,
                startedAt: now,
                remoteClipboardRestore: .notAttempted
            )

            guard await Self.isCurrentHelperTextInjection(
                self,
                draftID: draftID,
                sessionID: sessionID,
                profileID: profileID,
                helperBox: helperBox
            ) else {
                await Self.cancelTextInjection(
                    self,
                    draft: draft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID
                )
                return
            }

            do {
                let helperResult = try await helperBox.client.insertText(draft.text, metadata: metadata)
                let result = helperResult.requestID == metadata.id
                    ? helperResult
                    : HelperTextInsertResult(
                        requestID: metadata.id,
                        strategyUsed: .unsupported,
                        status: .failed,
                        safeFailureCode: .insertRejected
                    )
                let message = Self.helperInsertResultMessage(for: result)
                attempt.finishedAt = Date()
                attempt.status = result.status
                attempt.helperStrategyUsed = result.strategyUsed
                attempt.safeMessage = message
                attempt.remoteClipboardRestore = Self.remoteClipboardRestoreStatus(for: result)
                let nextState = Self.updatedHelperTextBridgeState(
                    helperState,
                    result: result
                )

                switch result.status {
                case .sent:
                    draft.markSent(message: message, at: attempt.finishedAt ?? now)
                case .failed:
                    draft.markFailed(reason: message, at: attempt.finishedAt ?? now)
                case .unknown:
                    draft.markUnknown(message: message, at: attempt.finishedAt ?? now)
                }

                await Self.finishTextInjection(
                    self,
                    draft: draft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID,
                    helperTextBridgeState: nextState,
                    helperProfileID: profileID
                )
            } catch {
                let failureCode = Self.helperFailureCode(from: error)
                let message = HelperTextBridgeError.safeMessage(for: failureCode)
                attempt.finishedAt = Date()
                attempt.status = .failed
                attempt.safeMessage = message
                draft.markFailed(reason: message, at: attempt.finishedAt ?? now)

                await Self.finishTextInjection(
                    self,
                    draft: draft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID,
                    helperTextBridgeState: Self.updatedHelperTextBridgeState(
                        helperState,
                        failureCode: failureCode
                    ),
                    helperProfileID: profileID
                )
            }
        }
    }

    private func sendComposedTextThroughStoredHelper(
        draft: ComposeDraft,
        payloadEncoding: TextInjectionPayloadEncoding,
        transferMode: TextClipboardTransferMode,
        utf8Support: RemoteClipboardUTF8Support,
        profile: ConnectionProfile,
        helperState: HelperTextBridgeProfileState,
        pasteCommand: PasteCommand,
        now: Date
    ) {
        guard let configuration = profile.helperTextBridge,
              let secretRef = configuration.pairingSecretRef,
              let helperPort = UInt16(exactly: configuration.port)
        else {
            return
        }

        var sendingDraft = draft
        let metadata = HelperTextInsertRequestMetadata(
            sessionID: sendingDraft.sessionID,
            payloadEncoding: payloadEncoding,
            payloadSizeBucket: HelperTextPayloadSizeBucket.bucket(
                utf8ByteCount: sendingDraft.text.utf8.count
            )
        )
        let draftID = sendingDraft.id
        let sessionID = sendingDraft.sessionID
        let profileID = profile.id
        let helperHost = configuration.resolvedHost(fallback: profile.host)
        let credentialStore = credentialStore

        sendingDraft.markSending(path: .helperTextBridge, at: now)
        composeDraft = sendingDraft
        latestInjectionAttempt = TextInjectionAttempt(
            draftID: sendingDraft.id,
            sessionID: sendingDraft.sessionID,
            path: .helperTextBridge,
            payloadEncoding: payloadEncoding,
            clipboardTransferMode: transferMode,
            utf8ClipboardSupport: utf8Support,
            startedAt: now,
            status: .unknown,
            remoteClipboardRestore: .notAttempted,
            safeMessage: "Sending through helperTextBridge"
        )

        Task.detached(priority: .userInitiated) { [weak self, credentialStore, sendingDraft, metadata, now, profileID, helperState, secretRef, helperHost, helperPort] in
            var draft = sendingDraft
            var attempt = TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .helperTextBridge,
                payloadEncoding: metadata.payloadEncoding,
                clipboardTransferMode: transferMode,
                utf8ClipboardSupport: utf8Support,
                startedAt: now,
                remoteClipboardRestore: .notAttempted
            )

            guard await Self.isCurrentStoredHelperTextInjection(
                self,
                draftID: draftID,
                sessionID: sessionID,
                profileID: profileID
            ) else {
                await Self.cancelTextInjection(
                    self,
                    draft: draft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID
                )
                return
            }

            let secret: String
            do {
                guard let loadedSecret = try await credentialStore?.password(for: secretRef),
                      !loadedSecret.isEmpty
                else {
                    throw HelperTextBridgeError.unavailable(.notConfigured)
                }
                secret = loadedSecret
            } catch let error as HelperTextBridgeError {
                await Self.finishStoredHelperRouteBlocked(
                    self,
                    draft: draft,
                    attempt: attempt,
                    helperState: helperState,
                    failureCode: Self.helperFailureCode(from: error),
                    vncPasteCommand: pasteCommand,
                    profileID: profileID,
                    draftID: draftID,
                    sessionID: sessionID,
                    now: now
                )
                return
            } catch {
                await Self.finishStoredHelperRouteBlocked(
                    self,
                    draft: draft,
                    attempt: attempt,
                    helperState: helperState,
                    failureCode: .notConfigured,
                    vncPasteCommand: pasteCommand,
                    profileID: profileID,
                    draftID: draftID,
                    sessionID: sessionID,
                    now: now
                )
                return
            }

            let client = NaruHelperNetworkTextInsertClient(
                host: helperHost,
                port: helperPort,
                pairingSecret: secret
            )

            let readyState: HelperTextBridgeProfileState
            do {
                let capability = try await client.capability(
                    profilePairingFingerprint: helperState.pairingFingerprint
                )
                let capabilityState = Self.helperTextBridgeProbeState(
                    for: profile,
                    capability: capability
                )
                guard capability.availability == .reachable else {
                    await Self.finishStoredHelperRouteBlocked(
                        self,
                        draft: draft,
                        attempt: attempt,
                        helperState: capabilityState,
                        failureCode: Self.failureCode(for: capability.availability),
                        vncPasteCommand: pasteCommand,
                        profileID: profileID,
                        draftID: draftID,
                        sessionID: sessionID,
                        now: now
                    )
                    return
                }
                guard capabilityState.supportsNativeInsertWhenKnown else {
                    await Self.finishStoredHelperRouteBlocked(
                        self,
                        draft: draft,
                        attempt: attempt,
                        helperState: capabilityState,
                        failureCode: .permissionMissing,
                        vncPasteCommand: pasteCommand,
                        profileID: profileID,
                        draftID: draftID,
                        sessionID: sessionID,
                        now: now
                    )
                    return
                }
                readyState = Self.updatedHelperTextBridgeState(
                    capabilityState,
                    failureCode: .none
                )
                await Self.publishHelperTextBridgeState(
                    self,
                    state: readyState,
                    profileID: profileID
                )
            } catch {
                await Self.finishStoredHelperRouteBlocked(
                    self,
                    draft: draft,
                    attempt: attempt,
                    helperState: helperState,
                    failureCode: Self.helperFailureCode(from: error),
                    vncPasteCommand: pasteCommand,
                    profileID: profileID,
                    draftID: draftID,
                    sessionID: sessionID,
                    now: now
                )
                return
            }

            do {
                let result = try await client.insertText(draft.text, metadata: metadata)
                let message = Self.helperInsertResultMessage(for: result)
                attempt.finishedAt = Date()
                attempt.status = result.status
                attempt.helperStrategyUsed = result.strategyUsed
                attempt.safeMessage = message
                attempt.remoteClipboardRestore = Self.remoteClipboardRestoreStatus(for: result)
                let nextState = Self.updatedHelperTextBridgeState(
                    readyState,
                    result: result
                )

                switch result.status {
                case .sent:
                    draft.markSent(message: message, at: attempt.finishedAt ?? now)
                case .failed:
                    draft.markFailed(reason: message, at: attempt.finishedAt ?? now)
                case .unknown:
                    draft.markUnknown(message: message, at: attempt.finishedAt ?? now)
                }

                await Self.finishTextInjection(
                    self,
                    draft: draft,
                    attempt: attempt,
                    draftID: draftID,
                    sessionID: sessionID,
                    helperTextBridgeState: nextState,
                    helperProfileID: profileID
                )
            } catch {
                await Self.finishStoredHelperFailure(
                    self,
                    draft: draft,
                    attempt: attempt,
                    helperState: readyState,
                    failureCode: Self.helperFailureCode(from: error),
                    profileID: profileID,
                    draftID: draftID,
                    sessionID: sessionID,
                    now: now
                )
            }
        }
    }

    private static func finishStoredHelperRouteBlocked(
        _ model: NaruRemoteAppModel?,
        draft: ComposeDraft,
        attempt: TextInjectionAttempt,
        helperState: HelperTextBridgeProfileState,
        failureCode: HelperTextBridgeFailureCode,
        vncPasteCommand: PasteCommand,
        profileID: ConnectionProfile.ID,
        draftID: ComposeDraft.ID,
        sessionID: RemoteSession.ID,
        now: Date
    ) async {
        let payloadEncoding = attempt.payloadEncoding ?? TextInjectionPayloadEncoding.classify(draft.text)
        let utf8Support = attempt.utf8ClipboardSupport ?? .unknown
        guard let vncMessage = TextInjectionClipboardPolicy.unsupportedPayloadMessage(
            payloadEncoding: payloadEncoding,
            utf8Support: utf8Support
        ) else {
            await finishStoredHelperFailure(
                model,
                draft: draft,
                attempt: attempt,
                helperState: helperState,
                failureCode: failureCode,
                profileID: profileID,
                draftID: draftID,
                sessionID: sessionID,
                now: now
            )
            return
        }

        let finishedAt = Date()
        let message = helperUnavailableMessage(
            vncMessage: vncMessage,
            helperFailureCode: failureCode
        )
        var failedDraft = draft
        failedDraft.markFailed(reason: message, at: finishedAt)
        let failedAttempt = TextInjectionAttempt(
            id: attempt.id,
            draftID: draft.id,
            sessionID: draft.sessionID,
            path: .vncClipboardPaste,
            pasteCommand: vncPasteCommand,
            payloadEncoding: payloadEncoding,
            clipboardTransferMode: TextClipboardTransferMode.selected(utf8Support: utf8Support),
            utf8ClipboardSupport: utf8Support,
            startedAt: attempt.startedAt,
            finishedAt: finishedAt,
            status: .failed,
            clipboardSetStatus: .notAttempted,
            pasteCommandStatus: .notAttempted,
            remoteClipboardRestore: .unsupported,
            safeMessage: message
        )

        await finishTextInjection(
            model,
            draft: failedDraft,
            attempt: failedAttempt,
            draftID: draftID,
            sessionID: sessionID,
            helperTextBridgeState: updatedHelperTextBridgeState(
                helperState,
                failureCode: failureCode
            ),
            helperProfileID: profileID
        )
    }

    private static func finishStoredHelperFailure(
        _ model: NaruRemoteAppModel?,
        draft: ComposeDraft,
        attempt: TextInjectionAttempt,
        helperState: HelperTextBridgeProfileState,
        failureCode: HelperTextBridgeFailureCode,
        profileID: ConnectionProfile.ID,
        draftID: ComposeDraft.ID,
        sessionID: RemoteSession.ID,
        now: Date
    ) async {
        var failedDraft = draft
        var failedAttempt = attempt
        let message = HelperTextBridgeError.safeMessage(for: failureCode)
        failedAttempt.finishedAt = Date()
        failedAttempt.status = .failed
        failedAttempt.safeMessage = message
        failedDraft.markFailed(reason: message, at: failedAttempt.finishedAt ?? now)
        await finishTextInjection(
            model,
            draft: failedDraft,
            attempt: failedAttempt,
            draftID: draftID,
            sessionID: sessionID,
            helperTextBridgeState: updatedHelperTextBridgeState(
                helperState,
                failureCode: failureCode
            ),
            helperProfileID: profileID
        )
    }

    nonisolated private static func canRouteThroughHelperTextBridge(
        state: HelperTextBridgeProfileState,
        client: any HelperTextInsertClient
    ) -> Bool {
        state.isEnabled &&
            state.availability == .reachable &&
            client.availability == .reachable &&
            state.supportsNativeInsertWhenKnown
    }

    nonisolated private static func canRouteThroughStoredHelperTextBridge(
        state: HelperTextBridgeProfileState,
        profile: ConnectionProfile
    ) -> Bool {
        guard let configuration = profile.helperTextBridge else {
            return false
        }
        return state.isEnabled &&
            state.availability == .reachable &&
            configuration.isEnabled &&
            configuration.pairingSecretRef != nil &&
            state.supportsNativeInsertWhenKnown
    }

    nonisolated private static func canAttemptStoredHelperTextBridge(
        state: HelperTextBridgeProfileState,
        profile: ConnectionProfile
    ) -> Bool {
        guard let configuration = profile.helperTextBridge else {
            return false
        }
        guard state.isEnabled,
              configuration.isEnabled,
              configuration.pairingSecretRef != nil
        else {
            return false
        }
        switch state.availability {
        case .checking:
            return true
        case .reachable:
            return state.supportsNativeInsertWhenKnown
        case .notConfigured, .disabled, .revoked:
            return false
        case .unreachable, .permissionMissing, .versionUnsupported:
            return false
        }
    }

    nonisolated private static func helperFailureCode(
        state: HelperTextBridgeProfileState?,
        client: (any HelperTextInsertClient)?
    ) -> HelperTextBridgeFailureCode {
        guard let state else {
            return .notConfigured
        }
        guard state.isEnabled else {
            switch state.availability {
            case .notConfigured:
                return .notConfigured
            case .revoked:
                return .revoked
            default:
                return .disabled
            }
        }

        switch state.availability {
        case .reachable:
            guard state.supportsNativeInsertWhenKnown else {
                return .permissionMissing
            }
            return client?.availability == .reachable ? .none : .unreachable
        case .notConfigured:
            return .notConfigured
        case .disabled:
            return .disabled
        case .checking, .unreachable:
            return .unreachable
        case .permissionMissing:
            return .permissionMissing
        case .revoked:
            return .revoked
        case .versionUnsupported:
            return .versionUnsupported
        }
    }

    nonisolated private static func helperFailureCode(from error: Error) -> HelperTextBridgeFailureCode {
        if case let HelperTextBridgeError.unavailable(code) = error {
            return code
        }
        return .insertRejected
    }

    nonisolated private static func diagnosticComposeRouteBlocker(
        for failureCode: HelperTextBridgeFailureCode
    ) -> DiagnosticComposeRouteBlocker {
        switch failureCode {
        case .none:
            return .none
        case .notConfigured:
            return .helperNotConfigured
        case .disabled:
            return .helperDisabled
        case .unreachable, .insertTimedOut:
            return .helperUnreachable
        case .revoked:
            return .helperRevoked
        case .permissionMissing:
            return .helperPermissionMissing
        case .versionUnsupported:
            return .helperVersionUnsupported
        case .focusUnavailable, .insertRejected, .restoreFailed:
            return .helperUnreachable
        }
    }

    nonisolated private static func helperUnavailableMessage(
        vncMessage: String,
        helperFailureCode: HelperTextBridgeFailureCode
    ) -> String {
        "\(vncMessage) \(HelperTextBridgeError.safeMessage(for: helperFailureCode))"
    }

    nonisolated private static func updatedHelperTextBridgeState(
        _ state: HelperTextBridgeProfileState,
        result: HelperTextInsertResult
    ) -> HelperTextBridgeProfileState {
        updatedHelperTextBridgeState(state, failureCode: result.safeFailureCode)
    }

    nonisolated private static func updatedHelperTextBridgeState(
        _ state: HelperTextBridgeProfileState,
        failureCode: HelperTextBridgeFailureCode
    ) -> HelperTextBridgeProfileState {
        var next = state
        next.lastFailureCode = failureCode
        next.lastCheckedBucket = .recent
        next.availability = availability(for: failureCode)
        return next
    }

    nonisolated private static func helperTextBridgeProbeState(
        for profile: ConnectionProfile,
        availability: HelperTextBridgeAvailability
    ) -> HelperTextBridgeProfileState {
        helperTextBridgeProbeState(
            for: profile,
            failureCode: failureCode(for: availability)
        )
    }

    nonisolated private static func helperTextBridgeProbeState(
        for profile: ConnectionProfile,
        capability: NaruHelperCapabilityResponse
    ) -> HelperTextBridgeProfileState {
        let configuration = profile.helperTextBridge
        let availability = capability.availability
        return HelperTextBridgeProfileState(
            isEnabled: availability != .disabled &&
                availability != .notConfigured &&
                availability != .revoked,
            pairingFingerprint: availability == .revoked ? nil : configuration?.pairingFingerprint,
            availability: availability,
            lastFailureCode: failureCode(for: availability),
            lastCheckedBucket: .recent,
            capabilitySummary: HelperTextBridgeCapabilitySummary(response: capability)
        )
    }

    nonisolated private static func helperTextBridgeProbeState(
        for profile: ConnectionProfile,
        failureCode: HelperTextBridgeFailureCode
    ) -> HelperTextBridgeProfileState {
        let configuration = profile.helperTextBridge
        let availability = availability(for: failureCode)
        return HelperTextBridgeProfileState(
            isEnabled: availability != .disabled &&
                availability != .notConfigured &&
                availability != .revoked,
            pairingFingerprint: availability == .revoked ? nil : configuration?.pairingFingerprint,
            availability: availability,
            lastFailureCode: failureCode,
            lastCheckedBucket: .recent
        )
    }

    nonisolated private static func availability(
        for failureCode: HelperTextBridgeFailureCode
    ) -> HelperTextBridgeAvailability {
        switch failureCode {
        case .none, .focusUnavailable, .insertRejected, .restoreFailed:
            return .reachable
        case .notConfigured:
            return .notConfigured
        case .disabled:
            return .disabled
        case .unreachable, .insertTimedOut:
            return .unreachable
        case .revoked:
            return .revoked
        case .permissionMissing:
            return .permissionMissing
        case .versionUnsupported:
            return .versionUnsupported
        }
    }

    nonisolated private static func failureCode(
        for availability: HelperTextBridgeAvailability
    ) -> HelperTextBridgeFailureCode {
        switch availability {
        case .notConfigured:
            return .notConfigured
        case .disabled:
            return .disabled
        case .checking, .unreachable:
            return .unreachable
        case .reachable:
            return .none
        case .permissionMissing:
            return .permissionMissing
        case .revoked:
            return .revoked
        case .versionUnsupported:
            return .versionUnsupported
        }
    }

    nonisolated private static func remoteClipboardRestoreStatus(
        for result: HelperTextInsertResult
    ) -> RemoteClipboardRestoreStatus {
        guard result.strategyUsed == .pasteboardPasteWithRestore else {
            return .notAttempted
        }
        return result.safeFailureCode == .restoreFailed ? .failed : .succeeded
    }

    /// Status copy for a helper insert result (QW3). A confirmed native
    /// insert (`nativeInsert` + `.sent`) is the one delivery route that can
    /// honestly claim the text landed, so it gets the positive fixed
    /// message; every other outcome keeps the fixed safe-catalog copy.
    nonisolated private static func helperInsertResultMessage(
        for result: HelperTextInsertResult
    ) -> String {
        if result.status == .sent,
           result.strategyUsed == .nativeInsert,
           result.safeFailureCode == HelperTextBridgeFailureCode.none {
            return helperNativeInsertConfirmedMessage
        }
        return HelperTextBridgeError.safeMessage(for: result.safeFailureCode)
    }

    private enum TextInjectionCurrentness {
        case current
        case staleDraft
        case staleSession
    }

    private enum TextInjectionCancellationReason {
        case sessionChanged
        case draftChanged

        var message: String {
            switch self {
            case .sessionChanged:
                "Text send cancelled because the remote session changed."
            case .draftChanged:
                "Text send cancelled because the compose draft changed."
            }
        }
    }

    private static func textInjectionCurrentness(
        _ model: NaruRemoteAppModel?,
        draftID: ComposeDraft.ID,
        sessionID: RemoteSession.ID,
        clientBox: RemoteClipboardTextClientBox
    ) async -> TextInjectionCurrentness {
        await MainActor.run {
            guard let model,
                  model.session?.id == sessionID,
                  model.session?.state == .active,
                  clientBox.matches(model.activeTextClient)
            else {
                return .staleSession
            }
            guard model.composeDraft?.id == draftID,
                  model.composeDraft?.sessionID == sessionID
            else {
                return .staleDraft
            }
            return .current
        }
    }

    private static func isCurrentHelperTextInjection(
        _ model: NaruRemoteAppModel?,
        draftID: ComposeDraft.ID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        helperBox: HelperTextInsertClientBox
    ) async -> Bool {
        await MainActor.run {
            guard let model,
                  model.session?.id == sessionID,
                  model.session?.profileID == profileID,
                  model.session?.state == .active,
                  helperBox.matches(model.helperTextInsertClient)
            else {
                return false
            }
            let helperState = model.helperTextBridgeState[profileID] ?? HelperTextBridgeProfileState()
            guard Self.canRouteThroughHelperTextBridge(
                state: helperState,
                client: helperBox.client
            ) else {
                return false
            }
            return model.composeDraft?.id == draftID
        }
    }

    private static func isCurrentStoredHelperTextInjection(
        _ model: NaruRemoteAppModel?,
        draftID: ComposeDraft.ID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) async -> Bool {
        await MainActor.run {
            guard let model,
                  model.session?.id == sessionID,
                  model.session?.profileID == profileID,
                  model.session?.state == .active,
                  let profile = model.profiles.first(where: { $0.id == profileID })
            else {
                return false
            }
            let helperState = model.helperTextBridgeState[profileID]
                ?? Self.initialHelperTextBridgeState(for: profile)
                ?? HelperTextBridgeProfileState()
            guard Self.canAttemptStoredHelperTextBridge(
                state: helperState,
                profile: profile
            ) else {
                return false
            }
            return model.composeDraft?.id == draftID
        }
    }

    private static func finishTextInjection(
        _ model: NaruRemoteAppModel?,
        draft: ComposeDraft,
        attempt: TextInjectionAttempt,
        draftID: ComposeDraft.ID,
        sessionID: RemoteSession.ID,
        helperTextBridgeState: HelperTextBridgeProfileState? = nil,
        helperProfileID: ConnectionProfile.ID? = nil
    ) async {
        await MainActor.run {
            guard let model,
                  model.session?.id == sessionID
            else {
                return
            }
            if let helperProfileID, let helperTextBridgeState {
                let current = model.helperTextBridgeState[helperProfileID]
                let shouldPreserveUserBlockedState = current.map {
                    Self.isUserBlockedHelperTextBridgeState($0) &&
                        !Self.isUserBlockedHelperTextBridgeState(helperTextBridgeState)
                } ?? false
                if !shouldPreserveUserBlockedState {
                    model.helperTextBridgeState[helperProfileID] = helperTextBridgeState
                }
            }
            if model.composeDraft?.id == draftID,
               model.composeDraft?.sessionID == sessionID {
                model.composeDraft = draft
            }
            model.latestInjectionAttempt = attempt
        }
    }

    private static func publishHelperTextBridgeState(
        _ model: NaruRemoteAppModel?,
        state: HelperTextBridgeProfileState,
        profileID: ConnectionProfile.ID
    ) async {
        await MainActor.run {
            guard let model,
                  model.profiles.contains(where: { $0.id == profileID })
            else {
                return
            }
            let current = model.helperTextBridgeState[profileID]
            let shouldPreserveUserBlockedState = current.map {
                Self.isUserBlockedHelperTextBridgeState($0) &&
                    !Self.isUserBlockedHelperTextBridgeState(state)
            } ?? false
            if !shouldPreserveUserBlockedState {
                model.helperTextBridgeState[profileID] = state
            }
        }
    }

    private static func cancelTextInjection(
        _ model: NaruRemoteAppModel?,
        draft: ComposeDraft,
        attempt: TextInjectionAttempt,
        draftID: ComposeDraft.ID,
        sessionID: RemoteSession.ID,
        reason: TextInjectionCancellationReason = .sessionChanged
    ) async {
        var cancelledDraft = draft
        var cancelledAttempt = attempt
        let message = reason.message
        let finishedAt = Date()
        cancelledDraft.markFailed(reason: message, at: finishedAt)
        cancelledAttempt.finishedAt = finishedAt
        cancelledAttempt.status = .failed
        cancelledAttempt.safeMessage = message
        await finishTextInjection(
            model,
            draft: cancelledDraft,
            attempt: cancelledAttempt,
            draftID: draftID,
            sessionID: sessionID
        )
    }

    nonisolated private static func safeClipboardFailureMessage(from error: Error) -> String {
        if let error = error as? TextInjectionError {
            return error.localizedDescription
        }

        return TextInjectionError
            .clipboardUnavailable("Remote clipboard did not accept text.")
            .localizedDescription
    }

    nonisolated private static func safePasteFailureMessage(from error: Error) -> String {
        if let error = error as? TextInjectionError {
            return error.localizedDescription
        }

        return TextInjectionError
            .pasteCommandFailed("Remote paste command could not be delivered.")
            .localizedDescription
    }

    nonisolated private static func isUserBlockedHelperTextBridgeState(
        _ state: HelperTextBridgeProfileState
    ) -> Bool {
        state.availability == .disabled || state.availability == .revoked
    }

    private func enqueuePointerCommands(
        _ commands: [RFBPointerCommand],
        pointerClient: RFBPointerEventClient,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) {
        enqueuePointerCommands(
            RFBPointerCommandBatch(commands),
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
    }

    private func enqueuePointerCommands(
        _ commandBatch: RFBPointerCommandBatch,
        pointerClient: RFBPointerEventClient,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?,
        allowsBestEffortPointerMove: Bool = false
    ) {
        guard !commandBatch.isEmpty else {
            return
        }

        let commandBatch = pointerBatchMappedForServerDownscale(commandBatch)

        if allowsBestEffortPointerMove,
           let command = commandBatch.singleButtonlessPointerMove,
           let bestEffortClient = pointerClient as? RFBBestEffortPointerEventClient,
           isCurrentPointerInputTarget(
               pointerClient: pointerClient,
               streamID: streamID,
               sessionID: sessionID,
               profileID: profileID
           )
        {
            sendImmediateBestEffortPointerMove(command, pointerClient: bestEffortClient)
            requestPointerInputFramebufferUpdateNudge(
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            )
            return
        }

        pointerInputDispatcher.enqueue(
            operation: { [pointerClient, commandBatch] in
                switch commandBatch {
                case .none:
                    return
                case let .one(command):
                    guard !Task.isCancelled else {
                        return
                    }
                    try await pointerClient.sendPointerEvent(
                        buttonMask: command.buttonMask,
                        x: command.x,
                        y: command.y
                    )
                case let .two(first, second):
                    guard !Task.isCancelled else {
                        return
                    }
                    try await pointerClient.sendPointerEvent(
                        buttonMask: first.buttonMask,
                        x: first.x,
                        y: first.y
                    )
                    guard !Task.isCancelled else {
                        return
                    }
                    try await pointerClient.sendPointerEvent(
                        buttonMask: second.buttonMask,
                        x: second.x,
                        y: second.y
                    )
                case let .many(commands):
                    for command in commands {
                        guard !Task.isCancelled else {
                            return
                        }
                        try await pointerClient.sendPointerEvent(
                            buttonMask: command.buttonMask,
                            x: command.x,
                            y: command.y
                        )
                    }
                }
            },
            validate: { [weak self, pointerClient, streamID, sessionID, profileID] in
                await MainActor.run {
                    guard let self else {
                        return false
                    }
                    return self.isCurrentPointerInputTarget(
                        pointerClient: pointerClient,
                        streamID: streamID,
                        sessionID: sessionID,
                        profileID: profileID
                    )
                }
            },
            record: { [weak self, pointerClient, streamID, sessionID, profileID] queueDelayMilliseconds, operationMilliseconds, timedOut in
                await MainActor.run {
                    guard let self,
                          self.activeFrameStreamID == streamID,
                          self.session?.id == sessionID,
                          self.selectedProfileID == profileID,
                          self.activePointerClient === pointerClient
                    else {
                        return
                    }
                    self.recordOutboundInputEvent(
                        queueDelayMilliseconds: queueDelayMilliseconds,
                        operationMilliseconds: operationMilliseconds,
                        timedOut: timedOut
                    )
                }
            },
            handleFailure: { [weak self, pointerClient, streamID, sessionID, profileID] queueDelayMilliseconds, operationMilliseconds, timedOut in
                await MainActor.run {
                    guard let self,
                          self.activeFrameStreamID == streamID,
                          self.session?.id == sessionID,
                          self.selectedProfileID == profileID,
                          self.activePointerClient === pointerClient
                    else {
                        return
                    }
                    self.recordOutboundInputEvent(
                        queueDelayMilliseconds: queueDelayMilliseconds,
                        operationMilliseconds: operationMilliseconds,
                        timedOut: timedOut
                    )
                    self.cancelPointerInputEventQueue()
                    self.lastEmittedDragCoord = nil
                }
            }
        )
    }

    private func isCurrentPointerInputTarget(
        pointerClient: RFBPointerEventClient,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) -> Bool {
        activeFrameStreamID == streamID
            && session?.id == sessionID
            && selectedProfileID == profileID
            && activePointerClient === pointerClient
    }

    private func requestPointerInputFramebufferUpdateNudge(
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?
    ) {
        guard shouldSendOutOfBandPointerInputFramebufferUpdateNudge else {
            return
        }
        guard let sender = activeFramebufferUpdateRequestSender,
              let streamID,
              let sessionID,
              let profileID,
              isCurrentStream(streamID, sessionID: sessionID, profileID: profileID)
        else {
            return
        }

        let region = activeFramePump.map { pump in
            currentViewportRequestRegion(
                incrementalRequestIndex: max(pump.deliveredFrameCount, 1)
            )
        } ?? nil
        let pendingNudge = PendingPointerInputFramebufferUpdateNudge(
            sender: sender,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID,
            region: region
        )
        let now = Date()
        if let lastPointerInputFramebufferUpdateNudgeAt {
            let elapsed = now.timeIntervalSince(lastPointerInputFramebufferUpdateNudgeAt)
            let remaining = Self.pointerInputFramebufferUpdateNudgeMinimumInterval - elapsed
            if remaining > 0 {
                pendingPointerInputFramebufferUpdateNudge = pendingNudge
                schedulePointerInputFramebufferUpdateNudge(after: remaining)
                return
            }
        }

        sendPointerInputFramebufferUpdateNudge(pendingNudge, requestedAt: now)
    }

    private var shouldSendOutOfBandPointerInputFramebufferUpdateNudge: Bool {
        frameStreamConfiguration.requestPipelineDepth <= 1
    }

    private func schedulePointerInputFramebufferUpdateNudge(after delay: TimeInterval) {
        guard pointerInputFramebufferUpdateNudgeTask == nil else {
            return
        }

        pointerInputFramebufferUpdateNudgeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(delay, 0)))
            } catch {
                return
            }
            self?.flushPendingPointerInputFramebufferUpdateNudge()
        }
    }

    private func flushPendingPointerInputFramebufferUpdateNudge() {
        pointerInputFramebufferUpdateNudgeTask = nil
        guard let pendingNudge = pendingPointerInputFramebufferUpdateNudge else {
            return
        }
        pendingPointerInputFramebufferUpdateNudge = nil
        sendPointerInputFramebufferUpdateNudge(pendingNudge, requestedAt: Date())
    }

    private func cancelPointerInputFramebufferUpdateNudge() {
        pointerInputFramebufferUpdateNudgeTask?.cancel()
        pointerInputFramebufferUpdateNudgeTask = nil
        pendingPointerInputFramebufferUpdateNudge = nil
        lastPointerInputFramebufferUpdateNudgeAt = nil
    }

    private func sendPointerInputFramebufferUpdateNudge(
        _ nudge: PendingPointerInputFramebufferUpdateNudge,
        requestedAt: Date
    ) {
        guard isCurrentStream(
            nudge.streamID,
            sessionID: nudge.sessionID,
            profileID: nudge.profileID
        ) else {
            return
        }

        lastPointerInputFramebufferUpdateNudgeAt = requestedAt
        let timeout = Self.pointerInputFramebufferUpdateNudgeWriteTimeout
        Task.detached(priority: .userInitiated) {
            try? nudge.sender.sendFramebufferUpdateRequest(
                incremental: true,
                timeout: timeout,
                region: nudge.region
            )
        }
    }

    private func sendImmediateBestEffortPointerMove(
        _ command: RFBPointerCommand,
        pointerClient: RFBBestEffortPointerEventClient
    ) {
        let startedAt = Date()
        do {
            try pointerClient.sendBestEffortPointerEvent(
                buttonMask: command.buttonMask,
                x: command.x,
                y: command.y
            )
            recordOutboundInputEvent(
                queueDelayMilliseconds: 0,
                operationMilliseconds: elapsedMilliseconds(since: startedAt),
                timedOut: false
            )
        } catch {
            recordOutboundInputEvent(
                queueDelayMilliseconds: 0,
                operationMilliseconds: elapsedMilliseconds(since: startedAt),
                timedOut: false
            )
        }
    }

    private func enqueueCoalescedPointerMove(
        _ command: RFBPointerCommand,
        pointerClient: RFBPointerEventClient,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?,
        coalescingDelay: Duration? = nil,
        allowsBestEffort: Bool = false,
        sendsImmediatelyWhenIdle: Bool = false
    ) {
        let coalescingDelay = coalescingDelay ?? Self.directPointerMoveCoalescingDelay

        if sendsImmediatelyWhenIdle,
           allowsBestEffort,
           pendingPointerMove == nil,
           pointerMoveFlushTask == nil,
           let bestEffortClient = pointerClient as? RFBBestEffortPointerEventClient,
           isCurrentPointerInputTarget(
               pointerClient: pointerClient,
               streamID: streamID,
               sessionID: sessionID,
               profileID: profileID
           )
        {
            sendImmediateBestEffortPointerMove(command, pointerClient: bestEffortClient)
            requestPointerInputFramebufferUpdateNudge(
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID
            )
            schedulePointerMoveFlush(after: coalescingDelay)
            return
        }

        pendingPointerMove = PendingPointerMove(
            command: command,
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID,
            allowsBestEffort: allowsBestEffort
        )

        guard pointerMoveFlushTask == nil else {
            return
        }

        schedulePointerMoveFlush(after: coalescingDelay)
    }

    private func schedulePointerMoveFlush(after delay: Duration) {
        pointerMoveFlushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.flushPendingPointerMove(cancelScheduledTask: false)
        }
    }

    private func flushPendingPointerMove(cancelScheduledTask: Bool = true) {
        if cancelScheduledTask {
            pointerMoveFlushTask?.cancel()
        }
        pointerMoveFlushTask = nil

        guard let pendingMove = pendingPointerMove else {
            return
        }
        pendingPointerMove = nil

        enqueuePointerCommands(
            RFBPointerCommandBatch([pendingMove.command]),
            pointerClient: pendingMove.pointerClient,
            streamID: pendingMove.streamID,
            sessionID: pendingMove.sessionID,
            profileID: pendingMove.profileID,
            allowsBestEffortPointerMove: pendingMove.allowsBestEffort
        )
    }

    private func publishTrackpadCursor(_ cursor: TrackpadCursor, immediately: Bool = false) {
        if immediately {
            trackpadCursorPublishTask?.cancel()
            trackpadCursorPublishTask = nil
            pendingTrackpadCursor = nil
            resolvedTrackpadCursor = cursor
            trackpadCursorStore.publish(cursor)
            return
        }

        resolvedTrackpadCursor = cursor
        pendingTrackpadCursor = cursor
        guard trackpadCursorPublishTask == nil else {
            return
        }

        let delay = Self.trackpadCursorPublishDelay
        trackpadCursorPublishTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.flushPendingTrackpadCursor(cancelScheduledTask: false)
        }
    }

    private func flushPendingTrackpadCursor(cancelScheduledTask: Bool = true) {
        if cancelScheduledTask {
            trackpadCursorPublishTask?.cancel()
        }
        trackpadCursorPublishTask = nil

        guard let cursor = pendingTrackpadCursor else {
            return
        }
        pendingTrackpadCursor = nil
        trackpadCursorStore.publish(cursor)
    }

    /// Translate a tap in the framebuffer view's coordinate space into a
    /// remote-side button-1 click and dispatch it as a pair of
    /// `PointerEvent` messages (RFC 6143 §7.5.5): button-down (mask
    /// 0x01) followed by button-up (mask 0x00) at the same `(x, y)`.
    ///
    /// The view→framebuffer mapping mirrors the aspect-fit choice in
    /// `MetalFramebufferRenderer.aspectFitViewport` — the framebuffer is
    /// centered inside the view with letterbox/pillarbox bands as
    /// needed.  Taps that fall inside the letterbox bands (outside the
    /// framebuffer rectangle) are NO-OPs: we will not synthesize a
    /// click at a clamped edge pixel because the user did not actually
    /// touch the remote framebuffer.
    ///
    /// No-op cases (silent, returns without side effects):
    ///   - no active remote coordinate space (VNC ServerInit/frame size)
    ///   - no streaming pointer client (legacy first-frame connector)
    ///   - the tap falls in the letterbox/pillarbox bands
    ///   - the view or framebuffer reports a degenerate (zero/negative)
    ///     dimension
    ///
    /// Constitution §IV: the `(x, y)` coordinates and the view point
    /// are NOT logged anywhere persistent.  Coordinates can be used to
    /// infer remote screen contents, so they stay confined to the
    /// outgoing `PointerEvent` bytes.
    public func sendTapAt(viewPoint: CGPoint, viewSize: CGSize) {
        sealLiveWindowForPointerInteraction()
        guard let coordinateSpace = currentInputCoordinateSpace(),
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: coordinateSpace.width,
            framebufferHeight: coordinateSpace.height
        ) else {
            return
        }

        markTransientFrameDeliveryInteractionActivity()
        let streamID = activeFrameStreamID
        let sessionID = session?.id
        let profileID = selectedProfileID

        flushPendingPointerMove()
        enqueuePointerCommands(
            RFBPointerCommand.click(mask: RFBPointerCommand.leftButton, x: mapped.x, y: mapped.y),
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
    }

    /// Translate a long-press in the framebuffer view's coordinate
    /// space into a remote-side button-3 (right-click) click and
    /// dispatch it as a pair of `PointerEvent` messages: button-down
    /// (mask `0x04`, RFC 6143 §7.5.5 bit 2) followed by button-up
    /// (mask `0x00`) at the same `(x, y)`.
    ///
    /// Mirrors `sendTapAt(viewPoint:viewSize:)` for stream gating,
    /// view→framebuffer mapping, and constitution §IV opacity:
    /// coordinates are NOT logged anywhere persistent and the
    /// diagnostic safe-detail catalog is unaffected.
    public func sendRightClickAt(viewPoint: CGPoint, viewSize: CGSize) {
        sealLiveWindowForPointerInteraction()
        guard let coordinateSpace = currentInputCoordinateSpace(),
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: coordinateSpace.width,
            framebufferHeight: coordinateSpace.height
        ) else {
            return
        }

        markTransientFrameDeliveryInteractionActivity()
        let streamID = activeFrameStreamID
        let sessionID = session?.id
        let profileID = selectedProfileID

        flushPendingPointerMove()
        enqueuePointerCommands(
            RFBPointerCommand.click(mask: RFBPointerCommand.rightButton, x: mapped.x, y: mapped.y),
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
    }

    /// Default scroll-tick threshold (in points) used when callers
    /// invoke `sendScrollAt(viewPoint:viewSize:deltaX:deltaY:)`
    /// without an explicit threshold.  Picked so a casual two-finger
    /// pan emits roughly one tick per ~24pt of accumulated motion —
    /// close to a single mouse-wheel notch on a desktop trackpad.
    public static let scrollTickThreshold: CGFloat = 24

    /// Translate a two-finger pan delta into discrete RFB
    /// scroll-wheel ticks at a single `(x, y)` and dispatch them.
    ///
    /// Mask layout (RFC 6143 §7.5.5, bits 3..6):
    ///   - 0x08: wheel-up    (positive `deltaY`, panning content downward)
    ///   - 0x10: wheel-down  (negative `deltaY`)
    ///   - 0x20: wheel-left  (negative `deltaX`)
    ///   - 0x40: wheel-right (positive `deltaX`)
    ///
    /// Each tick is a button-down (mask) followed by button-up
    /// (mask `0x00`) at the same coords.  Sub-threshold deltas are a
    /// no-op — the caller is expected to accumulate across `.changed`
    /// callbacks so a slow drag still eventually crosses the
    /// threshold.  See `scrollTicks(forDelta:threshold:)` for the
    /// pure helper used both here and by tests.
    ///
    /// Constitution §IV: the `(x, y)` coordinates and the per-axis
    /// deltas are NOT logged anywhere persistent.
    /// Sub-notch motion carried between callbacks (spec 037). Lives on the
    /// model rather than in each gesture recognizer so every scroll source
    /// behaves the same way.
    private var scrollTickAccumulator = ScrollTickAccumulator()

    /// Ends the current scroll gesture: the leftover under one notch is
    /// dropped so the next gesture starts from zero instead of inheriting
    /// credit from the last one.
    public func endScrollGesture() {
        scrollTickAccumulator.reset()
    }

    public func sendScrollAt(
        viewPoint: CGPoint,
        viewSize: CGSize,
        deltaX: CGFloat,
        deltaY: CGFloat,
        threshold: CGFloat = scrollTickThreshold
    ) {
        sealLiveWindowForPointerInteraction()
        guard let coordinateSpace = currentInputCoordinateSpace(),
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: coordinateSpace.width,
            framebufferHeight: coordinateSpace.height
        ) else {
            return
        }

        // Accumulate across callbacks before applying the threshold (spec 037).
        // A gesture recognizer zeroes its translation every callback, so the
        // per-callback delta is a few points and `floor(delta / 24)` was zero
        // forever: the founder's "scrolling doesn't work". The remainder lives
        // in `ScrollTickAccumulator`, next to the threshold that needs it.
        let emitted = scrollTickAccumulator.accumulate(
            deltaX: deltaX,
            deltaY: deltaY,
            threshold: threshold
        )
        guard emitted.x != 0 || emitted.y != 0 else {
            return
        }

        let verticalMask: UInt8 = emitted.y >= 0 ? 0x08 : 0x10
        let horizontalMask: UInt8 = emitted.x >= 0 ? 0x40 : 0x20

        let ticks = Self.scrollTicks(
            forDelta: (x: emitted.x, y: emitted.y),
            threshold: threshold,
            verticalMask: verticalMask,
            horizontalMask: horizontalMask
        )

        guard !ticks.isEmpty else {
            return
        }

        markTransientFrameDeliveryInteractionActivity()
        let streamID = activeFrameStreamID
        let sessionID = session?.id
        let profileID = selectedProfileID

        var commands: [RFBPointerCommand] = []
        for tick in ticks {
            for _ in 0..<tick.count {
                commands.append(contentsOf: RFBPointerCommand.click(mask: tick.mask, x: mapped.x, y: mapped.y))
            }
        }
        flushPendingPointerMove()
        enqueuePointerCommands(
            commands,
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
    }

    /// Translate the start of a single-finger drag (button-1 hold) in
    /// the framebuffer view's coordinate space into a remote-side
    /// button-down `PointerEvent` (RFC 6143 §7.5.5, mask `0x01`) at
    /// the mapped framebuffer coords.
    ///
    /// Mirrors `sendTapAt(viewPoint:viewSize:)` for stream gating,
    /// view→framebuffer mapping, and constitution §IV opacity:
    /// coordinates are NOT logged anywhere persistent and the
    /// diagnostic safe-detail catalog is unaffected.
    ///
    /// No-op cases (silent, returns without side effects):
    ///   - `explicitlyDisconnected` is set (the user has torn the
    ///     session down — drag must not resurrect any wire activity)
    ///   - no active remote coordinate space (VNC ServerInit/frame size)
    ///   - no streaming pointer client
    ///   - the drag start falls in the letterbox/pillarbox bands
    public func sendPointerDownAt(viewPoint: CGPoint, viewSize: CGSize) async {
        sealLiveWindowForPointerInteraction()
        guard !explicitlyDisconnected,
              let coordinateSpace = currentInputCoordinateSpace(),
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: coordinateSpace.width,
            framebufferHeight: coordinateSpace.height
        ) else {
            return
        }

        markTransientFrameDeliveryInteractionActivity()
        let streamID = activeFrameStreamID
        let sessionID = session?.id
        let profileID = selectedProfileID

        // Anchor the throttle on the down event so the FIRST move that
        // actually crosses the 1-pixel threshold gets emitted.
        lastEmittedDragCoord = (mapped.x, mapped.y)

        flushPendingPointerMove()
        enqueuePointerCommands(
            [RFBPointerCommand(buttonMask: RFBPointerCommand.leftButton, x: mapped.x, y: mapped.y)],
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
    }

    /// Continue a single-finger drag (button-1 hold) by emitting a
    /// `PointerEvent` with mask `0x01` at the mapped framebuffer
    /// coords for `viewPoint`.  Throttle: a move whose framebuffer-
    /// coord delta from the last emitted coord is `< 1` pixel on both
    /// axes is suppressed to avoid flooding the wire. Move events that
    /// do cross that threshold are coalesced over a tiny refresh-sized
    /// window so the wire sees the newest drag position instead of a
    /// backlog of stale intermediate points.
    ///
    /// Mirrors `sendPointerDownAt(...)` for the same no-op preconditions.
    public func sendPointerMoveTo(viewPoint: CGPoint, viewSize: CGSize) async {
        guard !explicitlyDisconnected,
              let coordinateSpace = currentInputCoordinateSpace(),
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: coordinateSpace.width,
            framebufferHeight: coordinateSpace.height
        ) else {
            return
        }

        markTransientFrameDeliveryInteractionActivity()
        // Sub-pixel throttle: drop moves whose framebuffer-coord delta
        // does not advance the last emitted coord on either axis.
        if let last = lastEmittedDragCoord, last.x == mapped.x, last.y == mapped.y {
            return
        }

        let streamID = activeFrameStreamID
        let sessionID = session?.id
        let profileID = selectedProfileID

        lastEmittedDragCoord = (mapped.x, mapped.y)

        enqueueCoalescedPointerMove(
            RFBPointerCommand(buttonMask: RFBPointerCommand.leftButton, x: mapped.x, y: mapped.y),
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
    }

    /// Conclude a single-finger drag by emitting a button-up
    /// `PointerEvent` (mask `0x00`) at the mapped framebuffer coords.
    /// Clears the throttle anchor so the next drag starts fresh.
    ///
    /// Mirrors `sendPointerDownAt(...)` for the same no-op preconditions.
    public func sendPointerUpAt(viewPoint: CGPoint, viewSize: CGSize) async {
        guard !explicitlyDisconnected,
              let coordinateSpace = currentInputCoordinateSpace(),
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: coordinateSpace.width,
            framebufferHeight: coordinateSpace.height
        ) else {
            return
        }

        markTransientFrameDeliveryInteractionActivity()
        let streamID = activeFrameStreamID
        let sessionID = session?.id
        let profileID = selectedProfileID

        lastEmittedDragCoord = nil
        flushPendingPointerMove()
        enqueuePointerCommands(
            [RFBPointerCommand(buttonMask: RFBPointerCommand.released, x: mapped.x, y: mapped.y)],
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
    }

    /// Pure helper that converts a 2D pan delta into a sequence of
    /// `(mask, count)` scroll-wheel ticks.  Vertical and horizontal
    /// axes each emit at most one entry, in `(vertical, horizontal)`
    /// order so vertical pans dispatch before horizontal pans on a
    /// mixed two-finger drag.  Sub-threshold magnitudes drop the
    /// axis entirely — there is no fractional tick.
    ///
    /// Exposed publicly so tests can verify the threshold logic
    /// without touching the network or the app model.
    public static func scrollTicks(
        forDelta delta: (x: CGFloat, y: CGFloat),
        threshold: CGFloat = scrollTickThreshold,
        verticalMask: UInt8? = nil,
        horizontalMask: UInt8? = nil
    ) -> [(mask: UInt8, count: Int)] {
        guard threshold > 0 else {
            return []
        }

        var ticks: [(mask: UInt8, count: Int)] = []

        let verticalCount = Int((abs(delta.y) / threshold).rounded(.down))
        if verticalCount > 0 {
            let mask = verticalMask ?? (delta.y >= 0 ? UInt8(0x08) : UInt8(0x10))
            ticks.append((mask: mask, count: verticalCount))
        }

        let horizontalCount = Int((abs(delta.x) / threshold).rounded(.down))
        if horizontalCount > 0 {
            let mask = horizontalMask ?? (delta.x >= 0 ? UInt8(0x40) : UInt8(0x20))
            ticks.append((mask: mask, count: horizontalCount))
        }

        return ticks
    }

    /// Pure aspect-fit math used by `sendTapAt(viewPoint:viewSize:)`.
    /// Public for test access — kept as a static so tests do not have
    /// to construct a full app model just to verify the mapping.
    /// Returns `nil` when the tap falls outside the framebuffer rect
    /// (letterbox/pillarbox) or when any dimension is non-positive.
    /// The resulting `(x, y)` is in framebuffer pixel coordinates,
    /// clamped to the inclusive range `[0, width-1]` / `[0, height-1]`
    /// so a tap exactly on the right/bottom edge of the framebuffer
    /// rect maps to the last valid pixel rather than an out-of-range
    /// `width`/`height` value (which would not fit `UInt16` for very
    /// large framebuffers).
    public static func framebufferCoordinate(
        forViewPoint viewPoint: CGPoint,
        viewSize: CGSize,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> (x: UInt16, y: UInt16)? {
        guard viewSize.width > 0,
              viewSize.height > 0,
              framebufferWidth > 0,
              framebufferHeight > 0
        else {
            return nil
        }

        let viewAspect = viewSize.width / viewSize.height
        let textureAspect = CGFloat(framebufferWidth) / CGFloat(framebufferHeight)

        let fitWidth: CGFloat
        let fitHeight: CGFloat
        if viewAspect > textureAspect {
            fitHeight = viewSize.height
            fitWidth = fitHeight * textureAspect
        } else {
            fitWidth = viewSize.width
            fitHeight = fitWidth / textureAspect
        }

        let originX = (viewSize.width - fitWidth) / 2
        let originY = (viewSize.height - fitHeight) / 2

        let localX = viewPoint.x - originX
        let localY = viewPoint.y - originY

        guard localX >= 0,
              localY >= 0,
              localX <= fitWidth,
              localY <= fitHeight
        else {
            return nil
        }

        let fbX = localX / fitWidth * CGFloat(framebufferWidth)
        let fbY = localY / fitHeight * CGFloat(framebufferHeight)

        let clampedX = max(0, min(CGFloat(framebufferWidth - 1), fbX))
        let clampedY = max(0, min(CGFloat(framebufferHeight - 1), fbY))

        // RFB pointer coordinates fit `UInt16` (RFC 6143 §7.5.5).
        // The clamp above keeps both values in `[0, 65535]` for any
        // framebuffer the protocol can describe (max width/height are
        // themselves `UInt16` in `ServerInit`).
        return (UInt16(clampedX.rounded(.down)), UInt16(clampedY.rounded(.down)))
    }

    public func startPiPWatch(at date: Date = Date()) {
        guard let session else {
            return
        }

        // Already up: entering again is what terminated the app on build 10,
        // and the lifecycle refuses it. Returning here keeps the refusal out
        // of the session's failure message, which "could not be delivered"
        // would misdescribe (spec 032).
        guard !isPiPWatchEngaged else {
            return
        }

        var watchSession = PiPWatchSession(sessionID: session.id)
        watchSession.prepare(
            from: session,
            profileAllowsPiPWatch: selectedProfile?.allowsPiPWatch ?? true,
            at: date
        )

        guard watchSession.state == .preparing else {
            pipWatchSession = watchSession
            return
        }

        guard let latestFramebuffer else {
            watchSession.fail("PiP frame is unavailable.")
            pipWatchSession = watchSession
            return
        }

        guard let pipWatchController else {
            watchSession.fail("PiP renderer is unavailable in this build.")
            pipWatchSession = watchSession
            return
        }

        guard pipWatchController.isSupported, prepareController(pipWatchController) else {
            watchSession.markUnavailable("System PiP is unavailable on this device.")
            pipWatchSession = watchSession
            return
        }

        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        // The framing a single tap gets is whatever the user was looking at
        // (FR-001); a chosen region imposes itself here, before the window
        // opens, because PiP is watch-only and there is no adjusting it after.
        switch appSettings.pipFramingMode {
        case .currentView:
            break
        case .chosenRegion:
            if let pipChosenRegion {
                applyPiPFraming(pipChosenRegion, replaying: latestFramebuffer)
            }
        }
        #endif

        do {
            forwardFrameToLayerHost(latestFramebuffer)
            try pipWatchController.enqueue(
                latestFramebuffer,
                viewport: currentPiPWatchViewport
            )
        } catch {
            watchSession.fail("PiP frame could not be rendered.")
            pipWatchSession = watchSession
            return
        }

        guard pipWatchController.start() else {
            watchSession.fail("PiP start request could not be delivered.")
            pipWatchSession = watchSession
            return
        }

        watchSession.markWatching(
            frame: PiPFrameSnapshot(
                width: latestFramebuffer.width,
                height: latestFramebuffer.height,
                capturedAt: session.lastFrameAt ?? date,
                changeActivity: .moderate
            )
        )
        pipWatchSession = watchSession
    }

    public func stopPiPWatch() {
        guard var pipWatchSession else {
            return
        }

        stopPiPWatchController(reason: .userRequested)
        pipWatchSession.stop()
        self.pipWatchSession = pipWatchSession
    }

    public func refreshPiPWatchStaleness(now: Date = Date()) {
        guard var pipWatchSession else {
            return
        }

        pipWatchSession.refreshStaleness(now: now)
        self.pipWatchSession = pipWatchSession
    }

    private func updatePiPWatchFrameIfNeeded(
        framebuffer: RFBRawFramebuffer,
        sessionID: RemoteSession.ID,
        capturedAt: Date,
        changeActivity: PiPFrameChangeActivity,
        dirtyRectangles: [RFBFrameDamageRect]? = nil
    ) {
        guard var pipWatchSession,
              pipWatchSession.sessionID == sessionID,
              pipWatchSession.state == .watching || pipWatchSession.state == .stale || pipWatchSession.state == .preparing
        else {
            return
        }

        guard let pipWatchController else {
            pipWatchSession.fail("PiP renderer is unavailable in this build.")
            self.pipWatchSession = pipWatchSession
            return
        }

        do {
            forwardFrameToLayerHost(framebuffer)
            try pipWatchController.enqueue(framebuffer, viewport: currentPiPWatchViewport)
        } catch {
            pipWatchSession.fail("PiP frame could not be rendered.")
            self.pipWatchSession = pipWatchSession
            return
        }

        pipWatchSession.markWatching(
            frame: PiPFrameSnapshot(
                width: framebuffer.width,
                height: framebuffer.height,
                capturedAt: capturedAt,
                changeActivity: changeActivity
            )
        )
        self.pipWatchSession = pipWatchSession
    }

    private func clearPiPWatchSession() {
        stopPiPWatchController(reason: .sessionEnded)
        pipWatchSession = nil
        pipChosenRegion = nil
        pipResumesAfterRegionChoice = false
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        pipLayerHost.flush()
        #endif
    }

    /// Streams a freshly arrived framebuffer into the shared
    /// `PiPLayerHost`.  This is the single sink that drives both the
    /// in-app `PiPSampleBufferDisplayLayerView` and any attached system
    /// PiP controller — a render failure is intentionally swallowed
    /// here because failures specific to the active PiP session are
    /// surfaced through `updatePiPWatchFrameIfNeeded`.
    private func forwardFrameToLayerHost(_ framebuffer: RFBRawFramebuffer) {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        do {
            _ = try pipLayerHost.enqueue(framebuffer)
        } catch {
            // The PiP-session bookkeeping will surface a render failure
            // through `updatePiPWatchFrameIfNeeded` when a session is
            // active.  Outside an active session, dropping the frame
            // is acceptable.
        }
        #endif
    }

    /// True while a PiP window is up or coming up, as the *system* sees it.
    /// The published `pipWatchSession` is the app's view; these can disagree
    /// while a transition is in flight, and this is the one that gates entry.
    public var isPiPWatchEngaged: Bool {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        if let reporting = pipWatchController as? any PiPWatchLifecycleReporting {
            return reporting.lifecycle.isEngaged
        }
        #endif
        return pipWatchSession?.state == .watching || pipWatchSession?.state == .stale
    }

    /// Routes to the reason-carrying stop where the controller supports it,
    /// so a session teardown and a user request are distinguishable in the
    /// export (spec 032 FR-006).
    private func stopPiPWatchController(reason: PiPWatchStopReason) {
        guard let pipWatchController else {
            return
        }
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        if let reporting = pipWatchController as? any PiPWatchLifecycleReporting {
            reporting.stop(reason: reason)
            return
        }
        #endif
        pipWatchController.stop()
    }

    /// Applies the framing the current mode asks for, to a PiP session that is
    /// already up. Entry does the same thing through `startPiPWatch`.
    private func applyPiPFramingForActiveWatch() {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        guard isPiPWatchEngaged, let latestFramebuffer else {
            return
        }

        switch appSettings.pipFramingMode {
        case .currentView:
            // The viewport already mirrors the app's; nothing to impose.
            break
        case .chosenRegion:
            if let pipChosenRegion {
                applyPiPFraming(pipChosenRegion, replaying: latestFramebuffer)
            }
        }
        #endif
    }

    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    /// `replaying` re-sends a frame through the new viewport, which is what a
    /// mode or region change needs — a static remote screen would otherwise
    /// keep the old framing until something moved.
    private func applyPiPFraming(
        _ target: PiPFramingTarget,
        replaying framebuffer: RFBRawFramebuffer?
    ) {
        _ = try? pipLayerHost.updateViewport(
            PiPWatchViewport(
                centerX: target.centerX,
                centerY: target.centerY,
                zoomScale: target.zoomScale
            ),
            replaying: framebuffer
        )
    }

    private static func framingTarget(for viewport: PiPWatchViewport) -> PiPFramingTarget {
        PiPFramingTarget(
            centerX: viewport.centerX,
            centerY: viewport.centerY,
            zoomScale: viewport.zoomScale
        )
    }
    #endif

    private var currentPiPWatchViewport: PiPWatchViewport {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        return pipLayerHost.currentViewport
        #else
        return .fullFrame
        #endif
    }

    private func prepareController(_ controller: any PiPWatchControlling) -> Bool {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        observePiPWatchLifecycleIfNeeded(controller)
        if let attaching = controller as? any PiPWatchLayerHostAttaching {
            return attaching.prepare(layerHost: pipLayerHost)
        }
        #endif
        return controller.prepare()
    }

    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    /// Subscribes to the controller's lifecycle once, so the app's PiP state
    /// follows the system's rather than assuming it (spec 032 FR-003).  A
    /// controller that cannot report a lifecycle keeps the previous
    /// behaviour — the same capability-downcast idiom the RFB boundary uses.
    private func observePiPWatchLifecycleIfNeeded(_ controller: any PiPWatchControlling) {
        guard let reporting = controller as? any PiPWatchLifecycleReporting,
              reporting.onLifecycleEvent == nil
        else {
            return
        }
        reporting.onLifecycleEvent = { [weak self] event in
            self?.handlePiPWatchLifecycleEvent(event)
        }
    }

    private func handlePiPWatchLifecycleEvent(_ event: PiPWatchLifecycleEvent) {
        guard var watchSession = pipWatchSession else {
            // A window the app did not ask for — the system started it because
            // the app left the foreground (spec 036 FR-004). Dropping the event
            // here is what would leave it frozen: every frame after this is
            // gated on a `pipWatchSession` existing.
            if case .started = event {
                adoptAutomaticallyStartedPiPWatch()
            }
            return
        }

        switch event {
        case .started:
            guard let frame = watchSession.lastFrame else {
                return
            }
            watchSession.markWatching(frame: frame)
        case .startFailed:
            watchSession.fail("PiP start request could not be delivered.")
        case .stopped:
            // Includes the user closing the floating window from the system
            // chrome, which the app previously never learned about.
            watchSession.stop()
        }

        pipWatchSession = watchSession
    }

    /// Builds the session record for a PiP window the *system* opened
    /// (spec 036 FR-004), so it is a first-class watch session: frames keep
    /// flowing through `updatePiPWatchFrameIfNeeded`, the framing mode applies,
    /// and closing the window from the system chrome still lands on
    /// `PiPWatchSession.stop()`.
    private func adoptAutomaticallyStartedPiPWatch() {
        guard let session, let latestFramebuffer else {
            return
        }

        var watchSession = PiPWatchSession(sessionID: session.id)
        watchSession.prepare(
            from: session,
            profileAllowsPiPWatch: selectedProfile?.allowsPiPWatch ?? true,
            at: Date()
        )
        guard watchSession.state == .preparing else {
            return
        }

        watchSession.markWatching(
            frame: PiPFrameSnapshot(
                width: latestFramebuffer.width,
                height: latestFramebuffer.height,
                capturedAt: session.lastFrameAt ?? Date(),
                changeActivity: .moderate
            )
        )
        pipWatchSession = watchSession

        // Same framing the tapped entry would have taken — automatic entry is
        // not a second, plainer kind of PiP (spec 034 applies as written).
        switch appSettings.pipFramingMode {
        case .currentView:
            break
        case .chosenRegion:
            if let pipChosenRegion {
                applyPiPFraming(pipChosenRegion, replaying: latestFramebuffer)
            }
        }
        forwardFrameToLayerHost(latestFramebuffer)
    }
    #endif
}

private struct ConnectionResult: Sendable {
    let serverInit: RFBServerInit
    let framebuffer: RFBRawFramebuffer?
    let frameCapturedAt: Date
}

private enum AppCredentialError: Error {
    case passwordMissing
}

/// Outcome of one attempt to receive a `ServerCutText` payload from
/// the remote computer.  The receive loop translates throws into
/// these tagged cases so the long-running task does not log raw
/// error strings (constitution §IV: never store user-entered or
/// remote-content-bearing strings in logs by default).
enum IncomingClipboardReceiveResult: Sendable {
    case text(String)
    /// The active client does not support `ServerCutText` — exit
    /// the receive loop entirely.
    case unsupported
    /// A timeout, decode error, or other recoverable failure —
    /// keep the loop alive and try again on the next iteration.
    case transientError
}
