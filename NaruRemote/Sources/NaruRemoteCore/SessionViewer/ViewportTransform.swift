import CoreGraphics
import Foundation

/// Pure, UIKit-free mapping between the on-screen view coordinate
/// space (points) and the remote framebuffer coordinate space
/// (pixels), accounting for aspect-fit, user pinch zoom, and pan.
///
/// This is the **single source of truth** for both pointer modes
/// (`spec.md` 003 FR-014) so the direct-touch and trackpad paths can
/// never drift apart. It lives in `NaruRemoteCore` so the geometry is
/// `swift test`-able without a simulator.
///
/// Geometry model: the framebuffer is drawn at
/// `displayScale = fitScale * zoomScale`, centered in the view, then
/// translated by `panOffset` (view-space points). `fitScale` is the
/// `contentMode = .fit` scale (the largest scale that fits the whole
/// framebuffer inside the view). Constitution §I: zoom and pan are
/// LOCAL transforms — this type never produces an RFB message.
public struct ViewportTransform: Equatable, Sendable {
    /// Remote framebuffer size in pixels.
    public let framebufferSize: CGSize
    /// Host view size in points.
    public let viewSize: CGSize
    /// Upper bound on the user pinch zoom multiplier (>= 1).
    public let maxZoomScale: CGFloat
    /// User pinch zoom multiplier, clamped to `[1, maxZoomScale]`.
    public let zoomScale: CGFloat
    /// Pan translation in view points, clamped so horizontal content
    /// edges stay flush against the view. Vertically, an overflowing
    /// axis is additionally allowed `verticalPanBand` points of travel
    /// past flush — see that property.
    public let panOffset: CGSize
    private let resolvedFitScale: CGFloat
    private let resolvedDisplayScale: CGFloat
    private let resolvedContentSize: CGSize
    private let resolvedContentOrigin: CGPoint

    public init(
        framebufferSize: CGSize,
        viewSize: CGSize,
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero,
        maxZoomScale: CGFloat = 4
    ) {
        let fb = CGSize(
            width: Swift.max(framebufferSize.width, 0),
            height: Swift.max(framebufferSize.height, 0)
        )
        let view = CGSize(
            width: Swift.max(viewSize.width, 0),
            height: Swift.max(viewSize.height, 0)
        )
        let cappedMax = Swift.max(1, maxZoomScale)
        let clampedZoom = Swift.min(Swift.max(zoomScale, 1), cappedMax)
        let fitScale = Self.fitScale(framebufferSize: fb, viewSize: view)
        let displayScale = fitScale * clampedZoom
        let content = CGSize(width: fb.width * displayScale, height: fb.height * displayScale)
        let clampedPan = Self.clampPan(panOffset, contentSize: content, viewSize: view)

        self.framebufferSize = fb
        self.viewSize = view
        self.maxZoomScale = cappedMax
        self.zoomScale = clampedZoom
        self.panOffset = clampedPan
        self.resolvedFitScale = fitScale
        self.resolvedDisplayScale = displayScale
        self.resolvedContentSize = content
        self.resolvedContentOrigin = Self.contentOrigin(
            contentSize: content,
            viewSize: view,
            panOffset: clampedPan
        )
    }

    /// Scale that fits the whole framebuffer inside the view.
    public var fitScale: CGFloat {
        resolvedFitScale
    }

    /// Scale at which framebuffer pixels are actually drawn.
    public var displayScale: CGFloat { resolvedDisplayScale }

    /// Size of the displayed framebuffer content in view points.
    public var contentSize: CGSize { resolvedContentSize }

    /// Top-left origin of the displayed content in view space, after
    /// centering and pan.
    public var contentOrigin: CGPoint { resolvedContentOrigin }

    /// `true` once the user has zoomed past the fit scale.
    public var isZoomed: Bool { zoomScale > 1.0001 }

    /// `true` when local pan can reveal off-screen framebuffer content.
    public var isPannable: Bool {
        contentSize.width > viewSize.width + 0.5
            || contentSize.height > viewSize.height + 0.5
    }

