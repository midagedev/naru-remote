import Foundation
import NaruRemoteCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

/// The single place `isIdleTimerDisabled` is written (spec 039 FR-003).
///
/// `ScreenWakePolicy` decides; this applies. Splitting them is what makes the
/// decision testable under `swift test` — there is no `UIApplication` there —
/// and it is also what keeps the write in one place. An idle-timer flag raised
/// from several call sites is the classic leak: every site remembers to raise
/// it and one forgets to lower it, and the phone stops sleeping until it is
/// force-quit.
///
/// The applier is injected so a test can watch the flag without touching the
/// real device state.
@MainActor
public final class ScreenWakeCoordinator {
    /// Last value actually written, so a repeated resolution costs nothing.
    /// `UIApplication.isIdleTimerDisabled` is a main-thread property whose
    /// setter the system acts on; the shell re-resolves on every session and
    /// scene change, which is far more often than the answer changes.
    private var appliedHold: Bool?
    private let apply: (Bool) -> Void

    /// Most recent resolution, for the debug HUD and for tests. Fixed-catalog
    /// reason only — constitution §IV.
    public private(set) var lastResolution: ScreenWakeResolution?

    public init(apply: @escaping (Bool) -> Void) {
        self.apply = apply
    }

    /// Production wiring. On any platform without an iOS idle timer this is a
    /// coordinator that decides correctly and applies nothing, which keeps the
    /// `NaruRemoteApp` target building for macOS unit tests.
    public convenience init() {
        #if os(iOS) && canImport(UIKit)
        self.init { holdsAwake in
            UIApplication.shared.isIdleTimerDisabled = holdsAwake
        }
        #else
        self.init { _ in }
        #endif
    }

    public func update(with resolution: ScreenWakeResolution) {
        lastResolution = resolution
        guard appliedHold != resolution.holdsAwake else {
            return
        }
        appliedHold = resolution.holdsAwake
        apply(resolution.holdsAwake)
    }

    /// Drops the hold unconditionally. The app going away is the one case
    /// where re-resolving is the wrong move: whatever the session state says,
    /// a backgrounded app has no screen to keep on.
    public func release() {
        lastResolution = ScreenWakeResolution(
            decision: .allowSleep,
            reason: .appNotForeground
        )
        // Only give back a hold this coordinator actually took. `appliedHold`
        // is nil until the first write, and writing `false` from nil would
        // have this object clearing a global flag it never set — which is the
        // same overreach in the other direction.
        guard appliedHold == true else {
            return
        }
        appliedHold = false
        apply(false)
    }
}

/// Holds the screen awake for as long as the supplied resolution says to.
///
/// A modifier rather than three modifiers inline on the shell: the wake state
/// has to be re-applied on appear, on every change, and dropped on disappear,
/// and those three belong to one another. Attaching them separately is how a
/// view ends up raising the flag on appear and never lowering it.
public struct ScreenWakeHold: ViewModifier {
    private let resolution: ScreenWakeResolution
    @State private var coordinator = ScreenWakeCoordinator()

    public init(resolution: ScreenWakeResolution) {
        self.resolution = resolution
    }

    public func body(content: Content) -> some View {
        content
            .onAppear { coordinator.update(with: resolution) }
            .onChange(of: resolution) { _, updated in
                coordinator.update(with: updated)
            }
            .onDisappear { coordinator.release() }
    }
}

public extension View {
    func screenWakeHold(_ resolution: ScreenWakeResolution) -> some View {
        modifier(ScreenWakeHold(resolution: resolution))
    }
}
