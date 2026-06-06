import NaruRemoteCore
import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeFirstFrameTimingTextTests: XCTestCase {
    func testReceiveLineFormatsFirstFrameTimingStably() {
        let line = BenchmarkStreamShapeFirstFrameTimingText.receiveLine(
            RFBFramebufferUpdateTiming(
                totalMilliseconds: 1_234,
                networkReadMilliseconds: 1_200,
                firstByteWaitMilliseconds: 900
            ),
            indentation: "  "
        )

        XCTAssertEqual(
            line,
            "  first-frame receive ms total/network/first-byte/payload/client: 1234/1200/900/300/34"
        )
    }

    func testReceiveLineOmitsMissingTiming() {
        XCTAssertNil(BenchmarkStreamShapeFirstFrameTimingText.receiveLine(nil, indentation: "  "))
    }

    func testAggregateLinesFormatFirstFrameTimingStably() {
        let aggregate = BenchmarkStreamShapeProfileAggregateReport(
            label: "local-low-latency-rgb565",
            transportMode: .requestResponse,
            requestRegion: .viewportPhonePortrait,
            averageFirstFrameReceiveTotalMilliseconds: 1_234,
            averageFirstFrameNetworkReadMilliseconds: 1_200,
            averageFirstFrameFirstByteWaitMilliseconds: 900,
            averageFirstFramePayloadReadMilliseconds: 300,
            averageFirstFrameClientProcessingMilliseconds: 34,
            averageFirstFrameFirstByteWaitSharePermille: 750,
            averageFirstFramePayloadReadSharePermille: 250,
            runCount: 1,
            usableRunCount: 1,
            failedRunCount: 0,
            averageUpdateMilliseconds: 100,
            maxP95UpdateMilliseconds: 120,
            averageContentFramesPerSecond: 4,
            averageRendererFullUploadPermille: 0,
            maxClientProcessingP95Milliseconds: 12,
            maxZrleTileApplyP95Milliseconds: nil,
            slowUpdateSamples: 0,
            verySlowUpdateSamples: 0,
            receivedSamples: 4,
            contentUpdateSamples: 4
        )

        XCTAssertEqual(
            BenchmarkStreamShapeFirstFrameTimingText.aggregateLines(aggregate, indentation: "  "),
            [
                "  first-frame receive ms avg total/network/first-byte/payload/client: 1234/1200/900/300/34",
                "  first-frame network split permille avg first-byte/payload: 750/250"
            ]
        )
    }
}
