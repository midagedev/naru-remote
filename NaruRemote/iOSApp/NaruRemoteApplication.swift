import Foundation
import NaruRemoteApp
import NaruRemoteCore
import SwiftUI

@main
struct NaruRemoteApplication: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = Self.makeModel()
#if DEBUG
    @MainActor private static var trackpadCursorStormTask: Task<Void, Never>?
    @MainActor private static var framebufferFloodTask: Task<Void, Never>?
    @MainActor private static var modelPublishStormTask: Task<Void, Never>?
    @MainActor private static var helperVideoHealthStormTask: Task<Void, Never>?
    @MainActor private static var incomingClipboardChromeStormTask: Task<Void, Never>?
    @MainActor private static var delayedFirstFrameTask: Task<Void, Never>?
#endif

    var body: some Scene {
        WindowGroup {
            NaruRemoteAppShell(
                model: model,
                buildVersion: Self.bundleBuildVersion(),
                startsOnSelectedProfileDetail: Self.testStartsOnOperationSurface()
            )
                .preferredColorScheme(Self.testOverrideColorScheme())
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase != .active else {
                        return
                    }
#if DEBUG
                    Self.cancelTestStormTasks()
#endif
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
#if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_OVERRIDE_INTERFACE_STYLE"],
              !raw.isEmpty
        else { return nil }
        switch raw.lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
#else
        nil
#endif
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
    /// Operation without tapping through Connections. The legacy detail key
    /// remains supported for focused input-dock tests; the Operation key does
    /// not implicitly force the dock into pre-session fixtures.
    private static func testStartsOnOperationSurface() -> Bool {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["NARU_TEST_START_OPERATION_SURFACE"]
                ?? environment["NARU_TEST_START_PROFILE_DETAIL"],
              !raw.isEmpty
        else { return false }
        return raw != "0" && raw.lowercased() != "false"
#else
        false
#endif
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

        #if DEBUG
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
        #else
        // App Store builds do not link synthetic fixtures or launch-
        // environment state injection. They always start from real persisted
        // state and the production dependency graph.
        let model = NaruRemoteAppModel(
            profilePreviewStore: previewStore,
            credentialStore: credentialStore,
            settingsPersistence: settingsPersistence,
            pipWatchController: PiPWatchPictureInPictureController(),
            localClipboardWriter: UIPasteboardClipboardWriter()
        )
        #endif
        Task { @MainActor in
#if DEBUG
            // XCUITest E2E hook — pre-populate the keychain with
            // known profile credentials BEFORE the profile store loads
            // so live UI tests can connect without driving the editor
            // UI. No-op when the env vars are unset (production).
            await applyTestInjectKeychainCredentials(into: credentialStore)
#endif

            if shouldLoadProfileStore() {
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

#if DEBUG
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
            applyTestIncomingClipboardChromeStorm(to: model)
            applyTestDelayedFirstFrameAfterComposeFocus(to: model)
            writeTestDeviceStateMarkerIfRequested(for: model)
#endif
        }
        return model
    }

    /// Release builds cannot bypass the real profile store through a process
    /// environment variable. Debug remains configurable for XCUITest and
    /// physical-device gates.
    private static func shouldLoadProfileStore() -> Bool {
#if DEBUG
        !testSkipsProfileStoreLoad()
#else
        true
#endif
    }

#if DEBUG
    /// Physical-device smoke hook — when explicitly requested by the
    /// launch environment, write a privacy-safe marker into the app
    /// Documents container.  The CLI gate can fetch this through
    /// `devicectl` to prove the freshly launched app applied test
    /// seed/profile settings without relying on XCTest on a locked or
    /// transient device.
    @MainActor
    private static func writeTestDeviceStateMarkerIfRequested(
        for model: NaruRemoteAppModel
    ) {
        guard testEnvironmentFlag("NARU_TEST_WRITE_DEVICE_STATE_MARKER") else {
            return
        }

        let selectedProfile = model.selectedProfile
        let marker = TestDeviceStateMarker(
            profileCount: model.profiles.count,
            selectedProfileStatus: selectedProfile == nil ? "missing" : "present",
            selectedProfileHostKind: selectedProfile?.hostKind.rawValue ?? "none",
            selectedProfileCredentialReferenceStatus: selectedProfile?.credentialRef == nil ? "missing" : "present",
            selectedProfileHelperVideoStatus: selectedProfile?.helperVideo?.isEnabled == true ? "enabled" : "disabled",
            selectedProfileHelperVideoSecretReferenceStatus: selectedProfile?.helperVideo?.pairingSecretRef == nil ? "missing" : "present",
            profileStoreLoadSkippedStatus: testSkipsProfileStoreLoad() ? "true" : "false",
            startsOnSelectedProfileDetailStatus: testStartsOnOperationSurface() ? "true" : "false",
            streamSettingsOverrideStatus: testStreamSettingsOverrideStatus(),
            markerRunNonce: ProcessInfo.processInfo.environment["NARU_TEST_DEVICE_STATE_MARKER_NONCE"] ?? ""
        )

        do {
            let url = testDeviceStateMarkerURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(marker)
            try data.write(to: url, options: .atomic)
        } catch {
            // Production never enables this hook.  The physical-device
            // gate reports a missing marker if the file cannot be written.
        }
    }

    private struct TestDeviceStateMarker: Encodable {
        let schemaVersion = 1
        let mode = "physical-ipad-state-marker"
        let profileCount: Int
        let selectedProfileStatus: String
        let selectedProfileHostKind: String
        let selectedProfileCredentialReferenceStatus: String
        let selectedProfileHelperVideoStatus: String
        let selectedProfileHelperVideoSecretReferenceStatus: String
        let profileStoreLoadSkippedStatus: String
        let startsOnSelectedProfileDetailStatus: String
        let streamSettingsOverrideStatus: String
        let markerRunNonce: String
    }

    private static func testStreamSettingsOverrideStatus() -> String {
        let env = ProcessInfo.processInfo.environment
        let keys = [
            "NARU_TEST_STREAM_POWER_MODE",
            "NARU_TEST_STREAM_ENCODING_MODE",
            "NARU_TEST_STARTUP_PREFLIGHT_MODE",
            "NARU_TEST_STARTUP_GLANCE_SCALE_MODE"
        ]
        return keys.contains { env[$0]?.isEmpty == false } ? "present" : "absent"
    }

    private static func testDeviceStateMarkerURL() -> URL {
        let filename = ProcessInfo.processInfo.environment["NARU_TEST_DEVICE_STATE_MARKER_FILENAME"]
            .flatMap(Self.sanitizedTestDeviceStateMarkerFilename)
            ?? "naru-device-state-marker.json"
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        return documentsURL.appendingPathComponent(filename, isDirectory: false)
    }

    private static func sanitizedTestDeviceStateMarkerFilename(_ raw: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: allowed.inverted) == nil,
              !trimmed.contains(".."),
              !trimmed.hasPrefix(".")
        else { return nil }
        return trimmed
    }

    private static func testEnvironmentFlag(_ key: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return false }
        let lowered = raw.lowercased()
        return lowered == "1" || lowered == "true" || lowered == "yes"
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

        trackpadCursorStormTask?.cancel()
        trackpadCursorStormTask = Task { @MainActor in
            defer { trackpadCursorStormTask = nil }
            for _ in 0..<160 {
                guard !Task.isCancelled else {
                    return
                }
                if model.isComposeInputEditingActiveForTesting {
                    break
                }
                try? await Task.sleep(for: .milliseconds(15))
            }
            guard !Task.isCancelled,
                  model.isComposeInputEditingActiveForTesting
            else {
                return
            }

            let framebufferSize = CGSize(width: framebuffer.width, height: framebuffer.height)
            let stormEndsAt = Date().addingTimeInterval(6)
            var index = 0
            while Date() < stormEndsAt {
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
                index += 1
                try? await Task.sleep(for: .milliseconds(16))
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
            let floodEndsAt = Date().addingTimeInterval(10)
            var index = 0
            while Date() < floodEndsAt {
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
                index += 1
                let frameInterval = model.frameApplicationContentFrameMinimumIntervalForTesting
                let frameDelayNanoseconds = Int64(
                    (max(frameInterval, 0.008) * 1_000_000_000).rounded(.up)
                )
                try? await Task.sleep(for: .nanoseconds(frameDelayNanoseconds))
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
        trackpadCursorStormTask?.cancel()
        trackpadCursorStormTask = nil
        delayedFirstFrameTask?.cancel()
        delayedFirstFrameTask = nil
        framebufferFloodTask?.cancel()
        framebufferFloodTask = nil
        modelPublishStormTask?.cancel()
        modelPublishStormTask = nil
        helperVideoHealthStormTask?.cancel()
        helperVideoHealthStormTask = nil
        incomingClipboardChromeStormTask?.cancel()
        incomingClipboardChromeStormTask = nil
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
            for index in 0..<240 {
                guard !Task.isCancelled else {
                    return
                }
                model.seedConnectionQualityForTesting(
                    qualitySamples[index % qualitySamples.count]
                )
                try? await Task.sleep(for: .milliseconds(16))
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
            for index in 0..<240 {
                guard !Task.isCancelled else {
                    return
                }
                model.updateHelperVideoStreamHealth(samples[index % samples.count])
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// XCUITest responsiveness hook — when enabled, wait until Compose owns
    /// first-responder focus and then repeatedly publish remote clipboard
    /// reviews. Unlike quality/helper samples, this drives a bottom
    /// safe-area banner whose height can appear above the keyboard; it
    /// reproduces the physical-device class where Korean/CJK input stalls
    /// after the first syllable because accessory chrome relayouts under
    /// UIKit's active IME transaction.
    @MainActor
    private static func applyTestIncomingClipboardChromeStorm(to model: NaruRemoteAppModel) {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_INCOMING_CLIPBOARD_CHROME_STORM"],
              !raw.isEmpty,
              raw != "0",
              raw.lowercased() != "false"
        else { return }
        guard model.session?.state == .active else {
            return
        }

        incomingClipboardChromeStormTask?.cancel()
        incomingClipboardChromeStormTask = Task { @MainActor in
            defer { incomingClipboardChromeStormTask = nil }
            for _ in 0..<160 {
                guard !Task.isCancelled else {
                    return
                }
                if model.isComposeInputEditingActiveForTesting {
                    break
                }
                try? await Task.sleep(for: .milliseconds(15))
            }
            guard !Task.isCancelled,
                  model.isComposeInputEditingActiveForTesting
            else {
                return
            }

            let samples = [
                "Synthetic remote clipboard review while Compose is focused.",
                "Synthetic remote clipboard review with enough text to span more than one compact iPhone line during a keyboard accessory relayout.",
                "Synthetic remote clipboard review updated again during active IME composition."
            ]
            for index in 0..<180 {
                guard !Task.isCancelled else {
                    return
                }
                model.recordIncomingClipboard(
                    samples[index % samples.count],
                    at: Date(timeIntervalSince1970: TimeInterval(index))
                )
                try? await Task.sleep(for: .milliseconds(16))
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

        let modifiers = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(StickyModifierState.Modifier.init(rawValue:))

        applyStickyModifierPrelock(modifiers, to: model)

        // Card-driven audits tap a connection card AFTER launch, and both
        // `selectProfile` and the connect path reset `directKeystrokeMode`
        // and `stickyModifierState` — wiping an init-time prelock before
        // the test can screenshot it.  Poll for the first session (same
        // pattern as the clipboard-storm hook above) and re-apply once the
        // connect-path resets are behind us.
        Task { @MainActor in
            for _ in 0..<2000 {  // ~30 s at 15 ms per lap
                guard !Task.isCancelled else { return }
                if model.session != nil { break }
                try? await Task.sleep(for: .milliseconds(15))
            }
            guard !Task.isCancelled, model.session != nil else { return }
            try? await Task.sleep(for: .milliseconds(250))
            applyStickyModifierPrelock(modifiers, to: model)
        }
    }

    @MainActor
    private static func applyStickyModifierPrelock(
        _ modifiers: [StickyModifierState.Modifier],
        to model: NaruRemoteAppModel
    ) {
        // Spec 011: the sticky modifiers render on the shared accessory
        // strip in both dock modes, so no mode switch is needed to reach
        // them — only an active session.
        for modifier in modifiers {
            // Back-to-back taps in the same `Task` land < 400 ms
            // apart (same `@MainActor` continuation), which is the
            // double-tap window — idle → armed → locked. Bypasses
            // the XCUITest tap-cadence gap (~600 ms between real
            // taps).
            Task { @MainActor in
                await model.tapDirectKey(.modifier(modifier))
                await model.tapDirectKey(.modifier(modifier))
            }
        }
    }

    /// XCUITest E2E hook — when a `*_REF` and matching `*_PASSWORD`
    /// pair is set, write it into the supplied
    /// `KeychainConnectionCredentialStore` before any profile flow
    /// runs. Pair with a seeded profile whose credential references
    /// match so live tests can exercise VNC and helper-video without
    /// driving the editor UI. No-op in production because the
    /// variables are never set.
    private static func applyTestInjectKeychainCredentials(
        into store: KeychainConnectionCredentialStore
    ) async {
        let env = ProcessInfo.processInfo.environment
        let mappings = [
            (
                ref: "NARU_TEST_INJECT_KEYCHAIN_REF",
                password: "NARU_TEST_INJECT_KEYCHAIN_PASSWORD"
            ),
            (
                ref: "NARU_TEST_INJECT_HELPER_VIDEO_KEYCHAIN_REF",
                password: "NARU_TEST_INJECT_HELPER_VIDEO_KEYCHAIN_PASSWORD"
            )
        ]

        for mapping in mappings {
            guard let ref = env[mapping.ref],
                  !ref.isEmpty,
                  let password = env[mapping.password],
                  !password.isEmpty
            else { continue }
            do {
                try await store.savePassword(password, for: ref)
            } catch {
                // Silently ignore — production never hits this branch and
                // a test failure will surface as "credential unavailable"
                // or "helper video unavailable" when Connect is tapped.
            }
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
#endif

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
