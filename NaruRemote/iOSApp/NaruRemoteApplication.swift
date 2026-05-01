import NaruRemoteApp
import NaruRemoteCore
import SwiftUI

@main
struct NaruRemoteApplication: App {
    @StateObject private var model = Self.makeModel()

    var body: some Scene {
        WindowGroup {
            NaruRemoteAppShell(model: model, buildVersion: Self.bundleBuildVersion())
                .accessibilityIdentifier("naru.app.shell")
        }
    }

    /// Reads `CFBundleShortVersionString` so the diagnostic share
    /// sheet header carries the marketing build label.  Returns
    /// `nil` if the key is missing or the value is not a string;
    /// `DiagnosticExport.renderShareText` renders that as `n/a`.
    private static func bundleBuildVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static func makeModel() -> NaruRemoteAppModel {
        let settingsPersistence = FileAppSettingsPersistence(fileURL: settingsStoreURL())
        // The profile store is now an `actor`; its initializer is
        // `async` so we cannot construct it from this synchronous
        // `@StateObject` factory.  Build a fresh model here without a
        // store, then attach it on first appear via the `.task`
        // modifier in `NaruRemoteAppShell` which calls
        // `loadStoredProfiles()` to merge disk-backed profiles in.
        let credentialStore = KeychainConnectionCredentialStore()
        let model = NaruRemoteAppModel(
            credentialStore: credentialStore,
            settingsPersistence: settingsPersistence,
            pipWatchController: PiPWatchPictureInPictureController(),
            localClipboardWriter: UIPasteboardClipboardWriter()
        )
        Task { @MainActor in
            do {
                let persistence = FileConnectionProfilePersistence(fileURL: profileStoreURL())
                let store = try await ConnectionProfileStore(persistence: persistence)
                await model.attachProfileStore(store)
            } catch {
                // Profile store could not be opened — the model still
                // works as an in-memory profile editor for this
                // launch.  The next launch will retry.
            }

            applyTestStickyModifierOverrides(to: model)
        }
        return model
    }

    /// XCUITest screenshot hook — `swift test` is fast enough to
    /// exercise the 400 ms double-tap lock window directly, but
    /// XCUITest taps land ~600 ms apart so the locked-state
    /// screenshot path can't reach `.locked` through real taps.
    /// Honour the `NARU_TEST_PRELOCK_MODIFIERS` launch environment
    /// variable so the screenshot harness can land on the locked
    /// visual deterministically.  The variable is a comma-list of
    /// `StickyModifierState.Modifier` raw values
    /// (e.g. `"control"` or `"control,shift"`).  No-op in production
    /// because the variable is never set.
    @MainActor
    private static func applyTestStickyModifierOverrides(to model: NaruRemoteAppModel) {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_PRELOCK_MODIFIERS"],
              !raw.isEmpty
        else {
            return
        }

        // Open Direct mode so the special-keys page is reachable
        // when the test takes the screenshot.
        if !model.directKeystrokeMode.isActive {
            model.toggleDirectKeystrokeMode()
        }

        let names = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for name in names {
            guard let modifier = StickyModifierState.Modifier(rawValue: name) else { continue }
            // Back-to-back taps in the same `Task` land < 400 ms
            // apart (same `@MainActor` continuation), which is the
            // double-tap window — idle → armed → locked.  Bypasses
            // the XCUITest tap-cadence gap (~600 ms between real
            // taps).
            Task { @MainActor in
                await model.tapDirectKey(.modifier(modifier))
                await model.tapDirectKey(.modifier(modifier))
            }
        }
    }

    private static func profileStoreURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["NARU_PROFILE_STORE_URL"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }

        return applicationSupportURL().appendingPathComponent("profiles.json")
    }

    private static func settingsStoreURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["NARU_SETTINGS_STORE_URL"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }

        return applicationSupportURL().appendingPathComponent("settings.json")
    }

    private static func applicationSupportURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseURL.appendingPathComponent("NaruRemote", isDirectory: true)
    }
}
