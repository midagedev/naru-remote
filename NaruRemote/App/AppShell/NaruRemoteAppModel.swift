import Combine
import Foundation
import NaruRemoteCore

private struct PendingPointerMove {
    let command: RFBPointerCommand
    let pointerClient: RFBPointerEventClient
    let streamID: UUID?
    let sessionID: RemoteSession.ID?
    let profileID: ConnectionProfile.ID?
}

private struct DeferredViewportInteractionFrame {
    let frame: RFBFramePumpFrame
    let serverInit: RFBServerInit
    let profile: ConnectionProfile
    let sessionID: RemoteSession.ID
    let streamID: UUID
}

struct StreamFrameApplicationWork: Sendable {
    let frame: RFBFramePumpFrame
    let serverInit: RFBServerInit
    let profile: ConnectionProfile
    let sessionID: RemoteSession.ID
    let streamID: UUID
    let isEmptyUpdate: Bool
}

struct SessionFrameApplicationWorkerPacing: Equatable, Sendable {
    static let defaultContentFrameMinimumInterval: TimeInterval = 1.0 / 60.0

    var contentFrameMinimumInterval: TimeInterval = Self.defaultContentFrameMinimumInterval

    func delay(
        before work: StreamFrameApplicationWork,
        lastContentFrameAppliedAt: Date?,
        now: Date
    ) -> TimeInterval {
        guard !work.isEmptyUpdate else {
            return 0
        }
        guard let lastContentFrameAppliedAt else {
            return 0
        }
        return max(contentFrameMinimumInterval - now.timeIntervalSince(lastContentFrameAppliedAt), 0)
    }
}

