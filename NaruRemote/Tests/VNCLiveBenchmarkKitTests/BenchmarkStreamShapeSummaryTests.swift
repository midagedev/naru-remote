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
                    zrleInflateMilliseconds: 3,
                    zrleTileApplyMilliseconds: 7,
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
            viewportInteractionPacingSamples: 2,
            viewportInteractionPausedRequestCount: 2,
            viewportInteractionPausePollCount: 24,
            viewportInteractionPausedMilliseconds: 400
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
        XCTAssertEqual(try XCTUnwrap(summary.zrleInflateLatency).averageMilliseconds, 3)
        XCTAssertEqual(try XCTUnwrap(summary.zrleTileApplyLatency).p95Milliseconds, 7)
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
        XCTAssertEqual(summary.viewportInteractionPausedRequestCount, 2)
        XCTAssertEqual(summary.viewportInteractionPausedRequestPermille, 667)
        XCTAssertEqual(summary.viewportInteractionPausePollCount, 24)
        XCTAssertEqual(summary.viewportInteractionPausedMilliseconds, 400)
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
            clientProcessingMilliseconds: -6,
            zrleInflateMilliseconds: -7,
            zrleTileApplyMilliseconds: -8
        )

        XCTAssertEqual(sample.durationMilliseconds, 0)
        XCTAssertEqual(sample.dirtyRectangleCount, 0)
        XCTAssertEqual(sample.dirtyAreaPermille, 1_000)
        XCTAssertEqual(sample.changedPixelsPermille, 0)
        XCTAssertEqual(sample.rendererUploadRegionCount, 0)
        XCTAssertEqual(sample.receiveTotalMilliseconds, 0)
        XCTAssertEqual(sample.networkReadMilliseconds, 0)
        XCTAssertEqual(sample.clientProcessingMilliseconds, 0)
        XCTAssertEqual(sample.zrleInflateMilliseconds, 0)
        XCTAssertEqual(sample.zrleTileApplyMilliseconds, 0)
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

    func testViewportInteractionPausedRequestsClampToRequestedSamples() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 2,
            samples: [
                streamShapeSample(duration: 10)
            ],
            elapsedMilliseconds: 10,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            viewportInteractionPausedRequestCount: 4,
            viewportInteractionPausePollCount: -1,
            viewportInteractionPausedMilliseconds: -20
        )

        XCTAssertEqual(summary.viewportInteractionPausedRequestCount, 2)
        XCTAssertEqual(summary.viewportInteractionPausedRequestPermille, 1_000)
        XCTAssertEqual(summary.viewportInteractionPausePollCount, 0)
        XCTAssertEqual(summary.viewportInteractionPausedMilliseconds, 0)
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
        XCTAssertEqual(summary.tailLatency.firstSlowUpdateOrdinal, 2)
        XCTAssertEqual(summary.tailLatency.firstSlowContentUpdateOrdinal, 2)
        XCTAssertEqual(summary.tailLatency.firstVerySlowUpdateOrdinal, 4)
        XCTAssertEqual(summary.tailLatency.firstVerySlowContentUpdateOrdinal, 3)
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
            iterationOrdinal: 2,
            orderOrdinal: 3,
            firstFrameMilliseconds: 1_234,
            summary: summary
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkStreamShapeProfileReport.self, from: encoded)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.transportMode, .continuousUpdates)
        XCTAssertEqual(decoded.iterationOrdinal, 2)
        XCTAssertEqual(decoded.orderOrdinal, 3)
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
                "zrleInflateLatency",
                "zrleTileApplyLatency",
                "adaptiveClientPressurePacingSamples",
                "adaptiveClientPressurePacingPermille",
                "viewportInteractionPacingSamples",
                "viewportInteractionPacingPermille",
                "viewportInteractionPausedRequestCount",
                "viewportInteractionPausedRequestPermille",
                "viewportInteractionPausePollCount",
                "viewportInteractionPausedMilliseconds"
            ]
        )
        let decodedSummary = try JSONDecoder().decode(BenchmarkStreamShapeSummary.self, from: legacySummaryData)

        XCTAssertEqual(decodedSummary.actualEncodingMix, RFBFramebufferEncodingMix())
        XCTAssertNil(decodedSummary.zrleInflateLatency)
        XCTAssertNil(decodedSummary.zrleTileApplyLatency)
        XCTAssertEqual(decodedSummary.adaptiveClientPressurePacingSamples, 0)
        XCTAssertEqual(decodedSummary.adaptiveClientPressurePacingPermille, 0)
        XCTAssertEqual(decodedSummary.viewportInteractionPacingSamples, 0)
        XCTAssertEqual(decodedSummary.viewportInteractionPacingPermille, 0)
        XCTAssertEqual(decodedSummary.viewportInteractionPausedRequestCount, 0)
        XCTAssertEqual(decodedSummary.viewportInteractionPausedRequestPermille, 0)
        XCTAssertEqual(decodedSummary.viewportInteractionPausePollCount, 0)
        XCTAssertEqual(decodedSummary.viewportInteractionPausedMilliseconds, 0)
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

    func testProfileAggregatesCombineRepeatedRequestResponseRuns() {
        let reports = [
            profileReport(label: "local-low-latency", durations: [1_200, 40], iteration: 1),
            profileReport(label: "zrle-compression-0", durations: [180, 220], iteration: 1),
            profileReport(label: "local-low-latency", durations: [80, 90], iteration: 2),
            profileReport(label: "zrle-compression-0", durations: [120, 140], iteration: 2),
            BenchmarkStreamShapeProfileReport(
                label: "continuous",
                transportMode: .continuousUpdates,
                iterationOrdinal: 1,
                orderOrdinal: 3,
                firstFrameMilliseconds: nil,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: 1,
                    samples: [],
                    elapsedMilliseconds: nil,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: "stream-continuous-updates-connection-failed"
                )
            )
        ]

        let aggregates = BenchmarkStreamShapeProfileAggregateReport.aggregates(from: reports)

        XCTAssertEqual(aggregates.map(\.label), ["local-low-latency", "zrle-compression-0", "continuous"])
        let local = aggregates[0]
        XCTAssertEqual(local.runCount, 2)
        XCTAssertEqual(local.usableRunCount, 2)
        XCTAssertEqual(local.failedRunCount, 0)
        XCTAssertEqual(local.averageUpdateMilliseconds, 353)
        XCTAssertEqual(local.maxP95UpdateMilliseconds, 1_200)
        XCTAssertEqual(local.slowUpdateSamples, 1)
        XCTAssertEqual(local.verySlowUpdateSamples, 1)
        XCTAssertEqual(local.receivedSamples, 4)

        let continuous = aggregates[2]
        XCTAssertEqual(continuous.runCount, 1)
        XCTAssertEqual(continuous.usableRunCount, 0)
        XCTAssertEqual(continuous.failedRunCount, 1)
        XCTAssertNil(continuous.averageUpdateMilliseconds)
    }

    func testOrderNeutralRecommendationUsesAggregateRuns() throws {
        let aggregates = BenchmarkStreamShapeProfileAggregateReport.aggregates(
            from: [
                profileReport(label: "local-low-latency", durations: [1_200, 40], iteration: 1),
                profileReport(label: "zrle-compression-0", durations: [180, 220], iteration: 1),
                profileReport(label: "local-low-latency", durations: [80, 90], iteration: 2),
                profileReport(label: "zrle-compression-0", durations: [120, 140], iteration: 2)
            ]
        )

        let recommendation = try XCTUnwrap(
            BenchmarkStreamShapeRecommendation.recommendedOrderNeutralRequestResponseProfile(
                from: aggregates
            )
        )

        XCTAssertEqual(recommendation.label, "zrle-compression-0")
        XCTAssertEqual(recommendation.reason, "lowest-average-update-latency-across-order-neutral-request-response-runs")
        XCTAssertEqual(recommendation.runCount, 2)
        XCTAssertEqual(recommendation.usableRunCount, 2)
        XCTAssertEqual(recommendation.averageUpdateMilliseconds, 165)
        XCTAssertEqual(recommendation.p95UpdateMilliseconds, 220)
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

    func testPracticalAssessmentPassesWhenTargetsAreMet() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 8,
            samples: (0..<8).map { _ in
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 40,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 10,
                    changedPixelsPermille: 10,
                    rendererUploadStrategy: .partial,
                    rendererUploadRegionCount: 1,
                    clientProcessingMilliseconds: 8
                )
            },
            elapsedMilliseconds: 1_000,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        XCTAssertEqual(summary.practicalAssessment.targetName, "iphone-practical-baseline-v1")
        XCTAssertEqual(summary.practicalAssessment.verdict, .pass)
        XCTAssertTrue(summary.practicalAssessment.issueCodes.isEmpty)
    }

    func testPracticalAssessmentWarnsForCurrentMacScreenSharingClassContentFPS() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 5,
            samples: (0..<5).map { _ in
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 150,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 10,
                    changedPixelsPermille: 10,
                    rendererUploadStrategy: .partial,
                    rendererUploadRegionCount: 1,
                    clientProcessingMilliseconds: 8
                )
            },
            elapsedMilliseconds: 1_000,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        XCTAssertEqual(summary.contentFramesPerSecond, 5)
        XCTAssertEqual(summary.practicalAssessment.verdict, .warning)
        XCTAssertEqual(summary.practicalAssessment.issueCodes, [.contentFPSWarning])
    }

    func testPracticalAssessmentFailsForVerySlowOrFullUploadPressure() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 4,
            samples: [
                streamShapeSample(duration: 1_100, rendererUploadStrategy: .full),
                streamShapeSample(duration: 40, rendererUploadStrategy: .full),
                streamShapeSample(duration: 40, rendererUploadStrategy: .full),
                streamShapeSample(duration: 40, rendererUploadStrategy: .partial)
            ],
            elapsedMilliseconds: 1_220,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        XCTAssertEqual(summary.practicalAssessment.verdict, .fail)
        XCTAssertTrue(summary.practicalAssessment.issueCodes.contains(.verySlowUpdate))
        XCTAssertTrue(summary.practicalAssessment.issueCodes.contains(.fullUploadFailed))
    }

    func testPracticalAssessmentIsEncodedIntoBenchmarkJSON() throws {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 0,
            samples: [],
            elapsedMilliseconds: nil,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(summary)) as? [String: Any]
        )
        let assessment = try XCTUnwrap(object["practicalAssessment"] as? [String: Any])

        XCTAssertEqual(assessment["targetName"] as? String, "iphone-practical-baseline-v1")
        XCTAssertEqual(assessment["verdict"] as? String, "disabled")
    }

    func testSustainedUsabilityTargetSelectionIsDefaultForCliGate() {
        XCTAssertEqual(
            BenchmarkStreamShapePracticalTargetSelection.defaultSelection,
            .iPhoneSustainedUsability
        )
        XCTAssertEqual(
            BenchmarkStreamShapePracticalTargetSelection.usageDescription,
            "iphone-practical-baseline-v1|iphone-sustained-usability-v2"
        )
        XCTAssertEqual(
            BenchmarkStreamShapePracticalTargetSelection.iPhoneSustainedUsability.targets.name,
            "iphone-sustained-usability-v2"
        )
    }

    func testSustainedUsabilityTargetPassesOnlyWhenV2BandsAreMet() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 8,
            samples: (0..<8).map { _ in
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 100,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 10,
                    changedPixelsPermille: 10,
                    rendererUploadStrategy: .partial,
                    rendererUploadRegionCount: 1,
                    clientProcessingMilliseconds: 8
                )
            },
            elapsedMilliseconds: 1_000,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            practicalTargets: .iPhoneSustainedUsability
        )

        XCTAssertEqual(summary.practicalAssessment.targetName, "iphone-sustained-usability-v2")
        XCTAssertEqual(summary.practicalAssessment.verdict, .pass)
        XCTAssertTrue(summary.practicalAssessment.issueCodes.isEmpty)
    }

    func testSustainedUsabilityTargetFailsAverageUpdateTail() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 8,
            samples: (0..<8).map { _ in
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 260,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 10,
                    changedPixelsPermille: 10,
                    rendererUploadStrategy: .partial,
                    rendererUploadRegionCount: 1,
                    clientProcessingMilliseconds: 8
                )
            },
            elapsedMilliseconds: 1_000,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            practicalTargets: .iPhoneSustainedUsability
        )

        XCTAssertEqual(summary.practicalAssessment.verdict, .fail)
        XCTAssertEqual(summary.practicalAssessment.issueCodes, [.averageUpdateFailed])
    }

    func testSustainedUsabilityTargetIsEncodedIntoBenchmarkJSON() throws {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 8,
            samples: (0..<8).map { _ in streamShapeSample(duration: 100, rendererUploadStrategy: .partial) },
            elapsedMilliseconds: 1_000,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            practicalTargets: .iPhoneSustainedUsability
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(summary)) as? [String: Any]
        )
        let assessment = try XCTUnwrap(object["practicalAssessment"] as? [String: Any])

        XCTAssertEqual(assessment["targetName"] as? String, "iphone-sustained-usability-v2")
        XCTAssertEqual(assessment["verdict"] as? String, "pass")
    }

    func testPracticalAssessmentDecodesWhenLegacyJSONOmitsField() throws {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 3,
            samples: [
                streamShapeSample(duration: 40, rendererUploadStrategy: .partial),
                streamShapeSample(duration: 40, rendererUploadStrategy: .partial),
                streamShapeSample(duration: 40, rendererUploadStrategy: .partial)
            ],
            elapsedMilliseconds: 120,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(summary)) as? [String: Any]
        )
        object.removeValue(forKey: "practicalAssessment")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BenchmarkStreamShapeSummary.self, from: legacyData)

        XCTAssertEqual(decoded.contentUpdateSamples, 3)
        XCTAssertEqual(decoded.practicalAssessment.verdict, .pass)
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
        XCTAssertNil(summary.zrleInflateLatency)
        XCTAssertNil(summary.zrleTileApplyLatency)
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

    private func profileReport(
        label: String,
        durations: [Int],
        iteration: Int
    ) -> BenchmarkStreamShapeProfileReport {
        BenchmarkStreamShapeProfileReport(
            label: label,
            transportMode: .requestResponse,
            iterationOrdinal: iteration,
            orderOrdinal: 1,
            firstFrameMilliseconds: 100,
            summary: BenchmarkStreamShapeSummary(
                requestedSamples: durations.count,
                samples: durations.map { duration in
                    BenchmarkStreamShapeSample(
                        kind: .contentUpdate,
                        durationMilliseconds: duration,
                        dirtyRectangleCount: 1,
                        dirtyAreaPermille: 1,
                        changedPixelsPermille: 1,
                        rendererUploadStrategy: .partial,
                        rendererUploadRegionCount: 1,
                        clientProcessingMilliseconds: max(duration / 10, 1),
                        zrleTileApplyMilliseconds: max(duration / 12, 1)
                    )
                },
                elapsedMilliseconds: durations.reduce(0, +),
                firstTimeoutMilliseconds: nil,
                failureLabel: nil
            )
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
