import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Terminal QR rendering (spec 040 FR-003): `NaruHelper --pair` draws
/// the pairing code directly in the terminal with half-block Unicode, so
/// the Mac side needs no GUI and no new dependency — CoreImage's
/// `CIQRCodeGenerator` has shipped with macOS since forever.
///
/// The renderer is a pure function from message to lines so tests can
/// verify structure (line count, width, glyph alphabet, quiet zone)
/// without a terminal.
public enum NaruHelperTerminalQr {
    public static let quietZoneModules = 3

    /// Renders `message` as QR lines using `▀ ▄ █` pairs — one character
    /// row covers two module rows. Returns nil when CoreImage refuses the
    /// message (too long for any QR version); callers print the raw code
    /// as the fallback, the way Orca's QR-error path does.
    public static func renderLines(message: String) -> [String]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else {
            return nil
        }
        let moduleWidth = Int(image.extent.width)
        let moduleHeight = Int(image.extent.height)
        guard moduleWidth > 0, moduleHeight > 0, moduleWidth <= 512, moduleHeight <= 512 else {
            return nil
        }

        // The macOS SDK exports no single-channel CIFormat here, so the
        // QR renders as RGBA8 and the red channel carries the grayscale.
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: moduleWidth * moduleHeight * bytesPerPixel)
        CIContext().render(
            image,
            toBitmap: &pixels,
            rowBytes: moduleWidth * bytesPerPixel,
            bounds: image.extent,
            format: .RGBA8,
            colorSpace: nil
        )
        let luminance = (0..<(moduleWidth * moduleHeight)).map {
            pixels[$0 * bytesPerPixel]
        }

        // CoreImage's polarity here is dark = 0, light = 255. A defensive
        // majority vote flips it if a future macOS inverts the filter —
        // a QR is majority-light, so the check is stable.
        let darkSample = luminance.strideSample(every: 7)
        let darkRatio = Double(darkSample.filter { $0 < 128 }.count) / Double(max(darkSample.count, 1))
        let darkIsLow = darkRatio <= 0.5
        func isDark(_ value: UInt8) -> Bool {
            darkIsLow ? value < 128 : value >= 128
        }

        func darkModule(_ x: Int, _ y: Int) -> Bool {
            guard (quietZoneModules..<(moduleWidth + quietZoneModules)).contains(x),
                  (quietZoneModules..<(moduleHeight + quietZoneModules)).contains(y)
            else {
                return false
            }
            return isDark(
                luminance[(y - quietZoneModules) * moduleWidth + (x - quietZoneModules)]
            )
        }

        let totalModules = moduleWidth + quietZoneModules * 2
        var lines: [String] = []
        var y = 0
        while y < totalModules {
            var line = ""
            for x in 0..<totalModules {
                let top = darkModule(x, y)
                let bottom = y + 1 < totalModules && darkModule(x, y + 1)
                switch (top, bottom) {
                case (true, true): line.append("█")
                case (true, false): line.append("▀")
                case (false, true): line.append("▄")
                case (false, false): line.append(" ")
                }
            }
            lines.append(line)
            y += 2
        }
        return lines
    }
}

private extension Array where Element == UInt8 {
    /// Sparse sampling for the polarity vote — every n-th pixel is
    /// plenty for a majority test on a binary image.
    func strideSample(every stride: Int) -> [UInt8] {
        guard stride > 0, !isEmpty else {
            return self
        }
        return enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }
}
