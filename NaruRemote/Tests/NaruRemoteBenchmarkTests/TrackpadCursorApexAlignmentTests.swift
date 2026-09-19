import CoreGraphics
import QuartzCore
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(UIKit)
import UIKit

/// Spec 045: the tip of the cursor the app draws in trackpad mode lands on
/// `ViewportTransform.viewPoint(fromFramebufferPoint:)` of the pointer
/// position it is drawing, within 1 view point, at every zoom.
///
/// Founder, 2026-09-19, physical iPhone, helper-video session in trackpad
/// mode: "여전히 마우스 커서가 살짝 어긋나 균일하게 살짝 오른쪽에 보이네" —
/// the remote pointer sits a little to the RIGHT of the drawn one, and the
/// gap shrinks as the viewport zooms in. Measured off screenshots: +8.7 pt
/// at fit zoom, +8.0 pt at maximum zoom — a constant in VIEW points, which
/// rules out every error that scales with zoom (spec 045 Measurements).
///
/// What is NOT re-derived here: the numbers above, the shared video/cursor
/// geometry (ruled out in spec 045), and the capture being clean (measured
/// on the founder's Mac with the helper's own SCStreamConfiguration).
///
/// ## Contract ↔ assertion table (FR-001..FR-003 → tests)
///
/// | Clause | Test |
/// | --- | --- |
/// | The drawn fallback glyph's tip lands on the anchor within 1 pt at fit
///   zoom, centre and off-centre (FR-001, FR-002). |
///   `testFallbackTipLandsOnAnchorAtFitZoom` |
/// | The drawn fallback glyph's tip lands on the anchor within 1 pt at
///   maximum zoom, centre and off-centre (FR-001, FR-002). |
///   `testFallbackTipLandsOnAnchorAtMaximumZoom` |
/// | The drawn server-cursor shape's tip lands on the anchor within 1 pt at
///   fit zoom, centre and off-centre (FR-001, FR-002). |
///   `testServerCursorTipLandsOnAnchorAtFitZoom` |
/// | The drawn server-cursor shape's tip lands on the anchor within 1 pt at
///   maximum zoom, centre and off-centre (FR-001, FR-002). |
///   `testServerCursorTipLandsOnAnchorAtMaximumZoom` |
/// | The tip is located by scanning the RENDERED bitmap, never by asking
///   the placement code where it put the tip (FR-003). | all four above |
/// | Characterisation numbers for a human reading this defect (depth req). |
///   `testCursorApexCharacterisation` (always green, prints only) |
///
/// ## Self-review: defect classes this gate does NOT cover, and why
///
/// 1. Non-zero pan. Placement consumes only the anchor plus constant
///    offsets, so pan enters solely through the asserted contract value —
///    a panned case would assert `ViewportTransform` against itself.
/// 2. The SwiftUI twin (`SessionViewportView.syntheticCursorOverlay`). It
///    is not rendered here, but it consumes the same `tipOffsetFromCenter`
///    static the fix corrects, and its remaining logic (`.position` of the
///    centred box) is pure arithmetic already pinned by
///    `TrackpadCursorGlyphTests.testCentrePlacementPutsTheTipExactlyOnTheAnchor`
///    under `swift test`.
/// 3. A future dark-tipped artwork defeating the bright-opaque scan. The
///    scan then finds nothing and the gate fails loudly (the explicit
///    `XCTFail` paths) rather than passing vacuously — fail-closed by
///    construction, no extra assertion needed.
@MainActor
final class TrackpadCursorApexAlignmentTests: XCTestCase {

    // MARK: - Fixture geometry (known constants the gate drives)

    private static let viewSize = CGSize(width: 390, height: 240)
    private static let framebufferSize = CGSize(width: 1920, height: 1080)
    private static let maxZoom: CGFloat = 4
    private static let renderScale: CGFloat = 3

