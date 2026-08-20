import XCTest
@testable import NaruRemoteCore

final class HelperVideoKeyframeRecoveryPolicyTests: XCTestCase {
    func testNoSupportFallsBackWithoutArmingRecovery() {
        var policy = HelperVideoKeyframeRecoveryPolicy()

        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: false),
            .fallback
        )
        XCTAssertEqual(policy.attemptsUsed, 0)
        XCTAssertFalse(policy.isRecovering)
        XCTAssertEqual(policy.remainingBudget, 0)
        XCTAssertFalse(policy.isBudgetExhausted)
    }

    func testFirstRejectionRequestsKeyframeAndArmsBudget() {
        var policy = HelperVideoKeyframeRecoveryPolicy()

        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .requestKeyframe
        )
        XCTAssertEqual(policy.attemptsUsed, 1)
        XCTAssertTrue(policy.isRecovering)
        XCTAssertEqual(
            policy.remainingBudget,
            HelperVideoKeyframeRecoveryPolicy.recoveryBudgetAccessUnits
        )
        XCTAssertFalse(policy.isBudgetExhausted)
    }

    func testFurtherRejectionsAreSwallowedWhileRecovering() {
        var policy = HelperVideoKeyframeRecoveryPolicy()

        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .requestKeyframe
        )
        policy.recordReceivedAccessUnitWhileRecovering()

        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .swallow
        )
        XCTAssertEqual(policy.attemptsUsed, 1)
        XCTAssertTrue(policy.isRecovering)
        XCTAssertEqual(
            policy.remainingBudget,
            HelperVideoKeyframeRecoveryPolicy.recoveryBudgetAccessUnits - 1
        )
    }

    func testDisplayableFrameEndsRecoveryWithoutConsumingAttemptCap() {
        var policy = HelperVideoKeyframeRecoveryPolicy()

        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .requestKeyframe
        )
        policy.recordReceivedAccessUnitWhileRecovering()
        policy.noteDisplayableFrame()

        XCTAssertFalse(policy.isRecovering)
        XCTAssertEqual(policy.remainingBudget, 0)
        XCTAssertEqual(policy.attemptsUsed, 1)
        XCTAssertFalse(policy.isBudgetExhausted)
    }

    func testBudgetExhaustionFallsBack() {
        var policy = HelperVideoKeyframeRecoveryPolicy()

        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .requestKeyframe
        )
        for _ in 0..<HelperVideoKeyframeRecoveryPolicy.recoveryBudgetAccessUnits {
            policy.recordReceivedAccessUnitWhileRecovering()
        }

        XCTAssertTrue(policy.isBudgetExhausted)
        XCTAssertEqual(policy.remainingBudget, 0)
        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .fallback
        )
        XCTAssertEqual(policy.attemptsUsed, 1)
    }

    func testAttemptCapFallsBackOnThirdRejectionAfterRecoveries() {
        var policy = HelperVideoKeyframeRecoveryPolicy()

        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .requestKeyframe
        )
        policy.noteDisplayableFrame()
        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .requestKeyframe
        )
        policy.noteDisplayableFrame()

        XCTAssertEqual(policy.attemptsUsed, 2)
        XCTAssertFalse(policy.isRecovering)
        XCTAssertEqual(
            policy.handleDecoderRejection(supportsKeyframeRequest: true),
            .fallback
        )
        XCTAssertEqual(
            HelperVideoKeyframeRecoveryPolicy.maxRecoveryAttemptsPerStream,
            2
        )
    }

    func testReceivedUnitsOutsideRecoveryDoNotChangeBudget() {
        var policy = HelperVideoKeyframeRecoveryPolicy()

        policy.recordReceivedAccessUnitWhileRecovering()
        policy.noteDisplayableFrame()

        XCTAssertEqual(policy.attemptsUsed, 0)
        XCTAssertFalse(policy.isRecovering)
        XCTAssertEqual(policy.remainingBudget, 0)
    }
}
