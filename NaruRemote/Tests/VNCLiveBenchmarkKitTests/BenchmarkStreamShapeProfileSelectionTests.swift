import XCTest
import NaruRemoteCore
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeProfileSelectionTests: XCTestCase {
    func testUsageDescriptionIncludesCoreMatrixSelection() {
        XCTAssertEqual(
            BenchmarkStreamShapeProfileSelection.usageDescription(
                allProfileLabels: ["local-low-latency", "tight-first"]
            ),
            "local-low-latency|core-matrix|zrle-isolation|pixel-format-isolation|"
                + "app-low-traffic|all|comma-separated labels (local-low-latency,tight-first)"
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

    func testZrleIsolationSelectsExtensionProfilesInOrder() throws {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: " zrle-isolation ",
            allProfileLabels: [
                "local-low-latency",
                "zrle-compression-0",
                "zrle-compression-0-cursor",
                "zrle-compression-0-clipboard",
                "zrle-compression-0-cursor-clipboard",
                "tight-first"
            ]
        )

        XCTAssertEqual(
            labels,
            [
                "local-low-latency",
                "zrle-compression-0",
                "zrle-compression-0-cursor",
                "zrle-compression-0-clipboard",
                "zrle-compression-0-cursor-clipboard"
            ]
        )
    }

    func testZrleIsolationThrowsWhenAnExtensionProfileIsMissing() {
        XCTAssertThrowsError(
            try BenchmarkStreamShapeProfileSelection.selectedLabels(
                from: "zrle-isolation",
                allProfileLabels: [
                    "local-low-latency",
                    "zrle-compression-0",
                    "zrle-compression-0-cursor",
                    "zrle-compression-0-clipboard"
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkStreamShapeProfileSelectionError,
                .missingZrleIsolationLabels(["zrle-compression-0-cursor-clipboard"])
            )
            XCTAssertEqual(
                (error as? BenchmarkStreamShapeProfileSelectionError)?.message,
                "zrle-isolation stream-shape profile selection is unavailable because "
                    + "required profile label(s) are missing: zrle-compression-0-cursor-clipboard."
            )
        }
    }

    func testPixelFormatIsolationSelectsFullColorAndRGB565Pairs() throws {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: " pixel-format-isolation ",
            allProfileLabels: [
                "local-low-latency",
                "local-low-latency-rgb565",
                "tight-first",
                "tight-first-rgb565",
                "zrle-compression-0",
                "zrle-compression-0-rgb565",
                "adaptive-good-full"
            ]
        )

        XCTAssertEqual(
            labels,
            [
                "local-low-latency",
                "local-low-latency-rgb565",
                "tight-first",
                "tight-first-rgb565",
                "zrle-compression-0",
                "zrle-compression-0-rgb565"
            ]
        )
    }

    func testPixelFormatIsolationIncludesAppLowTrafficStreamEncodingLabel() throws {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: "pixel-format-isolation",
            allProfileLabels: [
                "local-low-latency",
                StreamEncodingMode.localLowLatencyRGB565.rawValue,
                "tight-first",
                "tight-first-rgb565",
                StreamEncodingMode.zrleCompressionZero.rawValue,
                StreamEncodingMode.zrleCompressionZeroRGB565.rawValue
            ]
        )

        XCTAssertTrue(labels.contains(StreamEncodingMode.localLowLatencyRGB565.rawValue))
        XCTAssertTrue(labels.contains(StreamEncodingMode.zrleCompressionZero.rawValue))
        XCTAssertTrue(labels.contains(StreamEncodingMode.zrleCompressionZeroRGB565.rawValue))
    }

    func testAppLowTrafficSelectsAppRGB565LowTrafficLabels() throws {
        let labels = try BenchmarkStreamShapeProfileSelection.selectedLabels(
            from: " app-low-traffic ",
            allProfileLabels: [
                "local-low-latency",
                StreamEncodingMode.localLowLatencyRGB565.rawValue,
                StreamEncodingMode.zrleCompressionZero.rawValue,
                StreamEncodingMode.zrleCompressionZeroRGB565.rawValue,
                "adaptive-good-full"
            ]
        )

        XCTAssertEqual(
            labels,
            [
                StreamEncodingMode.localLowLatencyRGB565.rawValue,
                StreamEncodingMode.zrleCompressionZeroRGB565.rawValue
            ]
        )
    }

    func testAppLowTrafficThrowsWhenProfileIsMissing() {
        XCTAssertThrowsError(
            try BenchmarkStreamShapeProfileSelection.selectedLabels(
                from: "app-low-traffic",
                allProfileLabels: [
                    "local-low-latency",
                    StreamEncodingMode.zrleCompressionZero.rawValue
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkStreamShapeProfileSelectionError,
                .missingAppLowTrafficLabels([
                    StreamEncodingMode.localLowLatencyRGB565.rawValue,
                    StreamEncodingMode.zrleCompressionZeroRGB565.rawValue
                ])
            )
            XCTAssertEqual(
                (error as? BenchmarkStreamShapeProfileSelectionError)?.message,
                "app-low-traffic stream-shape profile selection is unavailable because "
                    + "required profile label(s) are missing: "
                    + "local-low-latency-rgb565, zrle-compression-0-rgb565."
            )
        }
    }

    func testPixelFormatIsolationThrowsWhenAPairProfileIsMissing() {
        XCTAssertThrowsError(
            try BenchmarkStreamShapeProfileSelection.selectedLabels(
                from: "pixel-format-isolation",
                allProfileLabels: [
                    "local-low-latency",
                    "local-low-latency-rgb565",
                    "tight-first",
                    "zrle-compression-0"
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkStreamShapeProfileSelectionError,
                .missingPixelFormatIsolationLabels([
                    "tight-first-rgb565",
                    "zrle-compression-0-rgb565"
                ])
            )
            XCTAssertEqual(
                (error as? BenchmarkStreamShapeProfileSelectionError)?.message,
                "pixel-format-isolation stream-shape profile selection is unavailable because "
                    + "required profile label(s) are missing: tight-first-rgb565, "
                    + "zrle-compression-0-rgb565."
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
