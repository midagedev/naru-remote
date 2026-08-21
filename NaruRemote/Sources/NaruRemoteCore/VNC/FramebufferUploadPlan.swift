import Foundation

public enum FramebufferUploadStrategy: String, Codable, Equatable, Sendable {
    case none
    case full
    case partial
}

public struct FramebufferUploadPlan: Codable, Equatable, Sendable {
    public static let maximumPartialUploadRegionCount = 64
    public static let maximumPartialUploadAreaFraction = 0.60
    public static let maximumSparsePartialUploadAreaFraction = 0.85
    public static let maximumSparsePartialChangedPixelFraction = 0.10
    /// Above this many incoming rectangles, skip coalescing and let the area
    /// rules decide — see `coalesced`.
    public static let maximumCoalescingInputCount = 512

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
        changedPixelCount: Int? = nil,
        shouldUpload: Bool = true
    ) -> FramebufferUploadPlan {
        guard shouldUpload, framebufferWidth > 0, framebufferHeight > 0 else {
            return FramebufferUploadPlan(strategy: .none, uploadRegionCount: 0)
        }

        let regions = uploadRegions(
            dirtyRectangles,
            textureWidth: framebufferWidth,
            textureHeight: framebufferHeight
        )

        guard !requiresTextureRecreation, !regions.isEmpty else {
            return FramebufferUploadPlan(strategy: .full, uploadRegionCount: 1)
        }
        guard regions.count <= maximumPartialUploadRegionCount else {
            return FramebufferUploadPlan(strategy: .full, uploadRegionCount: 1)
        }

        let dirtyAreaFraction = dirtyAreaFraction(
            regions,
            textureWidth: framebufferWidth,
            textureHeight: framebufferHeight
        )
        let canUseSparsePartialUpload = sparseDamageCanUsePartialUpload(
            dirtyAreaFraction: dirtyAreaFraction,
            changedPixelCount: changedPixelCount,
            textureWidth: framebufferWidth,
            textureHeight: framebufferHeight
        )
        guard dirtyAreaFraction <= maximumPartialUploadAreaFraction || canUseSparsePartialUpload else {
            return FramebufferUploadPlan(strategy: .full, uploadRegionCount: 1)
        }

        return FramebufferUploadPlan(
            strategy: .partial,
            uploadRegionCount: regions.count
        )
    }

    /// The regions a partial upload must actually copy — the **single owner**
    /// of that list (spec 024). `plan` counts these and the renderer uploads
    /// exactly these, so the reported region count and the work done can never
    /// disagree.
    ///
    /// Beyond validating the server's rectangles, this coalesces them when they
    /// outnumber `maximumPartialUploadRegionCount`. Too many rectangles is a
    /// reason to *merge*, not a reason to re-upload every pixel: live-measured
    /// 2026-08-21 against real Screen Sharing under a controlled 12 Hz
    /// stimulus, damage averaged 0.5% of the framebuffer (peak 6.8%) while the
    /// rectangle count peaked at 112 — so the count cap alone sent 3 of 18
    /// content frames down the full-upload path, which the benchmark reports as
    /// its primary issue (`full-upload-failed` → `rendererUpload`). Lifting the
    /// cap under an otherwise identical stimulus cleared that issue, which is
    /// how this branch was identified rather than guessed.
    ///
    /// The merged set always covers every original rectangle, so a partial
    /// upload can never leave a damaged pixel stale.
    public static func uploadRegions(
        _ dirtyRectangles: [RFBFrameDamageRect]?,
        textureWidth: Int,
        textureHeight: Int
    ) -> [RFBFrameDamageRect] {
        let valid = validDirtyRectangles(
            dirtyRectangles,
            textureWidth: textureWidth,
            textureHeight: textureHeight
        )
        guard valid.count > maximumPartialUploadRegionCount else {
            return valid
        }
        return coalesced(valid, maximumRegionCount: maximumPartialUploadRegionCount)
    }

    /// Merges rectangles until at most `maximumRegionCount` remain, always
    /// taking the cheapest merge available — the pair whose union adds the least
    /// area. Least-added-area is what keeps the merge honest: joining two
    /// rectangles on the same text line costs almost nothing, while joining
    /// opposite corners of the screen costs everything, so the cheap merges
    /// happen first and `plan`'s area guard still catches a genuinely
    /// screen-wide change.
    ///
    /// Candidates are restricted to neighbours in raster order (sorted by y then
    /// x) rather than all pairs. That is what makes the cost bearable per frame:
    /// all-pairs greedy is cubic in the rectangle count, which at the 512-input
    /// ceiling would be tens of millions of comparisons on every frame — far
    /// worse than the full upload it is trying to avoid. Raster order puts
    /// same-line neighbours next to each other, so the cheap merges are exactly
    /// the ones still in the candidate set.
    ///
    /// Bailing out above `maximumCoalescingInputCount` is deliberate: a frame
    /// arriving with that many rectangles has changed enough that one full
    /// upload is the cheaper answer.
    static func coalesced(
        _ rectangles: [RFBFrameDamageRect],
        maximumRegionCount: Int
    ) -> [RFBFrameDamageRect] {
        guard maximumRegionCount > 0 else { return rectangles }
        guard rectangles.count > maximumRegionCount else { return rectangles }
        guard rectangles.count <= maximumCoalescingInputCount else { return rectangles }

        // Raster order. A merged rectangle keeps the earlier neighbour's key
        // (its origin is the min of the two), so the array stays ordered.
        var working = rectangles.sorted { first, second in
            first.y != second.y ? first.y < second.y : first.x < second.x
        }

        while working.count > maximumRegionCount {
            var bestCost = Int.max
            var bestIndex = 0
            for index in 0..<(working.count - 1) {
                let cost = unionAddedArea(working[index], working[index + 1])
                if cost < bestCost {
                    bestCost = cost
                    bestIndex = index
                }
            }
            working[bestIndex] = union(working[bestIndex], working[bestIndex + 1])
            working.remove(at: bestIndex + 1)
        }
        return working
    }

    static func union(
        _ first: RFBFrameDamageRect,
        _ second: RFBFrameDamageRect
    ) -> RFBFrameDamageRect {
        let minX = Swift.min(first.x, second.x)
        let minY = Swift.min(first.y, second.y)
        let maxX = Swift.max(first.x + first.width, second.x + second.width)
        let maxY = Swift.max(first.y + first.height, second.y + second.height)
        return RFBFrameDamageRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func unionAddedArea(
        _ first: RFBFrameDamageRect,
        _ second: RFBFrameDamageRect
    ) -> Int {
        let merged = union(first, second)
        return merged.pixelCount - first.pixelCount - second.pixelCount
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

    private static func sparseDamageCanUsePartialUpload(
        dirtyAreaFraction: Double,
        changedPixelCount: Int?,
        textureWidth: Int,
        textureHeight: Int
    ) -> Bool {
        guard dirtyAreaFraction <= maximumSparsePartialUploadAreaFraction,
              let changedPixelCount
        else {
            return false
        }
        let fullArea = textureWidth * textureHeight
        guard fullArea > 0 else {
            return false
        }
        let changedFraction = Double(max(changedPixelCount, 0)) / Double(fullArea)
        return changedFraction <= maximumSparsePartialChangedPixelFraction
    }
}
