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

    func testClientPressureStateActivatesAppFloorAfterRepeatedLaggingContentSamples() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 1.0 / 60.0,
            idleFrameInterval: 0.05,
            clientPressureMode: .app
        )
        var state = BenchmarkStreamShapeClientPressureState()
        let slowContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 120,
            networkReadMilliseconds: 20,
            clientProcessingMilliseconds: 100
        )

        state.record(sample: slowContent, mode: policy.clientPressureMode)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        XCTAssertEqual(
            policy.delay(
                isEmptyUpdate: false,
                emptyUpdateStreak: 0,
                usesAdaptiveClientPressure: state.usesAdaptivePowerSaverPacing
            ),
            1.0 / 60.0,
            accuracy: 0.0001
        )

        state.record(sample: slowContent, mode: policy.clientPressureMode)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)

        state.record(sample: slowContent, mode: policy.clientPressureMode)
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
        XCTAssertEqual(
            policy.delay(
                isEmptyUpdate: false,
                emptyUpdateStreak: 0,
                usesAdaptiveClientPressure: state.usesAdaptivePowerSaverPacing
            ),
            1.0 / 30.0,
            accuracy: 0.0001
        )
    }

    func testClientPressureStateActivatesAppFloorAfterSustainedModerateContentSamples() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 1.0 / 60.0,
            idleFrameInterval: 0.05,
            clientPressureMode: .app
        )
        var state = BenchmarkStreamShapeClientPressureState()
        let moderateContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 55,
            networkReadMilliseconds: 15,
            clientProcessingMilliseconds: 40
        )

        for _ in 0..<(BenchmarkStreamShapePacingPolicy.appConsecutiveSustainedLaggingContentFrameThreshold - 1) {
            state.record(sample: moderateContent, mode: policy.clientPressureMode)
            XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        }

        state.record(sample: moderateContent, mode: policy.clientPressureMode)

        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
        XCTAssertEqual(
            policy.delay(
                isEmptyUpdate: false,
                emptyUpdateStreak: 0,
                usesAdaptiveClientPressure: state.usesAdaptivePowerSaverPacing
            ),
            1.0 / 30.0,
            accuracy: 0.0001
        )
    }

    func testClientPressureStateBreaksModerateStreakOnHealthyContentSample() {
        var state = BenchmarkStreamShapeClientPressureState()
        let moderateContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 55,
            networkReadMilliseconds: 15,
            clientProcessingMilliseconds: 40
        )
        let healthyContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 25,
            networkReadMilliseconds: 10,
            clientProcessingMilliseconds: 15
        )

        for _ in 0..<(BenchmarkStreamShapePacingPolicy.appConsecutiveSustainedLaggingContentFrameThreshold - 1) {
            state.record(sample: moderateContent, mode: .app)
        }
        state.record(sample: healthyContent, mode: .app)
        state.record(sample: moderateContent, mode: .app)

        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
    }

    func testClientPressureStateIgnoresNetworkWaitAndEmptySamples() {
        var state = BenchmarkStreamShapeClientPressureState()
        let slowNetworkContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 120,
            networkReadMilliseconds: 100,
            clientProcessingMilliseconds: 20
        )
        let slowEmpty = streamShapeSample(
            kind: .emptyUpdate,
            receiveTotalMilliseconds: 120,
            networkReadMilliseconds: 20,
            clientProcessingMilliseconds: 100
        )

        for _ in 0..<6 {
            state.record(sample: slowNetworkContent, mode: .app)
            state.record(sample: slowEmpty, mode: .app)
        }

        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
    }

    func testClientPressureStateDoesNotBreakContentStreakOnEmptySamples() {
        var state = BenchmarkStreamShapeClientPressureState()
        let slowContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 120,
            networkReadMilliseconds: 20,
            clientProcessingMilliseconds: 100
        )
        let empty = streamShapeSample(
            kind: .emptyUpdate,
            receiveTotalMilliseconds: 10,
            networkReadMilliseconds: 10,
            clientProcessingMilliseconds: 0
        )

        state.record(sample: slowContent, mode: .app)
        state.record(sample: empty, mode: .app)
        state.record(sample: slowContent, mode: .app)
        state.record(sample: empty, mode: .app)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)

        state.record(sample: slowContent, mode: .app)

        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testClientPressureStateOffModeStaysInactive() {
        var state = BenchmarkStreamShapeClientPressureState()
        let slowContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 120,
            networkReadMilliseconds: 20,
            clientProcessingMilliseconds: 100
        )

        for _ in 0..<BenchmarkStreamShapePacingPolicy.appConsecutiveLaggingContentFrameThreshold {
            state.record(sample: slowContent, mode: .off)
        }

        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
    }

    private func streamShapeSample(
        kind: BenchmarkStreamUpdateKind,
        receiveTotalMilliseconds: Int,
        networkReadMilliseconds: Int,
        clientProcessingMilliseconds: Int
    ) -> BenchmarkStreamShapeSample {
        BenchmarkStreamShapeSample(
            kind: kind,
            durationMilliseconds: receiveTotalMilliseconds,
            dirtyRectangleCount: kind == .contentUpdate ? 1 : 0,
            dirtyAreaPermille: kind == .contentUpdate ? 1 : 0,
            changedPixelsPermille: kind == .contentUpdate ? 1 : 0,
            receiveTotalMilliseconds: receiveTotalMilliseconds,
            networkReadMilliseconds: networkReadMilliseconds,
            clientProcessingMilliseconds: clientProcessingMilliseconds
        )
    }
}
