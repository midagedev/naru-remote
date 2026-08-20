import Foundation
import os
import XCTest
@testable import NaruRemoteCore

final class RFBFramePumpTests: XCTestCase {
    func testPumpRequestsFullFrameThenIncrementalFrames() throws {
        let source = FakeFramebufferUpdateSource(
            framebuffers: [
                Self.framebuffer(red: 255),
                Self.framebuffer(red: 128)
            ]
        )
        let pump = RFBFramePump(source: source)
        var frames: [RFBFramePumpFrame] = []

        let summary = try pump.run(
            configuration: RFBFramePumpConfiguration(maxFrames: 2)
        ) { frame in
            frames.append(frame)
            return .continue
        }

        XCTAssertEqual(source.requestedIncrementalFlags, [false, true])
        XCTAssertEqual(frames.map(\.sequence), [1, 2])
        XCTAssertEqual(frames.map(\.isIncremental), [false, true])
        XCTAssertEqual(frames.first?.framebuffer[0, 0], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(summary.deliveredFrameCount, 2)
        XCTAssertFalse(summary.stoppedByCallback)
        XCTAssertFalse(summary.stoppedByCancellation)
    }

    func testPumpStopsWhenFrameHandlerRequestsStop() throws {
        let source = FakeFramebufferUpdateSource(
            framebuffers: [
                Self.framebuffer(red: 255),
                Self.framebuffer(red: 128)
            ]
        )
        let pump = RFBFramePump(source: source)

        let summary = try pump.run(
            configuration: RFBFramePumpConfiguration(maxFrames: 4)
        ) { _ in
            .stop
        }

        XCTAssertEqual(source.requestedIncrementalFlags, [false])
        XCTAssertEqual(summary.deliveredFrameCount, 1)
        XCTAssertTrue(summary.stoppedByCallback)
        XCTAssertFalse(summary.stoppedByCancellation)
    }

    func testPumpStopsAfterCancellation() throws {
        let source = FakeFramebufferUpdateSource(
            framebuffers: [
                Self.framebuffer(red: 255),
                Self.framebuffer(red: 128)
            ]
        )
        let pump = RFBFramePump(source: source)

        let summary = try pump.run(
            configuration: RFBFramePumpConfiguration(maxFrames: 4)
        ) { _ in
            pump.cancel()
            return .continue
        }

        XCTAssertEqual(source.requestedIncrementalFlags, [false])
        XCTAssertEqual(summary.deliveredFrameCount, 1)
        XCTAssertFalse(summary.stoppedByCallback)
        XCTAssertTrue(summary.stoppedByCancellation)
    }

    func testPumpPropagatesSourceErrors() throws {
        let source = FakeFramebufferUpdateSource(framebuffers: [])
        let pump = RFBFramePump(source: source)

        XCTAssertThrowsError(
            try pump.run(configuration: RFBFramePumpConfiguration(maxFrames: 1)) { _ in
                .continue
            }
        ) { error in
            XCTAssertEqual(error as? FakeFramebufferUpdateSource.Error, .noFrame)
        }
    }

    func testPumpPreservesDamageTrackingMetadataWhenSourceProvidesIt() throws {
        let capturedAt = Date(timeIntervalSince1970: 200)
        let cursor = RFBServerCursor(
            width: 1,
            height: 1,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [RFBColor(red: 255, green: 255, blue: 255)]
        )
        let result = RFBFramebufferUpdateResult(
            framebuffer: RFBRawFramebuffer(width: 100, height: 100),
            dirtyRectangles: [
                RFBFrameDamageRect(x: 10, y: 10, width: 30, height: 30)
            ],
            changedPixelCount: 1_000,
            capturedAt: capturedAt,
            serverCursor: cursor,
            timing: RFBFramebufferUpdateTiming(
                totalMilliseconds: 21,
                networkReadMilliseconds: 17,
                firstByteWaitMilliseconds: 14
            ),
            decodeMetrics: RFBFramebufferDecodeMetrics(
                zrleInflateMilliseconds: 2,
                zrleTileApplyMilliseconds: 3
            ),
            encodingMix: RFBFramebufferEncodingMix(tightRectangles: 1, cursorRectangles: 1)
        )
        let source = FakeDamageTrackingFramebufferUpdateSource(results: [result])
        let pump = RFBFramePump(source: source)

        let frame = try XCTUnwrap(pump.nextFrame())

        XCTAssertEqual(source.requestedIncrementalFlags, [false])
        XCTAssertEqual(frame.dirtyRectangles, result.dirtyRectangles)
        XCTAssertEqual(frame.changedPixelCount, 1_000)
        XCTAssertEqual(frame.changeActivity, .moderate)
        XCTAssertEqual(frame.capturedAt, capturedAt)
        XCTAssertEqual(frame.serverCursor, cursor)
        XCTAssertEqual(frame.timing?.totalMilliseconds, 21)
        XCTAssertEqual(frame.timing?.networkReadMilliseconds, 17)
        XCTAssertEqual(frame.timing?.firstByteWaitMilliseconds, 14)
        XCTAssertEqual(frame.timing?.payloadReadMilliseconds, 3)
        XCTAssertEqual(frame.timing?.clientProcessingMilliseconds, 4)
        XCTAssertEqual(frame.decodeMetrics.zrleInflateMilliseconds, 2)
        XCTAssertEqual(frame.decodeMetrics.zrleTileApplyMilliseconds, 3)
        XCTAssertEqual(frame.encodingMix.tightRectangles, 1)
        XCTAssertEqual(frame.encodingMix.cursorRectangles, 1)
    }

    func testPumpUsesIdleIntervalAfterEmptyIncrementalFrame() throws {
        let framebuffer = Self.framebuffer(red: 255)
        let source = FakeDamageTrackingFramebufferUpdateSource(
            results: [
                .fullFrame(framebuffer: framebuffer),
                RFBFramebufferUpdateResult(
                    framebuffer: framebuffer,
                    dirtyRectangles: [],
                    changedPixelCount: 0
                )
            ]
        )
        let pump = RFBFramePump(source: source)

        let start = Date()
        _ = try pump.run(
            configuration: RFBFramePumpConfiguration(
                maxFrames: 2,
                frameInterval: 0,
                idleFrameInterval: 0.02
            )
        ) { _ in
            .continue
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(source.requestedIncrementalFlags, [false, true])
        XCTAssertGreaterThanOrEqual(elapsed, 0.015)
    }

    func testPumpUsesContinuousUpdatesAfterInitialFrameWhenSourceSupportsIt() throws {
        let initial = RFBFramebufferUpdateResult.fullFrame(framebuffer: Self.framebuffer(red: 255))
        let pushed = RFBFramebufferUpdateResult(
            framebuffer: Self.framebuffer(red: 128),
            dirtyRectangles: [
                RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)
            ],
            changedPixelCount: 1
        )
        let source = FakeContinuousFramebufferUpdateSource(
            requestedResults: [initial],
            receivedResults: [pushed]
        )
        let pump = RFBFramePump(source: source)

        let first = try pump.nextFrame(
            requestTimeout: 1,
            updateMode: .continuousUpdates
        )
        let second = try pump.nextFrame(
            requestTimeout: 1,
            updateMode: .continuousUpdates
        )

        XCTAssertEqual(first?.isIncremental, false)
        XCTAssertEqual(second?.isIncremental, true)
        XCTAssertEqual(second?.framebuffer[0, 0], RFBColor(red: 128, green: 0, blue: 0))
        XCTAssertEqual(source.requestedIncrementalFlags, [false])
        XCTAssertEqual(source.receivedFrameCount, 1)
        XCTAssertEqual(source.enableContinuousUpdatesCallCount, 1)
    }

    func testManualNextFrameLoopCanStopContinuousUpdates() throws {
        let initial = RFBFramebufferUpdateResult.fullFrame(framebuffer: Self.framebuffer(red: 255))
        let pushed = RFBFramebufferUpdateResult(
            framebuffer: Self.framebuffer(red: 128),
            dirtyRectangles: [
                RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)
            ],
            changedPixelCount: 1
        )
        let source = FakeContinuousFramebufferUpdateSource(
            requestedResults: [initial],
            receivedResults: [pushed]
        )
        let pump = RFBFramePump(source: source)

        _ = try pump.nextFrame(requestTimeout: 1, updateMode: .continuousUpdates)
        _ = try pump.nextFrame(requestTimeout: 1, updateMode: .continuousUpdates)
        pump.stopContinuousUpdatesIfNeeded(timeout: 1)
        pump.stopContinuousUpdatesIfNeeded(timeout: 1)

        XCTAssertEqual(source.enableContinuousUpdatesCallCount, 1)
        XCTAssertEqual(source.disableContinuousUpdatesCallCount, 1)
        XCTAssertEqual(source.continuousUpdatesEnabledFlags, [true, false])
    }

