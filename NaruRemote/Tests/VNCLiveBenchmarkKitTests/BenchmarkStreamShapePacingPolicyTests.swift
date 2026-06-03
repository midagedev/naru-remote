import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapePacingPolicyTests: XCTestCase {
    func testAppModeMatchesNaruIdleBackoffThresholds() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 1.0 / 60.0,
            idleFrameInterval: 0.05,
            emptyBackoffMode: .app
        )

        XCTAssertEqual(policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 1), 0.05, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 8), 0.075, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 24), 0.125, accuracy: 0.0001)
        XCTAssertEqual(
            policy.delay(isEmptyUpdate: false, emptyUpdateStreak: 24),
            1.0 / 60.0,
            accuracy: 0.0001
        )
    }

    func testNoneModeKeepsConfiguredIdleDelayForEveryEmptyUpdate() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 1.0 / 30.0,
            idleFrameInterval: 0.05,
            emptyBackoffMode: .none
        )

        XCTAssertEqual(policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 1), 0.05, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 24), 0.05, accuracy: 0.0001)
    }

    func testZeroIdleDelayStaysZeroForDeterministicRuns() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 1.0 / 30.0,
            idleFrameInterval: 0,
            emptyBackoffMode: .app
        )

        XCTAssertEqual(policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 24), 0, accuracy: 0.0001)
    }

    func testLowPowerModeAppliesAppFloorsWhenConfiguredDelayIsNonZero() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 1.0 / 60.0,
            idleFrameInterval: 0.05,
            emptyBackoffMode: .app,
            powerMode: .lowPower
        )

        XCTAssertEqual(
            policy.delay(isEmptyUpdate: false, emptyUpdateStreak: 1),
            1.0 / 30.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 1),
            0.125,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 24),
            0.125,
            accuracy: 0.0001
        )
    }

    func testLowPowerModePreservesExplicitZeroDelayRuns() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 0,
            idleFrameInterval: 0,
            emptyBackoffMode: .app,
            powerMode: .lowPower
        )

        XCTAssertEqual(policy.delay(isEmptyUpdate: false, emptyUpdateStreak: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(isEmptyUpdate: true, emptyUpdateStreak: 24), 0, accuracy: 0.0001)
    }
}
