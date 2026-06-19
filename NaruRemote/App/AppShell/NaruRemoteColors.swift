import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Adaptive surface tokens derived from `BRANDING.md` §7.  Lives in
/// the `NaruRemoteApp` SwiftPM target so SwiftUI views in that module
/// can reference them without crossing into the iOSApp Asset Catalog
/// (which is not visible across the SwiftPM module boundary).  Each
/// color is built with `UIColor(dynamicProvider:)` so the system
/// resolves it per `userInterfaceStyle` at draw time — `.dark`
/// traits get the dark hex, otherwise the light hex.
///
/// Hex values are kept inline as comments next to each branch so a
/// reviewer can verify the BRANDING.md token mapping without leaving
/// the file.
public enum NaruColors {
    /// `Canvas` token — primary detail-column background.
    /// Light: `#F7F8F5`  Dark: `#111318`
    public static let canvas: Color = adaptive(
        light: rgb(0xF7, 0xF8, 0xF5),
        dark: rgb(0x11, 0x13, 0x18)
    )

    /// `Surface Raised` token — dock / toolbar background.
    /// Light: `#EEF1F4`  Dark: `#242A33`
    public static let dock: Color = adaptive(
        light: rgb(0xEE, 0xF1, 0xF4),
        dark: rgb(0x24, 0x2A, 0x33)
    )

    /// `Hairline` token — divider color.
    /// Light: `#D9DEE5`  Dark: `#303845`
    public static let hairline: Color = adaptive(
        light: rgb(0xD9, 0xDE, 0xE5),
        dark: rgb(0x30, 0x38, 0x45)
    )

    /// `Surface` token — card and panel fill for app chrome that
    /// sits directly on `canvas`.  Used by the connection grid and
    /// diagnostics summary so those surfaces do not bake a light-only
    /// paper color into dark appearance.
    /// Light: `#FFFFFF`  Dark: `#1A1E25`
    public static let surface: Color = adaptive(
        light: rgb(0xFF, 0xFF, 0xFF),
        dark: rgb(0x1A, 0x1E, 0x25)
    )

    /// `Surface Muted` token — low-contrast preview placeholders and
    /// secondary panels.  Slightly below `surface` in light mode and
    /// above `surface` in dark mode so empty preview wells remain
    /// visible without becoming the loudest element on screen.
    /// Light: `#ECEFF2`  Dark: `#222832`
    public static let surfaceMuted: Color = adaptive(
        light: rgb(0xEC, 0xEF, 0xF2),
        dark: rgb(0x22, 0x28, 0x32)
    )

    /// `Signal Blue` token — primary action + selected state
    /// (BRANDING.md §7). This is the app's accent: the tint resolved by
    /// the iOSApp `AccentColor` asset uses the same hex pair, so SwiftUI
    /// `.borderedProminent` buttons and the SwiftPM-module surfaces below
    /// read as one identity. Blue is reserved for "you can press this";
    /// status uses `reachable`/`warning`/`coral`, never the accent.
    /// Light: `#2D7DFF`  Dark: `#5B9BFF`
    public static let signalBlue: Color = adaptive(
        light: rgb(0x2D, 0x7D, 0xFF),
        dark: rgb(0x5B, 0x9B, 0xFF)
    )

    /// Subtle selected-card outline. The "selected" cue maps to the
    /// Signal Blue accent (BRANDING.md §7: blue = primary action +
    /// selected), so a chosen connection card rings in the same accent
    /// the rest of the app presses.
    /// Light: `#2D7DFF`  Dark: `#5B9BFF`
    public static let focusRing: Color = signalBlue

    /// `Ink` token — primary text on app chrome (BRANDING.md §7). Most
    /// views can stay on `.primary`; this exists for brand surfaces that
    /// want the exact ink rather than the system label color.
    /// Light: `#171A1F`  Dark: `#F3F5F7`
    public static let ink: Color = adaptive(
        light: rgb(0x17, 0x1A, 0x1F),
        dark: rgb(0xF3, 0xF5, 0xF7)
    )

