import CoreGraphics
import Foundation
import NaruRemoteCore

public enum BenchmarkStreamShapeRequestRegion: String, Codable, Equatable, Sendable, CaseIterable {
    public static let defaultFirstFrameVisibleGlanceScale = 0.45
    public static let minimumFirstFrameVisibleGlanceScale = 0.10
    public static let maximumFirstFrameVisibleGlanceScale = 1.00

    case full
    case centerHalf = "center-half"
    case centerThird = "center-third"
    case viewportPhonePortrait = "viewport-phone-portrait"
    case viewportPhonePortraitHeartbeat = "viewport-phone-portrait-heartbeat"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    public static let requestRegionSweep: [BenchmarkStreamShapeRequestRegion] = [
        .full,
        .centerHalf,
        .centerThird
    ]

    public static let viewportRequestRegionSweep: [BenchmarkStreamShapeRequestRegion] = [
        .full,
        .viewportPhonePortrait,
        .viewportPhonePortraitHeartbeat
    ]

    public var allowsRegionTimeoutFullFallback: Bool {
        switch self {
        case .viewportPhonePortrait, .viewportPhonePortraitHeartbeat:
            return true
        case .full, .centerHalf, .centerThird:
            return false
        }
    }

    public func region(width: Int, height: Int) -> RFBFramebufferUpdateRegion? {
        region(width: width, height: height, incrementalRequestIndex: 1)
    }

    public func requestAreaPermille(width: Int, height: Int) -> Int {
        let safeWidth = min(max(width, 0), Int(UInt16.max))
        let safeHeight = min(max(height, 0), Int(UInt16.max))
        guard safeWidth > 0, safeHeight > 0 else {
            return 1_000
        }

        switch self {
        case .viewportPhonePortraitHeartbeat:
            return heartbeatRequestAreaPermille(width: safeWidth, height: safeHeight, interval: 5)
        case .full, .centerHalf, .centerThird, .viewportPhonePortrait:
            return requestAreaPermille(
                for: region(width: safeWidth, height: safeHeight, incrementalRequestIndex: 1),
                framebufferWidth: safeWidth,
                framebufferHeight: safeHeight
            )
        }
    }

    public func firstFrameVisibleCoreRegion(width: Int, height: Int) -> RFBFramebufferUpdateRegion? {
        switch self {
        case .full:
            return nil
        case .centerHalf, .centerThird:
            return region(width: width, height: height, incrementalRequestIndex: 1)
        case .viewportPhonePortrait, .viewportPhonePortraitHeartbeat:
            return phonePortraitViewportRegion(
                width: width,
                height: height,
                incrementalRequestIndex: 1,
                regionTimeoutStreak: 0,
                expansionMarginPixels: 0,
                fullHeartbeatInterval: nil
            )
        }
    }

    public func firstFrameVisibleCoreAreaPermille(width: Int, height: Int) -> Int {
        requestAreaPermille(
            for: firstFrameVisibleCoreRegion(width: width, height: height),
            framebufferWidth: width,
            framebufferHeight: height
        )
    }

    public func firstFrameVisibleFocusRegion(width: Int, height: Int) -> RFBFramebufferUpdateRegion? {
        guard let core = firstFrameVisibleCoreRegion(width: width, height: height) else {
            return nil
        }

        // Fixed benchmark policy: 80% of the visible core on each axis.
        let focusWidth = max(Int((Double(core.width) * 0.8).rounded()), 1)
        let focusHeight = max(Int((Double(core.height) * 0.8).rounded()), 1)
        let insetX = max((Int(core.width) - focusWidth) / 2, 0)
        let insetY = max((Int(core.height) - focusHeight) / 2, 0)
        return RFBFramebufferUpdateRegion(
            x: UInt16(Int(core.x) + insetX),
            y: UInt16(Int(core.y) + insetY),
            width: UInt16(focusWidth),
            height: UInt16(focusHeight)
        )
    }

    public func firstFrameVisibleFocusAreaPermille(width: Int, height: Int) -> Int {
        requestAreaPermille(
            for: firstFrameVisibleFocusRegion(width: width, height: height),
            framebufferWidth: width,
            framebufferHeight: height
        )
    }

    public static func normalizedFirstFrameVisibleGlanceScale(_ scale: Double) -> Double {
        min(max(scale, minimumFirstFrameVisibleGlanceScale), maximumFirstFrameVisibleGlanceScale)
    }

    public static func firstFrameVisibleGlanceScalePermille(_ scale: Double) -> Int {
        let normalized = normalizedFirstFrameVisibleGlanceScale(scale)
        return min(max(Int((normalized * 1_000).rounded()), 0), 1_000)
    }

