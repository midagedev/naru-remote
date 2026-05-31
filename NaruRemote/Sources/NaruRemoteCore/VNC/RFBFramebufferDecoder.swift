import Foundation

/// Multi-encoding framebuffer-update decoder (spec 004). Reads a whole
/// `FramebufferUpdate` message incrementally from an ``RFBByteReader``
/// and dispatches each rectangle by its encoding type, mutating the
/// previous framebuffer in place and reporting damage + change metadata
/// in the same ``RFBFramebufferUpdateResult`` contract the Raw-only
/// decoder always produced.
///
/// Increment 1 decodes: Raw (0), CopyRect (1), Hextile (5), plus the
/// LastRect (-224), DesktopSize (-223), and ExtendedDesktopSize (-308)
/// pseudo-encodings. ZRLE / Tight / Cursor are added in later increments
/// and slot into the same `switch`.
///
/// Every read is bounds- and length-checked against untrusted server
/// bytes (spec 004 SP-006): a malformed or hostile rectangle surfaces a
/// typed error and tears the stream down — never a trap, an
/// out-of-bounds write, or an unbounded allocation. The decode hot path
/// contains no logging of any payload (spec 004 SP-005).
public enum RFBFramebufferDecoder {
    /// Largest framebuffer dimension Naru will allocate from a server
    /// directive (DesktopSize). 16384 comfortably exceeds 8K while
    /// refusing a hostile 65535×65535 (~17 GB) reallocation.
    static let maxDimension = 16_384

    /// Backstop against a server that declares the 0xFFFF "unknown
    /// rectangle count" sentinel and then never sends a LastRect.
    private static let maxRectanglesSafetyCap = 200_000

    public static func decodeUpdate(
        reader: RFBByteReader,
        serverInit: RFBServerInit,
        previousFramebuffer: RFBRawFramebuffer?,
        capturedAt: Date = Date(),
        zlibStream: RFBZlibInflateStream? = nil
    ) throws -> RFBFramebufferUpdateResult {
        let pixelFormat = serverInit.pixelFormat
        guard pixelFormat.isSupported32BitTrueColor else {
            throw RFBRawFramebufferDecoderError.unsupportedPixelFormat
        }
        let bytesPerPixel = pixelFormat.bytesPerPixelValue

        // FramebufferUpdate message header (RFC 6143 §7.6.1):
        //   u8 message-type (0) · u8 padding · u16 number-of-rectangles
        let messageType = try reader.readUInt8()
        guard messageType == 0 else {
            throw RFBProtocolDecoderError.unexpectedMessageType(messageType)
        }
        _ = try reader.readUInt8()
        let declaredRectangleCount = Int(try reader.readUInt16())
        let hasUnknownCount = declaredRectangleCount == 0xFFFF

        var framebuffer = try baseFramebuffer(
            serverInit: serverInit,
            previousFramebuffer: previousFramebuffer
        )
        // Current framebuffer dimensions — start from the server init and
        // track DesktopSize reallocations so later rectangles in the same
        // update validate against the new bounds.
        var currentWidth = serverInit.width
        var currentHeight = serverInit.height
        var dirtyRectangles: [RFBFrameDamageRect] = []
        var changedPixelCount = 0
        var didResizeDesktop = false
        var processed = 0
        // A ZRLE rectangle uses the session's single persistent zlib
        // stream. If the caller did not supply one (the offline `Data`
        // shim / single-update tests), lazily create one shared across
        // every ZRLE rectangle in THIS update.
        var activeZlibStream = zlibStream

        rectangleLoop: while true {
            if !hasUnknownCount, processed >= declaredRectangleCount {
                break
            }
            if processed >= maxRectanglesSafetyCap {
                break
            }

            // Rectangle header: u16 x · u16 y · u16 w · u16 h · s32 encoding
            let x = Int(try reader.readUInt16())
            let y = Int(try reader.readUInt16())
            let width = Int(try reader.readUInt16())
            let height = Int(try reader.readUInt16())
            let encoding = try reader.readInt32()
            processed += 1

            switch encoding {
            case RFBEncoding.lastRect:
                break rectangleLoop

            case RFBEncoding.desktopSize:
                try resizeFramebuffer(
                    &framebuffer,
                    width: width,
                    height: height,
                    currentWidth: &currentWidth,
                    currentHeight: &currentHeight
                )
                didResizeDesktop = true
                dirtyRectangles.append(RFBFrameDamageRect(x: 0, y: 0, width: width, height: height))
                changedPixelCount += width * height

            case RFBEncoding.extendedDesktopSize:
                try consumeExtendedDesktopSizePayload(reader: reader)
                try resizeFramebuffer(
                    &framebuffer,
                    width: width,
                    height: height,
                    currentWidth: &currentWidth,
                    currentHeight: &currentHeight
                )
                didResizeDesktop = true
                dirtyRectangles.append(RFBFrameDamageRect(x: 0, y: 0, width: width, height: height))
                changedPixelCount += width * height

            case RFBEncoding.raw:
                let changed = try decodeRaw(
                    reader: reader,
                    into: &framebuffer,
                    x: x, y: y, width: width, height: height,
                    currentWidth: currentWidth, currentHeight: currentHeight,
                    pixelFormat: pixelFormat, bytesPerPixel: bytesPerPixel
                )
                if width > 0, height > 0 {
                    dirtyRectangles.append(RFBFrameDamageRect(x: x, y: y, width: width, height: height))
                }
                changedPixelCount += changed

            case RFBEncoding.copyRect:
                let changed = try decodeCopyRect(
                    reader: reader,
                    into: &framebuffer,
                    x: x, y: y, width: width, height: height,
                    currentWidth: currentWidth, currentHeight: currentHeight
                )
                if width > 0, height > 0 {
                    dirtyRectangles.append(RFBFrameDamageRect(x: x, y: y, width: width, height: height))
                    changedPixelCount += changed
                }

            case RFBEncoding.hextile:
                let changed = try decodeHextile(
                    reader: reader,
                    into: &framebuffer,
                    x: x, y: y, width: width, height: height,
                    currentWidth: currentWidth, currentHeight: currentHeight,
                    pixelFormat: pixelFormat, bytesPerPixel: bytesPerPixel
                )
                if width > 0, height > 0 {
                    dirtyRectangles.append(RFBFrameDamageRect(x: x, y: y, width: width, height: height))
                    changedPixelCount += changed
                }

            case RFBEncoding.zrle:
                let stream: RFBZlibInflateStream
                if let activeZlibStream {
                    stream = activeZlibStream
                } else {
                    stream = try RFBZlibInflateStream()
                    activeZlibStream = stream
                }
                let changed = try decodeZRLE(
                    reader: reader,
                    into: &framebuffer,
                    x: x, y: y, width: width, height: height,
                    currentWidth: currentWidth, currentHeight: currentHeight,
                    pixelFormat: pixelFormat, zlib: stream
                )
                if width > 0, height > 0 {
                    dirtyRectangles.append(RFBFrameDamageRect(x: x, y: y, width: width, height: height))
                    changedPixelCount += changed
                }

            default:
                throw RFBRawFramebufferDecoderError.unsupportedEncoding(encoding)
            }
        }

        return RFBFramebufferUpdateResult(
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            capturedAt: capturedAt,
            didResizeDesktop: didResizeDesktop
        )
    }

