public enum BenchmarkStreamShapeGatePreset: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case sustainedV2Core = "sustained-v2-core"
    case sustainedV2RequestResponse = "sustained-v2-request-response"
    case sustainedV2ZrleIsolation = "sustained-v2-zrle-isolation"
    case sustainedV2ZrleZeroDelay = "sustained-v2-zrle-zero-delay"
    case sustainedV2ZrlePacingSweep = "sustained-v2-zrle-pacing-sweep"
    case sustainedV2ZrleRegionSweep = "sustained-v2-zrle-region-sweep"
    case sustainedV2ZrleViewportRegion = "sustained-v2-zrle-viewport-region"
    case sustainedV2PixelFormat = "sustained-v2-pixel-format"
    case sustainedV2ConstrainedCellularBootstrap = "sustained-v2-constrained-cellular-bootstrap"
    case sustainedV2ConstrainedCellularVisibleStartup = "sustained-v2-constrained-cellular-visible-startup"
    case sustainedV2ConstrainedCellularVisibleCoreStartup =
        "sustained-v2-constrained-cellular-visible-core-startup"
    case sustainedV2ConstrainedCellularVisibleFocusStartup =
        "sustained-v2-constrained-cellular-visible-focus-startup"
    case sustainedV2ConstrainedCellularAppLowTraffic =
        "sustained-v2-constrained-cellular-app-low-traffic"
    case remoteDesktop10FPS = "remote-desktop-10fps"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}
