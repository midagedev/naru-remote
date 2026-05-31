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
        let result = RFBFramebufferUpdateResult(
            framebuffer: RFBRawFramebuffer(width: 100, height: 100),
            dirtyRectangles: [
                RFBFrameDamageRect(x: 10, y: 10, width: 30, height: 30)
            ],
            changedPixelCount: 1_000,
            capturedAt: capturedAt
        )
        let source = FakeDamageTrackingFramebufferUpdateSource(results: [result])
        let pump = RFBFramePump(source: source)

        let frame = try XCTUnwrap(pump.nextFrame())

        XCTAssertEqual(source.requestedIncrementalFlags, [false])
        XCTAssertEqual(frame.dirtyRectangles, result.dirtyRectangles)
        XCTAssertEqual(frame.changedPixelCount, 1_000)
        XCTAssertEqual(frame.changeActivity, .moderate)
        XCTAssertEqual(frame.capturedAt, capturedAt)
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

    private static func framebuffer(red: UInt8) -> RFBRawFramebuffer {
        RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: red, green: 0, blue: 0)
        )
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
