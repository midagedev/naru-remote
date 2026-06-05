import XCTest
import NaruRemoteCore
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapePacingPolicyTests: XCTestCase {
    func testBenchmarkBalancedCadenceMatchesAppDefault() {
        XCTAssertEqual(
            BenchmarkStreamShapePacingPolicy.appBalancedContentFrameInterval,
            StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds,
            accuracy: 0.0001
        )
    }

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

    func testViewportInteractionModeAppliesAppFloorsWhenConfiguredDelayIsNonZero() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 1.0 / 60.0,
            idleFrameInterval: 0.05,
            emptyBackoffMode: .app,
            viewportInteractionMode: .app
        )

        let contentDecision = policy.decision(isEmptyUpdate: false, emptyUpdateStreak: 1)
        XCTAssertEqual(
            contentDecision.delay,
            BenchmarkStreamShapePacingPolicy.appViewportInteractionContentFrameInterval,
            accuracy: 0.0001
        )
        XCTAssertTrue(contentDecision.usesViewportInteractionPacing)

        let idleDecision = policy.decision(isEmptyUpdate: true, emptyUpdateStreak: 1)
        XCTAssertEqual(
            idleDecision.delay,
            BenchmarkStreamShapePacingPolicy.appViewportInteractionIdleFrameInterval,
            accuracy: 0.0001
        )
        XCTAssertTrue(idleDecision.usesViewportInteractionPacing)
    }

    func testViewportInteractionModePreservesExplicitZeroDelayRuns() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: 0,
            idleFrameInterval: 0,
            emptyBackoffMode: .app,
            viewportInteractionMode: .app
        )

        let contentDecision = policy.decision(isEmptyUpdate: false, emptyUpdateStreak: 1)
        let idleDecision = policy.decision(isEmptyUpdate: true, emptyUpdateStreak: 24)

        XCTAssertEqual(contentDecision.delay, 0, accuracy: 0.0001)
        XCTAssertFalse(contentDecision.usesViewportInteractionPacing)
        XCTAssertEqual(idleDecision.delay, 0, accuracy: 0.0001)
        XCTAssertFalse(idleDecision.usesViewportInteractionPacing)
    }

    func testViewportInteractionModeReportsTiedAppFloorAsActive() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: BenchmarkStreamShapePacingPolicy
                .appViewportInteractionContentFrameInterval,
            idleFrameInterval: 0.05,
            emptyBackoffMode: .app,
            viewportInteractionMode: .app
        )

        let contentDecision = policy.decision(isEmptyUpdate: false, emptyUpdateStreak: 1)
        let idleDecision = policy.decision(isEmptyUpdate: true, emptyUpdateStreak: 24)

        XCTAssertEqual(
            contentDecision.delay,
            BenchmarkStreamShapePacingPolicy.appViewportInteractionContentFrameInterval,
            accuracy: 0.0001
        )
        XCTAssertTrue(contentDecision.usesViewportInteractionPacing)
        XCTAssertEqual(
            idleDecision.delay,
            BenchmarkStreamShapePacingPolicy.appViewportInteractionIdleFrameInterval,
            accuracy: 0.0001
        )
        XCTAssertTrue(idleDecision.usesViewportInteractionPacing)
    }

    func testViewportInteractionModeToleratesRoundedFloorValues() {
        let policy = BenchmarkStreamShapePacingPolicy(
            contentFrameInterval: BenchmarkStreamShapePacingPolicy
                .appViewportInteractionContentFrameInterval + 0.000_000_5,
            idleFrameInterval: 0.05,
            emptyBackoffMode: .app,
            viewportInteractionMode: .app
        )

        let decision = policy.decision(isEmptyUpdate: false, emptyUpdateStreak: 1)

        XCTAssertEqual(
            decision.delay,
            BenchmarkStreamShapePacingPolicy.appViewportInteractionContentFrameInterval + 0.000_000_5,
            accuracy: 0.0001
        )
        XCTAssertTrue(decision.usesViewportInteractionPacing)
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

    func testClientPressureStateActivatesAfterSustainedFullUploadContentSamples() {
        var state = BenchmarkStreamShapeClientPressureState()
        let fullUploadContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 25,
            networkReadMilliseconds: 10,
            clientProcessingMilliseconds: nil,
            rendererUploadStrategy: .full
        )

        for _ in 0..<(BenchmarkStreamShapePacingPolicy.appConsecutiveFullUploadContentFrameThreshold - 1) {
            state.record(sample: fullUploadContent, mode: .app)
            XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        }

        state.record(sample: fullUploadContent, mode: .app)

        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testClientPressureStateBreaksFullUploadStreakOnPartialContentSample() {
        var state = BenchmarkStreamShapeClientPressureState()
        let fullUploadContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 25,
            networkReadMilliseconds: 10,
            clientProcessingMilliseconds: nil,
            rendererUploadStrategy: .full
        )
        let partialContent = streamShapeSample(
            kind: .contentUpdate,
            receiveTotalMilliseconds: 25,
            networkReadMilliseconds: 10,
            clientProcessingMilliseconds: nil,
            rendererUploadStrategy: .partial
        )

        for _ in 0..<(BenchmarkStreamShapePacingPolicy.appConsecutiveFullUploadContentFrameThreshold - 1) {
            state.record(sample: fullUploadContent, mode: .app)
        }
        state.record(sample: partialContent, mode: .app)
        state.record(sample: fullUploadContent, mode: .app)

        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
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
        clientProcessingMilliseconds: Int?,
        rendererUploadStrategy: FramebufferUploadStrategy = .none
    ) -> BenchmarkStreamShapeSample {
        BenchmarkStreamShapeSample(
            kind: kind,
            durationMilliseconds: receiveTotalMilliseconds,
            dirtyRectangleCount: kind == .contentUpdate ? 1 : 0,
            dirtyAreaPermille: kind == .contentUpdate ? 1 : 0,
            changedPixelsPermille: kind == .contentUpdate ? 1 : 0,
            rendererUploadStrategy: rendererUploadStrategy,
            rendererUploadRegionCount: rendererUploadStrategy == .none ? 0 : 1,
            receiveTotalMilliseconds: receiveTotalMilliseconds,
            networkReadMilliseconds: networkReadMilliseconds,
            clientProcessingMilliseconds: clientProcessingMilliseconds
        )
    }
}
