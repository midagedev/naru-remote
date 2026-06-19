import Foundation

public enum RFBFramePumpDecision: Equatable, Sendable {
    case `continue`
    case stop
}

public enum RFBFramePumpUpdateMode: Equatable, Sendable {
    case requestResponse
    case continuousUpdates
}

public struct RFBFramePumpConfiguration: Equatable, Sendable {
    public let maxFrames: Int?
    public let requestTimeout: TimeInterval
    /// Delay applied after a frame that carried *new* content, i.e. the
    /// active-streaming cadence floor.  `0` means "request the next
    /// frame as fast as the network round-trip + decode allow" - the
    /// macOS Screen Sharing-like fluid path.  A non-zero value caps the
    /// active frame rate (the old default of `0.25` pinned streaming to
    /// ~4 fps, which is the single biggest felt-smoothness regression
    /// versus a native viewer).
    public let frameInterval: TimeInterval
    /// Delay applied after an *empty* incremental update (the server
    /// replied with zero changed rectangles instead of holding the
    /// request).  Decoupled from `frameInterval` so an idle screen
    /// polls gently, protecting against a hot request loop on servers
    /// that return empty updates immediately, without throttling the
    /// active path.  `0` polls as fast as the round-trip allows.
    public let idleFrameInterval: TimeInterval
    /// Transport mode used after the initial full-frame request. The
    /// default remains request/response for universal RFB compatibility.
    /// `continuousUpdates` is opportunistic: it activates only when the
    /// source exposes receive/control boundaries *and* reports that the
    /// current session confirmed the ContinuousUpdates extension.
    public let updateMode: RFBFramePumpUpdateMode
    /// Optional fixed remote-framebuffer region for incremental update requests.
    public let requestRegion: RFBFramebufferUpdateRegion?
    /// Optional fixed remote-framebuffer region for the first non-incremental
    /// update request. `nil` preserves the default full-frame bootstrap; a
    /// region is an opt-in benchmark/viewport startup experiment.
    public let initialRequestRegion: RFBFramebufferUpdateRegion?
    /// Number of incremental `FramebufferUpdateRequest` messages kept
    /// outstanding on a request/response transport. `1` is the classic
    /// one-request-per-round-trip behaviour. A depth `> 1` keeps the
    /// server's encode pipeline primed so it does not idle during the
    /// request→response round-trip — the request/response-compatible way
    /// to recover the latency that ContinuousUpdates would, against
    /// servers (e.g. Apple Screen Sharing) that do not support the
    /// extension. Ignored once ContinuousUpdates is active (that transport
    /// already decouples request from response). Clamped to `1...4`.
    public let requestPipelineDepth: Int

    public init(
        maxFrames: Int? = nil,
        requestTimeout: TimeInterval = 2,
        frameInterval: TimeInterval = 0,
        idleFrameInterval: TimeInterval = 0,
        updateMode: RFBFramePumpUpdateMode = .requestResponse,
        requestRegion: RFBFramebufferUpdateRegion? = nil,
        initialRequestRegion: RFBFramebufferUpdateRegion? = nil,
        requestPipelineDepth: Int = 1
    ) {
        self.maxFrames = maxFrames
        self.requestTimeout = requestTimeout
        self.frameInterval = max(frameInterval, 0)
        self.idleFrameInterval = max(idleFrameInterval, 0)
        self.updateMode = updateMode
        self.requestRegion = requestRegion
        self.initialRequestRegion = initialRequestRegion
        self.requestPipelineDepth = min(max(requestPipelineDepth, 1), 4)
    }
}

public struct RFBFramePumpFrame: Equatable, Sendable {
    public let sequence: Int
    public let framebuffer: RFBRawFramebuffer
    public let dirtyRectangles: [RFBFrameDamageRect]
    public let changedPixelCount: Int
    public let changeActivity: PiPFrameChangeActivity
    public let capturedAt: Date
    public let isIncremental: Bool
    public let serverCursor: RFBServerCursor?
    public let transportIdleTimedOut: Bool
    public let timing: RFBFramebufferUpdateTiming?
    public let decodeMetrics: RFBFramebufferDecodeMetrics
    public let encodingMix: RFBFramebufferEncodingMix

