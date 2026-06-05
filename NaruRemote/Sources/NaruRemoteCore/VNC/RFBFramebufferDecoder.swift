import CoreGraphics
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

/// Multi-encoding framebuffer-update decoder (spec 004). Reads a whole
/// `FramebufferUpdate` message incrementally from an ``RFBByteReader``
/// and dispatches each rectangle by its encoding type, mutating the
/// previous framebuffer in place and reporting damage + change metadata
/// in the same ``RFBFramebufferUpdateResult`` contract the Raw-only
/// decoder always produced.
///
/// Decodes: Raw (0), CopyRect (1), Hextile (5), ZRLE (16), Tight
/// fill / basic-copy / JPEG (7), plus the LastRect (-224), DesktopSize
/// (-223), ExtendedDesktopSize (-308), and Cursor (-239) / XCursor
/// (-240) pseudo-encodings.
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
    private static let maxCursorDimension = 1_024
    private static let maxCursorPixels = 1_048_576

    private struct DecodedFrameDamage {
        var dirtyRectangles: [RFBFrameDamageRect] = []
        var changedPixelCount = 0

        mutating func append(_ accumulator: FrameDamageAccumulator) {
            guard let rectangle = accumulator.boundingRectangle else {
                return
            }
            dirtyRectangles.append(rectangle)
            changedPixelCount += accumulator.changedPixelCount
        }

        mutating func appendConservativeRectangle(
            x: Int,
            y: Int,
            width: Int,
            height: Int,
            changedPixelCount: Int
        ) {
            guard width > 0, height > 0, changedPixelCount > 0 else {
                return
            }
            dirtyRectangles.append(RFBFrameDamageRect(x: x, y: y, width: width, height: height))
            self.changedPixelCount += changedPixelCount
        }
    }

    private struct FrameDamageAccumulator {
        private var minX: Int?
        private var minY: Int?
        private var maxX: Int?
        private var maxY: Int?
        private(set) var changedPixelCount = 0

        mutating func recordPixel(x: Int, y: Int) {
            changedPixelCount += 1
            minX = min(minX ?? x, x)
            minY = min(minY ?? y, y)
            maxX = max(maxX ?? x, x)
            maxY = max(maxY ?? y, y)
        }

        var boundingRectangle: RFBFrameDamageRect? {
            guard let minX, let minY, let maxX, let maxY else {
                return nil
            }
            return RFBFrameDamageRect(
                x: minX,
                y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            )
        }
    }

    public static func decodeUpdate(
        reader: RFBByteReader,
        serverInit: RFBServerInit,
        previousFramebuffer: RFBRawFramebuffer?,
        capturedAt: Date = Date(),
        zlibStream: RFBZlibInflateStream? = nil,
        tightZlibStreams: RFBTightZlibStreams? = nil
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
        var serverCursor: RFBServerCursor?
        var processed = 0
        var encodingMix = RFBFramebufferEncodingMix()
        // A ZRLE rectangle uses the session's single persistent zlib
        // stream. If the caller did not supply one (the offline `Data`
        // shim / single-update tests), lazily create one shared across
        // every ZRLE rectangle in THIS update.
        var activeZlibStream = zlibStream
        var activeTightZlibStreams = tightZlibStreams

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
            encodingMix = encodingMix.recordingRectangle(encoding: encoding)

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

            case RFBEncoding.cursor:
                serverCursor = try decodeCursor(
                    reader: reader,
                    hotSpotX: x,
                    hotSpotY: y,
                    width: width,
                    height: height,
                    pixelFormat: pixelFormat,
                    bytesPerPixel: bytesPerPixel
                )

            case RFBEncoding.xCursor:
                serverCursor = try decodeXCursor(
                    reader: reader,
                    hotSpotX: x,
                    hotSpotY: y,
                    width: width,
                    height: height
                )

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
                let damage = try decodeZRLE(
                    reader: reader,
                    into: &framebuffer,
                    x: x, y: y, width: width, height: height,
                    currentWidth: currentWidth, currentHeight: currentHeight,
                    pixelFormat: pixelFormat, zlib: stream
                )
                dirtyRectangles.append(contentsOf: damage.dirtyRectangles)
                changedPixelCount += damage.changedPixelCount

            case RFBEncoding.tight:
                let tightStreams: RFBTightZlibStreams
                if let activeTightZlibStreams {
                    tightStreams = activeTightZlibStreams
                } else {
                    tightStreams = RFBTightZlibStreams()
                    activeTightZlibStreams = tightStreams
                }
                let changed = try decodeTight(
                    reader: reader,
                    into: &framebuffer,
                    x: x, y: y, width: width, height: height,
                    currentWidth: currentWidth, currentHeight: currentHeight,
                    pixelFormat: pixelFormat,
                    tightZlibStreams: tightStreams
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
            didResizeDesktop: didResizeDesktop,
            serverCursor: serverCursor,
            encodingMix: encodingMix
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

    // MARK: - Cursor pseudo-encodings (-239 / -240)

    private static func decodeCursor(
        reader: RFBByteReader,
        hotSpotX: Int,
        hotSpotY: Int,
        width: Int,
        height: Int,
        pixelFormat: RFBPixelFormat,
        bytesPerPixel: Int
    ) throws -> RFBServerCursor {
        guard width >= 0,
              height >= 0,
              width <= maxCursorDimension,
              height <= maxCursorDimension,
              width * height <= maxCursorPixels
        else {
            throw RFBRawFramebufferDecoderError.malformedCursor
        }

        let pixelCount = width * height
        let pixels = try reader.readBytes(pixelCount * bytesPerPixel)
        let maskStride = (width + 7) / 8
        let mask = try reader.readBytes(maskStride * height)
        var decodedPixels: [RFBColor] = []
        decodedPixels.reserveCapacity(pixelCount)

        for row in 0..<height {
            for column in 0..<width {
                let pixelOffset = ((row * width) + column) * bytesPerPixel
                let isOpaque: Bool
                if width == 0 {
                    isOpaque = false
                } else {
                    let maskByte = mask[(row * maskStride) + (column / 8)]
                    let bit = UInt8(0x80 >> (column % 8))
                    isOpaque = maskByte & bit != 0
                }
                if isOpaque {
                    decodedPixels.append(pixelFormat.decodeColor(pixels, at: pixelOffset))
                } else {
                    decodedPixels.append(RFBColor(red: 0, green: 0, blue: 0, alpha: 0))
                }
            }
        }

        return RFBServerCursor(
            width: width,
            height: height,
            hotSpotX: hotSpotX,
            hotSpotY: hotSpotY,
            pixels: decodedPixels
        )
    }

    private static func decodeXCursor(
        reader: RFBByteReader,
        hotSpotX: Int,
        hotSpotY: Int,
        width: Int,
        height: Int
    ) throws -> RFBServerCursor {
        guard width >= 0,
              height >= 0,
              width <= maxCursorDimension,
              height <= maxCursorDimension,
              width * height <= maxCursorPixels
        else {
            throw RFBRawFramebufferDecoderError.malformedCursor
        }

        let primary = RFBColor(
            red: try reader.readUInt8(),
            green: try reader.readUInt8(),
            blue: try reader.readUInt8()
        )
        let secondary = RFBColor(
            red: try reader.readUInt8(),
            green: try reader.readUInt8(),
            blue: try reader.readUInt8()
        )
        let maskStride = (width + 7) / 8
        let bitmap = try reader.readBytes(maskStride * height)
        let bitmask = try reader.readBytes(maskStride * height)
        var decodedPixels: [RFBColor] = []
        decodedPixels.reserveCapacity(width * height)

        for row in 0..<height {
            for column in 0..<width {
                let maskByte = bitmask[(row * maskStride) + (column / 8)]
                let bit = UInt8(0x80 >> (column % 8))
                if maskByte & bit == 0 {
                    decodedPixels.append(RFBColor(red: 0, green: 0, blue: 0, alpha: 0))
                    continue
                }

                let bitmapByte = bitmap[(row * maskStride) + (column / 8)]
                decodedPixels.append(bitmapByte & bit != 0 ? primary : secondary)
            }
        }

        return RFBServerCursor(
            width: width,
            height: height,
            hotSpotX: hotSpotX,
            hotSpotY: hotSpotY,
            pixels: decodedPixels
        )
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
    ) throws -> DecodedFrameDamage {
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
            return DecodedFrameDamage()
        }

        let tiles = RFBDataReader(try zlib.inflate(compressed))
        let cpixelSize = pixelFormat.cpixelByteCount
        var damage = DecodedFrameDamage()

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
                var tileDamage = FrameDamageAccumulator()
                switch subencoding {
                case 0:
                    // Raw CPIXELs, raster order.
                    let bytes = try tiles.readBytes(pixelCount * cpixelSize)
                    for raster in 0..<pixelCount {
                        let color = pixelFormat.decodeCPixel(bytes, at: raster * cpixelSize, size: cpixelSize)
                        recordZRLEWrite(
                            &framebuffer,
                            damage: &tileDamage,
                            raster: raster,
                            tileWidth: tileWidth,
                            originX: originX,
                            originY: originY,
                            color: color
                        )
                    }
                    damage.append(tileDamage)

                case 1:
                    // Solid tile — one CPIXEL fills it.
                    let bytes = try tiles.readBytes(cpixelSize)
                    let color = pixelFormat.decodeCPixel(bytes, at: 0, size: cpixelSize)
                    let changedPixelCount = framebuffer.fillRegionTrackingChange(
                        x: originX,
                        y: originY,
                        width: tileWidth,
                        height: tileHeight,
                        color: color
                    )
                    damage.appendConservativeRectangle(
                        x: originX,
                        y: originY,
                        width: tileWidth,
                        height: tileHeight,
                        changedPixelCount: changedPixelCount
                    )

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
                            recordZRLEWrite(
                                &framebuffer,
                                damage: &tileDamage,
                                raster: row * tileWidth + col,
                                tileWidth: tileWidth,
                                originX: originX,
                                originY: originY,
                                color: palette[index]
                            )
                        }
                    }
                    damage.append(tileDamage)

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
                            recordZRLEWrite(
                                &framebuffer,
                                damage: &tileDamage,
                                raster: painted,
                                tileWidth: tileWidth,
                                originX: originX,
                                originY: originY,
                                color: color
                            )
                            painted += 1
                        }
                    }
                    damage.append(tileDamage)

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
                            recordZRLEWrite(
                                &framebuffer,
                                damage: &tileDamage,
                                raster: painted,
                                tileWidth: tileWidth,
                                originX: originX,
                                originY: originY,
                                color: color
                            )
                            painted += 1
                        }
                    }
                    damage.append(tileDamage)

                default:
                    // 17...127 and 129 are unused / invalid.
                    throw RFBRawFramebufferDecoderError.malformedZRLE
                }

                tileX += 64
            }
            tileY += 64
        }
        return damage
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

    private static func recordZRLEWrite(
        _ framebuffer: inout RFBRawFramebuffer,
        damage: inout FrameDamageAccumulator,
        raster: Int,
        tileWidth: Int,
        originX: Int,
        originY: Int,
        color: RFBColor
    ) {
        let x = originX + raster % tileWidth
        let y = originY + raster / tileWidth
        if framebuffer.setPixelTrackingChange(color, x: x, y: y) {
            damage.recordPixel(x: x, y: y)
        }
    }

    // MARK: - Tight (encoding 7, fill + basic filters + JPEG)

    private enum TightCompressionType {
        static let fill: UInt8 = 0x08
        static let jpeg: UInt8 = 0x09
        static let noZlibBasic: UInt8 = 0x0A
        static let noZlibExplicitFilter: UInt8 = 0x0E
    }

    private enum TightFilter {
        static let explicit: UInt8 = 0x04
        static let copy: UInt8 = 0x00
        static let palette: UInt8 = 0x01
        static let gradient: UInt8 = 0x02
    }

    private static let maxTightRectangleWidth = 2_048
    private static let maxTightBasicPayloadLength = 64 * 1024 * 1024
    private static let maxTightJPEGPayloadLength = 16 * 1024 * 1024

    private static func decodeTight(
        reader: RFBByteReader,
        into framebuffer: inout RFBRawFramebuffer,
        x: Int, y: Int, width: Int, height: Int,
        currentWidth: Int, currentHeight: Int,
        pixelFormat: RFBPixelFormat,
        tightZlibStreams: RFBTightZlibStreams
    ) throws -> Int {
        try validateRectangle(x: x, y: y, width: width, height: height, currentWidth: currentWidth, currentHeight: currentHeight)
        guard width <= maxTightRectangleWidth else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }

        let control = try reader.readUInt8()
        try tightZlibStreams.reset(mask: control & 0x0F)
        var compressionType = control >> 4

        switch compressionType {
        case TightCompressionType.fill:
            let color = try readTightPixel(reader: reader, pixelFormat: pixelFormat)
            guard width > 0, height > 0 else {
                return 0
            }
            return framebuffer.fillRegionTrackingChange(x: x, y: y, width: width, height: height, color: color)

        case TightCompressionType.jpeg:
            guard width > 0, height > 0 else {
                return 0
            }
            let payloadLength = try readTightCompactLength(reader)
            guard payloadLength > 0, payloadLength <= maxTightJPEGPayloadLength else {
                throw RFBRawFramebufferDecoderError.malformedTight
            }
            let payload = try reader.readBytes(payloadLength)
            return try decodeTightJPEG(
                payload,
                into: &framebuffer,
                x: x,
                y: y,
                width: width,
                height: height
            )

        case 0...0x07, TightCompressionType.noZlibBasic, TightCompressionType.noZlibExplicitFilter:
            let readsUncompressedPayload = compressionType == TightCompressionType.noZlibBasic
                || compressionType == TightCompressionType.noZlibExplicitFilter
            if compressionType == TightCompressionType.noZlibBasic {
                compressionType = TightFilter.copy
            } else if compressionType == TightCompressionType.noZlibExplicitFilter {
                compressionType = TightFilter.explicit
            }
            let hasExplicitFilter = compressionType & TightFilter.explicit != 0
            let filter = hasExplicitFilter ? try reader.readUInt8() : TightFilter.copy
            guard width > 0, height > 0 else {
                return 0
            }
            switch filter {
            case TightFilter.copy:
                let uncompressedSize = try tightCopyPayloadLength(width: width, height: height, pixelFormat: pixelFormat)
                let pixels = try readTightBasicPayload(
                    reader: reader,
                    byteCount: uncompressedSize,
                    compressionType: compressionType,
                    readsUncompressedPayload: readsUncompressedPayload,
                    tightZlibStreams: tightZlibStreams
                )
                return decodeTightBasicCopy(
                    pixels,
                    into: &framebuffer,
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    pixelFormat: pixelFormat
                )

            case TightFilter.palette:
                let palette = try readTightPalette(reader: reader, pixelFormat: pixelFormat)
                let indexByteCount = try tightPaletteIndexByteCount(width: width, height: height, colorCount: palette.count)
                let indices = try readTightBasicPayload(
                    reader: reader,
                    byteCount: indexByteCount,
                    compressionType: compressionType,
                    readsUncompressedPayload: readsUncompressedPayload,
                    tightZlibStreams: tightZlibStreams
                )
                return try decodeTightPalette(
                    indices,
                    palette: palette,
                    into: &framebuffer,
                    x: x,
                    y: y,
                    width: width,
                    height: height
                )

            case TightFilter.gradient:
                let uncompressedSize = try tightCopyPayloadLength(width: width, height: height, pixelFormat: pixelFormat)
                let deltas = try readTightBasicPayload(
                    reader: reader,
                    byteCount: uncompressedSize,
                    compressionType: compressionType,
                    readsUncompressedPayload: readsUncompressedPayload,
                    tightZlibStreams: tightZlibStreams
                )
                return try decodeTightGradient(
                    deltas,
                    into: &framebuffer,
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    pixelFormat: pixelFormat
                )

            default:
                throw RFBRawFramebufferDecoderError.malformedTight
            }

        default:
            throw RFBRawFramebufferDecoderError.malformedTight
        }
    }

    private static func decodeTightJPEG(
        _ payload: [UInt8],
        into framebuffer: inout RFBRawFramebuffer,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) throws -> Int {
        #if canImport(ImageIO)
        guard !payload.isEmpty else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }

        let imageData = Data(payload) as CFData
        guard let source = CGImageSourceCreateWithData(imageData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width,
              image.height == height
        else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let rendered = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo
                  )
            else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.flush()
            return true
        }
        guard rendered else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }

        var changed = 0
        for localY in 0..<height {
            for localX in 0..<width {
                let offset = (localY * bytesPerRow) + (localX * bytesPerPixel)
                let color = RFBColor(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2])
                if framebuffer.setPixelTrackingChange(color, x: x + localX, y: y + localY) {
                    changed += 1
                }
            }
        }
        return changed
        #else
        throw RFBRawFramebufferDecoderError.malformedTight
        #endif
    }

    private static func decodeTightBasicCopy(
        reader: RFBByteReader,
        into framebuffer: inout RFBRawFramebuffer,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        pixelFormat: RFBPixelFormat
    ) throws -> Int {
        let pixels = try reader.readBytes(tightCopyPayloadLength(width: width, height: height, pixelFormat: pixelFormat))
        return decodeTightBasicCopy(
            pixels,
            into: &framebuffer,
            x: x,
            y: y,
            width: width,
            height: height,
            pixelFormat: pixelFormat
        )
    }

    private static func decodeTightBasicCopy(
        _ pixels: [UInt8],
        into framebuffer: inout RFBRawFramebuffer,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        pixelFormat: RFBPixelFormat
    ) -> Int {
        let pixelByteCount = tightPixelByteCount(pixelFormat)
        var changed = 0
        for localY in 0..<height {
            for localX in 0..<width {
                let offset = ((localY * width) + localX) * pixelByteCount
                let color = decodeTightPixel(pixels, at: offset, pixelFormat: pixelFormat, pixelByteCount: pixelByteCount)
                if framebuffer.setPixelTrackingChange(color, x: x + localX, y: y + localY) {
                    changed += 1
                }
            }
        }
        return changed
    }

    private static func decodeTightGradient(
        _ deltas: [UInt8],
        into framebuffer: inout RFBRawFramebuffer,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        pixelFormat: RFBPixelFormat
    ) throws -> Int {
        let pixelByteCount = tightPixelByteCount(pixelFormat)
        guard pixelByteCount == 3,
              pixelFormat.redMax == 255,
              pixelFormat.greenMax == 255,
              pixelFormat.blueMax == 255
        else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }
        guard deltas.count == width * height * pixelByteCount else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }

        var changed = 0
        var previousRow = Array(repeating: RFBColor(red: 0, green: 0, blue: 0), count: width)
        for localY in 0..<height {
            var currentRow = Array(repeating: RFBColor(red: 0, green: 0, blue: 0), count: width)
            var left = RFBColor(red: 0, green: 0, blue: 0)
            for localX in 0..<width {
                let above = previousRow[localX]
                let upperLeft = localX == 0 ? RFBColor(red: 0, green: 0, blue: 0) : previousRow[localX - 1]
                let predicted = tightGradientPredict(left: left, above: above, upperLeft: upperLeft)
                let offset = ((localY * width) + localX) * pixelByteCount
                let color = RFBColor(
                    red: UInt8((Int(deltas[offset]) + Int(predicted.red)) & 0xFF),
                    green: UInt8((Int(deltas[offset + 1]) + Int(predicted.green)) & 0xFF),
                    blue: UInt8((Int(deltas[offset + 2]) + Int(predicted.blue)) & 0xFF)
                )
                currentRow[localX] = color
                left = color
                if framebuffer.setPixelTrackingChange(color, x: x + localX, y: y + localY) {
                    changed += 1
                }
            }
            previousRow = currentRow
        }
        return changed
    }

    private static func tightGradientPredict(left: RFBColor, above: RFBColor, upperLeft: RFBColor) -> RFBColor {
        func predict(_ left: UInt8, _ above: UInt8, _ upperLeft: UInt8) -> UInt8 {
            UInt8(max(0, min(255, Int(left) + Int(above) - Int(upperLeft))))
        }

        return RFBColor(
            red: predict(left.red, above.red, upperLeft.red),
            green: predict(left.green, above.green, upperLeft.green),
            blue: predict(left.blue, above.blue, upperLeft.blue)
        )
    }

    private static func decodeTightPalette(
        _ indices: [UInt8],
        palette: [RFBColor],
        into framebuffer: inout RFBRawFramebuffer,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) throws -> Int {
        var changed = 0
        if palette.count == 2 {
            let bytesPerRow = (width + 7) / 8
            guard indices.count == bytesPerRow * height else {
                throw RFBRawFramebufferDecoderError.malformedTight
            }
            for localY in 0..<height {
                for localX in 0..<width {
                    let byte = indices[localY * bytesPerRow + localX / 8]
                    let paletteIndex = Int((byte >> UInt8(7 - (localX % 8))) & 0x01)
                    if framebuffer.setPixelTrackingChange(palette[paletteIndex], x: x + localX, y: y + localY) {
                        changed += 1
                    }
                }
            }
            return changed
        }

        guard indices.count == width * height else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }
        for localY in 0..<height {
            for localX in 0..<width {
                let paletteIndex = Int(indices[localY * width + localX])
                guard paletteIndex < palette.count else {
                    throw RFBRawFramebufferDecoderError.malformedTight
                }
                if framebuffer.setPixelTrackingChange(palette[paletteIndex], x: x + localX, y: y + localY) {
                    changed += 1
                }
            }
        }
        return changed
    }

    private static func readTightBasicPayload(
        reader: RFBByteReader,
        byteCount: Int,
        compressionType: UInt8,
        readsUncompressedPayload: Bool,
        tightZlibStreams: RFBTightZlibStreams
    ) throws -> [UInt8] {
        guard byteCount >= 0, byteCount <= maxTightBasicPayloadLength else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }
        if byteCount < 12 {
            return try reader.readBytes(byteCount)
        }

        let payloadLength = try readTightCompactLength(reader)
        let payload = try reader.readBytes(payloadLength)
        if readsUncompressedPayload {
            guard payload.count == byteCount else {
                throw RFBRawFramebufferDecoderError.malformedTight
            }
            return payload
        }

        let streamIndex = Int(compressionType & 0x03)
        let decompressed = try tightZlibStreams.inflate(payload, streamIndex: streamIndex)
        guard decompressed.count == byteCount else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }
        return decompressed
    }

    private static func tightCopyPayloadLength(width: Int, height: Int, pixelFormat: RFBPixelFormat) throws -> Int {
        let byteCount = width * height * tightPixelByteCount(pixelFormat)
        guard byteCount <= maxTightBasicPayloadLength else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }
        return byteCount
    }

    private static func tightPaletteIndexByteCount(width: Int, height: Int, colorCount: Int) throws -> Int {
        let bytesPerRow: Int
        if colorCount == 2 {
            bytesPerRow = (width + 7) / 8
        } else {
            bytesPerRow = width
        }
        let byteCount = bytesPerRow * height
        guard byteCount <= maxTightBasicPayloadLength else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }
        return byteCount
    }

    private static func readTightCompactLength(_ reader: RFBByteReader) throws -> Int {
        let first = try reader.readUInt8()
        var value = Int(first & 0x7F)
        guard first & 0x80 != 0 else {
            return value
        }

        let second = try reader.readUInt8()
        value |= Int(second & 0x7F) << 7
        guard second & 0x80 != 0 else {
            return value
        }

        let third = try reader.readUInt8()
        value |= Int(third) << 14
        return value
    }

    private static func readTightPixel(
        reader: RFBByteReader,
        pixelFormat: RFBPixelFormat
    ) throws -> RFBColor {
        let pixelByteCount = tightPixelByteCount(pixelFormat)
        let bytes = try reader.readBytes(pixelByteCount)
        return decodeTightPixel(bytes, at: 0, pixelFormat: pixelFormat, pixelByteCount: pixelByteCount)
    }

    private static func readTightPalette(
        reader: RFBByteReader,
        pixelFormat: RFBPixelFormat
    ) throws -> [RFBColor] {
        let colorCount = Int(try reader.readUInt8()) + 1
        guard colorCount >= 2 else {
            throw RFBRawFramebufferDecoderError.malformedTight
        }
        let pixelByteCount = tightPixelByteCount(pixelFormat)
        let bytes = try reader.readBytes(colorCount * pixelByteCount)
        var palette = [RFBColor]()
        palette.reserveCapacity(colorCount)
        for index in 0..<colorCount {
            palette.append(decodeTightPixel(bytes, at: index * pixelByteCount, pixelFormat: pixelFormat, pixelByteCount: pixelByteCount))
        }
        return palette
    }

    private static func tightPixelByteCount(_ pixelFormat: RFBPixelFormat) -> Int {
        if pixelFormat.depth == 24,
           pixelFormat.redMax == 255,
           pixelFormat.greenMax == 255,
           pixelFormat.blueMax == 255 {
            return 3
        }
        return pixelFormat.bytesPerPixelValue
    }

    private static func decodeTightPixel(
        _ bytes: [UInt8],
        at offset: Int,
        pixelFormat: RFBPixelFormat,
        pixelByteCount: Int
    ) -> RFBColor {
        if pixelByteCount == 3 {
            return RFBColor(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
        }
        return pixelFormat.decodeColor(bytes, at: offset)
    }
}
