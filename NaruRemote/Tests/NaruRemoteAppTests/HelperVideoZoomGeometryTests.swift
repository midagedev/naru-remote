import CoreGraphics
import XCTest

@testable import NaruRemoteApp
import NaruRemoteCore

/// Spec 043 FR-004 / hypothesis H4: the helper-video zoom transform is built
/// from the VNC framebuffer size (e.g. 3024×1964) while the decoded video the
/// user sees is the helper's downscale (960×622 at the readability bucket).
/// If the two coordinate spaces diverged, the zoom would visibly misplace the
/// picture or the input overlay would map taps to the wrong framebuffer
/// pixels.
///
/// ## H4 is refuted, with these numbers
///
/// The helper's encode is aspect-preserving to within the even-pixel
/// rounding: for a 3024×1964 display at the readability bucket,
/// `NaruHelperVideoScreenCaptureKitAccessUnitSource` scales by 960/3024 and
/// rounds each dimension to even (`scaledEvenSize`, lines 143–174) —
/// 1964 × 960/3024 = 623.47 → 623 → **622**, width **960**. Aspect error
/// 960/622 vs 3024/1964 is 0.26 %.
///
/// On a 430×812 phone-sized view both spaces are width-constrained, so:
///
/// - the video's `.resizeAspect` band is `aspectFitSize(960/622, 430×812)`
///   = 430 × 278.60;
/// - the transform's content at zoom 1 is
///   `ViewportTransform(3024×1964, 430×812).contentSize` = 430 × 279.27.
///
/// Δ = 0.67 pt vertically, 0 horizontally, at fit; ×4 at zoom 4 = 2.67 pt.
/// Zooming an anchor from 1 to 2.5 drifts a pixel's on-screen position by
/// ≤ ~0.9 pt. All sub-perceptual on a 3×-downscaled video.
///
/// The layer semantics being modeled are production's
/// (`MetalFramebufferView.viewportLayerTransform`, line ~1756): the layer
/// draws the video aspect-fit inside a view that spans the whole viewport,
/// and zoom/pan are applied as
/// `CGAffineTransform(translationX: pan).scaledBy(z, z)` — i.e. scale about
/// the view center, then translate. `ViewportTransform` computes the same
/// centered-scale-plus-pan from the framebuffer side.
///
/// The corollary these tests also pin: input **must** stay in framebuffer
/// space — RFB `PointerEvent` x/y are framebuffer pixels, so a video-space
/// overlay would map taps to the wrong pixels. Deriving the transform from
/// the framebuffer is correct, not a defect.
///
/// Green from the start: these are refutation evidence, not a fix gate
/// (there is no production change for FR-004).
final class HelperVideoZoomGeometryTests: XCTestCase {

    /// The display under test: a 3024×1964 Mac desktop.
    private static let framebufferSize = CGSize(width: 3024, height: 1964)
    /// What the helper encodes at the readability bucket (derivation in the
    /// header comment).
    private static let encodedVideoSize = CGSize(width: 960, height: 622)
    /// A phone-sized viewport.
    private static let viewSize = CGSize(width: 430, height: 812)

    private static let maxZoomScale: CGFloat = 4

    /// Where the encoded video actually appears in the view under
    /// `.resizeAspect` — the same helper the production layer path uses.
    private static func videoBand(in container: CGSize) -> CGSize {
        SessionViewportView.aspectFitSize(
            aspectRatio: encodedVideoSize.width / encodedVideoSize.height,
            containerSize: container
        )
    }

    /// Where a framebuffer pixel lands on screen through the **layer's**
    /// semantics: aspect-fit band (video coordinates), scale about the view
    /// center by the zoom, then pan — mirroring
    /// `MetalFramebufferView.viewportLayerTransform`.
    private static func layerViewPoint(
        framebufferPoint: CGPoint,
        zoomScale: CGFloat,
        panOffset: CGSize
    ) -> CGPoint {
        let band = videoBand(in: viewSize)
        let videoScale = band.width / encodedVideoSize.width
        let pixelToVideo = CGSize(
            width: encodedVideoSize.width / framebufferSize.width,
            height: encodedVideoSize.height / framebufferSize.height
        )
        let bandOrigin = CGPoint(
            x: (viewSize.width - band.width) / 2,
            y: (viewSize.height - band.height) / 2
        )
        let inBand = CGPoint(
            x: bandOrigin.x + framebufferPoint.x * pixelToVideo.width * videoScale,
            y: bandOrigin.y + framebufferPoint.y * pixelToVideo.height * videoScale
        )
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        return CGPoint(
            x: center.x + zoomScale * (inBand.x - center.x) + panOffset.width,
            y: center.y + zoomScale * (inBand.y - center.y) + panOffset.height
        )
    }

