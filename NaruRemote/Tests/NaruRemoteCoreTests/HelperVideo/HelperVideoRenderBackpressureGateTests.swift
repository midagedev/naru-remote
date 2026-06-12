import XCTest
@testable import NaruRemoteCore

final class HelperVideoRenderBackpressureGateTests: XCTestCase {
    func testBackpressuredDeltaOpensBoundedDeltaDropWindow() {
        var gate = HelperVideoRenderBackpressureGate(deltaSkipLimitAfterBackpressure: 2)

        XCTAssertEqual(gate.decision(for: .delta), .queryRendererBackpressure)
        gate.recordRendererBackpressureResult(for: .delta, shouldDrop: true)

        XCTAssertEqual(gate.decision(for: .delta), .dropDeltaWithoutQuery)
        XCTAssertEqual(gate.decision(for: .delta), .dropDeltaWithoutQuery)
        XCTAssertEqual(gate.decision(for: .delta), .queryRendererBackpressure)
    }

    func testKeyframeAndParameterSetResetDeltaDropWindow() {
        var gate = HelperVideoRenderBackpressureGate(deltaSkipLimitAfterBackpressure: 3)

        XCTAssertEqual(gate.decision(for: .delta), .queryRendererBackpressure)
        gate.recordRendererBackpressureResult(for: .delta, shouldDrop: true)
        XCTAssertEqual(gate.decision(for: .delta), .dropDeltaWithoutQuery)

        XCTAssertEqual(gate.decision(for: .keyframe), .renderWithoutQuery)
        XCTAssertEqual(gate.decision(for: .delta), .queryRendererBackpressure)

        gate.recordRendererBackpressureResult(for: .delta, shouldDrop: true)
        XCTAssertEqual(gate.decision(for: .parameterSet), .renderWithoutQuery)
        XCTAssertEqual(gate.decision(for: .delta), .queryRendererBackpressure)
    }

    func testReadyDeltaClosesDropWindow() {
        var gate = HelperVideoRenderBackpressureGate(deltaSkipLimitAfterBackpressure: 2)

        XCTAssertEqual(gate.decision(for: .delta), .queryRendererBackpressure)
        gate.recordRendererBackpressureResult(for: .delta, shouldDrop: true)
        XCTAssertEqual(gate.decision(for: .delta), .dropDeltaWithoutQuery)

        XCTAssertEqual(gate.decision(for: .delta), .dropDeltaWithoutQuery)
        XCTAssertEqual(gate.decision(for: .delta), .queryRendererBackpressure)
        gate.recordRendererBackpressureResult(for: .delta, shouldDrop: false)

        XCTAssertEqual(gate.decision(for: .delta), .queryRendererBackpressure)
    }
}
