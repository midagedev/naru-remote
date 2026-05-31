import Foundation

public struct RFBColor: Codable, Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct RFBRawFramebuffer: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [RFBColor]

    public init(width: Int, height: Int, fill: RFBColor = RFBColor(red: 0, green: 0, blue: 0)) {
        self.width = max(width, 0)
        self.height = max(height, 0)
        self.pixels = Array(repeating: fill, count: self.width * self.height)
    }

    public subscript(x: Int, y: Int) -> RFBColor? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }
        return pixels[y * width + x]
    }

    fileprivate mutating func set(_ color: RFBColor, x: Int, y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else {
            return
        }
        pixels[y * width + x] = color
    }
}

// Internal mutation surface used by the multi-encoding decoders
// (`RFBFramebufferDecoder`). Kept in this file so `pixels`' private
// setter is in scope; marked `internal` so the decoder file (same
// module) can call them. Every method is bounds-checked — a hostile
// rectangle can never write out of range (spec 004 SP-006).
extension RFBRawFramebuffer {
    /// Writes one pixel if in bounds; returns true iff the pixel value
    /// actually changed (used for accurate `changedPixelCount`).
    @discardableResult
    mutating func setPixelTrackingChange(_ color: RFBColor, x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else {
            return false
        }
        let index = y * width + x
        guard pixels[index] != color else {
            return false
        }
        pixels[index] = color
        return true
    }

    /// Fills a clamped rectangle with a single colour (Hextile
    /// background / solid tiles).
    mutating func fillRegion(x: Int, y: Int, width regionWidth: Int, height regionHeight: Int, color: RFBColor) {
        let minX = max(x, 0)
        let minY = max(y, 0)
        let maxX = min(x + regionWidth, width)
        let maxY = min(y + regionHeight, height)
        guard minX < maxX, minY < maxY else {
            return
        }
        for row in minY..<maxY {
            let base = row * width
            for column in minX..<maxX {
                pixels[base + column] = color
            }
        }
    }

    /// Copies a `width × height` block from `(srcX, srcY)` to
    /// `(dstX, dstY)` of the *current* framebuffer (CopyRect, RFC 6143
    /// §7.7.2). Overlap-safe: the source region is snapshotted before any
    /// destination write. Caller must have bounds-validated both rects.
    mutating func copyRegion(srcX: Int, srcY: Int, toX dstX: Int, toY dstY: Int, width copyWidth: Int, height copyHeight: Int) {
        guard copyWidth > 0, copyHeight > 0 else {
            return
        }
        var snapshot = [RFBColor]()
        snapshot.reserveCapacity(copyWidth * copyHeight)
        for row in 0..<copyHeight {
            let srcBase = (srcY + row) * width + srcX
            snapshot.append(contentsOf: pixels[srcBase..<(srcBase + copyWidth)])
        }
        for row in 0..<copyHeight {
            let dstBase = (dstY + row) * width + dstX
            let snapBase = row * copyWidth
            for column in 0..<copyWidth {
                pixels[dstBase + column] = snapshot[snapBase + column]
            }
        }
    }
}

public struct RFBFrameDamageRect: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = max(x, 0)
        self.y = max(y, 0)
        self.width = max(width, 0)
        self.height = max(height, 0)
    }

    public var pixelCount: Int {
        width * height
    }
}

public struct RFBFramebufferUpdateResult: Codable, Equatable, Sendable {
    public let framebuffer: RFBRawFramebuffer
    public let dirtyRectangles: [RFBFrameDamageRect]
    public let changedPixelCount: Int
    public let capturedAt: Date
    /// True when this update reallocated the framebuffer via a
    /// DesktopSize / ExtendedDesktopSize pseudo-rectangle (spec 004
    /// FR-008). The App layer re-fits the viewport on this signal; the
    /// network client refreshes its cached server dimensions.
    public let didResizeDesktop: Bool

