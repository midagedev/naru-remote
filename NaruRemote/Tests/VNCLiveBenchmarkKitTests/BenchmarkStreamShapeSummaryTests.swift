import XCTest
import NaruRemoteCore
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeSummaryTests: XCTestCase {
    func testDisabledWhenRequestedSamplesIsZero() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 0,
            samples: [],
            elapsedMilliseconds: nil,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        XCTAssertEqual(summary.status, .disabled)
        XCTAssertEqual(summary.receivedSamples, 0)
        XCTAssertNil(summary.deliveredFramesPerSecond)
    }

    func testContentAndEmptySamplesProduceMixedSummary() throws {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 3,
            samples: [
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 30,
                    dirtyRectangleCount: 2,
                    dirtyAreaPermille: 120,
                    changedPixelsPermille: 90,
                    rendererUploadStrategy: .partial,
                    rendererUploadRegionCount: 2,
                    receiveTotalMilliseconds: 25,
                    networkReadMilliseconds: 20,
                    clientProcessingMilliseconds: 5,
                    actualEncodingMix: RFBFramebufferEncodingMix(tightRectangles: 1, cursorRectangles: 1)
                ),
                BenchmarkStreamShapeSample(
                    kind: .emptyUpdate,
                    durationMilliseconds: 50,
                    dirtyRectangleCount: 0,
                    dirtyAreaPermille: 0,
                    changedPixelsPermille: 0,
                    receiveTotalMilliseconds: 48,
                    networkReadMilliseconds: 47,
                    clientProcessingMilliseconds: 1,
                    actualEncodingMix: RFBFramebufferEncodingMix(rawRectangles: 1)
                )
            ],
            elapsedMilliseconds: 100,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            adaptiveClientPressurePacingSamples: 1,
            viewportInteractionPacingSamples: 2
        )

        XCTAssertEqual(summary.status, .mixedUpdates)
        XCTAssertEqual(summary.receivedSamples, 2)
        XCTAssertEqual(summary.emptyUpdateSamples, 1)
        XCTAssertEqual(summary.contentUpdateSamples, 1)
        XCTAssertEqual(summary.deliveredFramesPerSecond, 20)
        XCTAssertEqual(summary.contentFramesPerSecond, 10)
        XCTAssertEqual(try XCTUnwrap(summary.updateLatency).averageMilliseconds, 40)
        XCTAssertEqual(try XCTUnwrap(summary.dirtyRectangleCount).maxMilliseconds, 2)
        XCTAssertEqual(try XCTUnwrap(summary.dirtyAreaPermille).maxMilliseconds, 120)
        XCTAssertEqual(try XCTUnwrap(summary.changedPixelsPermille).maxMilliseconds, 90)
        XCTAssertEqual(try XCTUnwrap(summary.receiveTotalLatency).averageMilliseconds, 36)
        XCTAssertEqual(try XCTUnwrap(summary.networkReadLatency).averageMilliseconds, 33)
        XCTAssertEqual(try XCTUnwrap(summary.clientProcessingLatency).maxMilliseconds, 5)
        XCTAssertEqual(summary.tailLatency.slowUpdateSamples, 0)
        XCTAssertEqual(summary.tailLatency.verySlowUpdateSamples, 0)
        XCTAssertEqual(summary.rendererUploadSampleCount, 1)
        XCTAssertEqual(summary.rendererPartialUploadSamples, 1)
        XCTAssertEqual(summary.rendererFullUploadSamples, 0)
        XCTAssertEqual(summary.rendererPartialUploadPermille, 1_000)
        XCTAssertEqual(summary.rendererFullUploadPermille, 0)
        XCTAssertEqual(try XCTUnwrap(summary.rendererUploadRegionCount).maxMilliseconds, 2)
        XCTAssertEqual(summary.adaptiveClientPressurePacingSamples, 1)
        XCTAssertEqual(summary.adaptiveClientPressurePacingPermille, 500)
        XCTAssertEqual(summary.viewportInteractionPacingSamples, 2)
        XCTAssertEqual(summary.viewportInteractionPacingPermille, 1_000)
        XCTAssertEqual(summary.actualEncodingMix.rawRectangles, 1)
        XCTAssertEqual(summary.actualEncodingMix.tightRectangles, 1)
        XCTAssertEqual(summary.actualEncodingMix.cursorRectangles, 1)
        XCTAssertEqual(summary.actualEncodingMix.totalRectangles, 3)
    }

    func testTimeoutWithoutSamplesReportsNoUpdateBeforeTimeout() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 4,
            samples: [],
            elapsedMilliseconds: 750,
            firstTimeoutMilliseconds: 750,
            failureLabel: nil
        )

        XCTAssertEqual(summary.status, .noUpdateBeforeTimeout)
        XCTAssertEqual(summary.timedOutSamples, 1)
        XCTAssertEqual(summary.deliveredFramesPerSecond, 0)
        XCTAssertEqual(summary.contentFramesPerSecond, 0)
        XCTAssertEqual(summary.firstTimeoutMilliseconds, 750)
    }

    func testFailureOverridesObservedSamples() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 2,
            samples: [
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 10,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 20,
                    changedPixelsPermille: 20
                )
            ],
            elapsedMilliseconds: 20,
            firstTimeoutMilliseconds: nil,
            failureLabel: "connection-failed"
        )

        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.failureLabel, "connection-failed")
    }

    func testSamplesClampNegativeAndOversizedValues() {
        let sample = BenchmarkStreamShapeSample(
            kind: .contentUpdate,
            durationMilliseconds: -1,
            dirtyRectangleCount: -2,
            dirtyAreaPermille: 1_500,
            changedPixelsPermille: -100,
            rendererUploadStrategy: .partial,
            rendererUploadRegionCount: -3,
            receiveTotalMilliseconds: -4,
            networkReadMilliseconds: -5,
            clientProcessingMilliseconds: -6
        )

        XCTAssertEqual(sample.durationMilliseconds, 0)
        XCTAssertEqual(sample.dirtyRectangleCount, 0)
        XCTAssertEqual(sample.dirtyAreaPermille, 1_000)
        XCTAssertEqual(sample.changedPixelsPermille, 0)
        XCTAssertEqual(sample.rendererUploadRegionCount, 0)
        XCTAssertEqual(sample.receiveTotalMilliseconds, 0)
        XCTAssertEqual(sample.networkReadMilliseconds, 0)
        XCTAssertEqual(sample.clientProcessingMilliseconds, 0)
    }

    func testAdaptiveClientPressurePacingSamplesClampToReceivedSamples() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 1,
            samples: [
                streamShapeSample(duration: 10)
            ],
            elapsedMilliseconds: 10,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            adaptiveClientPressurePacingSamples: 4
        )

        XCTAssertEqual(summary.adaptiveClientPressurePacingSamples, 1)
        XCTAssertEqual(summary.adaptiveClientPressurePacingPermille, 1_000)
    }

    func testViewportInteractionPacingSamplesClampToReceivedSamples() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 1,
            samples: [
                streamShapeSample(duration: 10)
            ],
            elapsedMilliseconds: 10,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            viewportInteractionPacingSamples: 4
        )

        XCTAssertEqual(summary.viewportInteractionPacingSamples, 1)
        XCTAssertEqual(summary.viewportInteractionPacingPermille, 1_000)
    }

    func testTailLatencySummaryCorrelatesSlowSamplesWithDirtyAndUploadBuckets() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 4,
            samples: [
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 249,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 1000,
                    changedPixelsPermille: 1000,
                    rendererUploadStrategy: .full,
                    rendererUploadRegionCount: 1
                ),
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 250,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 1000,
                    changedPixelsPermille: 5,
                    rendererUploadStrategy: .partial,
                    rendererUploadRegionCount: 1
                ),
                BenchmarkStreamShapeSample(
                    kind: .emptyUpdate,
                    durationMilliseconds: 300,
                    dirtyRectangleCount: 0,
                    dirtyAreaPermille: 0,
                    changedPixelsPermille: 0
                ),
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 1_000,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 1000,
                    changedPixelsPermille: 1000,
                    rendererUploadStrategy: .full,
                    rendererUploadRegionCount: 1
                )
            ],
            elapsedMilliseconds: 1_800,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        XCTAssertEqual(summary.tailLatency.slowUpdateThresholdMilliseconds, 250)
        XCTAssertEqual(summary.tailLatency.verySlowUpdateThresholdMilliseconds, 1_000)
        XCTAssertEqual(summary.tailLatency.slowUpdateSamples, 3)
        XCTAssertEqual(summary.tailLatency.slowContentUpdateSamples, 2)
        XCTAssertEqual(summary.tailLatency.slowFullDirtyAreaSamples, 2)
        XCTAssertEqual(summary.tailLatency.slowRendererFullUploadSamples, 1)
        XCTAssertEqual(summary.tailLatency.verySlowUpdateSamples, 1)
    }

    func testProfileReportRoundTripsThroughJSON() throws {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 1,
            samples: [
                BenchmarkStreamShapeSample(
                    kind: .emptyUpdate,
                    durationMilliseconds: 12,
                    dirtyRectangleCount: 0,
                    dirtyAreaPermille: 0,
                    changedPixelsPermille: 0
                )
            ],
            elapsedMilliseconds: 33,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )
        let report = BenchmarkStreamShapeProfileReport(
            label: "local-low-latency",
            transportMode: .continuousUpdates,
            firstFrameMilliseconds: 1_234,
            summary: summary
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkStreamShapeProfileReport.self, from: encoded)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.transportMode, .continuousUpdates)
    }

    func testStreamShapeDecodesLegacyPayloadWithoutActualEncodingMix() throws {
        let sample = BenchmarkStreamShapeSample(
            kind: .contentUpdate,
            durationMilliseconds: 12,
            dirtyRectangleCount: 1,
            dirtyAreaPermille: 100,
            changedPixelsPermille: 50,
            rendererUploadStrategy: .partial,
            rendererUploadRegionCount: 1,
            actualEncodingMix: RFBFramebufferEncodingMix(tightRectangles: 1)
        )
        let legacySampleData = try Self.encodedPayloadRemovingActualEncodingMix(from: sample)
        let decodedSample = try JSONDecoder().decode(BenchmarkStreamShapeSample.self, from: legacySampleData)

        XCTAssertEqual(decodedSample.actualEncodingMix, RFBFramebufferEncodingMix())

        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 1,
            samples: [sample],
            elapsedMilliseconds: 12,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )
        let legacySummaryData = try Self.encodedPayload(
            from: summary,
            removingKeys: [
                "actualEncodingMix",
                "adaptiveClientPressurePacingSamples",
                "adaptiveClientPressurePacingPermille",
                "viewportInteractionPacingSamples",
                "viewportInteractionPacingPermille"
            ]
        )
        let decodedSummary = try JSONDecoder().decode(BenchmarkStreamShapeSummary.self, from: legacySummaryData)

        XCTAssertEqual(decodedSummary.actualEncodingMix, RFBFramebufferEncodingMix())
        XCTAssertEqual(decodedSummary.adaptiveClientPressurePacingSamples, 0)
        XCTAssertEqual(decodedSummary.adaptiveClientPressurePacingPermille, 0)
        XCTAssertEqual(decodedSummary.viewportInteractionPacingSamples, 0)
        XCTAssertEqual(decodedSummary.viewportInteractionPacingPermille, 0)
        XCTAssertEqual(decodedSummary.receivedSamples, 1)
    }

    func testRecommendationPicksLowestAverageRequestResponseLatency() throws {
        let local = BenchmarkStreamShapeProfileReport(
            label: "local-low-latency",
            firstFrameMilliseconds: 3_041,
            summary: BenchmarkStreamShapeSummary(
                requestedSamples: 3,
                samples: [
                    streamShapeSample(duration: 34, rendererUploadStrategy: .partial),
                    streamShapeSample(duration: 475, rendererUploadStrategy: .full),
                    streamShapeSample(duration: 250, kind: .emptyUpdate)
                ],
                elapsedMilliseconds: 750,
                firstTimeoutMilliseconds: nil,
                failureLabel: nil
            )
        )
        let zrle = BenchmarkStreamShapeProfileReport(
            label: "zrle-compression-0",
            firstFrameMilliseconds: 3_073,
            summary: BenchmarkStreamShapeSummary(
                requestedSamples: 3,
                samples: [
                    streamShapeSample(duration: 30, rendererUploadStrategy: .partial),
                    streamShapeSample(duration: 112, rendererUploadStrategy: .partial),
                    streamShapeSample(duration: 478, kind: .emptyUpdate)
                ],
                elapsedMilliseconds: 620,
                firstTimeoutMilliseconds: nil,
                failureLabel: nil
            )
        )
        let failedContinuous = BenchmarkStreamShapeProfileReport(
            label: "continuous",
            transportMode: .continuousUpdates,
            firstFrameMilliseconds: 3_000,
            summary: BenchmarkStreamShapeSummary(
                requestedSamples: 3,
                samples: [],
                elapsedMilliseconds: 1,
                firstTimeoutMilliseconds: nil,
                failureLabel: "stream-continuous-updates-connection-failed"
            )
        )

        let recommendation = try XCTUnwrap(
            BenchmarkStreamShapeRecommendation.recommendedRequestResponseProfile(
                from: [local, zrle, failedContinuous]
            )
        )

        XCTAssertEqual(recommendation.label, "zrle-compression-0")
        XCTAssertEqual(recommendation.transportMode, .requestResponse)
        XCTAssertEqual(
            recommendation.reason,
            "lowest-average-update-latency-among-request-response-profiles"
        )
        XCTAssertEqual(recommendation.averageUpdateMilliseconds, 206)
        XCTAssertEqual(recommendation.contentUpdateSamples, 2)
        XCTAssertEqual(recommendation.rendererFullUploadPermille, 0)
    }

    func testRecommendationReturnsNilWithoutUsableRequestResponseSamples() {
        let failed = BenchmarkStreamShapeProfileReport(
            label: "local-low-latency",
            firstFrameMilliseconds: nil,
            summary: BenchmarkStreamShapeSummary(
                requestedSamples: 3,
                samples: [],
                elapsedMilliseconds: nil,
                firstTimeoutMilliseconds: nil,
                failureLabel: "connection-failed"
            )
        )

        XCTAssertNil(
            BenchmarkStreamShapeRecommendation.recommendedRequestResponseProfile(from: [failed])
        )
    }

    func testRecommendationIgnoresReportsWithoutRendererUploadAggregates() {
        let partial = BenchmarkStreamShapeProfileReport(
            label: "local-low-latency",
            firstFrameMilliseconds: 1_000,
            summary: BenchmarkStreamShapeSummary(
                requestedSamples: 1,
                samples: [
                    streamShapeSample(duration: 20)
                ],
                elapsedMilliseconds: 20,
                firstTimeoutMilliseconds: nil,
                failureLabel: nil
            )
        )

        XCTAssertNil(
            BenchmarkStreamShapeRecommendation.recommendedRequestResponseProfile(from: [partial])
        )
    }

    func testTransportModeRawValuesAreStableForBenchmarkJSON() {
        XCTAssertEqual(BenchmarkStreamShapeTransportMode.requestResponse.rawValue, "request-response")
        XCTAssertEqual(BenchmarkStreamShapeTransportMode.continuousUpdates.rawValue, "continuous-updates")
    }

    func testSummaryOmitsTimingAggregatesWhenSamplesHaveNoReceiveTiming() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 1,
            samples: [
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 10,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 1,
                    changedPixelsPermille: 1
                )
            ],
            elapsedMilliseconds: 10,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        XCTAssertNil(summary.receiveTotalLatency)
        XCTAssertNil(summary.networkReadLatency)
        XCTAssertNil(summary.clientProcessingLatency)
    }

    private func streamShapeSample(
        duration: Int,
        kind: BenchmarkStreamUpdateKind = .contentUpdate,
        rendererUploadStrategy: FramebufferUploadStrategy = .none
    ) -> BenchmarkStreamShapeSample {
        BenchmarkStreamShapeSample(
            kind: kind,
            durationMilliseconds: duration,
            dirtyRectangleCount: kind == .contentUpdate ? 1 : 0,
            dirtyAreaPermille: kind == .contentUpdate ? 1 : 0,
            changedPixelsPermille: kind == .contentUpdate ? 1 : 0,
            rendererUploadStrategy: rendererUploadStrategy,
            rendererUploadRegionCount: rendererUploadStrategy == .none ? 0 : 1
        )
    }

    private static func encodedPayloadRemovingActualEncodingMix<T: Encodable>(from value: T) throws -> Data {
        try encodedPayload(from: value, removingKeys: ["actualEncodingMix"])
    }

    private static func encodedPayload<T: Encodable>(from value: T, removingKeys keys: [String]) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in keys {
            object.removeValue(forKey: key)
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
