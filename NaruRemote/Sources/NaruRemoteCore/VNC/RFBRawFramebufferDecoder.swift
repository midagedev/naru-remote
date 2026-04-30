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

    public init(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect],
        changedPixelCount: Int,
        capturedAt: Date = Date()
    ) {
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles
        self.changedPixelCount = max(changedPixelCount, 0)
        self.capturedAt = capturedAt
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
        }
    }
}

public enum RFBRawFramebufferDecoder {
    private static let rawEncoding: Int32 = 0

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
        previousFramebuffer: RFBRawFramebuffer?,
        capturedAt: Date = Date()
    ) throws -> RFBFramebufferUpdateResult {
        try validate(pixelFormat: serverInit.pixelFormat)

        let update = try RFBProtocolDecoder.parseFramebufferUpdateHeader(updateData)
        let bytes = Array(updateData)
        var payloadOffset = 4 + update.rectangles.count * 12
        var framebuffer = try baseFramebuffer(
            serverInit: serverInit,
            previousFramebuffer: previousFramebuffer
        )
        var dirtyRectangles: [RFBFrameDamageRect] = []
        dirtyRectangles.reserveCapacity(update.rectangles.count)
        var changedPixelCount = 0

        for rectangle in update.rectangles {
            guard rectangle.encodingType == rawEncoding else {
                throw RFBRawFramebufferDecoderError.unsupportedEncoding(rectangle.encodingType)
            }

            guard rectangle.x >= 0,
                  rectangle.y >= 0,
                  rectangle.x + rectangle.width <= serverInit.width,
                  rectangle.y + rectangle.height <= serverInit.height
            else {
                throw RFBRawFramebufferDecoderError.rectangleOutOfBounds
            }

            dirtyRectangles.append(
                RFBFrameDamageRect(
                    x: rectangle.x,
                    y: rectangle.y,
                    width: rectangle.width,
                    height: rectangle.height
                )
            )

            let byteCount = rectangle.width * rectangle.height * bytesPerPixel(for: serverInit.pixelFormat)
            guard bytes.count >= payloadOffset + byteCount else {
                throw RFBRawFramebufferDecoderError.insufficientPixelData(
                    expected: payloadOffset + byteCount,
                    actual: bytes.count
                )
            }

            for localY in 0..<rectangle.height {
                for localX in 0..<rectangle.width {
                    let pixelOffset = payloadOffset + ((localY * rectangle.width) + localX) * 4
                    let color = decodeColor(
                        bytes: bytes,
                        offset: pixelOffset,
                        pixelFormat: serverInit.pixelFormat
                    )
                    let targetX = rectangle.x + localX
                    let targetY = rectangle.y + localY
                    if framebuffer[targetX, targetY] != color {
                        changedPixelCount += 1
                    }
                    framebuffer.set(
                        color,
                        x: targetX,
                        y: targetY
                    )
                }
            }

            payloadOffset += byteCount
        }

        return RFBFramebufferUpdateResult(
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            capturedAt: capturedAt
        )
    }

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

    private static func validate(pixelFormat: RFBPixelFormat) throws {
        guard pixelFormat.bitsPerPixel == 32,
              pixelFormat.isTrueColor,
              pixelFormat.redMax > 0,
              pixelFormat.greenMax > 0,
              pixelFormat.blueMax > 0
        else {
            throw RFBRawFramebufferDecoderError.unsupportedPixelFormat
        }
    }

    private static func bytesPerPixel(for pixelFormat: RFBPixelFormat) -> Int {
        Int(pixelFormat.bitsPerPixel) / 8
    }

    private static func decodeColor(
        bytes: [UInt8],
        offset: Int,
        pixelFormat: RFBPixelFormat
    ) -> RFBColor {
        let value: UInt32
        if pixelFormat.isBigEndian {
            value = UInt32(bytes[offset]) << 24 |
                UInt32(bytes[offset + 1]) << 16 |
                UInt32(bytes[offset + 2]) << 8 |
                UInt32(bytes[offset + 3])
        } else {
            value = UInt32(bytes[offset]) |
                UInt32(bytes[offset + 1]) << 8 |
                UInt32(bytes[offset + 2]) << 16 |
                UInt32(bytes[offset + 3]) << 24
        }

        return RFBColor(
            red: scale((value >> UInt32(pixelFormat.redShift)) & UInt32(pixelFormat.redMax), max: pixelFormat.redMax),
            green: scale((value >> UInt32(pixelFormat.greenShift)) & UInt32(pixelFormat.greenMax), max: pixelFormat.greenMax),
            blue: scale((value >> UInt32(pixelFormat.blueShift)) & UInt32(pixelFormat.blueMax), max: pixelFormat.blueMax)
        )
    }

    private static func scale(_ component: UInt32, max: UInt16) -> UInt8 {
        UInt8((component * 255) / UInt32(max))
    }
}