    public init(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect],
        changedPixelCount: Int,
        capturedAt: Date = Date(),
        didResizeDesktop: Bool = false
    ) {
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles
        self.changedPixelCount = max(changedPixelCount, 0)
        self.capturedAt = capturedAt
        self.didResizeDesktop = didResizeDesktop
    }

    public static func fullFrame(
        framebuffer: RFBRawFramebuffer,
        capturedAt: Date = Date()
    ) -> RFBFramebufferUpdateResult {
        RFBFramebufferUpdateResult(
            framebuffer: framebuffer,
            dirtyRectangles: [
                RFBFrameDamageRect(
                    x: 0,
                    y: 0,
                    width: framebuffer.width,
                    height: framebuffer.height
                )
            ],
            changedPixelCount: framebuffer.width * framebuffer.height,
            capturedAt: capturedAt
        )
    }

    public var totalPixelCount: Int {
        framebuffer.width * framebuffer.height
    }

    public var changedPixelRatio: Double {
        guard totalPixelCount > 0 else {
            return 0
        }
        return Double(changedPixelCount) / Double(totalPixelCount)
    }

    public var changeActivity: PiPFrameChangeActivity {
        if changedPixelCount == 0 {
            return .idle
        }

        if changedPixelRatio <= 0.01 {
            return .idle
        }

        if changedPixelRatio <= 0.20 {
            return .moderate
        }

        return .high
    }
}

public enum RFBRawFramebufferDecoderError: Error, Equatable, LocalizedError {
    case unsupportedPixelFormat
    case unsupportedEncoding(Int32)
    case rectangleOutOfBounds
    case insufficientPixelData(expected: Int, actual: Int)
    case framebufferSizeMismatch(expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    /// A CopyRect source or destination rectangle fell outside the
    /// framebuffer (spec 004 FR-003).
    case copyRectOutOfBounds
    /// A Hextile tile declared a structure that does not fit its
    /// rectangle (spec 004 FR-004) — e.g. a sub-rectangle outside the
    /// tile.
    case malformedHextile
    /// A pseudo-encoding or rectangle declared dimensions Naru refuses
    /// to allocate (hostile/absurd size — spec 004 SP-006).
    case invalidDimensions(width: Int, height: Int)
    /// A ZRLE tile declared an invalid subencoding, palette size, or run
    /// that overran its tile (spec 004 FR-005), or a compressed length
    /// Naru refuses to buffer.
    case malformedZRLE

    public var errorDescription: String? {
        switch self {
        case .unsupportedPixelFormat:
            return "Only 32-bit true-color raw framebuffer updates are supported."
        case .unsupportedEncoding(let encoding):
            return "Unsupported framebuffer encoding: \(encoding)."
        case .rectangleOutOfBounds:
            return "Framebuffer update rectangle is outside the server framebuffer."
        case .insufficientPixelData(let expected, let actual):
            return "Raw framebuffer payload is incomplete. Expected \(expected) bytes, received \(actual)."
        case let .framebufferSizeMismatch(expectedWidth, expectedHeight, actualWidth, actualHeight):
            return "Previous framebuffer size \(actualWidth)x\(actualHeight) does not match server framebuffer \(expectedWidth)x\(expectedHeight)."
        case .copyRectOutOfBounds:
            return "CopyRect source or destination is outside the server framebuffer."
        case .malformedHextile:
            return "Hextile tile structure is malformed."
        case let .invalidDimensions(width, height):
            return "Refusing framebuffer dimensions \(width)x\(height)."
        case .malformedZRLE:
            return "ZRLE tile data is malformed."
        }
    }
}

/// Pixel-format decode helpers shared by every rectangle decoder
/// (Raw, Hextile, ZRLE, …). Defined here alongside `RFBColor` so the
/// colour math lives next to the colour type.
extension RFBPixelFormat {
    var bytesPerPixelValue: Int {
        Int(bitsPerPixel) / 8
    }

    /// The format Naru's framebuffer is built for: 32-bit true colour
    /// with non-zero RGB maxima.
    var isSupported32BitTrueColor: Bool {
        bitsPerPixel == 32 && isTrueColor && redMax > 0 && greenMax > 0 && blueMax > 0
    }

