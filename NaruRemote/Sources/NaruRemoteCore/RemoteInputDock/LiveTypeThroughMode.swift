import Foundation

/// Fixed catalog of reasons a Live editing window seals (spec 009 FR-011).
///
/// After a seal, no delete may cross into previously delivered text; a fresh
/// forward-only window opens for subsequent typing. These are safe, content-free
/// labels suitable for diagnostics (SP-005) — they never encode typed text.
public enum LiveWindowSealReason: String, Sendable, Equatable, Codable, CaseIterable {
    /// A pointer/trackpad interaction that could move the remote insertion point.
    case pointerInteraction
    /// The helper reported a focus-change / focus-unavailable state (spec 006).
    case focusUnavailable
    /// Local keyboard focus was lost on the device.
    case focusLost
    /// The session left `.active`.
    case sessionInactive
    /// The app was backgrounded.
    case appBackgrounded
    /// The dock mode was switched away from Live.
    case modeSwitch
    /// The session disconnected / reconnected.
    case disconnect
    /// The active profile changed.
    case profileChange
    /// A `Return`/`Enter` committed the line (FR-010).
    case lineCommitted
    /// The chosen insert adapter failed; the window seals and text is retained
    /// rather than silently retried on another tier (FR-006).
    case adapterFailure
}

/// In-memory dock state for Live type-through mode — peer to
/// `DirectKeystrokeMode` (spec 002) and Compose & Send (spec 006).
///
/// The empty/reset value is still `composeDefault` (Live inactive). Spec 011
/// US1 promotes Type (this mode) as the session default the first time a
/// fresh session reaches `.active`, via
/// `promoteTypeThroughDefaultOnSessionActivationIfNeeded` in
/// `NaruRemoteAppModel`. The mode flag itself still does not persist across
/// disconnect/reconnect or app relaunch; `resetForNewSession()` applies
/// `composeDefault`, then the app model re-promotes Type unless the user
/// already chose a dock mode.
///
/// This holds no draft: sealing leaves delivered text at the remote and discards
/// only marked/uncommitted text (FR-012). The editing-window mirror itself lives
/// in `LiveTypeThroughWindow`; this type carries the mode flag, the tier chosen
/// for the currently open window, and the last fixed status/seal labels for the
/// disclosure surface.
public struct LiveTypeThroughMode: Sendable, Equatable, Codable {
    /// Whether Live mode is the active dock mode.
    public var isActive: Bool
    /// The insert adapter tier selected for the currently open window, if any.
    /// `nil` when no window is open or no tier could carry the payload.
    public var selectedTier: LiveTypeThroughAdapterTier?
    /// Last fixed per-window delivery status for the disclosure surface (FR-013).
    public var lastStatus: LiveDeliveryStatus
    /// Fixed reason the last window sealed, if any (FR-011).
    public var lastSealReason: LiveWindowSealReason?
    /// Whether the persistent transport/latency disclosure has been shown this
    /// session (peer to Direct's per-session entry warning).
    public var hasShownEntryDisclosureThisSession: Bool

    public init(
        isActive: Bool = false,
        selectedTier: LiveTypeThroughAdapterTier? = nil,
        lastStatus: LiveDeliveryStatus = .idle,
        lastSealReason: LiveWindowSealReason? = nil,
        hasShownEntryDisclosureThisSession: Bool = false
    ) {
        self.isActive = isActive
        self.selectedTier = selectedTier
        self.lastStatus = lastStatus
        self.lastSealReason = lastSealReason
        self.hasShownEntryDisclosureThisSession = hasShownEntryDisclosureThisSession
    }

    /// Empty/reset value: Live inactive, no tier, idle status. Still applied by
    /// `resetForNewSession()` (spec 009 FR-016). Spec 011 then promotes Type on
    /// session activation via `promoteTypeThroughDefaultOnSessionActivationIfNeeded`;
    /// the case name is unchanged.
    public static let composeDefault = LiveTypeThroughMode()

    /// Reset to `composeDefault` for a new session (FR-016). Clears the mode
    /// flag, the selected tier, and the per-session disclosure gate.
    public mutating func resetForNewSession() {
        self = .composeDefault
    }
}

public extension LiveTypeThroughMode {
    enum CodingKeys: String, CodingKey {
        case isActive
        case selectedTier
        case lastStatus
        case lastSealReason
        case hasShownEntryDisclosureThisSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isActive: try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false,
            selectedTier: try container.decodeIfPresent(
                LiveTypeThroughAdapterTier.self,
                forKey: .selectedTier
            ),
            lastStatus: try container.decodeIfPresent(
                LiveDeliveryStatus.self,
                forKey: .lastStatus
            ) ?? .idle,
            lastSealReason: try container.decodeIfPresent(
                LiveWindowSealReason.self,
                forKey: .lastSealReason
            ),
            hasShownEntryDisclosureThisSession: try container.decodeIfPresent(
                Bool.self,
                forKey: .hasShownEntryDisclosureThisSession
            ) ?? false
        )
    }
}
