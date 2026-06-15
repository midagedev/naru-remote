import CoreGraphics
import Foundation

/// How a one-finger gesture on the remote screen is interpreted.
///
/// - `directTouch`: a tap clicks at the touched point; a one-finger
///   drag pans the viewport while zoomed (the established behavior,
///   extended with pan). The trackpad cursor is hidden.
/// - `trackpad`: a one-finger drag moves the visible cursor and emits
///   buttonless remote pointer moves (like a laptop trackpad); a tap
///   clicks at the cursor. This is Google Remote Desktop's default and
///   the phone precision win (`spec.md` 003 US3).
public enum PointerControlMode: String, Sendable, Equatable, CaseIterable, Codable {
    case directTouch
    case trackpad

    /// Applied on every fresh session start. Direct-touch preserves
    /// the established tap-where-you-touch behavior; trackpad is one
    /// tap away in the control bar.
    public static let productDefault: PointerControlMode = .directTouch

    public var isTrackpad: Bool { self == .trackpad }
}

/// A cursor position in remote framebuffer pixel space, used by
/// trackpad mode. Pure value type — the App layer sends buttonless RFB
/// pointer moves and renders either the server cursor shape or a local
/// fallback at `position` mapped through `ViewportTransform.viewPoint(...)`.
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

public enum RFBPointerCommandBatch: Equatable, Sendable {
    case none
    case one(RFBPointerCommand)
    case two(RFBPointerCommand, RFBPointerCommand)
    case many([RFBPointerCommand])

    public init(_ commands: [RFBPointerCommand]) {
        switch commands.count {
        case 0:
            self = .none
        case 1:
            self = .one(commands[0])
        case 2:
            self = .two(commands[0], commands[1])
        default:
            self = .many(commands)
        }
    }

    public var isEmpty: Bool {
        if case .none = self {
            return true
        }
        return false
    }

    public var count: Int {
        switch self {
        case .none:
            return 0
        case .one:
            return 1
        case .two:
            return 2
        case let .many(commands):
            return commands.count
        }
    }

    public var first: RFBPointerCommand? {
        switch self {
        case .none:
            return nil
        case let .one(command), let .two(command, _):
            return command
        case let .many(commands):
            return commands.first
        }
    }

    public var commands: [RFBPointerCommand] {
        switch self {
        case .none:
            return []
        case let .one(command):
            return [command]
        case let .two(first, second):
            return [first, second]
        case let .many(commands):
            return commands
        }
    }

    public var singleButtonlessPointerMove: RFBPointerCommand? {
        guard case let .one(command) = self,
              command.buttonMask == RFBPointerCommand.released
        else {
            return nil
        }
        return command
    }

    public static func click(mask: UInt8, x: UInt16, y: UInt16) -> RFBPointerCommandBatch {
        .two(
            RFBPointerCommand(buttonMask: mask, x: x, y: y),
            RFBPointerCommand(buttonMask: RFBPointerCommand.released, x: x, y: y)
        )
    }
}
