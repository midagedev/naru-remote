import CoreGraphics
import Foundation

/// UIKit-free accumulator for the viewport interaction hot path.
///
/// `MetalFramebufferHostingView` and helper-video's rendererless input overlay
/// ultimately operate on the same values: a clamped local `ViewportTransform`
/// plus immediate per-sample updates. Keeping this tiny driver in Core gives
/// benchmarks and tests a stable way to stress that math without constructing
/// UIKit views or display links.
public struct ViewportInputHotPathDriver: Sendable {
    public private(set) var transform: ViewportTransform
    public private(set) var minimumZoomScale: CGFloat
    public let maxZoomScale: CGFloat

    public init(
        framebufferSize: CGSize,
        viewSize: CGSize,
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero,
        minimumZoomScale: CGFloat = 1,
        maxZoomScale: CGFloat = 4
    ) {
        let cappedMaxZoomScale = max(1, maxZoomScale)
        self.minimumZoomScale = min(max(minimumZoomScale, 1), cappedMaxZoomScale)
        self.maxZoomScale = cappedMaxZoomScale
        self.transform = Self.makeTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: zoomScale,
            panOffset: panOffset,
            minimumZoomScale: self.minimumZoomScale,
            maxZoomScale: cappedMaxZoomScale
        )
    }

    @discardableResult
    public mutating func sync(
        framebufferSize: CGSize? = nil,
        viewSize: CGSize? = nil,
        zoomScale: CGFloat? = nil,
        panOffset: CGSize? = nil,
        minimumZoomScale: CGFloat? = nil
    ) -> ViewportInputHotPathUpdate {
        let previous = transform
        if let minimumZoomScale {
            self.minimumZoomScale = min(max(minimumZoomScale, 1), maxZoomScale)
        }
        transform = Self.makeTransform(
            framebufferSize: framebufferSize ?? transform.framebufferSize,
            viewSize: viewSize ?? transform.viewSize,
            zoomScale: zoomScale ?? transform.zoomScale,
            panOffset: panOffset ?? transform.panOffset,
            minimumZoomScale: self.minimumZoomScale,
            maxZoomScale: maxZoomScale
        )
        return ViewportInputHotPathUpdate(previous: previous, current: transform)
    }

    @discardableResult
    public mutating func applyPan(translation: CGSize) -> ViewportInputHotPathUpdate {
        guard translation != .zero else {
            return ViewportInputHotPathUpdate(previous: transform, current: transform)
        }
        let previous = transform
        transform = transform.panned(by: translation)
        return ViewportInputHotPathUpdate(previous: previous, current: transform)
    }

    @discardableResult
    public mutating func applyPinch(
        scaleMultiplier: CGFloat,
        anchor: CGPoint,
        anchorDelta: CGSize = .zero
    ) -> ViewportInputHotPathUpdate {
        guard scaleMultiplier.isFinite, scaleMultiplier > 0 else {
            return ViewportInputHotPathUpdate(previous: transform, current: transform)
        }
        let previous = transform
        transform = transform.pinched(
            to: transform.zoomScale * scaleMultiplier,
            about: anchor,
            anchorDelta: anchorDelta,
            minimumZoomScale: minimumZoomScale
        )
        return ViewportInputHotPathUpdate(previous: previous, current: transform)
    }

    @discardableResult
    public mutating func adopt(_ updated: ViewportTransform) -> ViewportInputHotPathUpdate {
        let previous = transform
        transform = Self.makeTransform(
            framebufferSize: updated.framebufferSize,
            viewSize: updated.viewSize,
            zoomScale: updated.zoomScale,
            panOffset: updated.panOffset,
            minimumZoomScale: minimumZoomScale,
            maxZoomScale: maxZoomScale
        )
        return ViewportInputHotPathUpdate(previous: previous, current: transform)
    }

    private static func makeTransform(
        framebufferSize: CGSize,
        viewSize: CGSize,
        zoomScale: CGFloat,
        panOffset: CGSize,
        minimumZoomScale: CGFloat,
        maxZoomScale: CGFloat
    ) -> ViewportTransform {
        ViewportTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: min(max(zoomScale, minimumZoomScale), maxZoomScale),
            panOffset: panOffset,
            maxZoomScale: maxZoomScale
        )
    }
}

public struct ViewportInputHotPathUpdate: Equatable, Sendable {
    public let previous: ViewportTransform
    public let current: ViewportTransform

    public var zoomDidChange: Bool {
        abs(previous.zoomScale - current.zoomScale) > 0.0001
    }

    public var panDidChange: Bool {
        previous.panOffset != current.panOffset
    }

    public var didChange: Bool {
        zoomDidChange || panDidChange
    }
}
