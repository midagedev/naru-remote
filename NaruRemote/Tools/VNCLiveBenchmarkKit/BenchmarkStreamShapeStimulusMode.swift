import Foundation

public enum BenchmarkStreamShapeStimulusMode: String, Codable, Equatable, Sendable, CaseIterable {
    case off
    case externalCommand = "external-command"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}
