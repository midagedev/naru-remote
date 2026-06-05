public enum BenchmarkStreamShapeProfileOrderMode: String, Codable, Equatable, Sendable, CaseIterable {
    case fixed
    case rotate

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}