    // MARK: - The displayed bands agree

    func testTheVideoBandAndTheTransformContentAgreeAtFit() {
        let transform = ViewportTransform(
            framebufferSize: Self.framebufferSize,
            viewSize: Self.viewSize,
            maxZoomScale: Self.maxZoomScale
        )
        let band = Self.videoBand(in: Self.viewSize)

        print("H4 fit: video band \(band), transform content \(transform.contentSize)")
        XCTAssertEqual(
            abs(band.width - transform.contentSize.width),
            0,
            accuracy: 0.001,
            "Both spaces are width-constrained against this view: widths match exactly"
        )
        XCTAssertLessThanOrEqual(
            abs(band.height - transform.contentSize.height),
            1,
            "0.67 pt of band mismatch at fit is sub-perceptual on 3x-downscaled video"
        )
    }

    func testTheVideoBandAndTheTransformContentAgreeAtMaxZoom() {
        let transform = ViewportTransform(
            framebufferSize: Self.framebufferSize,
            viewSize: Self.viewSize,
            zoomScale: Self.maxZoomScale,
            maxZoomScale: Self.maxZoomScale
        )
        // The layer scales its fit band by the same zoom about the center.
        let band = Self.videoBand(in: Self.viewSize)
        let zoomedBand = CGSize(
            width: band.width * Self.maxZoomScale,
            height: band.height * Self.maxZoomScale
        )

        print("H4 zoom 4: video band \(zoomedBand), transform content \(transform.contentSize)")
        XCTAssertLessThanOrEqual(
            abs(zoomedBand.width - transform.contentSize.width),
            1,
            "Width mismatch at max zoom (4x of an exact match)"
        )
        XCTAssertLessThanOrEqual(
            abs(zoomedBand.height - transform.contentSize.height),
            3,
            "2.67 pt of band mismatch at 4x zoom is the 0.26 % aspect rounding, scaled"
        )
    }

    // MARK: - Pixels stay put through a zoom

    func testAnchoredZoomDriftsOnScreenPositionsByLessThanAPointAndAHalf() {
        let anchor = CGPoint(x: 300, y: 400)
        let transform = ViewportTransform(
            framebufferSize: Self.framebufferSize,
            viewSize: Self.viewSize,
            maxZoomScale: Self.maxZoomScale
        )
        // The production zoom entry point: rescale keeping the framebuffer
        // pixel under `anchor` under `anchor`.
        let zoomed = transform.zoomed(to: 2.5, about: anchor)

        // A grid across the framebuffer, including the far corners from the
        // anchor — where any divergence accumulates most.
        let xs: [CGFloat] = [0, 500, 1512, 2400, 3024]
        let ys: [CGFloat] = [0, 400, 982, 1600, 1964]
        for x in xs {
            for y in ys {
                let pixel = CGPoint(x: x, y: y)
                let viaTransform = zoomed.viewPoint(fromFramebufferPoint: pixel)
                let viaLayer = Self.layerViewPoint(
                    framebufferPoint: pixel,
                    zoomScale: zoomed.zoomScale,
                    panOffset: zoomed.panOffset
                )
                let drift = hypot(
                    viaTransform.x - viaLayer.x,
                    viaTransform.y - viaLayer.y
                )
                XCTAssertLessThanOrEqual(
                    drift,
                    1.5,
                    "pixel (\(x), \(y)) drifts \(drift) pt between the two coordinate spaces at zoom \(zoomed.zoomScale)"
                )
            }
        }
    }

    // MARK: - Input must stay in framebuffer space (the corollary)

    func testInputMappingNeedsFramebufferCoordinates() {
        let transform = ViewportTransform(
            framebufferSize: Self.framebufferSize,
            viewSize: Self.viewSize,
            maxZoomScale: Self.maxZoomScale
        )

        // RFB PointerEvent x/y are framebuffer pixels (RFC 6143 §7.5.4), so
        // the transform the overlay uses has to speak framebuffer — the
        // center of the view is the center of the desktop, and the video's
        // coordinate space never enters this path.
        let center = CGPoint(x: Self.viewSize.width / 2, y: Self.viewSize.height / 2)
        let framebufferPoint = transform.framebufferPoint(fromViewPoint: center)
        XCTAssertEqual(framebufferPoint?.x ?? -1, 1512, accuracy: 0.5)
        XCTAssertEqual(framebufferPoint?.y ?? -1, 982, accuracy: 0.5)
    }
}
