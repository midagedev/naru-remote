import Foundation
import NaruRemoteCore

public enum BenchmarkStreamShapeFirstFrameRequestMode: String, Codable, Equatable, Sendable, CaseIterable {
    case full
    case matchRequestRegion = "match-request-region"
    case visibleCore = "visible-core"

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
            // Use the request-region policy's first visible candidate for the
            // first non-incremental frame. Heartbeat/fallback escalation starts
            // only after measured incremental requests begin.
            return requestRegion.region(
                width: framebufferWidth,
                height: framebufferHeight,
                incrementalRequestIndex: 1,
                regionTimeoutStreak: 0
            )
        case .visibleCore:
            // Start with the exact fixed visible core for startup survival,
            // then let measured incremental requests use the normal margin,
            // heartbeat, and timeout fallback policy.
            return requestRegion.firstFrameVisibleCoreRegion(
                width: framebufferWidth,
                height: framebufferHeight
            )
        }
    }

    public func requestAreaPermille(
        matching requestRegion: BenchmarkStreamShapeRequestRegion,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> Int {
        switch self {
        case .full:
            return 1_000
        case .matchRequestRegion:
            return requestRegion.requestAreaPermille(width: framebufferWidth, height: framebufferHeight)
        case .visibleCore:
            return requestRegion.firstFrameVisibleCoreAreaPermille(
                width: framebufferWidth,
                height: framebufferHeight
            )
        }
    }
}