    public func firstFrameVisibleGlanceRegion(
        width: Int,
        height: Int,
        scale: Double = Self.defaultFirstFrameVisibleGlanceScale
    ) -> RFBFramebufferUpdateRegion? {
        guard let core = firstFrameVisibleCoreRegion(width: width, height: height) else {
            return nil
        }

        return core.centeredScaled(by: Self.normalizedFirstFrameVisibleGlanceScale(scale))
    }

    public func firstFrameVisibleGlanceAreaPermille(
        width: Int,
        height: Int,
        scale: Double = Self.defaultFirstFrameVisibleGlanceScale
    ) -> Int {
        requestAreaPermille(
            for: firstFrameVisibleGlanceRegion(width: width, height: height, scale: scale),
            framebufferWidth: width,
            framebufferHeight: height
        )
    }

    public func region(
        width: Int,
        height: Int,
        incrementalRequestIndex: Int,
        regionTimeoutStreak: Int = 0
    ) -> RFBFramebufferUpdateRegion? {
        switch self {
        case .full:
            return nil
        case .centerHalf:
            return centeredRegion(width: width, height: height, divisor: 2)
        case .centerThird:
            return centeredRegion(width: width, height: height, divisor: 3)
        case .viewportPhonePortrait:
            return phonePortraitViewportRegion(
                width: width,
                height: height,
                incrementalRequestIndex: incrementalRequestIndex,
                regionTimeoutStreak: regionTimeoutStreak,
                expansionMarginPixels: 96,
                fullHeartbeatInterval: nil
            )
        case .viewportPhonePortraitHeartbeat:
            return phonePortraitViewportRegion(
                width: width,
                height: height,
                incrementalRequestIndex: incrementalRequestIndex,
                regionTimeoutStreak: regionTimeoutStreak,
                expansionMarginPixels: 96,
                fullHeartbeatInterval: 5
            )
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

    private func heartbeatRequestAreaPermille(width: Int, height: Int, interval: Int) -> Int {
        let interval = max(interval, 1)
        let permilles = (1...interval).map { index in
            requestAreaPermille(
                for: region(width: width, height: height, incrementalRequestIndex: index),
                framebufferWidth: width,
                framebufferHeight: height
            )
        }
        return Int((Double(permilles.reduce(0, +)) / Double(interval)).rounded())
    }

    public func requestAreaPermille(
        for region: RFBFramebufferUpdateRegion?,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> Int {
        let framebufferWidth = min(max(framebufferWidth, 0), Int(UInt16.max))
        let framebufferHeight = min(max(framebufferHeight, 0), Int(UInt16.max))
        guard framebufferWidth > 0, framebufferHeight > 0 else {
            return 1_000
        }
        guard let region else {
            return 1_000
        }
        let framebufferArea = max(framebufferWidth * framebufferHeight, 1)
        let regionArea = Int(region.width) * Int(region.height)
        let rounded = Int((Double(regionArea) / Double(framebufferArea) * 1_000).rounded())
        return regionArea > 0 ? min(max(rounded, 1), 1_000) : 0
    }

    private func phonePortraitViewportRegion(
        width: Int,
        height: Int,
        incrementalRequestIndex: Int,
        regionTimeoutStreak: Int,
        expansionMarginPixels: Int,
        fullHeartbeatInterval: Int?
    ) -> RFBFramebufferUpdateRegion? {
        let safeWidth = min(max(width, 0), Int(UInt16.max))
        let safeHeight = min(max(height, 0), Int(UInt16.max))
        guard safeWidth > 0, safeHeight > 0 else {
            return nil
        }

        let framebufferSize = CGSize(width: safeWidth, height: safeHeight)
        let viewSize = CGSize(width: 390, height: 844)
        let fit = ViewportTransform(framebufferSize: framebufferSize, viewSize: viewSize)
        let fillZoom = max(
            viewSize.width / framebufferSize.width,
            viewSize.height / framebufferSize.height
        ) / fit.fitScale
        let transform = ViewportTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: fillZoom
        )
        let policy = ViewportRequestRegionPolicy(
            expansionMarginPixels: expansionMarginPixels,
            minimumSavingsPermille: 100,
            fullHeartbeatInterval: fullHeartbeatInterval,
            fullFallbackTimeoutStreak: 1
        )
        return policy.requestRegion(
            for: transform,
            incrementalRequestIndex: incrementalRequestIndex,
            regionTimeoutStreak: regionTimeoutStreak
        )
    }
}
