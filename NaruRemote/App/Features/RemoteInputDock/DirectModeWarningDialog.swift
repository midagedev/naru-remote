import SwiftUI
import NaruRemoteCore

/// One-time-per-session warning dialog presented the first time the
/// user enters Direct keystroke mode (FR-009).  Renders as a SwiftUI
/// `confirmationDialog` attached to whichever ancestor mounts the
/// modifier — typically `RemoteInputDockView` so the warning sits
/// over the dock chrome rather than the framebuffer.
///
/// Triggered when both:
///
/// - `directKeystrokeMode.isActive == true`
/// - `directKeystrokeMode.hasShownEntryWarningThisSession == false`
///
/// Confirm action calls back into the app model via the supplied
/// `onDismiss` closure, which production wires to
/// `model.dismissDirectModeEntryWarning()`.  The model flips the
/// `hasShownEntryWarningThisSession` flag to `true`, so the dialog
/// will not reappear within the same session.  The flag resets in
/// lockstep with the rest of `DirectKeystrokeMode` (disconnect, fresh
/// connect, profile change — see `NaruRemoteAppModel`).
///
/// No cancel button: the user already opted in by tapping the
/// "Direct" segment.  This dialog is informational, surfacing the
/// IME caveat the constitution requires us to disclose.
///
/// Wording matches the dock's existing English idiom (the rest of
/// the dock UI is English — `"Compose"`, `"Direct"`, `"Send"`,
/// etc.).  The mention of Compose & Send mode steers users back to
/// the multilingual default, which is the constitution's §I rule.
struct DirectModeWarningDialog: ViewModifier {

    let directKeystrokeMode: DirectKeystrokeMode
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Direct keystroke mode",
            isPresented: Binding<Bool>(
                get: {
                    directKeystrokeMode.isActive
                        && !directKeystrokeMode.hasShownEntryWarningThisSession
                },
                set: { newValue in
                    if newValue == false {
                        // Dialog dismissed (any path) — flip the flag
                        // so it does not reappear this session.
                        onDismiss()
                    }
                }
            ),
            titleVisibility: .visible,
            actions: {
                Button("Got it") {
                    onDismiss()
                }
                .accessibilityIdentifier("naru.direct.warning.confirm")
            },
            message: {
                Text(
                    "Keystrokes go straight to the remote computer. "
                    + "IME input (Korean, Chinese, Japanese, emoji) will not work in this mode. "
                    + "Switch back to Compose & Send for multilingual text."
                )
            }
        )
    }
}

extension View {
    /// Convenience modifier so call-sites read like:
    ///
    /// ```swift
    /// dock.directModeEntryWarning(
    ///     mode: snapshot.directKeystrokeMode,
    ///     onDismiss: { model.dismissDirectModeEntryWarning() }
    /// )
    /// ```
    ///
    /// Keeps the warning's view-modifier nature local rather than
    /// asking every call-site to remember the `.modifier(...)`
    /// wrapper.
    func directModeEntryWarning(
        mode: DirectKeystrokeMode,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(DirectModeWarningDialog(
            directKeystrokeMode: mode,
            onDismiss: onDismiss
        ))
    }
}