actor SessionStreamFrameApplicationQueue {
    static let maximumPendingWorkCount = 3

    private var pending: [StreamFrameApplicationWork] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isClosed = false

    @discardableResult
    func enqueue(_ work: StreamFrameApplicationWork) -> Int {
        guard !isClosed else {
            return 0
        }
        pending.append(work)
        let droppedCount = coalescePending()
        resumePendingWaiters()
        return droppedCount
    }

    func next(preferControlUpdates: Bool = false) async -> StreamFrameApplicationWork? {
        while true {
            guard pending.isEmpty else {
                if preferControlUpdates,
                   let controlUpdateIndex = pending.firstIndex(where: \.isEmptyUpdate)
                {
                    return pending.remove(at: controlUpdateIndex)
                }
                return pending.removeFirst()
            }
            guard !isClosed else {
                return nil
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func pendingCount() -> Int {
        pending.count
    }

    func close() {
        isClosed = true
        resumePendingWaiters()
    }

    private func resumePendingWaiters() {
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    private func coalescePending() -> Int {
        guard pending.count > 1 else {
            return 0
        }

        let originalCount = pending.count
        let initialContentIndex = pending.indices.first {
            !pending[$0].frame.isIncremental && !pending[$0].isEmptyUpdate
        }
        let latestContentIndex = pending.indices.last {
            !pending[$0].isEmptyUpdate
        }
        let latestCursorIndex = pending.indices.last {
            pending[$0].isEmptyUpdate && pending[$0].frame.serverCursor != nil
        }
        let latestLivenessIndex = pending.indices.last {
            pending[$0].isEmptyUpdate && pending[$0].frame.serverCursor == nil
        }

        var retainedIndexes = Set<Int>()
        if let initialContentIndex {
            retainedIndexes.insert(initialContentIndex)
        }
        if let latestContentIndex {
            retainedIndexes.insert(latestContentIndex)
        }
        if let latestCursorIndex {
            retainedIndexes.insert(latestCursorIndex)
        }
        if retainedIndexes.isEmpty, let latestLivenessIndex {
            retainedIndexes.insert(latestLivenessIndex)
        }
        if retainedIndexes.isEmpty, let lastIndex = pending.indices.last {
            retainedIndexes.insert(lastIndex)
        }

        pending = pending.enumerated()
            .compactMap { retainedIndexes.contains($0.offset) ? $0.element : nil }
        if pending.count > Self.maximumPendingWorkCount {
            pending = Array(pending.suffix(Self.maximumPendingWorkCount))
        }
        return originalCount - pending.count
    }
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

private enum OutboundInputEventError: Error {
    case timedOut
}

private final class OutboundInputEventOperationRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var tasks: [Task<Void, Never>] = []
    private var isFinished = false

    func setContinuation(_ continuation: CheckedContinuation<Void, any Error>) {
        var shouldResume = false
        lock.lock()
        if isFinished {
            shouldResume = true
        } else {
            self.continuation = continuation
        }
        lock.unlock()

        if shouldResume {
            continuation.resume(throwing: CancellationError())
        }
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        var tasksToCancel: [Task<Void, Never>] = []
        lock.lock()
        if isFinished {
            tasksToCancel = tasks
        } else {
            self.tasks = tasks
        }
        lock.unlock()

        for task in tasksToCancel {
            task.cancel()
        }
    }

    func finish(_ result: Result<Void, any Error>) {
        let continuationToResume: CheckedContinuation<Void, any Error>?
        let tasksToCancel: [Task<Void, Never>]

        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        continuationToResume = continuation
        continuation = nil
        tasksToCancel = tasks
        tasks = []
        lock.unlock()

        for task in tasksToCancel {
            task.cancel()
        }
        continuationToResume?.resume(with: result)
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }
}

private final class OutboundInputEventDispatcher: @unchecked Sendable {
    typealias Operation = @Sendable () async throws -> Void
    typealias Validator = @Sendable () async -> Bool
    typealias Recorder = @Sendable (
        _ queueDelayMilliseconds: Int,
        _ operationMilliseconds: Int,
        _ timedOut: Bool
    ) async -> Void

    private let lock = NSLock()
    private let timeout: Duration
    private var generation = UUID()
    private var tail: Task<Void, Never>?

    init(timeout: Duration) {
        self.timeout = timeout
    }

    func cancelAll() {
        let taskToCancel: Task<Void, Never>?
        lock.lock()
        generation = UUID()
        taskToCancel = tail
        tail = nil
        lock.unlock()

        taskToCancel?.cancel()
    }

    func enqueue(
        operation: @escaping Operation,
        validate: @escaping Validator,
        record: @escaping Recorder,
        handleFailure: @escaping Recorder
    ) {
        let enqueuedAt = Date()
        let previous: Task<Void, Never>?
        let eventGeneration: UUID

        lock.lock()
        previous = tail
        eventGeneration = generation
        lock.unlock()

        let task = Task.detached(priority: .userInitiated) { [
            weak self,
            previous,
            enqueuedAt,
            eventGeneration,
            operation,
            validate,
            record,
            handleFailure
        ] in
            await previous?.value
            guard let self,
                  !Task.isCancelled,
                  self.isCurrent(eventGeneration),
                  await validate()
            else {
                return
            }

            let queueDelayMilliseconds = Self.elapsedMilliseconds(since: enqueuedAt)
            let operationStartedAt = Date()
            do {
                try await Self.runOperation(timeout: self.timeout, operation: operation)
                let operationMilliseconds = Self.elapsedMilliseconds(since: operationStartedAt)
                guard self.isCurrent(eventGeneration) else {
                    return
                }
                await record(queueDelayMilliseconds, operationMilliseconds, false)
            } catch {
                let operationMilliseconds = Self.elapsedMilliseconds(since: operationStartedAt)
                let timedOut: Bool
                if case OutboundInputEventError.timedOut = error {
                    timedOut = true
                } else {
                    timedOut = false
                }
                guard self.invalidateIfCurrent(eventGeneration) else {
                    return
                }
                await handleFailure(queueDelayMilliseconds, operationMilliseconds, timedOut)
            }
        }

        let shouldCancelTask: Bool
        lock.lock()
        if generation == eventGeneration {
            tail = task
            shouldCancelTask = false
        } else {
            shouldCancelTask = true
        }
        lock.unlock()

        if shouldCancelTask {
            task.cancel()
        }
    }

    private func isCurrent(_ eventGeneration: UUID) -> Bool {
        let current: Bool
        lock.lock()
        current = generation == eventGeneration
        lock.unlock()
        return current
    }

    private func invalidateIfCurrent(_ eventGeneration: UUID) -> Bool {
        let taskToCancel: Task<Void, Never>?
        lock.lock()
        guard generation == eventGeneration else {
            lock.unlock()
            return false
        }
        generation = UUID()
        taskToCancel = tail
        tail = nil
        lock.unlock()

        taskToCancel?.cancel()
        return true
    }

    private static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(start) * 1000).rounded()))
    }

    private static func runOperation(
        timeout: Duration,
        operation: @escaping Operation
    ) async throws {
        let race = OutboundInputEventOperationRace()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.setContinuation(continuation)
                let operationTask = Task.detached(priority: .userInitiated) {
                    do {
                        try await operation()
                        race.finish(.success(()))
                    } catch {
                        race.finish(.failure(error))
                    }
                }
                let timeoutTask = Task.detached(priority: .userInitiated) {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    operationTask.cancel()
                    race.finish(.failure(OutboundInputEventError.timedOut))
                }
                race.setTasks([operationTask, timeoutTask])
            }
        } onCancel: {
            race.cancel()
        }
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
    public typealias HelperVideoRendererFactory = @MainActor @Sendable () -> any HelperVideoAccessUnitRendering

    /// macOS Screen Sharing and other VNC servers apply ClientCutText
    /// asynchronously from key events. Keep the Send button responsive,
    /// but give the remote clipboard enough time to adopt the payload
    /// before the paste shortcut arrives.
    private static let remoteClipboardPasteSettleDelay: TimeInterval = 0.30
    @Published public private(set) var profiles: [ConnectionProfile]
    @Published public var selectedProfileID: ConnectionProfile.ID?
    @Published public private(set) var session: RemoteSession?
    @Published public private(set) var diagnosticRun: ConnectionDiagnosticRun?
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
    /// `idle | armed | locked` per `StickyModifierState`.
    /// Resets in lockstep with `directKeystrokeMode` — disconnect,
    /// fresh connect, profile change, and `toggleDirectKeystrokeMode`
    /// off all clear the state (FR-012).
    @Published public private(set) var stickyModifierState: StickyModifierState = .init()

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
    private var profilePreviewStore: (any ProfilePreviewStore)?
    private let credentialStore: ConnectionCredentialStoreProtocol?
    private let settingsPersistence: AppSettingsPersisting?
    private let pipWatchController: (any PiPWatchControlling)?
    private let localClipboardWriter: (any LocalClipboardWriting)?
    private let helperTextInsertClient: (any HelperTextInsertClient)?
    private let helperVideoStartStream: HelperVideoStartStream?
    private let helperVideoRendererFactory: HelperVideoRendererFactory?
    private let streamStartupPreflightPolicyOverride: SessionStreamStartupPreflightPolicy?
    private let incomingClipboardReceiveTimeout: TimeInterval
    private let thermalStateProvider: @Sendable () -> SessionStreamThermalState
    private let lowPowerModeProvider: @Sendable () -> Bool
    /// Test seam for observing app-level pacing decisions without
    /// sleeping in real time. `nil` keeps production cancellation on
    /// the direct `Task.sleep` path.
    private let streamPacingSleepOverride: (@Sendable (TimeInterval) async throws -> Void)?
    private let allowsAdaptiveEncodingRenegotiation: Bool
    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    public let pipLayerHost: PiPLayerHost
    #endif
    private var activeTextClient: RemoteClipboardTextClient?
    private var activePointerClient: RFBPointerEventClient?
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
    private static let trackpadPointerMoveCoalescingDelay: Duration = .milliseconds(8)
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
    private static let mainActorResponsivenessProbeInterval: Duration = .milliseconds(250)
    private static let mainActorResponsivenessProbeIntervalSeconds: TimeInterval = 0.25
    public static let defaultActiveFrameInterval: TimeInterval =
        StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds
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
        updateMode: .continuousUpdates
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
        helperVideoRendererFactory: HelperVideoRendererFactory? = nil,
        streamStartupPreflightPolicy: SessionStreamStartupPreflightPolicy? = nil,
        incomingClipboardReceiveTimeout: TimeInterval = 30,
        thermalStateProvider: @escaping @Sendable () -> SessionStreamThermalState = {
            SessionStreamThermalState(ProcessInfo.processInfo.thermalState)
        },
        lowPowerModeProvider: @escaping @Sendable () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        },
        streamPacingSleep: (@Sendable (TimeInterval) async throws -> Void)? = nil,
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
        self.latestFrameDirtyRectangles = snapshot.latestFrameDirtyRectangles
        self.latestFrameChangedPixelCount = snapshot.latestFrameChangedPixelCount
        self.sessionStreamStats = snapshot.sessionStreamStats
        self.latestServerCursor = snapshot.latestServerCursor
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
        self.reachabilityProbeTimeout = reachabilityProbeTimeout
        self.reachabilityProbeMaximumConcurrency = max(1, reachabilityProbeMaximumConcurrency)
        self.pipWatchController = pipWatchController
        self.localClipboardWriter = localClipboardWriter
        self.helperTextInsertClient = helperTextInsertClient
        self.helperVideoStartStream = helperVideoStartStream ?? Self.defaultHelperVideoStartStream()
        self.helperVideoRendererFactory = helperVideoRendererFactory ?? Self.defaultHelperVideoRendererFactory()
        self.streamStartupPreflightPolicyOverride = streamStartupPreflightPolicy
        self.incomingClipboardReceiveTimeout = incomingClipboardReceiveTimeout
        self.thermalStateProvider = thermalStateProvider
        self.lowPowerModeProvider = lowPowerModeProvider
        self.streamPacingSleepOverride = streamPacingSleep
        self.pointerInputDispatcher = OutboundInputEventDispatcher(
            timeout: outboundInputEventTimeout
        )
        self.keyInputDispatcher = OutboundInputEventDispatcher(
            timeout: outboundInputEventTimeout
        )
        self.allowsAdaptiveEncodingRenegotiation = allowsAdaptiveEncodingRenegotiation
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        self.pipLayerHost = PiPLayerHost()
        #endif
    }

    private static func defaultHelperVideoStartStream() -> HelperVideoStartStream? {
        #if canImport(Network)
        return { profile, pairingSecret, pairingFingerprint, requestBody, maxServerFrames in
            let client = HelperVideoStreamNetworkClient(
                host: profile.host,
                port: UInt16(naruHelperVideoStreamDefaultPort),
                profileFingerprint: pairingFingerprint,
                pairingSecret: pairingSecret
            )
            return try await client.startStream(requestBody, maxServerFrames: maxServerFrames)
        }
        #else
        return nil
        #endif
    }

    private static func defaultHelperVideoRendererFactory() -> HelperVideoRendererFactory? {
        #if canImport(AVFoundation) && canImport(CoreMedia)
        return {
            HelperVideoH264SampleBufferRenderer()
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
            stickyModifierState: stickyModifierState,
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
        guard activeSession.state == .active else {
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
        helperVideoStreamHealth = health
        guard health.shouldUseVNCVisualFallback else {
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
        if let sessionID, session?.id != sessionID {
            return false
        }
        if let profileID {
            guard session?.profileID == profileID,
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
        snapshot.isPiPWatchAvailable && (pipWatchController?.isSupported ?? false)
    }

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
            stopHelperVideoStreamBootstrap()
            stopFrameStream()
            stopIncomingClipboardReceive()
            pendingIncomingClipboard = nil
            activeTextClient = nil
            activePointerClient = nil
            activeKeyEventClient = nil
            keystrokeEmitter = nil
            directKeystrokeMode = .init()
            stickyModifierState = .init()
            resetPointerControl()
            lastEmittedDragCoord = nil
            activeStreamProfile = nil
            activeStreamCredential = nil
            reconnectAttempts = 0
            resetConnectionQuality()
            latestViewportTransform = nil
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

    public func addProfile(
        _ profile: ConnectionProfile,
        password: String? = nil,
        helperPairingSecret: String? = nil
    ) async {
        profilePersistenceError = nil
        var profileToSave = profile
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedPassword, !trimmedPassword.isEmpty {
            guard let credentialStore else {
                profilePersistenceError = "Password could not be saved on this device."
                return
            }

            let credentialRef = profileToSave.credentialRef ?? Self.credentialReference(for: profileToSave.id)
            do {
                try await credentialStore.savePassword(trimmedPassword, for: credentialRef)
                profileToSave.credentialRef = credentialRef
            } catch {
                profilePersistenceError = "Password could not be saved on this device."
                return
            }
        }

        guard await applyHelperPairingSecretUpdate(
            helperPairingSecret,
            to: &profileToSave,
            existingProfile: nil
        ) else {
            return
        }

        if let index = profiles.firstIndex(where: { $0.id == profileToSave.id }) {
            profiles[index] = profileToSave
        } else {
            profiles.append(profileToSave)
        }
        publishInitialHelperTextBridgeState(for: profileToSave)
        publishInitialHelperVideoState(for: profileToSave)

        do {
            try await profileStore?.save(profileToSave)
        } catch {
            profilePersistenceError = "Profile could not be saved on this device."
        }
        refreshProfileReachability()

        selectedProfileID = profileToSave.id
        if session == nil || session?.profileID != profileToSave.id {
            cancelPendingReconnect()
            stopFrameStream()
            stopIncomingClipboardReceive()
            pendingIncomingClipboard = nil
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
            activeKeyEventClient = nil
            keystrokeEmitter = nil
            directKeystrokeMode = .init()
            stickyModifierState = .init()
            resetPointerControl()
            lastEmittedDragCoord = nil
            activeStreamProfile = nil
            activeStreamCredential = nil
            reconnectAttempts = 0
        }
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
    public func editProfile(
        _ profile: ConnectionProfile,
        password: String?,
        helperPairingSecret: String? = nil
    ) async {
        profilePersistenceError = nil

        guard let existingProfile = profiles.first(where: { $0.id == profile.id }) else {
            return
        }

        var profileToSave = profile
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
                if let existingRef = profileToSave.credentialRef {
                    do {
                        try await credentialStore?.deletePassword(for: existingRef)
                    } catch {
                        profilePersistenceError = "Password could not be removed on this device."
                        return
                    }
                }
                profileToSave.credentialRef = nil
            } else {
                guard let credentialStore else {
                    profilePersistenceError = "Password could not be saved on this device."
                    return
                }

                let credentialRef = profileToSave.credentialRef ?? Self.credentialReference(for: profileToSave.id)
                do {
                    try await credentialStore.savePassword(trimmedPassword, for: credentialRef)
                    profileToSave.credentialRef = credentialRef
                } catch {
                    profilePersistenceError = "Password could not be saved on this device."
                    return
                }
            }
        }

        guard await applyHelperPairingSecretUpdate(
            helperPairingSecret,
            to: &profileToSave,
            existingProfile: existingProfile
        ) else {
            return
        }

        if let index = profiles.firstIndex(where: { $0.id == profileToSave.id }) {
            profiles[index] = profileToSave
        }
        publishInitialHelperTextBridgeState(for: profileToSave)
        publishInitialHelperVideoState(for: profileToSave)

        do {
            try await profileStore?.save(profileToSave)
        } catch {
            profilePersistenceError = "Profile could not be saved on this device."
        }
        refreshProfileReachability()
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
        guard let helperVideoStartStream else {
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
        activeHelperVideoStreamTask = Task.detached(priority: .userInitiated) { [weak self, credentialStore, profile, secretRef, pairingFingerprint, sessionID, bootstrapID, helperVideoStartStream, helperVideoRendererFactory] in
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
        startStream: @escaping HelperVideoStartStream,
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
        let runner = HelperVideoStreamSessionRunner(
            startStream: { requestBody, maxServerFrames in
                try await startStream(
                    profile,
                    pairingSecret,
                    pairingFingerprint,
                    requestBody,
                    maxServerFrames
                )
            },
            renderer: rendererFactory()
        )
        _ = await runner.start(sessionID: sessionID, profileID: profile.id, model: self)
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
        case .transportFailed:
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
        existingProfile: ConnectionProfile?
    ) async -> Bool {
        guard let helperPairingSecret else {
            return true
        }

        let trimmedSecret = helperPairingSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingRef = existingProfile?.helperTextBridge?.pairingSecretRef

        guard !trimmedSecret.isEmpty else {
            if let existingRef {
                do {
                    try await credentialStore?.deletePassword(for: existingRef)
                } catch {
                    profilePersistenceError = "Helper token could not be removed on this device."
                    return false
                }
            }
            return true
        }

        guard let credentialStore else {
            profilePersistenceError = "Helper token could not be saved on this device."
            return false
        }
        guard var configuration = profile.helperTextBridge else {
            profilePersistenceError = "Helper token could not be saved on this device."
            return false
        }

        let secretRef = configuration.pairingSecretRef
            ?? Self.helperPairingSecretReference(for: profile.id)
        do {
            try await credentialStore.savePassword(trimmedSecret, for: secretRef)
            if let existingRef, existingRef != secretRef {
                try await credentialStore.deletePassword(for: existingRef)
            }
        } catch {
            profilePersistenceError = "Helper token could not be saved on this device."
            return false
        }

        configuration.pairingSecretRef = secretRef
        profile.helperTextBridge = configuration
        return true
    }

    /// Remove a saved profile from the store.  Best-effort cleans up
    /// the keychain credential too — keychain delete-of-missing is
    /// treated as success so a profile that was never given a
    /// password still deletes cleanly.
    ///
    /// If the deleted profile was the active one, the session,
    /// frame stream, incoming-clipboard review, diagnostics, and
    /// PiP watch state are all torn down and `selectedProfileID` is
    /// cleared so no stale UI references the missing profile.
    public func deleteProfile(id: ConnectionProfile.ID) async {
        profilePersistenceError = nil

        guard let removedProfile = profiles.first(where: { $0.id == id }) else {
            return
        }

        let wasActive = selectedProfileID == id || session?.profileID == id

        profiles.removeAll { $0.id == id }
        // Drop any cached verdict for the deleted profile so the
        // sidebar dot doesn't outlive the row (UX punch-list #109).
        lastDiagnosticVerdict.removeValue(forKey: id)
        profilePreviews.removeValue(forKey: id)
        lastPreviewPublishAt.removeValue(forKey: id)
        lastPreviewSaveAt.removeValue(forKey: id)
        profileReachability.removeValue(forKey: id)

        if let credentialRef = removedProfile.credentialRef {
            do {
                try await credentialStore?.deletePassword(for: credentialRef)
            } catch {
                // The profile is already gone from the in-memory
                // list and the disk store; surface a non-fatal
                // error rather than aborting the whole delete and
                // leaving the user with a half-deleted profile.
                profilePersistenceError = "Saved password could not be removed on this device."
            }
        }

        if let helperSecretRef = removedProfile.helperTextBridge?.pairingSecretRef {
            do {
                try await credentialStore?.deletePassword(for: helperSecretRef)
            } catch {
                profilePersistenceError = "Helper token could not be removed on this device."
            }
        }
        if let helperVideoSecretRef = removedProfile.helperVideo?.pairingSecretRef {
            do {
                try await credentialStore?.deletePassword(for: helperVideoSecretRef)
            } catch {
                profilePersistenceError = "Helper video token could not be removed on this device."
            }
        }
        helperTextBridgeState.removeValue(forKey: id)
        helperVideoProfileState.removeValue(forKey: id)

        do {
            _ = try await profileStore?.deleteProfile(id: id)
        } catch {
            profilePersistenceError = "Profile could not be removed on this device."
        }

        do {
            try await profilePreviewStore?.deleteThumbnail(for: id)
        } catch {
            // Preview deletion is best-effort local cleanup. The
            // profile itself is already gone and the in-memory
            // thumbnail cache was cleared above.
        }

        if wasActive {
            cancelPendingReconnect()
            stopHelperVideoStreamBootstrap()
            stopFrameStream()
            stopIncomingClipboardReceive()
            pendingIncomingClipboard = nil
            activeTextClient = nil
            activePointerClient = nil
            activeKeyEventClient = nil
            keystrokeEmitter = nil
            directKeystrokeMode = .init()
            stickyModifierState = .init()
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
            helperTextBridgeState: helperTextBridgeState(for: composeRoute.helperProfileID)
        )
        let sustainedSessionAssessment = DiagnosticSustainedSessionAssessment.assess(
            streamPerformance: streamPerformance,
            input: input,
            contentFramesPerSecond: sessionStreamStats.contentFramesPerSecond
        )
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
                sustainedSessionAssessment: sustainedSessionAssessment
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
            sustainedSessionAssessment: sustainedSessionAssessment
        )
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
             .malformedExtendedServerCutText:
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
        guard ProcessInfo.processInfo.environment["NARU_TEST_LOG_DIAGNOSTIC_EXPORT"] == "1",
              run?.finishedAt != nil
        else {
            return
        }

        emitDiagnosticExportForTesting(buildVersion: "test-device")
    }

    public func emitDiagnosticExportForTesting(buildVersion: String?) {
        guard ProcessInfo.processInfo.environment["NARU_TEST_LOG_DIAGNOSTIC_EXPORT"] == "1" else {
            return
        }

        let payload = makeDiagnosticExport().renderCollectionJSON(
            buildVersion: buildVersion ?? "test-device",
            now: Date()
        )
        print("NARU_DIAGNOSTIC_EXPORT_BEGIN")
        print(payload)
        print("NARU_DIAGNOSTIC_EXPORT_END")
    }

    private func scheduleActiveDiagnosticExportForTestingIfRequested() {
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
    }

    private static func testSkipsSettingsStoreLoad() -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_SKIP_SETTINGS_STORE_LOAD"],
              !raw.isEmpty
        else { return false }
        return raw != "0" && raw.lowercased() != "false"
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

    public func connectSelectedProfile() async {
        guard let profile = selectedProfile else {
            return
        }

        // Fresh user-initiated connect attempt: clear any pending
        // auto-reconnect, drop the explicit-disconnect latch, and
        // reset the bounded attempt counter so a future drop gets a
        // fresh `maxAttempts` budget.
        cancelPendingReconnect()
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
            nextSession.markFailed("Credential unavailable")
            session = nextSession
            activeTextClient = nil
            activePointerClient = nil
            activeKeyEventClient = nil
            keystrokeEmitter = nil
            directKeystrokeMode = .init()
            stickyModifierState = .init()
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

        let initialEncodingPreference = initialStreamEncodingPreference()
        let initialPixelFormatPreference = initialStreamPixelFormatPreference()
        let connector = streamConnectorFactory(
            initialEncodingPreference,
            initialPixelFormatPreference
        )
        stopFrameStream()
        stopIncomingClipboardReceive()
        pendingIncomingClipboard = nil
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
                let keyEventClient = connector as? (any RFBKeyEventClient)
                activeKeyEventClient = keyEventClient
                keystrokeEmitter = keyEventClient.map { KeystrokeEmitter(client: $0) }
                lastEmittedDragCoord = nil
                if textClient != nil {
                    startIncomingClipboardReceive(receive: Self.makeReceive(connector: connector))
                }
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
                startHelperVideoStreamIfConfigured(profile: profile, sessionID: nextSession.id)
            } catch {
                activeTextClient = nil
                activePointerClient = nil
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

                await self.bindActiveStreamingClients(streamingClient)
                if shouldRenegotiateConfiguredSustainedEncodings {
                    await self.renegotiateConfiguredSustainedEncodingsIfNeeded(
                        transportControl: streamingClient as? any RFBTransportControlClient,
                        requestTimeout: configuration.requestTimeout
                    )
                }
                // Constitution §I: outgoing compose-and-send is the
                // primary text path; incoming server clipboard is
                // secondary.  Disabled until the RFB reader is
                // refactored into a single multiplexer that dispatches
                // by msg_type — running `receiveServerCutText` (issues
                // its own `readExactly(8)`) concurrently with the
                // frame pump's `requestFramebufferUpdate` made the two
                // tasks race on the same NWConnection, splitting the
                // FBUpdate header (`00 00 00 01 00 00 00 00`) into the
                // clipboard reader's buffer and surfacing as
                // `unexpectedMessageType(11)` from `parseFramebufferUpdateHeader`.
                // See task #30.

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
                    let initialRequestRegion = isIncrementalRequest
                        ? nil
                        : await self.currentViewportInitialRequestRegion(serverInit: serverInit)
                    let maybeFrame = try pump.nextFrame(
                        requestTimeout: requestTimeout,
                        updateMode: configuration.updateMode,
                        requestRegion: requestRegion,
                        initialRequestRegion: initialRequestRegion
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
                    let pacingDecision = await self.recordSessionStreamStatsAndPacingDecision(
                        for: frame,
                        configuration: configuration,
                        thermalState: thermalState,
                        usesAdaptiveClientPressurePacing: usesAdaptiveClientPressurePacing,
                        appFrameApplyMilliseconds: nil,
                        isEmptyUpdate: isEmptyUpdate,
                        emptyUpdateStreak: emptyUpdateStreak
                    )
                    let pacingDelay = pacingDecision.delay
                    if pacingDelay > 0 {
                        if let streamPacingSleepOverride = await self.currentStreamPacingSleepOverride() {
                            try await streamPacingSleepOverride(pacingDelay)
                        } else {
                            try await Task.sleep(for: .seconds(pacingDelay))
                        }
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

    private func bindActiveStreamingClients(_ streamingClient: any RFBStreamingClient) {
        activeTextClient = streamingClient
        activePointerClient = streamingClient
        activeKeyEventClient = streamingClient
        keystrokeEmitter = KeystrokeEmitter(client: streamingClient)
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
        let probeInterval = Self.mainActorResponsivenessProbeInterval
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
                    milliseconds: Self.elapsedMilliseconds(since: expectedWakeAt)
                )
            }
        }
    }

    private func stopMainActorResponsivenessMonitor() {
        mainActorResponsivenessTask?.cancel()
        mainActorResponsivenessTask = nil
        mainActorResponsivenessMonitorID = nil
    }

    private func currentStreamPacingSleepOverride() -> (@Sendable (TimeInterval) async throws -> Void)? {
        streamPacingSleepOverride
    }

    private func publishSessionFrame(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]?,
        changedPixelCount: Int?,
        serverCursor: RFBServerCursor?
    ) {
        latestFramebuffer = framebuffer
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
        latestFrameDirtyRectangles = nil
        latestFrameChangedPixelCount = nil
        latestServerCursor = nil
        frameStore.clear()
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
        let usesViewportInteractionPacing = isViewportInteractionActive
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
                usesViewportInteractionPacing: usesViewportInteractionPacing,
                emptyUpdateStreak: emptyUpdateStreak
            )
            : SessionStreamPacingPolicy.decision(
                for: .contentFrame,
                configuredDelay: configuration.frameInterval,
                thermalState: thermalState,
                usesPowerSaverPacing: usesPowerSaverPacing,
                usesViewportInteractionPacing: usesViewportInteractionPacing,
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

    private nonisolated static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(start) * 1000).rounded()))
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

    public func recordViewportRedrawDiagnostics(_ diagnostics: ViewportRedrawDiagnostics) {
        sessionStreamStats.recordViewportRedrawDiagnostics(diagnostics)
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
            return
        }
        viewportInteractionFrameStrategy = nil
        viewportInteractionStartedAt = nil
        lastViewportInteractionFramePublishedAt = nil
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

    private func currentViewportRequestRegion(
        incrementalRequestIndex: Int
    ) -> RFBFramebufferUpdateRegion? {
        guard usesViewportAwareRequestRegions else {
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

    private var usesViewportAwareRequestRegions: Bool {
        guard appSettings.streamPowerMode != .powerSaver,
              !lowPowerModeProvider()
        else {
            return false
        }
        switch appSettings.streamEncodingMode {
        case .localLowLatencyRGB565, .zrleCompressionZeroRGB565:
            return true
        case .standard, .tightFirstCursor, .zrleCompressionZero, .adaptiveGoodFull:
            return false
        }
    }

    private var usesViewportAwareInitialRequestRegion: Bool {
        usesViewportAwareRequestRegions
    }

    private func startFrameApplicationWorker(_ queue: SessionStreamFrameApplicationQueue) {
        activeFrameApplicationTask?.cancel()
        let workerPacing = SessionFrameApplicationWorkerPacing()
        activeFrameApplicationTask = Task.detached(priority: .userInitiated) { [weak self, queue] in
            var lastContentFrameAppliedAt: Date?
            while !Task.isCancelled,
                  let work = await queue.next(preferControlUpdates: lastContentFrameAppliedAt != nil)
            {
                let pacingDelay = workerPacing.delay(
                    before: work,
                    lastContentFrameAppliedAt: lastContentFrameAppliedAt,
                    now: Date()
                )
                if pacingDelay > 0 {
                    try? await Task.sleep(for: .seconds(pacingDelay))
                    if Task.isCancelled {
                        return
                    }
                }
                await self?.applyStreamFrameApplication(work)
                if !work.isEmptyUpdate {
                    lastContentFrameAppliedAt = Date()
                }
                await Task.yield()
            }
        }
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
        recordAppFrameApplyTiming(milliseconds: Self.elapsedMilliseconds(since: appFrameApplyStart))
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
            }
            activeSession = updatedSession
        } else {
            var updatedSession = RemoteSession(profileID: profile.id)
            updatedSession.markFirstFrameReceived(at: frame.capturedAt)
            session = updatedSession
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
            changeActivity: frame.changeActivity
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
            startHelperVideoStreamIfConfigured(profile: profile, sessionID: activeSession.id)
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
        if connectionQuality != bucket {
            connectionQuality = bucket
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
        if appSettings.streamPowerMode == .powerSaver || lowPowerModeProvider() {
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
              !lowPowerModeProvider()
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
        connectionQuality = .unknown
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
        connectionQuality = quality
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
        activeKeyEventClient = nil
        keystrokeEmitter = nil
        directKeystrokeMode = .init()
        stickyModifierState = .init()
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
        stopHelperVideoStreamBootstrap()
        stopFrameStream()
        stopIncomingClipboardReceive()
        pendingIncomingClipboard = nil
        activeTextClient = nil
        activePointerClient = nil
        activeKeyEventClient = nil
        keystrokeEmitter = nil
        directKeystrokeMode = .init()
        stickyModifierState = .init()
        lastEmittedDragCoord = nil
        activeStreamProfile = nil
        activeStreamCredential = nil
        reconnectAttempts = 0
        latestViewportTransform = nil
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
        pointerInputDispatcher.cancelAll()
        keyInputDispatcher.cancelAll()
    }

    private func cancelPointerInputEventQueue() {
        pointerMoveFlushTask?.cancel()
        pointerMoveFlushTask = nil
        pendingPointerMove = nil
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
    public func recordIncomingClipboard(_ text: String, at date: Date = Date()) {
        guard !text.isEmpty else {
            return
        }
        // REPLACE policy: a newer arrival supersedes a still-pending
        // older review.  See `startIncomingClipboardReceive` for
        // rationale.
        pendingIncomingClipboard = IncomingClipboardReview(text: text, arrivedAt: date)
    }

    /// User reviewed the preview and accepted the remote copy.
    /// Writes the *full* text through the injected
    /// `LocalClipboardWriting` boundary and clears the review.
    public func acceptIncomingClipboard() {
        guard let review = pendingIncomingClipboard else {
            return
        }
        localClipboardWriter?.write(review.text)
        pendingIncomingClipboard = nil
    }

    /// User dismissed the review.  Nothing is written to the local
    /// pasteboard.  The full `text` is dropped on the floor.
    public func dismissIncomingClipboard() {
        pendingIncomingClipboard = nil
    }

    // MARK: - Pointer control mode

    /// Current framebuffer size in pixels, or a sensible default when
    /// no frame has arrived yet.  Used to center the trackpad cursor on a
    /// mode switch and to clamp relative cursor moves.
    private var currentFramebufferSize: CGSize {
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
    /// framebuffer or pointer client.  Viewport auto-pan remains LOCAL
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

        guard !outcome.commands.isEmpty,
              let pointerClient = activePointerClient
        else {
            return result
        }

        let streamID = activeFrameStreamID
        let sessionID = session.id
        let profileID = selectedProfileID
        if case .dragChanged(_, _) = gesture,
           let command = Self.singleButtonlessPointerMove(outcome.commands) {
            enqueueCoalescedPointerMove(
                command,
                pointerClient: pointerClient,
                streamID: streamID,
                sessionID: sessionID,
                profileID: profileID,
                coalescingDelay: Self.trackpadPointerMoveCoalescingDelay
            )
            return result
        }

        flushPendingPointerMove()
        enqueuePointerCommands(
            outcome.commands,
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )
        return result
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
        directKeystrokeMode = DirectKeystrokeMode(
            isActive: newActive,
            page: .qwerty,
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
            hasShownEntryWarningThisSession: true
        )
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
    ///   `StickyModifierState` state machine.  No `KeyEvent` is
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
            let modifiers = stickyModifierState.activeModifiers
            enqueueKeyEventEmission(
                emitter: emitter,
                streamID: activeFrameStreamID,
                sessionID: session?.id,
                profileID: selectedProfileID
            ) {
                try await emitter.emit(keysym: keysym, modifiers: modifiers)
            }
            stickyModifierState.consumeAfterNonModifierEmission()

        case .named(let namedKey):
            guard directKeystrokeMode.isActive,
                  let emitter = keystrokeEmitter
            else {
                return
            }
            let keysym = KeysymMapping.keysym(for: namedKey)
            let modifiers = stickyModifierState.activeModifiers
            enqueueKeyEventEmission(
                emitter: emitter,
                streamID: activeFrameStreamID,
                sessionID: session?.id,
                profileID: selectedProfileID
            ) {
                try await emitter.emit(keysym: keysym, modifiers: modifiers)
            }
            stickyModifierState.consumeAfterNonModifierEmission()
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
    /// `StickyModifierState[.control] == .armed` (SC-005).
    ///
    /// Drops silently when:
    /// - Direct mode is not active (FR-007 — hardware path only
    ///   fires when the user has opted into Direct mode).
    /// - There is no active session (`keystrokeEmitter` is `nil`
    ///   outside an active stream — `spec.md` IN-003 fallback).
    ///
    /// **Sticky state is not touched** — `consumeAfterNonModifierEmission()`
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
        // FR-007 — hardware path only fires while the user has
        // opted into Direct mode.  Stale press events that arrive
        // during a mode toggle (e.g. the user releases a key just
        // after toggling out) drop silently rather than leaking a
        // press onto the wire.
        guard directKeystrokeMode.isActive,
              let emitter = keystrokeEmitter
        else {
            return
        }
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
        guard let emitter = keystrokeEmitter else {
            return
        }
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
            latestInjectionAttempt = nil
            latestComposeSendPreparation = nil
            return
        }

        draft.updateText(text)
        composeDraft = draft
        latestInjectionAttempt = nil
        latestComposeSendPreparation = nil
    }

    public func recordComposeSendPreparation(_ report: ComposeSendPreparationReport) {
        latestComposeSendPreparation = report
    }

    public func sendComposedText(_ text: String, pasteCommand: PasteCommand = .commandV) {
        guard var draft = composeDraft else {
            return
        }

        guard draft.sendState != .sending else {
            return
        }

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

            guard await Self.isCurrentTextInjection(
                self,
                draftID: draftID,
                sessionID: sessionID,
                clientBox: clientBox
            ) else {
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

            guard await Self.isCurrentTextInjection(
                self,
                draftID: draftID,
                sessionID: sessionID,
                clientBox: clientBox
            ) else {
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
                let message = HelperTextBridgeError.safeMessage(for: result.safeFailureCode)
                attempt.finishedAt = Date()
                attempt.status = result.status
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
                await Self.finishStoredHelperFailure(
                    self,
                    draft: draft,
                    attempt: attempt,
                    helperState: helperState,
                    failureCode: Self.helperFailureCode(from: error),
                    profileID: profileID,
                    draftID: draftID,
                    sessionID: sessionID,
                    now: now
                )
                return
            } catch {
                await Self.finishStoredHelperFailure(
                    self,
                    draft: draft,
                    attempt: attempt,
                    helperState: helperState,
                    failureCode: .notConfigured,
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

            do {
                let capability = try await client.capability(
                    profilePairingFingerprint: helperState.pairingFingerprint
                )
                let capabilityState = Self.helperTextBridgeProbeState(
                    for: profile,
                    capability: capability
                )
                guard capability.availability == .reachable else {
                    await Self.finishStoredHelperFailure(
                        self,
                        draft: draft,
                        attempt: attempt,
                        helperState: capabilityState,
                        failureCode: Self.failureCode(for: capability.availability),
                        profileID: profileID,
                        draftID: draftID,
                        sessionID: sessionID,
                        now: now
                    )
                    return
                }
                let readyState = Self.updatedHelperTextBridgeState(
                    capabilityState,
                    failureCode: .none
                )
                await Self.publishHelperTextBridgeState(
                    self,
                    state: readyState,
                    profileID: profileID
                )

                let result = try await client.insertText(draft.text, metadata: metadata)
                let message = HelperTextBridgeError.safeMessage(for: result.safeFailureCode)
                attempt.finishedAt = Date()
                attempt.status = result.status
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
                    helperState: helperState,
                    failureCode: Self.helperFailureCode(from: error),
                    profileID: profileID,
                    draftID: draftID,
                    sessionID: sessionID,
                    now: now
                )
            }
        }
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
            client.availability == .reachable
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
            configuration.pairingSecretRef != nil
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
        case .checking, .reachable:
            return true
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

    private static func isCurrentTextInjection(
        _ model: NaruRemoteAppModel?,
        draftID: ComposeDraft.ID,
        sessionID: RemoteSession.ID,
        clientBox: RemoteClipboardTextClientBox
    ) async -> Bool {
        await MainActor.run {
            guard let model,
                  model.session?.id == sessionID,
                  model.session?.state == .active,
                  clientBox.matches(model.activeTextClient)
            else {
                return false
            }
            return true
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
        sessionID: RemoteSession.ID
    ) async {
        var cancelledDraft = draft
        var cancelledAttempt = attempt
        let message = "Text send cancelled because the remote session changed."
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
        guard !commands.isEmpty else {
            return
        }

        pointerInputDispatcher.enqueue(
            operation: { [pointerClient, commands] in
                let useBestEffort = commands.count == 1
                    && commands[0].buttonMask == RFBPointerCommand.released
                if useBestEffort,
                   let bestEffortClient = pointerClient as? RFBBestEffortPointerEventClient,
                   let command = commands.first
                {
                    try bestEffortClient.sendBestEffortPointerEvent(
                        buttonMask: command.buttonMask,
                        x: command.x,
                        y: command.y
                    )
                    return
                }

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
            },
            validate: { [weak self, pointerClient, streamID, sessionID, profileID] in
                await MainActor.run {
                    guard let self else {
                        return false
                    }
                    return self.activeFrameStreamID == streamID
                        && self.session?.id == sessionID
                        && self.selectedProfileID == profileID
                        && self.activePointerClient === pointerClient
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
                    self.activePointerClient = nil
                    self.lastEmittedDragCoord = nil
                }
            }
        )
    }

    private static func singleButtonlessPointerMove(_ commands: [RFBPointerCommand]) -> RFBPointerCommand? {
        guard commands.count == 1,
              let command = commands.first,
              command.buttonMask == RFBPointerCommand.released
        else {
            return nil
        }
        return command
    }

    private func enqueueCoalescedPointerMove(
        _ command: RFBPointerCommand,
        pointerClient: RFBPointerEventClient,
        streamID: UUID?,
        sessionID: RemoteSession.ID?,
        profileID: ConnectionProfile.ID?,
        coalescingDelay: Duration? = nil
    ) {
        let coalescingDelay = coalescingDelay ?? Self.directPointerMoveCoalescingDelay
        pendingPointerMove = PendingPointerMove(
            command: command,
            pointerClient: pointerClient,
            streamID: streamID,
            sessionID: sessionID,
            profileID: profileID
        )

        guard pointerMoveFlushTask == nil else {
            return
        }

        let delay = coalescingDelay
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
            [pendingMove.command],
            pointerClient: pendingMove.pointerClient,
            streamID: pendingMove.streamID,
            sessionID: pendingMove.sessionID,
            profileID: pendingMove.profileID
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
    ///   - no `latestFramebuffer` (no first frame yet)
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
        guard let framebuffer = latestFramebuffer,
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height
        ) else {
            return
        }

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
        guard let framebuffer = latestFramebuffer,
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height
        ) else {
            return
        }

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
    public func sendScrollAt(
        viewPoint: CGPoint,
        viewSize: CGSize,
        deltaX: CGFloat,
        deltaY: CGFloat,
        threshold: CGFloat = scrollTickThreshold
    ) {
        guard let framebuffer = latestFramebuffer,
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height
        ) else {
            return
        }

        let verticalMask: UInt8 = deltaY >= 0 ? 0x08 : 0x10
        let horizontalMask: UInt8 = deltaX >= 0 ? 0x40 : 0x20

        let ticks = Self.scrollTicks(
            forDelta: (x: deltaX, y: deltaY),
            threshold: threshold,
            verticalMask: verticalMask,
            horizontalMask: horizontalMask
        )

        guard !ticks.isEmpty else {
            return
        }

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
    ///   - no `latestFramebuffer` (no first frame yet)
    ///   - no streaming pointer client
    ///   - the drag start falls in the letterbox/pillarbox bands
    public func sendPointerDownAt(viewPoint: CGPoint, viewSize: CGSize) async {
        guard !explicitlyDisconnected,
              let framebuffer = latestFramebuffer,
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height
        ) else {
            return
        }

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
              let framebuffer = latestFramebuffer,
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height
        ) else {
            return
        }

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
              let framebuffer = latestFramebuffer,
              let pointerClient = activePointerClient
        else {
            return
        }

        guard let mapped = Self.framebufferCoordinate(
            forViewPoint: viewPoint,
            viewSize: viewSize,
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height
        ) else {
            return
        }

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

        pipWatchController?.stop()
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
        changeActivity: PiPFrameChangeActivity
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
        pipWatchController?.stop()
        pipWatchSession = nil
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

    private var currentPiPWatchViewport: PiPWatchViewport {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        return pipLayerHost.currentViewport
        #else
        return .fullFrame
        #endif
    }

    private func prepareController(_ controller: any PiPWatchControlling) -> Bool {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        if let attaching = controller as? any PiPWatchLayerHostAttaching {
            return attaching.prepare(layerHost: pipLayerHost)
        }
        #endif
        return controller.prepare()
    }
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
