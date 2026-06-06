import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkNetworkConditionProfileTests: XCTestCase {
    func testUsageDescriptionListsStableLabels() {
        XCTAssertEqual(
            BenchmarkNetworkConditionProfile.usageDescription,
            "none|wan-latency|constrained-cellular"
        )
    }

    func testNoneHasNoConditionSettings() {
        XCTAssertNil(BenchmarkNetworkConditionProfile.none.settings)
    }

    func testConstrainedCellularChunksAndDelaysTraffic() throws {
        let settings = try XCTUnwrap(BenchmarkNetworkConditionProfile.constrainedCellular.settings)

        XCTAssertEqual(settings.chunkByteCounts(for: 20_000), [8_192, 8_192, 3_616])
        XCTAssertEqual(settings.chunkByteCounts(for: 0), [])
        XCTAssertGreaterThan(settings.delaySeconds(forChunkByteCount: 8_192), 0.18)
        XCTAssertLessThan(settings.delaySeconds(forChunkByteCount: 8_192), 0.19)
        XCTAssertGreaterThan(
            settings.delaySeconds(forChunkByteCount: 8_192, startsBurst: false),
            0.06
        )
        XCTAssertLessThan(
            settings.delaySeconds(forChunkByteCount: 8_192, startsBurst: false),
            0.07
        )
    }

    func testWanLatencyAddsDelayWithoutThroughputCap() throws {
        let settings = try XCTUnwrap(BenchmarkNetworkConditionProfile.wanLatency.settings)

        XCTAssertEqual(settings.chunkByteCounts(for: 20_000), [16_384, 3_616])
        XCTAssertEqual(settings.delaySeconds(forChunkByteCount: 16_384), 0.08, accuracy: 0.001)
        XCTAssertEqual(
            settings.delaySeconds(forChunkByteCount: 16_384, startsBurst: false),
            0,
            accuracy: 0.001
        )
    }
}
