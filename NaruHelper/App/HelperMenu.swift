import AppKit
import NaruHelperKit
import SwiftUI

/// The menu bar menu (spec 041 FR-001/T-B4), in contract order: status,
/// the two permission lines, **Pair with iPhone…**, **Start at login**,
/// **Revoke pairing…**, **Copy Diagnostics**, version, **Quit**.
struct HelperMenu: View {
    @ObservedObject var model: HelperAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text(model.pairingStatus.menuLabel)
                .disabled(true)
            Text("Accessibility: \(model.accessibility.rowLabel)")
                .disabled(true)
            Text("Screen Recording: \(model.screenRecording.rowLabel)")
                .disabled(true)
            Divider()
            Button("Pair with iPhone…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "pairing")
            }
            startAtLogin
            Button("Revoke pairing…") { model.confirmRevokePairing() }
                .disabled(model.pairingStatus == .notPaired)
            Button("Copy Diagnostics") { model.copyDiagnostics() }
            Divider()
            Text("Naru Helper \(model.versionText)")
                .disabled(true)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear { model.noteMenuOpened() }
    }

    /// The toggle shows the system-reported truth (`.on` **or**
    /// `.requiresApproval` read as on — registration was requested); the
    /// label names the approval state so the user knows where to go, and
    /// the route there is offered the moment the system asks for it
    /// (``HelperAppModel/setLoginItemEnabled(_:)``).
    private var startAtLogin: some View {
        Toggle(isOn: Binding(
            get: {
                model.loginItemState == .on || model.loginItemState == .requiresApproval
            },
            set: { model.setLoginItemEnabled($0) }
        )) {
            Text(
                model.loginItemState == .requiresApproval
                    ? "Start at login (needs approval in System Settings)"
                    : "Start at login")
        }
    }
}

// MARK: - Fixed-catalog display labels

extension NaruHelperPairingStatus {
    var menuLabel: String {
        switch self {
        case .notPaired: "Not paired"
        case .paired: "Paired"
        case .connected: "Connected"
        }
    }
}

extension NaruHelperPermissionStatus {
    var rowLabel: String {
        self == .granted ? "Granted" : "Missing"
    }
}

extension NaruHelperListenerState {
    /// The fixed catalog of spec 041 FR-002 — `Listening`, `Port in use`,
    /// `Stopped` — plus the Kit's remaining lifecycle values.
    var rowLabel: String {
        switch self {
        case .starting: "Starting"
        case .listening: "Listening"
        case .portInUse: "Port in use"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }
}