    func testPumpDisablesContinuousUpdatesWhenRunStopsAfterCallback() throws {
        let initial = RFBFramebufferUpdateResult.fullFrame(framebuffer: Self.framebuffer(red: 255))
        let pushed = RFBFramebufferUpdateResult(
            framebuffer: Self.framebuffer(red: 128),
            dirtyRectangles: [
                RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)
            ],
            changedPixelCount: 1
        )
        let source = FakeContinuousFramebufferUpdateSource(
            requestedResults: [initial],
            receivedResults: [pushed]
        )
        let pump = RFBFramePump(source: source)
        var frames: [RFBFramePumpFrame] = []

        let summary = try pump.run(
            configuration: RFBFramePumpConfiguration(
                maxFrames: 4,
                requestTimeout: 1,
                updateMode: .continuousUpdates
            )
        ) { frame in
            frames.append(frame)
            return frame.isIncremental ? .stop : .continue
        }

        XCTAssertEqual(frames.map(\.sequence), [1, 2])
        XCTAssertEqual(source.requestedIncrementalFlags, [false])
        XCTAssertEqual(source.receivedFrameCount, 1)
        XCTAssertEqual(source.enableContinuousUpdatesCallCount, 1)
        XCTAssertEqual(source.disableContinuousUpdatesCallCount, 1)
        XCTAssertEqual(source.continuousUpdatesEnabledFlags, [true, false])
        XCTAssertEqual(summary.deliveredFrameCount, 2)
        XCTAssertTrue(summary.stoppedByCallback)
        XCTAssertFalse(summary.stoppedByCancellation)
    }

    func testPumpFallsBackToRequestResponseWhenContinuousSourceIsUnavailable() throws {
        let source = FakeDamageTrackingFramebufferUpdateSource(
            results: [
                .fullFrame(framebuffer: Self.framebuffer(red: 255)),
                .fullFrame(framebuffer: Self.framebuffer(red: 128))
            ]
        )
        let pump = RFBFramePump(source: source)

        _ = try pump.nextFrame(updateMode: .continuousUpdates)
        _ = try pump.nextFrame(updateMode: .continuousUpdates)

        XCTAssertEqual(source.requestedIncrementalFlags, [false, true])
    }

    func testPumpPassesRequestRegionOnlyAfterInitialFrame() throws {
        let region = RFBFramebufferUpdateRegion(x: 1, y: 2, width: 3, height: 4)
        let source = FakeRegionFramebufferUpdateSource(
            results: [
                .fullFrame(framebuffer: Self.framebuffer(red: 255)),
                .fullFrame(framebuffer: Self.framebuffer(red: 128))
            ]
        )
        let pump = RFBFramePump(source: source)

        _ = try pump.run(
            configuration: RFBFramePumpConfiguration(maxFrames: 2, requestRegion: region)
        ) { _ in
            .continue
        }

        XCTAssertEqual(source.requestedIncrementalFlags, [false, true])
        XCTAssertEqual(source.requestedRegions, [nil, region])
    }

    func testPumpCanPassInitialRequestRegionWhenConfigured() throws {
        let initialRegion = RFBFramebufferUpdateRegion(x: 10, y: 20, width: 30, height: 40)
        let incrementalRegion = RFBFramebufferUpdateRegion(x: 1, y: 2, width: 3, height: 4)
        let source = FakeRegionFramebufferUpdateSource(
            results: [
                .fullFrame(framebuffer: Self.framebuffer(red: 255)),
                .fullFrame(framebuffer: Self.framebuffer(red: 128))
            ]
        )
        let pump = RFBFramePump(source: source)
        var frames: [RFBFramePumpFrame] = []

        _ = try pump.run(
            configuration: RFBFramePumpConfiguration(
                maxFrames: 2,
                requestRegion: incrementalRegion,
                initialRequestRegion: initialRegion
            )
        ) { frame in
            frames.append(frame)
            return .continue
        }

        XCTAssertEqual(source.requestedIncrementalFlags, [false, true])
        XCTAssertEqual(source.requestedRegions, [initialRegion, incrementalRegion])
        XCTAssertEqual(frames.map(\.sequence), [1, 2])
        XCTAssertEqual(frames.map(\.isIncremental), [false, true])
    }

    func testManualNextFrameCanPassInitialRequestRegion() throws {
        let initialRegion = RFBFramebufferUpdateRegion(x: 10, y: 20, width: 30, height: 40)
        let source = FakeRegionFramebufferUpdateSource(
            results: [
                .fullFrame(framebuffer: Self.framebuffer(red: 255))
            ]
        )
        let pump = RFBFramePump(source: source)

        let frame = try pump.nextFrame(initialRequestRegion: initialRegion)

        XCTAssertEqual(frame?.isIncremental, false)
        XCTAssertEqual(source.requestedIncrementalFlags, [false])
        XCTAssertEqual(source.requestedRegions, [initialRegion])
    }

    func testInitialRequestRegionFallsBackToFullWhenSourceCannotRequestRegions() throws {
        let initialRegion = RFBFramebufferUpdateRegion(x: 10, y: 20, width: 30, height: 40)
        let source = FakeDamageTrackingFramebufferUpdateSource(
            results: [
                .fullFrame(framebuffer: Self.framebuffer(red: 255))
            ]
        )
        let pump = RFBFramePump(source: source)

        let frame = try pump.nextFrame(initialRequestRegion: initialRegion)

        XCTAssertEqual(frame?.isIncremental, false)
        XCTAssertEqual(source.requestedIncrementalFlags, [false])
    }

    func testPumpFallsBackToRequestResponseUntilContinuousUpdatesAreAdvertised() throws {
        let source = FakeContinuousFramebufferUpdateSource(
            requestedResults: [
                .fullFrame(framebuffer: Self.framebuffer(red: 255)),
                .fullFrame(framebuffer: Self.framebuffer(red: 128))
            ],
            receivedResults: [
                .fullFrame(framebuffer: Self.framebuffer(red: 64))
            ],
            canEnableContinuousUpdates: false
        )
        let pump = RFBFramePump(source: source)

        _ = try pump.nextFrame(requestTimeout: 1, updateMode: .continuousUpdates)
        _ = try pump.nextFrame(requestTimeout: 1, updateMode: .continuousUpdates)

        XCTAssertEqual(source.requestedIncrementalFlags, [false, true])
        XCTAssertEqual(source.receivedFrameCount, 0)
        XCTAssertEqual(source.enableContinuousUpdatesCallCount, 0)
        XCTAssertTrue(source.continuousUpdatesEnabledFlags.isEmpty)
    }

    func testPumpPassesRequestRegionWhenEnablingContinuousUpdates() throws {
        let region = RFBFramebufferUpdateRegion(x: 1, y: 2, width: 3, height: 4)
        let source = FakeContinuousFramebufferUpdateSource(
            requestedResults: [
                .fullFrame(framebuffer: Self.framebuffer(red: 255))
            ],
            receivedResults: [
                .fullFrame(framebuffer: Self.framebuffer(red: 128))
            ]
        )
        let pump = RFBFramePump(source: source)

        _ = try pump.nextFrame(
            requestTimeout: 1,
            updateMode: .continuousUpdates,
            requestRegion: region
        )
        _ = try pump.nextFrame(
            requestTimeout: 1,
            updateMode: .continuousUpdates,
            requestRegion: region
        )

        XCTAssertEqual(source.continuousUpdatesEnabledFlags, [true])
        XCTAssertEqual(source.continuousUpdatesRegions, [region])
        XCTAssertEqual(source.requestedIncrementalFlags, [false])
    }

    func testPumpFallsBackToRequestResponseAfterContinuousUpdatesEnd() throws {
        let initial = RFBFramebufferUpdateResult.fullFrame(framebuffer: Self.framebuffer(red: 255))
        let ended = RFBFramebufferUpdateResult(
            framebuffer: Self.framebuffer(red: 255),
            dirtyRectangles: [],
            changedPixelCount: 0,
            endedContinuousUpdates: true
        )
        let fallback = RFBFramebufferUpdateResult.fullFrame(framebuffer: Self.framebuffer(red: 64))
        let source = FakeContinuousFramebufferUpdateSource(
            requestedResults: [initial, fallback],
            receivedResults: [ended]
        )
        let pump = RFBFramePump(source: source)

        let first = try pump.nextFrame(requestTimeout: 1, updateMode: .continuousUpdates)
        let second = try pump.nextFrame(requestTimeout: 1, updateMode: .continuousUpdates)
        let third = try pump.nextFrame(requestTimeout: 1, updateMode: .continuousUpdates)

        XCTAssertEqual(first?.isIncremental, false)
        XCTAssertEqual(second?.isIncremental, true)
        XCTAssertEqual(second?.changedPixelCount, 0)
        XCTAssertEqual(third?.isIncremental, true)
        XCTAssertEqual(third?.framebuffer[0, 0], RFBColor(red: 64, green: 0, blue: 0))
        XCTAssertEqual(source.requestedIncrementalFlags, [false, true])
        XCTAssertEqual(source.receivedFrameCount, 1)
        XCTAssertEqual(source.enableContinuousUpdatesCallCount, 1)
        XCTAssertEqual(source.disableContinuousUpdatesCallCount, 0)
        XCTAssertEqual(source.continuousUpdatesEnabledFlags, [true])
    }

    func testPipelinedRequestResponseKeepsDepthRequestsOutstanding() throws {
        let source = FakePipelinedFramebufferUpdateSource(
            firstFrame: Self.framebuffer(red: 255),
            receivedResults: [
                Self.contentResult(red: 10),
                Self.contentResult(red: 20),
                Self.contentResult(red: 30)
            ]
        )
        let pump = RFBFramePump(source: source)
        var frames: [RFBFramePumpFrame] = []

        _ = try pump.run(
            configuration: RFBFramePumpConfiguration(maxFrames: 4, requestPipelineDepth: 3)
        ) { frame in
            frames.append(frame)
            return .continue
        }

        XCTAssertEqual(frames.map(\.isIncremental), [false, true, true, true])
        // Depth 3 primes 3 incremental requests on the first incremental,
        // then refills one per consumed content frame: 3 + 3 = 6.
        XCTAssertEqual(source.sentIncrementalRequestCount, 6)
        XCTAssertTrue(source.sentRequestsAllIncremental)
        XCTAssertEqual(source.continuousReceiveCount, 3)
    }

    func testPipelinedRequestResponseDoesNotRefillAfterIdleTimeout() throws {
        let source = FakePipelinedFramebufferUpdateSource(
            firstFrame: Self.framebuffer(red: 255),
            receivedResults: [
                Self.idleResult(),
                Self.contentResult(red: 20)
            ]
        )
        let pump = RFBFramePump(source: source)

        _ = try pump.run(
            configuration: RFBFramePumpConfiguration(maxFrames: 3, requestPipelineDepth: 2)
        ) { _ in .continue }

        // Depth 2 primes 2 requests; the idle-timeout receive consumes no
        // server response so it does not refill; the content receive refills
        // one. 2 + 1 = 3, and the backlog never grows past the depth.
        XCTAssertEqual(source.sentIncrementalRequestCount, 3)
    }

    /// Regression (2026-08-21, founder report "first frame arrives then the
    /// next frame never comes"): region-scoped incremental requests parked in
    /// the pipeline describe the viewport as it was when they were sent. When
    /// damage lands outside them the server holds every parked request, no
    /// response is consumed, the old code never refilled, and the session
    /// deadlocked. Live-measured on real Screen Sharing: with damage driven
    /// outside the region, 7 of 8 receives were held. A held region request
    /// must therefore widen to a full-frame request, which costs nothing on a
    /// quiet screen (a full incremental request also just holds).
    func testHeldPipelinedRegionRequestWidensToFullFrameRequest() throws {
        let source = FakePipelinedFramebufferUpdateSource(
            firstFrame: Self.framebuffer(red: 255),
            receivedResults: [
                Self.idleResult(),
                Self.contentResult(red: 20)
            ]
        )
        let pump = RFBFramePump(source: source)

        _ = try pump.run(
            configuration: RFBFramePumpConfiguration(
                maxFrames: 3,
                requestRegion: RFBFramebufferUpdateRegion(x: 0, y: 0, width: 1, height: 1),
                requestPipelineDepth: 2
            )
        ) { _ in .continue }

        XCTAssertTrue(
            source.sentRegions.contains(where: { $0 == nil }),
            "A held region request must widen to a full-frame request so damage "
                + "outside a stale viewport region cannot deadlock the stream"
        )
        XCTAssertGreaterThan(
            pump.pipelinedRegionWidenedRequestCount,
            0,
            "The widen must be observable without a debugger"
        )
    }

    /// The gate that was missing on 2026-08-21 (founder: "the first frame
    /// arrives and then the next frame never comes"). It asserts the invariant
    /// the user actually feels — frames keep arriving while interacting — over
    /// a *region-aware* fake, driven through `nextFrame` with a changing
    /// region exactly as the app model drives it. A pan moves both the
    /// viewport region and the damage; the pump must not stay parked on the
    /// region the user already left.
    func testStreamStaysLiveWhenAPanMovesBothTheRegionAndTheDamage() throws {
        let regionA = RFBFramebufferUpdateRegion(x: 0, y: 0, width: 100, height: 100)
        let regionB = RFBFramebufferUpdateRegion(x: 400, y: 400, width: 100, height: 100)
        let source = FakeRegionAwarePipelinedSource(
            firstFrame: Self.framebuffer(red: 255),
            damageRect: RFBFrameDamageRect(x: 10, y: 10, width: 4, height: 4)
        )
        let pump = RFBFramePump(source: source)

        func tick(region: RFBFramebufferUpdateRegion?) throws -> RFBFramePumpFrame? {
            try pump.nextFrame(
                requestTimeout: 1,
                updateMode: .requestResponse,
                requestRegion: region,
                initialRequestRegion: nil,
                requestPipelineDepth: 3
            )
        }

        _ = try tick(region: nil)
        for _ in 0..<3 {
            _ = try tick(region: regionA)
        }
        let answeredBeforePan = source.answeredCount
        XCTAssertGreaterThan(answeredBeforePan, 0, "Fake never answered in-region damage")

        // The pan: the user is now looking at region B and that is where the
        // screen changes. The requests parked for region A can never be
        // answered again.
        source.moveDamage(to: RFBFrameDamageRect(x: 420, y: 420, width: 4, height: 4))

        var contentFramesAfterPan = 0
        for _ in 0..<6 {
            if let frame = try tick(region: regionB),
               frame.isIncremental,
               !frame.transportIdleTimedOut {
                contentFramesAfterPan += 1
            }
        }

        XCTAssertGreaterThan(
            contentFramesAfterPan,
            0,
            "The stream went dead after a pan: the pump stayed parked on the "
                + "region the user left, so damage in the new viewport never "
                + "produced a frame"
        )
    }

    func testDepthOneDoesNotUsePipelinedSendPath() throws {
        let source = FakePipelinedFramebufferUpdateSource(
            firstFrame: Self.framebuffer(red: 255),
            receivedResults: [Self.contentResult(red: 10)]
        )
        let pump = RFBFramePump(source: source)

        _ = try pump.run(
            configuration: RFBFramePumpConfiguration(maxFrames: 2, requestPipelineDepth: 1)
        ) { _ in .continue }

        // Depth 1 keeps the classic coupled request/response path, so the
        // fire-and-forget send primitive is never used.
        XCTAssertEqual(source.sentIncrementalRequestCount, 0)
    }

    private static func framebuffer(red: UInt8) -> RFBRawFramebuffer {
        RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: red, green: 0, blue: 0)
        )
    }

    private static func contentResult(red: UInt8) -> RFBFramebufferUpdateResult {
        RFBFramebufferUpdateResult(
            framebuffer: framebuffer(red: red),
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
            changedPixelCount: 1
        )
    }

    private static func idleResult() -> RFBFramebufferUpdateResult {
        RFBFramebufferUpdateResult(
            framebuffer: framebuffer(red: 0),
            dirtyRectangles: [],
            changedPixelCount: 0,
            transportIdleTimedOut: true
        )
    }
}

