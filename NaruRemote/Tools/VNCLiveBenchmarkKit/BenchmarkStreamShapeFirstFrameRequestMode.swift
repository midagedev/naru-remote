import Foundation
import NaruRemoteCore

public enum BenchmarkStreamShapeFirstFrameRequestMode: String, Codable, Equatable, Sendable, CaseIterable {
    case full
    case matchRequestRegion = "match-request-region"
    case visibleCore = "visible-core"
    case visibleFocus = "visible-focus"
    case visibleGlance = "visible-glance"

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
        case .visibleFocus:
            // Start with a smaller fixed central focus area to test first-frame
            // payload pressure. Sustained requests still use the normal
            // viewport margin, heartbeat, and timeout fallback policy.
            return requestRegion.firstFrameVisibleFocusRegion(
                width: framebufferWidth,
                height: framebufferHeight
            )
        case .visibleGlance:
            // Start with an even smaller fixed central glance area that mirrors
            // the app's first-useful-paint policy. Sustained requests still
            // expand back to the normal viewport margin/heartbeat policy.
            return requestRegion.firstFrameVisibleGlanceRegion(
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
        case .visibleFocus:
            return requestRegion.firstFrameVisibleFocusAreaPermille(
                width: framebufferWidth,
                height: framebufferHeight
            )
        case .visibleGlance:
            return requestRegion.firstFrameVisibleGlanceAreaPermille(
                width: framebufferWidth,
                height: framebufferHeight
            )
        }
    }
}
