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

    public init(
        width: Int,
        height: Int,
        pixels: [RFBColor],
        fill: RFBColor = RFBColor(red: 0, green: 0, blue: 0)
    ) {
        let safeWidth = max(width, 0)
        let safeHeight = max(height, 0)
        guard safeWidth == 0 || safeHeight <= Int.max / safeWidth else {
            self.width = 0
            self.height = 0
            self.pixels = []
            return
        }

        self.width = safeWidth
        self.height = safeHeight
        let expectedCount = self.width * self.height
        if pixels.count == expectedCount {
            self.pixels = pixels
        } else if pixels.count > expectedCount {
            self.pixels = Array(pixels.prefix(expectedCount))
        } else {
            self.pixels = pixels + Array(
                repeating: fill,
                count: expectedCount - pixels.count
            )
        }
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
    /// background / solid tiles), returning the number of pixels whose
    /// value actually changed.
    @discardableResult
    mutating func fillRegionTrackingChange(
        x: Int,
        y: Int,
        width regionWidth: Int,
        height regionHeight: Int,
        color: RFBColor
    ) -> Int {
        let minX = max(x, 0)
        let minY = max(y, 0)
        let maxX = min(x + regionWidth, width)
        let maxY = min(y + regionHeight, height)
        guard minX < maxX, minY < maxY else {
            return 0
        }
        var changed = 0
        for row in minY..<maxY {
            let base = row * width
            for column in minX..<maxX {
                let index = base + column
                if pixels[index] != color {
                    pixels[index] = color
                    changed += 1
                }
            }
        }
        return changed
    }

    /// Copies a `width × height` block from `(srcX, srcY)` to
    /// `(dstX, dstY)` of the *current* framebuffer (CopyRect, RFC 6143
    /// §7.7.2). Overlap-safe: the source region is snapshotted before any
    /// destination write. Caller must have bounds-validated both rects.
    /// Returns the number of destination pixels whose value changed.
    @discardableResult
    mutating func copyRegionTrackingChange(
        srcX: Int,
        srcY: Int,
        toX dstX: Int,
        toY dstY: Int,
        width copyWidth: Int,
        height copyHeight: Int
    ) -> Int {
        guard copyWidth > 0, copyHeight > 0 else {
            return 0
        }
        var snapshot = [RFBColor]()
        snapshot.reserveCapacity(copyWidth * copyHeight)
        for row in 0..<copyHeight {
            let srcBase = (srcY + row) * width + srcX
            snapshot.append(contentsOf: pixels[srcBase..<(srcBase + copyWidth)])
        }
        var changed = 0
        for row in 0..<copyHeight {
            let dstBase = (dstY + row) * width + dstX
            let snapBase = row * copyWidth
            for column in 0..<copyWidth {
                let index = dstBase + column
                let color = snapshot[snapBase + column]
                if pixels[index] != color {
                    pixels[index] = color
                    changed += 1
                }
            }
        }
        return changed
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

public struct RFBServerCursor: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let hotSpotX: Int
    public let hotSpotY: Int
    public let pixels: [RFBColor]

    public init(
        width: Int,
        height: Int,
        hotSpotX: Int,
        hotSpotY: Int,
        pixels: [RFBColor]
    ) {
        let safeWidth = max(width, 0)
        let safeHeight = max(height, 0)
        guard safeWidth == 0 || safeHeight <= Int.max / safeWidth else {
            self.width = 0
            self.height = 0
            self.hotSpotX = max(hotSpotX, 0)
            self.hotSpotY = max(hotSpotY, 0)
            self.pixels = []
            return
        }

        self.width = safeWidth
        self.height = safeHeight
        self.hotSpotX = max(hotSpotX, 0)
        self.hotSpotY = max(hotSpotY, 0)
        let expectedCount = self.width * self.height
        if pixels.count == expectedCount {
            self.pixels = pixels
        } else if pixels.count > expectedCount {
            self.pixels = Array(pixels.prefix(expectedCount))
        } else {
            self.pixels = pixels + Array(
                repeating: RFBColor(red: 0, green: 0, blue: 0, alpha: 0),
                count: expectedCount - pixels.count
            )
        }
    }

    public subscript(x: Int, y: Int) -> RFBColor? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }
        return pixels[y * width + x]
    }
}