    /// Decodes one `bytesPerPixelValue`-wide pixel at `offset` in
    /// `bytes`, honoring endianness, shifts, and maxima.
    func decodeColor(_ bytes: [UInt8], at offset: Int) -> RFBColor {
        let value: UInt32
        if isBigEndian {
            value = UInt32(bytes[offset]) << 24
                | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8
                | UInt32(bytes[offset + 3])
        } else {
            value = UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
        }
        return colorFromValue(value)
    }

    /// Maps a raw 32-bit pixel value to an `RFBColor` via the format's
    /// per-channel shift + max. Shared by full-PIXEL and CPIXEL decode.
    func colorFromValue(_ value: UInt32) -> RFBColor {
        RFBColor(
            red: Self.scale((value >> UInt32(redShift)) & UInt32(redMax), max: redMax),
            green: Self.scale((value >> UInt32(greenShift)) & UInt32(greenMax), max: greenMax),
            blue: Self.scale((value >> UInt32(blueShift)) & UInt32(blueMax), max: blueMax)
        )
    }

    /// Compressed-pixel byte count for ZRLE/Tile encodings (RFC 6143
    /// §7.7.6 CPIXEL): 3 bytes when the format is 32-bpp true-colour
    /// with depth ≤ 24 and every significant R/G/B bit fits in the low
    /// 3 bytes (the universal RGB888-in-32-bit case, incl. macOS Screen
    /// Sharing); otherwise the full pixel size.
    var cpixelByteCount: Int {
        if bitsPerPixel == 32, depth <= 24, significantBitsFitInLowThreeBytes {
            return 3
        }
        return bytesPerPixelValue
    }

    private var significantBitsFitInLowThreeBytes: Bool {
        func highestBit(_ max: UInt16, _ shift: UInt8) -> Int {
            guard max > 0 else { return 0 }
            return Int(shift) + (16 - max.leadingZeroBitCount)
        }
        let highest = Swift.max(
            highestBit(redMax, redShift),
            highestBit(greenMax, greenShift),
            highestBit(blueMax, blueShift)
        )
        return highest <= 24
    }

    /// Decodes one CPIXEL of `size` bytes (3 or 4) at `offset`. The
    /// 3-byte form carries the significant low 3 bytes in the format's
    /// byte order; the unused 4th (high) byte is implicitly zero.
    func decodeCPixel(_ bytes: [UInt8], at offset: Int, size: Int) -> RFBColor {
        guard size == 3 else {
            return decodeColor(bytes, at: offset)
        }
        let c0 = UInt32(bytes[offset])
        let c1 = UInt32(bytes[offset + 1])
        let c2 = UInt32(bytes[offset + 2])
        let value = isBigEndian
            ? (c0 << 16 | c1 << 8 | c2)
            : (c0 | c1 << 8 | c2 << 16)
        return colorFromValue(value)
    }

    private static func scale(_ component: UInt32, max: UInt16) -> UInt8 {
        UInt8((component * 255) / UInt32(max))
    }
}

/// Backward-compatible Raw entry points. Both wrap the incoming `Data`
/// in an ``RFBDataReader`` and delegate to ``RFBFramebufferDecoder`` so
/// the offline test path and the live network path share one decoder
/// (spec 004 FR-002). The Raw-only contract — pixel asserts, damage
/// rects, `framebufferSizeMismatch`, `rectangleOutOfBounds` — is
/// preserved.
public enum RFBRawFramebufferDecoder {
    public static func decode(
        updateData: Data,
        serverInit: RFBServerInit
    ) throws -> RFBRawFramebuffer {
        try apply(
            updateData: updateData,
            serverInit: serverInit,
            previousFramebuffer: nil
        ).framebuffer
    }

    public static func apply(
        updateData: Data,
        serverInit: RFBServerInit,
        previousFramebuffer: RFBRawFramebuffer? = nil,
        capturedAt: Date = Date()
    ) throws -> RFBFramebufferUpdateResult {
        try RFBFramebufferDecoder.decodeUpdate(
            reader: RFBDataReader(updateData),
            serverInit: serverInit,
            previousFramebuffer: previousFramebuffer,
            capturedAt: capturedAt
        )
    }
}
