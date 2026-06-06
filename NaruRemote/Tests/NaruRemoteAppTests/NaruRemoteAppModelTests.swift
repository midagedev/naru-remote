import Foundation
import os
import XCTest
import NaruHelperKit
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class NaruRemoteAppModelTests: XCTestCase {
    func testDefaultFrameStreamConfigurationCapsActiveCadenceForSustainedPhoneUse() {
        let configuration = NaruRemoteAppModel.defaultFrameStreamConfiguration

        XCTAssertEqual(configuration.requestTimeout, 8)
        XCTAssertEqual(
            configuration.frameInterval,
            StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds,
            accuracy: 0.0001,
            "Default live sessions should cap active frame requests at the benchmark-backed sustained cadence."
        )
        XCTAssertEqual(configuration.idleFrameInterval, 0.05)
        XCTAssertEqual(configuration.updateMode, .continuousUpdates)
    }

    func testStartupPreflightPolicyClampsHiddenFramesForAppSafety() {
        XCTAssertEqual(SessionStreamStartupPreflightPolicy.disabled.hiddenFrameCount, 0)
        XCTAssertEqual(SessionStreamStartupPreflightPolicy.maximumHiddenFrameCount, 1)
        XCTAssertEqual(SessionStreamStartupPreflightPolicy(hiddenFrameCount: -1).hiddenFrameCount, 0)
        XCTAssertEqual(SessionStreamStartupPreflightPolicy(hiddenFrameCount: 2).hiddenFrameCount, 1)
        XCTAssertEqual(SessionStreamStartupPreflightPolicy(hiddenFrameCount: 1, requestTimeout: -1).requestTimeout, 0)
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

    func testSessionStreamPacingPolicyBacksOffForViewportInteraction() {
        let contentDecision = SessionStreamPacingPolicy.decision(
            for: .contentFrame,
            configuredDelay: 1.0 / 60.0,
            thermalState: .nominal,
            usesViewportInteractionPacing: true
        )
        XCTAssertEqual(
            contentDecision.delay,
            StreamPressurePacingDefaults.viewportInteractionContentFrameIntervalSeconds,
            accuracy: 0.0001
        )
        XCTAssertFalse(contentDecision.usesThermalPacing)
        XCTAssertFalse(contentDecision.usesPowerSaverPacing)
        XCTAssertFalse(contentDecision.usesEmptyBackoffPacing)
        XCTAssertTrue(contentDecision.usesViewportInteractionPacing)

        let emptyDecision = SessionStreamPacingPolicy.decision(
            for: .emptyUpdate,
            configuredDelay: 0.05,
            thermalState: .nominal,
            usesViewportInteractionPacing: true,
            emptyUpdateStreak: 1
        )
        XCTAssertEqual(
            emptyDecision.delay,
            StreamPressurePacingDefaults.viewportInteractionIdleFrameIntervalSeconds,
            accuracy: 0.0001
        )
        XCTAssertTrue(emptyDecision.usesViewportInteractionPacing)

        XCTAssertEqual(
            SessionStreamPacingPolicy.delay(
                for: .contentFrame,
                configuredDelay: 0,
                thermalState: .nominal,
                usesViewportInteractionPacing: true
            ),
            0,
            accuracy: 0.0001,
            "Opt-in fake/test streams that remove pacing should stay deterministic."
        )
    }

    func testSessionStreamPacingDecisionClassifiesActiveFloor() {
        let thermal = SessionStreamPacingPolicy.decision(
            for: .contentFrame,
            configuredDelay: 1.0 / 30.0,
            thermalState: .serious
        )
        XCTAssertEqual(thermal.delay, 1.0 / 15.0, accuracy: 0.0001)
        XCTAssertTrue(thermal.usesThermalPacing)
        XCTAssertFalse(thermal.usesPowerSaverPacing)
        XCTAssertFalse(thermal.usesEmptyBackoffPacing)
        XCTAssertFalse(thermal.usesViewportInteractionPacing)

        let powerSaver = SessionStreamPacingPolicy.decision(
            for: .emptyUpdate,
            configuredDelay: 0.05,
            thermalState: .nominal,
            usesPowerSaverPacing: true,
            emptyUpdateStreak: 1
        )
        XCTAssertEqual(powerSaver.delay, 0.125, accuracy: 0.0001)
        XCTAssertFalse(powerSaver.usesThermalPacing)
        XCTAssertTrue(powerSaver.usesPowerSaverPacing)
        XCTAssertFalse(powerSaver.usesEmptyBackoffPacing)
        XCTAssertFalse(powerSaver.usesViewportInteractionPacing)

        let emptyBackoff = SessionStreamPacingPolicy.decision(
            for: .emptyUpdate,
            configuredDelay: 0.05,
            thermalState: .nominal,
            emptyUpdateStreak: 8
        )
        XCTAssertEqual(emptyBackoff.delay, 0.075, accuracy: 0.0001)
        XCTAssertFalse(emptyBackoff.usesThermalPacing)
        XCTAssertFalse(emptyBackoff.usesPowerSaverPacing)
        XCTAssertTrue(emptyBackoff.usesEmptyBackoffPacing)
        XCTAssertFalse(emptyBackoff.usesViewportInteractionPacing)

        let tiedFloors = SessionStreamPacingPolicy.decision(
            for: .emptyUpdate,
            configuredDelay: 0.05,
            thermalState: .serious,
            usesPowerSaverPacing: true,
            emptyUpdateStreak: 1
        )
        XCTAssertEqual(tiedFloors.delay, 0.125, accuracy: 0.0001)
        XCTAssertTrue(tiedFloors.usesThermalPacing)
        XCTAssertTrue(tiedFloors.usesPowerSaverPacing)
        XCTAssertFalse(tiedFloors.usesEmptyBackoffPacing)
        XCTAssertFalse(tiedFloors.usesViewportInteractionPacing)

        let overriddenBackoff = SessionStreamPacingPolicy.decision(
            for: .emptyUpdate,
            configuredDelay: 0.05,
            thermalState: .serious,
            emptyUpdateStreak: 8
        )
        XCTAssertEqual(overriddenBackoff.delay, 0.125, accuracy: 0.0001)
        XCTAssertTrue(overriddenBackoff.usesThermalPacing)
        XCTAssertFalse(overriddenBackoff.usesPowerSaverPacing)
        XCTAssertFalse(overriddenBackoff.usesEmptyBackoffPacing)
        XCTAssertFalse(overriddenBackoff.usesViewportInteractionPacing)
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

    func testSessionStreamPressurePacingStateActivatesAfterRepeatedLaggingAppApply() {
        var state = SessionStreamPressurePacingState()
        let fastFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10
        )

        state.record(frame: fastFrame, appFrameApplyMilliseconds: 95)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        state.record(frame: fastFrame, appFrameApplyMilliseconds: 95)
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        state.record(frame: fastFrame, appFrameApplyMilliseconds: 95)
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateActivatesAfterSingleVerySlowLocalWorkFrame() {
        var state = SessionStreamPressurePacingState()
        let frame = pressureTestFrame(
            totalMilliseconds: 1_240,
            networkReadMilliseconds: 20
        )

        state.record(frame: frame)

        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)

        let fastFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10
        )
        for _ in 0..<SessionStreamPressurePacingState.verySlowAdaptiveRecoveryUpdateCount {
            state.record(frame: fastFrame)
        }
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        XCTAssertLessThan(
            SessionStreamPressurePacingState.verySlowAdaptiveRecoveryUpdateCount,
            SessionStreamPressurePacingState.adaptiveRecoveryUpdateCount
        )
    }

    func testSessionStreamPressurePacingStateActivatesAfterSustainedModerateClientProcessing() {
        var state = SessionStreamPressurePacingState()
        let moderateFrame = pressureTestFrame(
            totalMilliseconds: 55,
            networkReadMilliseconds: 15
        )

        for _ in 0..<(SessionStreamPressurePacingState.consecutiveSustainedLaggingContentFrameThreshold - 1) {
            state.record(frame: moderateFrame)
            XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        }

        state.record(frame: moderateFrame)

        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateActivatesAfterSustainedModerateAppApply() {
        var state = SessionStreamPressurePacingState()
        let fastFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10
        )

        for _ in 0..<(SessionStreamPressurePacingState.consecutiveSustainedLaggingContentFrameThreshold - 1) {
            state.record(frame: fastFrame, appFrameApplyMilliseconds: 40)
            XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        }

        state.record(frame: fastFrame, appFrameApplyMilliseconds: 40)

        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateActivatesAfterSustainedFullUploadFrames() {
        var state = SessionStreamPressurePacingState()
        let fullUploadFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10,
            changedPixelCount: 8_000,
            dirtyRectangles: [
                RFBFrameDamageRect(x: 0, y: 0, width: 100, height: 80)
            ]
        )

        for _ in 0..<(SessionStreamPressurePacingState.consecutiveFullUploadContentFrameThreshold - 1) {
            state.record(frame: fullUploadFrame)
            XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
        }

        state.record(frame: fullUploadFrame)

        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateBreaksModerateStreakOnHealthyContentFrame() {
        var state = SessionStreamPressurePacingState()
        let moderateFrame = pressureTestFrame(
            totalMilliseconds: 55,
            networkReadMilliseconds: 15
        )
        let healthyFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10
        )

        for _ in 0..<(SessionStreamPressurePacingState.consecutiveSustainedLaggingContentFrameThreshold - 1) {
            state.record(frame: moderateFrame)
        }
        state.record(frame: healthyFrame)
        state.record(frame: moderateFrame)

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

    func testModelLoadsStoredStartupPreflightMode() async throws {
        let persistence = InMemoryAppSettingsPersistence(
            settings: AppSettings(startupPreflightMode: .oneHiddenFrame)
        )
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        await model.loadStoredSettings()

        XCTAssertEqual(model.appSettings.startupPreflightMode, .oneHiddenFrame)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testModelLoadsStoredStreamEncodingMode() async throws {
        let persistence = InMemoryAppSettingsPersistence(
            settings: AppSettings(streamEncodingMode: .zrleCompressionZero)
        )
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        await model.loadStoredSettings()

        XCTAssertEqual(model.appSettings.streamEncodingMode, .zrleCompressionZero)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testModelLoadsStoredStartupGlanceScaleMode() async throws {
        let persistence = InMemoryAppSettingsPersistence(
            settings: AppSettings(startupGlanceScaleMode: .glance025)
        )
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        await model.loadStoredSettings()

        XCTAssertEqual(model.appSettings.startupGlanceScaleMode, .glance025)
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

    func testModelPersistsStartupPreflightModeToggle() async throws {
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        model.toggleStartupPreflightMode()

        let savedEnabledSettings = try await waitForPersistedStartupPreflightMode(
            .oneHiddenFrame,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.startupPreflightMode, .oneHiddenFrame)
        XCTAssertEqual(savedEnabledSettings.startupPreflightMode, .oneHiddenFrame)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStartupPreflightMode()

        let savedDisabledSettings = try await waitForPersistedStartupPreflightMode(
            .disabled,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.startupPreflightMode, .disabled)
        XCTAssertEqual(savedDisabledSettings.startupPreflightMode, .disabled)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testModelPersistsStreamEncodingModeToggle() async throws {
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        model.toggleStreamEncodingMode()

        let savedTightCursorSettings = try await waitForPersistedStreamEncodingMode(
            .tightFirstCursor,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.streamEncodingMode, .tightFirstCursor)
        XCTAssertEqual(savedTightCursorSettings.streamEncodingMode, .tightFirstCursor)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStreamEncodingMode()

        let savedLocalRGB565Settings = try await waitForPersistedStreamEncodingMode(
            .localLowLatencyRGB565,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.streamEncodingMode, .localLowLatencyRGB565)
        XCTAssertEqual(savedLocalRGB565Settings.streamEncodingMode, .localLowLatencyRGB565)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStreamEncodingMode()

        let savedZrleSettings = try await waitForPersistedStreamEncodingMode(
            .zrleCompressionZero,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.streamEncodingMode, .zrleCompressionZero)
        XCTAssertEqual(savedZrleSettings.streamEncodingMode, .zrleCompressionZero)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStreamEncodingMode()

        let savedRGB565Settings = try await waitForPersistedStreamEncodingMode(
            .zrleCompressionZeroRGB565,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.streamEncodingMode, .zrleCompressionZeroRGB565)
        XCTAssertEqual(savedRGB565Settings.streamEncodingMode, .zrleCompressionZeroRGB565)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStreamEncodingMode()

        let savedAdaptiveSettings = try await waitForPersistedStreamEncodingMode(
            .adaptiveGoodFull,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.streamEncodingMode, .adaptiveGoodFull)
        XCTAssertEqual(savedAdaptiveSettings.streamEncodingMode, .adaptiveGoodFull)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStreamEncodingMode()

        let savedStandardSettings = try await waitForPersistedStreamEncodingMode(
            .standard,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.streamEncodingMode, .standard)
        XCTAssertEqual(savedStandardSettings.streamEncodingMode, .standard)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testModelPersistsStartupGlanceScaleModeToggle() async throws {
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        model.toggleStartupGlanceScaleMode()

        let savedMinimalSettings = try await waitForPersistedStartupGlanceScaleMode(
            .minimal035,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.startupGlanceScaleMode, .minimal035)
        XCTAssertEqual(savedMinimalSettings.startupGlanceScaleMode, .minimal035)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStartupGlanceScaleMode()

        let savedGlanceSettings = try await waitForPersistedStartupGlanceScaleMode(
            .glance025,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.startupGlanceScaleMode, .glance025)
        XCTAssertEqual(savedGlanceSettings.startupGlanceScaleMode, .glance025)
        XCTAssertNil(model.settingsPersistenceError)

        model.toggleStartupGlanceScaleMode()

        let savedStandardSettings = try await waitForPersistedStartupGlanceScaleMode(
            .standard045,
            in: persistence
        )
        XCTAssertEqual(model.appSettings.startupGlanceScaleMode, .standard045)
        XCTAssertEqual(savedStandardSettings.startupGlanceScaleMode, .standard045)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testStartupGlanceScaleControlAvailabilityMatchesInitialRegionPolicy() {
        let model = NaruRemoteAppModel(lowPowerModeProvider: { false })

        XCTAssertFalse(model.canUseStartupGlanceScaleMode)

        model.setStreamEncodingMode(.localLowLatencyRGB565)
        XCTAssertTrue(model.canUseStartupGlanceScaleMode)

        model.setStreamPowerMode(.powerSaver)
        XCTAssertFalse(model.canUseStartupGlanceScaleMode)
    }

    func testStartupGlanceScaleControlHidesDuringSystemLowPowerMode() {
        let model = NaruRemoteAppModel(lowPowerModeProvider: { true })

        model.setStreamEncodingMode(.localLowLatencyRGB565)

        XCTAssertFalse(model.canUseStartupGlanceScaleMode)
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

    func testModelSavesHelperPairingSecretInCredentialStoreAndKeepsOnlyReferenceInProfile() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: nil,
                port: naruHelperTextBridgeDefaultPort,
                pairingSecretRef: nil,
                pairingFingerprint: "sha256:helper-fingerprint"
            )
        )

        await model.addProfile(profile, helperPairingSecret: " helper-secret ")

        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let helperConfiguration = try XCTUnwrap(savedProfile.helperTextBridge)
        let credentialRef = try XCTUnwrap(helperConfiguration.pairingSecretRef)
        let storedSecret = try await credentialStore.password(for: credentialRef)
        XCTAssertEqual(storedSecret, "helper-secret")
        XCTAssertFalse(credentialRef.contains("helper-secret"))
        XCTAssertEqual(helperConfiguration.resolvedHost(fallback: savedProfile.host), "desk.tailnet.ts.net")
        let state = try XCTUnwrap(model.snapshot.helperTextBridgeState[profile.id])
        XCTAssertEqual(state.isEnabled, true)
        XCTAssertNotEqual(state.availability, .reachable)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testModelDeletesHelperPairingSecretWhenHelperIsRemovedFromProfile() async throws {
        let helperSecretRef = "helper-token:desk"
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [helperSecretRef: "helper-secret"])
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                port: naruHelperTextBridgeDefaultPort,
                pairingSecretRef: helperSecretRef,
                pairingFingerprint: "sha256:helper-fingerprint"
            )
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore
        )
        let updatedProfile = try ConnectionProfile(
            id: profile.id,
            displayName: profile.displayName,
            host: profile.host,
            port: profile.port
        )

        await model.editProfile(updatedProfile, password: nil, helperPairingSecret: "")

        XCTAssertNil(model.snapshot.selectedProfile?.helperTextBridge)
        XCTAssertNil(model.snapshot.helperTextBridgeState[profile.id])
        let storedSecret = try await credentialStore.password(for: helperSecretRef)
        XCTAssertNil(storedSecret)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testModelInitializesStoredHelperTextBridgeStateWhenLoadingProfiles() async throws {
        let helperSecretRef = "helper-token:desk"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                port: naruHelperTextBridgeDefaultPort,
                pairingSecretRef: helperSecretRef,
                pairingFingerprint: "sha256:helper-fingerprint"
            )
        )
        let persistence = InMemoryConnectionProfilePersistence(profiles: [profile])
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)

        await model.loadStoredProfiles()

        XCTAssertEqual(model.snapshot.selectedProfile?.id, profile.id)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.isEnabled, false)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .notConfigured)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .notConfigured)
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.pairingFingerprint,
            "sha256:helper-fingerprint"
        )
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
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
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
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(model.connectionQuality, .good)
        XCTAssertEqual(connector.renegotiatedPreferences, [])
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
            lowPowerModeProvider: { false },
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

    func testModelRenegotiatesConfiguredZrleStreamEncodingOnConnect() async throws {
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
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.zrleCompressionZero)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(
            connector.renegotiatedPreferences,
            [RFBEncodingPreference(zrle: true, compressionLevel: 0)]
        )
    }

    func testModelBuildsRGB565LowTrafficStreamConnectorOnConnect() async throws {
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
        let connectorFactory = RecordingStreamConnectorFactory(connector: connector)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            streamConnectorFactory: { encodingPreference, pixelFormatPreference in
                connectorFactory.make(
                    encodingPreference: encodingPreference,
                    pixelFormatPreference: pixelFormatPreference
                )
            },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.zrleCompressionZeroRGB565)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(
            connectorFactory.calls,
            [
                RecordingStreamConnectorFactory.Call(
                    encodingPreference: RFBEncodingPreference(zrle: true, compressionLevel: 0),
                    pixelFormatPreference: .rgb565In32LittleEndian
                )
            ]
        )
        XCTAssertEqual(connector.renegotiatedPreferences, [])
    }

    func testModelBuildsTightCursorStreamConnectorOnConnect() async throws {
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
        let connectorFactory = RecordingStreamConnectorFactory(connector: connector)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            streamConnectorFactory: { encodingPreference, pixelFormatPreference in
                connectorFactory.make(
                    encodingPreference: encodingPreference,
                    pixelFormatPreference: pixelFormatPreference
                )
            },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.tightFirstCursor)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(
            connectorFactory.calls,
            [
                RecordingStreamConnectorFactory.Call(
                    encodingPreference: .tightFirstCursor,
                    pixelFormatPreference: nil
                )
            ]
        )
        XCTAssertEqual(connector.renegotiatedPreferences, [])
    }

    func testModelBuildsLocalLowLatencyRGB565StreamConnectorOnConnect() async throws {
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
        let connectorFactory = RecordingStreamConnectorFactory(connector: connector)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            streamConnectorFactory: { encodingPreference, pixelFormatPreference in
                connectorFactory.make(
                    encodingPreference: encodingPreference,
                    pixelFormatPreference: pixelFormatPreference
                )
            },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.localLowLatencyRGB565)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(
            connectorFactory.calls,
            [
                RecordingStreamConnectorFactory.Call(
                    encodingPreference: .localLowLatency,
                    pixelFormatPreference: .rgb565In32LittleEndian
                )
            ]
        )
        XCTAssertEqual(connector.renegotiatedPreferences, [])
    }

    func testModelKeepsFullIncrementalStreamRequestsInStandardProfile() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1_000,
            height: 1_000,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 2,
                requestTimeout: 1,
                frameInterval: 0.2,
                idleFrameInterval: 0
            ),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))
        model.updateViewportTransform(
            ViewportTransform(
                framebufferSize: CGSize(width: 1_000, height: 1_000),
                viewSize: CGSize(width: 500, height: 500),
                zoomScale: 2
            )
        )
        try await Task.sleep(for: .milliseconds(260))

        XCTAssertEqual(connector.frameUpdateRequests, [false, true])
        XCTAssertEqual(connector.frameUpdateRegions, [nil, nil])
    }

    func testModelKeepsFullInitialStreamRequestInStandardProfile() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1_000,
            height: 1_000,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.updateViewportTransform(
            ViewportTransform(
                framebufferSize: CGSize(width: 1_000, height: 1_000),
                viewSize: CGSize(width: 500, height: 500),
                zoomScale: 2
            )
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(connector.frameUpdateRegions, [nil])
    }

    func testModelRequestsVisibleViewportRegionForLowTrafficIncrementalStreamFrames() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1_000,
            height: 1_000,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 2,
                requestTimeout: 1,
                frameInterval: 0.2,
                idleFrameInterval: 0
            ),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.zrleCompressionZeroRGB565)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))
        model.updateViewportTransform(
            ViewportTransform(
                framebufferSize: CGSize(width: 1_000, height: 1_000),
                viewSize: CGSize(width: 500, height: 500),
                zoomScale: 2
            )
        )
        try await Task.sleep(for: .milliseconds(260))

        XCTAssertEqual(connector.frameUpdateRequests, [false, true])
        XCTAssertEqual(
            connector.frameUpdateRegions,
            [
                nil,
                RFBFramebufferUpdateRegion(x: 186, y: 186, width: 628, height: 628)
            ]
        )
    }

    func testModelRequestsVisibleViewportRegionForLowTrafficInitialStreamFrame() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1_000,
            height: 1_000,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.zrleCompressionZeroRGB565)
        model.updateViewportTransform(
            ViewportTransform(
                framebufferSize: CGSize(width: 1_000, height: 1_000),
                viewSize: CGSize(width: 500, height: 500),
                zoomScale: 2
            )
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(
            connector.frameUpdateRegions,
            [
                RFBFramebufferUpdateRegion(x: 387, y: 387, width: 225, height: 225)
            ]
        )
    }

    func testModelRequestsVisibleViewportRegionForLocalRGB565InitialStreamFrame() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1_000,
            height: 1_000,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.localLowLatencyRGB565)
        model.updateViewportTransform(
            ViewportTransform(
                framebufferSize: CGSize(width: 1_000, height: 1_000),
                viewSize: CGSize(width: 500, height: 500),
                zoomScale: 2
            )
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(
            connector.frameUpdateRegions,
            [
                RFBFramebufferUpdateRegion(x: 387, y: 387, width: 225, height: 225)
            ]
        )
    }

    func testStartupGlanceScaleModeChangesLowTrafficInitialStreamRegion() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1_000,
            height: 1_000,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.localLowLatencyRGB565)
        model.setStartupGlanceScaleMode(.glance025)
        model.updateViewportTransform(
            ViewportTransform(
                framebufferSize: CGSize(width: 1_000, height: 1_000),
                viewSize: CGSize(width: 500, height: 500),
                zoomScale: 2
            )
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(
            connector.frameUpdateRegions,
            [
                RFBFramebufferUpdateRegion(x: 437, y: 437, width: 125, height: 125)
            ]
        )
    }

    func testModelUsesViewportSizeForLowTrafficInitialStreamFrameWithoutPriorFramebuffer() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1_920,
            height: 1_080,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1_920,
            height: 1_080,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.zrleCompressionZeroRGB565)
        model.updateViewportSize(CGSize(width: 390, height: 844))

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(connector.frameUpdateRequests, [false])
        let region = try XCTUnwrap(connector.frameUpdateRegions.first ?? nil)
        XCTAssertGreaterThan(region.x, 0)
        XCTAssertGreaterThan(region.y, 0)
        XCTAssertLessThan(region.width, 1_920)
        XCTAssertLessThan(region.height, 1_080)
    }

    func testModelKeepsFullLowTrafficInitialRequestWhenViewportDoesNotMatchServer() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1_000,
            height: 1_000,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1_000,
            height: 1_000,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.zrleCompressionZeroRGB565)
        model.updateViewportTransform(
            ViewportTransform(
                framebufferSize: CGSize(width: 2_000, height: 1_000),
                viewSize: CGSize(width: 500, height: 500),
                zoomScale: 2
            )
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(connector.frameUpdateRegions, [nil])
    }

    func testModelLetsPowerSaverOverrideRGB565LowTrafficStreamConnectorOnConnect() async throws {
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
        let connectorFactory = RecordingStreamConnectorFactory(connector: connector)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            streamConnectorFactory: { encodingPreference, pixelFormatPreference in
                connectorFactory.make(
                    encodingPreference: encodingPreference,
                    pixelFormatPreference: pixelFormatPreference
                )
            },
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.zrleCompressionZeroRGB565)
        model.setStreamPowerMode(.powerSaver)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(
            connectorFactory.calls,
            [
                RecordingStreamConnectorFactory.Call(
                    encodingPreference: .powerSaverSustained,
                    pixelFormatPreference: nil
                )
            ]
        )
        XCTAssertEqual(connector.renegotiatedPreferences, [])
    }

    func testModelLetsPowerSaverStreamModeOverrideConfiguredEncodingOnConnect() async throws {
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
            lowPowerModeProvider: { false }
        )
        model.setStreamEncodingMode(.adaptiveGoodFull)
        model.setStreamPowerMode(.powerSaver)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(connector.renegotiatedPreferences, [.powerSaverSustained])
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
            width: 10,
            height: 10,
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
        XCTAssertEqual(model.snapshot.sessionStreamStats.adaptiveClientPressurePacingSampleCount, 2)
        let performance = try XCTUnwrap(model.makeDiagnosticExport().streamPerformance)
        XCTAssertEqual(performance.adaptiveClientPressurePacingSampleCount, 2)
        XCTAssertEqual(performance.adaptiveClientPressurePacingPermille, 500)
        XCTAssertEqual(performance.appFrameApplyTimingSampleCount, 4)
        XCTAssertEqual(performance.streamPacingDelaySampleCount, 4)
        XCTAssertEqual(performance.averageStreamPacingDelayBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(performance.maxStreamPacingDelayBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(performance.powerSaverPacingSampleCount, 2)
        XCTAssertEqual(performance.thermalPacingSampleCount, 0)
        XCTAssertEqual(performance.emptyBackoffPacingSampleCount, 0)
        model.disconnect()
        try await Task.sleep(for: .milliseconds(10))
    }

    func testModelKeepsFrameRequestsAliveWithViewportInteractionPacing() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 10,
            height: 10,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let updates = (0..<3).map { _ in
            RFBFramebufferUpdateResult(
                framebuffer: framebuffer,
                dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                changedPixelCount: 1
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
                maxFrames: 3,
                frameInterval: 1.0 / 60.0,
                idleFrameInterval: 0.05
            ),
            connectorFactory: { connector },
            thermalStateProvider: { .nominal },
            lowPowerModeProvider: { false },
            streamPacingSleep: { delay in
                pacingSleepRecorder.record(delay)
                try await Task.sleep(for: .milliseconds(40))
            }
        )

        await model.connectSelectedProfile()
        _ = try await waitForRecordedPacingDelays(
            1,
            in: pacingSleepRecorder
        )
        model.setViewportInteractionActive(true)
        let delays = try await waitForRecordedPacingDelays(3, in: pacingSleepRecorder)

        model.setViewportInteractionActive(false)
        XCTAssertEqual(delays[0], 1.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(
            delays[1],
            ViewportInteractionFramePublishPolicy.partialUploadContentFrameIntervalSeconds,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            delays[2],
            ViewportInteractionFramePublishPolicy.partialUploadContentFrameIntervalSeconds,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(
            connector.frameUpdateRequests.count,
            1,
            "Viewport interaction should keep bounded live frame requests instead of freezing the remote stream."
        )
        let performance = try XCTUnwrap(model.makeDiagnosticExport().streamPerformance)
        XCTAssertEqual(performance.streamPacingDelaySampleCount, 3)
        XCTAssertEqual(performance.viewportInteractionPacingSampleCount, 2)
        XCTAssertEqual(performance.viewportInteractionRequestPauseCount, 0)
        XCTAssertEqual(performance.viewportInteractionRequestPausePollCount, 0)
        XCTAssertEqual(
            performance.averageViewportInteractionRequestPauseBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxViewportInteractionRequestPauseBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.viewportRequestPauseHint,
            DiagnosticViewportRequestPauseHint.notMeasured.rawValue
        )
        XCTAssertEqual(performance.powerSaverPacingSampleCount, 0)
        XCTAssertEqual(performance.thermalPacingSampleCount, 0)
        model.disconnect()
        try await Task.sleep(for: .milliseconds(10))
    }

    func testDirectViewportInteractionDefersPartialFramesUntilGestureSettles() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 10,
            height: 10,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 10,
            height: 10,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let thirdFramebuffer = RFBRawFramebuffer(
            width: 10,
            height: 10,
            fill: RFBColor(red: 30, green: 0, blue: 0)
        )
        let updates = [firstFramebuffer, secondFramebuffer, thirdFramebuffer].map { framebuffer in
            RFBFramebufferUpdateResult(
                framebuffer: framebuffer,
                dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                changedPixelCount: 1
            )
        }
        let connector = FakeStreamingConnector(
            width: 10,
            height: 10,
            name: "Desk",
            updateResults: updates
        )
        let pacingSleepRecorder = PacingSleepRecorder()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 3,
                frameInterval: 1.0 / 60.0,
                idleFrameInterval: 0.05
            ),
            connectorFactory: { connector },
            thermalStateProvider: { .nominal },
            lowPowerModeProvider: { false },
            streamPacingSleep: { delay in
                pacingSleepRecorder.record(delay)
                try await Task.sleep(for: .milliseconds(40))
            }
        )

        await model.connectSelectedProfile()
        _ = try await waitForRecordedPacingDelays(1, in: pacingSleepRecorder)
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)

        model.setViewportInteractionActive(true, frameStrategy: .deferUntilSettled)
        let delays = try await waitForRecordedPacingDelays(3, in: pacingSleepRecorder)

        XCTAssertEqual(
            delays[1],
            ViewportInteractionFramePublishPolicy.fullUploadContentFrameIntervalSeconds,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            model.snapshot.latestFramebuffer,
            firstFramebuffer,
            "Direct pinch/pan should keep even partial remote frames deferred so texture uploads and SwiftUI publication do not compete with local navigation."
        )

        model.setViewportInteractionActive(false)
        for _ in 0..<120 where model.snapshot.latestFramebuffer != thirdFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.snapshot.latestFramebuffer, thirdFramebuffer)
        model.disconnect()
        try await Task.sleep(for: .milliseconds(10))
    }

    func testViewportInteractionFramePublishPolicyPublishesOnlyBoundedPartialFrames() {
        let current = RFBRawFramebuffer(
            width: 10,
            height: 10,
            fill: RFBColor(red: 1, green: 0, blue: 0)
        )
        let partialFrame = RFBFramePumpFrame(
            sequence: 2,
            framebuffer: RFBRawFramebuffer(
                width: 10,
                height: 10,
                fill: RFBColor(red: 2, green: 0, blue: 0)
            ),
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 2, height: 2)],
            changedPixelCount: 4,
            capturedAt: Date(timeIntervalSince1970: 10),
            isIncremental: true
        )
        let fullFrame = RFBFramePumpFrame(
            sequence: 3,
            framebuffer: RFBRawFramebuffer(
                width: 10,
                height: 10,
                fill: RFBColor(red: 3, green: 0, blue: 0)
            ),
            dirtyRectangles: nil,
            changedPixelCount: 100,
            capturedAt: Date(timeIntervalSince1970: 10),
            isIncremental: false
        )

        let partialPlan = ViewportInteractionFramePublishPolicy.uploadPlan(
            for: partialFrame,
            currentFramebuffer: current
        )
        let fullPlan = ViewportInteractionFramePublishPolicy.uploadPlan(
            for: fullFrame,
            currentFramebuffer: current
        )
        let interactionStartedAt = Date(timeIntervalSince1970: 10)

        XCTAssertEqual(partialPlan.strategy, FramebufferUploadStrategy.partial)
        XCTAssertEqual(fullPlan.strategy, FramebufferUploadStrategy.full)
        XCTAssertTrue(
            ViewportInteractionFramePublishPolicy.shouldPublish(
                uploadPlan: partialPlan,
                capturedAt: partialFrame.capturedAt,
                lastPublishedAt: nil,
                interactionStartedAt: interactionStartedAt
            ),
            "Small dirty-rect updates should be allowed through so remote cursor/text echo does not freeze during pinch/pan."
        )
        XCTAssertFalse(
            ViewportInteractionFramePublishPolicy.shouldPublish(
                uploadPlan: fullPlan,
                capturedAt: fullFrame.capturedAt,
                lastPublishedAt: nil,
                interactionStartedAt: interactionStartedAt
            ),
            "Full uploads should still be coalesced at gesture start to protect touch tracking."
        )
        XCTAssertTrue(
            ViewportInteractionFramePublishPolicy.shouldPublish(
                uploadPlan: fullPlan,
                capturedAt: interactionStartedAt.addingTimeInterval(
                    ViewportInteractionFramePublishPolicy.fullUploadContentFrameIntervalSeconds
                ),
                lastPublishedAt: nil,
                interactionStartedAt: interactionStartedAt
            ),
            "Full-frame-only servers should still get bounded refresh slots during a long pinch/pan."
        )
        XCTAssertFalse(
            ViewportInteractionFramePublishPolicy.shouldPublish(
                uploadPlan: partialPlan,
                capturedAt: Date(timeIntervalSince1970: 10.02),
                lastPublishedAt: Date(timeIntervalSince1970: 10),
                interactionStartedAt: interactionStartedAt
            )
        )
        XCTAssertTrue(
            ViewportInteractionFramePublishPolicy.shouldPublish(
                uploadPlan: partialPlan,
                capturedAt: Date(timeIntervalSince1970: 10.07),
                lastPublishedAt: Date(timeIntervalSince1970: 10),
                interactionStartedAt: interactionStartedAt
            )
        )
    }

    func testModelKeepsBalancedEncodingProfileWithoutPowerSaverSignal() async throws {
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
            framebuffers: [framebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(connector.renegotiatedPreferences, [])
    }

    func testModelRenegotiatesPowerSaverSustainedEncodingProfile() async throws {
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
            framebuffers: [framebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.setStreamPowerMode(.powerSaver)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(connector.renegotiatedPreferences, [.powerSaverSustained])
        let list = try XCTUnwrap(connector.renegotiatedPreferences.first).encodingList()
        XCTAssertEqual(list.first, RFBEncoding.zrle)
        XCTAssertTrue(list.contains(RFBEncoding.cursor))
        XCTAssertTrue(list.contains(RFBEncoding.tightCompressionLevel(0)))
    }

    func testModelRenegotiatesPowerSaverSustainedEncodingProfileForSystemLowPowerMode() async throws {
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
            framebuffers: [framebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { true }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(connector.renegotiatedPreferences, [.powerSaverSustained])
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

    func testModelSelectsHelperVideoVisualTransportForPairedReachableProfile() throws {
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
                composeDraft: ComposeDraft(sessionID: session.id, text: "입력 유지"),
                latestFramebuffer: framebuffer,
                helperVideoProfileState: [
                    profile.id: HelperVideoProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-video",
                        availability: .available,
                        lastCheckedBucket: .recent
                    )
                ]
            )
        )

        let selected = model.selectHelperVideoVisualTransport(
            descriptor: HelperVideoStreamDescriptor(codecProfile: .baseline),
            health: HelperVideoStreamHealth(
                state: .healthy,
                startupBand: .fast,
                sustainedUpdateBand: .smooth,
                decodePressure: .low
            )
        )
        let snapshot = model.snapshot

        XCTAssertTrue(selected)
        XCTAssertEqual(snapshot.visualTransportMode, .helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamDescriptor?.codecProfile, .baseline)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .healthy)
        XCTAssertEqual(snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(snapshot.composeDraft?.text, "입력 유지")
        XCTAssertEqual(snapshot.session?.state, .active)
    }

    func testHelperVideoStallFallsBackToVNCWithoutClearingComposeDraft() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 30, green: 20, blue: 10)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "초기 입력"),
                latestFramebuffer: framebuffer
            )
        )

        model.setHelperVideoProfileState(
            HelperVideoProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-video",
                availability: .available,
                lastCheckedBucket: .recent
            ),
            for: profile.id
        )
        XCTAssertTrue(
            model.selectHelperVideoVisualTransport(
                descriptor: HelperVideoStreamDescriptor(),
                health: HelperVideoStreamHealth(state: .healthy, sustainedUpdateBand: .smooth)
            )
        )

        model.updateComposeDraftText("한글 조합 계속")
        model.updateHelperVideoStreamHealth(
            HelperVideoStreamHealth(
                state: .stalled,
                sustainedUpdateBand: .stalled,
                decodePressure: .high,
                fallbackCountBucket: .one
            )
        )
        let snapshot = model.snapshot

        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(snapshot.helperVideoStreamDescriptor)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .fallbackToVNC)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.sustainedUpdateBand, .stalled)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.decodePressure, .high)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.fallbackCountBucket, .one)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .fallbackToVNC)
        XCTAssertEqual(snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(snapshot.composeDraft?.text, "한글 조합 계속")
        XCTAssertEqual(snapshot.composeDraft?.sendState, .ready)
        XCTAssertEqual(snapshot.session?.state, .active)
    }

    func testHelperVideoSelectionFailureRecordsSafeReasonWithoutChangingVNCState() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 1, green: 2, blue: 3)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "draft"),
                latestFramebuffer: framebuffer
            )
        )

        let selected = model.selectHelperVideoVisualTransport()
        let snapshot = model.snapshot

        XCTAssertFalse(selected)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(
            snapshot.helperVideoVisualSelectionFailureReason,
            .helperVideoUnavailable
        )
        XCTAssertNil(snapshot.helperVideoStreamDescriptor)
        XCTAssertEqual(snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(snapshot.composeDraft?.text, "draft")
        XCTAssertEqual(snapshot.session?.state, .active)
    }

    func testNoHelperVideoProfileKeepsVNCBaselineAndReportsSafeDiagnosticState() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 1, green: 1, blue: 1)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "baseline"),
                latestFramebuffer: framebuffer
            )
        )

        let selected = model.selectHelperVideoVisualTransport()
        let snapshot = model.snapshot
        let export = model.makeDiagnosticExport()

        XCTAssertFalse(selected)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoVisualSelectionFailureReason, .helperVideoUnavailable)
        XCTAssertEqual(snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(snapshot.composeDraft?.text, "baseline")
        XCTAssertEqual(export.helperVideo?.availability, HelperVideoAvailability.notConfigured.rawValue)
        XCTAssertEqual(export.helperVideo?.canAttemptHelperVideoStream, false)
        XCTAssertEqual(export.helperVideo?.profileUsesVNCVisualFallback, true)
    }

    func testPublicHostProfileBlocksHelperVideoWithPrivateNetworkReason() throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "public.example.com",
            hostKind: .advancedManualPublicEndpoint,
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                helperVideoProfileState: [
                    profile.id: HelperVideoProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-video",
                        availability: .available,
                        lastCheckedBucket: .recent
                    )
                ]
            )
        )

        let selected = model.selectHelperVideoVisualTransport(
            descriptor: HelperVideoStreamDescriptor(),
            health: HelperVideoStreamHealth(state: .healthy)
        )
        let snapshot = model.snapshot

        XCTAssertFalse(selected)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoVisualSelectionFailureReason, .privateNetworkRequired)
        XCTAssertNil(snapshot.helperVideoStreamDescriptor)
    }

    func testStoredHelperVideoProfileInitializesPrivateNetworkStateWhenLoadingProfiles() async throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = InMemoryConnectionProfilePersistence(profiles: [profile])
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)

        await model.loadStoredProfiles()

        XCTAssertEqual(model.snapshot.selectedProfile?.id, profile.id)
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profile.id]?.isEnabled, true)
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profile.id]?.availability, .checking)
        XCTAssertEqual(
            model.snapshot.helperVideoProfileState[profile.id]?.pairingFingerprint,
            "sha256:helper-video"
        )
    }

    func testHelperVideoBootstrapStartsAfterVNCFirstFrameWithoutDroppingControl() async throws {
        let helperVideoSecretRef = "helper-video-token:desk"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoSecretRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let connector = FakeStreamingConnector(width: 2, height: 1, name: "Desk", framebuffer: framebuffer)
        let helperRecorder = HelperVideoStartRecorder(
            result: Self.helperVideoStartResult(
                descriptor: HelperVideoStreamDescriptor(codecProfile: .baseline),
                accessUnits: [
                    Self.helperVideoAccessUnit(sequence: 1, kind: .keyframe)
                ]
            )
        )
        let helperRenderer = AppModelFakeHelperVideoRenderer(displayableSequences: [1])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: [helperVideoSecretRef: "helper-video-secret"]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            helperVideoStartStream: { profile, pairingSecret, pairingFingerprint, requestBody, maxServerFrames in
                try await helperRecorder.start(
                    profile: profile,
                    pairingSecret: pairingSecret,
                    pairingFingerprint: pairingFingerprint,
                    requestBody: requestBody,
                    maxServerFrames: maxServerFrames
                )
            },
            helperVideoRendererFactory: { helperRenderer }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)
        model.sendTapAt(viewPoint: CGPoint(x: 1, y: 0.5), viewSize: CGSize(width: 2, height: 1))
        try await waitForPointerEvents(connector, count: 2)

        let calls = await helperRecorder.recordedCallSnapshot()
        let snapshot = model.snapshot
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.profileID, profile.id)
        XCTAssertEqual(calls.first?.pairingFingerprint, "sha256:helper-video")
        XCTAssertEqual(calls.first?.loadedSecretWasPresent, true)
        XCTAssertEqual(snapshot.session?.state, .active)
        XCTAssertEqual(snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(snapshot.visualTransportMode, VisualTransportMode.helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamDescriptor?.codecProfile, .baseline)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, nil)
        XCTAssertEqual(connector.recordedPointerEvents.map(\.mask), [1, 0])
    }

    func testHelperVideoBootstrapFailureKeepsVNCFrameAndControlPathActive() async throws {
        let helperVideoSecretRef = "helper-video-token:desk"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoSecretRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 30, green: 20, blue: 10)
        )
        let connector = FakeStreamingConnector(width: 2, height: 1, name: "Desk", framebuffer: framebuffer)
        let helperRecorder = HelperVideoStartRecorder(failure: .transportUnavailable)
        let helperRenderer = AppModelFakeHelperVideoRenderer(displayableSequences: [1])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: [helperVideoSecretRef: "helper-video-secret"]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            helperVideoStartStream: { profile, pairingSecret, pairingFingerprint, requestBody, maxServerFrames in
                try await helperRecorder.start(
                    profile: profile,
                    pairingSecret: pairingSecret,
                    pairingFingerprint: pairingFingerprint,
                    requestBody: requestBody,
                    maxServerFrames: maxServerFrames
                )
            },
            helperVideoRendererFactory: { helperRenderer }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoAvailability(model, profileID: profile.id, availability: .unreachable)
        model.sendTapAt(viewPoint: CGPoint(x: 1, y: 0.5), viewSize: CGSize(width: 2, height: 1))
        try await waitForPointerEvents(connector, count: 2)

        let calls = await helperRecorder.recordedCallSnapshot()
        let snapshot = model.snapshot
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(snapshot.session?.state, .active)
        XCTAssertEqual(snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .fallbackToVNC)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .transportFailed)
        XCTAssertEqual(snapshot.composeDraft?.sendState, .idle)
        XCTAssertEqual(connector.recordedPointerEvents.map(\.mask), [1, 0])
    }

    func testStoredPublicHostHelperVideoInitializesPrivateNetworkRequiredState() async throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "public.example.com",
            hostKind: .advancedManualPublicEndpoint,
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = InMemoryConnectionProfilePersistence(profiles: [profile])
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)

        await model.loadStoredProfiles()

        XCTAssertEqual(model.snapshot.helperVideoProfileState[profile.id]?.isEnabled, false)
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profile.id]?.availability, .privateNetworkRequired)
        XCTAssertEqual(
            model.snapshot.helperVideoProfileState[profile.id]?.lastFailureCode,
            .privateNetworkRequired
        )
    }

    func testDisableAndRevokeHelperVideoFallsBackWithoutDroppingSession() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "draft"),
                helperVideoProfileState: [
                    profile.id: HelperVideoProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-video",
                        availability: .available,
                        lastCheckedBucket: .recent
                    )
                ]
            )
        )
        XCTAssertTrue(model.selectHelperVideoVisualTransport(health: HelperVideoStreamHealth(state: .healthy)))

        await model.disableHelperVideo(for: profile.id)
        var snapshot = model.snapshot

        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.isEnabled, false)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .disabled)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .disabled)
        XCTAssertEqual(snapshot.composeDraft?.text, "draft")
        XCTAssertEqual(snapshot.session?.state, .active)

        model.setHelperVideoProfileState(
            HelperVideoProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-video",
                availability: .available,
                lastCheckedBucket: .recent
            ),
            for: profile.id
        )
        XCTAssertTrue(model.selectHelperVideoVisualTransport(health: HelperVideoStreamHealth(state: .healthy)))

        await model.revokeHelperVideo(for: profile.id)
        snapshot = model.snapshot

        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.isEnabled, false)
        XCTAssertNil(snapshot.helperVideoProfileState[profile.id]?.pairingFingerprint)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .revoked)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .revoked)
        XCTAssertEqual(snapshot.helperVideoVisualSelectionFailureReason, .helperVideoRevoked)
        XCTAssertEqual(snapshot.composeDraft?.text, "draft")
        XCTAssertEqual(snapshot.session?.state, .active)
    }

    func testDisableAndRevokeHelperVideoPersistThroughProfileReload() async throws {
        let helperVideoSecretRef = "helper-video-token:desk"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoSecretRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = InMemoryConnectionProfilePersistence(profiles: [profile])
        let store = try await ConnectionProfileStore(persistence: persistence)
        let credentialStore = InMemoryConnectionCredentialStore(
            passwords: [helperVideoSecretRef: "helper-video-secret"]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            profileStore: store,
            credentialStore: credentialStore
        )

        await model.disableHelperVideo(for: profile.id)

        let disabledReloadedStore = try await ConnectionProfileStore(persistence: persistence)
        let disabledProfileOrNil = await disabledReloadedStore.profile(id: profile.id)
        let disabledProfile = try XCTUnwrap(disabledProfileOrNil)
        XCTAssertEqual(disabledProfile.helperVideo?.isEnabled, false)
        XCTAssertEqual(disabledProfile.helperVideo?.isRevoked, false)
        XCTAssertEqual(disabledProfile.helperVideo?.pairingSecretRef, helperVideoSecretRef)
        XCTAssertEqual(disabledProfile.helperVideo?.pairingFingerprint, "sha256:helper-video")

        let revokingModel = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [disabledProfile],
                selectedProfileID: disabledProfile.id
            ),
            profileStore: disabledReloadedStore,
            credentialStore: credentialStore
        )
        await revokingModel.revokeHelperVideo(for: profile.id)

        let revokedReloadedStore = try await ConnectionProfileStore(persistence: persistence)
        let revokedProfileOrNil = await revokedReloadedStore.profile(id: profile.id)
        let revokedProfile = try XCTUnwrap(revokedProfileOrNil)
        XCTAssertEqual(revokedProfile.helperVideo?.isEnabled, false)
        XCTAssertEqual(revokedProfile.helperVideo?.isRevoked, true)
        XCTAssertNil(revokedProfile.helperVideo?.pairingSecretRef)
        XCTAssertNil(revokedProfile.helperVideo?.pairingFingerprint)
        let revokedSecret = try await credentialStore.password(for: helperVideoSecretRef)
        XCTAssertNil(revokedSecret)

        let reloadedModel = NaruRemoteAppModel(profileStore: revokedReloadedStore)
        await reloadedModel.loadStoredProfiles()
        XCTAssertEqual(reloadedModel.snapshot.helperVideoProfileState[profile.id]?.availability, .revoked)
        XCTAssertEqual(reloadedModel.snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .revoked)
    }

    func testRevokeHelperVideoKeepsCredentialWhenProfilePersistenceFails() async throws {
        let helperVideoSecretRef = "helper-video-token:desk"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoSecretRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = FailingConnectionProfilePersistence(profiles: [profile])
        let store = try await ConnectionProfileStore(persistence: persistence)
        let credentialStore = InMemoryConnectionCredentialStore(
            passwords: [helperVideoSecretRef: "helper-video-secret"]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            profileStore: store,
            credentialStore: credentialStore
        )

        await model.revokeHelperVideo(for: profile.id)

        let savedSecret = try await credentialStore.password(for: helperVideoSecretRef)
        XCTAssertEqual(savedSecret, "helper-video-secret")
        XCTAssertEqual(model.profilePersistenceError, "Profile could not be saved on this device.")
    }

    func testStaleHelperVideoCallbacksDoNotOverrideCurrentVisualState() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session
            )
        )
        model.setHelperVideoProfileState(
            HelperVideoProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-video",
                availability: .available,
                lastCheckedBucket: .recent
            ),
            for: profile.id
        )
        XCTAssertTrue(
            model.selectHelperVideoVisualTransport(
                descriptor: HelperVideoStreamDescriptor(codecProfile: .baseline),
                health: HelperVideoStreamHealth(state: .healthy, sustainedUpdateBand: .smooth)
            )
        )

        model.updateHelperVideoStreamHealth(
            HelperVideoStreamHealth(
                state: .stalled,
                sustainedUpdateBand: .stalled,
                fallbackCountBucket: .one
            ),
            sessionID: UUID(),
            profileID: profile.id
        )
        model.setHelperVideoProfileState(
            HelperVideoProfileState(isEnabled: false, availability: .unreachable),
            for: profile.id,
            sessionID: UUID()
        )
        var snapshot = model.snapshot

        XCTAssertEqual(snapshot.visualTransportMode, .helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamDescriptor?.codecProfile, .baseline)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .healthy)
        XCTAssertNil(snapshot.helperVideoVisualSelectionFailureReason)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)

        model.updateHelperVideoStreamHealth(
            HelperVideoStreamHealth(
                state: .stalled,
                sustainedUpdateBand: .stalled,
                fallbackCountBucket: .one
            ),
            sessionID: session.id,
            profileID: profile.id
        )
        snapshot = model.snapshot

        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .fallbackToVNC)
        XCTAssertEqual(
            snapshot.helperVideoVisualSelectionFailureReason,
            .streamHealthRequiresVNCFallback
        )
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
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .supported
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .controlV)

        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sending)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(
            connector.pasteCommands,
            [],
            "Paste should wait for the production remote clipboard settle window."
        )
        try await waitForPasteCommands(connector, count: 1)

        XCTAssertEqual(connector.clipboardPayloads, ["한글과 English 😊"])
        XCTAssertEqual(connector.pasteCommands, [.controlV])
        for _ in 0..<20
            where model.snapshot.latestInjectionAttempt?.pasteCommandStatus != .succeeded {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .unknown)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommand, .controlV)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardTransferMode, .extendedClipboardUTF8)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.utf8ClipboardSupport, .supported)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardSetStatus, .succeeded)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommandStatus, .succeeded)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .unknown)
        XCTAssertEqual(
            model.snapshot.composeDraft?.lastStatusMessage,
            "Paste command sent through UTF-8 clipboard; remote app confirmation unavailable."
        )

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(report.input?.hasComposeDraftText, true)
        XCTAssertEqual(report.input?.composeSendState, ComposeSendState.unknown.rawValue)
        XCTAssertEqual(
            report.input?.composeDraftPayloadEncoding,
            TextInjectionPayloadEncoding.utf8ExtensionRequired.rawValue
        )
        XCTAssertEqual(report.input?.composePlannedPath, TextInjectionPath.vncClipboardPaste.rawValue)
        XCTAssertEqual(
            report.input?.composeUTF8ClipboardSupport,
            RemoteClipboardUTF8Support.supported.rawValue
        )
        XCTAssertEqual(report.input?.composeRouteBlocker, DiagnosticComposeRouteBlocker.none.rawValue)
        XCTAssertEqual(report.input?.latestInjectionPasteCommand, PasteCommand.controlV.rawValue)
        XCTAssertEqual(
            report.input?.latestInjectionPayloadEncoding,
            TextInjectionPayloadEncoding.utf8ExtensionRequired.rawValue
        )
        XCTAssertEqual(
            report.input?.latestInjectionClipboardTransferMode,
            TextClipboardTransferMode.extendedClipboardUTF8.rawValue
        )
        XCTAssertEqual(
            report.input?.latestInjectionUTF8ClipboardSupport,
            RemoteClipboardUTF8Support.supported.rawValue
        )
        XCTAssertEqual(report.input?.latestInjectionClipboardSetStatus, TextInjectionStepStatus.succeeded.rawValue)
        XCTAssertEqual(report.input?.latestInjectionPasteCommandStatus, TextInjectionStepStatus.succeeded.rawValue)
        XCTAssertFalse(json.contains("한글과 English"))
        XCTAssertFalse(json.contains("😊"))
    }

    func testDiagnosticExportIncludesComposeRouteBlockerBeforeUTF8SendWithoutHelper() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.updateComposeDraftText("한글과 English 😊")

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(
            report.input?.composeDraftPayloadEncoding,
            TextInjectionPayloadEncoding.utf8ExtensionRequired.rawValue
        )
        XCTAssertEqual(
            report.input?.composeUTF8ClipboardSupport,
            RemoteClipboardUTF8Support.unknown.rawValue
        )
        XCTAssertEqual(report.input?.composePlannedPath, TextInjectionPath.vncClipboardPaste.rawValue)
        XCTAssertEqual(
            report.input?.composeRouteBlocker,
            DiagnosticComposeRouteBlocker.none.rawValue
        )
        XCTAssertNil(report.input?.latestInjectionPath)
        XCTAssertFalse(json.contains("한글과 English"))
        XCTAssertFalse(json.contains("😊"))
    }

    func testModelRoutesUTF8ComposeThroughReachableHelperWhenVNCUTF8IsUnconfirmed() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let helper = FakeHelperTextInsertClient()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperTextBridgeState: [
                    profile.id: HelperTextBridgeProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-pairing",
                        availability: .reachable,
                        lastFailureCode: nil,
                        lastCheckedBucket: .recent
                    )
                ]
            ),
            connectorFactory: { connector },
            helperTextInsertClient: helper
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.updateComposeDraftText("한글과 English 😊")
        let preflightJSON = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let preflightReport = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(preflightJSON.utf8)
        )
        XCTAssertEqual(preflightReport.input?.composePlannedPath, TextInjectionPath.helperTextBridge.rawValue)
        XCTAssertEqual(preflightReport.input?.composeRouteBlocker, DiagnosticComposeRouteBlocker.none.rawValue)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)
        try await waitForHelperInsertRequests(helper, count: 1)

        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(helper.insertedTexts, ["한글과 English 😊"])
        XCTAssertEqual(helper.requests.count, 1)
        XCTAssertEqual(helper.requests.first?.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(helper.requests.first?.payloadSizeBucket, .small)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .helperTextBridge)
        XCTAssertNil(model.snapshot.latestInjectionAttempt?.pasteCommand)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .sent)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardSetStatus, .notAttempted)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommandStatus, .notAttempted)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sent)
        XCTAssertEqual(model.snapshot.composeDraft?.lastStatusMessage, "Text sent through helper.")
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode,
            HelperTextBridgeFailureCode.none
        )

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(report.input?.latestInjectionPath, TextInjectionPath.helperTextBridge.rawValue)
        XCTAssertEqual(report.input?.latestInjectionStatus, TextInjectionStatus.sent.rawValue)
        XCTAssertEqual(
            report.input?.composeDraftPayloadEncoding,
            TextInjectionPayloadEncoding.utf8ExtensionRequired.rawValue
        )
        XCTAssertEqual(report.input?.composePlannedPath, TextInjectionPath.helperTextBridge.rawValue)
        XCTAssertEqual(
            report.input?.composeUTF8ClipboardSupport,
            RemoteClipboardUTF8Support.unknown.rawValue
        )
        XCTAssertEqual(report.input?.composeRouteBlocker, DiagnosticComposeRouteBlocker.none.rawValue)
        XCTAssertEqual(report.input?.helperTextBridgeAvailability, HelperTextBridgeAvailability.reachable.rawValue)
        XCTAssertEqual(report.input?.helperTextBridgeLastFailureCode, HelperTextBridgeFailureCode.none.rawValue)
        XCTAssertFalse(json.contains("한글과 English"))
        XCTAssertFalse(json.contains("😊"))
        XCTAssertFalse(json.contains("helper-pairing"))
    }

    func testModelRoutesUTF8ComposeThroughStoredHelperProfileTransport() async throws {
        let helperSecretRef = "helper-token:desk"
        let recorder = NetworkHelperInsertRecorder()
        let handler = NaruHelperNetworkRequestHandler(
            expectedPairingSecret: "helper-secret",
            capabilityProvider: {
                NaruHelperCapabilityResponse(
                    availability: .reachable,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "granted",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.pasteboardPasteWithRestore]
                )
            },
            insertHandler: { request in
                recorder.record(request)
                return NaruHelperInsertTextResponse(
                    requestID: request.requestID,
                    status: .sent,
                    strategyUsed: .pasteboardPasteWithRestore
                )
            }
        )
        let server = try NaruHelperNetworkServer(handler: handler)
        server.start()
        defer { server.cancel() }
        let helperPort = try await waitForHelperServerPort(server)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: "127.0.0.1",
                port: Int(helperPort),
                pairingSecretRef: helperSecretRef,
                pairingFingerprint: "sha256:helper-fingerprint"
            )
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [helperSecretRef: "helper-secret"])
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .unsupported
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)
        try await waitForNetworkHelperInsertRequests(recorder, count: 1)

        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(recorder.insertedTexts, ["한글과 English 😊"])
        XCTAssertEqual(recorder.requests.first?.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .helperTextBridge)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .sent)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sent)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .reachable)
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode,
            HelperTextBridgeFailureCode.none
        )
    }

    func testStoredHelperCapabilityProbeMarksReachableWithoutSendingText() async throws {
        let helperSecretRef = "helper-token:desk"
        let recorder = NetworkHelperInsertRecorder()
        let handler = NaruHelperNetworkRequestHandler(
            expectedPairingSecret: "helper-secret",
            capabilityProvider: {
                NaruHelperCapabilityResponse(
                    availability: .reachable,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "granted",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.pasteboardPasteWithRestore]
                )
            },
            insertHandler: { request in
                recorder.record(request)
                return NaruHelperInsertTextResponse(
                    requestID: request.requestID,
                    status: .sent,
                    strategyUsed: .pasteboardPasteWithRestore
                )
            }
        )
        let server = try NaruHelperNetworkServer(handler: handler)
        server.start()
        defer { server.cancel() }
        let helperPort = try await waitForHelperServerPort(server)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: "127.0.0.1",
                port: Int(helperPort),
                pairingSecretRef: helperSecretRef,
                pairingFingerprint: "sha256:helper-fingerprint"
            )
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [helperSecretRef: "helper-secret"])
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            connectorFactory: { connector }
        )

        model.refreshProfileReachability()
        try await waitForHelperAvailability(model, profileID: profile.id, availability: .reachable)

        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode,
            HelperTextBridgeFailureCode.none
        )
    }

    func testHelperCapabilityRefreshKeepsVisibleStateWhileProbeIsInFlight() async throws {
        let helperSecretRef = "helper-token:desk"
        let recorder = NetworkHelperInsertRecorder()
        let handler = NaruHelperNetworkRequestHandler(
            expectedPairingSecret: "helper-secret",
            capabilityProvider: {
                Thread.sleep(forTimeInterval: 0.15)
                return NaruHelperCapabilityResponse(
                    availability: .permissionMissing,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "missing",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.pasteboardPasteWithRestore]
                )
            },
            insertHandler: { request in
                recorder.record(request)
                return NaruHelperInsertTextResponse(
                    requestID: request.requestID,
                    status: .sent,
                    strategyUsed: .pasteboardPasteWithRestore
                )
            }
        )
        let server = try NaruHelperNetworkServer(handler: handler)
        server.start()
        defer { server.cancel() }
        let helperPort = try await waitForHelperServerPort(server)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: "127.0.0.1",
                port: Int(helperPort),
                pairingSecretRef: helperSecretRef,
                pairingFingerprint: "sha256:helper-fingerprint"
            )
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [helperSecretRef: "helper-secret"])
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperTextBridgeState: [
                    profile.id: HelperTextBridgeProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-fingerprint",
                        availability: .reachable,
                        lastFailureCode: HelperTextBridgeFailureCode.none,
                        lastCheckedBucket: .recent
                    )
                ]
            ),
            credentialStore: credentialStore,
            connectorFactory: { connector }
        )

        model.refreshProfileReachability()

        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .reachable)
        try await waitForHelperAvailability(model, profileID: profile.id, availability: .permissionMissing)
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testStoredHelperCapabilityFailureBlocksRawHelperInsertBeforeUnsupportedVNCFailure() async throws {
        let helperSecretRef = "helper-token:desk"
        let recorder = NetworkHelperInsertRecorder()
        let handler = NaruHelperNetworkRequestHandler(
            expectedPairingSecret: "helper-secret",
            capabilityProvider: {
                NaruHelperCapabilityResponse(
                    availability: .permissionMissing,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "missing",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.pasteboardPasteWithRestore]
                )
            },
            insertHandler: { request in
                recorder.record(request)
                return NaruHelperInsertTextResponse(
                    requestID: request.requestID,
                    status: .sent,
                    strategyUsed: .pasteboardPasteWithRestore
                )
            }
        )
        let server = try NaruHelperNetworkServer(handler: handler)
        server.start()
        defer { server.cancel() }
        let helperPort = try await waitForHelperServerPort(server)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: "127.0.0.1",
                port: Int(helperPort),
                pairingSecretRef: helperSecretRef,
                pairingFingerprint: "sha256:helper-fingerprint"
            )
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [helperSecretRef: "helper-secret"])
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .unsupported
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)
        for _ in 0..<60 where model.snapshot.latestInjectionAttempt?.status != .failed {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .vncClipboardPaste)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text clipboard unavailable: This VNC server reported that UTF-8 clipboard support is unavailable, so Korean/CJK/emoji Compose text cannot be sent reliably. Helper text bridge needs permission on the Mac."
        )
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .permissionMissing)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .permissionMissing)
    }

    func testModelRejectsMismatchedHelperInsertResultID() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let helper = FakeHelperTextInsertClient(
            result: HelperTextInsertResult(
                requestID: UUID(),
                strategyUsed: .nativeInsert,
                status: .sent,
                safeFailureCode: .none
            )
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperTextBridgeState: [
                    profile.id: HelperTextBridgeProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-pairing",
                        availability: .reachable,
                        lastFailureCode: nil,
                        lastCheckedBucket: .recent
                    )
                ]
            ),
            connectorFactory: { connector },
            helperTextInsertClient: helper
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)
        for _ in 0..<60 where model.snapshot.latestInjectionAttempt?.status != .failed {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(helper.insertedTexts, ["한글과 English 😊"])
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .helperTextBridge)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.safeMessage, "Helper text bridge rejected the insert request.")
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .insertRejected)
    }

    func testModelAllowsBestEffortUTF8ComposeWhenClipboardSupportIsUnconfirmedWithoutHelper() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)

        for _ in 0..<60 where model.snapshot.latestInjectionAttempt?.pasteCommandStatus != .succeeded {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(connector.clipboardPayloads, ["한글과 English 😊"])
        XCTAssertEqual(connector.pasteCommands, [.commandV])
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .unknown)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .unknown)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardTransferMode, .legacyClientCutText)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardSetStatus, .succeeded)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommandStatus, .succeeded)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.utf8ClipboardSupport, .unknown)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Paste command sent through legacy VNC clipboard; this server has not confirmed UTF-8 clipboard support, so Korean/CJK text may paste incorrectly."
        )
    }

    func testModelFallsBackToBestEffortUTF8ComposeWhenStoredHelperIsKnownUnreachable() async throws {
        let helperSecretRef = "helper-token:desk"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: "127.0.0.1",
                port: 65534,
                pairingSecretRef: helperSecretRef,
                pairingFingerprint: "sha256:helper-fingerprint"
            )
        )
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [helperSecretRef: "helper-secret"])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperTextBridgeState: [
                    profile.id: HelperTextBridgeProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-fingerprint",
                        availability: .unreachable,
                        lastFailureCode: .unreachable,
                        lastCheckedBucket: .recent
                    )
                ]
            ),
            credentialStore: credentialStore,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)
        for _ in 0..<60 where model.snapshot.latestInjectionAttempt?.pasteCommandStatus != .succeeded {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(connector.clipboardPayloads, ["한글과 English 😊"])
        XCTAssertEqual(connector.pasteCommands, [.commandV])
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .vncClipboardPaste)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .unknown)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .unknown)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .unreachable)
    }

    func testModelRejectsUTF8ComposeWhenClipboardSupportIsUnsupported() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .unsupported
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)

        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardSetStatus, .notAttempted)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommandStatus, .notAttempted)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text clipboard unavailable: This VNC server reported that UTF-8 clipboard support is unavailable, so Korean/CJK/emoji Compose text cannot be sent reliably. Helper text bridge is not configured for this profile."
        )
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode,
            .notConfigured
        )
    }

    func testDisablingHelperTextBridgeBlocksFutureHelperInsert() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .unsupported
        )
        let helper = FakeHelperTextInsertClient()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperTextBridgeState: [
                    profile.id: HelperTextBridgeProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-pairing",
                        availability: .reachable,
                        lastFailureCode: HelperTextBridgeFailureCode.none,
                        lastCheckedBucket: .recent
                    )
                ]
            ),
            connectorFactory: { connector },
            helperTextInsertClient: helper
        )

        model.disableHelperTextBridge(for: profile.id)

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)

        XCTAssertTrue(helper.requests.isEmpty)
        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.isEnabled, false)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.pairingFingerprint, "sha256:helper-pairing")
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .disabled)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .disabled)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text clipboard unavailable: This VNC server reported that UTF-8 clipboard support is unavailable, so Korean/CJK/emoji Compose text cannot be sent reliably. Helper text bridge is disabled for this profile."
        )

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(report.input?.helperTextBridgeAvailability, HelperTextBridgeAvailability.disabled.rawValue)
        XCTAssertEqual(report.input?.helperTextBridgeLastFailureCode, HelperTextBridgeFailureCode.disabled.rawValue)
        XCTAssertFalse(json.contains("helper-pairing"))
    }

    func testRevokingHelperTextBridgeClearsPairingAndBlocksFutureHelperInsert() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .unsupported
        )
        let helper = FakeHelperTextInsertClient()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperTextBridgeState: [
                    profile.id: HelperTextBridgeProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-pairing",
                        availability: .reachable,
                        lastFailureCode: HelperTextBridgeFailureCode.none,
                        lastCheckedBucket: .recent
                    )
                ]
            ),
            connectorFactory: { connector },
            helperTextInsertClient: helper
        )

        model.revokeHelperTextBridge(for: profile.id)

        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.isEnabled, false)
        XCTAssertNil(model.snapshot.helperTextBridgeState[profile.id]?.pairingFingerprint)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .revoked)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .revoked)

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)

        XCTAssertTrue(helper.requests.isEmpty)
        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .revoked)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .revoked)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text clipboard unavailable: This VNC server reported that UTF-8 clipboard support is unavailable, so Korean/CJK/emoji Compose text cannot be sent reliably. Helper text bridge pairing was revoked."
        )
    }

    func testRevokedHelperStateIsNotOverwrittenByLateHelperResult() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let helper = FakeHelperTextInsertClient(insertDelayNanoseconds: 120_000_000)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperTextBridgeState: [
                    profile.id: HelperTextBridgeProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-pairing",
                        availability: .reachable,
                        lastFailureCode: nil,
                        lastCheckedBucket: .recent
                    )
                ]
            ),
            connectorFactory: { connector },
            helperTextInsertClient: helper
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)
        try await waitForHelperInsertRequests(helper, count: 1)

        model.revokeHelperTextBridge(for: profile.id)
        for _ in 0..<40 where model.snapshot.latestInjectionAttempt?.status != .sent {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(helper.insertedTexts, ["한글과 English 😊"])
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .sent)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.isEnabled, false)
        XCTAssertNil(model.snapshot.helperTextBridgeState[profile.id]?.pairingFingerprint)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .revoked)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .revoked)
    }

    func testModelUpdatesComposeDraftAsUserTypes() throws {
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

        model.updateComposeDraftText("한글 조합 중 English")

        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글 조합 중 English")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .ready)
        XCTAssertNil(model.snapshot.latestInjectionAttempt)
    }

    func testDiagnosticExportIncludesComposeSendPreparationWithoutDraftText() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "한글 조합 중 English")
            )
        )

        model.recordComposeSendPreparation(
            ComposeSendPreparationReport(
                mode: .markedTextStabilization,
                snapshotCount: 30,
                durationBucket: .stalled
            )
        )

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(
            report.input?.latestComposeSendPreparationMode,
            ComposeSendPreparationMode.markedTextStabilization.rawValue
        )
        XCTAssertEqual(report.input?.latestComposeSendPreparationSnapshotCount, 30)
        XCTAssertEqual(
            report.input?.latestComposeSendPreparationDurationBucket,
            DiagnosticTimingBucket.stalled.rawValue
        )
        XCTAssertFalse(json.contains("한글 조합 중 English"))
    }

    func testEditingComposeDraftClearsStaleComposeSendPreparationDiagnostic() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "old")
            )
        )
        model.recordComposeSendPreparation(
            ComposeSendPreparationReport(
                mode: .fastSnapshot,
                snapshotCount: 3,
                durationBucket: .subFrame
            )
        )

        model.updateComposeDraftText("new")
        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(report.input?.latestComposeSendPreparationMode)
        XCTAssertNil(report.input?.latestComposeSendPreparationSnapshotCount)
        XCTAssertNil(report.input?.latestComposeSendPreparationDurationBucket)
    }

    func testComposeSendPreparationRecordedAfterFinalDraftSyncSurvivesExport() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "partial")
            )
        )

        model.updateComposeDraftText("final")
        model.recordComposeSendPreparation(
            ComposeSendPreparationReport(
                mode: .markedTextStabilization,
                snapshotCount: 30,
                durationBucket: .lagging
            )
        )
        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(
            report.input?.latestComposeSendPreparationMode,
            ComposeSendPreparationMode.markedTextStabilization.rawValue
        )
        XCTAssertEqual(report.input?.latestComposeSendPreparationSnapshotCount, 30)
        XCTAssertEqual(
            report.input?.latestComposeSendPreparationDurationBucket,
            DiagnosticTimingBucket.lagging.rawValue
        )
        XCTAssertFalse(json.contains("final"))
    }

    func testEditingComposeDraftDuringSendPreventsStalePasteFromOverwritingNewText() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .supported
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("첫 문장", pasteCommand: .controlV)
        let sendingDraftID = try XCTUnwrap(model.snapshot.composeDraft?.id)
        for _ in 0..<50 where connector.clipboardPayloads.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(connector.clipboardPayloads, ["첫 문장"])

        model.updateComposeDraftText("새로 쓰는 문장")
        try await waitForPasteCommands(connector, count: 1)

        XCTAssertNotEqual(model.snapshot.composeDraft?.id, sendingDraftID)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "새로 쓰는 문장")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .ready)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.draftID, sendingDraftID)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .unknown)
        XCTAssertEqual(connector.pasteCommands, [.controlV])
    }

    func testModelCancelsComposedPasteWhenSessionDisconnectsDuringSettleDelay() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .supported
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<20 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.session?.state, .active)

        model.sendComposedText("중단되어야 하는 paste", pasteCommand: .controlV)
        for _ in 0..<50 where connector.clipboardPayloads.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(connector.clipboardPayloads, ["중단되어야 하는 paste"])

        model.disconnect()
        try await Task.sleep(for: .milliseconds(420))

        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardSetStatus, .succeeded)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommandStatus, .notAttempted)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text send cancelled because the remote session changed."
        )
    }

    func testStartupPreflightConsumesHiddenIncrementalAfterFirstVisibleFrame() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let hiddenFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, hiddenFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector },
            streamStartupPreflightPolicy: SessionStreamStartupPreflightPolicy(hiddenFrameCount: 1),
            lowPowerModeProvider: { false }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(connector.frameUpdateRequests, [false, true])
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)
        XCTAssertEqual(model.snapshot.sessionStreamStats.deliveredFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.contentFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.emptyUpdateCount, 0)
        XCTAssertEqual(model.snapshot.sessionStreamStats.startupPreflightRequestedHiddenFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.startupPreflightConsumedHiddenFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.startupPreflightOutcome, .consumed)
    }

    func testStartupPreflightContinuesVisibleStreamAfterHiddenIncremental() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let hiddenFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let nextVisibleFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 30, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, hiddenFramebuffer, nextVisibleFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 3, frameInterval: 0),
            connectorFactory: { connector },
            streamStartupPreflightPolicy: SessionStreamStartupPreflightPolicy(hiddenFrameCount: 1),
            lowPowerModeProvider: { false }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(connector.frameUpdateRequests, [false, true, true])
        XCTAssertEqual(model.snapshot.latestFramebuffer, nextVisibleFramebuffer)
        XCTAssertEqual(model.snapshot.sessionStreamStats.deliveredFrameCount, 2)
        XCTAssertEqual(model.snapshot.sessionStreamStats.contentFrameCount, 2)
        XCTAssertEqual(model.snapshot.sessionStreamStats.emptyUpdateCount, 0)
        XCTAssertEqual(model.snapshot.sessionStreamStats.startupPreflightRequestedHiddenFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.startupPreflightConsumedHiddenFrameCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.startupPreflightOutcome, .consumed)
    }

    func testStartupPreflightUsesAppSettingWhenNoOverrideIsInjected() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let hiddenFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, hiddenFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        model.setStartupPreflightMode(.oneHiddenFrame)
        model.setStartupGlanceScaleMode(.glance025)

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(100))

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "0.1.0",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(connector.frameUpdateRequests, [false, true])
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)
        XCTAssertEqual(report.viewerStartupPreflightMode, StreamStartupPreflightMode.oneHiddenFrame.rawValue)
        XCTAssertEqual(report.viewerStartupGlanceScaleMode, StreamStartupGlanceScaleMode.glance025.rawValue)
        XCTAssertEqual(report.streamPerformance?.startupPreflightRequestedHiddenFrameCount, 1)
        XCTAssertEqual(report.streamPerformance?.startupPreflightConsumedHiddenFrameCount, 1)
        XCTAssertEqual(report.streamPerformance?.startupPreflightOutcome, DiagnosticStartupPreflightOutcome.consumed.rawValue)
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

    func testViewportInteractionKeepsRequestsLiveAndFlushesLatestFrameAfterGesture() async throws {
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
        let thirdFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 30, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer, thirdFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 3, frameInterval: 0.05),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<50 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)

        model.setViewportInteractionActive(true)
        let requestCountAtGestureStart = connector.frameUpdateRequests.count
        try await Task.sleep(for: .milliseconds(140))

        XCTAssertGreaterThan(
            connector.frameUpdateRequests.count,
            requestCountAtGestureStart,
            "Viewport interaction should no longer pause the request loop while a frame is visible."
        )
        XCTAssertEqual(
            model.snapshot.latestFramebuffer,
            firstFramebuffer,
            "Content frames should stay deferred while touch navigation owns the main-thread visual path."
        )

        model.setViewportInteractionActive(false)
        for _ in 0..<120 where model.snapshot.latestFramebuffer != thirdFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.snapshot.latestFramebuffer, thirdFramebuffer)
    }

    func testViewportInteractionDropsDeferredFrameWhenStreamFails() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let deferredFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, deferredFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: nil, frameInterval: 0.05),
            reconnectPolicy: ReconnectPolicy(maxAttempts: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        for _ in 0..<50 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)

        model.setViewportInteractionActive(true)
        for _ in 0..<120 where model.snapshot.latestFramebuffer != nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(model.snapshot.latestFramebuffer)

        model.setViewportInteractionActive(false)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(
            model.snapshot.latestFramebuffer,
            "A deferred gesture-time frame from a failed stream must not publish after the user lifts their fingers."
        )
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

        XCTAssertEqual(report.schemaVersion, DiagnosticCollectionReport.currentSchemaVersion)
        XCTAssertEqual(report.verdict, DiagnosticVerdict.failed.rawValue)
        XCTAssertEqual(report.viewerStreamPowerMode, StreamPowerMode.balanced.rawValue)
        XCTAssertEqual(report.viewerStreamEncodingMode, StreamEncodingMode.standard.rawValue)
        XCTAssertEqual(report.viewerStartupPreflightMode, StreamStartupPreflightMode.disabled.rawValue)
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
        model.setStreamEncodingMode(.zrleCompressionZero)

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
        let assessment = try XCTUnwrap(report.sustainedSessionAssessment)
        XCTAssertEqual(report.schemaVersion, DiagnosticCollectionReport.currentSchemaVersion)
        XCTAssertEqual(report.viewerStreamPowerMode, StreamPowerMode.powerSaver.rawValue)
        XCTAssertEqual(report.viewerStreamEncodingMode, StreamEncodingMode.zrleCompressionZero.rawValue)
        XCTAssertEqual(report.viewerStartupPreflightMode, StreamStartupPreflightMode.disabled.rawValue)
        XCTAssertEqual(performance.deliveredFrameCount, 2)
        XCTAssertEqual(performance.contentFrameCount, 2)
        XCTAssertEqual(performance.emptyUpdateCount, 0)
        XCTAssertEqual(performance.startupPreflightRequestedHiddenFrameCount, 0)
        XCTAssertEqual(performance.startupPreflightConsumedHiddenFrameCount, 0)
        XCTAssertEqual(performance.startupPreflightOutcome, DiagnosticStartupPreflightOutcome.notRequested.rawValue)
        XCTAssertEqual(performance.adaptiveClientPressurePacingSampleCount, 0)
        XCTAssertEqual(performance.adaptiveClientPressurePacingPermille, 0)
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
        XCTAssertEqual(performance.appFrameApplyTimingSampleCount, 2)
        XCTAssertEqual(performance.streamPacingDelaySampleCount, 2)
        XCTAssertEqual(performance.averageStreamPacingDelayBucket, DiagnosticTimingBucket.subFrame.rawValue)
        XCTAssertEqual(performance.maxStreamPacingDelayBucket, DiagnosticTimingBucket.subFrame.rawValue)
        XCTAssertEqual(performance.powerSaverPacingSampleCount, 0)
        XCTAssertEqual(performance.thermalPacingSampleCount, 0)
        XCTAssertEqual(performance.emptyBackoffPacingSampleCount, 0)
        XCTAssertEqual(
            performance.actualEncodingMix,
            RFBFramebufferEncodingMix(rawRectangles: 1, zrleRectangles: 1)
        )
        XCTAssertEqual(performance.thermalState, SessionStreamThermalState.fair.rawValue)
        XCTAssertEqual(assessment.targetName, DiagnosticSustainedSessionAssessment.target.rawValue)
        XCTAssertEqual(assessment.verdict, DiagnosticSustainedSessionVerdict.fail.rawValue)
        XCTAssertTrue(
            assessment.issueCodes.contains(
                DiagnosticSustainedSessionIssueCode.insufficientContentSamples.rawValue
            )
        )
        XCTAssertTrue(
            assessment.issueCodes.contains(
                DiagnosticSustainedSessionIssueCode.averageReceiveStalled.rawValue
            )
        )
        XCTAssertTrue(
            assessment.issueCodes.contains(
                DiagnosticSustainedSessionIssueCode.rendererFullUploadFailed.rawValue
            )
        )
        XCTAssertTrue(
            assessment.issueCodes.contains(
                DiagnosticSustainedSessionIssueCode.elevatedThermalState.rawValue
            )
        )
        XCTAssertEqual(
            assessment.primaryIssueCode,
            DiagnosticSustainedSessionIssueCode.elevatedThermalState.rawValue
        )
        XCTAssertEqual(
            assessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.thermal.rawValue
        )
        XCTAssertEqual(
            assessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runPowerSaverThermalPass.rawValue
        )
        XCTAssertEqual(
            assessment.physicalGateVerdict,
            DiagnosticSustainedSessionPhysicalGateVerdict.blocked.rawValue
        )
        XCTAssertTrue(json.contains("\"actualEncodingMix\""))
        XCTAssertTrue(json.contains("\"sustainedSessionAssessment\""))
        XCTAssertTrue(json.contains("\"primaryConstraint\" : \"thermal\""))
        XCTAssertTrue(json.contains("\"recommendedNextProbe\" : \"runPowerSaverThermalPass\""))
        XCTAssertTrue(json.contains("\"physicalGateVerdict\" : \"blocked\""))
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
        transportIdleTimedOut: Bool = false,
        dirtyRectangles: [RFBFrameDamageRect]? = nil
    ) -> RFBFramePumpFrame {
        let width = 100
        let height = 100
        return RFBFramePumpFrame(
            sequence: 1,
            framebuffer: RFBRawFramebuffer(width: width, height: height),
            dirtyRectangles: dirtyRectangles ?? (changedPixelCount == 0 ? [] : [
                RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)
            ]),
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

    private func waitForPersistedStartupPreflightMode(
        _ expected: StreamStartupPreflightMode,
        in persistence: InMemoryAppSettingsPersistence,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> AppSettings {
        for _ in 0..<20 {
            let settings = try await persistence.load()
            if settings.startupPreflightMode == expected {
                return settings
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let settings = try await persistence.load()
        XCTAssertEqual(settings.startupPreflightMode, expected, file: file, line: line)
        return settings
    }

    private func waitForPersistedStreamEncodingMode(
        _ expected: StreamEncodingMode,
        in persistence: InMemoryAppSettingsPersistence,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> AppSettings {
        for _ in 0..<20 {
            let settings = try await persistence.load()
            if settings.streamEncodingMode == expected {
                return settings
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let settings = try await persistence.load()
        XCTAssertEqual(settings.streamEncodingMode, expected, file: file, line: line)
        return settings
    }

    private func waitForPersistedStartupGlanceScaleMode(
        _ expected: StreamStartupGlanceScaleMode,
        in persistence: InMemoryAppSettingsPersistence,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> AppSettings {
        for _ in 0..<20 {
            let settings = try await persistence.load()
            if settings.startupGlanceScaleMode == expected {
                return settings
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let settings = try await persistence.load()
        XCTAssertEqual(settings.startupGlanceScaleMode, expected, file: file, line: line)
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

    private func waitForPasteCommands(
        _ connector: FakeFirstFrameConnector,
        count expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<60 {
            if connector.pasteCommands.count >= expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(connector.pasteCommands.count, expectedCount, file: file, line: line)
    }

    private func waitForHelperInsertRequests(
        _ helper: FakeHelperTextInsertClient,
        count expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<60 {
            if helper.requests.count >= expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(helper.requests.count, expectedCount, file: file, line: line)
    }

    private func waitForHelperAvailability(
        _ model: NaruRemoteAppModel,
        profileID: ConnectionProfile.ID,
        availability expectedAvailability: HelperTextBridgeAvailability,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if model.snapshot.helperTextBridgeState[profileID]?.availability == expectedAvailability {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profileID]?.availability,
            expectedAvailability,
            file: file,
            line: line
        )
    }

    private func waitForHelperVideoAvailability(
        _ model: NaruRemoteAppModel,
        profileID: ConnectionProfile.ID,
        availability expectedAvailability: HelperVideoAvailability,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if model.snapshot.helperVideoProfileState[profileID]?.availability == expectedAvailability {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            model.snapshot.helperVideoProfileState[profileID]?.availability,
            expectedAvailability,
            file: file,
            line: line
        )
    }

    private func waitForHelperVideoHealth(
        _ model: NaruRemoteAppModel,
        state expectedState: HelperVideoStreamState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if model.snapshot.helperVideoStreamHealth.state == expectedState {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            model.snapshot.helperVideoStreamHealth.state,
            expectedState,
            file: file,
            line: line
        )
    }

    private func waitForPointerEvents(
        _ connector: FakeStreamingConnector,
        count expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<60 {
            if connector.recordedPointerEvents.count >= expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            connector.recordedPointerEvents.count,
            expectedCount,
            file: file,
            line: line
        )
    }

    private static func helperVideoStartResult(
        result: HelperVideoStartStreamResult = .accepted,
        descriptor: HelperVideoStreamDescriptor = HelperVideoStreamDescriptor(),
        safeFailureCode: HelperVideoFailureCode? = nil,
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>] = []
    ) -> HelperVideoStreamNetworkStartResult {
        let requestID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        return HelperVideoStreamNetworkStartResult(
            requestID: requestID,
            startResponse: HelperVideoWireEnvelope(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: "sha256:helper-video",
                body: HelperVideoStartStreamResponseBody(
                    result: result,
                    streamDescriptor: descriptor,
                    safeFailureCode: safeFailureCode
                )
            ),
            accessUnits: accessUnits
        )
    }

    private static func helperVideoAccessUnit(
        sequence: Int,
        kind: HelperVideoAccessUnitKind
    ) -> HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>> {
        HelperVideoDecodedFrame(
            envelope: HelperVideoWireEnvelope(
                messageType: .videoAccessUnit,
                profileFingerprint: "sha256:helper-video",
                body: HelperVideoAccessUnitBody(sequence: sequence, kind: kind)
            ),
            binaryPayload: Data([0, 0, 0, 1, 0x65, 0x88, 0x84, 0x21])
        )
    }

    private func waitForHelperServerPort(
        _ server: NaruHelperNetworkServer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> UInt16 {
        for _ in 0..<60 {
            if let port = server.port, port > 0 {
                return port
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for helper server port.", file: file, line: line)
        throw HelperTextBridgeError.unavailable(.unreachable)
    }

    private func waitForNetworkHelperInsertRequests(
        _ recorder: NetworkHelperInsertRecorder,
        count expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if recorder.requests.count >= expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(recorder.requests.count, expectedCount, file: file, line: line)
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

private final class NetworkHelperInsertRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [NaruHelperInsertTextRequest] = []

    var requests: [NaruHelperInsertTextRequest] {
        lock.withLock { recordedRequests }
    }

    var insertedTexts: [String] {
        requests.map(\.text)
    }

    func record(_ request: NaruHelperInsertTextRequest) {
        lock.withLock {
            recordedRequests.append(request)
        }
    }
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

private final class FakeHelperTextInsertClient: HelperTextInsertClient {
    fileprivate struct Recording {
        var requests: [HelperTextInsertRequestMetadata] = []
        var insertedTexts: [String] = []
    }

    private let recording = OSAllocatedUnfairLock(initialState: Recording())
    let availability: HelperTextBridgeAvailability
    private let result: HelperTextInsertResult?
    private let error: Error?
    private let insertDelayNanoseconds: UInt64

    init(
        availability: HelperTextBridgeAvailability = .reachable,
        result: HelperTextInsertResult? = nil,
        error: Error? = nil,
        insertDelayNanoseconds: UInt64 = 0
    ) {
        self.availability = availability
        self.result = result
        self.error = error
        self.insertDelayNanoseconds = insertDelayNanoseconds
    }

    var requests: [HelperTextInsertRequestMetadata] {
        recording.withLock { $0.requests }
    }

    var insertedTexts: [String] {
        recording.withLock { $0.insertedTexts }
    }

    func insertText(
        _ text: String,
        metadata: HelperTextInsertRequestMetadata
    ) async throws -> HelperTextInsertResult {
        if let error {
            throw error
        }
        recording.withLock { state in
            state.requests.append(metadata)
            state.insertedTexts.append(text)
        }
        if insertDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: insertDelayNanoseconds)
        }
        if let result {
            return result
        }
        return HelperTextInsertResult(
            requestID: metadata.id,
            strategyUsed: .nativeInsert,
            status: .sent,
            safeFailureCode: .none
        )
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
    let utf8ClipboardSupport: RemoteClipboardUTF8Support

    init(
        width: Int,
        height: Int,
        name: String,
        connectError: Error? = nil,
        utf8ClipboardSupport: RemoteClipboardUTF8Support = .unknown
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.connectError = connectError
        self.utf8ClipboardSupport = utf8ClipboardSupport
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

private enum FakeHelperVideoStartError: Error, Sendable {
    case transportUnavailable
}

private actor HelperVideoStartRecorder {
    struct Call: Equatable, Sendable {
        let profileID: ConnectionProfile.ID
        let pairingFingerprint: String
        let loadedSecretWasPresent: Bool
        let requestBody: HelperVideoStartStreamRequestBody
        let maxServerFrames: Int
    }

    private let result: HelperVideoStreamNetworkStartResult?
    private let failure: FakeHelperVideoStartError?
    private var recordedCalls: [Call] = []

    init(
        result: HelperVideoStreamNetworkStartResult? = nil,
        failure: FakeHelperVideoStartError? = nil
    ) {
        self.result = result
        self.failure = failure
    }

    func recordedCallSnapshot() -> [Call] {
        recordedCalls
    }

    func start(
        profile: ConnectionProfile,
        pairingSecret: String,
        pairingFingerprint: String,
        requestBody: HelperVideoStartStreamRequestBody,
        maxServerFrames: Int
    ) async throws -> HelperVideoStreamNetworkStartResult {
        recordedCalls.append(
            Call(
                profileID: profile.id,
                pairingFingerprint: pairingFingerprint,
                loadedSecretWasPresent: !pairingSecret.isEmpty,
                requestBody: requestBody,
                maxServerFrames: maxServerFrames
            )
        )
        if let failure {
            throw failure
        }
        guard let result else {
            throw FakeHelperVideoStartError.transportUnavailable
        }
        return result
    }
}

@MainActor
private final class AppModelFakeHelperVideoRenderer: HelperVideoAccessUnitRendering {
    private let displayableSequences: Set<Int>

    private(set) var enqueuedSequences: [Int] = []
    private(set) var flushCount = 0

    init(displayableSequences: Set<Int> = []) {
        self.displayableSequences = displayableSequences
    }

    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) throws -> Bool {
        let sequence = decoded.envelope.body.sequence
        enqueuedSequences.append(sequence)
        return displayableSequences.contains(sequence)
    }

    func flush() {
        flushCount += 1
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

private final class RecordingStreamConnectorFactory: @unchecked Sendable {
    struct Call: Equatable {
        let encodingPreference: RFBEncodingPreference
        let pixelFormatPreference: RFBPixelFormat?
    }

    private let connector: RFBFirstFrameConnecting
    private let recording = OSAllocatedUnfairLock(initialState: [Call]())

    init(connector: RFBFirstFrameConnecting) {
        self.connector = connector
    }

    var calls: [Call] {
        recording.withLock { $0 }
    }

    func make(
        encodingPreference: RFBEncodingPreference,
        pixelFormatPreference: RFBPixelFormat?
    ) -> RFBFirstFrameConnecting {
        recording.withLock { calls in
            calls.append(
                Call(
                    encodingPreference: encodingPreference,
                    pixelFormatPreference: pixelFormatPreference
                )
            )
        }
        return connector
    }
}

private final class FakeStreamingConnector: RFBStreamingClient, RFBRegionFramebufferUpdating, RFBFramebufferUpdateReceiving, RFBTransportControlClient, RFBContinuousUpdateCapabilityReporting {
    fileprivate struct Recording {
        var frameUpdates: [RFBFramebufferUpdateResult]
        var recordedSessionRequests: [FakeFirstFrameConnector.Request] = []
        var recordedFrameUpdateRequests: [Bool] = []
        var recordedFrameUpdateRegions: [RFBFramebufferUpdateRegion?] = []
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

    var frameUpdateRegions: [RFBFramebufferUpdateRegion?] {
        recording.withLock { $0.recordedFrameUpdateRegions }
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
        try requestFramebufferUpdate(
            incremental: incremental,
            timeout: timeout,
            region: nil
        )
    }

    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval,
        region: RFBFramebufferUpdateRegion?
    ) throws -> RFBFramebufferUpdateResult {
        let update = recording.withLock { state -> RFBFramebufferUpdateResult? in
            state.recordedFrameUpdateRequests.append(incremental)
            state.recordedFrameUpdateRegions.append(region)
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

private struct FailingConnectionProfilePersistenceError: Error {}

private actor FailingConnectionProfilePersistence: ConnectionProfilePersisting {
    private let profiles: [ConnectionProfile]

    init(profiles: [ConnectionProfile]) {
        self.profiles = profiles
    }

    func loadProfiles() throws -> [ConnectionProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [ConnectionProfile]) throws {
        throw FailingConnectionProfilePersistenceError()
    }
}
