import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Centralized haptic feedback for remote-input surfaces.
///
/// The remote screen echo can lag behind the wire (the VNC content-frame
/// produce rate is the ceiling — see `PERFORMANCE_PARITY_ANALYSIS.md`), so
/// "did my input register?" must be answered locally and instantly: the
/// press itself acknowledges on touch-down, independent of when the remote
/// frame catches up (founder feedback 2026-07-05).
///
/// Generators are kept alive and re-`prepare()`d after each impact so the
/// Taptic Engine stays warm during typing/click bursts. On the iOS
/// simulator haptic hardware is absent and these calls are no-ops, which
/// keeps XCUITest flows deterministic.
@MainActor
enum NaruHaptics {
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    private static let keyGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let clickGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    /// Direct-mode soft-keyboard key press — light tap on touch-down.
    static func keyPress() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        keyGenerator.impactOccurred(intensity: 0.65)
        keyGenerator.prepare()
        #endif
    }

    /// Pointer click dispatched to the remote (direct-touch tap or
    /// trackpad-mode click at the cursor).
    static func pointerClick() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        clickGenerator.impactOccurred(intensity: 0.75)
        clickGenerator.prepare()
        #endif
    }

    /// Secondary (right) click — a firmer, distinct sensation.
    static func rightClick() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        rigidGenerator.impactOccurred()
        rigidGenerator.prepare()
        #endif
    }

    /// Pointer button pressed and held (drag began).
    static func pointerDown() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        keyGenerator.impactOccurred(intensity: 0.5)
        keyGenerator.prepare()
        #endif
    }
}
