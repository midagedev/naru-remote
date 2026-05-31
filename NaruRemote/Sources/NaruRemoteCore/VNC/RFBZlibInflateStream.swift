import Foundation
import Compression

/// Session-lifetime persistent zlib inflate for ZRLE (and later Tight)
/// — spec 004 D5 / FR-005.
///
/// RFB sends a **single continuous zlib stream for the whole session**,
/// `Z_SYNC_FLUSH`'d at each rectangle boundary so the client can recover
/// exactly that rectangle's tile bytes. The inflate context (the 32 KiB
/// sliding window) MUST persist across every rectangle and every update —
/// resetting it between rectangles corrupts every frame after the first.
///
/// Apple's `Compression` framework `COMPRESSION_ZLIB` consumes **raw
/// DEFLATE (RFC 1951)**, not the zlib wrapper (RFC 1950), so the 2-byte
/// zlib header at the very start of the stream is stripped once and the
/// remainder fed to one persistent `compression_stream`. The stream is
/// never finalized (no `COMPRESSION_STREAM_FINALIZE`) because the server
/// never ends it until disconnect.
///
/// Not `Sendable`: it owns a raw `compression_stream`. Callers serialize
/// access (the frame pump requests one update at a time); the
/// `RFBNetworkClient` that owns it is `@unchecked Sendable` and never
/// inflates two updates concurrently.
public final class RFBZlibInflateStream {
    public enum InflateError: Error, Equatable {
        case initializationFailed
        case inflateFailed
        case streamEndedUnexpectedly
    }

    private let stream: UnsafeMutablePointer<compression_stream>
    private var initialized = false
    /// RFC 1950 framing is a 2-byte header (e.g. `78 9C`) at the very
    /// start of the stream; stripped once before any raw-DEFLATE input.
    private var headerBytesRemaining = 2
    private var ended = false

    private static let outputChunkSize = 64 * 1024

    public init() throws {
        stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        let status = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else {
            stream.deallocate()
            throw InflateError.initializationFailed
        }
        initialized = true
    }

    deinit {
        if initialized {
            compression_stream_destroy(stream)
        }
        stream.deallocate()
    }

    /// Inflates one rectangle's worth of compressed bytes (already
    /// `Z_SYNC_FLUSH`'d by the server) and returns every decompressed
    /// byte it yields. The window persists across calls, so successive
    /// rectangles decode against the accumulated dictionary.
    public func inflate(_ input: [UInt8]) throws -> [UInt8] {
        guard !ended else {
            throw InflateError.streamEndedUnexpectedly
        }

        var source = input
        if headerBytesRemaining > 0 {
            let skip = min(headerBytesRemaining, source.count)
            source.removeFirst(skip)
            headerBytesRemaining -= skip
            if source.isEmpty {
                return []
            }
        }

        var output = [UInt8]()
        var failure: InflateError?
        let chunkSize = Self.outputChunkSize
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { destination.deallocate() }

        source.withUnsafeBufferPointer { sourceBuffer in
            guard let base = sourceBuffer.baseAddress else {
                return
            }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = sourceBuffer.count

            while true {
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = chunkSize
                let status = compression_stream_process(stream, 0)
                let produced = chunkSize - stream.pointee.dst_size
                if produced > 0 {
                    output.append(contentsOf: UnsafeBufferPointer(start: destination, count: produced))
                }

                switch status {
                case COMPRESSION_STATUS_OK:
                    // Done when the input is fully consumed and the last
                    // process didn't fill the whole output buffer (no more
                    // pending output at this flush boundary).
                    if stream.pointee.src_size == 0, produced < chunkSize {
                        return
                    }
                case COMPRESSION_STATUS_END:
                    ended = true
                    return
                default:
                    failure = .inflateFailed
                    return
                }
            }
        }

        if let failure {
            throw failure
        }
        return output
    }
}

/// Four persistent zlib streams used by Tight basic encoding. Tight can
/// switch between streams 0...3 per rectangle and can request one or
/// more streams be reset before decoding a rectangle.
public final class RFBTightZlibStreams {
    public enum StoreError: Error, Equatable {
        case invalidStreamIndex
    }

    private var streams: [RFBZlibInflateStream?] = Array(repeating: nil, count: 4)

    public init() {}

    public func reset(mask: UInt8) throws {
        for index in 0..<streams.count where mask & UInt8(1 << index) != 0 {
            streams[index] = try RFBZlibInflateStream()
        }
    }

    public func inflate(_ input: [UInt8], streamIndex: Int) throws -> [UInt8] {
        guard streams.indices.contains(streamIndex) else {
            throw StoreError.invalidStreamIndex
        }
        if streams[streamIndex] == nil {
            streams[streamIndex] = try RFBZlibInflateStream()
        }
        guard let stream = streams[streamIndex] else {
            throw StoreError.invalidStreamIndex
        }
        return try stream.inflate(input)
    }
}
