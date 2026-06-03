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
                .preferredColorScheme(Self.testOverrideColorScheme())
        }
    }

    /// XCUITest screenshot hook — when the
    /// `NARU_TEST_OVERRIDE_INTERFACE_STYLE` launch environment
    /// variable is set to `Light` or `Dark` (case-insensitive), force
    /// the root scene's color scheme to that value via
    /// `.preferredColorScheme`.  Returns `nil` when the variable is
    /// unset or unrecognised, which leaves SwiftUI to honour the
    /// device-level setting (production behaviour, zero runtime
    /// cost).  Closes UX punch-list #001 — the previously-used
    /// `-AppleInterfaceStyle Dark` launch argument is a macOS-only
    /// user-default key and is silently ignored on iOS.
    private static func testOverrideColorScheme() -> ColorScheme? {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_OVERRIDE_INTERFACE_STYLE"],
              !raw.isEmpty
        else { return nil }
        switch raw.lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
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
        let previewStore = FileProfilePreviewStore(directoryURL: previewStoreURL())
        // The profile store is now an `actor`; its initializer is
        // `async` so we cannot construct it from this synchronous
        // `@StateObject` factory.  Build a fresh model here without a
        // store, then attach it on first appear via the `.task`
        // modifier in `NaruRemoteAppShell` which calls
        // `loadStoredProfiles()` to merge disk-backed profiles in.
        let credentialStore = KeychainConnectionCredentialStore()

        // XCUITest fixture hook — when `NARU_TEST_FIXTURE_SNAPSHOT`
        // is set the model is seeded with a synthetic snapshot so
        // the audit harness can drive states the live persistence
        // path can't reach without a real RFB session.  Returns
        // `nil` (and `init(snapshot:)` defaults to the empty
        // snapshot) when the env var is unset — production behaviour,
        // zero runtime cost.
        let fixtureSnapshot = UXAuditFixtures.loadFixtureSnapshot()
            ?? UXAuditFixtures.loadSeedProfileSnapshot()
        let model: NaruRemoteAppModel
        if let fixtureSnapshot {
            model = NaruRemoteAppModel(
                snapshot: fixtureSnapshot,
                profilePreviewStore: previewStore,
                credentialStore: credentialStore,
                settingsPersistence: settingsPersistence,
                pipWatchController: PiPWatchPictureInPictureController(),
                localClipboardWriter: UIPasteboardClipboardWriter()
            )
        } else {
            model = NaruRemoteAppModel(
                profilePreviewStore: previewStore,
                credentialStore: credentialStore,
                settingsPersistence: settingsPersistence,
                pipWatchController: PiPWatchPictureInPictureController(),
                localClipboardWriter: UIPasteboardClipboardWriter()
            )
        }
        Task { @MainActor in
            // XCUITest E2E hook — pre-populate the keychain with a
            // known password BEFORE the profile store loads so the
            // model's `connectSelectedProfile` path can find a
            // credential without driving the editor UI.  No-op when
            // the env var is unset (production).  See
            // `LocalMacConnectE2EUITests`.
            await applyTestInjectKeychainPassword(into: credentialStore)

            if !testSkipsProfileStoreLoad() {
                do {
                    let persistence = FileConnectionProfilePersistence(fileURL: profileStoreURL())
                    let store = try await ConnectionProfileStore(persistence: persistence)
                    await model.attachProfileStore(store)
                } catch {
                    // Profile store could not be opened — the model still
                    // works as an in-memory profile editor for this
                    // launch.  The next launch will retry.
                }
            }
            await model.loadStoredProfilePreviews()

            applyTestStickyModifierOverrides(to: model)
            applyTestSuppressDirectModeWarning(to: model)
            // Apply post-init mutations (e.g. `pendingIncomingClipboard`)
            // for the fixture, if any.  No-op when the env var is
            // unset.
            UXAuditFixtures.applyFixturePostInitMutations(to: model)
        }
        return model
    }

    /// XCUITest hook — when the `NARU_TEST_SUPPRESS_DIRECT_WARNING`
    /// launch environment variable is set to a truthy value, mark
    /// the FR-009 first-entry warning as already dismissed so
    /// existing screenshot tests (PR-C / PR-D) can drive directly
    /// to the keyboard without seeing the new Phase 7 dialog.  No-op
    /// in production because the variable is never set.  The Phase 7
    /// screenshot tests deliberately leave it unset so they can
    /// capture the warning UI itself.
    @MainActor
    private static func applyTestSuppressDirectModeWarning(to model: NaruRemoteAppModel) {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_SUPPRESS_DIRECT_WARNING"],
              !raw.isEmpty,
              raw != "0",
              raw.lowercased() != "false"
        else { return }
        model.dismissDirectModeEntryWarning()
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

    /// XCUITest E2E hook — when `NARU_TEST_INJECT_KEYCHAIN_REF` and
    /// `NARU_TEST_INJECT_KEYCHAIN_PASSWORD` are both set, write the
    /// password into the supplied `KeychainConnectionCredentialStore`
    /// at the given credential reference before any profile flow
    /// runs.  Pair with a seeded profile whose `credentialRef`
    /// matches so `connectSelectedProfile` finds the credential
    /// without driving the editor UI.  No-op in production because
    /// the variables are never set.
    private static func applyTestInjectKeychainPassword(
        into store: KeychainConnectionCredentialStore
    ) async {
        let env = ProcessInfo.processInfo.environment
        guard let ref = env["NARU_TEST_INJECT_KEYCHAIN_REF"],
              !ref.isEmpty,
              let password = env["NARU_TEST_INJECT_KEYCHAIN_PASSWORD"],
              !password.isEmpty
        else { return }
        do {
            try await store.savePassword(password, for: ref)
        } catch {
            // Silently ignore — production never hits this branch and
            // a test failure will surface as "credential unavailable"
            // when Connect is tapped.
        }
    }

    /// XCUITest E2E hook — when a launch has seeded an in-memory
    /// profile from environment, tests can opt out of disk profile
    /// loading so a previous app install cannot replace that profile
    /// before Connect is tapped.  Production never sets the flag.
    private static func testSkipsProfileStoreLoad() -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_SKIP_PROFILE_STORE_LOAD"],
              !raw.isEmpty
        else { return false }
        return raw != "0" && raw.lowercased() != "false"
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

    private static func previewStoreURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["NARU_PREVIEW_STORE_URL"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }

        return applicationSupportURL().appendingPathComponent("profile-previews", isDirectory: true)
    }

    private static func applicationSupportURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseURL.appendingPathComponent("NaruRemote", isDirectory: true)
    }
}
