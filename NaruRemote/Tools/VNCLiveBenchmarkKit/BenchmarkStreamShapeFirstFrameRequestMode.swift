import Foundation
import NaruRemoteCore

public enum BenchmarkStreamShapeFirstFrameRequestMode: String, Codable, Equatable, Sendable, CaseIterable {
    case full
    case matchRequestRegion = "match-request-region"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    public func initialRegion(
        matching requestRegion: BenchmarkStreamShapeRequestRegion,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> RFBFramebufferUpdateRegion? {
        switch self {
        case .full:
            return nil
        case .matchRequestRegion:
            return requestRegion.region(
                width: framebufferWidth,
                height: framebufferHeight,
                incrementalRequestIndex: 1,
                regionTimeoutStreak: 0
            )
        }
    }
}
