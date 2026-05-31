import CoreGraphics
import Foundation

/// The set of gestures the session viewport can recognize, expressed
/// independently of UIKit so the decision logic is `swift test`-able.
/// View-space points/deltas are in the host view's coordinate space
/// (points); the resolver maps them to framebuffer pixels through the
/// shared `ViewportTransform` (003 FR-014).
public enum PointerGesture: Equatable, Sendable {
    /// A single tap at a view-space point.
    case tap(viewPoint: CGPoint)
    /// A two-finger tap at a view-space point (right-click intent).
    case secondaryTap(viewPoint: CGPoint)
    /// A long-press at a view-space point (right-click intent, used by
    /// direct-touch mode).
    case longPress(viewPoint: CGPoint)
    /// One-finger drag lifecycle. `translation` is the per-callback
    /// delta in view points; `viewPoint` is the current location.
    case dragBegan(viewPoint: CGPoint)
    case dragChanged(viewPoint: CGPoint, translation: CGSize)
    case dragEnded(viewPoint: CGPoint)
    /// Tap-and-a-half: a tap immediately followed by a hold-drag. In
    /// trackpad mode this is a button-1 press-drag-release at the
    /// cursor; the App layer recognizes the "tap then hold" timing.
    case pressDragBegan
    case pressDragChanged(translation: CGSize)
    case pressDragEnded
}

/// The outcome of resolving one gesture: an updated viewport transform
/// (local-only), an updated trackpad cursor (local-only), and zero or
/// more RFB `PointerEvent`s the App model must send on the wire. Zoom
/// and pan produce an empty `commands` array (constitution §I).
public struct PointerGestureOutcome: Equatable, Sendable {
    public var transform: ViewportTransform
    public var cursor: TrackpadCursor
    public var commands: [RFBPointerCommand]

    public init(
        transform: ViewportTransform,
        cursor: TrackpadCursor,
        commands: [RFBPointerCommand] = []
    ) {
        self.transform = transform
        self.cursor = cursor
        self.commands = commands
    }
}

/// Pure resolver mapping a gesture (given the current mode, transform,
/// and cursor) to a local state update plus RFB pointer commands. The
/// App layer owns recognizers and the async wire send; this owns the
/// decision table so direct-touch and trackpad can never diverge.
public struct PointerGestureResolver: Sendable {
    public let mode: PointerControlMode
    public let trackpadSensitivity: CGFloat
    /// Margin (view points) kept between the trackpad cursor and the
    /// viewport edge before auto-pan kicks in while zoomed.
    public let autoPanMargin: CGFloat

    public init(
        mode: PointerControlMode,
        trackpadSensitivity: CGFloat = 1.0,
        autoPanMargin: CGFloat = 48
    ) {
        self.mode = mode
        self.trackpadSensitivity = trackpadSensitivity
        self.autoPanMargin = autoPanMargin
    }

    public func resolve(
        _ gesture: PointerGesture,
        transform: ViewportTransform,
        cursor: TrackpadCursor
    ) -> PointerGestureOutcome {
        switch mode {
        case .directTouch:
            return resolveDirectTouch(gesture, transform: transform, cursor: cursor)
        case .trackpad:
            return resolveTrackpad(gesture, transform: transform, cursor: cursor)
        }
    }

    // MARK: - Direct touch

    private func resolveDirectTouch(
        _ gesture: PointerGesture,
        transform: ViewportTransform,
        cursor: TrackpadCursor
    ) -> PointerGestureOutcome {
        // Cursor is never shown in direct-touch mode.
        let hiddenCursor = TrackpadCursor(position: cursor.position, isVisible: false)

        switch gesture {
        case let .tap(viewPoint):
            return PointerGestureOutcome(
                transform: transform,
                cursor: hiddenCursor,
                commands: clickCommands(atViewPoint: viewPoint, transform: transform, mask: RFBPointerCommand.leftButton)
            )
        case let .secondaryTap(viewPoint), let .longPress(viewPoint):
            return PointerGestureOutcome(
                transform: transform,
                cursor: hiddenCursor,
                commands: clickCommands(atViewPoint: viewPoint, transform: transform, mask: RFBPointerCommand.rightButton)
            )
        case .dragBegan:
            // A pan begins; no wire event. (Drag-to-click in direct
            // mode remains the existing pointer-down/move/up path the
            // App model drives directly; this resolver path is for the
            // zoom-pan gesture set.)
            return PointerGestureOutcome(transform: transform, cursor: hiddenCursor)
        case let .dragChanged(_, translation):
            // Pan the viewport (local only — constitution §I).
            return PointerGestureOutcome(
                transform: transform.panned(by: translation),
                cursor: hiddenCursor
            )
        case .dragEnded:
            return PointerGestureOutcome(transform: transform, cursor: hiddenCursor)
        case .pressDragBegan, .pressDragChanged, .pressDragEnded:
            // Tap-and-a-half is a trackpad-mode affordance; ignore in
            // direct mode.
            return PointerGestureOutcome(transform: transform, cursor: hiddenCursor)
        }
    }