    // MARK: - Base framebuffer

    private static func baseFramebuffer(
        serverInit: RFBServerInit,
        previousFramebuffer: RFBRawFramebuffer?
    ) throws -> RFBRawFramebuffer {
        guard let previousFramebuffer else {
            return RFBRawFramebuffer(width: serverInit.width, height: serverInit.height)
        }
        guard previousFramebuffer.width == serverInit.width,
              previousFramebuffer.height == serverInit.height
        else {
            throw RFBRawFramebufferDecoderError.framebufferSizeMismatch(
                expectedWidth: serverInit.width,
                expectedHeight: serverInit.height,
                actualWidth: previousFramebuffer.width,
                actualHeight: previousFramebuffer.height
            )
        }
        return previousFramebuffer
    }

    private static func resizeFramebuffer(
        _ framebuffer: inout RFBRawFramebuffer,
        width: Int,
        height: Int,
        currentWidth: inout Int,
        currentHeight: inout Int
    ) throws {
        guard width >= 1, height >= 1, width <= maxDimension, height <= maxDimension else {
            throw RFBRawFramebufferDecoderError.invalidDimensions(width: width, height: height)
        }
        framebuffer = RFBRawFramebuffer(width: width, height: height)
        currentWidth = width
        currentHeight = height
    }

    /// ExtendedDesktopSize (-308) carries a screen array after the
    /// rectangle header that MUST be consumed to keep the stream aligned
    /// (RFB community extension): u8 number-of-screens, 3 bytes padding,
    /// then 16 bytes per screen.
    private static func consumeExtendedDesktopSizePayload(reader: RFBByteReader) throws {
        let numberOfScreens = Int(try reader.readUInt8())
        try reader.skip(3)
        if numberOfScreens > 0 {
            try reader.skip(numberOfScreens * 16)
        }
    }

