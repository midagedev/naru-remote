import Foundation

/// The injection adapter tier chosen for a Live type-through editing window.
///
/// Insert deltas ride one of these tiers, chosen once at window open and held
/// for the window (spec 009 FR-006). Control operations (`BackSpace` deletes and
/// `Return` line boundaries) are orthogonal to this choice and always ride the
/// VNC key-event lane (`.keyEvent`) — see `LiveDeliveryLadder.controlOperationTier`.
///
/// Precedence for *inserts* is `helperNativeInsert` → `clipboardChunk` →
/// `keyEvent` (FR-004). A Unicode payload is NEVER delivered via `.keyEvent`:
/// X11 Unicode keysyms do not arrive on macOS Screen Sharing (live-observed
/// `no-input`, 2026-07-05; FR-005), so the `.keyEvent` insert tier is ASCII-only.
public enum LiveTypeThroughAdapterTier: String, Sendable, Equatable, Codable, CaseIterable {
    /// Helper text bridge `nativeInsert` — the only path with observed delivery
    /// confirmation (spec 006). Primary tier; carries multilingual text.
    case helperNativeInsert

    /// Chunked VNC clipboard + paste — disclosed degraded tier (founder D2).
    /// Overwrites the remote general clipboard and carries a per-chunk settle
    /// latency; unconfirmed. Carries multilingual text when the server confirms
    /// UTF-8 clipboard support.
    case clipboardChunk

    /// ASCII-only VNC `KeyEvent` last resort (non-multilingual). Also the lane
    /// used for control operations (`BackSpace`/`Return`), which are never
    /// Unicode keysyms.
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

    /// Whether this tier can carry Korean/CJK/emoji. The `.keyEvent` insert tier
    /// is ASCII-only and must disclose that (FR-014).
    public var isMultilingualCapable: Bool { self != .keyEvent }

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
    /// Delivered through the ASCII-only `KeyEvent` last resort; non-multilingual.
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
    /// emoji, accented Latin) is `.unicode` and MUST NOT ride the `.keyEvent`
    /// insert tier (FR-005).
    public static func classify(_ text: String) -> LiveInsertPayloadKind {
        text.unicodeScalars.allSatisfy { $0.value <= 0x7F } ? .ascii : .unicode
    }
}

/// Pure policy that selects the insert adapter tier for a Live type-through
/// editing window at window open (spec 009 FR-004 / FR-006). No I/O, no session
/// — a table from capabilities + payload class to a tier.
///
/// The single hard rule this encodes: a Unicode payload is never routed to
/// `.keyEvent`. If neither the helper nor a UTF-8-confirmed clipboard can carry
/// Unicode, the ladder returns `nil` and the caller retains the text with a
/// `retainedFailure` status rather than emitting Unicode keysym garbage (US4.2).
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

    /// Choose the insert tier for a payload, or `nil` when no tier can carry it
    /// (Unicode with neither helper nor confirmed UTF-8 clipboard → retain).
    ///
    /// Precedence (FR-004):
    /// 1. helper reachable → `.helperNativeInsert` (any payload)
    /// 2. else UTF-8 clipboard confirmed → `.clipboardChunk` (any payload)
    /// 3. else ASCII payload → `.keyEvent` (ASCII-only last resort)
    /// 4. else (Unicode, no helper, no confirmed clipboard) → `nil`
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
        switch kind {
        case .ascii:
            // ASCII last resort is allowed on the key-event lane (FR-004 tier 3).
            return .keyEvent
        case .unicode:
            // Never Unicode keysyms (FR-005); retain instead.
            return nil
        }
    }

    /// Control operations (`BackSpace` deletes per D1, `Return` line boundaries)
    /// always ride the VNC key-event lane regardless of the window's insert tier
    /// (FR-005/FR-010). They are never a Unicode keysym and never an insert
    /// adapter switch.
    public static let controlOperationTier: LiveTypeThroughAdapterTier = .keyEvent
}