public struct RFBFramebufferUpdateTiming: Codable, Equatable, Sendable {
    /// Coarse elapsed receive time for benchmark bucketing, rounded to
    /// whole milliseconds before storage.
    public let totalMilliseconds: Int
    /// Coarse socket read time accumulated across blocking reads.
    public let networkReadMilliseconds: Int
    /// Coarse wait for the first server byte after the receive begins.
    /// This lets benchmarks distinguish server/update wait from the
    /// remaining payload read time without emitting frame contents.
    public let firstByteWaitMilliseconds: Int?
    /// Derived from `networkReadMilliseconds - firstByteWaitMilliseconds`.
    /// Nil when no server byte was received, such as an idle timeout.
    public let payloadReadMilliseconds: Int?
    /// Derived from rounded millisecond buckets, so it should be used
    /// for aggregate diagnosis rather than sub-millisecond profiling.
    public let clientProcessingMilliseconds: Int

    public init(
        totalMilliseconds: Int,
        networkReadMilliseconds: Int,
        firstByteWaitMilliseconds: Int? = nil
    ) {
        let totalMilliseconds = max(totalMilliseconds, 0)
        let networkReadMilliseconds = max(networkReadMilliseconds, 0)
        let firstByteWaitMilliseconds = firstByteWaitMilliseconds.map {
            min(max($0, 0), networkReadMilliseconds)
        }
        self.totalMilliseconds = totalMilliseconds
        self.networkReadMilliseconds = networkReadMilliseconds
        self.firstByteWaitMilliseconds = firstByteWaitMilliseconds
        self.payloadReadMilliseconds = firstByteWaitMilliseconds.map {
            max(networkReadMilliseconds - $0, 0)
        }
        self.clientProcessingMilliseconds = max(totalMilliseconds - networkReadMilliseconds, 0)
    }
}

public struct RFBFramebufferDecodeMetrics: Codable, Equatable, Sendable {
    /// Coarse aggregate time spent inflating ZRLE compressed payloads.
    /// Safe for benchmark artifacts: it carries no target identity,
    /// dimensions, coordinates, byte counts, pixels, or payload details.
    public let zrleInflateMilliseconds: Int
    /// Coarse aggregate time spent parsing ZRLE tiles and applying them
    /// to the local framebuffer.
    public let zrleTileApplyMilliseconds: Int

    public init(
        zrleInflateMilliseconds: Int = 0,
        zrleTileApplyMilliseconds: Int = 0
    ) {
        self.zrleInflateMilliseconds = max(zrleInflateMilliseconds, 0)
        self.zrleTileApplyMilliseconds = max(zrleTileApplyMilliseconds, 0)
    }

    public var hasMeasurements: Bool {
        zrleInflateMilliseconds > 0 || zrleTileApplyMilliseconds > 0
    }
}

public struct RFBFramebufferEncodingMix: Codable, Equatable, Sendable {
    public let rawRectangles: Int
    public let copyRectRectangles: Int
    public let hextileRectangles: Int
    public let zrleRectangles: Int
    public let tightRectangles: Int
    public let cursorRectangles: Int
    public let xCursorRectangles: Int
    public let desktopSizeRectangles: Int
    public let extendedDesktopSizeRectangles: Int
    public let lastRectRectangles: Int
    public let endOfContinuousUpdatesEvents: Int

    public init(
        rawRectangles: Int = 0,
        copyRectRectangles: Int = 0,
        hextileRectangles: Int = 0,
        zrleRectangles: Int = 0,
        tightRectangles: Int = 0,
        cursorRectangles: Int = 0,
        xCursorRectangles: Int = 0,
        desktopSizeRectangles: Int = 0,
        extendedDesktopSizeRectangles: Int = 0,
        lastRectRectangles: Int = 0,
        endOfContinuousUpdatesEvents: Int = 0
    ) {
        self.rawRectangles = max(rawRectangles, 0)
        self.copyRectRectangles = max(copyRectRectangles, 0)
        self.hextileRectangles = max(hextileRectangles, 0)
        self.zrleRectangles = max(zrleRectangles, 0)
        self.tightRectangles = max(tightRectangles, 0)
        self.cursorRectangles = max(cursorRectangles, 0)
        self.xCursorRectangles = max(xCursorRectangles, 0)
        self.desktopSizeRectangles = max(desktopSizeRectangles, 0)
        self.extendedDesktopSizeRectangles = max(extendedDesktopSizeRectangles, 0)
        self.lastRectRectangles = max(lastRectRectangles, 0)
        self.endOfContinuousUpdatesEvents = max(endOfContinuousUpdatesEvents, 0)
    }

