import Foundation

/// Pure policy for indirect-pointer (Bluetooth mouse / hardware
/// trackpad) input on the session viewport (spec 012 US1).
///
/// UIKit wiring lives in `MetalFramebufferView`. This type owns the
/// named recognizer constants and mode routing so `swift test` can
/// pin the contract without compiling the iOS host view.
///
/// Coordinates and user input never appear here (constitution §IV).
public enum IndirectPointerInputPolicy: Sendable {

    /// Where hover motion should land. Both cases produce a remote
    /// cursor move; they differ only in absolute vs trackpad routing.
    public enum HoverRoute: Equatable, Sendable {
        /// Trackpad mode: existing `.hoverMoved(viewPoint:)` resolver path.
        case trackpadRelative
        /// Direct-touch mode: absolute view-space pointer move.
        case absoluteMove
    }

    /// Where a physical secondary click should land.
    public enum SecondaryClickRoute: Equatable, Sendable {
        /// Trackpad mode: `.secondaryTap(viewPoint:)` through the resolver.
        case trackpadSecondaryTap
        /// Direct-touch mode: existing `rightClickHandler` at the view point.
        case absoluteRightClick
    }

    /// Button required of an indirect-pointer tap recognizer.
    /// Raw values match `UIEvent.ButtonMask` (`UIEvent.h`:
    /// Primary = 1<<0, Secondary = 1<<1). Finger taps are unaffected —
    /// `buttonMaskRequired` is only evaluated on indirect devices.
    public enum ButtonRequirement: Equatable, Sendable {
        case primary
        case secondary

        public var rawValue: Int {
            switch self {
            case .primary:
                return 1 << 0
            case .secondary:
                return 1 << 1
            }
        }
    }

    public static func hoverRoute(for mode: PointerControlMode) -> HoverRoute {
        mode.isTrackpad ? .trackpadRelative : .absoluteMove
    }

    public static func secondaryClickRoute(
        for mode: PointerControlMode
    ) -> SecondaryClickRoute {
        mode.isTrackpad ? .trackpadSecondaryTap : .absoluteRightClick
    }

    // MARK: Scroll-wheel pan recognizer (US1-1)

    /// Dedicated pan recognizer accepts only scroll-type events
    /// (mouse wheel / trackpad two-finger scroll), never finger pans.
    public static let scrollWheelRequiresScrollTypeMask = true
    public static let scrollWheelMinimumNumberOfTouches = 0
    public static let scrollWheelMaximumNumberOfTouches = 0
    /// `UIScrollTypeMask.all` = discrete | continuous.
    public static let scrollWheelAllowedScrollTypesMaskRawValue = (1 << 0) | (1 << 1)

    // MARK: Secondary-button tap recognizer (US1-2)

    public static let secondaryButtonTapNumberOfTouchesRequired = 1
    public static let secondaryButtonTapRequiredButton: ButtonRequirement = .secondary
    public static let primaryTapRequiredButton: ButtonRequirement = .primary
    public static let doubleTapRequiredButton: ButtonRequirement = .primary

    // MARK: Hover + system pointer (US1-3, US1-4)

    /// Hover must not move the remote cursor from Apple Pencil hover.
    public static let excludesPencilHover = true
    /// `UITouch.TouchType.indirectPointer` (not pencil = 2, not direct = 0).
    public static let indirectPointerTouchTypeRawValue = 3
    public static let hidesSystemPointerOverSessionView = true
}