    public init(
        sequence: Int,
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        changedPixelCount: Int? = nil,
        changeActivity: PiPFrameChangeActivity? = nil,
        capturedAt: Date = Date(),
        isIncremental: Bool,
        serverCursor: RFBServerCursor? = nil,
        transportIdleTimedOut: Bool = false,
        timing: RFBFramebufferUpdateTiming? = nil,
        decodeMetrics: RFBFramebufferDecodeMetrics = RFBFramebufferDecodeMetrics(),
        encodingMix: RFBFramebufferEncodingMix = RFBFramebufferEncodingMix()
    ) {
        self.sequence = sequence
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles ?? [
            RFBFrameDamageRect(
                x: 0,
                y: 0,
                width: framebuffer.width,
                height: framebuffer.height
            )
        ]
        self.changedPixelCount = changedPixelCount ?? framebuffer.width * framebuffer.height
        self.changeActivity = changeActivity ?? .high
        self.capturedAt = capturedAt
        self.isIncremental = isIncremental
        self.serverCursor = serverCursor
        self.transportIdleTimedOut = transportIdleTimedOut
        self.timing = timing
        self.decodeMetrics = decodeMetrics
        self.encodingMix = encodingMix
    }

    public init(
        sequence: Int,
        updateResult: RFBFramebufferUpdateResult,
        isIncremental: Bool
    ) {
        self.sequence = sequence
        self.framebuffer = updateResult.framebuffer
        self.dirtyRectangles = updateResult.dirtyRectangles
        self.changedPixelCount = updateResult.changedPixelCount
        self.changeActivity = updateResult.changeActivity
        self.capturedAt = updateResult.capturedAt
        self.isIncremental = isIncremental
        self.serverCursor = updateResult.serverCursor
        self.transportIdleTimedOut = updateResult.transportIdleTimedOut
        self.timing = updateResult.timing
        self.decodeMetrics = updateResult.decodeMetrics
        self.encodingMix = updateResult.encodingMix
    }
}

public struct RFBFramePumpSummary: Equatable, Sendable {
    public let deliveredFrameCount: Int
    public let stoppedByCallback: Bool
    public let stoppedByCancellation: Bool

    public init(
        deliveredFrameCount: Int,
        stoppedByCallback: Bool,
        stoppedByCancellation: Bool
    ) {
        self.deliveredFrameCount = deliveredFrameCount
        self.stoppedByCallback = stoppedByCallback
        self.stoppedByCancellation = stoppedByCancellation
    }
}

// @unchecked Sendable justified: `RFBFramePump.run` is a long-lived
// blocking frame loop — it issues a synchronous
// `requestFramebufferUpdate` on its `RFBFramebufferUpdating` source
// (the underlying `NWConnection` semaphores block the caller
// thread), invokes a synchronous `onFrame` callback that may
// itself call `pump.cancel()`, and `Thread.sleep`s between frames.
// Migrating to `actor` would put that blocking work on the actor's
// serial executor and force `cancel()` to be `async`, which would
// either deadlock callbacks that `await pump.cancel()` from inside
// `run` (`RFBFramePumpTests.testPumpStopsAfterCancellation`) or
// cascade `async` through `RFBFramebufferUpdating` — which the test
// fakes for that protocol implement synchronously today (deferred
// per PR #17's out-of-scope list).  Mutable state (`cancelled`,
// `_deliveredFrameCount`) is guarded by `lock` — every read and
// every write goes through `lock.withRFBFramePumpLock`.
public final class RFBFramePump: @unchecked Sendable {
    private let source: any RFBFramebufferUpdating
    private let lock = NSLock()
    private var cancelled = false
    private var continuousUpdatesEnabled = false
    private var continuousUpdatesSuppressed = false
    /// Incremental requests currently parked on the server in pipelined
    /// request/response mode. Maintained at the configured depth so the
    /// backlog stays bounded across a sustained session (unlike a naive
    /// send-depth-per-frame burst, which would grow without limit).
    private var pipelinedOutstandingRequests = 0

    public init(source: any RFBFramebufferUpdating) {
        self.source = source
    }

    public func cancel() {
        lock.withRFBFramePumpLock {
            cancelled = true
        }
    }

    public var deliveredFrameCount: Int {
        lock.withRFBFramePumpLock {
            _deliveredFrameCount
        }
    }

