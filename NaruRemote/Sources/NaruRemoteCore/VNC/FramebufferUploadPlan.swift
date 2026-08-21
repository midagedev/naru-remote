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
    /// Above this many rectangles, a cheap linear pass reduces the set before
    /// the least-added-area merge runs — see `coalesced`. This bounds the
    /// merge's cost without letting the rectangle count decide the strategy.
    ///
    /// 1024, not a smaller number, because the linear pass is blunt: it unions
    /// raster-order runs without weighing what that costs in area, and a frame
    /// pushed past `maximumPartialUploadAreaFraction` that way takes a full
    /// upload it did not need. Measured live 2026-08-21 against real Screen
    /// Sharing, a ceiling of 256 left 57‰ of content frames on the full-upload
    /// path where letting the quality-aware merge see all ~713 rectangles left
    /// 0‰. Real damage counts peaked at 738, so this sits above the working
    /// range with headroom and the linear pass is only the backstop for counts
    /// no server has been observed to send.
    public static let quadraticMergeInputCeiling = 1_024

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
    /// all-pairs greedy is cubic in the rectangle count, which at the counts
    /// this server actually sends would be tens of millions of comparisons on
    /// every frame — far worse than the full upload it is trying to avoid.
    /// Raster order puts
    /// same-line neighbours next to each other, so the cheap merges are exactly
    /// the ones still in the candidate set.
    ///
    /// **No rectangle count falls back to a full upload.** An earlier version of
    /// this bailed out above an input ceiling of 512, on the assumption that a
    /// frame arriving with that many rectangles has changed enough that one full
    /// upload is cheaper. Live measurement 2026-08-21 refuted the assumption:
    /// against real Screen Sharing the damage count is bimodal, sitting at 3
    /// rectangles for half of all frames and jumping to ~713 (peak 738) for the
    /// top few percent — and those high-count frames carried only 34–45% damage
    /// area, comfortably inside the partial-upload area rules. So the ceiling
    /// was re-uploading the whole framebuffer for frames that had changed a
    /// third of it, and it did so for 174‰ of content frames (median of eight
    /// runs). Lifting the ceiling alone under an identical stimulus took that to
    /// 0‰, which is how this branch was attributed rather than reasoned about.
    ///
    /// A count ceiling was the wrong shape for the problem twice over: the first
    /// version of it was 64 (spec 024 replaced that with merging), and its
    /// replacement at 512 sat *below* the counts this server actually sends. A
    /// bound that degrades to the most expensive possible upload is not a
    /// safety valve. So the bound now degrades to a *cheaper merge* instead:
    /// above `quadraticMergeInputCeiling`, a linear pass unions consecutive
    /// raster-order runs to bring the set down to that ceiling, and the
    /// least-added-area merge finishes the job. Cost is O(n log n) for the sort
    /// plus a fixed quadratic term, for any n. The area rules in `plan` remain
    /// the only escape hatch to a full upload, which is correct: a genuine
    /// repaint is identified by how much changed, never by how many messages it
    /// arrived in.
    static func coalesced(
        _ rectangles: [RFBFrameDamageRect],
        maximumRegionCount: Int
    ) -> [RFBFrameDamageRect] {
        guard maximumRegionCount > 0 else { return rectangles }
        guard rectangles.count > maximumRegionCount else { return rectangles }

        // Raster order. A merged rectangle keeps the earlier neighbour's key
        // (its origin is the min of the two), so the array stays ordered.
        var working = rectangles.sorted { first, second in
            first.y != second.y ? first.y < second.y : first.x < second.x
        }

        let quadraticCeiling = Swift.max(maximumRegionCount, quadraticMergeInputCeiling)
        if working.count > quadraticCeiling {
            working = rasterRunReduced(working, targetCount: quadraticCeiling)
        }

        // `costs[i]` is what merging `working[i]` with `working[i + 1]` would
        // add. A merge only changes the two costs adjacent to it, so they are
        // cached and patched rather than recomputed for the whole array on every
        // iteration — measured at the live peak count that took the per-frame
        // cost from 1.2 ms to a fraction of it. Finding the minimum is still a
        // linear scan; a heap would make the whole thing O(n log n), but at the
        // counts this actually runs on the scan is not what costs anything and a
        // lazily-deleted heap over a shrinking neighbour list is a much easier
        // thing to get subtly wrong.
        var costs: [Int] = []
        costs.reserveCapacity(working.count)
        for index in 0..<(working.count - 1) {
            costs.append(unionAddedArea(working[index], working[index + 1]))
        }

        while working.count > maximumRegionCount {
            var bestCost = Int.max
            var bestIndex = 0
            for index in 0..<costs.count where costs[index] < bestCost {
                bestCost = costs[index]
                bestIndex = index
            }

            working[bestIndex] = union(working[bestIndex], working[bestIndex + 1])
            working.remove(at: bestIndex + 1)
            costs.remove(at: bestIndex)

            if bestIndex < costs.count {
                costs[bestIndex] = unionAddedArea(working[bestIndex], working[bestIndex + 1])
            }
            if bestIndex > 0 {
                costs[bestIndex - 1] = unionAddedArea(
                    working[bestIndex - 1],
                    working[bestIndex]
                )
            }
        }
        return working
    }

    /// Unions consecutive runs of an already raster-ordered set until at most
    /// `targetCount` regions remain, in one linear pass.
    ///
    /// This is deliberately blunter than least-added-area merging, and it is the
    /// only part of the merge that does not consider cost. It stays honest
    /// because raster order puts rectangles from the same and adjacent text rows
    /// next to each other, so a run of consecutive entries is a local
    /// neighbourhood rather than an arbitrary pair — and because it only runs at
    /// counts where the quality-aware pass would be too expensive to run per
    /// frame. Whatever it over-unions is still subject to the area rules in
    /// `plan`.
    static func rasterRunReduced(
        _ rectangles: [RFBFrameDamageRect],
        targetCount: Int
    ) -> [RFBFrameDamageRect] {
        guard targetCount > 0, rectangles.count > targetCount else { return rectangles }

        let runLength = (rectangles.count + targetCount - 1) / targetCount
        var reduced: [RFBFrameDamageRect] = []
        reduced.reserveCapacity(targetCount)
        var index = 0
        while index < rectangles.count {
            var merged = rectangles[index]
            let runEnd = Swift.min(index + runLength, rectangles.count)
            var offset = index + 1
            while offset < runEnd {
                merged = union(merged, rectangles[offset])
                offset += 1
            }
            reduced.append(merged)
            index = runEnd
        }
        return reduced
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
