import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeProfileSelectionTests: XCTestCase {
    func testUsageDescriptionIncludesCoreMatrixSelection() {
        XCTAssertEqual(
            BenchmarkStreamShapeProfileSelection.usageDescription(
                allProfileLabels: ["local-low-latency", "tight-first"]
            ),
            "local-low-latency|core-matrix|all|comma-separated labels (local-low-latency,tight-first)"
        )
    }

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

    func testCoreMatrixSelectsStableCandidateProfilesInOrder() throws {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: " core-matrix ",
            allProfileLabels: [
                "local-low-latency",
                "tight-first",
                "zrle-compression-0",
                "adaptive-good-full",
                "adaptive-poor-full"
            ]
        )

        XCTAssertEqual(
            labels,
            [
                "local-low-latency",
                "zrle-compression-0",
                "tight-first",
                "adaptive-good-full"
            ]
        )
    }

    func testCoreMatrixThrowsWhenACandidateProfileIsMissing() {
        XCTAssertThrowsError(
            try BenchmarkStreamShapeProfileSelection.selectedLabels(
                from: "core-matrix",
                allProfileLabels: [
                    "local-low-latency",
                    "tight-first",
                    "adaptive-good-full"
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkStreamShapeProfileSelectionError,
                .missingCoreMatrixLabels(["zrle-compression-0"])
            )
            XCTAssertEqual(
                (error as? BenchmarkStreamShapeProfileSelectionError)?.message,
                "core-matrix stream-shape profile selection is unavailable because "
                    + "required profile label(s) are missing: zrle-compression-0."
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
