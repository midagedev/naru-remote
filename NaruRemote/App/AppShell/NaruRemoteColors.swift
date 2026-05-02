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
