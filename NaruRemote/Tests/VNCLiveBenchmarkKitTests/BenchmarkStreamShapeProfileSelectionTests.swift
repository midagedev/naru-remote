import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeProfileSelectionTests: XCTestCase {
    func testAllSelectsEveryKnownProfileInOrder() throws {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: "all",
            allProfileLabels: ["local-low-latency", "tight-first", "zrle-first"]
        )

        XCTAssertEqual(labels, ["local-low-latency", "tight-first", "zrle-first"])
    }

    func testLocalLowLatencySelectsLocalProfileOnly() throws {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: "local-low-latency",
            allProfileLabels: ["tight-first", "local-low-latency", "zrle-first"]
        )

        XCTAssertEqual(labels, ["local-low-latency"])
    }

    func testLocalLowLatencyThrowsWhenLocalProfileIsNotKnown() {
        XCTAssertThrowsError(
            try BenchmarkStreamShapeProfileSelection.selectedLabels(
                from: "local-low-latency",
                allProfileLabels: ["tight-first", "zrle-first"]
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkStreamShapeProfileSelectionError,
                .unknownLabels(["local-low-latency"])
            )
        }
    }

    func testCommaSeparatedSelectionPreservesRequestedOrder() throws {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: " tight-first, adaptive-good-full, zrle-first ",
            allProfileLabels: [
                "local-low-latency",
                "tight-first",
                "zrle-first",
                "adaptive-good-full"
            ]
        )

        XCTAssertEqual(labels, ["tight-first", "adaptive-good-full", "zrle-first"])
    }

    func testUnknownLabelThrowsSafeCatalogError() {
        XCTAssertThrowsError(
            try BenchmarkStreamShapeProfileSelection.selectedLabels(
                from: "tight-first,nope",
                allProfileLabels: ["local-low-latency", "tight-first"]
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkStreamShapeProfileSelectionError,
                .unknownLabels(["nope"])
            )
        }
    }

    func testDuplicateLabelThrowsSafeCatalogError() {
        XCTAssertThrowsError(
            try BenchmarkStreamShapeProfileSelection.selectedLabels(
                from: "tight-first,tight-first",
                allProfileLabels: ["local-low-latency", "tight-first"]
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkStreamShapeProfileSelectionError,
                .duplicateLabels(["tight-first"])
            )
        }
    }

    func testEmptySelectionThrowsSafeCatalogError() {
        XCTAssertThrowsError(
            try BenchmarkStreamShapeProfileSelection.selectedLabels(
                from: "tight-first,",
                allProfileLabels: ["local-low-latency", "tight-first"]
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkStreamShapeProfileSelectionError,
                .emptySelection
            )
        }
    }
}