    // MARK: - Raw (encoding 0)

    private static func decodeRaw(
        reader: RFBByteReader,
        into framebuffer: inout RFBRawFramebuffer,
        x: Int, y: Int, width: Int, height: Int,
        currentWidth: Int, currentHeight: Int,
        pixelFormat: RFBPixelFormat, bytesPerPixel: Int
    ) throws -> Int {
        try validateRectangle(x: x, y: y, width: width, height: height, currentWidth: currentWidth, currentHeight: currentHeight)
        guard width > 0, height > 0 else {
            return 0
        }
        let pixels = try reader.readBytes(width * height * bytesPerPixel)
        var changed = 0
        for localY in 0..<height {
            for localX in 0..<width {
                let offset = ((localY * width) + localX) * bytesPerPixel
                let color = pixelFormat.decodeColor(pixels, at: offset)
                if framebuffer.setPixelTrackingChange(color, x: x + localX, y: y + localY) {
                    changed += 1
                }
            }
        }
        return changed
    }

    // MARK: - CopyRect (encoding 1, RFC 6143 §7.7.2)

    private static func decodeCopyRect(
        reader: RFBByteReader,
        into framebuffer: inout RFBRawFramebuffer,
        x: Int, y: Int, width: Int, height: Int,
        currentWidth: Int, currentHeight: Int
    ) throws -> Int {
        // Payload is always present even for a zero-area rect.
        let srcX = Int(try reader.readUInt16())
        let srcY = Int(try reader.readUInt16())
        guard width > 0, height > 0 else {
            return 0
        }
        guard x >= 0, y >= 0, srcX >= 0, srcY >= 0,
              x + width <= currentWidth, y + height <= currentHeight,
              srcX + width <= currentWidth, srcY + height <= currentHeight
        else {
            throw RFBRawFramebufferDecoderError.copyRectOutOfBounds
        }
        return framebuffer.copyRegionTrackingChange(srcX: srcX, srcY: srcY, toX: x, toY: y, width: width, height: height)
    }

    // MARK: - Hextile (encoding 5, RFC 6143 §7.7.4)

    private enum HextileMask {
        static let raw: UInt8 = 0x01
        static let backgroundSpecified: UInt8 = 0x02
        static let foregroundSpecified: UInt8 = 0x04
        static let anySubrects: UInt8 = 0x08
        static let subrectsColoured: UInt8 = 0x10
    }

    private static func decodeHextile(
        reader: RFBByteReader,
        into framebuffer: inout RFBRawFramebuffer,
        x: Int, y: Int, width: Int, height: Int,
        currentWidth: Int, currentHeight: Int,
        pixelFormat: RFBPixelFormat, bytesPerPixel: Int
    ) throws -> Int {
        try validateRectangle(x: x, y: y, width: width, height: height, currentWidth: currentWidth, currentHeight: currentHeight)
        guard width > 0, height > 0 else {
            return 0
        }

        // Background / foreground PERSIST across tiles when their bit is
        // unset (RFC 6143 §7.7.4) — the most common Hextile bug.
        var background = RFBColor(red: 0, green: 0, blue: 0)
        var foreground = RFBColor(red: 0, green: 0, blue: 0)
        var changed = 0

        var tileY = 0
        while tileY < height {
            let tileHeight = min(16, height - tileY)
            var tileX = 0
            while tileX < width {
                let tileWidth = min(16, width - tileX)
                let originX = x + tileX
                let originY = y + tileY

                let mask = try reader.readUInt8()

                if mask & HextileMask.raw != 0 {
                    let pixels = try reader.readBytes(tileWidth * tileHeight * bytesPerPixel)
                    for localY in 0..<tileHeight {
                        for localX in 0..<tileWidth {
                            let offset = ((localY * tileWidth) + localX) * bytesPerPixel
                            let color = pixelFormat.decodeColor(pixels, at: offset)
                            if framebuffer.setPixelTrackingChange(color, x: originX + localX, y: originY + localY) {
                                changed += 1
                            }
                        }
                    }
                    tileX += 16
                    continue
                }

                if mask & HextileMask.backgroundSpecified != 0 {
                    background = try readPixel(reader: reader, pixelFormat: pixelFormat, bytesPerPixel: bytesPerPixel)
                }
                if mask & HextileMask.foregroundSpecified != 0 {
                    foreground = try readPixel(reader: reader, pixelFormat: pixelFormat, bytesPerPixel: bytesPerPixel)
                }

                changed += framebuffer.fillRegionTrackingChange(x: originX, y: originY, width: tileWidth, height: tileHeight, color: background)

                if mask & HextileMask.anySubrects != 0 {
                    let subrectCount = Int(try reader.readUInt8())
                    let coloured = mask & HextileMask.subrectsColoured != 0
                    for _ in 0..<subrectCount {
                        let subColor: RFBColor
                        if coloured {
                            subColor = try readPixel(reader: reader, pixelFormat: pixelFormat, bytesPerPixel: bytesPerPixel)
                        } else {
                            subColor = foreground
                        }
                        let xy = try reader.readUInt8()
                        let wh = try reader.readUInt8()
                        let subX = Int(xy >> 4)
                        let subY = Int(xy & 0x0F)
                        let subWidth = Int(wh >> 4) + 1
                        let subHeight = Int(wh & 0x0F) + 1
                        guard subX + subWidth <= tileWidth, subY + subHeight <= tileHeight else {
                            throw RFBRawFramebufferDecoderError.malformedHextile
                        }
                        changed += framebuffer.fillRegionTrackingChange(
                            x: originX + subX,
                            y: originY + subY,
                            width: subWidth,
                            height: subHeight,
                            color: subColor
                        )
                    }
                }

                tileX += 16
            }
            tileY += 16
        }
        return changed
    }

