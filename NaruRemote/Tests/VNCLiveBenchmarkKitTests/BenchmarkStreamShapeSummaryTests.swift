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
                    firstByteWaitMilliseconds: 18,
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
                    firstByteWaitMilliseconds: 40,
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
        XCTAssertEqual(summary.attemptedSamples, 3)
        XCTAssertEqual(summary.receivedSamples, 2)
        XCTAssertEqual(summary.emptyUpdateSamples, 1)
        XCTAssertEqual(summary.contentUpdateSamples, 1)
        XCTAssertEqual(summary.receivedSamplePermille, 667)
        XCTAssertEqual(summary.unansweredSamplePermille, 333)
        XCTAssertEqual(summary.contentSamplePermille, 333)
        XCTAssertEqual(summary.emptyResponsePermille, 500)
        XCTAssertEqual(summary.contentResponsePermille, 500)
        XCTAssertEqual(summary.deliveredFramesPerSecond, 20)
        XCTAssertEqual(summary.contentFramesPerSecond, 10)
        XCTAssertEqual(try XCTUnwrap(summary.updateLatency).averageMilliseconds, 40)
        XCTAssertEqual(try XCTUnwrap(summary.dirtyRectangleCount).maxMilliseconds, 2)
        XCTAssertEqual(try XCTUnwrap(summary.dirtyAreaPermille).maxMilliseconds, 120)
        XCTAssertEqual(try XCTUnwrap(summary.changedPixelsPermille).maxMilliseconds, 90)
        XCTAssertEqual(try XCTUnwrap(summary.receiveTotalLatency).averageMilliseconds, 36)
        XCTAssertEqual(try XCTUnwrap(summary.networkReadLatency).averageMilliseconds, 33)
        XCTAssertEqual(try XCTUnwrap(summary.firstByteWaitLatency).averageMilliseconds, 29)
        XCTAssertEqual(try XCTUnwrap(summary.firstByteWaitLatency).p95Milliseconds, 40)
        XCTAssertEqual(try XCTUnwrap(summary.payloadReadLatency).averageMilliseconds, 4)
        XCTAssertEqual(try XCTUnwrap(summary.payloadReadLatency).p95Milliseconds, 7)
        XCTAssertEqual(try XCTUnwrap(summary.clientProcessingLatency).maxMilliseconds, 5)
        XCTAssertEqual(try XCTUnwrap(summary.zrleInflateLatency).averageMilliseconds, 3)
        XCTAssertEqual(try XCTUnwrap(summary.zrleTileApplyLatency).p95Milliseconds, 7)
        XCTAssertEqual(summary.phaseBudget.sampleCount, 2)
        XCTAssertEqual(summary.phaseBudget.networkReadSharePermille, 838)
        XCTAssertEqual(summary.phaseBudget.firstByteWaitSharePermille, 866)
        XCTAssertEqual(summary.phaseBudget.payloadReadSharePermille, 134)
        XCTAssertEqual(summary.phaseBudget.clientProcessingSharePermille, 75)
        XCTAssertEqual(summary.phaseBudget.requestLoopSharePermille, 88)
        XCTAssertEqual(summary.phaseBudget.dominantPhase, .networkRead)
        XCTAssertEqual(summary.phaseBudget.networkReadDominantSubphase, .firstByteWait)
        XCTAssertEqual(summary.phaseBudget.slowUpdateSampleCount, 0)
        XCTAssertEqual(summary.phaseBudget.slowDominantPhase, .unknown)
        XCTAssertNil(summary.phaseBudget.slowNetworkReadDominantSubphase)
        XCTAssertEqual(try XCTUnwrap(summary.phaseBudget.requestLoopLatency).averageMilliseconds, 3)
        XCTAssertEqual(try XCTUnwrap(summary.phaseBudget.requestLoopLatency).p95Milliseconds, 5)
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
        XCTAssertEqual(summary.attemptedSamples, 4)
        XCTAssertEqual(summary.timedOutSamples, 1)
        XCTAssertEqual(summary.receivedSamplePermille, 0)
        XCTAssertEqual(summary.unansweredSamplePermille, 1_000)
        XCTAssertEqual(summary.contentSamplePermille, 0)
        XCTAssertNil(summary.emptyResponsePermille)
        XCTAssertNil(summary.contentResponsePermille)
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
            firstByteWaitMilliseconds: -6,
            payloadReadMilliseconds: -7,
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
        XCTAssertEqual(sample.firstByteWaitMilliseconds, 0)
        XCTAssertEqual(sample.payloadReadMilliseconds, 0)
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
            pacingWindow: .zeroContentDelay,
            requestRegion: .centerHalf,
            requestRegionAreaPermille: 250,
            firstFrameRequestAreaPermille: 125,
            iterationOrdinal: 2,
            orderOrdinal: 3,
            firstFrameMilliseconds: 1_234,
            firstFrameReceiveTiming: RFBFramebufferUpdateTiming(
                totalMilliseconds: 1_234,
                networkReadMilliseconds: 1_200,
                firstByteWaitMilliseconds: 900
            ),
            summary: summary
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkStreamShapeProfileReport.self, from: encoded)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.transportMode, .continuousUpdates)
        XCTAssertEqual(decoded.pacingWindow, .zeroContentDelay)
        XCTAssertEqual(decoded.requestRegion, .centerHalf)
        XCTAssertEqual(decoded.requestRegionAreaPermille, 250)
        XCTAssertEqual(decoded.firstFrameRequestAreaPermille, 125)
        XCTAssertEqual(decoded.iterationOrdinal, 2)
        XCTAssertEqual(decoded.orderOrdinal, 3)
        XCTAssertEqual(decoded.firstFrameReceiveTiming?.networkReadMilliseconds, 1_200)
        XCTAssertEqual(decoded.firstFrameReceiveTiming?.firstByteWaitMilliseconds, 900)
        XCTAssertEqual(decoded.firstFrameReceiveTiming?.payloadReadMilliseconds, 300)
    }

    func testProfileReportDecodesLegacyPayloadWithoutPacingWindowAndRequestRegionAsDefaults() throws {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 1,
            samples: [
                BenchmarkStreamShapeSample(
                    kind: .contentUpdate,
                    durationMilliseconds: 12,
                    dirtyRectangleCount: 1,
                    dirtyAreaPermille: 10,
                    changedPixelsPermille: 10
                )
            ],
            elapsedMilliseconds: 12,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )
        let report = BenchmarkStreamShapeProfileReport(
            label: "local-low-latency",
            transportMode: .requestResponse,
            pacingWindow: .appBalanced30Hz,
            requestRegion: .centerThird,
            firstFrameMilliseconds: 120,
            summary: summary
        )
        let legacyData = try Self.encodedPayload(
            from: report,
            removingKeys: [
                "pacingWindow",
                "requestRegion",
                "requestRegionAreaPermille",
                "firstFrameRequestAreaPermille",
                "firstFrameReceiveTiming"
            ]
        )

        let decoded = try JSONDecoder().decode(BenchmarkStreamShapeProfileReport.self, from: legacyData)

        XCTAssertEqual(decoded.pacingWindow, .single)
        XCTAssertEqual(decoded.requestRegion, .full)
        XCTAssertNil(decoded.requestRegionAreaPermille)
        XCTAssertNil(decoded.firstFrameRequestAreaPermille)
        XCTAssertNil(decoded.firstFrameReceiveTiming)
        XCTAssertEqual(decoded.label, "local-low-latency")
        XCTAssertEqual(decoded.transportMode, .requestResponse)
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
                "viewportInteractionPausedMilliseconds",
                "attemptedSamples",
                "receivedSamplePermille",
                "unansweredSamplePermille",
                "contentSamplePermille",
                "emptyResponsePermille",
                "contentResponsePermille"
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
        XCTAssertEqual(decodedSummary.phaseBudget, .empty)
        XCTAssertEqual(decodedSummary.attemptedSamples, 1)
        XCTAssertEqual(decodedSummary.receivedSamplePermille, 1_000)
        XCTAssertEqual(decodedSummary.unansweredSamplePermille, 0)
        XCTAssertEqual(decodedSummary.contentSamplePermille, 1_000)
        XCTAssertEqual(decodedSummary.contentResponsePermille, 1_000)
        XCTAssertEqual(decodedSummary.receivedSamples, 1)
    }

    func testStreamShapeSummaryReportsAttemptedSampleHitRates() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 10,
            attemptedSamples: 4,
            samples: [
                streamShapeSample(duration: 40),
                streamShapeSample(duration: 45, kind: .emptyUpdate),
                streamShapeSample(duration: 50)
            ],
            elapsedMilliseconds: 200,
            firstTimeoutMilliseconds: 100,
            failureLabel: nil
        )

        XCTAssertEqual(summary.attemptedSamples, 4)
        XCTAssertEqual(summary.receivedSamples, 3)
        XCTAssertEqual(summary.contentUpdateSamples, 2)
        XCTAssertEqual(summary.receivedSamplePermille, 750)
        XCTAssertEqual(summary.unansweredSamplePermille, 250)
        XCTAssertEqual(summary.contentSamplePermille, 500)
        XCTAssertEqual(summary.emptyResponsePermille, 333)
        XCTAssertEqual(summary.contentResponsePermille, 667)
    }

    func testDecodingClampsAttemptedSamplesAtReceivedSamples() throws {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 2,
            attemptedSamples: 2,
            samples: [
                streamShapeSample(duration: 40),
                streamShapeSample(duration: 45)
            ],
            elapsedMilliseconds: 100,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil
        )
        let encoded = try JSONEncoder().encode(summary)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["attemptedSamples"] = 1
        object.removeValue(forKey: "receivedSamplePermille")
        object.removeValue(forKey: "unansweredSamplePermille")
        object.removeValue(forKey: "contentSamplePermille")

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(BenchmarkStreamShapeSummary.self, from: data)

        XCTAssertEqual(decoded.attemptedSamples, 2)
        XCTAssertEqual(decoded.receivedSamplePermille, 1_000)
        XCTAssertEqual(decoded.unansweredSamplePermille, 0)
        XCTAssertEqual(decoded.contentSamplePermille, 1_000)
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
            pacingWindow: .zeroContentDelay,
            requestRegion: .centerHalf,
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
        XCTAssertEqual(recommendation.pacingWindow, .zeroContentDelay)
        XCTAssertEqual(recommendation.requestRegion, .centerHalf)
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
        XCTAssertEqual(local.averageReceivedSamplePermille, 1_000)
        XCTAssertEqual(local.averageContentSamplePermille, 1_000)
        XCTAssertEqual(local.averageContentResponsePermille, 1_000)
        XCTAssertEqual(local.averageUnansweredSamplePermille, 0)

        let continuous = aggregates[2]
        XCTAssertEqual(continuous.runCount, 1)
        XCTAssertEqual(continuous.usableRunCount, 0)
        XCTAssertEqual(continuous.failedRunCount, 1)
        XCTAssertNil(continuous.averageUpdateMilliseconds)
    }

    func testProfileAggregatesKeepPacingWindowsSeparate() {
        let reports = [
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [90, 100],
                iteration: 1,
                pacingWindow: .zeroContentDelay
            ),
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [150, 160],
                iteration: 1,
                pacingWindow: .appBalanced30Hz
            ),
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [80, 85],
                iteration: 2,
                pacingWindow: .zeroContentDelay
            )
        ]

        let aggregates = BenchmarkStreamShapeProfileAggregateReport.aggregates(from: reports)

        XCTAssertEqual(aggregates.map(\.pacingWindow), [.zeroContentDelay, .appBalanced30Hz])
        XCTAssertEqual(aggregates.map(\.label), [
            "zrle-compression-0-clipboard",
            "zrle-compression-0-clipboard"
        ])
        XCTAssertEqual(aggregates[0].runCount, 2)
        XCTAssertEqual(aggregates[0].averageUpdateMilliseconds, 89)
        XCTAssertEqual(aggregates[1].runCount, 1)
        XCTAssertEqual(aggregates[1].averageUpdateMilliseconds, 155)
    }

    func testProfileAggregatesKeepRequestRegionsSeparate() {
        let reports = [
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [90, 100],
                iteration: 1,
                requestRegion: .full,
                requestRegionAreaPermille: 1_000,
                firstFrameRequestAreaPermille: 1_000,
                firstFrameReceiveTiming: RFBFramebufferUpdateTiming(
                    totalMilliseconds: 120,
                    networkReadMilliseconds: 100,
                    firstByteWaitMilliseconds: 80
                )
            ),
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [120, 130],
                iteration: 1,
                requestRegion: .centerHalf,
                requestRegionAreaPermille: 250,
                firstFrameRequestAreaPermille: 125,
                firstFrameReceiveTiming: RFBFramebufferUpdateTiming(
                    totalMilliseconds: 90,
                    networkReadMilliseconds: 80,
                    firstByteWaitMilliseconds: 20
                )
            ),
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [80, 85],
                iteration: 2,
                requestRegion: .full,
                requestRegionAreaPermille: 1_000,
                firstFrameRequestAreaPermille: 1_000,
                firstFrameReceiveTiming: RFBFramebufferUpdateTiming(
                    totalMilliseconds: 80,
                    networkReadMilliseconds: 60,
                    firstByteWaitMilliseconds: 30
                )
            )
        ]

        let aggregates = BenchmarkStreamShapeProfileAggregateReport.aggregates(from: reports)

        XCTAssertEqual(aggregates.map(\.requestRegion), [.full, .centerHalf])
        XCTAssertEqual(aggregates[0].runCount, 2)
        XCTAssertEqual(aggregates[0].averageUpdateMilliseconds, 89)
        XCTAssertEqual(aggregates[0].averageRequestRegionAreaPermille, 1_000)
        XCTAssertEqual(aggregates[0].averageFirstFrameRequestAreaPermille, 1_000)
        XCTAssertEqual(aggregates[0].averageFirstFrameReceiveTotalMilliseconds, 100)
        XCTAssertEqual(aggregates[0].averageFirstFrameNetworkReadMilliseconds, 80)
        XCTAssertEqual(aggregates[0].averageFirstFrameFirstByteWaitMilliseconds, 55)
        XCTAssertEqual(aggregates[0].averageFirstFramePayloadReadMilliseconds, 25)
        XCTAssertEqual(aggregates[0].averageFirstFrameClientProcessingMilliseconds, 20)
        XCTAssertEqual(aggregates[0].averageFirstFrameFirstByteWaitSharePermille, 650)
        XCTAssertEqual(aggregates[0].averageFirstFramePayloadReadSharePermille, 350)
        XCTAssertEqual(aggregates[1].runCount, 1)
        XCTAssertEqual(aggregates[1].averageUpdateMilliseconds, 125)
        XCTAssertEqual(aggregates[1].averageRequestRegionAreaPermille, 250)
        XCTAssertEqual(aggregates[1].averageFirstFrameRequestAreaPermille, 125)
        XCTAssertEqual(aggregates[1].averageFirstFrameReceiveTotalMilliseconds, 90)
        XCTAssertEqual(aggregates[1].averageFirstFrameNetworkReadMilliseconds, 80)
        XCTAssertEqual(aggregates[1].averageFirstFrameFirstByteWaitMilliseconds, 20)
        XCTAssertEqual(aggregates[1].averageFirstFramePayloadReadMilliseconds, 60)
        XCTAssertEqual(aggregates[1].averageFirstFrameClientProcessingMilliseconds, 10)
        XCTAssertEqual(aggregates[1].averageFirstFrameFirstByteWaitSharePermille, 250)
        XCTAssertEqual(aggregates[1].averageFirstFramePayloadReadSharePermille, 750)
    }

    func testProfileGatesSummarizePracticalVerdictsByProfile() {
        let reports = [
            profileReport(label: "zrle-compression-0", durations: [40, 45, 50], iteration: 1),
            BenchmarkStreamShapeProfileReport(
                label: "zrle-compression-0",
                iterationOrdinal: 2,
                orderOrdinal: 1,
                firstFrameMilliseconds: 100,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: 3,
                    samples: [],
                    elapsedMilliseconds: 100,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: "stream-request-response-receive-failed"
                )
            ),
            BenchmarkStreamShapeProfileReport(
                label: "continuous",
                transportMode: .continuousUpdates,
                iterationOrdinal: 1,
                orderOrdinal: 2,
                firstFrameMilliseconds: nil,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: 0,
                    samples: [],
                    elapsedMilliseconds: nil,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil
                )
            )
        ]

        let gates = BenchmarkStreamShapeProfileGateReport.gates(from: reports)

        XCTAssertEqual(gates.map(\.label), ["zrle-compression-0", "continuous"])
        let zrle = gates[0]
        XCTAssertEqual(zrle.transportMode, .requestResponse)
        XCTAssertEqual(zrle.targetName, "iphone-practical-baseline-v1")
        XCTAssertEqual(zrle.verdict, .fail)
        XCTAssertEqual(zrle.runCount, 2)
        XCTAssertEqual(zrle.passRunCount, 1)
        XCTAssertEqual(zrle.warningRunCount, 0)
        XCTAssertEqual(zrle.failRunCount, 1)
        XCTAssertEqual(zrle.disabledRunCount, 0)
        XCTAssertEqual(zrle.issueCodes, [.probeFailed])
        XCTAssertEqual(zrle.primaryIssueCode, .probeFailed)
        XCTAssertEqual(
            zrle.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue
        )
        XCTAssertEqual(
            zrle.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.inspectServerTransportCadence.rawValue
        )
        XCTAssertEqual(zrle.primaryConstraintCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionPrimaryConstraint.none.rawValue,
                count: 1
            ),
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue,
                count: 1
            )
        ])
        XCTAssertEqual(zrle.recommendedNextProbeCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionNextProbe.none.rawValue,
                count: 1
            ),
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionNextProbe.inspectServerTransportCadence.rawValue,
                count: 1
            )
        ])
        XCTAssertEqual(zrle.failureLabelCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: "stream-request-response-receive-failed",
                count: 1
            )
        ])
        XCTAssertEqual(zrle.averageReceivedSamplePermille, 500)
        XCTAssertEqual(zrle.averageContentSamplePermille, 500)
        XCTAssertEqual(zrle.averageContentResponsePermille, 1_000)
        XCTAssertEqual(zrle.averageUnansweredSamplePermille, 500)

        let continuous = gates[1]
        XCTAssertEqual(continuous.transportMode, .continuousUpdates)
        XCTAssertEqual(continuous.verdict, .disabled)
        XCTAssertEqual(continuous.disabledRunCount, 1)
        XCTAssertEqual(continuous.issueCodes, [.probeDisabled])
        XCTAssertEqual(continuous.primaryIssueCode, .probeDisabled)
        XCTAssertEqual(
            continuous.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.none.rawValue
        )
        XCTAssertEqual(continuous.failureLabelCounts, [])
    }

    func testProfileGatesKeepPacingWindowsSeparate() {
        let reports = [
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [90, 95, 100],
                iteration: 1,
                pacingWindow: .zeroContentDelay
            ),
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [520, 530, 540],
                iteration: 1,
                pacingWindow: .appBalanced30Hz
            )
        ]

        let gates = BenchmarkStreamShapeProfileGateReport.gates(from: reports)

        XCTAssertEqual(gates.map(\.pacingWindow), [.zeroContentDelay, .appBalanced30Hz])
        XCTAssertEqual(gates[0].verdict, .pass)
        XCTAssertEqual(gates[1].verdict, .fail)
    }

    func testProfileGatesKeepRequestRegionsSeparate() {
        let reports = [
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [90, 95, 100],
                iteration: 1,
                requestRegion: .full,
                requestRegionAreaPermille: 1_000,
                firstFrameRequestAreaPermille: 1_000
            ),
            profileReport(
                label: "zrle-compression-0-clipboard",
                durations: [520, 530, 540],
                iteration: 1,
                requestRegion: .centerHalf,
                requestRegionAreaPermille: 250,
                firstFrameRequestAreaPermille: 125
            )
        ]

        let gates = BenchmarkStreamShapeProfileGateReport.gates(from: reports)

        XCTAssertEqual(gates.map(\.requestRegion), [.full, .centerHalf])
        XCTAssertEqual(gates.map(\.averageRequestRegionAreaPermille), [1_000, 250])
        XCTAssertEqual(gates.map(\.averageFirstFrameRequestAreaPermille), [1_000, 125])
        XCTAssertEqual(gates[0].verdict, .pass)
        XCTAssertEqual(gates[1].verdict, .fail)
    }

    func testProfileGatesSeparateSameProfileAcrossTargets() {
        let samples = Array(repeating: streamShapeSample(duration: 40), count: 8)
        let reports = [
            BenchmarkStreamShapeProfileReport(
                label: "candidate",
                firstFrameMilliseconds: 100,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: samples.count,
                    samples: samples,
                    elapsedMilliseconds: 320,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil,
                    practicalTargets: .iPhonePracticalBaseline
                )
            ),
            BenchmarkStreamShapeProfileReport(
                label: "candidate",
                firstFrameMilliseconds: 100,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: samples.count,
                    samples: samples,
                    elapsedMilliseconds: 320,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil,
                    practicalTargets: .iPhoneSustainedUsability
                )
            )
        ]

        let gates = BenchmarkStreamShapeProfileGateReport.gates(from: reports)

        XCTAssertEqual(gates.map(\.label), ["candidate", "candidate"])
        XCTAssertEqual(gates.map(\.targetName), [
            "iphone-practical-baseline-v1",
            "iphone-sustained-usability-v2"
        ])
        XCTAssertEqual(gates.map(\.verdict), [.pass, .pass])
    }

    func testOptimizationDecisionSummarizesProfileGateTriage() throws {
        let rendererPressure = BenchmarkStreamShapeProfileReport(
            label: "local-low-latency",
            firstFrameMilliseconds: 100,
            summary: BenchmarkStreamShapeSummary(
                requestedSamples: 4,
                samples: [
                    streamShapeSample(duration: 40, rendererUploadStrategy: .full),
                    streamShapeSample(duration: 40, rendererUploadStrategy: .full),
                    streamShapeSample(duration: 40, rendererUploadStrategy: .full),
                    streamShapeSample(duration: 40, rendererUploadStrategy: .partial)
                ],
                elapsedMilliseconds: 160,
                firstTimeoutMilliseconds: nil,
                failureLabel: nil
            )
        )
        let contentCadenceWarning = BenchmarkStreamShapeProfileReport(
            label: "zrle-compression-0",
            firstFrameMilliseconds: 100,
            summary: BenchmarkStreamShapeSummary(
                requestedSamples: 5,
                samples: (0..<5).map { _ in
                    streamShapeSample(duration: 150, rendererUploadStrategy: .partial)
                },
                elapsedMilliseconds: 1_000,
                firstTimeoutMilliseconds: nil,
                failureLabel: nil
            )
        )
        let gates = BenchmarkStreamShapeProfileGateReport.gates(
            from: [rendererPressure, contentCadenceWarning]
        )

        let decision = try XCTUnwrap(BenchmarkStreamShapeOptimizationDecision.decision(from: gates))

        XCTAssertEqual(decision.targetName, "iphone-practical-baseline-v1")
        XCTAssertEqual(decision.verdict, .fail)
        XCTAssertEqual(decision.gateCount, 2)
        XCTAssertEqual(decision.warningGateCount, 1)
        XCTAssertEqual(decision.failGateCount, 1)
        XCTAssertEqual(decision.blockedGateCount, 2)
        XCTAssertEqual(decision.primaryIssueCode, .fullUploadFailed)
        XCTAssertEqual(
            decision.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.rendererUpload.rawValue
        )
        XCTAssertEqual(
            decision.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.inspectLocalRenderPipeline.rawValue
        )
        XCTAssertEqual(decision.primaryConstraintCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionPrimaryConstraint.contentCadence.rawValue,
                count: 1
            ),
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionPrimaryConstraint.rendererUpload.rawValue,
                count: 1
            )
        ])
        XCTAssertEqual(decision.recommendedNextProbeCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionNextProbe.runSustainedV2ProfileGate.rawValue,
                count: 1
            ),
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionNextProbe.inspectLocalRenderPipeline.rawValue,
                count: 1
            )
        ])
    }

    func testOptimizationDecisionRejectsMismatchedDecodedTriageFields() throws {
        let json = """
        {
          "targetName": "iphone-sustained-usability-v2",
          "verdict": "warning",
          "gateCount": 2,
          "passGateCount": 1,
          "warningGateCount": 1,
          "failGateCount": 0,
          "disabledGateCount": 0,
          "blockedGateCount": 99,
          "primaryIssueCode": "content-fps-warning",
          "primaryConstraint": "thermal",
          "recommendedNextProbe": "inspectComposeRoute",
          "primaryConstraintCounts": [
            { "label": "contentCadence", "count": 2 },
            { "label": "not-safe", "count": 7 }
          ],
          "recommendedNextProbeCounts": [
            { "label": "runSustainedV2ProfileGate", "count": 2 },
            { "label": "inspectComposeRoute", "count": -3 }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BenchmarkStreamShapeOptimizationDecision.self, from: json)

        XCTAssertEqual(decoded.blockedGateCount, 1)
        XCTAssertEqual(decoded.primaryIssueCode, .contentFPSWarning)
        XCTAssertEqual(
            decoded.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.contentCadence.rawValue
        )
        XCTAssertEqual(
            decoded.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runSustainedV2ProfileGate.rawValue
        )
        XCTAssertEqual(decoded.primaryConstraintCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionPrimaryConstraint.contentCadence.rawValue,
                count: 2
            )
        ])
        XCTAssertEqual(decoded.recommendedNextProbeCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionNextProbe.runSustainedV2ProfileGate.rawValue,
                count: 2
            )
        ])
    }

    func testOptimizationDecisionMarksMixedTargetsExplicitly() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "legacy",
                transportMode: .requestResponse,
                targetName: "iphone-practical-baseline-v1",
                verdict: .pass,
                runCount: 1,
                passRunCount: 1,
                warningRunCount: 0,
                failRunCount: 0,
                disabledRunCount: 0,
                issueCodes: []
            ),
            BenchmarkStreamShapeProfileGateReport(
                label: "sustained",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .pass,
                runCount: 1,
                passRunCount: 1,
                warningRunCount: 0,
                failRunCount: 0,
                disabledRunCount: 0,
                issueCodes: []
            )
        ]

        let decision = try XCTUnwrap(BenchmarkStreamShapeOptimizationDecision.decision(from: gates))

        XCTAssertEqual(decision.targetName, "mixed-targets")
        XCTAssertEqual(decision.verdict, .pass)
    }

    func testOptimizationDecisionMergesFailureLabels() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "local-low-latency",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.probeFailed],
                failureLabelCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: "stream-continuous-updates-connection-failed",
                        count: 5
                    )
                ]
            ),
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.probeFailed],
                failureLabelCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: "stream-continuous-updates-connection-failed",
                        count: 4
                    ),
                    BenchmarkStreamShapeTriageLabelCount(
                        label: "stream-continuous-updates-timeout",
                        count: 1
                    )
                ]
            )
        ]

        let decision = try XCTUnwrap(BenchmarkStreamShapeOptimizationDecision.decision(from: gates))

        XCTAssertEqual(decision.failureLabelCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: "stream-continuous-updates-connection-failed",
                count: 9
            ),
            BenchmarkStreamShapeTriageLabelCount(
                label: "stream-continuous-updates-timeout",
                count: 1
            )
        ])
    }

    func testTransportCadenceDiagnosisRoutesContinuousUpdateConnectionFailures() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.contentFPSFailed, .averageUpdateFailed],
                primaryIssueCode: .averageUpdateFailed,
                primaryConstraintCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue,
                        count: 5
                    )
                ]
            ),
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.probeFailed],
                failureLabelCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: "stream-continuous-updates-connection-failed",
                        count: 5
                    )
                ]
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.targetName, "iphone-sustained-usability-v2")
        XCTAssertEqual(diagnosis.requestResponseStatus, .belowTarget)
        XCTAssertEqual(diagnosis.continuousUpdatesStatus, .failedBeforeSamples)
        XCTAssertEqual(diagnosis.recommendedTransportMode, .requestResponse)
        XCTAssertEqual(diagnosis.recommendedNextAction, .inspectContinuousUpdatesConnection)
        XCTAssertEqual(diagnosis.requestResponseGateCount, 1)
        XCTAssertEqual(diagnosis.requestResponseBlockedGateCount, 1)
        XCTAssertEqual(diagnosis.continuousUpdatesGateCount, 1)
        XCTAssertEqual(diagnosis.continuousUpdatesBlockedGateCount, 1)
        XCTAssertEqual(diagnosis.continuousUpdatesFailureLabelCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: "stream-continuous-updates-connection-failed",
                count: 5
            )
        ])
    }

    func testTransportCadenceDiagnosisRoutesRequestResponseDecodePressure() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "zrle-compression-0",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.clientProcessingFailed],
                primaryIssueCode: .clientProcessingFailed,
                primaryConstraintCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: DiagnosticSustainedSessionPrimaryConstraint.clientDecode.rawValue,
                        count: 5
                    )
                ]
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.requestResponseStatus, .belowTarget)
        XCTAssertEqual(diagnosis.continuousUpdatesStatus, .notTested)
        XCTAssertEqual(diagnosis.recommendedTransportMode, .requestResponse)
        XCTAssertEqual(diagnosis.recommendedNextAction, .compareRequestResponseEncodingProfiles)
        XCTAssertEqual(diagnosis.requestResponsePrimaryConstraintCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionPrimaryConstraint.clientDecode.rawValue,
                count: 5
            )
        ])
    }

    func testTransportCadenceDiagnosisTunesCadenceWhenReceivePathDominatesDecodePressure() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "zrle-compression-0",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.contentFPSWarning, .p95UpdateFailed, .clientProcessingFailed],
                primaryIssueCode: .clientProcessingFailed,
                primaryConstraintCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue,
                        count: 20
                    ),
                    BenchmarkStreamShapeTriageLabelCount(
                        label: DiagnosticSustainedSessionPrimaryConstraint.clientDecode.rawValue,
                        count: 5
                    )
                ]
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.requestResponseStatus, .belowTarget)
        XCTAssertEqual(diagnosis.recommendedTransportMode, .requestResponse)
        XCTAssertEqual(diagnosis.recommendedNextAction, .tuneTransportCadence)
        XCTAssertEqual(diagnosis.requestResponsePrimaryConstraintCounts, [
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue,
                count: 20
            ),
            BenchmarkStreamShapeTriageLabelCount(
                label: DiagnosticSustainedSessionPrimaryConstraint.clientDecode.rawValue,
                count: 5
            )
        ])
    }

    func testTransportCadenceDiagnosisKeepsMixedTransportBelowTarget() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .pass,
                runCount: 5,
                passRunCount: 5,
                warningRunCount: 0,
                failRunCount: 0,
                disabledRunCount: 0,
                issueCodes: []
            ),
            BenchmarkStreamShapeProfileGateReport(
                label: "zrle-compression-0",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.probeFailed],
                failureLabelCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: "stream-continuous-updates-connection-failed",
                        count: 5
                    )
                ]
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.continuousUpdatesStatus, .belowTarget)
        XCTAssertEqual(diagnosis.recommendedNextAction, .tuneTransportCadence)
    }

    func testTransportCadenceDiagnosisKeepsUnlabeledFailuresBelowTarget() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.probeFailed]
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.continuousUpdatesStatus, .belowTarget)
        XCTAssertEqual(diagnosis.recommendedNextAction, .tuneTransportCadence)
    }

    func testTransportCadenceDiagnosisKeepsNonTransportFailuresBelowTarget() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.probeFailed],
                failureLabelCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: "stream-stimulus-command-launch-failed",
                        count: 5
                    )
                ]
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.continuousUpdatesStatus, .belowTarget)
        XCTAssertEqual(diagnosis.recommendedNextAction, .tuneTransportCadence)
    }

    func testTransportCadenceDiagnosisRoutesUnconfirmedContinuousUpdatesBeforeSamples() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.probeFailed],
                failureLabelCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: "stream-continuous-updates-continuous-updates-not-confirmed",
                        count: 5
                    )
                ]
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.continuousUpdatesStatus, .failedBeforeSamples)
        XCTAssertEqual(diagnosis.recommendedNextAction, .inspectContinuousUpdatesConnection)
    }

    func testTransportCadenceDiagnosisRoutesPassingGateToPhysicalDevice() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .pass,
                runCount: 5,
                passRunCount: 5,
                warningRunCount: 0,
                failRunCount: 0,
                disabledRunCount: 0,
                issueCodes: []
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.requestResponseStatus, .pass)
        XCTAssertEqual(diagnosis.recommendedNextAction, .runPhysicalDeviceSustainedGate)
    }

    func testTransportCadenceDiagnosisPrefersPassingTransportOverBelowTargetTransport() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "zrle-compression-0",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.clientProcessingFailed],
                primaryIssueCode: .clientProcessingFailed,
                primaryConstraintCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: DiagnosticSustainedSessionPrimaryConstraint.clientDecode.rawValue,
                        count: 5
                    )
                ]
            ),
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .continuousUpdates,
                targetName: "iphone-sustained-usability-v2",
                verdict: .pass,
                runCount: 5,
                passRunCount: 5,
                warningRunCount: 0,
                failRunCount: 0,
                disabledRunCount: 0,
                issueCodes: []
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.requestResponseStatus, .belowTarget)
        XCTAssertEqual(diagnosis.continuousUpdatesStatus, .pass)
        XCTAssertEqual(diagnosis.recommendedTransportMode, .continuousUpdates)
        XCTAssertEqual(diagnosis.recommendedNextAction, .runPhysicalDeviceSustainedGate)
    }

    func testTransportCadenceDiagnosisIgnoresDisabledGatesWhenActiveGatePasses() throws {
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "tight-first",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .pass,
                runCount: 5,
                passRunCount: 5,
                warningRunCount: 0,
                failRunCount: 0,
                disabledRunCount: 0,
                issueCodes: []
            ),
            BenchmarkStreamShapeProfileGateReport(
                label: "continuous-disabled",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .disabled,
                runCount: 0,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 0,
                disabledRunCount: 1,
                issueCodes: []
            )
        ]

        let diagnosis = try XCTUnwrap(BenchmarkStreamShapeTransportCadenceDiagnosis.diagnosis(from: gates))

        XCTAssertEqual(diagnosis.requestResponseStatus, .pass)
        XCTAssertEqual(diagnosis.recommendedTransportMode, .requestResponse)
        XCTAssertEqual(diagnosis.recommendedNextAction, .runPhysicalDeviceSustainedGate)
    }

    func testRequestCadenceHealthRoutesHighHitRequestLoopTailToUpdateWaitInspection() throws {
        let reports = [
            BenchmarkStreamShapeProfileReport(
                label: "zrle-compression-0-cursor",
                transportMode: .requestResponse,
                iterationOrdinal: 1,
                orderOrdinal: 1,
                firstFrameMilliseconds: 100,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: 8,
                    attemptedSamples: 8,
                    samples: (0..<7).map { _ in
                        phaseBudgetContentSample(
                            duration: 116,
                            receiveTotal: 100,
                            networkRead: 90,
                            firstByteWait: 80,
                            clientProcessing: 10
                        )
                    } + [
                        phaseBudgetContentSample(
                            duration: 508,
                            receiveTotal: 120,
                            networkRead: 100,
                            firstByteWait: 95,
                            clientProcessing: 20
                        )
                    ],
                    elapsedMilliseconds: 1_320,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil,
                    practicalTargets: .iPhoneSustainedUsability
                )
            )
        ]

        let health = try XCTUnwrap(
            BenchmarkStreamShapeRequestCadenceHealth.health(
                from: BenchmarkStreamShapeProfileAggregateReport.aggregates(from: reports),
                gates: BenchmarkStreamShapeProfileGateReport.gates(from: reports),
                targets: .iPhoneSustainedUsability
            )
        )

        XCTAssertEqual(health.targetName, "iphone-sustained-usability-v2")
        XCTAssertEqual(health.sampleStatus, .highContentHit)
        XCTAssertEqual(health.latencyStatus, .p95Failed)
        XCTAssertEqual(health.dominantPhase, .networkRead)
        XCTAssertEqual(health.networkReadDominantSubphase, .firstByteWait)
        XCTAssertEqual(health.slowDominantPhase, .requestLoop)
        XCTAssertEqual(health.slowNetworkReadDominantSubphase, .firstByteWait)
        XCTAssertEqual(health.recommendedNextProbe, .inspectUpdateWaitTiming)
        XCTAssertEqual(health.requestResponseGateCount, 1)
        XCTAssertEqual(health.requestResponseBlockedGateCount, 1)
        XCTAssertEqual(health.requestResponseAggregateCount, 1)
        XCTAssertEqual(health.requestResponseUsableRunCount, 1)
        XCTAssertEqual(health.averageReceivedSamplePermille, 1_000)
        XCTAssertEqual(health.averageContentSamplePermille, 1_000)
        XCTAssertEqual(health.averageContentResponsePermille, 1_000)
        XCTAssertEqual(health.averageUnansweredSamplePermille, 0)
        XCTAssertEqual(health.maxP95UpdateMilliseconds, 508)
        XCTAssertEqual(health.averageFirstByteWaitSharePermille, 897)
        XCTAssertEqual(health.averagePayloadReadSharePermille, 103)
        XCTAssertEqual(health.maxFirstByteWaitP95Milliseconds, 95)
        XCTAssertEqual(health.maxPayloadReadP95Milliseconds, 10)
    }

    func testRequestCadenceHealthRoutesUnansweredWaitsToUpdateWaitInspection() throws {
        let reports = [
            BenchmarkStreamShapeProfileReport(
                label: "zrle-compression-0",
                transportMode: .requestResponse,
                iterationOrdinal: 1,
                orderOrdinal: 1,
                firstFrameMilliseconds: 100,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: 10,
                    attemptedSamples: 10,
                    samples: [
                        sustainedContentSample(duration: 100),
                        sustainedContentSample(duration: 100)
                    ],
                    elapsedMilliseconds: 1_000,
                    firstTimeoutMilliseconds: 800,
                    failureLabel: nil,
                    practicalTargets: .iPhoneSustainedUsability
                )
            )
        ]

        let health = try XCTUnwrap(
            BenchmarkStreamShapeRequestCadenceHealth.health(
                from: BenchmarkStreamShapeProfileAggregateReport.aggregates(from: reports),
                gates: BenchmarkStreamShapeProfileGateReport.gates(from: reports),
                targets: .iPhoneSustainedUsability
            )
        )

        XCTAssertEqual(health.sampleStatus, .unansweredWait)
        XCTAssertEqual(health.recommendedNextProbe, .inspectUpdateWaitTiming)
        XCTAssertEqual(health.averageReceivedSamplePermille, 200)
        XCTAssertEqual(health.averageUnansweredSamplePermille, 800)
    }

    func testRequestCadenceHealthRoutesEmptyResponsesToRegionAndStimulusInspection() throws {
        let samples = (0..<8).map { _ in sustainedEmptySample(duration: 80) }
            + (0..<2).map { _ in sustainedContentSample(duration: 90) }
        let reports = [
            BenchmarkStreamShapeProfileReport(
                label: "zrle-compression-0",
                transportMode: .requestResponse,
                iterationOrdinal: 1,
                orderOrdinal: 1,
                firstFrameMilliseconds: 100,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: 10,
                    attemptedSamples: 10,
                    samples: samples,
                    elapsedMilliseconds: 1_000,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil,
                    practicalTargets: .iPhoneSustainedUsability
                )
            )
        ]

        let health = try XCTUnwrap(
            BenchmarkStreamShapeRequestCadenceHealth.health(
                from: BenchmarkStreamShapeProfileAggregateReport.aggregates(from: reports),
                gates: BenchmarkStreamShapeProfileGateReport.gates(from: reports),
                targets: .iPhoneSustainedUsability
            )
        )

        XCTAssertEqual(health.sampleStatus, .emptyResponse)
        XCTAssertEqual(health.recommendedNextProbe, .inspectRequestRegionAndStimulus)
        XCTAssertEqual(health.averageReceivedSamplePermille, 1_000)
        XCTAssertEqual(health.averageContentResponsePermille, 200)
    }

    func testRequestCadenceHealthLetsDominantDecodePressureOverrideHitRate() throws {
        let aggregates = [
            BenchmarkStreamShapeProfileAggregateReport(
                label: "zrle-compression-0-cursor-clipboard",
                transportMode: .requestResponse,
                runCount: 5,
                usableRunCount: 5,
                failedRunCount: 0,
                averageUpdateMilliseconds: 118,
                maxP95UpdateMilliseconds: 320,
                averageContentFramesPerSecond: 6.7,
                averageRendererFullUploadPermille: 0,
                maxClientProcessingP95Milliseconds: 135,
                maxZrleTileApplyP95Milliseconds: 132,
                slowUpdateSamples: 0,
                verySlowUpdateSamples: 0,
                receivedSamples: 60,
                contentUpdateSamples: 55,
                averageReceivedSamplePermille: 1_000,
                averageContentSamplePermille: 917,
                averageContentResponsePermille: 917,
                averageUnansweredSamplePermille: 0
            )
        ]
        let gates = [
            BenchmarkStreamShapeProfileGateReport(
                label: "zrle-compression-0-cursor-clipboard",
                transportMode: .requestResponse,
                targetName: "iphone-sustained-usability-v2",
                verdict: .fail,
                runCount: 5,
                passRunCount: 0,
                warningRunCount: 0,
                failRunCount: 5,
                disabledRunCount: 0,
                issueCodes: [.clientProcessingFailed, .p95UpdateWarning],
                primaryIssueCode: .clientProcessingFailed,
                primaryConstraintCounts: [
                    BenchmarkStreamShapeTriageLabelCount(
                        label: DiagnosticSustainedSessionPrimaryConstraint.clientDecode.rawValue,
                        count: 5
                    ),
                    BenchmarkStreamShapeTriageLabelCount(
                        label: DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue,
                        count: 1
                    )
                ]
            )
        ]

        let health = try XCTUnwrap(
            BenchmarkStreamShapeRequestCadenceHealth.health(
                from: aggregates,
                gates: gates,
                targets: .iPhoneSustainedUsability
            )
        )

        XCTAssertEqual(health.sampleStatus, .highContentHit)
        XCTAssertEqual(health.recommendedNextProbe, .compareRequestResponseEncodingProfiles)
    }

    func testProfileGateDecodesMissingFailureLabelCountsAsEmpty() throws {
        let json = Data(
            """
            {
              "label": "tight-first",
              "transportMode": "request-response",
              "targetName": "iphone-sustained-usability-v2",
              "verdict": "pass",
              "runCount": 1,
              "passRunCount": 1,
              "warningRunCount": 0,
              "failRunCount": 0,
              "disabledRunCount": 0,
              "issueCodes": [],
              "primaryConstraint": "none",
              "recommendedNextProbe": "none",
              "primaryConstraintCounts": [],
              "recommendedNextProbeCounts": []
            }
            """.utf8
        )

        let gate = try JSONDecoder().decode(BenchmarkStreamShapeProfileGateReport.self, from: json)

        XCTAssertEqual(gate.failureLabelCounts, [])
    }

    func testOrderNeutralRecommendationUsesAggregateRuns() throws {
        let aggregates = BenchmarkStreamShapeProfileAggregateReport.aggregates(
            from: [
                profileReport(label: "local-low-latency", durations: [1_200, 40], iteration: 1),
                profileReport(
                    label: "zrle-compression-0",
                    durations: [180, 220],
                    iteration: 1,
                    requestRegion: .centerThird
                ),
                profileReport(label: "local-low-latency", durations: [80, 90], iteration: 2),
                profileReport(
                    label: "zrle-compression-0",
                    durations: [120, 140],
                    iteration: 2,
                    requestRegion: .centerThird
                )
            ]
        )

        let recommendation = try XCTUnwrap(
            BenchmarkStreamShapeRecommendation.recommendedOrderNeutralRequestResponseProfile(
                from: aggregates
            )
        )

        XCTAssertEqual(recommendation.label, "zrle-compression-0")
        XCTAssertEqual(recommendation.requestRegion, .centerThird)
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
        XCTAssertNil(summary.practicalAssessment.primaryIssueCode)
        XCTAssertEqual(
            summary.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.none.rawValue
        )
        XCTAssertEqual(
            summary.practicalAssessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.none.rawValue
        )
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
        XCTAssertEqual(summary.practicalAssessment.primaryIssueCode, .contentFPSWarning)
        XCTAssertEqual(
            summary.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.contentCadence.rawValue
        )
        XCTAssertEqual(
            summary.practicalAssessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runSustainedV2ProfileGate.rawValue
        )
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
        XCTAssertEqual(summary.practicalAssessment.primaryIssueCode, .fullUploadFailed)
        XCTAssertEqual(
            summary.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.rendererUpload.rawValue
        )
        XCTAssertEqual(
            summary.practicalAssessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.inspectLocalRenderPipeline.rawValue
        )
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
        XCTAssertEqual(assessment["primaryIssueCode"] as? String, "probe-disabled")
        XCTAssertEqual(assessment["primaryConstraint"] as? String, "none")
        XCTAssertEqual(assessment["recommendedNextProbe"] as? String, "none")
    }

    func testSustainedUsabilityTargetSelectionIsDefaultForCliGate() {
        XCTAssertEqual(
            BenchmarkStreamShapePracticalTargetSelection.defaultSelection,
            .iPhoneSustainedUsability
        )
        XCTAssertEqual(
            BenchmarkStreamShapePracticalTargetSelection.usageDescription,
            "iphone-practical-baseline-v1|iphone-sustained-usability-v2|iphone-poor-network-traffic-v1"
        )
        XCTAssertEqual(
            BenchmarkStreamShapePracticalTargetSelection.iPhoneSustainedUsability.targets.name,
            "iphone-sustained-usability-v2"
        )
        XCTAssertEqual(
            BenchmarkStreamShapePracticalTargetSelection.iPhonePoorNetworkTraffic.targets.name,
            "iphone-poor-network-traffic-v1"
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
        XCTAssertNil(summary.practicalAssessment.primaryIssueCode)
        XCTAssertEqual(
            summary.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.none.rawValue
        )
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
        XCTAssertEqual(summary.practicalAssessment.primaryIssueCode, .averageUpdateFailed)
        XCTAssertEqual(
            summary.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue
        )
        XCTAssertEqual(
            summary.practicalAssessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.inspectServerTransportCadence.rawValue
        )
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
        XCTAssertEqual(assessment["primaryConstraint"] as? String, "none")
        XCTAssertEqual(assessment["recommendedNextProbe"] as? String, "none")
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
        XCTAssertNil(decoded.practicalAssessment.primaryIssueCode)
        XCTAssertEqual(
            decoded.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.none.rawValue
        )
    }

    func testPracticalAssessmentDerivesTriageWhenLegacyJSONOmitsTriageFields() throws {
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
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(summary)) as? [String: Any]
        )
        var assessment = try XCTUnwrap(object["practicalAssessment"] as? [String: Any])
        assessment.removeValue(forKey: "primaryIssueCode")
        assessment.removeValue(forKey: "primaryConstraint")
        assessment.removeValue(forKey: "recommendedNextProbe")
        object["practicalAssessment"] = assessment
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(BenchmarkStreamShapeSummary.self, from: legacyData)

        XCTAssertEqual(decoded.practicalAssessment.primaryIssueCode, .averageUpdateFailed)
        XCTAssertEqual(
            decoded.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue
        )
        XCTAssertEqual(
            decoded.practicalAssessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.inspectServerTransportCadence.rawValue
        )
    }

    func testPracticalAssessmentRejectsMismatchedDecodedTriageFields() throws {
        let json = """
        {
          "targetName": "iphone-sustained-usability-v2",
          "verdict": "fail",
          "issueCodes": ["content-fps-failed"],
          "primaryIssueCode": "content-fps-failed",
          "primaryConstraint": "thermal",
          "recommendedNextProbe": "inspectComposeRoute"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BenchmarkStreamShapePracticalAssessment.self, from: json)

        XCTAssertEqual(decoded.primaryIssueCode, .contentFPSFailed)
        XCTAssertEqual(
            decoded.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.contentCadence.rawValue
        )
        XCTAssertEqual(
            decoded.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runSustainedV2ProfileGate.rawValue
        )
    }

    func testPoorNetworkTrafficGateFailsSlowFirstFrame() {
        let samples = Array(repeating: streamShapeSample(duration: 100, rendererUploadStrategy: .partial), count: 4)
        let reports = [
            BenchmarkStreamShapeProfileReport(
                label: "local-low-latency-rgb565",
                requestRegion: .viewportPhonePortrait,
                requestRegionAreaPermille: 364,
                firstFrameRequestAreaPermille: 260,
                firstFrameMilliseconds: 25_000,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: samples.count,
                    samples: samples,
                    elapsedMilliseconds: 1_000,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil,
                    practicalTargets: .iPhonePoorNetworkTraffic
                )
            )
        ]

        let gate = BenchmarkStreamShapeProfileGateReport.gates(from: reports)[0]

        XCTAssertEqual(gate.targetName, "iphone-poor-network-traffic-v1")
        XCTAssertEqual(gate.verdict, .fail)
        XCTAssertEqual(gate.issueCodes, [.firstFrameFailed])
        XCTAssertEqual(gate.primaryIssueCode, .firstFrameFailed)
        XCTAssertEqual(
            gate.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue
        )
        XCTAssertEqual(
            gate.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.inspectServerTransportCadence.rawValue
        )
        XCTAssertEqual(gate.averageRequestRegionAreaPermille, 364)
        XCTAssertEqual(gate.averageFirstFrameRequestAreaPermille, 260)
    }

    func testPoorNetworkTrafficGateFailsLargeRequestRegionArea() {
        let samples = Array(repeating: streamShapeSample(duration: 100, rendererUploadStrategy: .partial), count: 4)
        let reports = [
            BenchmarkStreamShapeProfileReport(
                label: "full-region",
                requestRegion: .full,
                requestRegionAreaPermille: 1_000,
                firstFrameRequestAreaPermille: 1_000,
                firstFrameMilliseconds: 1_000,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: samples.count,
                    samples: samples,
                    elapsedMilliseconds: 1_000,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil,
                    practicalTargets: .iPhonePoorNetworkTraffic
                )
            )
        ]

        let gate = BenchmarkStreamShapeProfileGateReport.gates(from: reports)[0]

        XCTAssertEqual(gate.verdict, .fail)
        XCTAssertEqual(gate.issueCodes, [.requestRegionAreaFailed])
        XCTAssertEqual(gate.primaryIssueCode, .requestRegionAreaFailed)
        XCTAssertEqual(
            gate.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.viewportInteraction.rawValue
        )
        XCTAssertEqual(
            gate.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runViewportInteractionTrace.rawValue
        )
        XCTAssertEqual(gate.averageRequestRegionAreaPermille, 1_000)
        XCTAssertEqual(gate.averageFirstFrameRequestAreaPermille, 1_000)
    }

    func testPoorNetworkTrafficGateFailsLargeFirstFrameRequestArea() {
        let samples = Array(repeating: streamShapeSample(duration: 100, rendererUploadStrategy: .partial), count: 4)
        let reports = [
            BenchmarkStreamShapeProfileReport(
                label: "visible-steady-full-startup",
                requestRegion: .viewportPhonePortrait,
                requestRegionAreaPermille: 364,
                firstFrameRequestAreaPermille: 1_000,
                firstFrameMilliseconds: 1_000,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: samples.count,
                    samples: samples,
                    elapsedMilliseconds: 1_000,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil,
                    practicalTargets: .iPhonePoorNetworkTraffic
                )
            )
        ]

        let gate = BenchmarkStreamShapeProfileGateReport.gates(from: reports)[0]

        XCTAssertEqual(gate.verdict, .fail)
        XCTAssertEqual(gate.issueCodes, [.requestRegionAreaFailed])
        XCTAssertEqual(gate.averageRequestRegionAreaPermille, 364)
        XCTAssertEqual(gate.averageFirstFrameRequestAreaPermille, 1_000)
    }

    func testPoorNetworkTrafficGateKeepsVisibleFocusStartupAsWarningCandidate() {
        let samples = Array(repeating: streamShapeSample(duration: 457, rendererUploadStrategy: .partial), count: 4)
        let reports = [
            BenchmarkStreamShapeProfileReport(
                label: "visible-focus-rgb565",
                requestRegion: .viewportPhonePortrait,
                requestRegionAreaPermille: 364,
                firstFrameRequestAreaPermille: 192,
                firstFrameMilliseconds: 16_299,
                summary: BenchmarkStreamShapeSummary(
                    requestedSamples: samples.count,
                    samples: samples,
                    elapsedMilliseconds: 1_830,
                    firstTimeoutMilliseconds: nil,
                    failureLabel: nil,
                    practicalTargets: .iPhonePoorNetworkTraffic
                )
            )
        ]

        let gate = BenchmarkStreamShapeProfileGateReport.gates(from: reports)[0]

        XCTAssertEqual(gate.targetName, "iphone-poor-network-traffic-v1")
        XCTAssertEqual(gate.verdict, .warning)
        XCTAssertTrue(gate.issueCodes.contains(.firstFrameWarning))
        XCTAssertFalse(gate.issueCodes.contains(.firstFrameFailed))
        XCTAssertEqual(gate.averageRequestRegionAreaPermille, 364)
        XCTAssertEqual(gate.averageFirstFrameRequestAreaPermille, 192)
    }

    func testPoorNetworkTrafficTargetFailsPayloadReadPressure() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 4,
            samples: (0..<4).map { _ in
                phaseBudgetContentSample(
                    duration: 690,
                    receiveTotal: 670,
                    networkRead: 650,
                    firstByteWait: 40,
                    clientProcessing: 20
                )
            },
            elapsedMilliseconds: 2_760,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            practicalTargets: .iPhonePoorNetworkTraffic
        )

        XCTAssertEqual(summary.payloadReadLatency?.p95Milliseconds, 610)
        XCTAssertEqual(summary.phaseBudget.payloadReadSharePermille, 938)
        XCTAssertEqual(summary.practicalAssessment.verdict, .fail)
        XCTAssertTrue(summary.practicalAssessment.issueCodes.contains(.payloadReadFailed))
        XCTAssertEqual(summary.practicalAssessment.primaryIssueCode, .payloadReadFailed)
        XCTAssertEqual(
            summary.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue
        )
        XCTAssertEqual(
            summary.practicalAssessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.compareEncodingProfileGate.rawValue
        )
    }

    func testPoorNetworkTrafficTargetWarnsFirstByteWaitPressureSeparately() {
        let summary = BenchmarkStreamShapeSummary(
            requestedSamples: 4,
            samples: (0..<4).map { _ in
                phaseBudgetContentSample(
                    duration: 640,
                    receiveTotal: 620,
                    networkRead: 600,
                    firstByteWait: 500,
                    clientProcessing: 20
                )
            },
            elapsedMilliseconds: 2_560,
            firstTimeoutMilliseconds: nil,
            failureLabel: nil,
            practicalTargets: .iPhonePoorNetworkTraffic
        )

        XCTAssertEqual(summary.firstByteWaitLatency?.p95Milliseconds, 500)
        XCTAssertEqual(summary.phaseBudget.firstByteWaitSharePermille, 833)
        XCTAssertEqual(summary.practicalAssessment.verdict, .warning)
        XCTAssertTrue(summary.practicalAssessment.issueCodes.contains(.firstByteWaitWarning))
        XCTAssertFalse(summary.practicalAssessment.issueCodes.contains(.payloadReadWarning))
        XCTAssertEqual(summary.practicalAssessment.primaryIssueCode, .firstByteWaitWarning)
        XCTAssertEqual(
            summary.practicalAssessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.receivePath.rawValue
        )
        XCTAssertEqual(
            summary.practicalAssessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.inspectServerTransportCadence.rawValue
        )
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
        XCTAssertNil(summary.firstByteWaitLatency)
        XCTAssertNil(summary.payloadReadLatency)
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

    private func sustainedContentSample(duration: Int) -> BenchmarkStreamShapeSample {
        BenchmarkStreamShapeSample(
            kind: .contentUpdate,
            durationMilliseconds: duration,
            dirtyRectangleCount: 1,
            dirtyAreaPermille: 10,
            changedPixelsPermille: 10,
            rendererUploadStrategy: .partial,
            rendererUploadRegionCount: 1,
            clientProcessingMilliseconds: 8,
            zrleTileApplyMilliseconds: 7
        )
    }

    private func phaseBudgetContentSample(
        duration: Int,
        receiveTotal: Int,
        networkRead: Int,
        firstByteWait: Int? = nil,
        clientProcessing: Int
    ) -> BenchmarkStreamShapeSample {
        BenchmarkStreamShapeSample(
            kind: .contentUpdate,
            durationMilliseconds: duration,
            dirtyRectangleCount: 1,
            dirtyAreaPermille: 10,
            changedPixelsPermille: 10,
            rendererUploadStrategy: .partial,
            rendererUploadRegionCount: 1,
            receiveTotalMilliseconds: receiveTotal,
            networkReadMilliseconds: networkRead,
            firstByteWaitMilliseconds: firstByteWait,
            clientProcessingMilliseconds: clientProcessing,
            zrleTileApplyMilliseconds: 7
        )
    }

    private func sustainedEmptySample(duration: Int) -> BenchmarkStreamShapeSample {
        BenchmarkStreamShapeSample(
            kind: .emptyUpdate,
            durationMilliseconds: duration,
            dirtyRectangleCount: 0,
            dirtyAreaPermille: 0,
            changedPixelsPermille: 0,
            clientProcessingMilliseconds: 2
        )
    }

    private func profileReport(
        label: String,
        durations: [Int],
        iteration: Int,
        pacingWindow: BenchmarkStreamShapePacingWindow = .single,
        requestRegion: BenchmarkStreamShapeRequestRegion = .full,
        requestRegionAreaPermille: Int? = nil,
        firstFrameRequestAreaPermille: Int? = nil,
        firstFrameReceiveTiming: RFBFramebufferUpdateTiming? = nil
    ) -> BenchmarkStreamShapeProfileReport {
        BenchmarkStreamShapeProfileReport(
            label: label,
            transportMode: .requestResponse,
            pacingWindow: pacingWindow,
            requestRegion: requestRegion,
            requestRegionAreaPermille: requestRegionAreaPermille,
            firstFrameRequestAreaPermille: firstFrameRequestAreaPermille,
            iterationOrdinal: iteration,
            orderOrdinal: 1,
            firstFrameMilliseconds: 100,
            firstFrameReceiveTiming: firstFrameReceiveTiming,
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
