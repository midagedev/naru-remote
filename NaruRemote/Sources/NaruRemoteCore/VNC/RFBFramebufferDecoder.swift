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
        capturedAt: Date = Date()
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
                try decodeCopyRect(
                    reader: reader,
                    into: &framebuffer,
                    x: x, y: y, width: width, height: height,
                    currentWidth: currentWidth, currentHeight: currentHeight
                )
                if width > 0, height > 0 {
                    dirtyRectangles.append(RFBFrameDamageRect(x: x, y: y, width: width, height: height))
                    changedPixelCount += width * height
                }

            case RFBEncoding.hextile:
                try decodeHextile(
                    reader: reader,
                    into: &framebuffer,
                    x: x, y: y, width: width, height: height,
                    currentWidth: currentWidth, currentHeight: currentHeight,
                    pixelFormat: pixelFormat, bytesPerPixel: bytesPerPixel
                )
                if width > 0, height > 0 {
                    dirtyRectangles.append(RFBFrameDamageRect(x: x, y: y, width: width, height: height))
                    changedPixelCount += width * height
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
    ) throws {
        // Payload is always present even for a zero-area rect.
        let srcX = Int(try reader.readUInt16())
        let srcY = Int(try reader.readUInt16())
        guard width > 0, height > 0 else {
            return
        }
        guard x >= 0, y >= 0, srcX >= 0, srcY >= 0,
              x + width <= currentWidth, y + height <= currentHeight,
              srcX + width <= currentWidth, srcY + height <= currentHeight
        else {
            throw RFBRawFramebufferDecoderError.copyRectOutOfBounds
        }
        framebuffer.copyRegion(srcX: srcX, srcY: srcY, toX: x, toY: y, width: width, height: height)
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
    ) throws {
        try validateRectangle(x: x, y: y, width: width, height: height, currentWidth: currentWidth, currentHeight: currentHeight)
        guard width > 0, height > 0 else {
            return
        }

        // Background / foreground PERSIST across tiles when their bit is
        // unset (RFC 6143 §7.7.4) — the most common Hextile bug.
        var background = RFBColor(red: 0, green: 0, blue: 0)
        var foreground = RFBColor(red: 0, green: 0, blue: 0)

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
                            framebuffer.setPixelTrackingChange(color, x: originX + localX, y: originY + localY)
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

                framebuffer.fillRegion(x: originX, y: originY, width: tileWidth, height: tileHeight, color: background)

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
                        framebuffer.fillRegion(
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
}
