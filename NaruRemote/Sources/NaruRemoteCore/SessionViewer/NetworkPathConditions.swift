import Foundation

/// Two privacy-safe bits from the live network path.
///
/// `isConstrained` is Low Data Mode and is the only cap trigger.
/// `isExpensive` (cellular/hotspot as such) is captured for future
/// diagnostics and MUST NOT degrade streams by itself (constitution
/// §VI — cellular is the baseline scenario). Interface names, SSIDs,
/// and endpoints never belong here (constitution §IV).
///
/// `.unknown` is both-false and errs toward not capping.
public struct NetworkPathConditions: Equatable, Sendable {
    public let isExpensive: Bool
    public let isConstrained: Bool

    public static let unknown = NetworkPathConditions(
        isExpensive: false,
        isConstrained: false
    )

    public init(isExpensive: Bool, isConstrained: Bool) {
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}