    /// Counts safe catalogued framebuffer update records, including
    /// pseudo-encodings such as cursor, desktop-size, and LastRect.
    public var totalRectangles: Int {
        rawRectangles
            + copyRectRectangles
            + hextileRectangles
            + zrleRectangles
            + tightRectangles
            + cursorRectangles
            + xCursorRectangles
            + desktopSizeRectangles
            + extendedDesktopSizeRectangles
            + lastRectRectangles
    }

    public func recordingRectangle(encoding: Int32) -> RFBFramebufferEncodingMix {
        switch encoding {
        case RFBEncoding.raw:
            return adding(rawRectangles: 1)
        case RFBEncoding.copyRect:
            return adding(copyRectRectangles: 1)
        case RFBEncoding.hextile:
            return adding(hextileRectangles: 1)
        case RFBEncoding.zrle:
            return adding(zrleRectangles: 1)
        case RFBEncoding.tight:
            return adding(tightRectangles: 1)
        case RFBEncoding.cursor:
            return adding(cursorRectangles: 1)
        case RFBEncoding.xCursor:
            return adding(xCursorRectangles: 1)
        case RFBEncoding.desktopSize:
            return adding(desktopSizeRectangles: 1)
        case RFBEncoding.extendedDesktopSize:
            return adding(extendedDesktopSizeRectangles: 1)
        case RFBEncoding.lastRect:
            return adding(lastRectRectangles: 1)
        default:
            return self
        }
    }

    public func adding(_ other: RFBFramebufferEncodingMix) -> RFBFramebufferEncodingMix {
        RFBFramebufferEncodingMix(
            rawRectangles: rawRectangles + other.rawRectangles,
            copyRectRectangles: copyRectRectangles + other.copyRectRectangles,
            hextileRectangles: hextileRectangles + other.hextileRectangles,
            zrleRectangles: zrleRectangles + other.zrleRectangles,
            tightRectangles: tightRectangles + other.tightRectangles,
            cursorRectangles: cursorRectangles + other.cursorRectangles,
            xCursorRectangles: xCursorRectangles + other.xCursorRectangles,
            desktopSizeRectangles: desktopSizeRectangles + other.desktopSizeRectangles,
            extendedDesktopSizeRectangles: extendedDesktopSizeRectangles + other.extendedDesktopSizeRectangles,
            lastRectRectangles: lastRectRectangles + other.lastRectRectangles,
            endOfContinuousUpdatesEvents: endOfContinuousUpdatesEvents + other.endOfContinuousUpdatesEvents
        )
    }

    private func adding(
        rawRectangles: Int = 0,
        copyRectRectangles: Int = 0,
        hextileRectangles: Int = 0,
        zrleRectangles: Int = 0,
        tightRectangles: Int = 0,
        cursorRectangles: Int = 0,
        xCursorRectangles: Int = 0,
        desktopSizeRectangles: Int = 0,
        extendedDesktopSizeRectangles: Int = 0,
        lastRectRectangles: Int = 0,
        endOfContinuousUpdatesEvents: Int = 0
    ) -> RFBFramebufferEncodingMix {
        adding(
            RFBFramebufferEncodingMix(
                rawRectangles: rawRectangles,
                copyRectRectangles: copyRectRectangles,
                hextileRectangles: hextileRectangles,
                zrleRectangles: zrleRectangles,
                tightRectangles: tightRectangles,
                cursorRectangles: cursorRectangles,
                xCursorRectangles: xCursorRectangles,
                desktopSizeRectangles: desktopSizeRectangles,
                extendedDesktopSizeRectangles: extendedDesktopSizeRectangles,
                lastRectRectangles: lastRectRectangles,
                endOfContinuousUpdatesEvents: endOfContinuousUpdatesEvents
            )
        )
    }
}