    // MARK: - Trackpad

    private func resolveTrackpad(
        _ gesture: PointerGesture,
        transform: ViewportTransform,
        cursor: TrackpadCursor
    ) -> PointerGestureOutcome {
        switch gesture {
        case .tap:
            // Tap clicks at the CURSOR, not the touch point (003 FR-008).
            return clickAtCursor(mask: RFBPointerCommand.leftButton, transform: transform, cursor: cursor)
        case .secondaryTap, .longPress:
            return clickAtCursor(mask: RFBPointerCommand.rightButton, transform: transform, cursor: cursor)
        case .dragBegan:
            return PointerGestureOutcome(transform: transform, cursor: cursor)
        case let .dragChanged(_, translation):
            // Move the cursor relatively; auto-pan to keep it visible.
            let movedCursor = cursor.moved(
                byViewDelta: translation,
                displayScale: transform.displayScale,
                sensitivity: trackpadSensitivity,
                framebufferSize: transform.framebufferSize
            )
            let pannedTransform = transform.panToReveal(
                framebufferPoint: movedCursor.position,
                margin: autoPanMargin
            )
            return PointerGestureOutcome(transform: pannedTransform, cursor: movedCursor)
        case .dragEnded:
            return PointerGestureOutcome(transform: transform, cursor: cursor)
        case .pressDragBegan:
            // Button-1 down at the cursor; held through the move.
            let x = RFBPointerCommand.clamp(cursor.position.x)
            let y = RFBPointerCommand.clamp(cursor.position.y)
            return PointerGestureOutcome(
                transform: transform,
                cursor: cursor,
                commands: [RFBPointerCommand(buttonMask: RFBPointerCommand.leftButton, x: x, y: y)]
            )
        case let .pressDragChanged(translation):
            let movedCursor = cursor.moved(
                byViewDelta: translation,
                displayScale: transform.displayScale,
                sensitivity: trackpadSensitivity,
                framebufferSize: transform.framebufferSize
            )
            let pannedTransform = transform.panToReveal(
                framebufferPoint: movedCursor.position,
                margin: autoPanMargin
            )
            let x = RFBPointerCommand.clamp(movedCursor.position.x)
            let y = RFBPointerCommand.clamp(movedCursor.position.y)
            // Button-1 stays held (mask 0x01) through the move.
            return PointerGestureOutcome(
                transform: pannedTransform,
                cursor: movedCursor,
                commands: [RFBPointerCommand(buttonMask: RFBPointerCommand.leftButton, x: x, y: y)]
            )
        case .pressDragEnded:
            let x = RFBPointerCommand.clamp(cursor.position.x)
            let y = RFBPointerCommand.clamp(cursor.position.y)
            return PointerGestureOutcome(
                transform: transform,
                cursor: cursor,
                commands: [RFBPointerCommand(buttonMask: RFBPointerCommand.released, x: x, y: y)]
            )
        }
    }

    // MARK: - Helpers

    private func clickCommands(
        atViewPoint viewPoint: CGPoint,
        transform: ViewportTransform,
        mask: UInt8
    ) -> [RFBPointerCommand] {
        guard let fbPoint = transform.framebufferPoint(fromViewPoint: viewPoint) else {
            // Letterbox band → no-op (not a clamped edge click).
            return []
        }
        return RFBPointerCommand.click(
            mask: mask,
            x: RFBPointerCommand.clamp(fbPoint.x),
            y: RFBPointerCommand.clamp(fbPoint.y)
        )
    }

    private func clickAtCursor(
        mask: UInt8,
        transform: ViewportTransform,
        cursor: TrackpadCursor
    ) -> PointerGestureOutcome {
        let x = RFBPointerCommand.clamp(cursor.position.x)
        let y = RFBPointerCommand.clamp(cursor.position.y)
        return PointerGestureOutcome(
            transform: transform,
            cursor: cursor,
            commands: RFBPointerCommand.click(mask: mask, x: x, y: y)
        )
    }
}