    /// A small macOS-like arrow: white body, black outline, hotspot exactly
    /// on the apex pixel. The outline runs below-left of the tip row so no
    /// bright pixel sits above or left of the tip — the scan below then has
    /// exactly one correct answer: the hotspot.
    private static func syntheticArrowCursor() -> RFBServerCursor {
        let width = 12
        let height = 18
        let hotSpotX = 3
        let hotSpotY = 1
        let clear = RFBColor(red: 0, green: 0, blue: 0, alpha: 0)
        let white = RFBColor(red: 255, green: 255, blue: 255, alpha: 255)
        let black = RFBColor(red: 0, green: 0, blue: 0, alpha: 255)
        var pixels = [RFBColor](repeating: clear, count: width * height)
        func set(_ x: Int, _ y: Int, _ color: RFBColor) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            pixels[y * width + x] = color
        }
        set(hotSpotX, hotSpotY, white)
        for y in (hotSpotY + 1)..<height {
            let halfWidth = min(y - hotSpotY, 5)
            set(hotSpotX - 1, y, black)
            for x in hotSpotX..<(hotSpotX + halfWidth) {
                set(x, y, white)
            }
            set(hotSpotX + halfWidth, y, black)
        }
        return RFBServerCursor(
            width: width,
            height: height,
            hotSpotX: hotSpotX,
            hotSpotY: hotSpotY,
            pixels: pixels
        )
    }

    // MARK: - Driver (public API only)

    /// Retained so the hosts' windows stay alive for the render.
    private var retainedWindows: [UIWindow] = []

    private func makeHost() -> MetalFramebufferHostingView {
        let host = MetalFramebufferHostingView(
            coordinator: MetalFramebufferView.Coordinator(device: nil)
        )
        host.frame = CGRect(origin: .zero, size: Self.viewSize)
        // A retained (never visible) window keeps the hierarchy alive for
        // the snapshot. Note it is NOT what makes the render non-blank —
        // `drawHierarchy` snapshots blank even windowed without a screen
        // commit, which is why `renderToBitmap` uses `layer.render`.
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.viewSize))
        window.addSubview(host)
        retainedWindows.append(window)
        host.layoutIfNeeded()
        return host
    }

    private func drive(
        _ host: MetalFramebufferHostingView,
        zoom: CGFloat,
        cursorPosition: CGPoint,
        serverCursor: RFBServerCursor?
    ) {
        host.syncZoomPan(scale: zoom, offset: .zero)
        host.syncInputState(
            pointerControlMode: .trackpad,
            trackpadCursor: TrackpadCursor(position: cursorPosition, isVisible: true),
            serverCursor: serverCursor,
            framebufferSize: Self.framebufferSize
        )
        host.layoutIfNeeded()
    }

    /// The overlay image arrives on different schedules per branch: the
    /// fallback image is set synchronously, while the server-cursor bitmap
    /// is rasterized off the main actor. The wait must therefore be
    /// branch-aware — waiting for "any image" in the server case fires on
    /// the synchronously-set fallback and measures the wrong branch (this
    /// exact mistake produced identical numbers for both branches in an
    /// early revision of this gate). The server image is identified by its
    /// size, which is the synthetic cursor's own dimensions — nothing the
    /// placement code computes.
    private func waitForHotCursorImage(
        in host: UIView,
        serverCursor: RFBServerCursor?
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if hasExpectedHotCursorImage(host, serverCursor: serverCursor) {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return hasExpectedHotCursorImage(host, serverCursor: serverCursor)
    }

    private func hasExpectedHotCursorImage(
        _ host: UIView,
        serverCursor: RFBServerCursor?
    ) -> Bool {
        let images = host.subviews.compactMap { ($0 as? UIImageView)?.image }
        if let serverCursor {
            let expected = CGSize(width: serverCursor.width, height: serverCursor.height)
            return images.contains { $0.size == expected }
        }
        return images.contains { $0.size.width > 0 && $0.size.height > 0 }
    }

    private func renderToBitmap(_ host: UIView) -> CGImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = Self.renderScale
        format.opaque = false
        // 8-bit pixels: the default extended range yields float components
        // the byte scan below cannot parse.
        format.preferredRange = .standard
        // `layer.render` rather than `drawHierarchy`: the test host never
        // reaches the screen, so there is no commit for `drawHierarchy` to
        // wait on — it snapshots blank. The cursor view is a plain
        // `UIImageView` whose layer contents exist from image assignment,
        // so a direct layer render is faithful here.
        CATransaction.flush()
        let image = UIGraphicsImageRenderer(size: host.bounds.size, format: format).image { context in
            host.layer.render(in: context.cgContext)
        }
        return image.cgImage
    }

    /// The tip of the drawn glyph, defined as the leftmost bright-opaque
    /// pixel of the topmost bright-opaque row of the rendered bitmap.
    ///
    /// This loop necessarily resembles `TrackpadCursorGlyph.tipPoint`
    /// (there is one way to spell "leftmost of topmost"), but it is an
    /// independent re-implementation over rendered pixels: it never calls
    /// `tipPoint`, `measureTipOffsetFromCenter`, or `tipOffsetFromCenter`,
    /// so it cannot restate the placement arithmetic (FR-003).
    ///
    /// "Bright-opaque" rather than merely "opaque": the host draws a
    /// blurred black drop shadow (`shadowOpacity` 0.55, radius 2) that
    /// extends past the glyph silhouette. Keying the scan on alpha alone
    /// would mistake shadow fringe for the tip and move the reading ~2 pt
    /// up-left of the glyph the founder thresholded as a "hard-edged
    /// near-white silhouette" — the same thresholding this rule mirrors.
    ///
    /// Bytes are read straight from the image's data provider, so there
    /// is no intermediate bitmap context and no row-flip question: provider
    /// row 0 is the displayed top row.
    private func scannedTipPoint(in image: CGImage) -> CGPoint? {
        guard let (pixels, width, height, bytesPerRow, isBGRA) = pixelBytes(of: image) else {
            return nil
        }
        return pixels.withUnsafeBytes { raw -> CGPoint? in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    let (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat)
                    if isBGRA {
                        (blue, green, red, alpha) = (
                            CGFloat(bytes[offset]),
                            CGFloat(bytes[offset + 1]),
                            CGFloat(bytes[offset + 2]),
                            CGFloat(bytes[offset + 3])
                        )
                    } else {
                        (red, green, blue, alpha) = (
                            CGFloat(bytes[offset]),
                            CGFloat(bytes[offset + 1]),
                            CGFloat(bytes[offset + 2]),
                            CGFloat(bytes[offset + 3])
                        )
                    }
                    guard alpha > 128 else { continue }
                    // Premultiplied storage: un-premultiply before judging
                    // brightness so a dim-but-opaque pixel cannot pass.
                    let scale = 255.0 / max(alpha, 1)
                    guard red * scale > 150, green * scale > 150, blue * scale > 150 else {
                        continue
                    }
                    return CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                }
            }
            return nil
        }
    }

    /// Raw provider bytes plus the layout needed to parse them. Supports
    /// the two premultiplied 32-bit layouts iOS renderers produce.
    private func pixelBytes(
        of image: CGImage
    ) -> (Data, Int, Int, Int, Bool)? {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              let provider = image.dataProvider,
              let data = provider.data as Data?
        else {
            return nil
        }
        let alphaInfo = image.alphaInfo
        let isPremultiplied = alphaInfo == .premultipliedFirst
            || alphaInfo == .premultipliedLast
        guard isPremultiplied else { return nil }
        let byteOrder = image.byteOrderInfo
        let isBGRA = (alphaInfo == .premultipliedFirst && byteOrder == .order32Little)
            || (alphaInfo == .premultipliedFirst && byteOrder == .orderDefault)
        let isRGBA = alphaInfo == .premultipliedLast
            && (byteOrder == .order32Big || byteOrder == .orderDefault)
        guard isBGRA || isRGBA else { return nil }
        return (data, image.width, image.height, image.bytesPerRow, isBGRA)
    }

    private func expectedAnchor(zoom: CGFloat, cursorPosition: CGPoint) -> CGPoint {
        ViewportTransform(
            framebufferSize: Self.framebufferSize,
            viewSize: Self.viewSize,
            zoomScale: zoom,
            panOffset: .zero,
            maxZoomScale: Self.maxZoom
        ).viewPoint(fromFramebufferPoint: cursorPosition)
    }

    private func assertTipLandsOnAnchor(
        zoom: CGFloat,
        cursorPosition: CGPoint,
        serverCursor: RFBServerCursor?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let host = makeHost()
        drive(host, zoom: zoom, cursorPosition: cursorPosition, serverCursor: serverCursor)
        let branch = serverCursor == nil ? "fallback" : "server"
        guard await waitForHotCursorImage(in: host, serverCursor: serverCursor) else {
            XCTFail(
                "zoom \(zoom) \(branch) fb=\(cursorPosition): the hot-cursor view never drew an image",
                file: file,
                line: line
            )
            return
        }
        guard let bitmap = renderToBitmap(host) else {
            XCTFail(
                "zoom \(zoom) \(branch) fb=\(cursorPosition): could not render the host view",
                file: file,
                line: line
            )
            return
        }
        guard let tipPixels = scannedTipPoint(in: bitmap) else {
            XCTFail(
                "zoom \(zoom) \(branch) fb=\(cursorPosition): no bright-opaque tip found in the render",
                file: file,
                line: line
            )
            return
        }
        let tip = CGPoint(
            x: tipPixels.x / Self.renderScale,
            y: tipPixels.y / Self.renderScale
        )
        let anchor = expectedAnchor(zoom: zoom, cursorPosition: cursorPosition)
        // FAIL-first on unmodified source (2026-09-19, this simulator):
        // fallback Δx −8.17/−8.50 at zoom 1, −8.17/−7.92 at zoom 4 (Δy < 1
        // everywhere); server branch green (Δ +0.17,+0.17 — the control).
        XCTAssertEqual(
            tip.x, anchor.x, accuracy: 1.0,
            "zoom \(zoom) \(branch) fb=\(cursorPosition): drawn tip.x \(tip.x) vs anchor.x \(anchor.x)",
            file: file, line: line
        )
        XCTAssertEqual(
            tip.y, anchor.y, accuracy: 1.0,
            "zoom \(zoom) \(branch) fb=\(cursorPosition): drawn tip.y \(tip.y) vs anchor.y \(anchor.y)",
            file: file, line: line
        )
    }

    // MARK: FR-001/FR-002 — fallback branch

    func testFallbackTipLandsOnAnchorAtFitZoom() async {
        // FAIL-first: tip.x 186.83 vs 195.0 (Δx −8.17).
        await assertTipLandsOnAnchor(zoom: 1, cursorPosition: CGPoint(x: 960, y: 540), serverCursor: nil)
        // FAIL-first: tip.x 56.5 vs 65.0 (Δx −8.50).
        await assertTipLandsOnAnchor(zoom: 1, cursorPosition: CGPoint(x: 320, y: 810), serverCursor: nil)
    }

    func testFallbackTipLandsOnAnchorAtMaximumZoom() async {
        // FAIL-first: tip.x 186.83 vs 195.0 (Δx −8.17).
        await assertTipLandsOnAnchor(zoom: 4, cursorPosition: CGPoint(x: 960, y: 540), serverCursor: nil)
        // FAIL-first: tip.x 300.83 vs 308.75 (Δx −7.92).
        await assertTipLandsOnAnchor(zoom: 4, cursorPosition: CGPoint(x: 1100, y: 600), serverCursor: nil)
    }

    // MARK: FR-001/FR-002 — server-cursor branch

    func testServerCursorTipLandsOnAnchorAtFitZoom() async {
        // FAIL-first: green — the control (tip 195.17 vs anchor 195.0).
        let cursor = Self.syntheticArrowCursor()
        await assertTipLandsOnAnchor(zoom: 1, cursorPosition: CGPoint(x: 960, y: 540), serverCursor: cursor)
        // FAIL-first: green — the control.
        await assertTipLandsOnAnchor(zoom: 1, cursorPosition: CGPoint(x: 320, y: 810), serverCursor: cursor)
    }

    func testServerCursorTipLandsOnAnchorAtMaximumZoom() async {
        // FAIL-first: green — the control.
        let cursor = Self.syntheticArrowCursor()
        await assertTipLandsOnAnchor(zoom: 4, cursorPosition: CGPoint(x: 960, y: 540), serverCursor: cursor)
        // FAIL-first: green — the control.
        await assertTipLandsOnAnchor(zoom: 4, cursorPosition: CGPoint(x: 1100, y: 600), serverCursor: cursor)
    }

    // MARK: - Characterisation (always green; numbers for a human)

    /// Prints the numbers a human needs to read this defect. No assertions:
    /// this test is an instrument, not a gate.
    func testCursorApexCharacterisation() async {
        print("[cursor-apex] fallback glyphSize=\(TrackpadCursorGlyph.glyphSize)")
        print("[cursor-apex] fallback tipOffsetFromCenter=\(TrackpadCursorGlyph.tipOffsetFromCenter)")
        if let image = TrackpadCursorGlyph.image {
            print("[cursor-apex] fallback imageSize=\(image.size) scale=\(image.scale)")
            if let scanned = scannedTipOfStandaloneGlyph(image) {
                print(
                    "[cursor-apex] fallback renderedScannedTipInBox=\(scanned.x),\(scanned.y) "
                        + "box=\(image.size.width),\(image.size.height)"
                )
            } else {
                print("[cursor-apex] fallback renderedScannedTipInBox=not-found")
            }
        } else {
            print("[cursor-apex] fallback image=nil")
        }

        let cursor = Self.syntheticArrowCursor()
        let hotspotOffset = CGSize(
            width: CGFloat(cursor.hotSpotX) - CGFloat(cursor.width) / 2,
            height: CGFloat(cursor.hotSpotY) - CGFloat(cursor.height) / 2
        )
        print("[cursor-apex] server cursorSize=\(cursor.width),\(cursor.height)")
        print("[cursor-apex] server hotspot=\(cursor.hotSpotX),\(cursor.hotSpotY)")
        print("[cursor-apex] server hotspotOffsetFromCenter=\(hotspotOffset)")

        let host = makeHost()
        drive(
            host,
            zoom: 1,
            cursorPosition: CGPoint(x: 960, y: 540),
            serverCursor: cursor
        )
        guard await waitForHotCursorImage(in: host, serverCursor: cursor),
              let bitmap = renderToBitmap(host),
              let tipPixels = scannedTipPoint(in: bitmap)
        else {
            print("[cursor-apex] server renderedScannedTip=not-found")
            return
        }
        let tip = CGPoint(x: tipPixels.x / Self.renderScale, y: tipPixels.y / Self.renderScale)
        let anchor = expectedAnchor(zoom: 1, cursorPosition: CGPoint(x: 960, y: 540))
        print("[cursor-apex] server renderedScannedTip=\(tip.x),\(tip.y) anchor=\(anchor.x),\(anchor.y)")
    }

    /// Renders the fallback artwork alone (no placement, no shadow) and
    /// locates its tip with the same independent scan, in glyph-box points.
    private func scannedTipOfStandaloneGlyph(_ image: UIImage) -> CGPoint? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = Self.renderScale
        format.opaque = false
        format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = rendered.cgImage,
              let tipPixels = scannedTipPoint(in: cgImage)
        else {
            return nil
        }
        return CGPoint(x: tipPixels.x / Self.renderScale, y: tipPixels.y / Self.renderScale)
    }
}
#endif
