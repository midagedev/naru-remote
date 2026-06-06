import CoreGraphics
import Foundation

/// Builds optional RFB framebuffer-update request regions from the local
/// viewport transform. `nil` means "request the full framebuffer".
///
/// Coordinates are framebuffer pixels and must stay out of logs and diagnostic
/// exports (constitution IV). This policy is pure so benchmark and app paths can
/// share it before any production default changes.
public struct ViewportRequestRegionPolicy: Equatable, Sendable {
    /// Extra pixels around the visible viewport. A margin absorbs small cursor,
    /// scroll, and text echo movement without immediately requiring a full
    /// request.
    public let expansionMarginPixels: Int
    /// Minimum area saved before a region is worth using. If the visible region
    /// would cover almost the whole framebuffer, the policy returns nil so the
    /// stream stays on full incremental requests.
    public let minimumSavingsPermille: Int
    /// Request a full framebuffer every N incremental requests. `nil` or values
    /// <= 0 disable the heartbeat.
    public let fullHeartbeatInterval: Int?
    /// After this many region timeouts, force a full request. Values <= 0 disable
    /// timeout-driven fallback.
    public let fullFallbackTimeoutStreak: Int

    public init(
        expansionMarginPixels: Int = 64,
        minimumSavingsPermille: Int = 100,
        fullHeartbeatInterval: Int? = nil,
        fullFallbackTimeoutStreak: Int = 1
    ) {
        self.expansionMarginPixels = max(expansionMarginPixels, 0)
        self.minimumSavingsPermille = min(max(minimumSavingsPermille, 0), 1000)
        self.fullHeartbeatInterval = fullHeartbeatInterval
        self.fullFallbackTimeoutStreak = max(fullFallbackTimeoutStreak, 0)
    }

    public func requestRegion(
        for transform: ViewportTransform,
        incrementalRequestIndex: Int,
        regionTimeoutStreak: Int = 0
    ) -> RFBFramebufferUpdateRegion? {
        guard incrementalRequestIndex > 0 else {
            return nil
        }

        if fullFallbackTimeoutStreak > 0,
           regionTimeoutStreak >= fullFallbackTimeoutStreak {
            return nil
        }

        if let fullHeartbeatInterval,
           fullHeartbeatInterval > 0,
           incrementalRequestIndex % fullHeartbeatInterval == 0 {
            return nil
        }

        return transform.visibleFramebufferUpdateRegion(
            expansionMarginPixels: expansionMarginPixels,
            minimumSavingsPermille: minimumSavingsPermille
        )
    }
}

public extension ViewportTransform {
    /// Returns the visible framebuffer area, expanded and clamped for safe RFB
    /// request-region use. `nil` means the visible area is effectively full-frame
    /// or the transform is not request-region eligible.
    func visibleFramebufferUpdateRegion(
        expansionMarginPixels: Int = 0,
        minimumSavingsPermille: Int = 1
    ) -> RFBFramebufferUpdateRegion? {
        guard displayScale > 0,
              framebufferSize.width > 0,
              framebufferSize.height > 0,
              viewSize.width > 0,
              viewSize.height > 0
        else {
            return nil
        }

        let safeFramebufferWidth = min(Int(framebufferSize.width.rounded(.down)), Int(UInt16.max))
        let safeFramebufferHeight = min(Int(framebufferSize.height.rounded(.down)), Int(UInt16.max))
        guard safeFramebufferWidth > 0, safeFramebufferHeight > 0 else {
            return nil
        }

        let viewRect = CGRect(origin: .zero, size: viewSize)
        let contentRect = CGRect(origin: contentOrigin, size: contentSize)
        let visibleContentRect = viewRect.intersection(contentRect)
        guard !visibleContentRect.isNull,
              visibleContentRect.width > 0,
              visibleContentRect.height > 0
        else {
            return nil
        }

        let margin = max(expansionMarginPixels, 0)
        let minX = Int(floor((visibleContentRect.minX - contentOrigin.x) / displayScale)) - margin
        let minY = Int(floor((visibleContentRect.minY - contentOrigin.y) / displayScale)) - margin
        let maxX = Int(ceil((visibleContentRect.maxX - contentOrigin.x) / displayScale)) + margin
        let maxY = Int(ceil((visibleContentRect.maxY - contentOrigin.y) / displayScale)) + margin

        let x = min(max(minX, 0), safeFramebufferWidth)
        let y = min(max(minY, 0), safeFramebufferHeight)
        let right = min(max(maxX, x), safeFramebufferWidth)
        let bottom = min(max(maxY, y), safeFramebufferHeight)
        let width = right - x
        let height = bottom - y
        guard width > 0, height > 0 else {
            return nil
        }

        if x == 0, y == 0, width >= safeFramebufferWidth, height >= safeFramebufferHeight {
            return nil
        }

        let fullArea = safeFramebufferWidth * safeFramebufferHeight
        let regionArea = width * height
        let savingsPermille = 1000 - (regionArea * 1000 / max(fullArea, 1))
        guard savingsPermille >= min(max(minimumSavingsPermille, 0), 1000) else {
            return nil
        }

        return RFBFramebufferUpdateRegion(
            x: UInt16(x),
            y: UInt16(y),
            width: UInt16(width),
            height: UInt16(height)
        )
    }
}

public extension RFBFramebufferUpdateRegion {
    /// Returns a smaller rectangle centered inside this region. This is useful
    /// for first-useful-paint probes where the stream should fetch a small
    /// visible core before sustained viewport-aware requests take over.
    func centeredScaled(by scale: Double) -> RFBFramebufferUpdateRegion {
        let clampedScale = min(max(scale, 0.01), 1)
        let currentWidth = Int(width)
        let currentHeight = Int(height)
        guard currentWidth > 0, currentHeight > 0 else {
            return self
        }
        let scaledWidth = max(Int((Double(currentWidth) * clampedScale).rounded()), 1)
        let scaledHeight = max(Int((Double(currentHeight) * clampedScale).rounded()), 1)
        let insetX = max((currentWidth - scaledWidth) / 2, 0)
        let insetY = max((currentHeight - scaledHeight) / 2, 0)

        return RFBFramebufferUpdateRegion(
            x: UInt16(min(Int(x) + insetX, Int(UInt16.max))),
            y: UInt16(min(Int(y) + insetY, Int(UInt16.max))),
            width: UInt16(min(scaledWidth, Int(UInt16.max))),
            height: UInt16(min(scaledHeight, Int(UInt16.max)))
        )
    }
}
