import Foundation
import Combine
import os
import XCTest
import NaruHelperKit
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class NaruRemoteAppModelTests: XCTestCase {
    func testDefaultFrameStreamConfigurationLetsWorkerOwnActiveCadence() {
        let configuration = NaruRemoteAppModel.defaultFrameStreamConfiguration

        XCTAssertEqual(configuration.requestTimeout, 8)
        XCTAssertEqual(
            configuration.frameInterval,
            0,
            accuracy: 0.0001,
            "The application worker is the single content-rate authority; the request loop should not stack a second steady-state cap, so the active request floor is 0 (request as fast as the round-trip allows)."
        )
        XCTAssertEqual(configuration.idleFrameInterval, 0.05)
        XCTAssertEqual(configuration.updateMode, .continuousUpdates)
    }

    func testHelperVideoStartRequestPolicyPrefersReadabilityAtThirtyFPSWhenNominal() {
        let policy = HelperVideoStartRequestPolicy(
            streamPowerMode: .balanced,
            isSystemLowPowerModeEnabled: false,
            thermalState: .nominal,
            isNetworkConstrained: false,
            deviceSupportsHEVCDecode: false
        )

        XCTAssertEqual(policy.requestBody.codec, .h264)
        XCTAssertNil(policy.requestBody.acceptsHEVC)
        XCTAssertEqual(policy.requestBody.latencyMode, .lowLatency)
        XCTAssertEqual(policy.requestBody.qualityBucket, .readability)
        XCTAssertEqual(policy.requestBody.maxFrameRateBucket, .upTo30)
    }

    func testHelperVideoStartRequestPolicyDropsToFifteenFPSForPowerAndThermalPressure() {
        let constrainedPolicies = [
            HelperVideoStartRequestPolicy(
                streamPowerMode: .powerSaver,
                isSystemLowPowerModeEnabled: false,
                thermalState: .nominal,
                isNetworkConstrained: false,
                deviceSupportsHEVCDecode: false
            ),
            HelperVideoStartRequestPolicy(
                streamPowerMode: .balanced,
                isSystemLowPowerModeEnabled: true,
                thermalState: .nominal,
                isNetworkConstrained: false,
                deviceSupportsHEVCDecode: false
            ),
            HelperVideoStartRequestPolicy(
                streamPowerMode: .balanced,
                isSystemLowPowerModeEnabled: false,
                thermalState: .fair,
                isNetworkConstrained: false,
                deviceSupportsHEVCDecode: false
            ),
            HelperVideoStartRequestPolicy(
                streamPowerMode: .balanced,
                isSystemLowPowerModeEnabled: false,
                thermalState: .serious,
                isNetworkConstrained: false,
                deviceSupportsHEVCDecode: false
            ),
            HelperVideoStartRequestPolicy(
                streamPowerMode: .balanced,
                isSystemLowPowerModeEnabled: false,
                thermalState: .critical,
                isNetworkConstrained: false,
                deviceSupportsHEVCDecode: false
            )
        ]

        XCTAssertTrue(constrainedPolicies.allSatisfy {
            $0.requestBody.qualityBucket == .readability
                && $0.requestBody.maxFrameRateBucket == .upTo15
        })
    }

    func testHelperVideoStartRequestPolicyDropsToFifteenFPSWhenNetworkConstrained() {
        let policy = HelperVideoStartRequestPolicy(
            streamPowerMode: .balanced,
            isSystemLowPowerModeEnabled: false,
            thermalState: .nominal,
            isNetworkConstrained: true,
            deviceSupportsHEVCDecode: false
        )

        XCTAssertEqual(policy.requestBody.qualityBucket, .readability)
        XCTAssertEqual(policy.requestBody.maxFrameRateBucket, .upTo15)
        XCTAssertNil(policy.requestBody.acceptsHEVC)
    }

    func testHelperVideoStartRequestPolicyOffersHEVCWhenDeviceDecodeIsSupported() {
        let supported = HelperVideoStartRequestPolicy(
            streamPowerMode: .balanced,
            isSystemLowPowerModeEnabled: false,
            thermalState: .nominal,
            isNetworkConstrained: false,
            deviceSupportsHEVCDecode: true
        )
        let unsupported = HelperVideoStartRequestPolicy(
            streamPowerMode: .balanced,
            isSystemLowPowerModeEnabled: false,
            thermalState: .nominal,
            isNetworkConstrained: false,
            deviceSupportsHEVCDecode: false
        )

        XCTAssertEqual(supported.requestBody.codec, .h264)
        XCTAssertEqual(supported.requestBody.acceptsHEVC, true)
        XCTAssertNil(unsupported.requestBody.acceptsHEVC)
    }

    func testSessionStreamFrameApplicationQueueCoalescesContentBacklogToInitialAndLatestFrame() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let sessionID = RemoteSession(profileID: profile.id).id
        let streamID = UUID()
        let serverInit = Self.makeServerInit(width: 1, height: 1)
        let queue = SessionStreamFrameApplicationQueue()

        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 41,
                red: 41,
                isIncremental: false,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        for sequence in 42...46 {
            await queue.enqueue(
                Self.makeStreamFrameApplicationWork(
                    sequence: sequence,
                    red: UInt8(sequence),
                    isIncremental: true,
                    serverInit: serverInit,
                    profile: profile,
                    sessionID: sessionID,
                    streamID: streamID
                )
            )
        }
        await queue.close()

        let pendingCount = await queue.pendingCount()
        XCTAssertEqual(
            pendingCount,
            2,
            "A lagging UI worker should keep the initial connect frame and latest content frame, not every transient framebuffer."
        )
        let first = await queue.next()
        let latest = await queue.next()
        let done = await queue.next()

        XCTAssertEqual(first?.frame.sequence, 41)
        XCTAssertEqual(latest?.frame.sequence, 46)
        XCTAssertNil(done)
        XCTAssertEqual(SessionStreamFrameApplicationQueue.maximumPendingWorkCount, 3)
    }

    func testSessionStreamFrameApplicationQueueKeepsLatestCursorUpdateWhenContentBacklogIsCoalesced() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let sessionID = RemoteSession(profileID: profile.id).id
        let streamID = UUID()
        let serverInit = Self.makeServerInit(width: 1, height: 1)
        let queue = SessionStreamFrameApplicationQueue()
        let firstCursor = RFBServerCursor(
            width: 1,
            height: 1,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [RFBColor(red: 1, green: 1, blue: 1)]
        )
        let latestCursor = RFBServerCursor(
            width: 1,
            height: 1,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [RFBColor(red: 2, green: 2, blue: 2)]
        )

        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 1,
                red: 10,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 2,
                red: 10,
                isEmptyUpdate: true,
                serverCursor: firstCursor,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 3,
                red: 30,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 4,
                red: 30,
                isEmptyUpdate: true,
                serverCursor: latestCursor,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 5,
                red: 30,
                isEmptyUpdate: true,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 6,
                red: 60,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.close()

        let retained = [
            await queue.next(),
            await queue.next(),
            await queue.next()
        ]
        let done = await queue.next()

        XCTAssertEqual(retained.compactMap { $0?.frame.sequence }, [1, 4, 6])
        XCTAssertEqual(retained[1]?.frame.serverCursor, latestCursor)
        XCTAssertNil(done)
    }

    func testSessionStreamFrameApplicationQueueCanPreferControlUpdatesDuringContentPacing() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let sessionID = RemoteSession(profileID: profile.id).id
        let streamID = UUID()
        let serverInit = Self.makeServerInit(width: 1, height: 1)
        let queue = SessionStreamFrameApplicationQueue()
        let latestCursor = RFBServerCursor(
            width: 1,
            height: 1,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [RFBColor(red: 2, green: 2, blue: 2)]
        )

        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 10,
                red: 10,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 11,
                red: 10,
                isEmptyUpdate: true,
                serverCursor: latestCursor,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.close()

        let preferred = await queue.next(preferControlUpdates: true)
        let content = await queue.next(preferControlUpdates: true)
        let done = await queue.next(preferControlUpdates: true)

        XCTAssertEqual(preferred?.frame.sequence, 11)
        XCTAssertEqual(preferred?.frame.serverCursor, latestCursor)
        XCTAssertEqual(content?.frame.sequence, 10)
        XCTAssertNil(done)
    }

    func testSessionStreamFrameApplicationQueueReplacesStaleDequeuedContentAfterPacingSleep() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let sessionID = RemoteSession(profileID: profile.id).id
        let streamID = UUID()
        let serverInit = Self.makeServerInit(width: 1, height: 1)
        let queue = SessionStreamFrameApplicationQueue()
        let stale = Self.makeStreamFrameApplicationWork(
            sequence: 20,
            red: 20,
            serverInit: serverInit,
            profile: profile,
            sessionID: sessionID,
            streamID: streamID
        )

        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 21,
                red: 21,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )
        await queue.enqueue(
            Self.makeStreamFrameApplicationWork(
                sequence: 22,
                red: 22,
                serverInit: serverInit,
                profile: profile,
                sessionID: sessionID,
                streamID: streamID
            )
        )

        let replacement = await queue.latestContentWork(replacing: stale)
        let pendingCount = await queue.pendingCount()

        XCTAssertEqual(replacement.frame.sequence, 22)
        XCTAssertEqual(pendingCount, 0)
    }

    func testSessionFrameApplicationWorkerPacingDelaysRepeatedContentFrame() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let sessionID = RemoteSession(profileID: profile.id).id
        let streamID = UUID()
        let serverInit = Self.makeServerInit(width: 1, height: 1)
        let pacing = SessionFrameApplicationWorkerPacing()
        let lastContentAppliedAt = Date(timeIntervalSince1970: 100)
        let work = Self.makeStreamFrameApplicationWork(
            sequence: 1,
            red: 10,
            serverInit: serverInit,
            profile: profile,
            sessionID: sessionID,
            streamID: streamID
        )

        XCTAssertEqual(
            pacing.delay(
                before: work,
                lastContentFrameAppliedAt: lastContentAppliedAt,
                now: lastContentAppliedAt.addingTimeInterval(0.001)
            ),
            SessionFrameApplicationWorkerPacing.defaultContentFrameMinimumInterval - 0.001,
            accuracy: 0.0001
        )
    }

    func testSessionFrameApplicationWorkerPacingUsesInputAwareCadence() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let sessionID = RemoteSession(profileID: profile.id).id
        let streamID = UUID()
        let serverInit = Self.makeServerInit(width: 1, height: 1)
        let pacing = SessionFrameApplicationWorkerPacing()
        let lastContentAppliedAt = Date(timeIntervalSince1970: 100)
        let work = Self.makeStreamFrameApplicationWork(
            sequence: 1,
            red: 10,
            serverInit: serverInit,
            profile: profile,
            sessionID: sessionID,
            streamID: streamID
        )

        XCTAssertEqual(
            SessionFrameApplicationWorkerPacing.contentFrameMinimumInterval(for: .visual),
            1.0 / 60.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionFrameApplicationWorkerPacing.contentFrameMinimumInterval(for: .viewportNavigation),
            1.0 / 24.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SessionFrameApplicationWorkerPacing.contentFrameMinimumInterval(for: .textInput),
            1.0 / 30.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            pacing.delay(
                before: work,
                lastContentFrameAppliedAt: lastContentAppliedAt,
                now: lastContentAppliedAt.addingTimeInterval(0.001),
                contentFrameMinimumInterval: SessionFrameApplicationWorkerPacing
                    .contentFrameMinimumInterval(for: .textInput)
            ),
            SessionFrameApplicationWorkerPacing.textInputContentFrameMinimumInterval - 0.001,
            accuracy: 0.0001,
            "Focused Compose should pace MainActor frame application at the 30fps-class text-input cadence while keeping only the latest pending frame."
        )
    }

    func testSessionFrameApplicationWorkerPacingDoesNotDelayInitialContentFrame() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let sessionID = RemoteSession(profileID: profile.id).id
        let streamID = UUID()
        let serverInit = Self.makeServerInit(width: 1, height: 1)
        let pacing = SessionFrameApplicationWorkerPacing()
        let work = Self.makeStreamFrameApplicationWork(
            sequence: 1,
            red: 10,
            serverInit: serverInit,
            profile: profile,
            sessionID: sessionID,
            streamID: streamID
        )

        XCTAssertEqual(
            pacing.delay(
                before: work,
                lastContentFrameAppliedAt: nil,
                now: Date(timeIntervalSince1970: 100)
            ),
            0,
            accuracy: 0.0001
        )
    }

    func testSessionFrameApplicationWorkerPacingDoesNotDelayEmptyUpdates() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let sessionID = RemoteSession(profileID: profile.id).id
        let streamID = UUID()
        let serverInit = Self.makeServerInit(width: 1, height: 1)
        let pacing = SessionFrameApplicationWorkerPacing()
        let lastContentAppliedAt = Date(timeIntervalSince1970: 100)
        let cursor = RFBServerCursor(
            width: 1,
            height: 1,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [RFBColor(red: 1, green: 1, blue: 1)]
        )
        let work = Self.makeStreamFrameApplicationWork(
            sequence: 2,
            red: 10,
            isEmptyUpdate: true,
            serverCursor: cursor,
            serverInit: serverInit,
            profile: profile,
            sessionID: sessionID,
            streamID: streamID
        )

        XCTAssertEqual(
            pacing.delay(
                before: work,
                lastContentFrameAppliedAt: lastContentAppliedAt,
                now: lastContentAppliedAt
            ),
            0,
            accuracy: 0.0001
        )
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

    func testSessionStreamPacingPolicyUsesHelperVideoPrimaryVNCSamplingFloor() {
        let interval = StreamPressurePacingDefaults.helperVideoPrimaryVNCFallbackSamplingIntervalSeconds
        let contentDecision = SessionStreamPacingPolicy.decision(
            for: .contentFrame,
            configuredDelay: 0,
            thermalState: .nominal,
            helperVideoPrimaryVNCSamplingInterval: interval
        )

        XCTAssertEqual(contentDecision.delay, interval, accuracy: 0.0001)
        XCTAssertFalse(contentDecision.usesThermalPacing)
        XCTAssertFalse(contentDecision.usesPowerSaverPacing)
        XCTAssertFalse(contentDecision.usesEmptyBackoffPacing)
        XCTAssertFalse(contentDecision.usesViewportInteractionPacing)
        XCTAssertTrue(contentDecision.usesHelperVideoPrimaryVNCSamplingPacing)

        let idleDecision = SessionStreamPacingPolicy.decision(
            for: .emptyUpdate,
            configuredDelay: 0.05,
            thermalState: .nominal,
            helperVideoPrimaryVNCSamplingInterval: interval,
            emptyUpdateStreak: 24
        )

        XCTAssertEqual(idleDecision.delay, interval, accuracy: 0.0001)
        XCTAssertFalse(idleDecision.usesEmptyBackoffPacing)
        XCTAssertTrue(idleDecision.usesHelperVideoPrimaryVNCSamplingPacing)
    }

    func testSessionStreamPacingPolicyUsesActiveInputFloor() {
        let interval = StreamPressurePacingDefaults.textInputContentFrameIntervalSeconds
        let contentDecision = SessionStreamPacingPolicy.decision(
            for: .contentFrame,
            configuredDelay: StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds,
            thermalState: .nominal,
            activeInputPacingInterval: interval
        )

        XCTAssertEqual(contentDecision.delay, interval, accuracy: 0.0001)
        XCTAssertTrue(contentDecision.usesActiveInputPacing)
        XCTAssertFalse(contentDecision.usesViewportInteractionPacing)
        XCTAssertFalse(contentDecision.usesHelperVideoPrimaryVNCSamplingPacing)

        let emptyDecision = SessionStreamPacingPolicy.decision(
            for: .emptyUpdate,
            configuredDelay: 0.05,
            thermalState: .nominal,
            activeInputPacingInterval: interval,
            emptyUpdateStreak: 1
        )

        XCTAssertEqual(emptyDecision.delay, interval, accuracy: 0.0001)
        XCTAssertTrue(emptyDecision.usesActiveInputPacing)
        XCTAssertFalse(emptyDecision.usesEmptyBackoffPacing)
    }

    func testSessionStreamPacingPolicyUsesActiveInputEchoCadenceForSlowVisualStreams() {
        let interval = StreamPressurePacingDefaults.transientInputContentFrameIntervalSeconds
        let slowVisualDecision = SessionStreamPacingPolicy.decision(
            for: .contentFrame,
            configuredDelay: 1.5,
            thermalState: .nominal,
            activeInputPacingInterval: interval
        )

        XCTAssertEqual(slowVisualDecision.delay, interval, accuracy: 0.0001)
        XCTAssertTrue(slowVisualDecision.usesActiveInputPacing)
        XCTAssertFalse(slowVisualDecision.usesHelperVideoPrimaryVNCSamplingPacing)

        let helperFallbackDecision = SessionStreamPacingPolicy.decision(
            for: .contentFrame,
            configuredDelay: StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds,
            thermalState: .nominal,
            activeInputPacingInterval: interval,
            helperVideoPrimaryVNCSamplingInterval:
                StreamPressurePacingDefaults.helperVideoPrimaryVNCFallbackSamplingIntervalSeconds
        )

        XCTAssertEqual(helperFallbackDecision.delay, interval, accuracy: 0.0001)
        XCTAssertTrue(helperFallbackDecision.usesActiveInputPacing)
        XCTAssertFalse(
            helperFallbackDecision.usesHelperVideoPrimaryVNCSamplingPacing,
            "Pointer/keyboard echo must temporarily sample faster than the helper-video fallback cadence."
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

    func testSessionStreamPressurePacingStateActivatesAfterFrameApplicationBacklogDrop() {
        var state = SessionStreamPressurePacingState()
        let fastFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10
        )

        state.recordFrameApplicationBacklogDrop(1)
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)

        for _ in 0..<SessionStreamPressurePacingState.verySlowAdaptiveRecoveryUpdateCount {
            state.record(frame: fastFrame)
        }
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
    }

    func testSessionStreamPressurePacingStateUsesLongRecoveryForLargeFrameApplicationBacklogDrop() {
        var state = SessionStreamPressurePacingState()
        let fastFrame = pressureTestFrame(
            totalMilliseconds: 25,
            networkReadMilliseconds: 10
        )

        state.recordFrameApplicationBacklogDrop(3)
        XCTAssertTrue(state.usesAdaptivePowerSaverPacing)

        for _ in 0..<SessionStreamPressurePacingState.verySlowAdaptiveRecoveryUpdateCount {
            state.record(frame: fastFrame)
        }
        XCTAssertTrue(
            state.usesAdaptivePowerSaverPacing,
            "A larger frame-application backlog means the UI apply path fell materially behind, so recovery should last longer than the one-spike cooldown."
        )
        for _ in 0..<(SessionStreamPressurePacingState.adaptiveRecoveryUpdateCount - SessionStreamPressurePacingState.verySlowAdaptiveRecoveryUpdateCount) {
            state.record(frame: fastFrame)
        }
        XCTAssertFalse(state.usesAdaptivePowerSaverPacing)
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

    func testConnectProfileSelectsAndConnectsRequestedProfileAsOneIntent() async throws {
        let first = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let requested = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Studio")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [first, requested],
                selectedProfileID: first.id
            ),
            connectorFactory: { connector }
        )

        await model.connectProfile(id: requested.id)
        for _ in 0..<80 where model.snapshot.session?.state != .active {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.snapshot.selectedProfile?.id, requested.id)
        XCTAssertEqual(model.snapshot.session?.profileID, requested.id)
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(
            connector.requests,
            [FakeFirstFrameConnector.Request(host: requested.host, port: UInt16(requested.port))]
        )
    }

    func testDisconnectDropsLateNonStreamingFirstFrameSuccess() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connectGate = SynchronousConnectGate()
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            connectGate: connectGate
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )
        defer { connectGate.release() }

        await model.connectSelectedProfile()
        for _ in 0..<80 where !connectGate.hasEntered {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(connectGate.hasEntered)

        let disconnectedSessionID = try XCTUnwrap(model.snapshot.session?.id)
        model.disconnect()
        connectGate.release()
        for _ in 0..<80 where connector.completedRequestCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(connector.completedRequestCount, 1)
        XCTAssertEqual(model.snapshot.session?.id, disconnectedSessionID)
        XCTAssertEqual(model.snapshot.session?.state, .closed)
        XCTAssertEqual(model.snapshot.session?.hudMessage, "Disconnected")
        XCTAssertNotEqual(model.snapshot.diagnosticRun?.verdict, .passed)
        XCTAssertNil(model.snapshot.latestFramebuffer)
    }

    func testProfileSwitchDropsLateNonStreamingFirstFrameFailure() async throws {
        let first = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let connectGate = SynchronousConnectGate()
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            connectError: RFBNetworkClientError.connectionFailed,
            connectGate: connectGate
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [first, second],
                selectedProfileID: first.id
            ),
            connectorFactory: { connector }
        )
        defer { connectGate.release() }

        await model.connectSelectedProfile()
        for _ in 0..<80 where !connectGate.hasEntered {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(connectGate.hasEntered)

        model.selectProfile(id: second.id)
        let switchedSession = try XCTUnwrap(model.snapshot.session)
        connectGate.release()
        for _ in 0..<80 where connector.completedRequestCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(connector.completedRequestCount, 1)
        XCTAssertEqual(model.snapshot.selectedProfile?.id, second.id)
        XCTAssertEqual(model.snapshot.session, switchedSession)
        XCTAssertNotEqual(model.snapshot.session?.state, .failed)
        XCTAssertNil(model.snapshot.diagnosticRun)
    }

    func testDisconnectWhileCredentialLoadsDoesNotLaunchStaleTransport() async throws {
        let credentialRef = "vnc-password:blocked"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            credentialRef: credentialRef
        )
        let credentialStore = BlockingCredentialStore(password: "secret")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            connectorFactory: { connector }
        )

        let connectTask = Task { await model.connectSelectedProfile() }
        await credentialStore.waitForPasswordRequest()
        model.disconnect()
        await credentialStore.releasePasswordRequest()
        await connectTask.value
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(model.snapshot.session?.state, .closed)
        XCTAssertEqual(model.snapshot.session?.hudMessage, "Disconnected")
        XCTAssertEqual(connector.requests, [])
        XCTAssertNil(model.snapshot.latestFramebuffer)
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

    /// Rewritten for spec 017 (2026-08-19): the standard profile now DOES
    /// scope zoomed incremental requests (see
    /// `testAZoomedStandardProfileStillRequestsTheWholeFramebuffer`), so the
    /// still-valid "off" side of the gate is the power-saver override — it
    /// keeps every request full-frame even while zoomed.
    func testPowerSaverKeepsFullIncrementalStreamRequestsWhileZoomed() async throws {
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
        model.setStreamPowerMode(.powerSaver)

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

    func testLowTrafficIncrementalStreamFramesRequestTheWholeFramebuffer() async throws {
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
        // Spec 030, 2026-08-25: incremental requests are full-frame even when
        // the viewport is a zoomed crop. This assertion previously required the
        // scoped region and was inverted on measurement, not on preference —
        // against live Apple Screen Sharing (release, no conditioning, one axis
        // at a time, three repeats) a scoped request was answered in 540-787 ms
        // with a p95 at the client's idle timeout while a full-frame request was
        // answered in 33 ms, and content frame rate went 0.49-0.74 scoped
        // against 5.66-7.08 full. No other axis moved the result, and moving the
        // stimulus inside the region did not close the gap. The scoping policy
        // itself is still covered by ViewportRequestRegionPolicyTests.
        XCTAssertTrue(
            connector.frameUpdateRegions.allSatisfy { $0 == nil },
            "Incremental requests must cover the whole framebuffer (spec 030)."
        )
        XCTAssertEqual(connector.frameUpdateRegions.count, 2)
    }

    /// Spec 017: the default profile also scopes *incremental* requests to the
    /// visible viewport once the user zooms in. Un-zoomed sessions are
    /// unaffected — the policy returns nil (full request) when the visible
    /// region saves less than 10% of the framebuffer.
    func testAZoomedStandardProfileStillRequestsTheWholeFramebuffer() async throws {
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
        // No stream-profile opt-in: `.standard` is the product default.
        XCTAssertEqual(model.appSettings.streamEncodingMode, .standard)

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
        // Spec 030, 2026-08-25: incremental requests are full-frame even when
        // the viewport is a zoomed crop. This assertion previously required the
        // scoped region and was inverted on measurement, not on preference —
        // against live Apple Screen Sharing (release, no conditioning, one axis
        // at a time, three repeats) a scoped request was answered in 540-787 ms
        // with a p95 at the client's idle timeout while a full-frame request was
        // answered in 33 ms, and content frame rate went 0.49-0.74 scoped
        // against 5.66-7.08 full. No other axis moved the result, and moving the
        // stimulus inside the region did not close the gap. The scoping policy
        // itself is still covered by ViewportRequestRegionPolicyTests.
        XCTAssertTrue(
            connector.frameUpdateRegions.allSatisfy { $0 == nil },
            "Incremental requests must cover the whole framebuffer (spec 030)."
        )
        XCTAssertEqual(connector.frameUpdateRegions.count, 2)
    }

    /// Spec 017 keeps the *initial* request full-frame on the default profile:
    /// a region-scoped first frame leaves never-delivered framebuffer area
    /// unpainted until the server reports damage there, and that glance-startup
    /// trade stays opt-in (the RGB565 lanes, D110).
    func testStandardProfileKeepsFullInitialStreamRequestWhileZoomed() async throws {
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
        XCTAssertEqual(model.appSettings.streamEncodingMode, .standard)
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

    /// Spec 031: the default power mode keeps full resolution.
    ///
    /// The downscale was a compensation for slowness, and spec 030 found the
    /// slowness was viewport-scoped request regions — Apple answered those in
    /// 540-787 ms instead of 33 ms. The measurements that showed 5.66-7.08
    /// content fps after that fix were taken at full 3024x1964 resolution,
    /// because the live benchmark never sends ScaleFactor, so the pixels bought
    /// nothing that was still needed. The founder looked at build 9 and said so:
    /// "해상도 너무 낮은데... 왜 이렇게 뭉개지지".
    func testBalancedSessionKeepsFullResolution() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let (connector, model) = makeAppleDownscaleHarness(
            profile: profile,
            advertisedAppleSecurity: true,
            allowsDownscale: false
        )
        model.updateViewportTransform(Self.appleDownscaleLosslessUnzoomedTransform)

        await model.connectSelectedProfile()
        // Long enough that the policy's ten-tick threshold would have fired
        // several times over on the old default.
        try await Task.sleep(for: .milliseconds(900))

        XCTAssertTrue(
            connector.sentScaleFactors.isEmpty,
            "A balanced-power session must not trade resolution for latency it no longer needs."
        )
    }

    /// Spec 018: Apple-gated session sends ScaleFactor 0.5 exactly once after
    /// 10 consecutive un-zoomed lossless incremental ticks.
    func testAppleGatedSessionDownscalesAfterSustainedUnzoomedFit() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let (connector, model) = makeAppleDownscaleHarness(
            profile: profile,
            advertisedAppleSecurity: true
        )
        model.updateViewportTransform(Self.appleDownscaleLosslessUnzoomedTransform)

        await model.connectSelectedProfile()
        for _ in 0..<250 where connector.sentScaleFactors.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(connector.sentScaleFactors, [0.5])
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(connector.sentScaleFactors, [0.5])
    }

    /// Spec 018: after 0.5 is applied, a zoomed transform restores 1.0 on the
    /// next incremental tick.
    func testZoomInRestoresFullScaleImmediately() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let (connector, model) = makeAppleDownscaleHarness(
            profile: profile,
            advertisedAppleSecurity: true
        )
        model.updateViewportTransform(Self.appleDownscaleLosslessUnzoomedTransform)

        await model.connectSelectedProfile()
        for _ in 0..<250 where connector.sentScaleFactors.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(connector.sentScaleFactors, [0.5])

        model.updateViewportTransform(Self.appleDownscaleZoomedTransform)
        for _ in 0..<250 where connector.sentScaleFactors.last != 1.0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(connector.sentScaleFactors.last, 1.0)
        XCTAssertEqual(connector.sentScaleFactors, [0.5, 1.0])
    }

    /// Spec 018 FR-001: a non-Apple fake never receives ScaleFactor, even
    /// after the same un-zoomed lossless script that would downscale Apple.
    func testNonAppleServerNeverReceivesScaleFactor() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let (connector, model) = makeAppleDownscaleHarness(
            profile: profile,
            advertisedAppleSecurity: false
        )
        model.updateViewportTransform(Self.appleDownscaleLosslessUnzoomedTransform)

        await model.connectSelectedProfile()
        for _ in 0..<250 where connector.frameUpdateRequests.count < 12 {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertGreaterThanOrEqual(connector.frameUpdateRequests.count, 11)
        XCTAssertGreaterThan(
            connector.advertisedAppleSecurityReadCount,
            0,
            "The model must consult the Apple security gate rather than simply never sending."
        )
        XCTAssertTrue(connector.sentScaleFactors.isEmpty)
    }

    /// Spec 018 pointer mapping: screensharingd's pointer input space stays
    /// the UNSCALED framebuffer while ScaleFactor 0.5 is applied
    /// (live-measured 2026-08-20). Once the fake applies the resize, a tap
    /// computed in the scaled framebuffer must leave the model doubled back
    /// into unscaled coordinates.
    func testPointerCoordinatesMapToUnscaledSpaceWhileDownscaled() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let (connector, model) = makeAppleDownscaleHarness(
            profile: profile,
            advertisedAppleSecurity: true
        )
        connector.appliesScaleFactorResize = true
        model.updateViewportTransform(Self.appleDownscaleLosslessUnzoomedTransform)

        await model.connectSelectedProfile()
        for _ in 0..<250 where connector.sentScaleFactors.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(connector.sentScaleFactors, [0.5])

        // Wait for the resized framebuffer (fake's DesktopSize analogue) to
        // reach the model, so the tap below is computed in scaled space.
        for _ in 0..<250 where model.snapshot.latestFramebuffer?.width != 60 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer?.width, 60)

        model.sendTapAt(viewPoint: CGPoint(x: 10, y: 10), viewSize: CGSize(width: 20, height: 20))
        for _ in 0..<250 where connector.recordedPointerEvents.count < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }

        // View center → scaled framebuffer (30, 30) → unscaled wire (60, 60).
        XCTAssertEqual(connector.recordedPointerEvents.map(\.mask), [1, 0])
        XCTAssertEqual(connector.recordedPointerEvents.map(\.x), [60, 60])
        XCTAssertEqual(connector.recordedPointerEvents.map(\.y), [60, 60])
        model.disconnect()
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
        for _ in 0..<40 where model.snapshot.sessionStreamStats.appFrameApplyTimingSampleCount < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        let performance = try XCTUnwrap(model.makeDiagnosticExport().streamPerformance)
        XCTAssertEqual(performance.adaptiveClientPressurePacingSampleCount, 2)
        XCTAssertEqual(performance.adaptiveClientPressurePacingPermille, 500)
        XCTAssertEqual(
            performance.appFrameApplyTimingSampleCount,
            2,
            "The paced frame-apply worker should keep the initial visual state and the latest coalesced state instead of replaying every stale intermediate frame."
        )
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

    func testModelRenegotiatesPowerSaverSustainedEncodingProfileWhenNetworkConstrained() async throws {
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
            lowPowerModeProvider: { false },
            networkPathConditionsProvider: {
                NetworkPathConditions(isExpensive: false, isConstrained: true)
            }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(connector.renegotiatedPreferences, [.powerSaverSustained])
    }

    func testModelLetsNetworkConstrainedOverrideRGB565LowTrafficStreamConnectorOnConnect() async throws {
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
            lowPowerModeProvider: { false },
            networkPathConditionsProvider: {
                NetworkPathConditions(isExpensive: false, isConstrained: true)
            }
        )
        model.setStreamEncodingMode(.zrleCompressionZeroRGB565)

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

    func testModelKeepsRGB565LowTrafficStreamConnectorWhenNetworkIsExpensiveOnly() async throws {
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
            lowPowerModeProvider: { false },
            networkPathConditionsProvider: {
                NetworkPathConditions(isExpensive: true, isConstrained: false)
            }
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
        for _ in 0..<120 where model.snapshot.latestFramebuffer != framebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffer)

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

    func testHelperVideoBootstrapKeepsVNCControlPathActive() async throws {
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
            helperVideoRendererFactory: { helperRenderer },
            thermalStateProvider: { .nominal },
            lowPowerModeProvider: { false }
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
        XCTAssertEqual(calls.first?.requestBody.qualityBucket, .readability)
        XCTAssertEqual(calls.first?.requestBody.maxFrameRateBucket, .upTo30)
        XCTAssertEqual(snapshot.session?.state, .active)
        XCTAssertEqual(snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(snapshot.visualTransportMode, VisualTransportMode.helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamDescriptor?.codecProfile, .baseline)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, nil)
        XCTAssertEqual(connector.recordedPointerEvents.map(\.mask), [1, 0])
    }

    func testHelperVideoBootstrapReportsOutcomeAndUsesInjectedFrameLimit() async throws {
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
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            )
        )
        let helperRecorder = HelperVideoStartRecorder(
            result: Self.helperVideoStartResult(
                descriptor: HelperVideoStreamDescriptor(codecProfile: .baseline),
                accessUnits: [
                    Self.helperVideoAccessUnit(sequence: 0, kind: .parameterSet),
                    Self.helperVideoAccessUnit(sequence: 1, kind: .keyframe),
                    Self.helperVideoAccessUnit(sequence: 2, kind: .delta),
                    Self.helperVideoAccessUnit(sequence: 3, kind: .delta)
                ]
            )
        )
        let helperRenderer = AppModelFakeHelperVideoRenderer(displayableSequences: [1, 2, 3])
        let outcomeRecorder = AppModelHelperVideoOutcomeRecorder()
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
            helperVideoRendererFactory: { helperRenderer },
            helperVideoMaxServerFrames: 5,
            helperVideoStreamOutcomeHandler: { _, profileID, outcome in
                guard profileID == profile.id else { return }
                await outcomeRecorder.record(outcome)
            }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)
        let outcome = try await waitForHelperVideoOutcome(outcomeRecorder)

        let calls = await helperRecorder.recordedCallSnapshot()
        XCTAssertEqual(calls.first?.maxServerFrames, 5)
        XCTAssertEqual(outcome.displayableFrameCount, 3)
        XCTAssertEqual(outcome.receivedAccessUnitCount, 4)
        XCTAssertNil(outcome.fallbackFailureCode)
    }

    func testHelperVideoBootstrapRequestsFifteenFPSInSystemLowPowerMode() async throws {
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
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            )
        )
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
            helperVideoRendererFactory: { helperRenderer },
            lowPowerModeProvider: { true }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)

        let calls = await helperRecorder.recordedCallSnapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.requestBody.qualityBucket, .readability)
        XCTAssertEqual(calls.first?.requestBody.maxFrameRateBucket, .upTo15)
    }

    func testHelperVideoBootstrapOffersHEVCWhenDecodeProviderReportsSupport() async throws {
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
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            )
        )
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
            helperVideoRendererFactory: { helperRenderer },
            lowPowerModeProvider: { false },
            hevcDecodeSupportProvider: { true }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)

        let calls = await helperRecorder.recordedCallSnapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.requestBody.codec, .h264)
        XCTAssertEqual(calls.first?.requestBody.acceptsHEVC, true)
    }

    func testHelperVideoBootstrapOmitsHEVCOfferWhenDecodeProviderReportsUnsupported() async throws {
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
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            )
        )
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
            helperVideoRendererFactory: { helperRenderer },
            lowPowerModeProvider: { false },
            hevcDecodeSupportProvider: { false }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)

        let calls = await helperRecorder.recordedCallSnapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.requestBody.codec, .h264)
        XCTAssertNil(calls.first?.requestBody.acceptsHEVC)
    }

    func testHelperVideoBootstrapRequestsFifteenFPSWhenNetworkConstrained() async throws {
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
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            )
        )
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
            helperVideoRendererFactory: { helperRenderer },
            thermalStateProvider: { .nominal },
            lowPowerModeProvider: { false },
            networkPathConditionsProvider: {
                NetworkPathConditions(isExpensive: false, isConstrained: true)
            }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)

        let calls = await helperRecorder.recordedCallSnapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.requestBody.qualityBucket, .readability)
        XCTAssertEqual(calls.first?.requestBody.maxFrameRateBucket, .upTo15)
    }

    func testModelDoesNotCapStreamsWhenNetworkIsExpensiveOnly() async throws {
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
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            )
        )
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
            helperVideoRendererFactory: { helperRenderer },
            thermalStateProvider: { .nominal },
            lowPowerModeProvider: { false },
            networkPathConditionsProvider: {
                NetworkPathConditions(isExpensive: true, isConstrained: false)
            }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)

        let calls = await helperRecorder.recordedCallSnapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.requestBody.qualityBucket, .readability)
        XCTAssertEqual(calls.first?.requestBody.maxFrameRateBucket, .upTo30)
        XCTAssertEqual(connector.renegotiatedPreferences, [])
    }

    func testHelperVideoPrimarySamplesVNCFallbackAndKeepsControlPathActive() async throws {
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
        let framebuffers = (1...3).map { red in
            RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: UInt8(red), green: 20, blue: 30)
            )
        }
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffers: framebuffers,
            frameUpdateDelay: 0.08
        )
        let helperRecorder = HelperVideoStartRecorder(
            result: Self.helperVideoStartResult(
                descriptor: HelperVideoStreamDescriptor(codecProfile: .baseline),
                accessUnits: [
                    Self.helperVideoAccessUnit(sequence: 1, kind: .keyframe)
                ]
            )
        )
        let helperRenderer = AppModelFakeHelperVideoRenderer(displayableSequences: [1])
        let pacingGate = PacingSleepGate()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: [helperVideoSecretRef: "helper-video-secret"]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 3, frameInterval: 0),
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
            helperVideoRendererFactory: { helperRenderer },
            streamPacingSleep: { delay in
                try await pacingGate.sleep(delay)
            }
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)
        try await waitForLatestFramebuffer(model)
        try await pacingGate.waitForWaitCount(1)

        var delays = await pacingGate.delays
        let firstDelay = try XCTUnwrap(delays.first)
        XCTAssertEqual(
            firstDelay,
            StreamPressurePacingDefaults.helperVideoPrimaryVNCFallbackSamplingIntervalSeconds,
            accuracy: 0.0001
        )
        XCTAssertEqual(model.snapshot.visualTransportMode, .helperVideo)
        XCTAssertEqual(model.snapshot.sessionStreamStats.helperVideoPrimaryVNCSamplingPacingSampleCount, 1)

        model.sendTapAt(viewPoint: CGPoint(x: 1, y: 0.5), viewSize: CGSize(width: 2, height: 1))
        try await waitForPointerEvents(connector, count: 2)
        XCTAssertEqual(
            connector.recordedPointerEvents.map(\.mask),
            [1, 0],
            "VNC must remain the control plane while helper-video owns the visual plane."
        )

        await pacingGate.releaseNext()
        try await pacingGate.waitForWaitCount(2)
        model.updateHelperVideoStreamHealth(
            HelperVideoStreamHealth(
                state: .stalled,
                sustainedUpdateBand: .stalled,
                fallbackCountBucket: .one
            )
        )
        XCTAssertEqual(model.snapshot.visualTransportMode, .vncFramebuffer)

        await pacingGate.releaseNext()
        for _ in 0..<120 where model.snapshot.latestFramebuffer != framebuffers[2] {
            try await Task.sleep(for: .milliseconds(10))
        }

        delays = await pacingGate.delays
        XCTAssertEqual(delays.count, 2)
        XCTAssertEqual(
            delays[1],
            StreamPressurePacingDefaults.transientInputContentFrameIntervalSeconds,
            accuracy: 0.0001,
            "Pointer input should temporarily sample the VNC control plane faster than the helper-video fallback cadence."
        )
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffers[2])
        XCTAssertEqual(model.snapshot.sessionStreamStats.helperVideoPrimaryVNCSamplingPacingSampleCount, 1)
        XCTAssertEqual(model.snapshot.sessionStreamStats.activeInputPacingSampleCount, 1)
    }

    func testHelperVideoFallbackWakesVNCFallbackSamplingSleepEarly() async throws {
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
        let firstFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let fallbackFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 40, green: 20, blue: 30)
        )
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, fallbackFramebuffer],
            frameUpdateDelay: 0.05
        )
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
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
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
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)
        for _ in 0..<120 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)

        let fallbackStartedAt = Date()
        model.updateHelperVideoStreamHealth(
            HelperVideoStreamHealth(
                state: .stalled,
                sustainedUpdateBand: .stalled,
                fallbackCountBucket: .one
            )
        )

        for _ in 0..<120 where model.snapshot.latestFramebuffer != fallbackFramebuffer {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(model.snapshot.latestFramebuffer, fallbackFramebuffer)
        XCTAssertLessThan(
            Date().timeIntervalSince(fallbackStartedAt),
            StreamPressurePacingDefaults.helperVideoPrimaryVNCFallbackSamplingIntervalSeconds,
            "Fallback must wake the helper-primary VNC sampling sleep instead of waiting for the full cadence slot."
        )
    }

    func testHelperVideoBootstrapStartsBeforeSlowVNCFirstFrame() async throws {
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
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: framebuffer,
            frameUpdateDelay: 0.4
        )
        let helperRecorder = HelperVideoStartRecorder(
            result: Self.helperVideoStartResult(
                descriptor: HelperVideoStreamDescriptor(codecProfile: .high),
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
        try await waitForHelperVideoStartCalls(helperRecorder, count: 1)

        XCTAssertNil(
            model.snapshot.latestFramebuffer,
            "Helper video should no longer wait for the VNC first framebuffer before starting."
        )
        XCTAssertEqual(model.snapshot.visualTransportMode, .helperVideo)
        XCTAssertEqual(model.snapshot.helperVideoStreamDescriptor?.codecProfile, .high)
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profile.id]?.availability, .available)

        try await waitForLatestFramebuffer(model)
        model.disconnect()
    }

    func testPointerInputCanUseServerInitCoordinateSpaceBeforeFirstFramebuffer() async throws {
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
            width: 4,
            height: 2,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let connector = FakeStreamingConnector(
            width: 4,
            height: 2,
            name: "Desk",
            framebuffer: framebuffer,
            frameUpdateDelay: 1.0
        )
        let helperVideoResult = Self.helperVideoStartResult(
            descriptor: HelperVideoStreamDescriptor(codecProfile: .high),
            accessUnits: [
                Self.helperVideoAccessUnit(sequence: 1, kind: .keyframe)
            ]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: [helperVideoSecretRef: "helper-video-secret"]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            helperVideoStartStream: { _, _, _, _, _ in
                helperVideoResult
            },
            helperVideoRendererFactory: {
                AppModelFakeHelperVideoRenderer(displayableSequences: [1])
            }
        )

        await model.connectSelectedProfile()
        try await waitForInputCoordinateSpace(model)

        XCTAssertNil(
            model.snapshot.latestFramebuffer,
            "This assertion keeps the regression focused on the pre-first-frame input window."
        )

        model.sendTapAt(viewPoint: CGPoint(x: 1, y: 0.5), viewSize: CGSize(width: 4, height: 2))
        try await waitForPointerEvents(connector, count: 2)

        XCTAssertNil(model.snapshot.latestFramebuffer)
        XCTAssertEqual(connector.recordedPointerEvents.map(\.mask), [1, 0])
        XCTAssertEqual(connector.recordedPointerEvents.map(\.x), [1, 1])
        XCTAssertEqual(connector.recordedPointerEvents.map(\.y), [0, 0])
        model.disconnect()
    }

    func testHelperVideoBootstrapPrefersContinuousOpenStreamAfterVNCFirstFrame() async throws {
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
            fill: RFBColor(red: 8, green: 16, blue: 24)
        )
        let connector = FakeStreamingConnector(width: 2, height: 1, name: "Desk", framebuffer: framebuffer)
        let descriptor = HelperVideoStreamDescriptor(codecProfile: .high, frameRateBucket: .upTo30)
        let helperRecorder = HelperVideoOpenStreamRecorder(
            descriptor: descriptor,
            accessUnits: [
                Self.helperVideoAccessUnit(sequence: 0, kind: .parameterSet),
                Self.helperVideoAccessUnit(sequence: 1, kind: .keyframe),
                Self.helperVideoAccessUnit(sequence: 2, kind: .delta)
            ]
        )
        let helperRenderer = AppModelFakeHelperVideoRenderer(displayableSequences: [1, 2])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: [helperVideoSecretRef: "helper-video-secret"]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            helperVideoOpenStream: { profile, pairingSecret, pairingFingerprint, requestBody in
                helperRecorder.open(
                    profile: profile,
                    pairingSecret: pairingSecret,
                    pairingFingerprint: pairingFingerprint,
                    requestBody: requestBody
                )
            },
            helperVideoRendererFactory: { helperRenderer }
        )

        await model.connectSelectedProfile()
        try await waitForHelperVideoHealth(model, state: .healthy)
        model.sendTapAt(viewPoint: CGPoint(x: 1, y: 0.5), viewSize: CGSize(width: 2, height: 1))
        try await waitForPointerEvents(connector, count: 2)

        let calls = helperRecorder.recordedCallSnapshot()
        let snapshot = model.snapshot
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.profileID, profile.id)
        XCTAssertEqual(calls.first?.pairingFingerprint, "sha256:helper-video")
        XCTAssertEqual(calls.first?.loadedSecretWasPresent, true)
        XCTAssertEqual(snapshot.session?.state, .active)
        XCTAssertEqual(snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(snapshot.visualTransportMode, VisualTransportMode.helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamDescriptor, descriptor)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertEqual(helperRenderer.enqueuedSequences, [0, 1, 2])
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

    func testHelperVideoCallbacksAfterInactiveSessionDoNotMutateVisualOrProfileState() throws {
        let inactiveStates: [(String, RemoteSessionState)] = [
            ("failed", .failed),
            ("closed", .closed)
        ]

        for (label, inactiveState) in inactiveStates {
            let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
            let session = RemoteSession(
                profileID: profile.id,
                state: inactiveState,
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

            model.updateHelperVideoStreamHealth(
                HelperVideoStreamHealth(
                    state: .stalled,
                    sustainedUpdateBand: .stalled,
                    fallbackCountBucket: .one
                ),
                sessionID: session.id,
                profileID: profile.id
            )
            model.setHelperVideoProfileState(
                HelperVideoProfileState(
                    isEnabled: true,
                    pairingFingerprint: "sha256:helper-video",
                    availability: .failed,
                    lastFailureCode: .streamStalled,
                    lastCheckedBucket: .recent
                ),
                for: profile.id,
                sessionID: session.id
            )

            let snapshot = model.snapshot
            XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer, label)
            XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .idle, label)
            XCTAssertNil(snapshot.helperVideoStreamDescriptor, label)
            XCTAssertNil(snapshot.helperVideoVisualSelectionFailureReason, label)
            XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available, label)
            XCTAssertNil(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, label)
        }
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

    func testModelPrefersReachableHelperForComposePayloadsEvenWhenVNCPasteCouldRun() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(
            width: 1440,
            height: 900,
            name: "Desk",
            utf8ClipboardSupport: .supported
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

        model.updateComposeDraftText("status")
        let asciiPreflightJSON = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let asciiPreflightReport = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(asciiPreflightJSON.utf8)
        )
        XCTAssertEqual(asciiPreflightReport.input?.composePlannedPath, TextInjectionPath.helperTextBridge.rawValue)

        model.sendComposedText("status", pasteCommand: .commandV)
        try await waitForHelperInsertRequests(helper, count: 1)
        try await waitForComposeSendState(model, .sent)

        XCTAssertEqual(helper.insertedTexts, ["status"])
        XCTAssertEqual(helper.requests.first?.strategyPreferences, [.nativeInsert])
        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .helperTextBridge)
        XCTAssertNil(model.snapshot.latestInjectionAttempt?.pasteCommand)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.payloadEncoding, .ascii)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .sent)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.helperStrategyUsed, .nativeInsert)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sent)

        model.updateComposeDraftText("한글과 English 😊")
        let utf8PreflightJSON = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let utf8PreflightReport = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(utf8PreflightJSON.utf8)
        )
        XCTAssertEqual(utf8PreflightReport.input?.composePlannedPath, TextInjectionPath.helperTextBridge.rawValue)

        model.sendComposedText("한글과 English 😊", pasteCommand: .controlV)
        try await waitForHelperInsertRequests(helper, count: 2)
        try await waitForComposeSendState(model, .sent)

        XCTAssertEqual(helper.insertedTexts, ["status", "한글과 English 😊"])
        XCTAssertEqual(helper.requests.last?.strategyPreferences, [.nativeInsert])
        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .helperTextBridge)
        XCTAssertNil(model.snapshot.latestInjectionAttempt?.pasteCommand)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .sent)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.helperStrategyUsed, .nativeInsert)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sent)
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
        XCTAssertEqual(helper.requests.first?.strategyPreferences, [.nativeInsert])
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .helperTextBridge)
        XCTAssertNil(model.snapshot.latestInjectionAttempt?.pasteCommand)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .sent)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.helperStrategyUsed, .nativeInsert)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardSetStatus, .notAttempted)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommandStatus, .notAttempted)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sent)
        XCTAssertEqual(model.snapshot.composeDraft?.lastStatusMessage, "Inserted into the remote app.")
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
        XCTAssertEqual(report.input?.latestInjectionHelperStrategy, HelperTextInsertStrategy.nativeInsert.rawValue)
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

    // QW3: a confirmed helper native insert reports a distinct positive
    // status ("Inserted into the remote app.") rather than the unknown
    // "confirmation unavailable" copy the clipboard path is stuck with.
    func testHelperNativeInsertReportsConfirmedPositiveStatus() async throws {
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
        model.sendComposedText("한글과 English 😊")
        try await waitForHelperInsertRequests(helper, count: 1)
        for _ in 0..<60 where model.snapshot.composeDraft?.sendState == .sending {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .sent)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.helperStrategyUsed, .nativeInsert)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Inserted into the remote app."
        )
        XCTAssertEqual(model.snapshot.inputStatusText, "Inserted into the remote app.")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sent)

        // The fixed positive copy must not leak composed content into the
        // diagnostic export, which stays on the enum-rawValue safe catalog.
        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        XCTAssertFalse(json.contains("Inserted into the remote app"))
        XCTAssertFalse(json.contains("한글과 English"))
    }

    // QW3: a non-confirming helper result (e.g. pasteboard fallback that
    // could not confirm restore) keeps the honest safe-catalog copy rather
    // than claiming a confirmed insert.
    func testHelperNonNativeInsertKeepsSafeCatalogStatus() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let helper = FakeHelperTextInsertClient(
            result: HelperTextInsertResult(
                requestID: UUID(),
                strategyUsed: .pasteboardPasteWithRestore,
                status: .unknown,
                safeFailureCode: .restoreFailed
            ),
            stampRequestID: true
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

        model.updateComposeDraftText("status")
        model.sendComposedText("status")
        try await waitForHelperInsertRequests(helper, count: 1)
        for _ in 0..<60 where model.snapshot.composeDraft?.sendState == .sending {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Inserted into the remote app.",
            "Only a confirmed native insert may claim the text landed."
        )
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            HelperTextBridgeError.safeMessage(for: .restoreFailed)
        )
    }

    // QW2: the 0.30s clipboard settle exists only so the remote clipboard
    // adopts the payload before Cmd-V. The helper native-insert route never
    // touches the clipboard, so its attempt must complete without paying
    // that latency.
    func testHelperNativeInsertRouteSkipsClipboardPasteSettleDelay() async throws {
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

        model.updateComposeDraftText("status")
        model.sendComposedText("status")
        try await waitForHelperInsertRequests(helper, count: 1)
        for _ in 0..<60 where model.snapshot.composeDraft?.sendState == .sending {
            try await Task.sleep(for: .milliseconds(10))
        }

        let attempt = try XCTUnwrap(model.snapshot.latestInjectionAttempt)
        XCTAssertEqual(attempt.path, .helperTextBridge)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sent)
        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        let finished = try XCTUnwrap(attempt.finishedAt)
        XCTAssertLessThan(
            finished.timeIntervalSince(attempt.startedAt),
            0.25,
            "Helper native insert must not pay the 0.30s clipboard settle delay."
        )
    }

    func testReachableHelperWithoutNativeInsertPermissionDoesNotReceiveComposePayload() async throws {
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
                        lastFailureCode: nil,
                        lastCheckedBucket: .recent,
                        capabilitySummary: HelperTextBridgeCapabilitySummary(
                            nativeInsert: .missing,
                            accessibilityValueInsert: .missing,
                            unicodeKeyboardEvent: .missing,
                            pasteboardFallback: .available
                        )
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
        XCTAssertNil(preflightReport.input?.composePlannedPath)
        XCTAssertEqual(
            preflightReport.input?.composeRouteBlocker,
            DiagnosticComposeRouteBlocker.helperPermissionMissing.rawValue
        )

        model.sendComposedText("한글과 English 😊", pasteCommand: .commandV)
        for _ in 0..<60 where model.snapshot.latestInjectionAttempt?.status != .failed {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(helper.requests.isEmpty)
        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .vncClipboardPaste)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text clipboard unavailable: This VNC server reported that UTF-8 clipboard support is unavailable, so Korean/CJK/emoji Compose text cannot be sent reliably. Helper text bridge needs permission on the Mac."
        )
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .permissionMissing)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .permissionMissing)
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
                        accessibilityValueInsert: "granted",
                        unicodeKeyboardEvent: "granted",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.nativeInsert, .pasteboardPasteWithRestore]
                )
            },
            insertHandler: { request in
                recorder.record(request)
                return NaruHelperInsertTextResponse(
                    requestID: request.requestID,
                    status: .sent,
                    strategyUsed: .nativeInsert
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
        try await waitForComposeSendState(model, .sent)

        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(recorder.insertedTexts, ["한글과 English 😊"])
        XCTAssertEqual(recorder.requests.first?.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(recorder.requests.first?.strategyPreference, [.nativeInsert])
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .helperTextBridge)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .sent)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.helperStrategyUsed, .nativeInsert)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .sent)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .reachable)
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode,
            HelperTextBridgeFailureCode.none
        )
    }

    func testStoredHelperReachableButNativeInsertMissingBlocksComposeBeforePayloadSend() async throws {
        let helperSecretRef = "helper-token:desk"
        let recorder = NetworkHelperInsertRecorder()
        let handler = NaruHelperNetworkRequestHandler(
            expectedPairingSecret: "helper-secret",
            capabilityProvider: {
                NaruHelperCapabilityResponse(
                    availability: .reachable,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "missing",
                        accessibilityValueInsert: "missing",
                        unicodeKeyboardEvent: "missing",
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
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .permissionMissing)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode, .permissionMissing)
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.capabilitySummary?.nativeInsert,
            .missing
        )
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.capabilitySummary?.pasteboardFallback,
            .available
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
                        accessibility: "missing",
                        accessibilityValueInsert: "missing",
                        unicodeKeyboardEvent: "granted",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "missing",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.nativeInsert]
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
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.capabilitySummary?.nativeInsert,
            .available
        )
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.capabilitySummary?.accessibilityValueInsert,
            .missing
        )
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.capabilitySummary?.unicodeKeyboardEvent,
            .granted
        )
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.capabilitySummary?.pasteboardFallback,
            .missing
        )
        XCTAssertEqual(model.snapshot.inputHelperStatusText, "Helper ready for Unicode text insert")

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let report = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(report.input?.helperTextBridgeNativeInsert, HelperTextBridgeRouteCapability.available.rawValue)
        XCTAssertEqual(
            report.input?.helperTextBridgeAccessibilityValueInsert,
            HelperTextBridgeRouteCapability.missing.rawValue
        )
        XCTAssertEqual(
            report.input?.helperTextBridgeUnicodeKeyboardEvent,
            HelperTextBridgeRouteCapability.granted.rawValue
        )
        XCTAssertEqual(
            report.input?.helperTextBridgePasteboardFallback,
            HelperTextBridgeRouteCapability.missing.rawValue
        )
        XCTAssertFalse(json.contains("helper-fingerprint"))
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

    func testModelRejectsUTF8ComposeWhenClipboardSupportIsUnconfirmedWithoutHelper() async throws {
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

        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardTransferMode, .legacyClientCutText)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardSetStatus, .notAttempted)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommandStatus, .notAttempted)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.utf8ClipboardSupport, .unknown)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text clipboard unavailable: This VNC server has not confirmed UTF-8 clipboard support, so Korean/CJK/emoji Compose text cannot be sent reliably. Helper text bridge is not configured for this profile."
        )
        XCTAssertEqual(
            model.snapshot.helperTextBridgeState[profile.id]?.lastFailureCode,
            .notConfigured
        )
    }

    func testModelRejectsUTF8ComposeWhenStoredHelperIsKnownUnreachable() async throws {
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

        XCTAssertTrue(connector.clipboardPayloads.isEmpty)
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.path, .vncClipboardPaste)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.helperTextBridgeState[profile.id]?.availability, .unreachable)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text clipboard unavailable: This VNC server has not confirmed UTF-8 clipboard support, so Korean/CJK/emoji Compose text cannot be sent reliably. Helper text bridge is not reachable."
        )
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

    func testFocusedComposeEditingDefersStaleSendFeedbackClearUntilFocusLeaves() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let attempt = TextInjectionAttempt(
            draftID: UUID(),
            sessionID: session.id,
            path: .vncClipboardPaste,
            status: .unknown,
            safeMessage: "Paste command sent; remote app confirmation unavailable."
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: ""),
                latestInjectionAttempt: attempt
            )
        )

        model.setComposeInputEditingActive(true)
        model.updateComposeDraftText("입")

        XCTAssertEqual(model.snapshot.composeDraft?.text, "입")
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.safeMessage, attempt.safeMessage)

        model.setComposeInputEditingActive(false)

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

    func testEditingComposeDraftDuringSendCancelsStalePasteCommand() async throws {
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
        for _ in 0..<80 {
            let attempt = model.snapshot.latestInjectionAttempt
            if attempt?.draftID == sendingDraftID,
               attempt?.status == .failed,
               attempt?.finishedAt != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotEqual(model.snapshot.composeDraft?.id, sendingDraftID)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "새로 쓰는 문장")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .ready)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.draftID, sendingDraftID)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.clipboardSetStatus, .succeeded)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.pasteCommandStatus, .notAttempted)
        XCTAssertEqual(
            model.snapshot.latestInjectionAttempt?.safeMessage,
            "Text send cancelled because the compose draft changed."
        )
        XCTAssertTrue(connector.pasteCommands.isEmpty)
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
        XCTAssertTrue(
            connector.pasteCommands.isEmpty,
            "Observing the clipboard transfer before any paste command places the send inside its settle window."
        )

        model.disconnect()
        for _ in 0..<120 where model.snapshot.latestInjectionAttempt?.status != .failed {
            try await Task.sleep(for: .milliseconds(10))
        }

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

    func testModelDoesNotEnqueueForegroundStreamingFramesToInactivePiPController() async throws {
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
        try await waitForLatestFramebuffer(model, equalTo: secondFramebuffer)

        XCTAssertEqual(model.snapshot.latestFramebuffer, secondFramebuffer)
        XCTAssertNil(model.snapshot.pipWatchSession)
        XCTAssertEqual(
            pipController.enqueuedFramebuffers,
            [],
            "Foreground VNC frames must not enter the PiP sample-buffer path unless PiP Watch is active."
        )
    }

    func testStreamingFramesFlowThroughFrameEventsWithoutInvalidatingSwiftUIChrome() async throws {
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
        let pacingGate = PacingSleepGate()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0.5),
            connectorFactory: { connector },
            lowPowerModeProvider: { false },
            streamPacingSleep: { delay in
                try await pacingGate.sleep(delay)
            }
        )

        var appModelPublishCount = 0
        let appModelCancellable = model.objectWillChange.sink {
            appModelPublishCount += 1
        }
        var frameStorePublishCount = 0
        let frameStoreCancellable = model.frameStore.objectWillChange.sink {
            frameStorePublishCount += 1
        }
        var frameEventCount = 0
        let frameEventCancellable = model.frameStore.framePublisher.sink { _ in
            frameEventCount += 1
        }

        await model.connectSelectedProfile()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await pacingGate.waitForWaitCount(1)
        for _ in 0..<80 where model.snapshot.profilePreviews[profile.id] == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)
        XCTAssertEqual(model.frameStore.framebuffer, firstFramebuffer)

        let appModelBaseline = appModelPublishCount
        let frameStoreBaseline = frameStorePublishCount
        let frameEventBaseline = frameEventCount

        await pacingGate.releaseNext()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != secondFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(model.snapshot.latestFramebuffer, secondFramebuffer)
        XCTAssertEqual(model.frameStore.framebuffer, secondFramebuffer)
        XCTAssertEqual(
            appModelPublishCount,
            appModelBaseline,
            "After the session is already active, content frames should not invalidate the app shell/input dock."
        )
        XCTAssertEqual(
            frameStorePublishCount,
            frameStoreBaseline,
            "Same-size content frames should not force SwiftUI to rebuild the viewport representable."
        )
        XCTAssertGreaterThan(
            frameEventCount,
            frameEventBaseline,
            "The Metal host still needs a dedicated side-channel frame event for redraw."
        )

        withExtendedLifetime((appModelCancellable, frameStoreCancellable, frameEventCancellable)) {}
    }

    func testComposeDraftSurvivesSteadyStreamingFrameFlood() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffers = (1...24).map { red in
            RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: UInt8(red), green: 0, blue: 0)
            )
        }
        let connector = FakeStreamingConnector(
            width: 2,
            height: 2,
            name: "Desk",
            framebuffers: framebuffers
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: framebuffers.count, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )

        await model.connectSelectedProfile()

        model.updateComposeDraftText("입")
        try await Task.sleep(for: .milliseconds(2))
        model.updateComposeDraftText("입력")
        try await Task.sleep(for: .milliseconds(2))
        model.updateComposeDraftText("입력느낌")

        for _ in 0..<160 where model.snapshot.latestFramebuffer != framebuffers.last {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffers.last)
        XCTAssertEqual(
            model.snapshot.composeDraft?.text,
            "입력느낌",
            "Incoming frame churn must not reset or roll back the locally composed draft while UIKit is feeding Compose text."
        )
        XCTAssertNil(
            model.snapshot.latestInjectionAttempt,
            "Typing during a frame flood should only edit the local draft; it must not synthesize a send result."
        )
    }

    func testComposeFocusPacesFrameApplicationBeforeMainActorWork() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffers = (1...4).map { red in
            RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: UInt8(red), green: 0, blue: 0)
            )
        }
        let connectGate = SynchronousConnectGate()
        let connector = FakeStreamingConnector(
            width: 2,
            height: 2,
            name: "Desk",
            framebuffers: framebuffers,
            connectGate: connectGate
        )
        let frameApplicationGate = PacingSleepGate()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: framebuffers.count, frameInterval: 0),
            connectorFactory: { connector },
            lowPowerModeProvider: { false },
            // Request/decode pacing has its own integration coverage. Let the
            // producer fill this test's bounded queue immediately so the
            // frame-application worker and its coalescing slot are isolated.
            streamPacingSleep: { _ in },
            frameApplicationSleep: { delay in
                try await frameApplicationGate.sleep(delay)
            }
        )
        defer {
            connectGate.release()
            model.disconnect()
        }

        await model.connectSelectedProfile()
        for _ in 0..<80 where !connectGate.hasEntered {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(connectGate.hasEntered)

        // Hold the synchronous connector before its first frame so Compose
        // focus is established before any content can claim an application
        // slot. This removes the connect/focus race deterministically.
        model.setComposeInputEditingActive(true)
        XCTAssertEqual(
            model.frameApplicationContentFrameMinimumIntervalForTesting,
            SessionFrameApplicationWorkerPacing.textInputContentFrameMinimumInterval,
            accuracy: 0.0001
        )
        connectGate.release()

        for _ in 0..<80 where model.snapshot.latestFramebuffer != framebuffers.first {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffers.first)

        try await frameApplicationGate.waitForWaitCount(1)
        let frameApplicationDelays = await frameApplicationGate.delays
        let firstFrameApplicationDelay = try XCTUnwrap(frameApplicationDelays.first)
        XCTAssertGreaterThan(
            firstFrameApplicationDelay,
            0,
            "The repeated content frame must wait for the active text-input application slot."
        )
        XCTAssertLessThanOrEqual(
            firstFrameApplicationDelay,
            SessionFrameApplicationWorkerPacing.textInputContentFrameMinimumInterval
        )
        XCTAssertEqual(
            frameApplicationDelays.count,
            1,
            "The worker should occupy exactly one text-input pacing slot while the gate is closed."
        )

        // `latestContentWork(replacing:)` coalesces work that arrived while
        // this pacing slot was occupied. Wait until the producer has recorded
        // every frame (which happens after enqueue) before opening the slot;
        // otherwise the worker can legitimately apply frame 2 before frames
        // 3 and 4 have reached the bounded queue.
        for _ in 0..<80 where model.snapshot.sessionStreamStats.deliveredFrameCount < framebuffers.count {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(
            model.snapshot.sessionStreamStats.deliveredFrameCount,
            framebuffers.count,
            "All decoded frames must be queued before asserting latest-content coalescing for this pacing slot."
        )
        XCTAssertEqual(
            model.snapshot.latestFramebuffer,
            framebuffers.first,
            "Focused Compose should hold the queued content backlog before it enters MainActor frame application."
        )

        await frameApplicationGate.releaseNext()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != framebuffers.last {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(
            model.snapshot.latestFramebuffer,
            framebuffers.last,
            "After the input-aware pacing slot opens, only the newest queued content frame should apply."
        )
    }

    func testComposeFocusPacesVNCRequestsBeforeDecodeWork() async throws {
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
        let thirdFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 2,
            fill: RFBColor(red: 30, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 2,
            height: 2,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer, thirdFramebuffer]
        )
        let pacingGate = PacingSleepGate()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 3,
                frameInterval: StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds
            ),
            connectorFactory: { connector },
            thermalStateProvider: { .nominal },
            lowPowerModeProvider: { false },
            streamPacingSleep: { delay in
                try await pacingGate.sleep(delay)
            }
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()

        for _ in 0..<80 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await pacingGate.waitForWaitCount(1)
        var delays = await pacingGate.delays
        XCTAssertEqual(
            try XCTUnwrap(delays.first),
            StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds,
            accuracy: 0.0001
        )

        model.setComposeInputEditingActive(true)
        model.updateComposeDraftText("입")
        await pacingGate.releaseNext()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != secondFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await pacingGate.waitForWaitCount(2)

        delays = await pacingGate.delays
        XCTAssertEqual(
            try XCTUnwrap(delays.dropFirst().first),
            SessionFrameApplicationWorkerPacing.textInputContentFrameMinimumInterval,
            accuracy: 0.0001,
            "Focused Compose must lower VNC request/decode cadence to the text-input floor (the single worker rate authority) before frames can compete with UIKit IME."
        )
        XCTAssertEqual(model.snapshot.sessionStreamStats.activeInputPacingSampleCount, 1)

        model.updateComposeDraftText("입력")
        XCTAssertEqual(model.snapshot.composeDraft?.text, "입력")

        await pacingGate.releaseNext()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != thirdFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.snapshot.latestFramebuffer, thirdFramebuffer)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "입력")
    }

    func testTransientInputPacesVNCRequestsBeforeDecodeWork() async throws {
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
        let thirdFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 2,
            fill: RFBColor(red: 30, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 2,
            height: 2,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer, thirdFramebuffer]
        )
        let pacingGate = PacingSleepGate()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 3,
                frameInterval: StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds
            ),
            connectorFactory: { connector },
            thermalStateProvider: { .nominal },
            lowPowerModeProvider: { false },
            streamPacingSleep: { delay in
                try await pacingGate.sleep(delay)
            }
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()

        for _ in 0..<80 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await pacingGate.waitForWaitCount(1)
        var delays = await pacingGate.delays
        XCTAssertEqual(
            try XCTUnwrap(delays.first),
            StreamPressurePacingDefaults.balancedContentFrameIntervalSeconds,
            accuracy: 0.0001
        )

        model.markTransientFrameDeliveryInteractionActivityForTesting()
        await pacingGate.releaseNext()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != secondFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await pacingGate.waitForWaitCount(2)

        delays = await pacingGate.delays
        XCTAssertEqual(
            try XCTUnwrap(delays.dropFirst().first),
            StreamPressurePacingDefaults.transientInputContentFrameIntervalSeconds,
            accuracy: 0.0001,
            "Pointer/direct-key interaction should cap VNC request/decode work before visual frames can crowd input."
        )
        XCTAssertEqual(model.snapshot.sessionStreamStats.activeInputPacingSampleCount, 1)

        await pacingGate.releaseNext()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != thirdFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.snapshot.latestFramebuffer, thirdFramebuffer)
    }

    func testPointerInputWakesVisualPacingSleepBeforeNextRequest() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let hoverEchoFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, hoverEchoFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 2,
                frameInterval: 1.5
            ),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()
        for _ in 0..<120 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)

        let wakeStartedAt = Date()
        model.sendTapAt(viewPoint: CGPoint(x: 1, y: 0.5), viewSize: CGSize(width: 2, height: 1))
        try await waitForPointerEvents(connector, count: 2)
        for _ in 0..<120 where model.snapshot.latestFramebuffer != hoverEchoFramebuffer {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.snapshot.latestFramebuffer, hoverEchoFramebuffer)
        XCTAssertLessThan(
            Date().timeIntervalSince(wakeStartedAt),
            1.0,
            "Pointer input should wake an in-flight visual pacing sleep so remote hover/click echo is sampled without waiting for the full visual cadence slot."
        )
    }

    func testHardwareHoverInputWakesVisualPacingSleepBeforeNextRequest() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let hoverEchoFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, hoverEchoFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 2,
                frameInterval: 1.5
            ),
            connectorFactory: { connector },
            lowPowerModeProvider: { false }
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()
        for _ in 0..<120 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)

        model.togglePointerControlMode()
        let wakeStartedAt = Date()
        model.handleTrackpadGesture(
            .hoverMoved(viewPoint: CGPoint(x: 1, y: 0.5)),
            viewSize: CGSize(width: 2, height: 1)
        )
        try await waitForPointerEvents(connector, count: 1)
        XCTAssertEqual(connector.recordedBestEffortPointerEventCount, 1)
        for _ in 0..<120 where model.snapshot.latestFramebuffer != hoverEchoFramebuffer {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.snapshot.latestFramebuffer, hoverEchoFramebuffer)
        XCTAssertLessThan(
            Date().timeIntervalSince(wakeStartedAt),
            1.0,
            "Hardware pointer hover should wake an in-flight visual pacing sleep so desktop hover echo is sampled without waiting for the full visual cadence slot."
        )
    }

    func testPointerInputUsesEchoCadenceAfterWakingSlowVisualStream() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let hoverEchoFramebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, hoverEchoFramebuffer]
        )
        let pacingGate = PacingSleepGate()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 2,
                frameInterval: 1.5
            ),
            connectorFactory: { connector },
            lowPowerModeProvider: { false },
            streamPacingSleep: { delay in
                try await pacingGate.sleep(delay)
            }
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await pacingGate.waitForWaitCount(1)
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)
        var delays = await pacingGate.delays
        XCTAssertEqual(try XCTUnwrap(delays.first), 1.5, accuracy: 0.0001)

        model.sendTapAt(viewPoint: CGPoint(x: 1, y: 0.5), viewSize: CGSize(width: 2, height: 1))
        try await waitForPointerEvents(connector, count: 2)

        await pacingGate.releaseNext()
        for _ in 0..<80 where model.snapshot.latestFramebuffer != hoverEchoFramebuffer {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await pacingGate.waitForWaitCount(2)
        delays = await pacingGate.delays

        XCTAssertEqual(
            try XCTUnwrap(delays.dropFirst().first),
            StreamPressurePacingDefaults.transientInputContentFrameIntervalSeconds,
            accuracy: 0.0001,
            "After pointer input wakes a slow visual stream, follow-up sampling should stay in the input-echo cadence instead of falling back to the slow visual slot."
        )
        XCTAssertEqual(model.snapshot.sessionStreamStats.activeInputPacingSampleCount, 1)

        await pacingGate.releaseNext()
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
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()
        for _ in 0..<50 where model.snapshot.latestFramebuffer != firstFramebuffer {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(model.snapshot.latestFramebuffer, firstFramebuffer)

        model.setViewportInteractionActive(true)
        let requestCountAtGestureStart = connector.frameUpdateRequests.count
        for _ in 0..<120 where connector.frameUpdateRequests.count <= requestCountAtGestureStart {
            try await Task.sleep(for: .milliseconds(5))
        }

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

    private static func makeServerInit(width: Int, height: Int) -> RFBServerInit {
        RFBServerInit(
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
            name: "Desk"
        )
    }

    private static func makeStreamFrameApplicationWork(
        sequence: Int,
        red: UInt8,
        isEmptyUpdate: Bool = false,
        isIncremental: Bool? = nil,
        serverCursor: RFBServerCursor? = nil,
        serverInit: RFBServerInit,
        profile: ConnectionProfile,
        sessionID: RemoteSession.ID,
        streamID: UUID
    ) -> StreamFrameApplicationWork {
        let framebuffer = RFBRawFramebuffer(
            width: Int(serverInit.width),
            height: Int(serverInit.height),
            fill: RFBColor(red: red, green: 0, blue: 0)
        )
        return StreamFrameApplicationWork(
            frame: RFBFramePumpFrame(
                sequence: sequence,
                framebuffer: framebuffer,
                dirtyRectangles: isEmptyUpdate
                    ? []
                    : [RFBFrameDamageRect(x: 0, y: 0, width: framebuffer.width, height: framebuffer.height)],
                changedPixelCount: isEmptyUpdate ? 0 : framebuffer.width * framebuffer.height,
                capturedAt: Date(timeIntervalSince1970: TimeInterval(sequence)),
                isIncremental: isIncremental ?? (sequence > 1),
                serverCursor: serverCursor
            ),
            serverInit: serverInit,
            profile: profile,
            sessionID: sessionID,
            streamID: streamID,
            isEmptyUpdate: isEmptyUpdate
        )
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
        for _ in 0..<120 where model.snapshot.lastDiagnosticVerdict[first.id] != .passed {
            try await Task.sleep(for: .milliseconds(5))
        }
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

    private func waitForHelperVideoOutcome(
        _ recorder: AppModelHelperVideoOutcomeRecorder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> HelperVideoStreamSessionOutcome {
        for _ in 0..<120 {
            if let outcome = await recorder.outcomeSnapshot() {
                return outcome
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for helper-video outcome.", file: file, line: line)
        throw AppModelHelperVideoOutcomeRecorderError.outcomeTimedOut
    }

    private func waitForHelperVideoStartCalls(
        _ recorder: HelperVideoStartRecorder,
        count expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if await recorder.recordedCallSnapshot().count >= expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let calls = await recorder.recordedCallSnapshot()
        XCTAssertEqual(calls.count, expectedCount, file: file, line: line)
    }

    private func waitForLatestFramebuffer(
        _ model: NaruRemoteAppModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if model.snapshot.latestFramebuffer != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(model.snapshot.latestFramebuffer, file: file, line: line)
    }

    private func waitForLatestFramebuffer(
        _ model: NaruRemoteAppModel,
        equalTo expectedFramebuffer: RFBRawFramebuffer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if model.snapshot.latestFramebuffer == expectedFramebuffer {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            model.snapshot.latestFramebuffer,
            expectedFramebuffer,
            "Timed out waiting for the expected streamed framebuffer.",
            file: file,
            line: line
        )
    }

    private func waitForInputCoordinateSpace(
        _ model: NaruRemoteAppModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if model.snapshot.inputCoordinateSpace != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(model.snapshot.inputCoordinateSpace, file: file, line: line)
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

    /// Waits for the state the caller is about to assert.
    ///
    /// Waiting on the helper *receiving* a request and then asserting the
    /// model's send state is a proxy wait: the request arriving is not the same
    /// event as the model finishing with the response. Measured 2026-08-21, that
    /// gap made `testModelRoutesUTF8ComposeThroughStoredHelperProfileTransport`
    /// fail in a loaded full-suite run (`sending` where `sent` was expected)
    /// while passing five times out of five in isolation.
    private func waitForComposeSendState(
        _ model: NaruRemoteAppModel,
        _ expectedState: ComposeSendState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<250 {
            if model.snapshot.composeDraft?.sendState == expectedState {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(
            model.snapshot.composeDraft?.sendState,
            expectedState,
            file: file,
            line: line
        )
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

    /// 120×120 fit into 20×20 → displayScale 1/6, so assumed ppp 3 is
    /// exactly the lossless boundary (displayScale·ppp ≤ 0.5).
    private static let appleDownscaleLosslessUnzoomedTransform = ViewportTransform(
        framebufferSize: CGSize(width: 120, height: 120),
        viewSize: CGSize(width: 20, height: 20)
    )

    private static let appleDownscaleZoomedTransform = ViewportTransform(
        framebufferSize: CGSize(width: 120, height: 120),
        viewSize: CGSize(width: 20, height: 20),
        zoomScale: 2
    )

    /// Spec 031: the downscale now only runs where the user asked for less data,
    /// so these harnesses report system low-power mode by default. The machinery
    /// itself is unchanged and still covered; what moved is when the app asks for
    /// it. `allowsDownscale: false` is the new product default.
    private func makeAppleDownscaleHarness(
        profile: ConnectionProfile,
        advertisedAppleSecurity: Bool,
        allowsDownscale: Bool = true
    ) -> (FakeStreamingConnector, NaruRemoteAppModel) {
        let framebuffer = RFBRawFramebuffer(
            width: 120,
            height: 120,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 120,
            height: 120,
            name: "Desk",
            framebuffer: framebuffer
        )
        connector.serverAdvertisedAppleSecurity = advertisedAppleSecurity
        connector.repeatsLastFramebufferUpdate = true
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(
                maxFrames: 40,
                requestTimeout: 1,
                frameInterval: 0.08,
                idleFrameInterval: 0
            ),
            connectorFactory: { connector },
            lowPowerModeProvider: { allowsDownscale }
        )
        return (connector, model)
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

private actor PacingSleepGate {
    private var recordedDelays: [TimeInterval] = []
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var pendingReleases = 0

    var delays: [TimeInterval] {
        recordedDelays
    }

    func sleep(_ delay: TimeInterval) async throws {
        recordedDelays.append(delay)
        let waitCount = recordedDelays.count
        let countWaitersToResume = countWaiters
            .filter { waitCount >= $0.0 }
            .map(\.1)
        countWaiters.removeAll { waitCount >= $0.0 }
        countWaitersToResume.forEach { $0.resume() }

        guard pendingReleases == 0 else {
            pendingReleases -= 1
            return
        }

        await withCheckedContinuation { continuation in
            sleepWaiters.append(continuation)
        }
    }

    func releaseNext() {
        guard !sleepWaiters.isEmpty else {
            pendingReleases += 1
            return
        }
        sleepWaiters.removeFirst().resume()
    }

    func waitForWaitCount(_ expectedCount: Int) async throws {
        guard recordedDelays.count < expectedCount else {
            return
        }
        await withCheckedContinuation { continuation in
            if recordedDelays.count >= expectedCount {
                continuation.resume()
            } else {
                countWaiters.append((expectedCount, continuation))
            }
        }
    }
}

private actor BlockingCredentialStore: ConnectionCredentialStoreProtocol {
    private let passwordValue: String?
    private var passwordRequestStarted = false
    private var passwordRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var passwordReleaseContinuation: CheckedContinuation<Void, Never>?

    init(password: String?) {
        self.passwordValue = password
    }

    func savePassword(_ password: String, for credentialRef: String) async throws {
        // This deterministic fixture only exercises a blocked read.
    }

    func password(for credentialRef: String) async throws -> String? {
        passwordRequestStarted = true
        let waiters = passwordRequestWaiters
        passwordRequestWaiters.removeAll()
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            passwordReleaseContinuation = continuation
        }
        return passwordValue
    }

    func deletePassword(for credentialRef: String) async throws {
        // This deterministic fixture only exercises a blocked read.
    }

    func waitForPasswordRequest() async {
        guard !passwordRequestStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            passwordRequestWaiters.append(continuation)
        }
    }

    func releasePasswordRequest() {
        passwordReleaseContinuation?.resume()
        passwordReleaseContinuation = nil
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
    private let stampRequestID: Bool
    private let error: Error?
    private let insertDelayNanoseconds: UInt64

    init(
        availability: HelperTextBridgeAvailability = .reachable,
        result: HelperTextInsertResult? = nil,
        stampRequestID: Bool = false,
        error: Error? = nil,
        insertDelayNanoseconds: UInt64 = 0
    ) {
        self.availability = availability
        self.result = result
        self.stampRequestID = stampRequestID
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
            guard stampRequestID else {
                return result
            }
            return HelperTextInsertResult(
                requestID: metadata.id,
                strategyUsed: result.strategyUsed,
                status: result.status,
                safeFailureCode: result.safeFailureCode
            )
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
        var completedRequestCount = 0
        var recordedClipboardPayloads: [String] = []
        var recordedPasteCommands: [PasteCommand] = []
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String
    private let connectError: Error?
    private let connectGate: SynchronousConnectGate?
    let utf8ClipboardSupport: RemoteClipboardUTF8Support

    init(
        width: Int,
        height: Int,
        name: String,
        connectError: Error? = nil,
        connectGate: SynchronousConnectGate? = nil,
        utf8ClipboardSupport: RemoteClipboardUTF8Support = .unknown
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.connectError = connectError
        self.connectGate = connectGate
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

    var completedRequestCount: Int {
        recording.withLock { $0.completedRequestCount }
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
        connectGate?.waitBeforeConnecting()
        recording.withLock { state in
            state.recordedRequests.append(Request(host: host, port: port))
        }

        if let connectError {
            recording.withLock { $0.completedRequestCount += 1 }
            throw connectError
        }

        let serverInit = RFBServerInit(
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
        recording.withLock { $0.completedRequestCount += 1 }
        return serverInit
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

private enum AppModelHelperVideoOutcomeRecorderError: Error {
    case outcomeTimedOut
}

private actor AppModelHelperVideoOutcomeRecorder {
    private var outcome: HelperVideoStreamSessionOutcome?

    func record(_ outcome: HelperVideoStreamSessionOutcome) {
        self.outcome = outcome
    }

    func outcomeSnapshot() -> HelperVideoStreamSessionOutcome? {
        outcome
    }
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

private final class HelperVideoOpenStreamRecorder: @unchecked Sendable {
    struct Call: Equatable, Sendable {
        let profileID: ConnectionProfile.ID
        let pairingFingerprint: String
        let loadedSecretWasPresent: Bool
        let requestBody: HelperVideoStartStreamRequestBody
    }

    private let lock = NSLock()
    private let descriptor: HelperVideoStreamDescriptor
    private let accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>]
    private var recordedCalls: [Call] = []

    init(
        descriptor: HelperVideoStreamDescriptor,
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>]
    ) {
        self.descriptor = descriptor
        self.accessUnits = accessUnits
    }

    func recordedCallSnapshot() -> [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func open(
        profile: ConnectionProfile,
        pairingSecret: String,
        pairingFingerprint: String,
        requestBody: HelperVideoStartStreamRequestBody
    ) -> HelperVideoStreamNetworkEvents {
        lock.lock()
        recordedCalls.append(
            Call(
                profileID: profile.id,
                pairingFingerprint: pairingFingerprint,
                loadedSecretWasPresent: !pairingSecret.isEmpty,
                requestBody: requestBody
            )
        )
        lock.unlock()
        let descriptor = descriptor
        let accessUnits = accessUnits
        return HelperVideoStreamNetworkEvents { continuation in
            continuation.yield(.startResponse(
                HelperVideoWireEnvelope(
                    messageType: .startStream,
                    profileFingerprint: pairingFingerprint,
                    body: HelperVideoStartStreamResponseBody(
                        result: .accepted,
                        streamDescriptor: descriptor
                    )
                )
            ))
            for accessUnit in accessUnits {
                continuation.yield(.accessUnit(accessUnit))
            }
            continuation.finish()
        }
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
    ) async throws -> Bool {
        let sequence = decoded.envelope.body.sequence
        enqueuedSequences.append(sequence)
        return displayableSequences.contains(sequence)
    }

    func flush() async {
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

private final class SynchronousConnectGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var entered = false
    private var released = false

    var hasEntered: Bool {
        lock.withLock { entered }
    }

    func waitBeforeConnecting() {
        let shouldWait = lock.withLock { () -> Bool in
            entered = true
            return !released
        }
        if shouldWait {
            releaseSemaphore.wait()
        }
    }

    func release() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !released else {
                return false
            }
            released = true
            return true
        }
        if shouldSignal {
            releaseSemaphore.signal()
        }
    }
}

private final class FakeStreamingConnector:
    RFBStreamingClient,
    RFBBestEffortPointerEventClient,
    RFBRegionFramebufferUpdating,
    RFBFramebufferUpdateReceiving,
    RFBTransportControlClient,
    RFBContinuousUpdateCapabilityReporting,
    RFBServerScalingClient
{
    fileprivate struct Recording {
        var frameUpdates: [RFBFramebufferUpdateResult]
        var recordedSessionRequests: [FakeFirstFrameConnector.Request] = []
        var recordedFrameUpdateRequests: [Bool] = []
        var recordedFrameUpdateRegions: [RFBFramebufferUpdateRegion?] = []
        var recordedCredentials: [RFBConnectionCredential] = []
        var recordedClipboardPayloads: [String] = []
        var recordedPasteCommands: [PasteCommand] = []
        var recordedPointerEventsList: [(mask: UInt8, x: UInt16, y: UInt16)] = []
        var recordedBestEffortPointerEventCount = 0
        var renegotiatedPreferences: [RFBEncodingPreference] = []
        var receivedFrameCount = 0
        var continuousUpdateFlags: [Bool] = []
        var initialCanEnableContinuousUpdates: Bool
        var sentScaleFactors: [Double] = []
        var serverAdvertisedAppleSecurity = false
        var advertisedAppleSecurityReadCount = 0
        var repeatsLastFramebufferUpdate = false
        var appliesScaleFactorResize = false
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String
    private let connectDelay: TimeInterval
    private let frameUpdateDelay: TimeInterval
    private let connectGate: SynchronousConnectGate?

    var recordedPointerEvents: [(mask: UInt8, x: UInt16, y: UInt16)] {
        recording.withLock { $0.recordedPointerEventsList }
    }

    var recordedBestEffortPointerEventCount: Int {
        recording.withLock { $0.recordedBestEffortPointerEventCount }
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

    var sentScaleFactors: [Double] {
        recording.withLock { $0.sentScaleFactors }
    }

    var advertisedAppleSecurityReadCount: Int {
        recording.withLock { $0.advertisedAppleSecurityReadCount }
    }

    var serverAdvertisedAppleSecurity: Bool {
        get {
            recording.withLock {
                $0.advertisedAppleSecurityReadCount += 1
                return $0.serverAdvertisedAppleSecurity
            }
        }
        set { recording.withLock { $0.serverAdvertisedAppleSecurity = newValue } }
    }

    var repeatsLastFramebufferUpdate: Bool {
        get { recording.withLock { $0.repeatsLastFramebufferUpdate } }
        set { recording.withLock { $0.repeatsLastFramebufferUpdate = newValue } }
    }

    var appliesScaleFactorResize: Bool {
        get { recording.withLock { $0.appliesScaleFactorResize } }
        set { recording.withLock { $0.appliesScaleFactorResize = newValue } }
    }

    init(
        width: Int,
        height: Int,
        name: String,
        framebuffer: RFBRawFramebuffer,
        canEnableContinuousUpdates: Bool = false,
        connectDelay: TimeInterval = 0,
        frameUpdateDelay: TimeInterval = 0,
        connectGate: SynchronousConnectGate? = nil
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.connectDelay = max(connectDelay, 0)
        self.frameUpdateDelay = max(frameUpdateDelay, 0)
        self.connectGate = connectGate
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
        canEnableContinuousUpdates: Bool = false,
        connectDelay: TimeInterval = 0,
        frameUpdateDelay: TimeInterval = 0,
        connectGate: SynchronousConnectGate? = nil
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.connectDelay = max(connectDelay, 0)
        self.frameUpdateDelay = max(frameUpdateDelay, 0)
        self.connectGate = connectGate
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
        canEnableContinuousUpdates: Bool = false,
        connectDelay: TimeInterval = 0,
        frameUpdateDelay: TimeInterval = 0,
        connectGate: SynchronousConnectGate? = nil
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.connectDelay = max(connectDelay, 0)
        self.frameUpdateDelay = max(frameUpdateDelay, 0)
        self.connectGate = connectGate
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
        connectGate?.waitBeforeConnecting()
        if connectDelay > 0 {
            Thread.sleep(forTimeInterval: connectDelay)
        }
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
        if frameUpdateDelay > 0 {
            Thread.sleep(forTimeInterval: frameUpdateDelay)
        }
        let update = recording.withLock { state -> RFBFramebufferUpdateResult? in
            state.recordedFrameUpdateRequests.append(incremental)
            state.recordedFrameUpdateRegions.append(region)
            if state.repeatsLastFramebufferUpdate {
                return state.frameUpdates.first
            }
            return state.frameUpdates.isEmpty ? nil : state.frameUpdates.removeFirst()
        }

        guard let update else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }

        return update
    }

    func receiveFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult {
        if frameUpdateDelay > 0 {
            Thread.sleep(forTimeInterval: frameUpdateDelay)
        }
        let update = recording.withLock { state -> RFBFramebufferUpdateResult? in
            state.receivedFrameCount += 1
            if state.repeatsLastFramebufferUpdate {
                return state.frameUpdates.first
            }
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

    func sendBestEffortPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) throws {
        guard buttonMask == RFBPointerCommand.released else {
            throw RFBNetworkClientError.unsupportedBestEffortPointerMask
        }
        recording.withLock { state in
            state.recordedBestEffortPointerEventCount += 1
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

    func sendAppleScaleFactor(_ scale: Double, timeout: TimeInterval) throws {
        recording.withLock { state in
            state.sentScaleFactors.append(scale)
            // Simulate screensharingd honoring the request: subsequent
            // updates serve a resized framebuffer announced via the
            // DesktopSize path (didResizeDesktop), like the live server.
            guard state.appliesScaleFactorResize, scale > 0, scale < 1 else {
                return
            }
            let scaledWidth = max(Int((Double(width) * scale).rounded()), 1)
            let scaledHeight = max(Int((Double(height) * scale).rounded()), 1)
            let scaledFramebuffer = RFBRawFramebuffer(
                width: scaledWidth,
                height: scaledHeight,
                fill: RFBColor(red: 10, green: 0, blue: 0)
            )
            let resized = RFBFramebufferUpdateResult(
                framebuffer: scaledFramebuffer,
                dirtyRectangles: [
                    RFBFrameDamageRect(
                        x: 0,
                        y: 0,
                        width: scaledWidth,
                        height: scaledHeight
                    )
                ],
                changedPixelCount: scaledWidth * scaledHeight,
                capturedAt: Date(),
                didResizeDesktop: true
            )
            state.frameUpdates = [resized]
            state.repeatsLastFramebufferUpdate = true
        }
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
