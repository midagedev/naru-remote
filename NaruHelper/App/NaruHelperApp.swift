import AppKit
import SwiftUI

/// The helper's shipping surface (spec 041 FR-001): a menu bar item with
/// no Dock icon (`LSUIElement`), one window for pairing, and everything
/// else observable from the menu.
@main
struct NaruHelperApp: App {
    /// The model lives on the delegate so the single-instance check and
    /// the DEBUG UI-test surfaces can reach the same instance the scenes
    /// render — one process, one runtime, one store.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Naru Helper", systemImage: "qrcode") {
            HelperMenu(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)

        Window("Pair with iPhone", id: "pairing") {
            PairingWindow(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 480)
    }
}

/// Single-instance handoff (spec 041 FR-008): a second launch activates
/// the running instance and exits instead of starting duplicate listeners
/// that would fight for ports 5974/5975.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = HelperAppModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // `runningApplications(withBundleIdentifier:)` is not documented
        // to exclude the caller, and the safe reading of both behaviors
        // is the same: never match this process.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.naruremote.helper")
            .filter { $0.processIdentifier != ownPID }
        guard let running = others.first else { return }
        running.activate()
        exit(0)
    }

    #if DEBUG
    func applicationDidFinishLaunching(_ notification: Notification) {
        HelperUITestSurface.presentFixtures(model: model)
    }
    #endif
}

#if DEBUG
/// UI-test window surfaces (spec 041 T-B5). SwiftUI's `openWindow` action
/// is only reachable from a live view, and a menu-bar app has no window
/// content alive at launch, so the fixture windows are plain `NSWindow`s
/// hosting the *same* SwiftUI views the shipping surfaces render. Shown
/// only when the `--ui-test` fixture set is present — never in a normal
/// launch, never in a Release build (the whole type is DEBUG-only).
@MainActor
enum HelperUITestSurface {
    private static var retainedWindows: [NSWindow] = []

    static func presentFixtures(model: HelperAppModel) {
        guard let fixtures = model.uiTestFixtures else { return }
        if fixtures.openPairing {
            let window = fixtureWindow(title: "Pair with iPhone")
            window.contentView = NSHostingView(rootView: PairingWindow(model: model))
            window.setContentSize(NSSize(width: 720, height: 500))
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        if fixtures.openMenuPreview {
            let window = fixtureWindow(title: "Menu Preview")
            window.contentView = NSHostingView(
                rootView: HelperMenu(model: model)
                    .frame(width: 280)
                    .padding(12)
            )
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func fixtureWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        retainedWindows.append(window)
        return window
    }
}
#endif
