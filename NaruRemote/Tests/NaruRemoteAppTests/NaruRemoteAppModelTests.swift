import Foundation
import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class NaruRemoteAppModelTests: XCTestCase {
    func testDefaultFrameStreamConfigurationCapsActiveCadenceAtDisplayRate() {
        let configuration = NaruRemoteAppModel.defaultFrameStreamConfiguration

        XCTAssertEqual(configuration.requestTimeout, 8)
        XCTAssertEqual(
            configuration.frameInterval,
            1.0 / 60.0,
            accuracy: 0.0001,
            "Default live sessions should cap active frame requests at about 60 fps."
        )
        XCTAssertEqual(configuration.idleFrameInterval, 0.05)
        XCTAssertEqual(configuration.updateMode, .continuousUpdates)
    }

    func testSessionStreamPacingPolicyBacksOffForThermalPressure() {
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 1.0 / 30.0,
                thermalState: .nominal
            ),
            1.0 / 30.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 1.0 / 30.0,
                thermalState: .fair
            ),
            1.0 / 24.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 1.0 / 30.0,
                thermalState: .serious
            ),
            1.0 / 15.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 1.0 / 30.0,
                thermalState: .critical
            ),
            1.0 / 8.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .emptyUpdate,
                configuredDelay: 0.05,
                thermalState: .critical,
                emptyUpdateStreak: 24
            ),
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 0,
                thermalState: .critical
            ),
            0,
            accuracy: 0.0001,
            "Opt-in fake/test streams that remove pacing should stay deterministic."
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 1.0 / 60.0,
                thermalState: .serious,
                usesPowerSaverPacing: true
            ),
            1.0 / 15.0,
            accuracy: 0.0001,
            "Thermal floors should win when they are stricter than Low Power Mode."
        )
    }

    func testSessionStreamPacingPolicyBacksOffForSustainedEmptyUpdates() {
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .emptyUpdate,
                configuredDelay: 0.05,
                thermalState: .nominal,
                emptyUpdateStreak: 1
            ),
            0.05,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .emptyUpdate,
                configuredDelay: 0.05,
                thermalState: .nominal,
                emptyUpdateStreak: 8
            ),
            0.075,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .emptyUpdate,
                configuredDelay: 0.05,
                thermalState: .nominal,
                emptyUpdateStreak: 24
            ),
            0.125,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 1.0 / 30.0,
                thermalState: .nominal,
                emptyUpdateStreak: 24
            ),
            1.0 / 30.0,
            accuracy: 0.0001,
            "Empty-update streaks must not throttle content frames after activity resumes."
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .emptyUpdate,
                configuredDelay: 0,
                thermalState: .nominal,
                emptyUpdateStreak: 24
            ),
            0,
            accuracy: 0.0001,
            "Opt-in fake/test streams that remove idle pacing should stay deterministic."
        )
    }

    func testSessionStreamPacingPolicyBacksOffForLowPowerMode() {
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 1.0 / 60.0,
                thermalState: .nominal,
                usesPowerSaverPacing: true
            ),
            1.0 / 30.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .emptyUpdate,
                configuredDelay: 0.05,
                thermalState: .nominal,
                usesPowerSaverPacing: true,
                emptyUpdateStreak: 1
            ),
            0.125,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 0,
                thermalState: .nominal,
                usesPowerSaverPacing: true
            ),
            0,
            accuracy: 0.0001,
            "Opt-in fake/test streams that remove pacing should stay deterministic."
        )
    }

    func testSessionStreamPressurePacingStateActivatesAfterRepeatedLaggingClientProcessing() {
        var state = SessionStreamPressurePacingState()
        let slowFrame = pressureTestFrame(
            totalMilliseconds: 120,
            networkReadMilliseconds: 20
        )

        state.record(frame: slowFrame)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        state.record(frame: slowFrame)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        state.record(frame: slowFrame)
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)

        let fastFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10
        )
        for _ in 0..<SessionStreamPressurePacingState.adaptiveRecoveryUpdateCount {
            state.record(frame: fastFrame)
        }
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateIgnoresNetworkWaitAndEmptyUpdates() {
        var state = SessionStreamPressurePacingState()
        let networkWaitFrame = pressureTestFrame(
            totalMilliseconds: 320,
            networkReadMilliseconds: 260
        )
        let emptySlowFrame = pressureTestFrame(
            totalMilliseconds: 160,
            networkReadMilliseconds: 20,
            isIncremental: true,
            changedPixelCount: 0
        )
        let timeoutSlowFrame = pressureTestFrame(
            totalMilliseconds: 160,
            networkReadMilliseconds: 20,
            transportIdleTimedOut: true
        )

        for _ in 0..<6 {
            state.record(frame: networkWaitFrame)
            state.record(frame: emptySlowFrame)
            state.record(frame: timeoutSlowFrame)
        }

        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateRequiresConsecutiveLaggingContentFrames() {
        var state = SessionStreamPressurePacingState()
        let slowFrame = pressureTestFrame(
            totalMilliseconds: 120,
            networkReadMilliseconds: 20
        )
        let fastFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10
        )

        state.record(frame: slowFrame)
        state.record(frame: fastFrame)
        state.record(frame: slowFrame)
        state.record(frame: slowFrame)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)

        state.record(frame: slowFrame)
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateDoesNotBreakContentStreakOnEmptyUpdates() {
        var state = SessionStreamPressurePacingState()
        let slowFrame = pressureTestFrame(
            totalMilliseconds: 120,
            networkReadMilliseconds: 20
        )
        let emptyFrame = pressureTestFrame(
            totalMilliseconds: 15,
            networkReadMilliseconds: 10,
            isIncremental: true,
            changedPixelCount: 0
        )

        state.record(frame: slowFrame)
        state.record(frame: emptyFrame)
        state.record(frame: slowFrame)
        state.record(frame: emptyFrame)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)

        state.record(frame: slowFrame)
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateBreaksContentStreakOnTransportTimeout() {
        var state = SessionStreamPressurePacingState()
        let slowFrame = pressureTestFrame(
            totalMilliseconds: 120,
            networkReadMilliseconds: 20
        )
        let timeoutFrame = pressureTestFrame(
            totalMilliseconds: 160,
            networkReadMilliseconds: 20,
            transportIdleTimedOut: true
        )

        state.record(frame: slowFrame)
        state.record(frame: timeoutFrame)
        state.record(frame: slowFrame)
        state.record(frame: slowFrame)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)

        state.record(frame: slowFrame)
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateRecoveryCountsEveryUpdateDecision() {
        var state = SessionStreamPressurePacingState()
        let slowFrame = pressureTestFrame(
            totalMilliseconds: 120,
            networkReadMilliseconds: 20
        )
        let emptyFrame = pressureTestFrame(
            totalMilliseconds: 15,
            networkReadMilliseconds: 10,
            isIncremental: true,
            changedPixelCount: 0
        )

        for _ in 0..<SessionStreamPressurePacingState.consecutiveLaggingContentFrameThreshold {
            state.record(frame: slowFrame)
        }
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)

        for _ in 0..<SessionStreamPressurePacingState.adaptiveRecoveryUpdateCount {
            state.record(frame: emptyFrame)
        }
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
    }

    func testModelLoadsStoredStreamPowerMode() async throws {
        let persistence = InMemoryAppSettingsPersistence(
            settings: AppSettings(streamPowerMode: .powerSaver)
        )
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        await model.loadStoredSettings()

        XCTAssertEqual(model.appSettings.streamPowerMode, .powerSaver)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testModelPersistsStreamPowerModeToggle() async throws {
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        model.toggleStreamPowerMode()

        let savedPowerSaverSettings = try await waitForPersistedStreamPowerMode(
            .powerSaver,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.streamPowerMode, .powerSaver)
        XCTAssertEqual(savedPowerSaverSettings.streamPowerMode, .powerSaver)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStreamPowerMode()

        let savedBalancedSettings = try await waitForPersistedStreamPowerMode(
            .balanced,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.streamPowerMode, .balanced)
        XCTAssertEqual(savedBalancedSettings.streamPowerMode, .balanced)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testStoredSettingsLoadDoesNotClobberUserStreamPowerToggle() async throws {
        let persistence = InMemoryAppSettingsPersistence(
            settings: AppSettings(streamPowerMode: .balanced)
        )
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        model.setStreamPowerMode(.powerSaver)
        await model.loadStoredSettings()

        XCTAssertEqual(model.appSettings.streamPowerMode, .powerSaver)
    }

    func testModelAddsProfileAndCreatesSessionDraft() async throws {
        let model = NaruRemoteAppModel()
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")

        await model.addProfile(profile)

        XCTAssertEqual(model.snapshot.selectedProfile, profile)
        XCTAssertEqual(model.snapshot.session?.profileID, profile.id)
        XCTAssertEqual(model.snapshot.composeDraft?.sessionID, model.snapshot.session?.id)
    }

    func testModelLoadsProfilesFromStoreOnLaunch() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let persistence = InMemoryConnectionProfilePersistence(profiles: [profile])
        let store = try await ConnectionProfileStore(persistence: persistence)

        let model = NaruRemoteAppModel(profileStore: store)
        await model.loadStoredProfiles()

        XCTAssertEqual(model.snapshot.profiles, [profile])
        XCTAssertEqual(model.snapshot.selectedProfile, profile)
    }

    func testModelLoadsStoredProfilePreviewsWithProfiles() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let preview = ProfilePreviewThumbnail(
            width: 1,
            height: 1,
            sourceWidth: 2,
            sourceHeight: 2,
            capturedAt: Date(timeIntervalSince1970: 100),
            pixels: [RFBColor(red: 1, green: 2, blue: 3)]
        )
        let persistence = InMemoryConnectionProfilePersistence(profiles: [profile])
        let profileStore = try await ConnectionProfileStore(persistence: persistence)
        let previewStore = InMemoryProfilePreviewStore(thumbnails: [profile.id: preview])
        let model = NaruRemoteAppModel(
            profileStore: profileStore,
            profilePreviewStore: previewStore
        )

        await model.loadStoredProfiles()

        XCTAssertEqual(model.snapshot.profilePreviews[profile.id], preview)
        XCTAssertEqual(model.snapshot.connectionGridCards.first?.preview, preview)
    }

    func testModelPersistsAddedProfileToStore() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")

        await model.addProfile(profile)

        let reloaded = try await ConnectionProfileStore(persistence: persistence)
        let allProfiles = await reloaded.allProfiles()
        XCTAssertEqual(allProfiles, [profile])
        XCTAssertNil(model.profilePersistenceError)
    }

    func testModelSavesProfilePasswordInCredentialStoreAndKeepsOnlyReferenceInProfile() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")

        await model.addProfile(profile, password: "secret")

        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(savedProfile.credentialRef)
        XCTAssertEqual(savedProfile.host, "desk.tailnet.ts.net")
        let storedPassword = try await credentialStore.password(for: credentialRef)
        XCTAssertEqual(storedPassword, "secret")
        XCTAssertFalse(credentialRef.contains("secret"))
        XCTAssertNil(model.profilePersistenceError)
    }

    func testModelUsesStoredVNCPasswordForStreamingConnection() async throws {
        let credentialRef = "vnc-password:test"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            credentialRef: credentialRef
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [credentialRef: "secret"])
        let framebuffer = RFBRawFramebuffer(width: 1, height: 1, fill: RFBColor(red: 10, green: 0, blue: 0))
        let connector = FakeStreamingConnector(width: 1, height: 1, name: "Desk", framebuffer: framebuffer)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.credentials, [.vncPassword("secret")])
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffer)
    }

    func testModelRecordsInjectedSessionThermalState() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            thermalStateProvider: { .serious }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.snapshot.sessionStreamStats.deliveredFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.thermalState, .serious)
    }

    func testModelFailsSafelyWhenProfileCredentialReferenceCannotBeLoaded() async throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            credentialRef: "vnc-password:missing"
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(width: 1, height: 1, fill: RFBColor(red: 10, green: 0, blue: 0))
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()

        XCTAssertEqual(connector.sessionRequests, [])
        XCTAssertEqual(model.snapshot.session?.state, .failed)
        XCTAssertEqual(model.snapshot.diagnosticRun?.firstFailedStage?.stage, .authentication)
        XCTAssertNil(model.snapshot.latestFramebuffer)
    }

    func testModelConnectsSelectedProfileThroughConnector() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.requests, [FakeFirstFrameConnector.Request(host: "desk.tailnet.ts.net", port: 5900)])
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(model.snapshot.session?.hudMessage, "Connected")
        XCTAssertEqual(model.snapshot.diagnosticRun?.firstFailedStage, nil)
        XCTAssertEqual(model.snapshot.diagnosticRun?.stages.last?.stage, .firstFrame)
    }

    func testModelConnectsStreamingClientAndStoresFirstFramebuffer() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let connector = FakeStreamingConnector(width: 2, height: 1, name: "Desk", framebuffer: framebuffer)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.sessionRequests, [FakeFirstFrameConnector.Request(host: "desk.tailnet.ts.net", port: 5900)])
        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(model.snapshot.session?.hudMessage, "Connected")
        XCTAssertEqual(model.snapshot.diagnosticRun?.stages.last?.safeDetail, "2x1 remote framebuffer is available.")
    }

    func testStreamingFirstFrameFailureAfterHandshakeReportsFirstFrameStage() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeStreamingConnector(width: 2, height: 1, name: "Desk", framebuffers: [])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, requestTimeout: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.sessionRequests, [FakeFirstFrameConnector.Request(host: "desk.tailnet.ts.net", port: 5900)])
        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(model.snapshot.session?.state, .failed)
        XCTAssertEqual(model.snapshot.session?.hudMessage, "No frame received")
        XCTAssertEqual(model.snapshot.diagnosticRun?.firstFailedStage?.stage, .firstFrame)
        XCTAssertEqual(model.snapshot.diagnosticRun?.firstFailedStage?.metadata?.failureCode, "rfb.incompleteTranscript")
    }

    func testModelStoresStreamingFramebufferPreview() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 640,
            height: 400,
            fill: RFBColor(red: 42, green: 7, blue: 9)
        )
        let connector = FakeStreamingConnector(width: 640, height: 400, name: "Desk", framebuffer: framebuffer)
        let previewStore = InMemoryProfilePreviewStore()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            profilePreviewStore: previewStore,
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        let preview = try XCTUnwrap(model.snapshot.profilePreviews[profile.id])
        XCTAssertEqual(preview.width, 320)
        XCTAssertEqual(preview.height, 200)
        XCTAssertEqual(preview.pixels.first, RFBColor(red: 42, green: 7, blue: 9))

        let storedPreview = try await previewStore.loadThumbnail(for: profile.id)
        XCTAssertEqual(storedPreview, preview)
    }

    func testModelThrottlesStreamingFramebufferPreviewUpdates() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            updateResults: [
                RFBFramebufferUpdateResult(
                    framebuffer: firstFramebuffer,
                    dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                    changedPixelCount: 1,
                    capturedAt: Date(timeIntervalSince1970: 100)
                ),
                RFBFramebufferUpdateResult(
                    framebuffer: secondFramebuffer,
                    dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                    changedPixelCount: 1,
                    capturedAt: Date(timeIntervalSince1970: 100.5)
                )
            ]
        )
        let previewStore = InMemoryProfilePreviewStore()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            profilePreviewStore: previewStore,
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(model.snapshot.latestFramebuffer, secondFramebuffer)
        let preview = try XCTUnwrap(model.snapshot.profilePreviews[profile.id])
        XCTAssertEqual(preview.pixels.first, RFBColor(red: 10, green: 0, blue: 0))

        let storedPreview = try await previewStore.loadThumbnail(for: profile.id)
        XCTAssertEqual(storedPreview, preview)
    }

    func testModelPublishesReconnectFirstFramePreviewInsideThrottleWindow() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let reconnectFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 30, green: 0, blue: 0)
        )
        let firstConnector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            updateResults: [
                RFBFramebufferUpdateResult(
                    framebuffer: firstFramebuffer,
                    dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                    changedPixelCount: 1,
                    capturedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        let reconnectConnector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            updateResults: [
                RFBFramebufferUpdateResult(
                    framebuffer: reconnectFramebuffer,
                    dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                    changedPixelCount: 1,
                    capturedAt: Date(timeIntervalSince1970: 100.5)
                )
            ]
        )
        let connectorSequence = FakeStreamingConnectorSequence([
            firstConnector,
            reconnectConnector
        ])
        let previewStore = InMemoryProfilePreviewStore()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            profilePreviewStore: previewStore,
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connectorSequence.next() }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(
            try XCTUnwrap(model.snapshot.profilePreviews[profile.id]).pixels.first,
            RFBColor(red: 10, green: 0, blue: 0)
        )

        model.disconnect()
        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(model.snapshot.latestFramebuffer, reconnectFramebuffer)
        XCTAssertEqual(
            try XCTUnwrap(model.snapshot.profilePreviews[profile.id]).pixels.first,
            RFBColor(red: 30, green: 0, blue: 0)
        )
    }

    func testDeletingProfileClearsStoredPreview() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let preview = ProfilePreviewThumbnail(
            width: 1,
            height: 1,
            sourceWidth: 2,
            sourceHeight: 2,
            capturedAt: Date(timeIntervalSince1970: 100),
            pixels: [RFBColor(red: 1, green: 2, blue: 3)]
        )
        let previewStore = InMemoryProfilePreviewStore(thumbnails: [profile.id: preview])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                profilePreviews: [profile.id: preview]
            ),
            profilePreviewStore: previewStore
        )

        await model.deleteProfile(id: profile.id)

        XCTAssertNil(model.snapshot.profilePreviews[profile.id])
        let storedPreview = try await previewStore.loadThumbnail(for: profile.id)
        XCTAssertNil(storedPreview)
    }

    func testModelKeepsStreamingFramesAfterFirstFramebuffer() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(connector.frameUpdateRequests, [false, true])
        XCTAssertEqual(model.snapshot.latestFramebuffer, secondFramebuffer)
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(model.snapshot.sessionStreamStats.deliveredFrameCount, 2)
        XCTAssertEqual(model.snapshot.sessionStreamStats.contentFrameCount, 2)
        XCTAssertEqual(model.snapshot.sessionStreamStats.emptyUpdateCount, 0)
    }

    func testModelDoesNotRenegotiateAdaptiveEncodingsByDefault() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(model.connectionQuality, .good)
        XCTAssertTrue(connector.renegotiatedPreferences.isEmpty)
    }

    func testModelRenegotiatesAdaptiveEncodingsWhenOptedInOnceQualityBucketIsKnown() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector },
            allowsAdaptiveEncodingRenegotiation: true
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        let expected = RFBEncodingPreference.adaptive(
            supported: .full,
            requestedPseudoEncodings: .withServerCursorAndPacingExtensions,
            connectionQuality: .good
        )
        XCTAssertEqual(model.connectionQuality, .good)
        XCTAssertEqual(connector.renegotiatedPreferences, [expected])
        let renegotiated = try XCTUnwrap(connector.renegotiatedPreferences.first)
        XCTAssertTrue(renegotiated.encodingList().contains(RFBEncoding.fence))
        XCTAssertTrue(renegotiated.encodingList().contains(RFBEncoding.continuousUpdates))
    }

    func testModelStopsContinuousUpdatesWhenContinuousFrameStreamEnds() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer],
            canEnableContinuousUpdates: true
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 2,
                requestTimeout: 1,
                frameInterval: 0,
                updateMode: .continuousUpdates
            ),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(connector.receivedFrameCount, 1)
        XCTAssertEqual(connector.continuousUpdateFlags, [true, false])
        XCTAssertEqual(model.snapshot.latestFramebuffer, secondFramebuffer)
    }

    func testModelPublishesAndPersistsServerCursorFromFramePump() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let cursor = RFBServerCursor(
            width: 1,
            height: 1,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [RFBColor(red: 255, green: 255, blue: 255)]
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            updateResults: [
                RFBFramebufferUpdateResult(
                    framebuffer: firstFramebuffer,
                    dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                    changedPixelCount: 1,
                    serverCursor: cursor
                ),
                .fullFrame(framebuffer: secondFramebuffer)
            ]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(model.snapshot.latestFramebuffer, secondFramebuffer)
        XCTAssertEqual(model.snapshot.latestServerCursor, cursor)
    }

    func testModelSkipsPublishingEmptyIncrementalUpdates() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            updateResults: [
                .fullFrame(framebuffer: framebuffer),
                RFBFramebufferUpdateResult(
                    framebuffer: framebuffer,
                    dirtyRectangles: [],
                    changedPixelCount: 0
                )
            ]
        )
        let pipController = FakePiPWatchController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 2,
                frameInterval: 0.05,
                idleFrameInterval: 0
            ),
            connectorFactory: { connector },
            pipWatchController: pipController
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(30))
        model.startPiPWatch(at: Date(timeIntervalSince1970: 100))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(connector.frameUpdateRequests, [false, true])
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(pipController.enqueuedFramebuffers, [framebuffer])
        XCTAssertEqual(model.snapshot.sessionStreamStats.deliveredFrameCount, 2)
        XCTAssertEqual(model.snapshot.sessionStreamStats.contentFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.emptyUpdateCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.transportIdleTimeoutCount, 0)
        XCTAssertEqual(model.snapshot.sessionStreamStats.dirtyRectangleSampleCount, 2)
        XCTAssertEqual(model.snapshot.sessionStreamStats.dirtyRectangleCountMax, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.dirtyAreaPermilleMax, 1_000)
        XCTAssertEqual(model.snapshot.sessionStreamStats.changedPixelsPermilleMax, 1_000)

        model.disconnect()

        XCTAssertEqual(model.snapshot.sessionStreamStats, SessionStreamStats())
    }

    func testModelPublishesServerCursorFromEmptyIncrementalUpdateWithoutRepublishingFrame() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let cursor = RFBServerCursor(
            width: 1,
            height: 1,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [RFBColor(red: 255, green: 255, blue: 255)]
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            updateResults: [
                .fullFrame(framebuffer: framebuffer),
                RFBFramebufferUpdateResult(
                    framebuffer: framebuffer,
                    dirtyRectangles: [],
                    changedPixelCount: 0,
                    serverCursor: cursor
                )
            ]
        )
        let pipController = FakePiPWatchController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 2,
                frameInterval: 0.05,
                idleFrameInterval: 0
            ),
            connectorFactory: { connector },
            pipWatchController: pipController
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(30))
        model.startPiPWatch(at: Date(timeIntervalSince1970: 100))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(connector.frameUpdateRequests, [false, true])
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(model.snapshot.latestServerCursor, cursor)
        XCTAssertEqual(
            pipController.enqueuedFramebuffers,
            [framebuffer],
            "Cursor-only updates must not forward an unchanged framebuffer into PiP."
        )
        XCTAssertEqual(model.snapshot.sessionStreamStats.deliveredFrameCount, 2)
        XCTAssertEqual(model.snapshot.sessionStreamStats.contentFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.emptyUpdateCount, 1)
    }

    func testModelAppliesAdaptivePressurePacingInFrameLoop() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let slowClientTiming = RFBFramebufferUpdateTiming(
            totalMilliseconds: 120,
            networkReadMilliseconds: 20
        )
        let updates = (0..<4).map { _ in
            RFBFramebufferUpdateResult(
                framebuffer: framebuffer,
                dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                changedPixelCount: 1,
                timing: slowClientTiming
            )
        }
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            updateResults: updates
        )
        let pacingSleepRecorder = PacingSleepRecorder()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 4,
                frameInterval: 1.0 / 60.0,
                idleFrameInterval: 0.05
            ),
            connectorFactory: { connector },
            thermalStateProvider: { .nominal },
            lowPowerModeProvider: { false },
            streamPacingSleep: { delay in
                pacingSleepRecorder.record(delay)
            }
        )

        await model.connectSelectedProfile()

        let delays = try await waitForRecordedPacingDelays(
            4,
            in: pacingSleepRecorder
        )
        XCTAssertEqual(delays[0], 1.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(delays[1], 1.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(delays[2], 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(delays[3], 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(model.appSettings.streamPowerMode, .balanced)
        XCTAssertEqual(model.snapshot.sessionStreamStats.contentFrameCount, 4)
        model.disconnect()
        try await Task.sleep(for: .milliseconds(10))
    }

    func testModelCancelsFrameStreamAndClearsFramebufferWhenProfileChanges() async throws {
        let first = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Laptop", host: "laptop.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [framebuffer, framebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [first, second], selectedProfileID: first.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0.05),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNotNil(model.snapshot.latestFramebuffer)

        model.selectProfile(id: second.id)

        XCTAssertEqual(model.snapshot.selectedProfile, second)
        XCTAssertEqual(model.snapshot.session?.profileID, second.id)
        XCTAssertNil(model.snapshot.latestFramebuffer)
        XCTAssertNil(model.snapshot.diagnosticRun)
    }

    func testModelStartsPiPWatchWhenActiveFrameExists() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            pipWatchController: FakePiPWatchController()
        )

        model.startPiPWatch(at: Date(timeIntervalSince1970: 101))

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .watching)
        XCTAssertEqual(model.snapshot.pipWatchSession?.inputPolicy, .watchOnly)
        XCTAssertEqual(model.snapshot.pipWatchSession?.lastFrame?.width, 2)
        XCTAssertEqual(model.snapshot.pipWatchSession?.lastFrame?.height, 1)
        XCTAssertEqual(model.snapshot.pipWatchStatusText, "Watching in PiP")
    }

    func testModelStartsSystemPiPControllerWhenActiveFrameExists() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let pipController = FakePiPWatchController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            pipWatchController: pipController
        )

        XCTAssertTrue(model.canStartPiPWatch)

        model.startPiPWatch(at: Date(timeIntervalSince1970: 101))

        XCTAssertEqual(pipController.prepareCount, 1)
        XCTAssertEqual(pipController.startCount, 1)
        XCTAssertEqual(pipController.enqueuedFramebuffers, [framebuffer])
        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .watching)
    }

    func testModelReportsPiPUnavailableWhenSystemPiPIsUnsupported() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let pipController = FakePiPWatchController(isSupported: false)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: RFBRawFramebuffer(width: 1, height: 1)
            ),
            pipWatchController: pipController
        )

        XCTAssertFalse(model.canStartPiPWatch)
        XCTAssertEqual(model.pipWatchStatusText, "PiP unavailable on device")

        model.startPiPWatch()

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .unavailable)
        XCTAssertEqual(model.snapshot.pipWatchSession?.safeMessage, "System PiP is unavailable on this device.")
        XCTAssertEqual(pipController.enqueuedFramebuffers, [])
    }

    func testModelFailsPiPWatchWhenInitialFrameCannotBeRendered() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let pipController = FakePiPWatchController(enqueueError: FakePiPWatchError.renderFailed)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: RFBRawFramebuffer(width: 1, height: 1)
            ),
            pipWatchController: pipController
        )

        model.startPiPWatch()

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .failed)
        XCTAssertEqual(model.snapshot.pipWatchSession?.safeMessage, "PiP frame could not be rendered.")
        XCTAssertEqual(pipController.startCount, 0)
    }

    func testModelReportsPiPUnavailableWithoutReceivedFrame() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session
            )
        )

        model.startPiPWatch()

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .unavailable)
        XCTAssertEqual(
            model.snapshot.pipWatchSession?.safeMessage,
            "PiP Watch is available after a remote frame is active."
        )
    }

    func testModelRefreshesAndStopsPiPWatchSession() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            pipWatchController: FakePiPWatchController()
        )

        model.startPiPWatch(at: Date(timeIntervalSince1970: 100))
        model.refreshPiPWatchStaleness(now: Date(timeIntervalSince1970: 109))

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .stale)
        XCTAssertEqual(model.snapshot.pipWatchStatusText, "PiP frame stale")

        model.stopPiPWatch()

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .stopped)
        XCTAssertEqual(model.snapshot.pipWatchStatusText, "PiP Watch ready")
    }

    func testModelSendsComposedTextThroughActiveRFBTextClientAfterConnect() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        model.sendComposedText("한글과 English 😊", pasteCommand: .controlV)

        XCTAssertEqual(connector.clipboardPayloads, ["한글과 English 😊"])
        XCTAssertEqual(connector.pasteCommands, [.controlV])
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .unknown)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
    }

    func testModelRetainsComposedTextWhenSendHasNoActiveConnection() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id)
            )
        )

        model.sendComposedText("로컬에 남아야 하는 문장")

        XCTAssertEqual(model.snapshot.composeDraft?.text, "로컬에 남아야 하는 문장")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
    }

    func testModelEnqueuesStreamingFramesToActivePiPController() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let pipController = FakePiPWatchController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0.05),
            connectorFactory: { connector },
            pipWatchController: pipController
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(40))
        model.startPiPWatch(at: Date(timeIntervalSince1970: 100))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(pipController.enqueuedFramebuffers, [firstFramebuffer, secondFramebuffer])
        XCTAssertEqual(model.snapshot.pipWatchSession?.lastFrame?.changeActivity, .high)
    }

    // MARK: - Per-profile diagnostic verdict cache (UX punch-list #109)

    func testRunConnectionChecksLeavesVerdictUnknownWhileRunIsInFlight() throws {
        // The "running" placeholder run should stamp `.unknown` so
        // the sidebar dot stays neutral until the real attempt
        // resolves — never optimistically green.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id)
        )

        model.runConnectionChecks()

        XCTAssertEqual(model.snapshot.lastDiagnosticVerdict[profile.id], .unknown)
    }

    func testStreamingConnectStampsPassedVerdictForActiveProfile() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(width: 2, height: 1, name: "Desk", framebuffer: framebuffer)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.snapshot.lastDiagnosticVerdict[profile.id], .passed)
    }

    func testCredentialFailureStampsFailedVerdictForActiveProfile() async throws {
        // Credential lookup fails → the catalog-built run finishes
        // immediately with an `.authentication` failure → verdict
        // is `.failed`.
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            credentialRef: "vnc-password:missing"
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(width: 1, height: 1, fill: RFBColor(red: 10, green: 0, blue: 0))
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()

        XCTAssertEqual(model.snapshot.lastDiagnosticVerdict[profile.id], .failed)
    }

    func testFailedConnectExportIncludesDebugSafeFailureContext() async throws {
        let credentialRef = "vnc-password:test"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            port: 5901,
            credentialRef: credentialRef,
            hostKind: .privateAddress
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [credentialRef: "secret"])
        let connector = FakeFirstFrameConnector(
            width: 1,
            height: 1,
            name: "Desk",
            connectError: RFBNetworkClientError.connectionFailed
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(report.schemaVersion, 7)
        XCTAssertEqual(report.verdict, DiagnosticVerdict.failed.rawValue)
        XCTAssertEqual(report.viewerStreamPowerMode, StreamPowerMode.balanced.rawValue)
        XCTAssertEqual(report.profileHostKind, ConnectionProfile.HostKind.privateAddress.rawValue)
        XCTAssertEqual(report.configuredPort, 5901)
        XCTAssertEqual(report.hasCredentialReference, true)
        XCTAssertEqual(report.diagnosticTrigger, DiagnosticRunTrigger.connect.rawValue)
        XCTAssertEqual(report.probeTimeoutSeconds, 8)
        XCTAssertTrue(report.targetFingerprint?.hasPrefix("sha256:") ?? false)
        XCTAssertEqual(report.targetFingerprint?.count, "sha256:".count + 64)
        XCTAssertEqual(report.stageRows.last?.stageID, DiagnosticStage.tcp.rawValue)
        XCTAssertEqual(report.stageRows.last?.failureCode, "network.connectionFailed")
        XCTAssertNil(report.streamPerformance)
        XCTAssertFalse(json.contains("desk.tailnet.ts.net"))
        XCTAssertFalse(json.contains("desk.tailnet.ts.net:5901"))
        XCTAssertFalse(json.contains(credentialRef))
        XCTAssertFalse(json.contains("secret"))
        XCTAssertFalse(json.contains(profile.id.uuidString))
    }

    func testActiveSessionExportIncludesSafeStreamPerformanceSummary() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 2,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 2,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 2,
            height: 2,
            name: "Desk",
            updateResults: [
                .fullFrame(framebuffer: firstFramebuffer),
                RFBFramebufferUpdateResult(
                    framebuffer: secondFramebuffer,
                    dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                    changedPixelCount: 1,
                    timing: RFBFramebufferUpdateTiming(
                        totalMilliseconds: 420,
                        networkReadMilliseconds: 360
                    ),
                    encodingMix: RFBFramebufferEncodingMix(rawRectangles: 1, zrleRectangles: 1)
                )
            ]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector },
            thermalStateProvider: { .fair }
        )
        model.setStreamPowerMode(.powerSaver)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )

        let performance = try XCTUnwrap(report.streamPerformance)
        XCTAssertEqual(report.schemaVersion, 7)
        XCTAssertEqual(report.viewerStreamPowerMode, StreamPowerMode.powerSaver.rawValue)
        XCTAssertEqual(performance.deliveredFrameCount, 2)
        XCTAssertEqual(performance.contentFrameCount, 2)
        XCTAssertEqual(performance.emptyUpdateCount, 0)
        XCTAssertEqual(performance.contentFramePermille, 1_000)
        XCTAssertEqual(performance.dirtyRectangleCountMax, 1)
        XCTAssertEqual(performance.dirtyAreaPermilleMax, 1_000)
        XCTAssertEqual(performance.changedPixelsPermilleMax, 1_000)
        XCTAssertEqual(performance.rendererUploadSampleCount, 2)
        XCTAssertEqual(performance.rendererPartialUploadCount, 1)
        XCTAssertEqual(performance.rendererFullUploadCount, 1)
        XCTAssertEqual(performance.rendererPartialUploadPermille, 500)
        XCTAssertEqual(performance.rendererFullUploadPermille, 500)
        XCTAssertEqual(performance.rendererUploadRegionCountMax, 1)
        XCTAssertEqual(performance.receiveTimingSampleCount, 1)
        XCTAssertEqual(performance.averageReceiveTotalTimingBucket, DiagnosticTimingBucket.stalled.rawValue)
        XCTAssertEqual(performance.maxReceiveTotalTimingBucket, DiagnosticTimingBucket.stalled.rawValue)
        XCTAssertEqual(performance.averageNetworkReadTimingBucket, DiagnosticTimingBucket.stalled.rawValue)
        XCTAssertEqual(performance.maxNetworkReadTimingBucket, DiagnosticTimingBucket.stalled.rawValue)
        XCTAssertEqual(performance.averageClientProcessingTimingBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(performance.maxClientProcessingTimingBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(
            performance.actualEncodingMix,
            RFBFramebufferEncodingMix(rawRectangles: 1, zrleRectangles: 1)
        )
        XCTAssertEqual(performance.thermalState, SessionStreamThermalState.fair.rawValue)
        XCTAssertTrue(json.contains("\"actualEncodingMix\""))
        XCTAssertTrue(json.contains("\"zrleRectangles\" : 1"))
        XCTAssertTrue(json.contains("\"averageReceiveTotalTimingBucket\" : \"stalled\""))
        XCTAssertFalse(json.contains("totalMilliseconds"))
        XCTAssertFalse(json.contains("networkReadMilliseconds"))
        XCTAssertFalse(json.contains("clientProcessingMilliseconds"))
        XCTAssertFalse(json.contains("desk.tailnet.ts.net"))
        XCTAssertFalse(json.contains(profile.id.uuidString))
    }

    func testFailedConnectExportSeparatesTimeoutSource() async throws {
        let connectTimeoutReport = try await failedConnectReport(
            connectError: RFBNetworkClientError.connectTimedOut
        )
        XCTAssertEqual(connectTimeoutReport.stageRows.last?.stageID, DiagnosticStage.tcp.rawValue)
        XCTAssertEqual(connectTimeoutReport.stageRows.last?.failureCode, "network.connectTimedOut")

        let readTimeoutReport = try await failedConnectReport(
            connectError: RFBNetworkClientError.readTimedOut
        )
        XCTAssertEqual(readTimeoutReport.stageRows.last?.stageID, DiagnosticStage.rfbHandshake.rawValue)
        XCTAssertEqual(readTimeoutReport.stageRows.last?.failureCode, "network.readTimedOut")
    }

    private func failedConnectReport(connectError: RFBNetworkClientError) async throws -> DiagnosticCollectionReport {
        let credentialRef = "vnc-password:test-timeout-\(UUID().uuidString)"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "100.126.136.43",
            port: 5900,
            credentialRef: credentialRef,
            hostKind: .privateAddress
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [credentialRef: "secret"])
        let connector = FakeFirstFrameConnector(
            width: 1,
            height: 1,
            name: "Desk",
            connectError: connectError
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        return try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )
    }

    func testVerdictCacheIsScopedPerProfile() async throws {
        // A second profile's selection + diagnostic should not stomp
        // the first profile's recorded verdict — the dict is per-id
        // by design (sidebar shows verdicts for ALL profiles at
        // once).
        let first = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Office", host: "office.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(width: 2, height: 1, name: "Studio", framebuffer: framebuffer)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [first, second],
                selectedProfileID: first.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.snapshot.lastDiagnosticVerdict[first.id], .passed)

        // Switch to the second profile — the first profile's
        // verdict must remain in the cache.
        model.selectProfile(id: second.id)

        XCTAssertEqual(model.snapshot.lastDiagnosticVerdict[first.id], .passed)
        XCTAssertNil(model.snapshot.lastDiagnosticVerdict[second.id])
    }

    func testDeletingProfileEvictsItsVerdictFromTheCache() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            lastDiagnosticVerdict: [profile.id: .passed]
        )
        let model = NaruRemoteAppModel(snapshot: snapshot)
        XCTAssertEqual(model.snapshot.lastDiagnosticVerdict[profile.id], .passed)

        await model.deleteProfile(id: profile.id)

        XCTAssertNil(model.snapshot.lastDiagnosticVerdict[profile.id])
    }

    private func pressureTestFrame(
        totalMilliseconds: Int,
        networkReadMilliseconds: Int,
        isIncremental: Bool = true,
        changedPixelCount: Int = 1,
        transportIdleTimedOut: Bool = false
    ) -> RFBFramePumpFrame {
        RFBFramePumpFrame(
            sequence: 1,
            framebuffer: RFBRawFramebuffer(width: 1, height: 1),
            dirtyRectangles: changedPixelCount == 0 ? [] : [
                RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)
            ],
            changedPixelCount: changedPixelCount,
            isIncremental: isIncremental,
            transportIdleTimedOut: transportIdleTimedOut,
            timing: RFBFramebufferUpdateTiming(
                totalMilliseconds: totalMilliseconds,
                networkReadMilliseconds: networkReadMilliseconds
            )
        )
    }

    private func waitForPersistedStreamPowerMode(
        _ expected: StreamPowerMode,
        in persistence: InMemoryAppSettingsPersistence,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> AppSettings {
        for _ in 0..<20 {
            let settings = try await persistence.load()
            if settings.streamPowerMode == expected {
                return settings
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let settings = try await persistence.load()
        XCTAssertEqual(settings.streamPowerMode, expected, file: file, line: line)
        return settings
    }

    private func waitForRecordedPacingDelays(
        _ expectedCount: Int,
        in pacingSleepRecorder: PacingSleepRecorder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [TimeInterval] {
        for _ in 0..<20 {
            let delays = pacingSleepRecorder.delays
            if delays.count >= expectedCount {
                return delays
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let delays = pacingSleepRecorder.delays
        XCTAssertEqual(delays.count, expectedCount, file: file, line: line)
        return delays
    }
}

private final class PacingSleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDelays: [TimeInterval] = []

    var delays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recordedDelays
    }

    func record(_ delay: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        recordedDelays.append(delay)
    }
}

private enum FakePiPWatchError: Error {
    case renderFailed
}

@MainActor
private final class FakePiPWatchController: PiPWatchControlling {
    let isSupported: Bool
    let enqueueError: Error?
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var enqueuedFramebuffers: [RFBRawFramebuffer] = []

    init(isSupported: Bool = true, enqueueError: Error? = nil) {
        self.isSupported = isSupported
        self.enqueueError = enqueueError
    }

    func prepare() -> Bool {
        prepareCount += 1
        return isSupported
    }

    func enqueue(_ framebuffer: RFBRawFramebuffer) throws {
        if let enqueueError {
            throw enqueueError
        }
        enqueuedFramebuffers.append(framebuffer)
    }

    func start() -> Bool {
        startCount += 1
        return isSupported
    }

    func stop() {
        stopCount += 1
    }
}

private final class FakeFirstFrameConnector: RFBAuthenticatedFirstFrameConnecting, RemoteClipboardTextClient {
    struct Request: Equatable {
        let host: String
        let port: UInt16
    }

    fileprivate struct Recording {
        var recordedRequests: [Request] = []
        var recordedClipboardPayloads: [String] = []
        var recordedPasteCommands: [PasteCommand] = []
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String
    private let connectError: Error?

    init(width: Int, height: Int, name: String, connectError: Error? = nil) {
        self.width = width
        self.height = height
        self.name = name
        self.connectError = connectError
        self.recording = OSAllocatedUnfairLock(initialState: Recording())
    }

    var state: RFBClientState {
        .receivingFrames
    }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    var requests: [Request] {
        recording.withLock { $0.recordedRequests }
    }

    var clipboardPayloads: [String] {
        recording.withLock { $0.recordedClipboardPayloads }
    }

    var pasteCommands: [PasteCommand] {
        recording.withLock { $0.recordedPasteCommands }
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectFirstFrame(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        _ = credential
        recording.withLock { state in
            state.recordedRequests.append(Request(host: host, port: port))
        }

        if let connectError {
            throw connectError
        }

        return RFBServerInit(
            width: width,
            height: height,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: name
        )
    }

    func setClipboardText(_ text: String) throws {
        recording.withLock { state in
            state.recordedClipboardPayloads.append(text)
        }
    }

    func sendPasteCommand(_ command: PasteCommand) throws {
        recording.withLock { state in
            state.recordedPasteCommands.append(command)
        }
    }
}

private final class FakeStreamingConnectorSequence: @unchecked Sendable {
    private let connectors: OSAllocatedUnfairLock<[FakeStreamingConnector]>

    init(_ connectors: [FakeStreamingConnector]) {
        self.connectors = OSAllocatedUnfairLock(initialState: connectors)
    }

    func next() -> RFBFirstFrameConnecting {
        connectors.withLock { connectors in
            connectors.removeFirst()
        }
    }
}

private final class FakeStreamingConnector: RFBStreamingClient, RFBDamageTrackingFramebufferUpdating, RFBFramebufferUpdateReceiving, RFBTransportControlClient, RFBContinuousUpdateCapabilityReporting {
    fileprivate struct Recording {
        var frameUpdates: [RFBFramebufferUpdateResult]
        var recordedSessionRequests: [FakeFirstFrameConnector.Request] = []
        var recordedFrameUpdateRequests: [Bool] = []
        var recordedCredentials: [RFBConnectionCredential] = []
        var recordedClipboardPayloads: [String] = []
        var recordedPasteCommands: [PasteCommand] = []
        var recordedPointerEventsList: [(mask: UInt8, x: UInt16, y: UInt16)] = []
        var renegotiatedPreferences: [RFBEncodingPreference] = []
        var receivedFrameCount = 0
        var continuousUpdateFlags: [Bool] = []
        var initialCanEnableContinuousUpdates: Bool
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String

    var recordedPointerEvents: [(mask: UInt8, x: UInt16, y: UInt16)] {
        recording.withLock { $0.recordedPointerEventsList }
    }

    var renegotiatedPreferences: [RFBEncodingPreference] {
        recording.withLock { $0.renegotiatedPreferences }
    }

    var receivedFrameCount: Int {
        recording.withLock { $0.receivedFrameCount }
    }

    var continuousUpdateFlags: [Bool] {
        recording.withLock { $0.continuousUpdateFlags }
    }

    var canEnableContinuousUpdates: Bool {
        recording.withLock {
            $0.initialCanEnableContinuousUpdates ||
                $0.renegotiatedPreferences.last?.continuousUpdates == true
        }
    }

    init(
        width: Int,
        height: Int,
        name: String,
        framebuffer: RFBRawFramebuffer,
        canEnableContinuousUpdates: Bool = false
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.recording = OSAllocatedUnfairLock(
            initialState: Recording(
                frameUpdates: [.fullFrame(framebuffer: framebuffer)],
                initialCanEnableContinuousUpdates: canEnableContinuousUpdates
            )
        )
    }

    init(
        width: Int,
        height: Int,
        name: String,
        framebuffers: [RFBRawFramebuffer],
        canEnableContinuousUpdates: Bool = false
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.recording = OSAllocatedUnfairLock(
            initialState: Recording(
                frameUpdates: framebuffers.map { .fullFrame(framebuffer: $0) },
                initialCanEnableContinuousUpdates: canEnableContinuousUpdates
            )
        )
    }

    init(
        width: Int,
        height: Int,
        name: String,
        updateResults: [RFBFramebufferUpdateResult],
        canEnableContinuousUpdates: Bool = false
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.recording = OSAllocatedUnfairLock(
            initialState: Recording(
                frameUpdates: updateResults,
                initialCanEnableContinuousUpdates: canEnableContinuousUpdates
            )
        )
    }

    var state: RFBClientState {
        .receivingFrames
    }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    var sessionRequests: [FakeFirstFrameConnector.Request] {
        recording.withLock { $0.recordedSessionRequests }
    }

    var frameUpdateRequests: [Bool] {
        recording.withLock { $0.recordedFrameUpdateRequests }
    }

    var credentials: [RFBConnectionCredential] {
        recording.withLock { $0.recordedCredentials }
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectFirstFrame(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: credential, timeout: timeout)
    }

    func connectNoAuthSession(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectSession(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        recording.withLock { state in
            state.recordedSessionRequests.append(FakeFirstFrameConnector.Request(host: host, port: port))
            state.recordedCredentials.append(credential)
        }

        return RFBServerInit(
            width: width,
            height: height,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: name
        )
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        try requestFramebufferUpdate(
            incremental: incremental,
            timeout: timeout
        ).framebuffer
    }

    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBFramebufferUpdateResult {
        let update = recording.withLock { state -> RFBFramebufferUpdateResult? in
            state.recordedFrameUpdateRequests.append(incremental)
            return state.frameUpdates.isEmpty ? nil : state.frameUpdates.removeFirst()
        }

        guard let update else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }

        return update
    }

    func receiveFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult {
        let update = recording.withLock { state -> RFBFramebufferUpdateResult? in
            state.receivedFrameCount += 1
            return state.frameUpdates.isEmpty ? nil : state.frameUpdates.removeFirst()
        }

        guard let update else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }

        return update
    }

    func setClipboardText(_ text: String) throws {
        recording.withLock { state in
            state.recordedClipboardPayloads.append(text)
        }
    }

    func sendPasteCommand(_ command: PasteCommand) throws {
        recording.withLock { state in
            state.recordedPasteCommands.append(command)
        }
    }

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        recording.withLock { state in
            state.recordedPointerEventsList.append((buttonMask, x, y))
        }
    }

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        // Key events are out of scope for the existing app-model
        // pointer / clipboard tests; Direct Keystroke Mode tests live
        // in DirectKeystrokeModeTests.swift.
    }

    func renegotiateEncodings(_ preference: RFBEncodingPreference, timeout: TimeInterval) throws {
        recording.withLock { state in
            state.renegotiatedPreferences.append(preference)
        }
    }

    func enableContinuousUpdates(
        _ enabled: Bool,
        region: RFBFramebufferUpdateRegion?,
        timeout: TimeInterval
    ) throws {
        recording.withLock { state in
            state.continuousUpdateFlags.append(enabled)
        }
    }

    func sendFence(flags: RFBFenceFlags, payload: Data, timeout: TimeInterval) throws {
        // Fence behavior is covered at the RFB transport boundary.
    }
}
