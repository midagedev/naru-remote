import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Single owner of the **fallback** trackpad cursor glyph — the arrow drawn
/// when the RFB server has sent no cursor shape (spec 023 FR-008).
///
/// It exists because the two render paths (the Metal hot overlay in
/// `MetalFramebufferView` and the SwiftUI overlay in `SessionViewportView`)
/// each used to place the glyph's *centre* on the cursor's framebuffer
/// position. The SF Symbol's arrow tip is nowhere near its box centre, so the
/// drawn tip pointed several points up-and-left of the pixel that was actually
/// clicked — the founder's "미세하게 트랙패드 커서 끝이랑 실제 클릭되는곳 갭"
/// (2026-08-21). The server-cursor path never had the bug because RFB ships an
/// explicit `hotSpotX`/`hotSpotY`; this type is that hotspot for our own glyph.
///
/// The tip is **measured from the rendered glyph**, not written down as a
/// constant, so new SF Symbol artwork cannot silently re-introduce the offset
/// (FR-006).
///
/// Constitution §IV: nothing here touches a cursor coordinate — it converts a
/// caller-supplied anchor and never logs, stores, or exports one.
enum TrackpadCursorGlyph {
    static let symbolName = "cursorarrow"
    static let pointSize: CGFloat = 22

    /// Fallback used only if the glyph cannot be rendered for measurement.
    /// Measured 2026-08-21 against the shipping artwork at `pointSize`
    /// (19×26pt box, tip pixel at (3, 3)); kept as a floor so a failed
    /// render degrades to "close" rather than to "centred", which is the
    /// defect being fixed.
    static let fallbackTipOffsetFromCenter = CGSize(width: -6.5, height: -10)

    /// Fallback box used only if the glyph cannot be rendered.
    static let fallbackGlyphSize = CGSize(width: 19, height: 26)

    // MARK: - Pure geometry (testable without a simulator)

    /// The arrow tip inside a glyph raster: the leftmost opaque pixel of the
    /// topmost opaque row, in the raster's own top-left origin space.
    ///
    /// `isOpaque` is asked in UIKit orientation — `(x, y)` with `y == 0` at the
    /// top — so the caller owns any bitmap row flip.
    static func tipPoint(
        width: Int,
        height: Int,
        isOpaque: (Int, Int) -> Bool
    ) -> CGPoint? {
        guard width > 0, height > 0 else { return nil }
        for y in 0..<height {
            for x in 0..<width where isOpaque(x, y) {
                // +0.5 addresses the pixel's centre rather than its corner.
                return CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
            }
        }
        return nil
    }

    /// Vector from the glyph box's centre to the tip.
    static func tipOffsetFromCenter(glyphSize: CGSize, tipPoint: CGPoint) -> CGSize {
        CGSize(
            width: tipPoint.x - glyphSize.width / 2,
            height: tipPoint.y - glyphSize.height / 2
        )
    }

    /// Where the glyph box's centre must sit so its tip lands on `anchor`.
    static func center(
        placingTipAt anchor: CGPoint,
        tipOffsetFromCenter offset: CGSize
    ) -> CGPoint {
        CGPoint(x: anchor.x - offset.width, y: anchor.y - offset.height)
    }

    // MARK: - Rendered glyph (UIKit)

    #if canImport(UIKit)
    /// The glyph, rendered once at `pointSize` as a template image so the
    /// hosting view's tint applies.
    static let image: UIImage? = {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return UIImage(systemName: symbolName, withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate)
    }()

    /// Natural glyph box in points — used as-is so the arrow keeps its aspect
    /// ratio instead of being squashed into a square (FR-007).
    static let glyphSize: CGSize = image?.size ?? fallbackGlyphSize

    /// Measured tip offset for `image`, or the documented fallback.
    static let tipOffsetFromCenter: CGSize = {
        guard let image, let measured = measureTipOffsetFromCenter(of: image) else {
            return fallbackTipOffsetFromCenter
        }
        return measured
    }()

    /// Renders the glyph at scale 1 and scans its alpha for the tip. Runs once
    /// (the `static let` above); a 19×26 scan is not a hot path.
    static func measureTipOffsetFromCenter(of image: UIImage) -> CGSize? {
        let size = image.size
        let width = Int(size.width.rounded(.up))
        let height = Int(size.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = rendered.cgImage else { return nil }

        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                  )
            else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // `CGContext` origin is bottom-left; `tipPoint` asks in UIKit
        // orientation, so the row index is flipped here rather than inside the
        // pure scan.
        let opaqueThreshold: UInt8 = 38 // ~15% alpha: ignore anti-aliased fringe
        guard let tip = tipPoint(width: width, height: height, isOpaque: { x, y in
            let row = height - 1 - y
            return alpha[row * width + x] > opaqueThreshold
        }) else {
            return nil
        }
        return tipOffsetFromCenter(glyphSize: size, tipPoint: tip)
    }
    #else
    /// Non-UIKit builds (the macOS `swift test` compile of `NaruRemoteApp`)
    /// have no rendered glyph to measure, so the documented fallbacks stand in.
    /// The shipping surfaces are iOS-only.
    static let glyphSize: CGSize = fallbackGlyphSize
    static let tipOffsetFromCenter: CGSize = fallbackTipOffsetFromCenter
    #endif
}
