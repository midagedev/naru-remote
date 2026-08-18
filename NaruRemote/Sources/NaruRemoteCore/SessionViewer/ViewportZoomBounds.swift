import CoreGraphics
import Foundation

/// The two zoom scales the session viewport needs, kept apart on purpose.
///
/// `ViewportTransform` measures zoom relative to **fit**: `1.0` draws the whole
/// remote screen inside the view, letterboxed. Above that the content is
/// cropped by the view's edges.
///
/// The hero (full-screen) viewport used to set its *minimum* to the fill scale,
/// which made fill both the opening scale and the floor — so the whole remote
/// screen could never be brought into view, and on a phone the session
/// controls that ride over the top and bottom edges always covered live
/// content. The founder hit exactly that on a device (2026-08-19): "화면 상하에
/// 컨트롤러가 겹치면 그 영역을 다루기가 힘들어서 최대 줌아웃은 가로 너비
/// 기준으로 하거나 그래야할듯해."
///
/// They are now separate: a session still *opens* filled, and the user can zoom
/// out to fit.
public enum ViewportZoomBounds: Sendable {
    /// How far out the user may zoom: fit, the scale that shows everything.
    ///
    /// On a portrait phone against a landscape desktop this is precisely the
    /// requested "fit the width" — the width is the constraining edge, and the
    /// letterbox bands it leaves top and bottom are where the session controls
    /// can sit without covering content. In landscape, where the *phone* is
    /// proportionally wider than the desktop, fit constrains on height instead
    /// and fitting by width would push content back under those controls, so
    /// fit is the better floor in both orientations.
    public static let floorScale: CGFloat = 1

    /// The scale that fills the view — the viewport's opening state, so a
    /// session starts using the whole screen rather than in a letterboxed box.
    ///
    /// Expressed as a multiple of fit: how much more than "everything visible"
    /// is needed to cover the view in both axes.
    public static func fillScale(
        framebufferAspectRatio: CGFloat,
        containerSize: CGSize
    ) -> CGFloat {
        guard framebufferAspectRatio.isFinite,
              framebufferAspectRatio > 0,
              containerSize.width > 0,
              containerSize.height > 0
        else {
            return floorScale
        }

        let containerRatio = containerSize.width / containerSize.height
        guard containerRatio > 0, containerRatio.isFinite else {
            return floorScale
        }

        return max(
            floorScale,
            max(containerRatio / framebufferAspectRatio, framebufferAspectRatio / containerRatio)
        )
    }

    /// Clamps a candidate scale into `[floorScale, maxZoomScale]`.
    public static func clamped(_ scale: CGFloat, maxZoomScale: CGFloat) -> CGFloat {
        let ceiling = max(floorScale, maxZoomScale)
        guard scale.isFinite else {
            return floorScale
        }
        return min(max(scale, floorScale), ceiling)
    }
}
