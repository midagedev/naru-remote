import Foundation

/// Mac-aware session controls that can be driven through the existing
/// VNC `KeyEvent` path. These are not private Apple Remote Desktop
/// administrator commands; they are documented macOS keyboard
/// shortcuts expressed as X11 keysyms plus the modifier envelope used
/// by `KeystrokeEmitter`.
public enum MacSessionControl: String, Sendable, Equatable, Codable, CaseIterable {
    case missionControl
    case appWindows
    case switchApplication
    case showDesktop
    case spaceLeft
    case spaceRight

    public var label: String {
        switch self {
        case .missionControl:
            "Mission"
        case .appWindows:
            "App Windows"
        case .switchApplication:
            "Switch App"
        case .showDesktop:
            "Desktop"
        case .spaceLeft:
            "Space Left"
        case .spaceRight:
            "Space Right"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .missionControl:
            "Open Mission Control"
        case .appWindows:
            "Show windows for the front app"
        case .switchApplication:
            "Switch to the previous app"
        case .showDesktop:
            "Show desktop"
        case .spaceLeft:
            "Move to the space on the left"
        case .spaceRight:
            "Move to the space on the right"
        }
    }

    public var systemImageName: String {
        switch self {
        case .missionControl:
            "rectangle.3.group"
        case .appWindows:
            "macwindow.on.rectangle"
        case .switchApplication:
            "arrow.triangle.2.circlepath"
        case .showDesktop:
            "rectangle.dashed"
        case .spaceLeft:
            "chevron.left.2"
        case .spaceRight:
            "chevron.right.2"
        }
    }

    /// The X11 keysym and modifier set to emit. The remote Mac may
    /// customize these shortcuts in Keyboard settings; this catalog
    /// intentionally models Apple's defaults only.
    public var emission: (keysym: UInt32, modifiers: Set<DirectKeystrokeModifier>) {
        switch self {
        case .missionControl:
            return (KeysymMapping.keysym(for: .up), [.control])
        case .appWindows:
            return (KeysymMapping.keysym(for: .down), [.control])
        case .switchApplication:
            return (KeysymMapping.keysym(for: .tab), [.meta])
        case .showDesktop:
            return (KeysymMapping.keysym(for: .f11), [])
        case .spaceLeft:
            return (KeysymMapping.keysym(for: .left), [.control])
        case .spaceRight:
            return (KeysymMapping.keysym(for: .right), [.control])
        }
    }
}
