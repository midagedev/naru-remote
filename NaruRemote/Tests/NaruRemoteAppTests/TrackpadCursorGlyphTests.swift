import CoreGraphics
import XCTest
@testable import NaruRemoteApp

/// Spec 023 FR-006..FR-008. The fallback trackpad cursor's *tip* is its
/// hotspot; placing the glyph's centre on the cursor position is the defect
/// these cases pin. The raster scan is exercised against a synthetic arrow so
/// the contract holds without a simulator.
final class TrackpadCursorGlyphTests: XCTestCase {

    /// A 6x8 stand-in for `cursorarrow`: tip at (1, 1), body widening down.
    /// `y == 0` is the top row, matching what `tipPoint` is asked.
    private let syntheticArrow: [String] = [
        "......",
        ".#....",
        ".##...",
        ".###..",
        ".####.",
        ".###..",
        "..##..",
        "...#.."
    ]

    private func isOpaque(_ x: Int, _ y: Int) -> Bool {
        guard y >= 0, y < syntheticArrow.count else { return false }
        let row = Array(syntheticArrow[y])
        guard x >= 0, x < row.count else { return false }
        return row[x] == "#"
    }

    func testTipPointIsTheLeftmostOpaquePixelOfTheTopmostOpaqueRow() {
        let tip = TrackpadCursorGlyph.tipPoint(width: 6, height: 8, isOpaque: isOpaque)

        // Pixel (1, 1) addressed at its centre.
        XCTAssertEqual(tip?.x ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertEqual(tip?.y ?? -1, 1.5, accuracy: 1e-9)
    }

    func testTipPointIsNilForAFullyTransparentRaster() {
        XCTAssertNil(
            TrackpadCursorGlyph.tipPoint(width: 6, height: 8, isOpaque: { _, _ in false })
        )
    }

    func testTipPointIsNilForAnEmptyRaster() {
        XCTAssertNil(TrackpadCursorGlyph.tipPoint(width: 0, height: 0, isOpaque: isOpaque))
    }

    func testTipOffsetIsMeasuredFromTheGlyphBoxCentre() {
        let offset = TrackpadCursorGlyph.tipOffsetFromCenter(
            glyphSize: CGSize(width: 6, height: 8),
            tipPoint: CGPoint(x: 1.5, y: 1.5)
        )

        XCTAssertEqual(offset.width, -1.5, accuracy: 1e-9)
        XCTAssertEqual(offset.height, -2.5, accuracy: 1e-9)
    }

    func testCentrePlacementPutsTheTipExactlyOnTheAnchor() {
        let anchor = CGPoint(x: 120, y: 240)
        let offset = CGSize(width: -6.5, height: -10)

        let center = TrackpadCursorGlyph.center(
            placingTipAt: anchor,
            tipOffsetFromCenter: offset
        )
        // Round-trip: the tip of a glyph centred there lands back on the anchor.
        let tip = CGPoint(x: center.x + offset.width, y: center.y + offset.height)

        XCTAssertEqual(center.x, 126.5, accuracy: 1e-9)
        XCTAssertEqual(center.y, 250, accuracy: 1e-9)
        XCTAssertEqual(tip.x, anchor.x, accuracy: 1e-9)
        XCTAssertEqual(tip.y, anchor.y, accuracy: 1e-9)
    }

    func testCentrePlacementIsNotTheAnchorForTheShippingGlyph() {
        // The regression itself: if the resolved glyph's tip offset were zero,
        // centring would be correct and this whole type would be pointless.
        // Any real cursor arrow has its tip away from its centre.
        let anchor = CGPoint(x: 100, y: 100)
        let center = TrackpadCursorGlyph.center(
            placingTipAt: anchor,
            tipOffsetFromCenter: TrackpadCursorGlyph.tipOffsetFromCenter
        )

        XCTAssertGreaterThan(
            hypot(center.x - anchor.x, center.y - anchor.y),
            4,
            "The shipping glyph's tip must sit well away from its box centre — "
                + "otherwise the drawn tip and the clicked pixel cannot disagree, "
                + "and the measured offset has silently gone to zero."
        )
    }

    func testShippingGlyphKeepsANonSquareBoxSoItIsNotDistorted() {
        let size = TrackpadCursorGlyph.glyphSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, size.width)
    }
}
