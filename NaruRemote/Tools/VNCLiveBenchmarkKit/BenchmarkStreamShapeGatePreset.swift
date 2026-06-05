public enum BenchmarkStreamShapeGatePreset: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case sustainedV2Core = "sustained-v2-core"
    case sustainedV2RequestResponse = "sustained-v2-request-response"
    case sustainedV2PixelFormat = "sustained-v2-pixel-format"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}