/// Source that only exposes the request/response *send* primitive plus the
/// ContinuousUpdates-style receive boundary — the exact capability shape
/// `RFBNetworkClient` presents — so the pump's pipelined request/response
/// path can be exercised in isolation.
private final class FakePipelinedFramebufferUpdateSource:
    RFBFramebufferUpdating,
    RFBFramebufferUpdateRequestSending,
    RFBContinuousFramebufferUpdateReceiving
{
    enum Error: Swift.Error { case noFirstFrame, noReceivedFrame }

    private struct State {
        var frame: RFBRawFramebuffer
        var receivedResults: [RFBFramebufferUpdateResult]
        var sentIncrementalFlags: [Bool] = []
        var sentRegions: [RFBFramebufferUpdateRegion?] = []
        var continuousReceiveCount = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(firstFrame: RFBRawFramebuffer, receivedResults: [RFBFramebufferUpdateResult]) {
        self.state = OSAllocatedUnfairLock(
            initialState: State(frame: firstFrame, receivedResults: receivedResults)
        )
    }

    var sentIncrementalRequestCount: Int {
        state.withLock { $0.sentIncrementalFlags.count }
    }

    var sentRequestsAllIncremental: Bool {
        state.withLock { $0.sentIncrementalFlags.allSatisfy { $0 } }
    }

    var continuousReceiveCount: Int {
        state.withLock { $0.continuousReceiveCount }
    }

    var sentRegions: [RFBFramebufferUpdateRegion?] {
        state.withLock { $0.sentRegions }
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        // Serves the coupled request/response path (first frame, and any
        // depth-1 incremental that bypasses the pipelined send primitive).
        state.withLock { $0.frame }
    }

    func sendFramebufferUpdateRequest(
        incremental: Bool,
        timeout: TimeInterval,
        region: RFBFramebufferUpdateRegion?
    ) throws {
        state.withLock {
            $0.sentIncrementalFlags.append(incremental)
            $0.sentRegions.append(region)
        }
    }

    func receiveFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult {
        try receiveContinuousFramebufferUpdate(timeout: timeout)
    }

    func receiveContinuousFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult {
        try state.withLock { state in
            state.continuousReceiveCount += 1
            guard !state.receivedResults.isEmpty else {
                throw Error.noReceivedFrame
            }
            return state.receivedResults.removeFirst()
        }
    }
}

private final class FakeRegionFramebufferUpdateSource: RFBRegionFramebufferUpdating {
    enum Error: Swift.Error, Equatable {
        case noFrame
    }

    private struct State {
        var results: [RFBFramebufferUpdateResult]
        var incrementalFlags: [Bool] = []
        var regions: [RFBFramebufferUpdateRegion?] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(results: [RFBFramebufferUpdateResult]) {
        self.state = OSAllocatedUnfairLock(initialState: State(results: results))
    }

    var requestedIncrementalFlags: [Bool] {
        state.withLock { $0.incrementalFlags }
    }

    var requestedRegions: [RFBFramebufferUpdateRegion?] {
        state.withLock { $0.regions }
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        try requestFramebufferUpdate(
            incremental: incremental,
            timeout: timeout
        ).framebuffer
    }

    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBFramebufferUpdateResult {
        try requestFramebufferUpdate(
            incremental: incremental,
            timeout: timeout,
            region: nil
        )
    }

    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval,
        region: RFBFramebufferUpdateRegion?
    ) throws -> RFBFramebufferUpdateResult {
        try state.withLock { state in
            state.incrementalFlags.append(incremental)
            state.regions.append(region)
            guard !state.results.isEmpty else {
                throw Error.noFrame
            }
            return state.results.removeFirst()
        }
    }
}

private final class FakeFramebufferUpdateSource: RFBFramebufferUpdating {
    enum Error: Swift.Error, Equatable {
        case noFrame
    }

    private struct State {
        var framebuffers: [RFBRawFramebuffer]
        var incrementalFlags: [Bool] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(framebuffers: [RFBRawFramebuffer]) {
        self.state = OSAllocatedUnfairLock(initialState: State(framebuffers: framebuffers))
    }

    var requestedIncrementalFlags: [Bool] {
        state.withLock { $0.incrementalFlags }
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        try state.withLock { state in
            state.incrementalFlags.append(incremental)
            guard !state.framebuffers.isEmpty else {
                throw Error.noFrame
            }
            return state.framebuffers.removeFirst()
        }
    }
}

private final class FakeDamageTrackingFramebufferUpdateSource: RFBDamageTrackingFramebufferUpdating {
    enum Error: Swift.Error, Equatable {
        case noFrame
    }

    private struct State {
        var results: [RFBFramebufferUpdateResult]
        var incrementalFlags: [Bool] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(results: [RFBFramebufferUpdateResult]) {
        self.state = OSAllocatedUnfairLock(initialState: State(results: results))
    }

    var requestedIncrementalFlags: [Bool] {
        state.withLock { $0.incrementalFlags }
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        try requestFramebufferUpdate(
            incremental: incremental,
            timeout: timeout
        ).framebuffer
    }

    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBFramebufferUpdateResult {
        try state.withLock { state in
            state.incrementalFlags.append(incremental)
            guard !state.results.isEmpty else {
                throw Error.noFrame
            }
            return state.results.removeFirst()
        }
    }
}

private final class FakeContinuousFramebufferUpdateSource: RFBDamageTrackingFramebufferUpdating, RFBFramebufferUpdateReceiving, RFBTransportControlClient, RFBContinuousUpdateCapabilityReporting {
    enum Error: Swift.Error, Equatable {
        case noRequestedFrame
        case noReceivedFrame
    }

    private struct State {
        var requestedResults: [RFBFramebufferUpdateResult]
        var receivedResults: [RFBFramebufferUpdateResult]
        var incrementalFlags: [Bool] = []
        var receivedFrameCount = 0
        var enableContinuousUpdatesCallCount = 0
        var disableContinuousUpdatesCallCount = 0
        var continuousUpdatesEnabledFlags: [Bool] = []
        var continuousUpdatesRegions: [RFBFramebufferUpdateRegion?] = []
        var canEnableContinuousUpdates: Bool
    }

    private let state: OSAllocatedUnfairLock<State>

    init(
        requestedResults: [RFBFramebufferUpdateResult],
        receivedResults: [RFBFramebufferUpdateResult],
        canEnableContinuousUpdates: Bool = true
    ) {
        self.state = OSAllocatedUnfairLock(
            initialState: State(
                requestedResults: requestedResults,
                receivedResults: receivedResults,
                canEnableContinuousUpdates: canEnableContinuousUpdates
            )
        )
    }

    var canEnableContinuousUpdates: Bool {
        state.withLock { $0.canEnableContinuousUpdates }
    }

    var requestedIncrementalFlags: [Bool] {
        state.withLock { $0.incrementalFlags }
    }

    var receivedFrameCount: Int {
        state.withLock { $0.receivedFrameCount }
    }

    var enableContinuousUpdatesCallCount: Int {
        state.withLock { $0.enableContinuousUpdatesCallCount }
    }

    var disableContinuousUpdatesCallCount: Int {
        state.withLock { $0.disableContinuousUpdatesCallCount }
    }

    var continuousUpdatesEnabledFlags: [Bool] {
        state.withLock { $0.continuousUpdatesEnabledFlags }
    }

    var continuousUpdatesRegions: [RFBFramebufferUpdateRegion?] {
        state.withLock { $0.continuousUpdatesRegions }
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        try requestFramebufferUpdate(
            incremental: incremental,
            timeout: timeout
        ).framebuffer
    }

    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBFramebufferUpdateResult {
        try state.withLock { state in
            state.incrementalFlags.append(incremental)
            guard !state.requestedResults.isEmpty else {
                throw Error.noRequestedFrame
            }
            return state.requestedResults.removeFirst()
        }
    }

    func receiveFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult {
        try state.withLock { state in
            state.receivedFrameCount += 1
            guard !state.receivedResults.isEmpty else {
                throw Error.noReceivedFrame
            }
            return state.receivedResults.removeFirst()
        }
    }

    func renegotiateEncodings(
        _ preference: RFBEncodingPreference,
        timeout: TimeInterval
    ) throws {}

    func enableContinuousUpdates(
        _ enabled: Bool,
        region: RFBFramebufferUpdateRegion?,
        timeout: TimeInterval
    ) throws {
        state.withLock { state in
            state.continuousUpdatesEnabledFlags.append(enabled)
            state.continuousUpdatesRegions.append(region)
            if enabled {
                state.enableContinuousUpdatesCallCount += 1
            } else {
                state.disableContinuousUpdatesCallCount += 1
            }
        }
    }

    func sendFence(
        flags: RFBFenceFlags,
        payload: Data,
        timeout: TimeInterval
    ) throws {}
}

/// Region-aware fake server: models the RFB rule the old fakes ignored — a
/// `FramebufferUpdateRequest` is answered only by damage that lands inside
/// *its own* region, and is otherwise held. Without this rule a fake happily
/// answers requests carrying a stale region, which is exactly why the
/// 2026-08-21 freeze (parked requests describing an area the user had already
/// panned away from) passed every unit and simulator gate and had to be found
/// on a real device.
private final class FakeRegionAwarePipelinedSource:
    RFBFramebufferUpdating,
    RFBFramebufferUpdateRequestSending,
    RFBContinuousFramebufferUpdateReceiving
{
    private struct ParkedRequest {
        var region: RFBFramebufferUpdateRegion?
    }

    private struct State {
        var frame: RFBRawFramebuffer
        /// Where the next change happens. Damage outside a parked request's
        /// region cannot satisfy it.
        var damageRect: RFBFrameDamageRect
        var parked: [ParkedRequest] = []
        var answeredCount = 0
        var heldCount = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(firstFrame: RFBRawFramebuffer, damageRect: RFBFrameDamageRect) {
        self.state = OSAllocatedUnfairLock(
            initialState: State(frame: firstFrame, damageRect: damageRect)
        )
    }

    func moveDamage(to rect: RFBFrameDamageRect) {
        state.withLock { $0.damageRect = rect }
    }

    var answeredCount: Int { state.withLock { $0.answeredCount } }
    var heldCount: Int { state.withLock { $0.heldCount } }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        state.withLock { $0.frame }
    }

    func sendFramebufferUpdateRequest(
        incremental: Bool,
        timeout: TimeInterval,
        region: RFBFramebufferUpdateRegion?
    ) throws {
        state.withLock { $0.parked.append(ParkedRequest(region: region)) }
    }

    func receiveFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult {
        try receiveContinuousFramebufferUpdate(timeout: timeout)
    }

    func receiveContinuousFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult {
        state.withLock { state in
            let damage = state.damageRect
            let satisfiableIndex = state.parked.firstIndex { parked in
                guard let region = parked.region else {
                    // A full-frame request is satisfied by damage anywhere.
                    return true
                }
                return Self.intersects(region: region, damage: damage)
            }

            guard let satisfiableIndex else {
                state.heldCount += 1
                return RFBFramebufferUpdateResult(
                    framebuffer: state.frame,
                    dirtyRectangles: [],
                    changedPixelCount: 0,
                    transportIdleTimedOut: true
                )
            }

            state.parked.remove(at: satisfiableIndex)
            state.answeredCount += 1
            return RFBFramebufferUpdateResult(
                framebuffer: state.frame,
                dirtyRectangles: [damage],
                changedPixelCount: max(damage.width * damage.height, 1),
                transportIdleTimedOut: false
            )
        }
    }

    private static func intersects(
        region: RFBFramebufferUpdateRegion,
        damage: RFBFrameDamageRect
    ) -> Bool {
        region.x < damage.x + damage.width
            && damage.x < region.x + region.width
            && region.y < damage.y + damage.height
            && damage.y < region.y + region.height
    }
}
