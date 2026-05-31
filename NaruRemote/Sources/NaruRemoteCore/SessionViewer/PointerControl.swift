import CoreGraphics
import Foundation

/// How a one-finger gesture on the remote screen is interpreted.
///
/// - `directTouch`: a tap clicks at the touched point; a one-finger
///   drag pans the viewport while zoomed (the established behavior,
///   extended with pan). The soft cursor is hidden.
/// - `trackpad`: a one-finger drag moves a visible soft cursor
///   relatively (like a laptop trackpad); a tap clicks at the cursor.
///   This is Google Remote Desktop's default and the phone precision
///   win (`spec.md` 003 US3).
public enum PointerControlMode: String, Sendable, Equatable, CaseIterable, Codable {
    case directTouch
    case trackpad

    /// Applied on every fresh session start. Direct-touch preserves
    /// the established tap-where-you-touch behavior; trackpad is one
    /// tap away in the control bar.
    public static let productDefault: PointerControlMode = .directTouch

    public var isTrackpad: Bool { self == .trackpad }
}

/// A soft cursor positioned in remote framebuffer pixel space, used by
/// trackpad mode. Pure value type — the App layer renders an overlay
/// at `position` mapped through `ViewportTransform.viewPoint(...)`.
public struct TrackpadCursor: Equatable, Sendable {
    /// Cursor position in framebuffer pixels.
    public var position: CGPoint
    /// Whether the cursor should be drawn (trackpad mode + has moved).
    public var isVisible: Bool

    public init(position: CGPoint = .zero, isVisible: Bool = false) {
        self.position = position
        self.isVisible = isVisible
    }

    /// Cursor centered on a framebuffer of the given size, visible.
    public static func centered(in framebufferSize: CGSize) -> TrackpadCursor {
        TrackpadCursor(
            position: CGPoint(
                x: framebufferSize.width / 2,
                y: framebufferSize.height / 2
            ),
            isVisible: true
        )
    }

    /// Move relatively by a view-space finger delta. The framebuffer
    /// travel is `viewDelta * sensitivity / displayScale`, so at
    /// `sensitivity == 1` the cursor tracks the finger ~1:1 on screen
    /// regardless of zoom. Result is clamped to the framebuffer.
    public func moved(
        byViewDelta delta: CGSize,
        displayScale: CGFloat,
        sensitivity: CGFloat,
        framebufferSize: CGSize
    ) -> TrackpadCursor {
        let scale = displayScale > 0 ? displayScale : 1
        let dx = delta.width * sensitivity / scale
        let dy = delta.height * sensitivity / scale
        let maxX = Swift.max(0, framebufferSize.width - 1)
        let maxY = Swift.max(0, framebufferSize.height - 1)
        return TrackpadCursor(
            position: CGPoint(
                x: Swift.min(Swift.max(position.x + dx, 0), maxX),
                y: Swift.min(Swift.max(position.y + dy, 0), maxY)
            ),
            isVisible: true
        )
    }
}

/// One RFB `PointerEvent` (RFC 6143 §7.5.5) the App model should send.
/// `x`/`y` are already in framebuffer pixel space. Kept as a value so
/// the gesture decision logic stays pure and `swift test`-able while
/// the async wire send happens in the App layer.
public struct RFBPointerCommand: Equatable, Sendable {
    public let buttonMask: UInt8
    public let x: UInt16
    public let y: UInt16

    public init(buttonMask: UInt8, x: UInt16, y: UInt16) {
        self.buttonMask = buttonMask
        self.x = x
        self.y = y
    }

    /// Button masks per RFC 6143 §7.5.5.
    public static let leftButton: UInt8 = 0x01
    public static let middleButton: UInt8 = 0x02
    public static let rightButton: UInt8 = 0x04
    public static let released: UInt8 = 0x00

    /// A down→up pair for `mask` at `(x, y)`.
    public static func click(mask: UInt8, x: UInt16, y: UInt16) -> [RFBPointerCommand] {
        [
            RFBPointerCommand(buttonMask: mask, x: x, y: y),
            RFBPointerCommand(buttonMask: released, x: x, y: y)
        ]
    }

    static func clamp(_ value: CGFloat) -> UInt16 {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded <= 0 { return 0 }
        if rounded >= CGFloat(UInt16.max) { return UInt16.max }
        return UInt16(rounded)
    }
}