public struct RFBFramebufferUpdateResult: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case framebuffer
        case dirtyRectangles
        case changedPixelCount
        case capturedAt
        case didResizeDesktop
        case serverCursor
        case endedContinuousUpdates
        case transportIdleTimedOut
        case timing
        case decodeMetrics
        case encodingMix
    }

    public let framebuffer: RFBRawFramebuffer
    public let dirtyRectangles: [RFBFrameDamageRect]
    public let changedPixelCount: Int
    public let capturedAt: Date
    /// True when this update reallocated the framebuffer via a
    /// DesktopSize / ExtendedDesktopSize pseudo-rectangle (spec 004
    /// FR-008). The App layer re-fits the viewport on this signal; the
    /// network client refreshes its cached server dimensions.
    public let didResizeDesktop: Bool
    /// Cursor pseudo-encoding decoded from this update, if present.
    /// It is additive to the framebuffer: cursor pixels are surfaced to
    /// the presentation layer and never written into `framebuffer`.
    public let serverCursor: RFBServerCursor?
    /// True when the server sent TigerVNC's EndOfContinuousUpdates
    /// control byte. The framebuffer is unchanged; callers can treat
    /// the update as liveness and fall back to request/response pacing.
    public let endedContinuousUpdates: Bool
    /// True when a ContinuousUpdates receive timed out without bytes
    /// while keeping the socket and buffered read state intact. This is
    /// not a frame round-trip latency sample.
    public let transportIdleTimedOut: Bool
    /// Optional receive-path timing captured by the live network client.
    /// Contains only aggregate millisecond durations: total receive,
    /// socket-read waiting/copy time, and the derived client processing
    /// remainder. It carries no target identity, dimensions, coordinates,
    /// byte counts, pixels, or raw payload details.
    public let timing: RFBFramebufferUpdateTiming?
    /// Safe aggregate decode-phase timings captured by the framebuffer
    /// decoder. This is diagnostic/benchmark metadata only; it stores no
    /// pixels, coordinates, dimensions, byte counts, or raw payload.
    public let decodeMetrics: RFBFramebufferDecodeMetrics
    /// Safe counts of actual framebuffer encodings observed in this
    /// update. Counts are fixed catalog labels only; no raw payload,
    /// rectangle coordinates, dimensions, byte counts, or pixels are
    /// stored here.
    public let encodingMix: RFBFramebufferEncodingMix

    public init(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect],
        changedPixelCount: Int,
        capturedAt: Date = Date(),
        didResizeDesktop: Bool = false,
        serverCursor: RFBServerCursor? = nil,
        endedContinuousUpdates: Bool = false,
        transportIdleTimedOut: Bool = false,
        timing: RFBFramebufferUpdateTiming? = nil,
        decodeMetrics: RFBFramebufferDecodeMetrics = RFBFramebufferDecodeMetrics(),
        encodingMix: RFBFramebufferEncodingMix = RFBFramebufferEncodingMix()
    ) {
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles
        self.changedPixelCount = max(changedPixelCount, 0)
        self.capturedAt = capturedAt
        self.didResizeDesktop = didResizeDesktop
        self.serverCursor = serverCursor
        self.endedContinuousUpdates = endedContinuousUpdates
        self.transportIdleTimedOut = transportIdleTimedOut
        self.timing = timing
        self.decodeMetrics = decodeMetrics
        self.encodingMix = encodingMix
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            framebuffer: try container.decode(RFBRawFramebuffer.self, forKey: .framebuffer),
            dirtyRectangles: try container.decode([RFBFrameDamageRect].self, forKey: .dirtyRectangles),
            changedPixelCount: try container.decode(Int.self, forKey: .changedPixelCount),
            capturedAt: try container.decode(Date.self, forKey: .capturedAt),
            didResizeDesktop: try container.decodeIfPresent(Bool.self, forKey: .didResizeDesktop) ?? false,
            serverCursor: try container.decodeIfPresent(RFBServerCursor.self, forKey: .serverCursor),
            endedContinuousUpdates: try container.decodeIfPresent(Bool.self, forKey: .endedContinuousUpdates) ?? false,
            transportIdleTimedOut: try container.decodeIfPresent(Bool.self, forKey: .transportIdleTimedOut) ?? false,
            timing: try container.decodeIfPresent(RFBFramebufferUpdateTiming.self, forKey: .timing),
            decodeMetrics: try container.decodeIfPresent(
                RFBFramebufferDecodeMetrics.self,
                forKey: .decodeMetrics
            ) ?? RFBFramebufferDecodeMetrics(),
            encodingMix: try container.decodeIfPresent(
                RFBFramebufferEncodingMix.self,
                forKey: .encodingMix
            ) ?? RFBFramebufferEncodingMix()
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(framebuffer, forKey: .framebuffer)
        try container.encode(dirtyRectangles, forKey: .dirtyRectangles)
        try container.encode(changedPixelCount, forKey: .changedPixelCount)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(didResizeDesktop, forKey: .didResizeDesktop)
        try container.encodeIfPresent(serverCursor, forKey: .serverCursor)
        try container.encode(endedContinuousUpdates, forKey: .endedContinuousUpdates)
        try container.encode(transportIdleTimedOut, forKey: .transportIdleTimedOut)
        try container.encodeIfPresent(timing, forKey: .timing)
        if decodeMetrics.hasMeasurements {
            try container.encode(decodeMetrics, forKey: .decodeMetrics)
        }
        try container.encode(encodingMix, forKey: .encodingMix)
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

    public func withTiming(_ timing: RFBFramebufferUpdateTiming?) -> RFBFramebufferUpdateResult {
        RFBFramebufferUpdateResult(
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            capturedAt: capturedAt,
            didResizeDesktop: didResizeDesktop,
            serverCursor: serverCursor,
            endedContinuousUpdates: endedContinuousUpdates,
            transportIdleTimedOut: transportIdleTimedOut,
            timing: timing,
            decodeMetrics: decodeMetrics,
            encodingMix: encodingMix
        )
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
    /// Cursor pseudo-encoding declared an absurd shape or malformed
    /// payload (spec 004 FR-009 / SP-006).
    case malformedCursor
    /// Tight rectangle declared an unsupported or malformed
    /// subencoding/filter in the current decoder slice (spec 004
    /// FR-006 / SP-006).
    case malformedTight

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
        case .malformedCursor:
            return "Cursor pseudo-encoding payload is malformed."
        case .malformedTight:
            return "Tight rectangle payload is malformed or unsupported."
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
        if let offsets = directEightBitChannelOffsets(pixelByteCount: bytesPerPixelValue) {
            return RFBColor(
                red: bytes[offset + offsets.red],
                green: bytes[offset + offsets.green],
                blue: bytes[offset + offsets.blue]
            )
        }

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
        if let offsets = directEightBitChannelOffsets(pixelByteCount: size) {
            return RFBColor(
                red: bytes[offset + offsets.red],
                green: bytes[offset + offsets.green],
                blue: bytes[offset + offsets.blue]
            )
        }

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

    /// Fast path for the overwhelmingly common VNC format used by macOS
    /// Screen Sharing and TigerVNC: 8-bit RGB channels sitting on byte
    /// boundaries inside a 32-bpp true-colour pixel. Avoids per-pixel
    /// shift/mask/divide work in the Raw/Hextile/ZRLE hot path while
    /// falling back to the general decoder for unusual max/shift layouts.
    private func directEightBitChannelOffsets(pixelByteCount: Int) -> (red: Int, green: Int, blue: Int)? {
        guard isTrueColor,
              redMax == 255,
              greenMax == 255,
              blueMax == 255,
              redShift.isMultiple(of: 8),
              greenShift.isMultiple(of: 8),
              blueShift.isMultiple(of: 8)
        else {
            return nil
        }

        func byteOffset(for shift: UInt8) -> Int? {
            let shiftByte = Int(shift / 8)
            let index = isBigEndian ? pixelByteCount - 1 - shiftByte : shiftByte
            guard index >= 0, index < pixelByteCount else {
                return nil
            }
            return index
        }

        guard let red = byteOffset(for: redShift),
              let green = byteOffset(for: greenShift),
              let blue = byteOffset(for: blueShift)
        else {
            return nil
        }
        return (red, green, blue)
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