    public func run(
        configuration: RFBFramePumpConfiguration = RFBFramePumpConfiguration(),
        onFrame: (RFBFramePumpFrame) throws -> RFBFramePumpDecision
    ) throws -> RFBFramePumpSummary {
        reset()
        defer {
            stopContinuousUpdatesIfNeeded(timeout: configuration.requestTimeout)
        }

        while shouldContinue(deliveredFrameCount: deliveredFrameCount, maxFrames: configuration.maxFrames) {
            guard let frame = try nextFrame(
                requestTimeout: configuration.requestTimeout,
                updateMode: configuration.updateMode,
                requestRegion: configuration.requestRegion,
                initialRequestRegion: configuration.initialRequestRegion,
                requestPipelineDepth: configuration.requestPipelineDepth
            ) else {
                break
            }

            if try onFrame(frame) == .stop {
                return RFBFramePumpSummary(
                    deliveredFrameCount: deliveredFrameCount,
                    stoppedByCallback: true,
                    stoppedByCancellation: false
                )
            }

            if isCancelled {
                return RFBFramePumpSummary(
                    deliveredFrameCount: deliveredFrameCount,
                    stoppedByCallback: false,
                    stoppedByCancellation: true
                )
            }

            let pacingDelay = frame.isIncremental && frame.changedPixelCount == 0
                ? configuration.idleFrameInterval
                : configuration.frameInterval
            if pacingDelay > 0 {
                Thread.sleep(forTimeInterval: pacingDelay)
            }
        }

        return RFBFramePumpSummary(
            deliveredFrameCount: deliveredFrameCount,
            stoppedByCallback: false,
            stoppedByCancellation: isCancelled
        )
    }

    public func nextFrame(
        requestTimeout: TimeInterval = 2,
        updateMode: RFBFramePumpUpdateMode = .requestResponse,
        requestRegion: RFBFramebufferUpdateRegion? = nil,
        initialRequestRegion: RFBFramebufferUpdateRegion? = nil,
        requestPipelineDepth: Int = 1
    ) throws -> RFBFramePumpFrame? {
        let nextSequence: Int? = lock.withRFBFramePumpLock {
            guard !cancelled else {
                return nil
            }
            return _deliveredFrameCount + 1
        }

        guard let nextSequence else {
            return nil
        }

        let isIncremental = nextSequence > 1
        let regionForRequest = isIncremental ? requestRegion : initialRequestRegion
        let updateResult: RFBFramebufferUpdateResult
        // Region requests require a region-capable source. Sources that only
        // expose damage tracking keep the compatible full-frame bootstrap path.
        if updateMode == .continuousUpdates,
           isIncremental,
           canUseContinuousUpdates,
           let receiver = source as? any RFBFramebufferUpdateReceiving,
           let transportControl = source as? any RFBTransportControlClient
        {
            try enableContinuousUpdatesIfNeeded(
                transportControl,
                region: regionForRequest,
                timeout: requestTimeout
            )
            if let continuousReceiver = source as? any RFBContinuousFramebufferUpdateReceiving {
                updateResult = try continuousReceiver.receiveContinuousFramebufferUpdate(timeout: requestTimeout)
            } else {
                updateResult = try receiver.receiveFramebufferUpdate(timeout: requestTimeout)
            }
        } else if isIncremental,
                  requestPipelineDepth > 1,
                  let sender = source as? any RFBFramebufferUpdateRequestSending,
                  let pipelinedReceiver = source as? any RFBContinuousFramebufferUpdateReceiving {
            // Pipelined request/response: keep `requestPipelineDepth`
            // incremental requests parked on the server so it can begin
            // encoding the next frame while we are still reading the
            // current one. This is the request/response-safe stand-in for
            // ContinuousUpdates on servers (e.g. Apple Screen Sharing)
            // that do not support the extension — it removes the per-frame
            // request→response idle gap that dominates that server's
            // first-byte wait.
            let depth = max(requestPipelineDepth, 1)
            if pipelinedOutstandingRequests <= 0 {
                for _ in 0..<depth {
                    try sender.sendFramebufferUpdateRequest(
                        incremental: true,
                        timeout: requestTimeout,
                        region: regionForRequest
                    )
                }
                pipelinedOutstandingRequests = depth
            }
            let result = try pipelinedReceiver.receiveContinuousFramebufferUpdate(timeout: requestTimeout)
            if !result.transportIdleTimedOut {
                // Consumed one server response — refill to hold the pipeline
                // at `depth`. On an idle timeout no response was consumed, so
                // the parked requests stay put and the backlog never grows.
                try sender.sendFramebufferUpdateRequest(
                    incremental: true,
                    timeout: requestTimeout,
                    region: regionForRequest
                )
            }
            updateResult = result
        } else if (isIncremental || regionForRequest != nil),
                  let regionSource = source as? any RFBRegionFramebufferUpdating {
            updateResult = try regionSource.requestFramebufferUpdate(
                incremental: isIncremental,
                timeout: requestTimeout,
                region: regionForRequest
            )
        } else if let damageTrackingSource = source as? any RFBDamageTrackingFramebufferUpdating {
            updateResult = try damageTrackingSource.requestFramebufferUpdate(
                incremental: isIncremental,
                timeout: requestTimeout
            )
        } else {
            let framebuffer = try source.requestRawFramebufferUpdate(
                incremental: isIncremental,
                timeout: requestTimeout
            )
            updateResult = .fullFrame(framebuffer: framebuffer)
        }

        if updateResult.endedContinuousUpdates {
            markContinuousUpdatesEnded()
        }

        lock.withRFBFramePumpLock {
            _deliveredFrameCount = nextSequence
        }

        return RFBFramePumpFrame(
            sequence: nextSequence,
            updateResult: updateResult,
            isIncremental: isIncremental
        )
    }

