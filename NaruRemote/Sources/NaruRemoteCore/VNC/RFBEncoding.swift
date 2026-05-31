import Foundation

/// RFB encoding and pseudo-encoding code registry (RFC 6143 §7.7 plus
/// the community RFB extensions used by TigerVNC / TurboVNC / macOS
/// Screen Sharing). All values are the signed `s32` codes that appear in
/// a rectangle header's encoding-type field and in the `SetEncodings`
/// preference list.
public enum RFBEncoding {
    // MARK: Real encodings (carry pixel payload)

    public static let raw: Int32 = 0
    public static let copyRect: Int32 = 1
    public static let rre: Int32 = 2
    public static let hextile: Int32 = 5
    public static let tight: Int32 = 7
    public static let trle: Int32 = 15
    public static let zrle: Int32 = 16

    // MARK: Pseudo-encodings (no pixel payload / out-of-band signals)

    public static let lastRect: Int32 = -224
    public static let cursor: Int32 = -239
    public static let xCursor: Int32 = -240
    public static let desktopSize: Int32 = -223
    public static let extendedDesktopSize: Int32 = -308
    public static let desktopName: Int32 = -307
    public static let fence: Int32 = -312
    public static let continuousUpdates: Int32 = -313

    // MARK: Tight quality / compression hint pseudo-encodings

    /// JPEG quality level `0...9` → codes `-32...-23` (community RFB:
    /// `rfbEncodingQualityLevel0 = -32`, `…Level9 = -23`). Higher level
    /// = better quality.
    public static func tightQualityLevel(_ level: Int) -> Int32 {
        let clamped = min(max(level, 0), 9)
        return Int32(-32 + clamped)
    }

    /// Zlib compression level `0...9` → codes `-256...-247`
    /// (`rfbEncodingCompressLevel0 = -256`). Higher level = more CPU,
    /// smaller bytes.
    public static func tightCompressionLevel(_ level: Int) -> Int32 {
        let clamped = min(max(level, 0), 9)
        return Int32(-256 + clamped)
    }
}

/// Pure builder for the ordered `SetEncodings` list (spec 004 FR-001 /
/// FR-012). The order is the server-honored preference: the most
/// efficient *real* encoding Naru can decode comes first, Raw is always
/// present and always last among the real encodings (the universal
/// fallback, RFC 6143 §7.7.1), then pseudo-encodings (whose order is
/// irrelevant — listing one merely enables it).
///
/// Flags default to the set Naru decodes end-to-end in spec 004
/// Increment 1 (CopyRect + Hextile + Raw, plus the streaming-critical
/// LastRect / DesktopSize pseudo-encodings). ZRLE / Tight / Cursor /
/// adaptive quality flip on in later increments without changing the
/// ordering contract.
public struct RFBEncodingPreference: Equatable, Sendable {
    public var zrle: Bool
    public var tight: Bool
    public var hextile: Bool
    public var copyRect: Bool
    public var desktopSize: Bool
    public var extendedDesktopSize: Bool
    public var lastRect: Bool
    public var cursor: Bool
    /// Optional JPEG quality level `0...9` (Tight). Emitted only when
    /// `tight` is also true. `nil` advertises no quality hint.
    public var tightQualityLevel: Int?
    /// Optional zlib compression level `0...9`. Emitted only when a
    /// zlib-using encoding (`zrle` or `tight`) is advertised.
    public var compressionLevel: Int?

    public init(
        zrle: Bool = false,
        tight: Bool = false,
        hextile: Bool = true,
        copyRect: Bool = true,
        desktopSize: Bool = true,
        extendedDesktopSize: Bool = true,
        lastRect: Bool = true,
        cursor: Bool = false,
        tightQualityLevel: Int? = nil,
        compressionLevel: Int? = nil
    ) {
        self.zrle = zrle
        self.tight = tight
        self.hextile = hextile
        self.copyRect = copyRect
        self.desktopSize = desktopSize
        self.extendedDesktopSize = extendedDesktopSize
        self.lastRect = lastRect
        self.cursor = cursor
        self.tightQualityLevel = tightQualityLevel
        self.compressionLevel = compressionLevel
    }

    /// What Naru decodes end-to-end as of spec 004 Increment 1
    /// (CopyRect + Hextile + Raw + streaming pseudo-encodings).
    public static let increment1 = RFBEncodingPreference()

    /// Increment 2 adds **ZRLE** — the cellular bandwidth centerpiece —
    /// ahead of Hextile in the preference order.
    public static let increment2 = RFBEncodingPreference(zrle: true)

    /// Builds the ordered encoding list for the `SetEncodings` message.
    public func encodingList() -> [Int32] {
        var list: [Int32] = []

        // Real encodings, most-preferred first. Raw is appended after
        // these as the guaranteed floor.
        if zrle { list.append(RFBEncoding.zrle) }
        if tight { list.append(RFBEncoding.tight) }
        if hextile { list.append(RFBEncoding.hextile) }
        if copyRect { list.append(RFBEncoding.copyRect) }
        list.append(RFBEncoding.raw)

        // Pseudo-encodings — order among these has no protocol effect.
        if desktopSize { list.append(RFBEncoding.desktopSize) }
        if extendedDesktopSize { list.append(RFBEncoding.extendedDesktopSize) }
        if lastRect { list.append(RFBEncoding.lastRect) }
        if cursor { list.append(RFBEncoding.cursor) }

        // Quality / compression hints ride only on the encodings that
        // use them (spec 004 FR-013).
        if tight, let quality = tightQualityLevel {
            list.append(RFBEncoding.tightQualityLevel(quality))
        }
        if (zrle || tight), let compression = compressionLevel {
            list.append(RFBEncoding.tightCompressionLevel(compression))
        }

        return list
    }
}
