import Foundation

/// The brand palette as plain numbers, independent of SwiftUI.
///
/// `NaruColors` turns these into `Color`s; this type exists so the palette can
/// be *measured*. A `Color` built from `UIColor(dynamicProvider:)` only resolves
/// against a trait environment, and on a `swift test` run there is none — the
/// dark half of every token is unreachable and no test can say what contrast the
/// app actually ships. Keeping the hex pairs as data makes both appearances
/// checkable in a plain unit test (`NaruColorContrastTests`), which is what
/// stopped a 2:1 dock from shipping (2026-08-19).
public struct NaruPaletteColor: Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(_ red: Int, _ green: Int, _ blue: Int) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// WCAG 2.1 relative luminance.
    public var relativeLuminance: Double {
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255.0
            return value <= 0.03928
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.1 contrast ratio, 1…21.
    public static func contrastRatio(_ first: NaruPaletteColor, _ second: NaruPaletteColor) -> Double {
        let a = first.relativeLuminance
        let b = second.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// One brand token: the same role in both appearances.
public struct NaruPaletteToken: Equatable, Sendable {
    public let name: String
    public let light: NaruPaletteColor
    public let dark: NaruPaletteColor

    public init(_ name: String, light: NaruPaletteColor, dark: NaruPaletteColor) {
        self.name = name
        self.light = light
        self.dark = dark
    }

    /// Contrast against another token, per appearance.
    public func contrast(against background: NaruPaletteToken) -> (light: Double, dark: Double) {
        (
            NaruPaletteColor.contrastRatio(light, background.light),
            NaruPaletteColor.contrastRatio(dark, background.dark)
        )
    }
}

/// `BRANDING.md` §7 tokens. `NaruColors` is the SwiftUI face of this table;
/// every hex lives here exactly once.
public enum NaruPalette: Sendable {
    public static let canvas = NaruPaletteToken(
        "Canvas",
        light: NaruPaletteColor(0xF7, 0xF8, 0xF5),
        dark: NaruPaletteColor(0x11, 0x13, 0x18)
    )

    public static let dock = NaruPaletteToken(
        "Surface Raised",
        light: NaruPaletteColor(0xEE, 0xF1, 0xF4),
        dark: NaruPaletteColor(0x24, 0x2A, 0x33)
    )

    public static let hairline = NaruPaletteToken(
        "Hairline",
        light: NaruPaletteColor(0xD9, 0xDE, 0xE5),
        dark: NaruPaletteColor(0x30, 0x38, 0x45)
    )

    public static let surface = NaruPaletteToken(
        "Surface",
        light: NaruPaletteColor(0xFF, 0xFF, 0xFF),
        dark: NaruPaletteColor(0x1A, 0x1E, 0x25)
    )

    public static let surfaceMuted = NaruPaletteToken(
        "Surface Muted",
        light: NaruPaletteColor(0xEC, 0xEF, 0xF2),
        dark: NaruPaletteColor(0x22, 0x28, 0x32)
    )

    public static let signalBlue = NaruPaletteToken(
        "Signal Blue",
        light: NaruPaletteColor(0x2D, 0x7D, 0xFF),
        dark: NaruPaletteColor(0x5B, 0x9B, 0xFF)
    )

    public static let ink = NaruPaletteToken(
        "Ink",
        light: NaruPaletteColor(0x17, 0x1A, 0x1F),
        dark: NaruPaletteColor(0xF3, 0xF5, 0xF7)
    )

    /// `Muted Ink` — secondary text.
    ///
    /// The light value was darkened from `#68707D` to `#5F6773` on 2026-08-19:
    /// measured against the surfaces it is actually read on, the old value was
    /// 4.41:1 on `Surface Raised` and 4.33:1 on `Surface Muted` — both just
    /// under the 4.5:1 WCAG AA floor, and `Surface Raised` is the dock, where
    /// this token appears most. The new value measures 5.04:1 and 4.95:1.
    /// `NaruColorContrastTests` holds that line for every pairing the app makes.
    /// `BRANDING.md` §7 carries the same value.
    public static let mutedInk = NaruPaletteToken(
        "Muted Ink",
        light: NaruPaletteColor(0x5F, 0x67, 0x73),
        dark: NaruPaletteColor(0x9A, 0xA3, 0xAF)
    )

    public static let surfaceKey = NaruPaletteToken(
        "Surface Key",
        light: NaruPaletteColor(0xFF, 0xFF, 0xFF),
        dark: NaruPaletteColor(0x1A, 0x1E, 0x25)
    )

    public static let surfaceKeyAlt = NaruPaletteToken(
        "Surface Key Alt",
        light: NaruPaletteColor(0xEA, 0xED, 0xF0),
        dark: NaruPaletteColor(0x2C, 0x31, 0x3B)
    )

    public static let surfaceEditor = NaruPaletteToken(
        "Surface Editor",
        light: NaruPaletteColor(0xFF, 0xFF, 0xFF),
        dark: NaruPaletteColor(0x1A, 0x1E, 0x25)
    )

    public static let coral = NaruPaletteToken(
        "Coral",
        light: NaruPaletteColor(0xE8, 0x5D, 0x4F),
        dark: NaruPaletteColor(0xFF, 0x75, 0x6B)
    )

    public static let reachable = NaruPaletteToken(
        "Reachable",
        light: NaruPaletteColor(0x13, 0x8A, 0x5B),
        dark: NaruPaletteColor(0x4E, 0xDC, 0x91)
    )

    public static let warning = NaruPaletteToken(
        "Warning",
        light: NaruPaletteColor(0xA0, 0x5D, 0x00),
        dark: NaruPaletteColor(0xFF, 0xB8, 0x4D)
    )
}
