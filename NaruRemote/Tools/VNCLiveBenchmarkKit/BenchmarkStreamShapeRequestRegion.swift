import Foundation
import NaruRemoteCore

public enum BenchmarkStreamShapeRequestRegion: String, Codable, Equatable, Sendable, CaseIterable {
    case full
    case centerHalf = "center-half"
    case centerThird = "center-third"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    public static let requestRegionSweep: [BenchmarkStreamShapeRequestRegion] = [
        .full,
        .centerHalf,
        .centerThird
    ]

    public func region(width: Int, height: Int) -> RFBFramebufferUpdateRegion? {
        switch self {
        case .full:
            return nil
        case .centerHalf:
            return centeredRegion(width: width, height: height, divisor: 2)
        case .centerThird:
            return centeredRegion(width: width, height: height, divisor: 3)
        }
    }

    private func centeredRegion(width: Int, height: Int, divisor: Int) -> RFBFramebufferUpdateRegion? {
        let safeWidth = min(max(width, 0), Int(UInt16.max))
        let safeHeight = min(max(height, 0), Int(UInt16.max))
        guard safeWidth > 0, safeHeight > 0 else {
            return nil
        }

        let regionWidth = max(safeWidth / max(divisor, 1), 1)
        let regionHeight = max(safeHeight / max(divisor, 1), 1)
        let x = max((safeWidth - regionWidth) / 2, 0)
        let y = max((safeHeight - regionHeight) / 2, 0)
        return RFBFramebufferUpdateRegion(
            x: UInt16(x),
            y: UInt16(y),
            width: UInt16(regionWidth),
            height: UInt16(regionHeight)
        )
    }
}