    /// Map a view-space point (points) to a framebuffer pixel.
    /// Returns `nil` when the point falls in a letterbox band (outside
    /// the content rect). Callers treat `nil` as a no-op — no clamped
    /// edge click — preserving the established tap behavior.
    public func framebufferPoint(fromViewPoint point: CGPoint) -> CGPoint? {
        guard displayScale > 0 else { return nil }
        let unclamped = framebufferPointUnclamped(fromViewPoint: point)
        guard unclamped.x >= 0,
              unclamped.y >= 0,
              unclamped.x < framebufferSize.width,
              unclamped.y < framebufferSize.height
        else {
            return nil
        }
        return unclamped
    }

    /// Map a framebuffer pixel to a view-space point — used to place
    /// the trackpad cursor overlay over the rendered content.
    public func viewPoint(fromFramebufferPoint point: CGPoint) -> CGPoint {
        let origin = contentOrigin
        return CGPoint(
            x: origin.x + point.x * displayScale,
            y: origin.y + point.y * displayScale
        )
    }

    /// Copy with a new zoom scale (clamped) anchored about a view-space
    /// point so the framebuffer pixel under `anchor` stays under it.
    public func zoomed(to newScale: CGFloat, about anchor: CGPoint) -> ViewportTransform {
        let target = Swift.min(Swift.max(newScale, 1), maxZoomScale)
        let fbUnderAnchor = framebufferPointUnclamped(fromViewPoint: anchor)
        let newDisplay = fitScale * target
        let newContent = CGSize(
            width: framebufferSize.width * newDisplay,
            height: framebufferSize.height * newDisplay
        )
        // Want: anchor.x == newOrigin.x + fbUnderAnchor.x * newDisplay
        // and newOrigin.x == (view - newContent)/2 + newPan.x
        let centeredOriginX = (viewSize.width - newContent.width) / 2
        let centeredOriginY = (viewSize.height - newContent.height) / 2
        let desiredOriginX = anchor.x - fbUnderAnchor.x * newDisplay
        let desiredOriginY = anchor.y - fbUnderAnchor.y * newDisplay
        let newPan = CGSize(
            width: desiredOriginX - centeredOriginX,
            height: desiredOriginY - centeredOriginY
        )
        return ViewportTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: target,
            panOffset: newPan,
            maxZoomScale: maxZoomScale
        )
    }

    /// Copy with an incremental pinch update. In addition to zooming about the
    /// current pinch centroid, this applies the centroid translation so a
    /// two-finger pan during pinch follows the fingers like Photos/Maps.
    public func pinched(
        to newScale: CGFloat,
        about anchor: CGPoint,
        anchorDelta: CGSize = .zero,
        minimumZoomScale: CGFloat = 1
    ) -> ViewportTransform {
        let floor = Swift.min(Swift.max(minimumZoomScale, 1), maxZoomScale)
        let target = Swift.min(Swift.max(newScale, floor), maxZoomScale)
        let previousAnchor = CGPoint(
            x: anchor.x - anchorDelta.width,
            y: anchor.y - anchorDelta.height
        )
        return zoomed(to: target, about: previousAnchor).panned(by: anchorDelta)
    }

    /// Copy translated by a view-space delta (re-clamped).
    public func panned(by delta: CGSize) -> ViewportTransform {
        ViewportTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            maxZoomScale: maxZoomScale,
            zoomScale: zoomScale,
            panOffset: CGSize(
                width: panOffset.width + delta.width,
                height: panOffset.height + delta.height
            ),
            fitScale: resolvedFitScale,
            displayScale: resolvedDisplayScale,
            contentSize: resolvedContentSize
        )
    }

    /// Copy at the fit scale (zoom reset, pan cleared).
    public func reset() -> ViewportTransform {
        ViewportTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: 1,
            panOffset: .zero,
            maxZoomScale: maxZoomScale
        )
    }

    /// Copy with the pan adjusted so a framebuffer pixel is brought
    /// inside the visible viewport with a margin — used by trackpad
    /// auto-pan so the cursor never leaves the screen while zoomed.
    public func panToReveal(framebufferPoint point: CGPoint, margin: CGFloat) -> ViewportTransform {
        guard isZoomed else { return self }
        let view = viewPoint(fromFramebufferPoint: point)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if view.x < margin {
            dx = margin - view.x
        } else if view.x > viewSize.width - margin {
            dx = (viewSize.width - margin) - view.x
        }
        if view.y < margin {
            dy = margin - view.y
        } else if view.y > viewSize.height - margin {
            dy = (viewSize.height - margin) - view.y
        }
        guard dx != 0 || dy != 0 else { return self }
        return panned(by: CGSize(width: dx, height: dy))
    }

    // MARK: - Pure helpers

    private func framebufferPointUnclamped(fromViewPoint point: CGPoint) -> CGPoint {
        let origin = contentOrigin
        return CGPoint(
            x: (point.x - origin.x) / displayScale,
            y: (point.y - origin.y) / displayScale
        )
    }

    static func fitScale(framebufferSize fb: CGSize, viewSize view: CGSize) -> CGFloat {
        guard fb.width > 0, fb.height > 0, view.width > 0, view.height > 0 else {
            return 1
        }
        return Swift.min(view.width / fb.width, view.height / fb.height)
    }

    /// Extra vertical pan travel allowed past flush on an axis that is
    /// already overflowing the viewport — the top/bottom breathing band
    /// (spec 023 FR-003).
    ///
    /// Why it exists: a live session draws its own chrome over the
    /// viewport (the immersive action bar at the top, the floating input
    /// dock at the bottom), and a flush-only clamp means the remote
    /// screen's first and last rows can *only* rest underneath that
    /// chrome. Trackpad mode has no one-finger pan to work around it —
    /// moving the view is auto-pan only — so without the band the remote
    /// Dock and menu bar are reachable but not comfortably clickable.
    ///
    /// Sized to `PointerGestureResolver`'s auto-pan follow margin so a
    /// cursor pushed to the bottom edge comes to rest on the follow line
    /// with the remote screen's bottom row above the dock. It is not a
    /// rubber band: pan parked inside it stays parked (FR-005).
    public static func verticalPanBand(viewSize: CGSize) -> CGFloat {
        guard viewSize.height.isFinite, viewSize.height > 0 else { return 0 }
        return Swift.min(96, viewSize.height * 0.16)
    }

    /// The band actually applied to this transform: zero unless the
    /// vertical axis overflows the viewport.
    public var verticalPanBand: CGFloat {
        Self.verticalPanBand(
            contentSize: resolvedContentSize,
            viewSize: viewSize
        )
    }

    static func verticalPanBand(contentSize: CGSize, viewSize: CGSize) -> CGFloat {
        // Gate on real overflow, not on `zoomScale > 1`: at fit scale (and at
        // any zoom that still leaves the content inside the viewport) the
        // letterbox already provides the breathing room, and letting the
        // fitted image drift inside its own bands would be a new defect
        // (FR-004).
        guard (contentSize.height - viewSize.height) / 2 > 0.5 else { return 0 }
        return verticalPanBand(viewSize: viewSize)
    }

    static func clampPan(_ pan: CGSize, contentSize: CGSize, viewSize: CGSize) -> CGSize {
        let maxX = Swift.max(0, (contentSize.width - viewSize.width) / 2)
        let maxY = Swift.max(0, (contentSize.height - viewSize.height) / 2)
            + verticalPanBand(contentSize: contentSize, viewSize: viewSize)
        return CGSize(
            width: Swift.min(Swift.max(pan.width, -maxX), maxX),
            height: Swift.min(Swift.max(pan.height, -maxY), maxY)
        )
    }

    private init(
        framebufferSize: CGSize,
        viewSize: CGSize,
        maxZoomScale: CGFloat,
        zoomScale: CGFloat,
        panOffset: CGSize,
        fitScale: CGFloat,
        displayScale: CGFloat,
        contentSize: CGSize
    ) {
        let clampedPan = Self.clampPan(
            panOffset,
            contentSize: contentSize,
            viewSize: viewSize
        )
        self.framebufferSize = framebufferSize
        self.viewSize = viewSize
        self.maxZoomScale = maxZoomScale
        self.zoomScale = zoomScale
        self.panOffset = clampedPan
        self.resolvedFitScale = fitScale
        self.resolvedDisplayScale = displayScale
        self.resolvedContentSize = contentSize
        self.resolvedContentOrigin = Self.contentOrigin(
            contentSize: contentSize,
            viewSize: viewSize,
            panOffset: clampedPan
        )
    }

    private static func contentOrigin(
        contentSize: CGSize,
        viewSize: CGSize,
        panOffset: CGSize
    ) -> CGPoint {
        CGPoint(
            x: (viewSize.width - contentSize.width) / 2 + panOffset.width,
            y: (viewSize.height - contentSize.height) / 2 + panOffset.height
        )
    }
}
