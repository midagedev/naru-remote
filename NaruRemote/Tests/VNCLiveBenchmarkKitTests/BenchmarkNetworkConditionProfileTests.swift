import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkNetworkConditionProfileTests: XCTestCase {
    func testUsageDescriptionListsStableLabels() {
        // Extended 2026-08-25 by spec 029, which added two profiles derived from
        // a measurement of the founder's actual link. The existing three labels
        // keep their spelling and their order — this pins the CLI contract, so
        // the point of it is that old labels never move, not that new ones can
        // never be added.
        XCTAssertEqual(
            BenchmarkNetworkConditionProfile.usageDescription,
            "none|wan-latency|constrained-cellular|tailnet-mobile-median|tailnet-mobile-tail"
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

    // MARK: - Measured mobile profiles (spec 029)

    func testTheMobileProfilesModelTheMeasuredLink() {
        // The founder's iPhone, direct over a mobile network, measured
        // 2026-08-25: 41 56 232 372 416 65 137 500 ms round trip.
        let median = try! XCTUnwrap(
            BenchmarkNetworkConditionProfile.tailnetMobileMedian.settings
        )
        XCTAssertEqual(median.oneWayDelayMilliseconds * 2, 184, "round trip near the measured median")
        XCTAssertGreaterThan(median.jitterMilliseconds, 0, "a fixed delay cannot model a 12x spread")
        XCTAssertNil(
            median.throughputKilobitsPerSecond,
            "the mobile profiles isolate round-trip time; a bandwidth cap would confound that"
        )

        let tail = try! XCTUnwrap(
            BenchmarkNetworkConditionProfile.tailnetMobileTail.settings
        )
        XCTAssertEqual(tail.oneWayDelayMilliseconds * 2, 500, "round trip at the observed maximum")
        XCTAssertGreaterThan(tail.oneWayDelayMilliseconds, median.oneWayDelayMilliseconds)
    }

    func testJitterIsReplayableAcrossRuns() {
        // A benchmark whose conditioning cannot be replayed produces numbers
        // that cannot be compared between arms — which is the failure mode
        // spec 025 was written about.
        let settings = BenchmarkNetworkConditionSettings(
            oneWayDelayMilliseconds: 92,
            throughputKilobitsPerSecond: nil,
            maxChunkBytes: 16 * 1024,
            jitterMilliseconds: 70
        )
        let first = (0..<64).map { settings.jitteredOneWayDelayMilliseconds(sequence: $0) }
        let second = (0..<64).map { settings.jitteredOneWayDelayMilliseconds(sequence: $0) }
        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(Set(first).count, 20, "consecutive bursts must not share one delay")
    }

    func testJitterStaysInsideItsBandAndNeverGoesNegative() {
        let settings = BenchmarkNetworkConditionSettings(
            oneWayDelayMilliseconds: 30,
            throughputKilobitsPerSecond: nil,
            maxChunkBytes: 1024,
            jitterMilliseconds: 90
        )
        for sequence in 0..<2_000 {
            let delay = settings.jitteredOneWayDelayMilliseconds(sequence: sequence)
            XCTAssertGreaterThanOrEqual(delay, 0, "a negative delay would send a chunk into the past")
            XCTAssertLessThanOrEqual(delay, 30 + 90)
        }
    }

    func testZeroJitterKeepsTheOriginalFixedDelayBehaviour() {
        let settings = BenchmarkNetworkConditionSettings(
            oneWayDelayMilliseconds: 80,
            throughputKilobitsPerSecond: nil,
            maxChunkBytes: 16 * 1024
        )
        for sequence in 0..<32 {
            XCTAssertEqual(settings.jitteredOneWayDelayMilliseconds(sequence: sequence), 80)
        }
        XCTAssertEqual(
            BenchmarkNetworkConditionProfile.wanLatency.settings?.jitterMilliseconds,
            0,
            "the pre-existing profiles must be unchanged by spec 029"
        )
    }
}
