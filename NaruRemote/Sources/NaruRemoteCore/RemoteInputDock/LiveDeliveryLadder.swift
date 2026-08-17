import Foundation

/// The injection adapter tier chosen for a Live type-through editing window.
///
/// Insert deltas ride one of these tiers, chosen once at window open and held
/// for the window (spec 009 FR-006). Control operations (`BackSpace` deletes and
/// `Return` line boundaries) are orthogonal to this choice and always ride the
/// VNC key-event lane (`.keyEvent`) — see `LiveDeliveryLadder.controlOperationTier`.
///
/// Precedence for *inserts* is `helperNativeInsert` → `clipboardChunk` →
/// `keyEvent` (FR-004). A Unicode payload may ride `.keyEvent` as X11
/// Unicode keysyms: live measurement 2026-07-13 proved they render on macOS
/// Screen Sharing (Korean/CJK land regardless of the remote IME; astral-plane
/// emoji excepted), overturning the earlier 2026-07-05 `no-input` result and
/// blessing the keysym stream in constitution §I (spec 011).
public enum LiveTypeThroughAdapterTier: String, Sendable, Equatable, Codable, CaseIterable {
    /// Helper text bridge `nativeInsert` — the only path with observed delivery
    /// confirmation (spec 006). Primary tier; carries multilingual text.
    case helperNativeInsert

    /// Chunked VNC clipboard + paste — disclosed degraded tier (founder D2).
    /// Overwrites the remote general clipboard and carries a per-chunk settle
    /// latency; unconfirmed. Carries multilingual text when the server confirms
    /// UTF-8 clipboard support.
    case clipboardChunk

    /// VNC `KeyEvent` keysym stream — the pure-VNC type-through path for both
    /// ASCII and Unicode keysyms (2026-07-13 ground truth). Also the lane used
    /// for control operations (`BackSpace`/`Return`), which are never Unicode
    /// keysyms.
    case keyEvent

    /// Whether this tier carries a delivery confirmation observable to Naru.
    /// Only the helper path does (FR-013 — never present the helper path as an
    /// "unknown" result).
    public var deliversObservedConfirmation: Bool { self == .helperNativeInsert }

    /// Whether this tier carries a per-chunk settle latency that must be
    /// disclosed as not real-time (FR-014).
    public var carriesSettleLatency: Bool { self == .clipboardChunk }

    /// Whether this tier overwrites the remote general clipboard, which must be
    /// disclosed (IN-004).
    public var overwritesRemoteClipboard: Bool { self == .clipboardChunk }

    /// Whether this tier can carry Korean/CJK/emoji. Every insert tier can
    /// (helper-native, disclosed clipboard, or Unicode-keysym stream);
    /// astral-plane emoji are the known keysym-stream exception.
    public var isMultilingualCapable: Bool { true }

    /// The fixed per-window delivery status this tier surfaces on success
    /// (FR-013). Raw text never appears; only these fixed catalog values.
    public var successStatus: LiveDeliveryStatus {
        switch self {
        case .helperNativeInsert: return .deliveredObserved
        case .clipboardChunk:     return .unconfirmedClipboard
        case .keyEvent:           return .asciiLastResort
        }
    }
}

/// Fixed catalog of per-window Live delivery statuses surfaced in the dock and
/// diagnostics (spec 009 FR-013 / SP-005). Only these fixed values are ever
/// recorded — never typed content, deltas, or per-unit timings.
public enum LiveDeliveryStatus: String, Sendable, Equatable, Codable, CaseIterable {
    /// No delivery in progress; window open and idle.
    case idle
    /// A delivery is in flight on the selected tier.
    case delivering
    /// Delivered through the helper path with observed confirmation.
    case deliveredObserved
    /// Delivered through the chunked-clipboard fallback; unconfirmed, settle
    /// latency, remote clipboard overwritten (D2).
    case unconfirmedClipboard
    /// Delivered through the Unicode-keysym `KeyEvent` stream; unconfirmed
    /// by observation (best-effort, like the clipboard tier minus the
    /// clipboard overwrite and settle latency).
    case asciiLastResort
    /// Delivery failed or no confirmed/disclosed transport could carry the
    /// payload; the user's text is retained locally (FR-015).
    case retainedFailure
}

/// Payload class for a Live insert delta. Only the distinction that changes the
/// adapter ladder outcome is modelled: pure ASCII vs anything requiring Unicode.
public enum LiveInsertPayloadKind: String, Sendable, Equatable, Codable, CaseIterable {
    case ascii
    case unicode

    /// Classify an insert payload. Anything outside 7-bit ASCII (Korean, CJK,
    /// emoji, accented Latin) is `.unicode`. Both classes ride the keysym
    /// stream on the `.keyEvent` tier (2026-07-13 ground truth); the class only
    /// distinguishes helper/clipboard tier preference disclosures.
    public static func classify(_ text: String) -> LiveInsertPayloadKind {
        text.unicodeScalars.allSatisfy { $0.value <= 0x7F } ? .ascii : .unicode
    }
}

/// Pure policy that selects the insert adapter tier for a Live type-through
/// editing window at window open (spec 009 FR-004 / FR-006, amended by spec
/// 011 / constitution §I 2026-08-17). No I/O, no session — a table from
/// capabilities + payload class to a tier.
///
/// Precedence (FR-004):
/// 1. helper reachable → `.helperNativeInsert` (any payload)
/// 2. else UTF-8 clipboard confirmed → `.clipboardChunk` (any payload)
/// 3. else → `.keyEvent` — the keysym stream carries ASCII and Unicode keysyms
///    alike (2026-07-13 live measurement; Korean/CJK render on macOS Screen
///    Sharing, astral-plane emoji excepted)
public enum LiveDeliveryLadder {
    /// Transport capabilities observed for the current session.
    public struct Capabilities: Sendable, Equatable, Codable {
        /// A paired helper is reachable for `nativeInsert` (spec 006).
        public var helperReachable: Bool
        /// The VNC server confirmed UTF-8 clipboard support, so the chunked
        /// clipboard tier can carry Korean/CJK/emoji.
        public var utf8ClipboardConfirmed: Bool

        public init(helperReachable: Bool, utf8ClipboardConfirmed: Bool) {
            self.helperReachable = helperReachable
            self.utf8ClipboardConfirmed = utf8ClipboardConfirmed
        }
    }

    /// Choose the insert tier for a payload. Always resolves — the keysym
    /// stream is the universal fallback (2026-07-13 ground truth).
    ///
    /// Precedence (FR-004):
    /// 1. helper reachable → `.helperNativeInsert` (any payload)
    /// 2. else UTF-8 clipboard confirmed → `.clipboardChunk` (any payload)
    /// 3. else → `.keyEvent` (keysym stream; ASCII and Unicode alike)
    public static func insertTier(
        for kind: LiveInsertPayloadKind,
        capabilities: Capabilities
    ) -> LiveTypeThroughAdapterTier? {
        if capabilities.helperReachable {
            return .helperNativeInsert
        }
        if capabilities.utf8ClipboardConfirmed {
            return .clipboardChunk
        }
        return .keyEvent
    }

    /// Control operations (`BackSpace` deletes per D1, `Return` line boundaries)
    /// always ride the VNC key-event lane regardless of the window's insert tier
    /// (FR-005/FR-010). They are never a Unicode keysym and never an insert
    /// adapter switch.
    public static let controlOperationTier: LiveTypeThroughAdapterTier = .keyEvent
}
