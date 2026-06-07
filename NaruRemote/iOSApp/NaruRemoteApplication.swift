import NaruRemoteApp
import NaruRemoteCore
import SwiftUI

@main
struct NaruRemoteApplication: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = Self.makeModel()
    @MainActor private static var framebufferFloodTask: Task<Void, Never>?
    @MainActor private static var modelPublishStormTask: Task<Void, Never>?
    @MainActor private static var helperVideoHealthStormTask: Task<Void, Never>?
    @MainActor private static var delayedFirstFrameTask: Task<Void, Never>?

    var body: some Scene {
        WindowGroup {
            NaruRemoteAppShell(
                model: model,
                buildVersion: Self.bundleBuildVersion(),
                startsOnSelectedProfileDetail: Self.testStartsOnSelectedProfileDetail()
            )
                .accessibilityIdentifier("naru.app.shell")
                .preferredColorScheme(Self.testOverrideColorScheme())
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase != .active else {
                        return
                    }
                    Self.cancelTestStormTasks()
                }
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

    /// XCUITest hook — production launches saved profiles into the
    /// connection grid, but focused input-dock tests need to start on the
    /// selected profile detail without tapping through the launcher.
    private static func testStartsOnSelectedProfileDetail() -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_START_PROFILE_DETAIL"],
              !raw.isEmpty
        else { return false }
        return raw != "0" && raw.lowercased() != "false"
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

            applyTestAppSettingsOverrides(to: model)
            applyTestStickyModifierOverrides(to: model)
            applyTestSuppressDirectModeWarning(to: model)
            // Apply post-init mutations (e.g. `pendingIncomingClipboard`)
            // for the fixture, if any.  No-op when the env var is
            // unset.
            UXAuditFixtures.applyFixturePostInitMutations(to: model)
            applyTestTrackpadCursorStorm(to: model)
            applyTestFramebufferFlood(to: model)
            applyTestModelPublishStorm(to: model)
            applyTestHelperVideoHealthStorm(to: model)
            applyTestDelayedFirstFrameAfterComposeFocus(to: model)
        }
        return model
    }

    /// XCUITest physical-gate hook — lets the test launch a specific
    /// non-secret stream candidate (power / encoding / startup preflight /
    /// startup glance scale) without tapping through the UI or persisting
    /// that candidate to disk.
    @MainActor
    private static func applyTestAppSettingsOverrides(to model: NaruRemoteAppModel) {
        let env = ProcessInfo.processInfo.environment
        var settings = model.appSettings
        var didOverride = false

        if let raw = env["NARU_TEST_STREAM_POWER_MODE"],
           let mode = StreamPowerMode(rawValue: raw) {
            settings.streamPowerMode = mode
            didOverride = true
        }
        if let raw = env["NARU_TEST_STREAM_ENCODING_MODE"],
           let mode = StreamEncodingMode(rawValue: raw) {
            settings.streamEncodingMode = mode
            didOverride = true
        }
        if let raw = env["NARU_TEST_STARTUP_PREFLIGHT_MODE"],
           let mode = StreamStartupPreflightMode(rawValue: raw) {
            settings.startupPreflightMode = mode
            didOverride = true
        }
        if let raw = env["NARU_TEST_STARTUP_GLANCE_SCALE_MODE"],
           let mode = StreamStartupGlanceScaleMode(rawValue: raw) {
            settings.startupGlanceScaleMode = mode
            didOverride = true
        }

        if didOverride {
            model.applyAppSettingsOverrideForTesting(settings)
        }
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

    /// XCUITest responsiveness hook — when enabled on an active-session
    /// fixture, continuously drives the model's trackpad cursor mirror while
    /// the test types in Compose. This recreates the class of UI pressure that
    /// used to make the input dock share invalidation with viewport movement.
    @MainActor
    private static func applyTestTrackpadCursorStorm(to model: NaruRemoteAppModel) {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_TRACKPAD_CURSOR_STORM"],
              !raw.isEmpty,
              raw != "0",
              raw.lowercased() != "false"
        else { return }
        guard let framebuffer = model.latestFramebuffer else {
            return
        }
        if !model.pointerControlMode.isTrackpad {
            model.togglePointerControlMode()
        }

        let framebufferSize = CGSize(width: framebuffer.width, height: framebuffer.height)
        Task { @MainActor in
            for index in 0..<300 {
                guard !Task.isCancelled else {
                    return
                }
                let transform = ViewportTransform(
                    framebufferSize: framebufferSize,
                    viewSize: CGSize(width: 390, height: 260),
                    zoomScale: 2,
                    panOffset: .zero
                )
                let horizontal: CGFloat = index.isMultiple(of: 2) ? 6 : -4
                let vertical: CGFloat = index.isMultiple(of: 3) ? 2 : -1
                _ = model.handleTrackpadGesture(
                    .dragChanged(
                        viewPoint: CGPoint(x: 195, y: 130),
                        translation: CGSize(width: horizontal, height: vertical)
                    ),
                    transform: transform
                )
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    /// XCUITest responsiveness hook — when enabled on an active-session
    /// fixture, continuously publishes same-size full-frame updates through
    /// `SessionFrameStore.framePublisher`. This recreates the "live stream is
    /// already flowing and the phone keyboard stops after the first Korean/CJK
    /// syllable" pressure without opening a real socket or persisting pixels.
    @MainActor
    private static func applyTestFramebufferFlood(to model: NaruRemoteAppModel) {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_FRAMEBUFFER_FLOOD"],
              !raw.isEmpty,
              raw != "0",
              raw.lowercased() != "false"
        else { return }
        guard let framebuffer = model.latestFramebuffer else {
            return
        }

        let frames = framebufferFloodFrames(
            width: framebuffer.width,
            height: framebuffer.height
        )
        guard !frames.isEmpty else {
            return
        }

        framebufferFloodTask?.cancel()
        framebufferFloodTask = Task { @MainActor in
            defer { framebufferFloodTask = nil }
            for index in 0..<1_200 {
                guard !Task.isCancelled else {
                    return
                }
                let frame = frames[index % frames.count]
                model.frameStore.publish(
                    framebuffer: frame,
                    dirtyRectangles: nil,
                    changedPixelCount: frame.width * frame.height,
                    serverCursor: nil
                )
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    private static func framebufferFloodFrames(
        width: Int,
        height: Int
    ) -> [RFBRawFramebuffer] {
        guard width > 0, height > 0 else {
            return []
        }
        let colors = [
            RFBColor(red: 0x1E, green: 0x2A, blue: 0x38),
            RFBColor(red: 0x24, green: 0x31, blue: 0x42),
            RFBColor(red: 0x18, green: 0x3B, blue: 0x3D),
            RFBColor(red: 0x34, green: 0x2A, blue: 0x3D)
        ]
        return colors.map { color in
            RFBRawFramebuffer(width: width, height: height, fill: color)
        }
    }

    @MainActor
    private static func cancelTestStormTasks() {
        delayedFirstFrameTask?.cancel()
        delayedFirstFrameTask = nil
        framebufferFloodTask?.cancel()
        framebufferFloodTask = nil
        modelPublishStormTask?.cancel()
        modelPublishStormTask = nil
        helperVideoHealthStormTask?.cancel()
        helperVideoHealthStormTask = nil
    }

    /// XCUITest responsiveness hook — for the connecting-session fixture,
    /// wait until Compose has first-responder focus and then publish the first
    /// framebuffer. This exercises the exact live-layout transition that can
    /// otherwise happen under an active Korean/CJK IME transaction.
    @MainActor
    private static func applyTestDelayedFirstFrameAfterComposeFocus(to model: NaruRemoteAppModel) {
        guard UXAuditFixtureToken.current() == .sessionConnectingDelayedFirstFrame else {
            return
        }

        let env = ProcessInfo.processInfo.environment
        let delayMilliseconds = env["NARU_TEST_DELAYED_FIRST_FRAME_AFTER_FOCUS_MILLISECONDS"]
            .flatMap(Int.init) ?? 250

        delayedFirstFrameTask?.cancel()
        delayedFirstFrameTask = Task { @MainActor in
            defer { delayedFirstFrameTask = nil }
            for _ in 0..<120 {
                guard !Task.isCancelled else {
                    return
                }
                if model.isComposeInputEditingActiveForTesting {
                    break
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard !Task.isCancelled,
                  model.isComposeInputEditingActiveForTesting
            else {
                return
            }
            try? await Task.sleep(for: .milliseconds(max(delayMilliseconds, 0)))
            guard !Task.isCancelled else {
                return
            }
            model.publishFirstFrameForTesting(UXAuditFixtures.sampleWidescreenFramebuffer())
        }
    }

    /// XCUITest responsiveness hook — when enabled on an active-session
    /// fixture, continuously mutates model-published chrome while Compose is
    /// focused. This recreates the production class of pressure where frame
    /// liveness, quality, and helper state can invalidate the shell even
    /// though the UIKit IME editor should remain an isolated transaction.
    @MainActor
    private static func applyTestModelPublishStorm(to model: NaruRemoteAppModel) {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_MODEL_PUBLISH_STORM"],
              !raw.isEmpty,
              raw != "0",
              raw.lowercased() != "false"
        else { return }
        guard model.session?.state == .active else {
            return
        }

        modelPublishStormTask?.cancel()
        modelPublishStormTask = Task { @MainActor in
            defer { modelPublishStormTask = nil }
            let qualitySamples: [ConnectionQuality] = [.good, .fair, .poor, .good]
            for index in 0..<900 {
                guard !Task.isCancelled else {
                    return
                }
                model.seedConnectionQualityForTesting(
                    qualitySamples[index % qualitySamples.count]
                )
                try? await Task.sleep(for: .milliseconds(6))
            }
        }
    }

    /// XCUITest responsiveness hook — when enabled on an active-session
    /// fixture, continuously publishes helper-video health changes while
    /// Compose is focused. This recreates helper-video renderer/status churn
    /// without requiring ScreenCaptureKit permission, encoded frames, or a
    /// helper process in the simulator.
    @MainActor
    private static func applyTestHelperVideoHealthStorm(to model: NaruRemoteAppModel) {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_HELPER_VIDEO_HEALTH_STORM"],
              !raw.isEmpty,
              raw != "0",
              raw.lowercased() != "false"
        else { return }
        guard model.session?.state == .active else {
            return
        }

        helperVideoHealthStormTask?.cancel()
        helperVideoHealthStormTask = Task { @MainActor in
            defer { helperVideoHealthStormTask = nil }
            let samples = [
                HelperVideoStreamHealth(
                    state: .healthy,
                    startupBand: .fast,
                    sustainedUpdateBand: .smooth,
                    decodePressure: .low
                ),
                HelperVideoStreamHealth(
                    state: .healthy,
                    startupBand: .fast,
                    sustainedUpdateBand: .usable,
                    decodePressure: .medium
                ),
                HelperVideoStreamHealth(
                    state: .healthy,
                    startupBand: .usable,
                    sustainedUpdateBand: .usable,
                    decodePressure: .medium
                )
            ]
            for index in 0..<900 {
                guard !Task.isCancelled else {
                    return
                }
                model.updateHelperVideoStreamHealth(samples[index % samples.count])
                try? await Task.sleep(for: .milliseconds(7))
            }
        }
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
