import Foundation

public enum FramebufferUploadStrategy: String, Codable, Equatable, Sendable {
    case none
    case full
    case partial
}

public struct FramebufferUploadPlan: Codable, Equatable, Sendable {
    public static let maximumPartialUploadRegionCount = 64
    public static let maximumPartialUploadAreaFraction = 0.60

    public let strategy: FramebufferUploadStrategy
    public let uploadRegionCount: Int

    public init(strategy: FramebufferUploadStrategy, uploadRegionCount: Int) {
        self.strategy = strategy
        self.uploadRegionCount = max(uploadRegionCount, 0)
    }

    public static func plan(
        framebufferWidth: Int,
        framebufferHeight: Int,
        dirtyRectangles: [RFBFrameDamageRect]?,
        requiresTextureRecreation: Bool,
        shouldUpload: Bool = true
    ) -> FramebufferUploadPlan {
        guard shouldUpload, framebufferWidth > 0, framebufferHeight > 0 else {
            return FramebufferUploadPlan(strategy: .none, uploadRegionCount: 0)
        }

        let validDirtyRectangles = validDirtyRectangles(
            dirtyRectangles,
            textureWidth: framebufferWidth,
            textureHeight: framebufferHeight
        )

        guard !requiresTextureRecreation, !validDirtyRectangles.isEmpty else {
            return FramebufferUploadPlan(strategy: .full, uploadRegionCount: 1)
        }

        guard validDirtyRectangles.count <= maximumPartialUploadRegionCount else {
            return FramebufferUploadPlan(strategy: .full, uploadRegionCount: 1)
        }

        guard dirtyAreaFraction(
            validDirtyRectangles,
            textureWidth: framebufferWidth,
            textureHeight: framebufferHeight
        ) <= maximumPartialUploadAreaFraction else {
            return FramebufferUploadPlan(strategy: .full, uploadRegionCount: 1)
        }

        return FramebufferUploadPlan(
            strategy: .partial,
            uploadRegionCount: validDirtyRectangles.count
        )
    }

    public static func validDirtyRectangles(
        _ rectangles: [RFBFrameDamageRect]?,
        textureWidth: Int,
        textureHeight: Int
    ) -> [RFBFrameDamageRect] {
        guard let rectangles else {
            return []
        }

        return rectangles.filter { rect in
            rect.width > 0
                && rect.height > 0
                && rect.x >= 0
                && rect.y >= 0
                && rect.x <= textureWidth - rect.width
                && rect.y <= textureHeight - rect.height
        }
    }

    public static func dirtyAreaFraction(
        _ rectangles: [RFBFrameDamageRect],
        textureWidth: Int,
        textureHeight: Int
    ) -> Double {
        let fullArea = textureWidth * textureHeight
        guard fullArea > 0 else {
            return 1
        }
        let dirtyArea = rectangles.reduce(0) { total, rect in
            total + rect.width * rect.height
        }
        return Double(dirtyArea) / Double(fullArea)
    }
}
