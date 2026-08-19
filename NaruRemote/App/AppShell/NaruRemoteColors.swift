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
/// The hex pairs themselves live in `NaruPalette`, once each, so that
/// both appearances can be measured by a plain unit test
/// (`NaruColorContrastTests`) — a `Color` resolves only against a trait
/// environment and cannot be inspected off-device.
public enum NaruColors {
    /// `Canvas` token — primary detail-column background.
    public static let canvas: Color = adaptive(NaruPalette.canvas)

    /// `Surface Raised` token — dock / toolbar background.
    public static let dock: Color = adaptive(NaruPalette.dock)

    /// `Hairline` token — divider color.
    public static let hairline: Color = adaptive(NaruPalette.hairline)

    /// `Surface` token — card and panel fill for app chrome that
    /// sits directly on `canvas`.  Used by the connection grid and
    /// diagnostics summary so those surfaces do not bake a light-only
    /// paper color into dark appearance.
    public static let surface: Color = adaptive(NaruPalette.surface)

    /// `Surface Muted` token — low-contrast preview placeholders and
    /// secondary panels.  Slightly below `surface` in light mode and
    /// above `surface` in dark mode so empty preview wells remain
    /// visible without becoming the loudest element on screen.
    public static let surfaceMuted: Color = adaptive(NaruPalette.surfaceMuted)

    /// `Signal Blue` token — primary action + selected state
    /// (BRANDING.md §7). This is the app's accent: the tint resolved by
    /// the iOSApp `AccentColor` asset uses the same hex pair, so SwiftUI
    /// `.borderedProminent` buttons and the SwiftPM-module surfaces below
    /// read as one identity. Blue is reserved for "you can press this";
    /// status uses `reachable`/`warning`/`coral`, never the accent.
    public static let signalBlue: Color = adaptive(NaruPalette.signalBlue)

    /// Subtle selected-card outline. The "selected" cue maps to the
    /// Signal Blue accent (BRANDING.md §7: blue = primary action +
    /// selected), so a chosen connection card rings in the same accent
    /// the rest of the app presses.
    public static let focusRing: Color = signalBlue

    /// `Ink` token — primary text on app chrome (BRANDING.md §7). Most
    /// views can stay on `.primary`; this exists for brand surfaces that
    /// want the exact ink rather than the system label color.
    public static let ink: Color = adaptive(NaruPalette.ink)

    /// `Muted Ink` token — secondary text (BRANDING.md §7).
    public static let mutedInk: Color = adaptive(NaruPalette.mutedInk)

    /// `Surface Key` — primary fill for letter / number tiles on the
    /// Direct-mode soft keyboard.  Used to be hardcoded `Color.white`
    /// in `DirectKeystrokeKeyboardView.backgroundFor(role:)`, which
    /// rendered as white-on-white in dark mode (`Color.primary` text
    /// resolves to white) — UX punch-list #301.  Maps to the
    /// BRANDING.md §7 `Surface` token so the tile fill reads as the
    /// raised paper-on-canvas surface in light mode and a slate panel
    /// in dark.
    public static let surfaceKey: Color = adaptive(NaruPalette.surfaceKey)

    /// `Surface Key Alt` — secondary fill for wide / spacebar /
    /// modifier / page-toggle tiles on the Direct-mode soft keyboard.
    /// Slightly darker than `surfaceKey` so the row reads as a
    /// two-tier keyboard (alphas ↑ vs. system keys ↓), matching the
    /// iOS keyboard idiom without baking white into the swatch.
    /// Dark: `#2C313B` (between Dark Surface and Dark Surface Raised)
    public static let surfaceKeyAlt: Color = adaptive(NaruPalette.surfaceKeyAlt)

    /// `Surface Editor` — fill for the Compose `TextEditor` inside
    /// the Remote Input Dock.  Used to be hardcoded
    /// `Color.white.opacity(0.74)`, which read as a stark bright
    /// rectangle on the dark canvas (UX punch-list #302).  Same hex
    /// pair as `surfaceKey` (BRANDING.md §7 `Surface`) — the editor
    /// is conceptually a sheet of paper sitting on the dock surface.
    public static let surfaceEditor: Color = adaptive(NaruPalette.surfaceEditor)

    /// `Coral` token — error / blocked / advanced-public-endpoint
    /// warning color (BRANDING.md §7).  Used by the sidebar's
    /// public-IP profile cue per UX punch-list #006 and constitution
    /// §II ("public VNC is an advanced/manual path with explicit
    /// warnings").
    public static let coral: Color = adaptive(NaruPalette.coral)

    /// Reachable/healthy status fill tuned for legibility on both
    /// light card surfaces and dark preview placeholders.
    public static let reachable: Color = adaptive(NaruPalette.reachable)

    /// Warning/degraded status fill.  More brown than system yellow in
    /// light mode so it stays readable on white cards, brighter amber
    /// in dark mode so it does not flatten into the dark surface.
    public static let warning: Color = adaptive(NaruPalette.warning)

    // MARK: - Helpers

    #if canImport(UIKit)
    private static func adaptive(_ token: NaruPaletteToken) -> Color {
        let light = uiColor(token.light)
        let dark = uiColor(token.dark)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func uiColor(_ color: NaruPaletteColor) -> UIColor {
        UIColor(
            red: CGFloat(color.red) / 255.0,
            green: CGFloat(color.green) / 255.0,
            blue: CGFloat(color.blue) / 255.0,
            alpha: 1.0
        )
    }
    #else
    // On non-UIKit platforms (e.g. macOS unit-test runs of
    // NaruRemoteApp) fall back to the light hex.  Production paths
    // are always iOS / UIKit.
    private static func adaptive(_ token: NaruPaletteToken) -> Color {
        Color(
            red: Double(token.light.red) / 255.0,
            green: Double(token.light.green) / 255.0,
            blue: Double(token.light.blue) / 255.0
        )
    }
    #endif
}
