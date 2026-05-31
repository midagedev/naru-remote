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
    /// source also exposes the receive and transport-control capability
    /// protocols.
    public let updateMode: RFBFramePumpUpdateMode

    public init(
        maxFrames: Int? = nil,
        requestTimeout: TimeInterval = 2,
        frameInterval: TimeInterval = 0,
        idleFrameInterval: TimeInterval = 0,
        updateMode: RFBFramePumpUpdateMode = .requestResponse
    ) {
        self.maxFrames = maxFrames
        self.requestTimeout = requestTimeout
        self.frameInterval = max(frameInterval, 0)
        self.idleFrameInterval = max(idleFrameInterval, 0)
        self.updateMode = updateMode
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

    public init(
        sequence: Int,
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        changedPixelCount: Int? = nil,
        changeActivity: PiPFrameChangeActivity? = nil,
        capturedAt: Date = Date(),
        isIncremental: Bool,
        serverCursor: RFBServerCursor? = nil
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
            disableContinuousUpdatesIfNeeded(timeout: configuration.requestTimeout)
        }

        while shouldContinue(deliveredFrameCount: deliveredFrameCount, maxFrames: configuration.maxFrames) {
            guard let frame = try nextFrame(
                requestTimeout: configuration.requestTimeout,
                updateMode: configuration.updateMode
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
        updateMode: RFBFramePumpUpdateMode = .requestResponse
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
        let updateResult: RFBFramebufferUpdateResult
        if updateMode == .continuousUpdates,
           isIncremental,
           let receiver = source as? any RFBFramebufferUpdateReceiving,
           let transportControl = source as? any RFBTransportControlClient
        {
            try enableContinuousUpdatesIfNeeded(
                transportControl,
                timeout: requestTimeout
            )
            updateResult = try receiver.receiveFramebufferUpdate(timeout: requestTimeout)
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
        }
    }

    private func enableContinuousUpdatesIfNeeded(
        _ transportControl: any RFBTransportControlClient,
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
            region: nil,
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

    private var _deliveredFrameCount = 0
}

private extension NSLock {
    func withRFBFramePumpLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
