public enum BenchmarkStreamShapeGatePreset: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case sustainedV2Core = "sustained-v2-core"
    case sustainedV2RequestResponse = "sustained-v2-request-response"
    case sustainedV2ZrleIsolation = "sustained-v2-zrle-isolation"
    case sustainedV2ZrleZeroDelay = "sustained-v2-zrle-zero-delay"
    case sustainedV2ZrlePacingSweep = "sustained-v2-zrle-pacing-sweep"
    case sustainedV2ZrleRegionSweep = "sustained-v2-zrle-region-sweep"
    case sustainedV2PixelFormat = "sustained-v2-pixel-format"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}
