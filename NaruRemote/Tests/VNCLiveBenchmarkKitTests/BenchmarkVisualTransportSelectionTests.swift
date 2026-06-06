import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkVisualTransportSelectionTests: XCTestCase {
    func testUsageDescriptionUsesFixedLabels() {
        XCTAssertEqual(
            BenchmarkVisualTransportSelection.usageDescription,
            "vnc|helper-video|all|comma-separated labels (vnc,helper-video)"
        )
    }

    func testParseVNCAndHelperVideoSelectionInStableOrder() throws {
        let selection = try BenchmarkVisualTransportSelection.parse(" helper-video, vnc,helper-video ")

        XCTAssertEqual(selection.rawValue, "vnc,helper-video")
        XCTAssertEqual(selection.transports, [.vnc, .helperVideo])
    }

    func testParseAllSelectsEveryKnownVisualTransport() throws {
        let selection = try BenchmarkVisualTransportSelection.parse("all")

        XCTAssertEqual(selection.rawValue, "vnc,helper-video")
        XCTAssertEqual(selection.transports, BenchmarkVisualTransport.allCases)
    }

    func testParseRejectsUnknownVisualTransportLabel() {
        XCTAssertThrowsError(
            try BenchmarkVisualTransportSelection.parse("vnc,screen-stream")
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkVisualTransportSelectionError,
                .unknownLabels(["screen-stream"])
            )
            XCTAssertEqual(
                (error as? BenchmarkVisualTransportSelectionError)?.message,
                "visual-transport contains unknown label(s): screen-stream."
            )
        }
    }

    func testParseRejectsEmptyVisualTransportSelection() {
        XCTAssertThrowsError(
            try BenchmarkVisualTransportSelection.parse(" , ")
        ) { error in
            XCTAssertEqual(error as? BenchmarkVisualTransportSelectionError, .emptySelection)
            XCTAssertEqual(
                (error as? BenchmarkVisualTransportSelectionError)?.message,
                "visual-transport must include at least one label."
            )
        }
    }
}
