public enum BenchmarkStreamShapeGatePreset: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case sustainedV2Core = "sustained-v2-core"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}
