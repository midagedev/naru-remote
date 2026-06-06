import Foundation

public struct BenchmarkFirstFrameVisualAudit: Codable, Equatable, Sendable {
    public enum RiskLabel: String, Codable, Equatable, Sendable {
        case glanceOnly = "glance-only"
        case minimalContext = "minimal-context"
        case centralContext = "central-context"
        case broadContext = "broad-context"
    }

    public let model: String
    public let scalePermille: Int
    public let visibleCoreAxisCoveragePermille: Int
    public let visibleCoreAreaCoveragePermille: Int
    public let omittedVisibleCoreAreaPermille: Int
    public let riskLabel: RiskLabel
    public let visualCheckRequired: Bool

    public init(scale: Double) {
        // This is a synthetic terminal-grid coverage proxy, not a live pixel measurement.
        let normalizedScale = BenchmarkStreamShapeRequestRegion.normalizedFirstFrameVisibleGlanceScale(scale)
        let scalePermille = BenchmarkStreamShapeRequestRegion.firstFrameVisibleGlanceScalePermille(normalizedScale)
        let areaPermille = min(max(Int((normalizedScale * normalizedScale * 1_000).rounded()), 0), 1_000)

        self.model = "synthetic-terminal-grid"
        self.scalePermille = scalePermille
        self.visibleCoreAxisCoveragePermille = scalePermille
        self.visibleCoreAreaCoveragePermille = areaPermille
        self.omittedVisibleCoreAreaPermille = 1_000 - areaPermille
        self.riskLabel = Self.riskLabel(forScalePermille: scalePermille)
        self.visualCheckRequired = scalePermille < 400
    }

    private static func riskLabel(forScalePermille scalePermille: Int) -> RiskLabel {
        switch scalePermille {
        case ..<300:
            return .glanceOnly
        case 300..<400:
            return .minimalContext
        case 400..<700:
            return .centralContext
        default:
            return .broadContext
        }
    }
}