    // MARK: - Shared

    private static func readPixel(
        reader: RFBByteReader,
        pixelFormat: RFBPixelFormat,
        bytesPerPixel: Int
    ) throws -> RFBColor {
        let bytes = try reader.readBytes(bytesPerPixel)
        return pixelFormat.decodeColor(bytes, at: 0)
    }

    private static func validateRectangle(
        x: Int, y: Int, width: Int, height: Int,
        currentWidth: Int, currentHeight: Int
    ) throws {
        guard x >= 0, y >= 0,
              x + width <= currentWidth, y + height <= currentHeight
        else {
            throw RFBRawFramebufferDecoderError.rectangleOutOfBounds
        }
    }

    // MARK: - ZRLE (encoding 16, RFC 6143 §7.7.6)

    /// Hostile-length guard for the per-rectangle compressed payload.
    private static let maxZRLECompressedLength = 64 * 1024 * 1024

    private static func decodeZRLE(
        reader: RFBByteReader,
        into framebuffer: inout RFBRawFramebuffer,
        x: Int, y: Int, width: Int, height: Int,
        currentWidth: Int, currentHeight: Int,
        pixelFormat: RFBPixelFormat, zlib: RFBZlibInflateStream
    ) throws -> Int {
        try validateRectangle(x: x, y: y, width: width, height: height, currentWidth: currentWidth, currentHeight: currentHeight)

        // The compressed length is read (and the bytes consumed off the
        // session zlib stream) even for a zero-area rectangle so the
        // stream stays aligned.
        let length = Int(try reader.readUInt32())
        guard length >= 0, length <= maxZRLECompressedLength else {
            throw RFBRawFramebufferDecoderError.malformedZRLE
        }
        let compressed = try reader.readBytes(length)
        guard width > 0, height > 0 else {
            _ = try zlib.inflate(compressed)
            return 0
        }

        let tiles = RFBDataReader(try zlib.inflate(compressed))
        let cpixelSize = pixelFormat.cpixelByteCount
        var changed = 0

        var tileY = 0
        while tileY < height {
            let tileHeight = min(64, height - tileY)
            var tileX = 0
            while tileX < width {
                let tileWidth = min(64, width - tileX)
                let originX = x + tileX
                let originY = y + tileY
                let pixelCount = tileWidth * tileHeight

                let subencoding = try tiles.readUInt8()
                switch subencoding {
                case 0:
                    // Raw CPIXELs, raster order.
                    let bytes = try tiles.readBytes(pixelCount * cpixelSize)
                    for raster in 0..<pixelCount {
                        let color = pixelFormat.decodeCPixel(bytes, at: raster * cpixelSize, size: cpixelSize)
                        if zrleWrite(&framebuffer, raster: raster, tileWidth: tileWidth, originX: originX, originY: originY, color: color) {
                            changed += 1
                        }
                    }

                case 1:
                    // Solid tile — one CPIXEL fills it.
                    let bytes = try tiles.readBytes(cpixelSize)
                    let color = pixelFormat.decodeCPixel(bytes, at: 0, size: cpixelSize)
                    changed += framebuffer.fillRegionTrackingChange(x: originX, y: originY, width: tileWidth, height: tileHeight, color: color)

                case 2...16:
                    // Packed palette: palette of `subencoding` CPIXELs, then
                    // packed indices (1/2/4 bits), rows byte-padded.
                    let paletteSize = Int(subencoding)
                    let palette = try readPalette(tiles, count: paletteSize, pixelFormat: pixelFormat, cpixelSize: cpixelSize)
                    let bitsPerIndex = paletteSize <= 2 ? 1 : (paletteSize <= 4 ? 2 : 4)
                    let bytesPerRow = (tileWidth * bitsPerIndex + 7) / 8
                    let mask = UInt8((1 << bitsPerIndex) - 1)
                    for row in 0..<tileHeight {
                        let rowBytes = try tiles.readBytes(bytesPerRow)
                        for col in 0..<tileWidth {
                            let bitPos = col * bitsPerIndex
                            let shift = 8 - bitsPerIndex - (bitPos % 8)
                            let index = Int((rowBytes[bitPos / 8] >> UInt8(shift)) & mask)
                            guard index < palette.count else {
                                throw RFBRawFramebufferDecoderError.malformedZRLE
                            }
                            if zrleWrite(&framebuffer, raster: row * tileWidth + col, tileWidth: tileWidth, originX: originX, originY: originY, color: palette[index]) {
                                changed += 1
                            }
                        }
                    }

                case 128:
                    // Plain RLE: runs of <CPIXEL, length>.
                    var painted = 0
                    while painted < pixelCount {
                        let bytes = try tiles.readBytes(cpixelSize)
                        let color = pixelFormat.decodeCPixel(bytes, at: 0, size: cpixelSize)
                        let runLength = try readRunLength(tiles)
                        guard painted + runLength <= pixelCount else {
                            throw RFBRawFramebufferDecoderError.malformedZRLE
                        }
                        for _ in 0..<runLength {
                            if zrleWrite(&framebuffer, raster: painted, tileWidth: tileWidth, originX: originX, originY: originY, color: color) {
                                changed += 1
                            }
                            painted += 1
                        }
                    }

                case 130...255:
                    // Palette RLE: palette of `subencoding-128` CPIXELs, then
                    // runs of <index[, length]>; index high bit signals a run.
                    let paletteSize = Int(subencoding) - 128
                    let palette = try readPalette(tiles, count: paletteSize, pixelFormat: pixelFormat, cpixelSize: cpixelSize)
                    var painted = 0
                    while painted < pixelCount {
                        let indexByte = try tiles.readUInt8()
                        let paletteIndex: Int
                        let runLength: Int
                        if indexByte & 0x80 != 0 {
                            paletteIndex = Int(indexByte & 0x7F)
                            runLength = try readRunLength(tiles)
                        } else {
                            paletteIndex = Int(indexByte)
                            runLength = 1
                        }
                        guard paletteIndex < palette.count, painted + runLength <= pixelCount else {
                            throw RFBRawFramebufferDecoderError.malformedZRLE
                        }
                        let color = palette[paletteIndex]
                        for _ in 0..<runLength {
                            if zrleWrite(&framebuffer, raster: painted, tileWidth: tileWidth, originX: originX, originY: originY, color: color) {
                                changed += 1
                            }
                            painted += 1
                        }
                    }

                default:
                    // 17...127 and 129 are unused / invalid.
                    throw RFBRawFramebufferDecoderError.malformedZRLE
                }

                tileX += 64
            }
            tileY += 64
        }
        return changed
    }

    private static func readPalette(
        _ reader: RFBByteReader,
        count: Int,
        pixelFormat: RFBPixelFormat,
        cpixelSize: Int
    ) throws -> [RFBColor] {
        let bytes = try reader.readBytes(count * cpixelSize)
        var palette = [RFBColor]()
        palette.reserveCapacity(count)
        for index in 0..<count {
            palette.append(pixelFormat.decodeCPixel(bytes, at: index * cpixelSize, size: cpixelSize))
        }
        return palette
    }

    /// ZRLE run length: 1 plus the sum of bytes, every 255 byte
    /// continuing the run (RFC 6143 §7.7.6).
    private static func readRunLength(_ reader: RFBByteReader) throws -> Int {
        var length = 1
        while true {
            let byte = try reader.readUInt8()
            length += Int(byte)
            if byte != 255 {
                break
            }
        }
        return length
    }

    private static func zrleWrite(
        _ framebuffer: inout RFBRawFramebuffer,
        raster: Int,
        tileWidth: Int,
        originX: Int,
        originY: Int,
        color: RFBColor
    ) -> Bool {
        framebuffer.setPixelTrackingChange(color, x: originX + raster % tileWidth, y: originY + raster / tileWidth)
    }
}
