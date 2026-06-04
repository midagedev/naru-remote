import XCTest
@testable import NaruRemoteCore

final class ViewportRedrawDiagnosticsTests: XCTestCase {
    func testClampsGestureDiagnosticsToSafeNonNegativeValues() {
        let diagnostics = ViewportRedrawDiagnostics(
            interactionCount: -1,
            gestureSampleCount: -2,
            gestureLongFrameCount: -3,
            gestureMaxIntervalMilliseconds: -4
        )

        XCTAssertEqual(diagnostics.interactionCount, 0)
        XCTAssertEqual(diagnostics.gestureSampleCount, 0)
        XCTAssertEqual(diagnostics.gestureLongFrameCount, 0)
        XCTAssertEqual(diagnostics.gestureMaxIntervalMilliseconds, 0)
        XCTAssertFalse(diagnostics.hasSamples)
    }

    func testMergesGestureDiagnosticsAndKeepsMaxInterval() {
        var diagnostics = ViewportRedrawDiagnostics(
            interactionCount: 1,
            gestureSampleCount: 4,
            gestureLongFrameCount: 1,
            gestureMaxIntervalMilliseconds: 31
        )

        diagnostics.merge(
            ViewportRedrawDiagnostics(
                interactionCount: 2,
                gestureSampleCount: 6,
                gestureLongFrameCount: 3,
                gestureMaxIntervalMilliseconds: 18
            )
        )

        XCTAssertEqual(diagnostics.interactionCount, 3)
        XCTAssertEqual(diagnostics.gestureSampleCount, 10)
        XCTAssertEqual(diagnostics.gestureLongFrameCount, 4)
        XCTAssertEqual(diagnostics.gestureMaxIntervalMilliseconds, 31)
    }
}
