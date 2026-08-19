import XCTest
@testable import NaruRemoteApp

/// Every text/background pairing the app makes out of brand tokens, measured
/// against WCAG AA in **both** appearances.
///
/// Why this exists: the Remote Input Dock floats over the remote screen, and it
/// used to take its background from `.ultraThinMaterial` — so the contrast of
/// "Ready to compose locally" was decided by whatever pixels the remote Mac
/// happened to be showing. Over a dark desktop in light appearance the material
/// resolved to a mid-gray under dark `.secondary` text and landed near 2:1
/// (found 2026-08-19 while shooting the light store captures). A material
/// cannot be gated; a token can. So dock chrome now paints an opaque token and
/// this test holds the ratios.
///
/// Each pairing cites where the app makes it. Adding a new token pairing to a
/// view means adding a row here — that is the point.
final class NaruColorContrastTests: XCTestCase {

    /// WCAG 2.1 AA for body text. The dock's status lines are `.caption`/
    /// `.caption2`, which is *not* large text, so the 3:1 large-text allowance
    /// does not apply to them.
    private let minimumBodyRatio = 4.5

    private struct Pairing {
        let text: NaruPaletteToken
        let background: NaruPaletteToken
        /// Where the app draws this text on this background.
        let site: String
    }

    private var bodyTextPairings: [Pairing] {
        [
            // The defect this test was written for.
            Pairing(
                text: NaruPalette.mutedInk,
                background: NaruPalette.dock,
                site: "RemoteInputDockView statusBlock / compactStatusLine / liveStatusLine; NaruRemoteAppShell RemoteInputDockStatusLine"
            ),
            Pairing(
                text: NaruPalette.ink,
                background: NaruPalette.dock,
                site: "RemoteInputDockView header title"
            ),
            Pairing(
                text: NaruPalette.mutedInk,
                background: NaruPalette.surfaceMuted,
                site: "RemoteInputDockView liveDisclosureBadge"
            ),
            Pairing(
                text: NaruPalette.mutedInk,
                background: NaruPalette.surface,
                site: "ConnectionGridView card secondary lines; SessionDiagnosticCornerView neutral tone"
            ),
            Pairing(
                text: NaruPalette.ink,
                background: NaruPalette.surface,
                site: "connection cards, diagnostics rows"
            ),
            Pairing(
                text: NaruPalette.mutedInk,
                background: NaruPalette.canvas,
                site: "empty-home and list secondary copy"
            ),
            Pairing(
                text: NaruPalette.ink,
                background: NaruPalette.canvas,
                site: "primary copy on the app canvas"
            ),
            Pairing(
                text: NaruPalette.ink,
                background: NaruPalette.surfaceEditor,
                site: "Compose editor text"
            ),
            Pairing(
                text: NaruPalette.ink,
                background: NaruPalette.surfaceKey,
                site: "accessory strip key caps"
            ),
            Pairing(
                text: NaruPalette.ink,
                background: NaruPalette.surfaceKeyAlt,
                site: "accessory strip modifier caps"
            )
        ]
    }

    func testEveryTokenTextPairingClearsWCAGAAInBothAppearances() {
        for pairing in bodyTextPairings {
            let ratio = pairing.text.contrast(against: pairing.background)
            XCTAssertGreaterThanOrEqual(
                ratio.light,
                minimumBodyRatio,
                """
                \(pairing.text.name) \(pairing.text.light.hex) on \(pairing.background.name) \
                \(pairing.background.light.hex) is \(String(format: "%.2f", ratio.light)):1 in light \
                appearance (need \(minimumBodyRatio):1) — \(pairing.site)
                """
            )
            XCTAssertGreaterThanOrEqual(
                ratio.dark,
                minimumBodyRatio,
                """
                \(pairing.text.name) \(pairing.text.dark.hex) on \(pairing.background.name) \
                \(pairing.background.dark.hex) is \(String(format: "%.2f", ratio.dark)):1 in dark \
                appearance (need \(minimumBodyRatio):1) — \(pairing.site)
                """
            )
        }
    }

    /// Status colors carry meaning, so they are read as text too.
    func testStatusTokensAreLegibleOnTheSurfacesTheyAppearOn() {
        let statusPairings = [
            Pairing(text: NaruPalette.reachable, background: NaruPalette.surface, site: "reachable status"),
            Pairing(text: NaruPalette.warning, background: NaruPalette.surface, site: "degraded status"),
            Pairing(text: NaruPalette.coral, background: NaruPalette.surface, site: "failure status"),
            Pairing(text: NaruPalette.signalBlue, background: NaruPalette.surface, site: "primary action label"),
            // Spec 016 FR-002: the host-card status dot and tag icons sit on
            // the Surface Muted capsule; the hue is the non-text carrier.
            Pairing(text: NaruPalette.reachable, background: NaruPalette.surfaceMuted, site: "grid status dot"),
            Pairing(text: NaruPalette.warning, background: NaruPalette.surfaceMuted, site: "grid status dot"),
            Pairing(text: NaruPalette.coral, background: NaruPalette.surfaceMuted, site: "grid status dot / public tag icon")
        ]

        for pairing in statusPairings {
            let ratio = pairing.text.contrast(against: pairing.background)
            XCTAssertGreaterThanOrEqual(
                ratio.light,
                3.0,
                "\(pairing.text.name) on \(pairing.background.name) is \(String(format: "%.2f", ratio.light)):1 in light — \(pairing.site)"
            )
            XCTAssertGreaterThanOrEqual(
                ratio.dark,
                3.0,
                "\(pairing.text.name) on \(pairing.background.name) is \(String(format: "%.2f", ratio.dark)):1 in dark — \(pairing.site)"
            )
        }
    }

    /// The hairline has to be visible, not legible — a lower bar, but a real
    /// one: it is the only thing separating the dock from the remote screen.
    func testHairlineIsVisibleAgainstTheSurfacesItDivides() {
        for background in [NaruPalette.dock, NaruPalette.surface, NaruPalette.canvas] {
            let ratio = NaruPalette.hairline.contrast(against: background)
            XCTAssertGreaterThanOrEqual(ratio.light, 1.15, "Hairline vanishes on \(background.name) in light")
            XCTAssertGreaterThanOrEqual(ratio.dark, 1.15, "Hairline vanishes on \(background.name) in dark")
        }
    }

    // MARK: - The measurement itself

    func testContrastRatioMatchesKnownValues() {
        let black = NaruPaletteColor(0, 0, 0)
        let white = NaruPaletteColor(255, 255, 255)
        XCTAssertEqual(NaruPaletteColor.contrastRatio(black, white), 21, accuracy: 0.01)
        XCTAssertEqual(NaruPaletteColor.contrastRatio(white, white), 1, accuracy: 0.0001)
        // WCAG's own worked example: #777777 on white is 4.48:1 — just under AA,
        // which also pins the direction of the rounding.
        XCTAssertEqual(
            NaruPaletteColor.contrastRatio(NaruPaletteColor(0x77, 0x77, 0x77), white),
            4.48,
            accuracy: 0.01
        )
    }
}