    public func reset() {
        lock.withRFBFramePumpLock {
            _deliveredFrameCount = 0
            cancelled = false
            continuousUpdatesEnabled = false
            continuousUpdatesSuppressed = false
            pipelinedOutstandingRequests = 0
        }
    }

    /// Best-effort shutdown hook for callers that drive the pump with
    /// manual `nextFrame` loops instead of `run`. `run` calls this
    /// automatically on exit.
    public func stopContinuousUpdatesIfNeeded(timeout: TimeInterval = 2) {
        disableContinuousUpdatesIfNeeded(timeout: timeout)
    }

    private func enableContinuousUpdatesIfNeeded(
        _ transportControl: any RFBTransportControlClient,
        region: RFBFramebufferUpdateRegion?,
        timeout: TimeInterval
    ) throws {
        let shouldEnable = lock.withRFBFramePumpLock {
            !continuousUpdatesEnabled
        }
        guard shouldEnable else {
            return
        }

        try transportControl.enableContinuousUpdates(
            true,
            region: region,
            timeout: timeout
        )

        lock.withRFBFramePumpLock {
            continuousUpdatesEnabled = true
        }
    }

    private func disableContinuousUpdatesIfNeeded(timeout: TimeInterval) {
        let shouldDisable = lock.withRFBFramePumpLock {
            continuousUpdatesEnabled
        }
        guard shouldDisable,
              let transportControl = source as? any RFBTransportControlClient else {
            return
        }

        try? transportControl.enableContinuousUpdates(
            false,
            region: nil,
            timeout: timeout
        )

        lock.withRFBFramePumpLock {
            continuousUpdatesEnabled = false
        }
    }

    private func markContinuousUpdatesEnded() {
        lock.withRFBFramePumpLock {
            continuousUpdatesEnabled = false
            continuousUpdatesSuppressed = true
        }
    }

    private func shouldContinue(deliveredFrameCount: Int, maxFrames: Int?) -> Bool {
        guard !isCancelled else {
            return false
        }

        guard let maxFrames else {
            return true
        }

        return deliveredFrameCount < max(maxFrames, 0)
    }

    private var isCancelled: Bool {
        lock.withRFBFramePumpLock {
            cancelled
        }
    }

    private var canUseContinuousUpdates: Bool {
        guard let capability = source as? any RFBContinuousUpdateCapabilityReporting,
              capability.canEnableContinuousUpdates else {
            return false
        }

        return lock.withRFBFramePumpLock {
            !continuousUpdatesSuppressed
        }
    }

    private var _deliveredFrameCount = 0
}

private extension NSLock {
    func withRFBFramePumpLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
