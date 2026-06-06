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

    private static func framebuffer(red: UInt8) -> RFBRawFramebuffer {
        RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: red, green: 0, blue: 0)
        )
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
