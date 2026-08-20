/// Pure in-lane recovery policy for helper-video decoder rejections.
///
/// Count-based and clock-free: a decoder rejection either requests a keyframe,
/// is swallowed while a recovery budget is armed, or falls back to VNC.
/// Constants and the decision table are spec 019 FR-003.
public struct HelperVideoKeyframeRecoveryPolicy: Equatable, Sendable {
    public static let maxRecoveryAttemptsPerStream = 2
    public static let recoveryBudgetAccessUnits = 30

    public private(set) var attemptsUsed = 0
    public private(set) var isRecovering = false
    public private(set) var remainingBudget = 0

    public enum DecoderRejectionDecision: Equatable, Sendable {
        case fallback
        case requestKeyframe
        case swallow
    }

    public init() {}

    public var isBudgetExhausted: Bool {
        isRecovering && remainingBudget == 0
    }

    public mutating func handleDecoderRejection(
        supportsKeyframeRequest: Bool
    ) -> DecoderRejectionDecision {
        guard supportsKeyframeRequest else {
            return .fallback
        }

        if isRecovering {
            return remainingBudget > 0 ? .swallow : .fallback
        }

        guard attemptsUsed < Self.maxRecoveryAttemptsPerStream else {
            return .fallback
        }

        attemptsUsed += 1
        isRecovering = true
        remainingBudget = Self.recoveryBudgetAccessUnits
        return .requestKeyframe
    }

    public mutating func recordReceivedAccessUnitWhileRecovering() {
        guard isRecovering else {
            return
        }
        remainingBudget = max(remainingBudget - 1, 0)
    }

    public mutating func noteDisplayableFrame() {
        guard isRecovering else {
            return
        }
        isRecovering = false
        remainingBudget = 0
    }
}
