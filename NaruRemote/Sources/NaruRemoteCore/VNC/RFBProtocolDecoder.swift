import Foundation

public struct RFBProtocolVersion: Codable, Equatable, Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }
}

public struct RFBSecurityTypes: Codable, Equatable, Sendable {
    public let types: [UInt8]

    public init(types: [UInt8]) {
        self.types = types
    }

    public var supportsNone: Bool {
        types.contains(RFBSecurityType.none.rawValue)
    }

    public var supportsVNCAuthentication: Bool {
        types.contains(RFBSecurityType.vncAuthentication.rawValue)
    }
}

public struct RFBPixelFormat: Codable, Equatable, Sendable {
    public let bitsPerPixel: UInt8
    public let depth: UInt8
    public let isBigEndian: Bool
    public let isTrueColor: Bool
    public let redMax: UInt16
    public let greenMax: UInt16
    public let blueMax: UInt16
    public let redShift: UInt8
    public let greenShift: UInt8
    public let blueShift: UInt8

    public init(
        bitsPerPixel: UInt8,
        depth: UInt8,
        isBigEndian: Bool,
        isTrueColor: Bool,
        redMax: UInt16,
        greenMax: UInt16,
        blueMax: UInt16,
        redShift: UInt8,
        greenShift: UInt8,
        blueShift: UInt8
    ) {
        self.bitsPerPixel = bitsPerPixel
        self.depth = depth
        self.isBigEndian = isBigEndian
        self.isTrueColor = isTrueColor
        self.redMax = redMax
        self.greenMax = greenMax
        self.blueMax = blueMax
        self.redShift = redShift
        self.greenShift = greenShift
        self.blueShift = blueShift
    }
}

public struct RFBServerInit: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixelFormat: RFBPixelFormat
    public let name: String

    public init(width: Int, height: Int, pixelFormat: RFBPixelFormat, name: String) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.name = name
    }

    public func frameMetadata(receivedAt: Date = Date()) -> RFBFrameMetadata {
        RFBFrameMetadata(width: width, height: height, receivedAt: receivedAt)
    }
}

public struct RFBRectangleHeader: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let encodingType: Int32
}

public struct RFBFramebufferUpdateHeader: Codable, Equatable, Sendable {
    public let rectangles: [RFBRectangleHeader]

    public var firstUpdatedRectangle: RFBRectangleHeader? {
        rectangles.first
    }
}

public enum RFBProtocolDecoderError: Error, Equatable, LocalizedError {
    case insufficientData(expected: Int, actual: Int)
    case invalidProtocolVersion(String)
    case securityFailed(UInt32)
    case unexpectedMessageType(UInt8)
    case truncatedServerCutText(expected: Int, actual: Int)
    case invalidServerCutTextEncoding

    public var errorDescription: String? {
        switch self {
        case .insufficientData(let expected, let actual):
            "RFB data is incomplete. Expected at least \(expected) bytes, received \(actual)."
        case .invalidProtocolVersion(let value):
            "Invalid RFB protocol version: \(value)"
        case .securityFailed(let status):
            "RFB security result failed with status \(status)."
        case .unexpectedMessageType(let type):
            "Unexpected RFB message type \(type)."
        case .truncatedServerCutText(let expected, let actual):
            "Truncated RFB ServerCutText payload. Expected \(expected) bytes, received \(actual)."
        case .invalidServerCutTextEncoding:
            "RFB ServerCutText payload is not valid UTF-8."
        }
    }
}

public enum RFBProtocolDecoder {
    public static func parseVersion(_ data: Data) throws -> RFBProtocolVersion {
        let bytes = Array(data)
        try require(bytes, count: 12)

        let version = String(decoding: bytes[0..<12], as: UTF8.self)
        guard version.hasPrefix("RFB "),
              version.count == 12,
              version[version.index(version.startIndex, offsetBy: 7)] == ".",
              version.hasSuffix("\n")
        else {
            throw RFBProtocolDecoderError.invalidProtocolVersion(version)
        }

        let majorText = String(version.dropFirst(4).prefix(3))
        let minorText = String(version.dropFirst(8).prefix(3))

        guard let major = Int(majorText), let minor = Int(minorText) else {
            throw RFBProtocolDecoderError.invalidProtocolVersion(version)
        }

        return RFBProtocolVersion(major: major, minor: minor)
    }

    public static func parseSecurityTypes(_ data: Data) throws -> RFBSecurityTypes {
        let bytes = Array(data)
        try require(bytes, count: 1)

        let count = Int(bytes[0])
        try require(bytes, count: 1 + count)

        return RFBSecurityTypes(types: Array(bytes[1..<(1 + count)]))
    }

