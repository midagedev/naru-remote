import Foundation

/// Error surfaced by an ``RFBByteReader`` when a decoder asks for more
/// bytes than the source can supply. The decode path treats every
/// server byte as untrusted (spec 004 SP-006): a short or hostile
/// rectangle surfaces this typed error and tears the stream down — it
/// never traps or reads out of bounds.
public enum RFBByteReaderError: Error, Equatable {
    case insufficientData(requested: Int, available: Int)
    case negativeRequest(Int)
}

/// Incremental, pull-based byte source the rectangle decoders read
/// from (spec 004 FR-002). The same decoder code path works against a
/// fixed `Data` buffer (unit tests / the kept `RFBRawFramebufferDecoder`
/// shim) and against a live `NWConnection` (production): a rectangle
/// that spans multiple TCP segments simply blocks for more bytes.
///
/// Reference semantics on purpose — the connection-backed reader mutates
/// an underlying socket, so a value-type cursor would not compose.
public protocol RFBByteReader: AnyObject {
    /// Reads exactly `count` bytes, advancing the cursor. Throws
    /// ``RFBByteReaderError`` if the bytes are unavailable.
    func readBytes(_ count: Int) throws -> [UInt8]

    /// Reads exactly `count` bytes as `Data`, advancing the cursor.
    /// Implementations that already receive `Data` can override this to
    /// avoid a full intermediate `[UInt8]` copy on large payload paths.
    func readData(_ count: Int) throws -> Data
}

public extension RFBByteReader {
    func readData(_ count: Int) throws -> Data {
        try Data(readBytes(count))
    }

    func readUInt8() throws -> UInt8 {
        try readBytes(1)[0]
    }

    /// Big-endian (RFC 6143 — all multi-byte fields are big-endian).
    func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(2)
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    /// Big-endian.
    func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(4)
        return UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
    }

    /// Big-endian, two's-complement (encoding types are signed `s32`).
    func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    /// Skips `count` bytes (e.g. padding), advancing the cursor.
    func skip(_ count: Int) throws {
        _ = try readBytes(count)
    }
}

/// `RFBByteReader` over a fixed in-memory buffer. Used by every pure
/// decoder unit test and by the `RFBRawFramebufferDecoder.apply(updateData:)`
/// shim, which wraps the incoming `Data` so the offline test path and the
/// live network path share one decoder.
public final class RFBDataReader: RFBByteReader {
    private let data: Data
    public private(set) var offset: Int

    public init(_ data: Data) {
        self.data = data
        self.offset = 0
    }

    public init(_ bytes: [UInt8]) {
        self.data = Data(bytes)
        self.offset = 0
    }

    /// Bytes not yet consumed.
    public var remaining: Int {
        data.count - offset
    }

    public func readBytes(_ count: Int) throws -> [UInt8] {
        try Array(readData(count))
    }

    public func readData(_ count: Int) throws -> Data {
        guard count >= 0 else {
            throw RFBByteReaderError.negativeRequest(count)
        }
        guard count > 0 else {
            return Data()
        }
        guard offset + count <= data.count else {
            throw RFBByteReaderError.insufficientData(
                requested: count,
                available: data.count - offset
            )
        }
        let slice = data[offset..<(offset + count)]
        offset += count
        return slice
    }
}
