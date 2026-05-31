import XCTest
@testable import NaruRemoteCore

final class ConnectionQualityTests: XCTestCase {
    func testBucketThresholds() {
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: 0), .good)
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: 79), .good)
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: 80), .fair)
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: 249), .fair)
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: 250), .poor)
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: 5_000), .poor)
    }

    func testBucketRejectsInvalidSamples() {
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: -1), .unknown)
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: .nan), .unknown)
        XCTAssertEqual(ConnectionQuality.bucket(forLatencyMilliseconds: .infinity), .unknown)
    }

    func testEstimatorStartsUnknown() {
        let estimator = ConnectionQualityEstimator()
        XCTAssertNil(estimator.smoothedLatencyMilliseconds)
        XCTAssertEqual(estimator.quality, .unknown)
    }

    func testEstimatorFirstSampleSeedsAverage() {
        var estimator = ConnectionQualityEstimator(alpha: 0.3)
        estimator.record(latencyMilliseconds: 100)
        XCTAssertEqual(estimator.smoothedLatencyMilliseconds ?? -1, 100, accuracy: 1e-6)
        XCTAssertEqual(estimator.quality, .fair)
    }

    func testEstimatorSmoothsSubsequentSamples() {
        var estimator = ConnectionQualityEstimator(alpha: 0.3)
        estimator.record(latencyMilliseconds: 100)
        estimator.record(latencyMilliseconds: 300)
        // 100 + 0.3 * (300 - 100) = 160
        XCTAssertEqual(estimator.smoothedLatencyMilliseconds ?? -1, 160, accuracy: 1e-6)
        XCTAssertEqual(estimator.quality, .fair)
    }

    func testEstimatorIgnoresInvalidSamples() {
        var estimator = ConnectionQualityEstimator()
        estimator.record(latencyMilliseconds: .nan)
        estimator.record(latencyMilliseconds: -10)
        XCTAssertEqual(estimator.quality, .unknown)
    }

    func testResetClearsHistory() {
        var estimator = ConnectionQualityEstimator()
        estimator.record(latencyMilliseconds: 50)
        XCTAssertEqual(estimator.quality, .good)
        estimator.reset()
        XCTAssertEqual(estimator.quality, .unknown)
    }
}