    public static func parseSecurityResult(_ data: Data) throws {
        let bytes = Array(data)
        try require(bytes, count: 4)

        let status = uint32(bytes, at: 0)
        guard status == 0 else {
            throw RFBProtocolDecoderError.securityFailed(status)
        }
    }

    public static func parseServerInit(_ data: Data) throws -> RFBServerInit {
        let bytes = Array(data)
        try require(bytes, count: 24)

        let width = Int(uint16(bytes, at: 0))
        let height = Int(uint16(bytes, at: 2))
        let pixelFormat = RFBPixelFormat(
            bitsPerPixel: bytes[4],
            depth: bytes[5],
            isBigEndian: bytes[6] != 0,
            isTrueColor: bytes[7] != 0,
            redMax: uint16(bytes, at: 8),
            greenMax: uint16(bytes, at: 10),
            blueMax: uint16(bytes, at: 12),
            redShift: bytes[14],
            greenShift: bytes[15],
            blueShift: bytes[16]
        )

        let nameLength = Int(uint32(bytes, at: 20))
        try require(bytes, count: 24 + nameLength)
        let nameBytes = bytes[24..<(24 + nameLength)]
        let name = String(decoding: nameBytes, as: UTF8.self)

        return RFBServerInit(
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            name: name
        )
    }

    public static func parseFramebufferUpdateHeader(_ data: Data) throws -> RFBFramebufferUpdateHeader {
        let bytes = Array(data)
        try require(bytes, count: 4)

        guard bytes[0] == 0 else {
            throw RFBProtocolDecoderError.unexpectedMessageType(bytes[0])
        }

        let rectangleCount = Int(uint16(bytes, at: 2))
        try require(bytes, count: 4 + rectangleCount * 12)

        var rectangles: [RFBRectangleHeader] = []
        rectangles.reserveCapacity(rectangleCount)

        var offset = 4
        for _ in 0..<rectangleCount {
            rectangles.append(
                RFBRectangleHeader(
                    x: Int(uint16(bytes, at: offset)),
                    y: Int(uint16(bytes, at: offset + 2)),
                    width: Int(uint16(bytes, at: offset + 4)),
                    height: Int(uint16(bytes, at: offset + 6)),
                    encodingType: int32(bytes, at: offset + 8)
                )
            )
            offset += 12
        }

        return RFBFramebufferUpdateHeader(rectangles: rectangles)
    }

    /// Parses an RFB ServerCutText message (server-to-client message type 3).
    ///
    /// Wire layout (RFC 6143 §7.6.4):
    ///
    ///   - 1 byte:  message type (must equal 3)
    ///   - 3 bytes: padding (ignored)
    ///   - 4 bytes: big-endian UInt32 length
    ///   - N bytes: clipboard payload (decoded as UTF-8)
    ///
    /// The RFB 3.x specification calls the payload "Latin-1", but real-world
    /// VNC servers and clients commonly transmit UTF-8 here, and the Naru
    /// Remote outgoing path already does so. Decoding as UTF-8 preserves
    /// multilingual round-trip.
    ///
    /// Returns the decoded payload string. Throws a typed
    /// ``RFBProtocolDecoderError`` (never traps) on truncation, wrong message
    /// type, or invalid UTF-8.
    public static func parseServerCutText(_ data: Data) throws -> String {
        let bytes = Array(data)
        try require(bytes, count: 8)

        guard bytes[0] == 3 else {
            throw RFBProtocolDecoderError.unexpectedMessageType(bytes[0])
        }

        let payloadLength = Int(uint32(bytes, at: 4))
        let expectedTotal = 8 + payloadLength
        guard bytes.count >= expectedTotal else {
            throw RFBProtocolDecoderError.truncatedServerCutText(
                expected: expectedTotal,
                actual: bytes.count
            )
        }

        guard payloadLength > 0 else {
            return ""
        }

        let payloadBytes = bytes[8..<expectedTotal]
        guard let text = String(bytes: payloadBytes, encoding: .utf8) else {
            throw RFBProtocolDecoderError.invalidServerCutTextEncoding
        }
        return text
    }

    private static func require(_ bytes: [UInt8], count: Int) throws {
        guard bytes.count >= count else {
            throw RFBProtocolDecoderError.insufficientData(
                expected: count,
                actual: bytes.count
            )
        }
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 |
            UInt32(bytes[offset + 1]) << 16 |
            UInt32(bytes[offset + 2]) << 8 |
            UInt32(bytes[offset + 3])
    }

    private static func int32(_ bytes: [UInt8], at offset: Int) -> Int32 {
        Int32(bitPattern: uint32(bytes, at: offset))
    }
}
