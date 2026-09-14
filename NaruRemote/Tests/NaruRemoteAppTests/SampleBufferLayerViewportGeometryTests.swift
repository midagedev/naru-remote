import QuartzCore
import XCTest
@testable import NaruRemoteApp
@testable import NaruRemoteCore

/// Spec 044: the helper-video picture and the drawn cursor are two renderings
/// of one `ViewportTransform`, and nothing may move one without the other.
///
/// Founder, 2026-09-14, physical iPhone: "트랙패드 모드에서 앱에서 그려진
/// 커서와 실제 원격화면에 보이는 커서가 위치가 심하게 차이난다" and then, after
/// the first round of measurement, "vnc는 잘 동작해 헬퍼가 문제야". The
/// coordinates were never wrong — a live probe against this Mac's Screen
/// Sharing server put every pointer event on its addressed pixel with 0 pt of
/// error, and a DEBUG read-out on the drawn cursor matched the Mac's real
/// pointer exactly, zoomed and unzoomed, in a VNC session. What was wrong was
/// where the *video* got drawn.
///
/// ## Contract ↔ assertion table (FR-001..FR-003 → tests)
///
/// | Clause | Test |
/// | --- | --- |
/// | Placing the shared layer twice under a live viewport transform leaves its
///   geometry unchanged (FR-001). |
///   `testPlacingTwiceUnderALiveTransformLeavesTheLayerWhereItWas` |
/// | Placement is idempotent at the identity transform too, so the fix cannot
///   be read as "only matters when zoomed" (FR-001). |
///   `testPlacingTwiceAtTheIdentityTransformIsAlsoStable` |
/// | The rect the layer occupies equals the content rect `ViewportTransform`
///   reports for the same container, zoom and pan (FR-003). |
///   `testPlacedLayerOccupiesTheViewportTransformContentRect` |
final class SampleBufferLayerViewportGeometryTests: XCTestCase {

    private static let container = CGRect(x: 0, y: 0, width: 402, height: 874)

    // MARK: FR-001 — the defect

    /// The failing case. `CALayer.frame` is derived from `bounds`, `position`
    /// and `transform`, and assigning it while a transform is live is
    /// undefined: Core Animation inverts the transform over the rect it was
    /// given. The hosting view assigned `frame` on every `updateUIView` and
    /// every layout pass, so the layer shrank by the zoom factor and shifted
    /// by the pan — the video then rendered unzoomed and displaced while the
    /// cursor overlay kept using the real zoom and pan.
    func testPlacingTwiceUnderALiveTransformLeavesTheLayerWhereItWas() {
        let layer = CALayer()
        SampleBufferLayerViewportGeometry.place(layer, in: Self.container)
        SampleBufferLayerViewportGeometry.applyViewportTransform(
            to: layer,
            scale: 3,
            offset: CGSize(width: 12, height: -30)
        )

        let boundsAfterFirstPlacement = layer.bounds
        let positionAfterFirstPlacement = layer.position

        // A second layout pass, exactly as SwiftUI drives one.
        SampleBufferLayerViewportGeometry.place(layer, in: Self.container)

        XCTAssertEqual(
            layer.bounds,
            boundsAfterFirstPlacement,
            """
            FR-001 violated: re-placing the shared display layer under a live \
            viewport transform changed its bounds from \
            \(boundsAfterFirstPlacement.size) to \(layer.bounds.size). The \
            picture then draws at a different scale from the cursor overlay, \
            which is the gap the founder saw in helper video, and it is \
            recomputed wrong again on every zoom change.
            """
        )
        XCTAssertEqual(
            layer.position,
            positionAfterFirstPlacement,
            """
            FR-001 violated: re-placing the layer moved it from \
            \(positionAfterFirstPlacement) to \(layer.position) — a constant \
            displacement between the video and the drawn cursor.
            """
        )
        // The placement must be the container itself, not something the
        // transform was folded into.
        XCTAssertEqual(layer.bounds.size, Self.container.size)
        XCTAssertEqual(
            layer.position,
            CGPoint(x: Self.container.midX, y: Self.container.midY)
        )
    }

    // MARK: FR-001 — the contracts the fix must not break

    func testPlacingTwiceAtTheIdentityTransformIsAlsoStable() {
        let layer = CALayer()
        SampleBufferLayerViewportGeometry.place(layer, in: Self.container)
        SampleBufferLayerViewportGeometry.applyViewportTransform(
            to: layer,
            scale: 1,
            offset: .zero
        )
        SampleBufferLayerViewportGeometry.place(layer, in: Self.container)

        XCTAssertEqual(layer.bounds.size, Self.container.size)
        XCTAssertEqual(
            layer.position,
            CGPoint(x: Self.container.midX, y: Self.container.midY)
        )
    }

    // MARK: FR-003 — the picture and the cursor agree

    /// The cursor overlay maps framebuffer pixels through `ViewportTransform`.
    /// The video is placed by this type. They are only two renderings of one
    /// thing if the rect they produce for the same inputs is the same rect —
    /// so this asserts against `ViewportTransform` itself rather than against
    /// a restatement of its arithmetic.
    func testPlacedLayerOccupiesTheViewportTransformContentRect() {
        for (zoom, pan) in [
            (CGFloat(1), CGSize.zero),
            (CGFloat(2.5), CGSize(width: 40, height: -60)),
            (CGFloat(3.35), CGSize(width: -120, height: 90))
        ] {
            // A container-shaped framebuffer makes `fitScale` exactly 1, so
            // the transform's content rect is the container under the same
            // zoom and pan — the comparison is about composition, not fit.
            let transform = ViewportTransform(
                framebufferSize: Self.container.size,
                viewSize: Self.container.size,
                zoomScale: zoom,
                panOffset: pan,
                maxZoomScale: 4
            )

            let layer = CALayer()
            SampleBufferLayerViewportGeometry.place(layer, in: Self.container)
            SampleBufferLayerViewportGeometry.applyViewportTransform(
                to: layer,
                scale: transform.zoomScale,
                // The clamped pan: the overlay draws with the clamped value,
                // so the layer must be given the same one.
                offset: transform.panOffset
            )

            let expected = CGRect(
                origin: transform.contentOrigin,
                size: transform.contentSize
            )
            let actual = layer.frame
            XCTAssertEqual(
                actual.origin.x,
                expected.origin.x,
                accuracy: 0.01,
                "zoom \(zoom): video origin.x \(actual.origin.x) vs cursor space \(expected.origin.x)"
            )
            XCTAssertEqual(
                actual.origin.y,
                expected.origin.y,
                accuracy: 0.01,
                "zoom \(zoom): video origin.y \(actual.origin.y) vs cursor space \(expected.origin.y)"
            )
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.01, "zoom \(zoom): width")
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.01, "zoom \(zoom): height")
        }
    }
}