    /// `Muted Ink` token — secondary text (BRANDING.md §7).
    /// Light: `#68707D`  Dark: `#9AA3AF`
    public static let mutedInk: Color = adaptive(
        light: rgb(0x68, 0x70, 0x7D),
        dark: rgb(0x9A, 0xA3, 0xAF)
    )

    /// `Surface Key` — primary fill for letter / number tiles on the
    /// Direct-mode soft keyboard.  Used to be hardcoded `Color.white`
    /// in `DirectKeystrokeKeyboardView.backgroundFor(role:)`, which
    /// rendered as white-on-white in dark mode (`Color.primary` text
    /// resolves to white) — UX punch-list #301.  Maps to the
    /// BRANDING.md §7 `Surface` token so the tile fill reads as the
    /// raised paper-on-canvas surface in light mode and a slate panel
    /// in dark.
    /// Light: `#FFFFFF`  Dark: `#1A1E25`
    public static let surfaceKey: Color = adaptive(
        light: rgb(0xFF, 0xFF, 0xFF),
        dark: rgb(0x1A, 0x1E, 0x25)
    )

    /// `Surface Key Alt` — secondary fill for wide / spacebar /
    /// modifier / page-toggle tiles on the Direct-mode soft keyboard.
    /// Slightly darker than `surfaceKey` so the row reads as a
    /// two-tier keyboard (alphas ↑ vs. system keys ↓), matching the
    /// iOS keyboard idiom without baking white into the swatch.
    /// Light: `#EAEDF0` (between Surface and Surface Raised)
    /// Dark: `#2C313B` (between Dark Surface and Dark Surface Raised)
    public static let surfaceKeyAlt: Color = adaptive(
        light: rgb(0xEA, 0xED, 0xF0),
        dark: rgb(0x2C, 0x31, 0x3B)
    )

    /// `Surface Editor` — fill for the Compose `TextEditor` inside
    /// the Remote Input Dock.  Used to be hardcoded
    /// `Color.white.opacity(0.74)`, which read as a stark bright
    /// rectangle on the dark canvas (UX punch-list #302).  Same hex
    /// pair as `surfaceKey` (BRANDING.md §7 `Surface`) — the editor
    /// is conceptually a sheet of paper sitting on the dock surface.
    /// Light: `#FFFFFF`  Dark: `#1A1E25`
    public static let surfaceEditor: Color = adaptive(
        light: rgb(0xFF, 0xFF, 0xFF),
        dark: rgb(0x1A, 0x1E, 0x25)
    )

    /// `Coral` token — error / blocked / advanced-public-endpoint
    /// warning color (BRANDING.md §7).  Used by the sidebar's
    /// public-IP profile cue per UX punch-list #006 and constitution
    /// §II ("public VNC is an advanced/manual path with explicit
    /// warnings").
    /// Light: `#E85D4F`  Dark: `#FF756B`
    public static let coral: Color = adaptive(
        light: rgb(0xE8, 0x5D, 0x4F),
        dark: rgb(0xFF, 0x75, 0x6B)
    )

    /// Reachable/healthy status fill tuned for legibility on both
    /// light card surfaces and dark preview placeholders.
    /// Light: `#138A5B`  Dark: `#4EDC91`
    public static let reachable: Color = adaptive(
        light: rgb(0x13, 0x8A, 0x5B),
        dark: rgb(0x4E, 0xDC, 0x91)
    )

    /// Warning/degraded status fill.  More brown than system yellow in
    /// light mode so it stays readable on white cards, brighter amber
    /// in dark mode so it does not flatten into the dark surface.
    /// Light: `#A05D00`  Dark: `#FFB84D`
    public static let warning: Color = adaptive(
        light: rgb(0xA0, 0x5D, 0x00),
        dark: rgb(0xFF, 0xB8, 0x4D)
    )

    // MARK: - Helpers

    #if canImport(UIKit)
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: 1.0
        )
    }
    #else
    // On non-UIKit platforms (e.g. macOS unit-test runs of
    // NaruRemoteApp) fall back to the light hex.  Production paths
    // are always iOS / UIKit.
    private static func adaptive(light: Color, dark: Color) -> Color { light }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0
        )
    }
    #endif
}
