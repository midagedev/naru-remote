import CoreGraphics
import Foundation
import QuartzCore

/// Single owner of where the shared `AVSampleBufferDisplayLayer` sits inside
/// its host view, and of the viewport transform applied to it (spec 044
/// FR-001/FR-002).
///
/// It exists because that geometry used to be set in three places on a layer
/// that is *shared* with the PiP controller — `frame` in `attach(layer:)`,
/// `frame` again in `layoutSubviews`, and the transform in a third method —
/// so nothing could state what the layer's geometry was supposed to be. The
/// founder's report (2026-09-14, "vnc는 잘 동작해 헬퍼가 문제야") was the
/// consequence: see `SampleBufferLayerViewportGeometryTests` for the numbers.
///
/// Deliberately free of UIKit so `swift test` can hold it to its invariant on
/// every run. The hosting view is iOS-only and the repository's iOS unit-test
/// bundle is the benchmark target, so before this type there was nowhere the
/// fast gate could reach this code at all.
///
/// Constitution §IV: layer geometry is not user-entered content; nothing here
/// is logged or persisted.
enum SampleBufferLayerViewportGeometry {

    /// Places `layer` to fill `containerBounds`.
    ///
    /// Uses `bounds` and `position` rather than `frame` on purpose. `frame` is
    /// derived from those two and the transform, and Core Animation documents
    /// its value as undefined while a non-identity transform is set — it
    /// resolves an assignment by inverting the live transform over the rect it
    /// was given. Measured on 2026-09-14 with scale 3 and translation
    /// (12, −30) over a 402×874 container: `frame = bounds` moved the layer
    /// from bounds 402×874 / position (201, 437) to bounds 134×291.3 /
    /// position (189, 467), cancelling the zoom and displacing the picture
    /// while the cursor overlay kept drawing at the real zoom and pan.
    /// Re-assigning the same rect is a fixed point rather than a runaway
    /// (measured: bounds stay 134×291.3 across three passes), but the wrong
    /// geometry is recomputed from scratch on every zoom change.
    ///
    /// `bounds` and `position` carry no such dependency, so this is idempotent
    /// under any transform.
    static func place(_ layer: CALayer, in containerBounds: CGRect) {
        let size = CGSize(
            width: max(containerBounds.width, 0),
            height: max(containerBounds.height, 0)
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.position = CGPoint(x: containerBounds.midX, y: containerBounds.midY)
        CATransaction.commit()
    }

    /// The viewport transform for a local zoom/pan, in the same composition
    /// the Metal path uses for `UIView.transform`: scale about the layer's
    /// centre, then translate by the pan in view points. Matching
    /// `ViewportTransform.contentOrigin`, which is
    /// `(viewSize − contentSize) / 2 + panOffset`.
    static func viewportTransform(scale: CGFloat, offset: CGSize) -> CGAffineTransform {
        let sanitizedScale = scale.isFinite ? max(scale, 0.0001) : 1
        let sanitizedOffset = CGSize(
            width: offset.width.isFinite ? offset.width : 0,
            height: offset.height.isFinite ? offset.height : 0
        )
        return CGAffineTransform(
            translationX: sanitizedOffset.width,
            y: sanitizedOffset.height
        )
        .scaledBy(x: sanitizedScale, y: sanitizedScale)
    }

    /// Applies `viewportTransform(scale:offset:)` to `layer` without an
    /// implicit animation.
    static func applyViewportTransform(to layer: CALayer, scale: CGFloat, offset: CGSize) {
        let transform = viewportTransform(scale: scale, offset: offset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(transform)
        CATransaction.commit()
    }
}
