import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class SessionFrameDeliveryPriorityModelTests: XCTestCase {
    func testComposeFocusUsesTextInputFrameDeliveryUntilFocusLeaves() {
        let model = NaruRemoteAppModel()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )

        model.setComposeInputEditingActive(true)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.textInputFrameDeliveryCoalescingDelay
        )

        model.setComposeInputEditingActive(false)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testTestingFrameApplicationIntervalTracksComposeFocusPriority() {
        let model = NaruRemoteAppModel()

        XCTAssertEqual(
            model.frameApplicationContentFrameMinimumIntervalForTesting,
            SessionFrameApplicationWorkerPacing.visualContentFrameMinimumInterval,
            accuracy: 0.0001
        )

        model.setComposeInputEditingActive(true)

        XCTAssertEqual(
            model.frameApplicationContentFrameMinimumIntervalForTesting,
            SessionFrameApplicationWorkerPacing.textInputContentFrameMinimumInterval,
            accuracy: 0.0001,
            "Synthetic frame pressure used by XCUITest should follow the same IME-friendly cadence as production frame application."
        )

        model.setComposeInputEditingActive(false)

        XCTAssertEqual(
            model.frameApplicationContentFrameMinimumIntervalForTesting,
            SessionFrameApplicationWorkerPacing.visualContentFrameMinimumInterval,
            accuracy: 0.0001
        )
    }

    func testViewportGestureUsesNavigationFrameDeliveryUntilGestureEnds() {
        let model = NaruRemoteAppModel()

        model.setViewportInteractionActive(true)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.viewportNavigationFrameDeliveryCoalescingDelay
        )

        model.setViewportInteractionActive(false)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testDirectKeyTapTemporarilyUsesNavigationFrameDelivery() async throws {
        let model = NaruRemoteAppModel()

        await model.tapDirectKey(.character("a"))

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.viewportNavigationFrameDeliveryCoalescingDelay
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testDirectModeToggleTemporarilyUsesNavigationFrameDelivery() async throws {
        let model = NaruRemoteAppModel()

        model.toggleDirectKeystrokeMode()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.viewportNavigationFrameDeliveryCoalescingDelay
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testDisconnectClearsTransientFrameDeliveryInteractionPriorityImmediately() async throws {
        let model = NaruRemoteAppModel()

        model.markTransientFrameDeliveryInteractionActivityForTesting()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.viewportNavigationFrameDeliveryCoalescingDelay
        )

        model.disconnect()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testRepeatedTransientInteractionExtendsFrameDeliveryLeaseFromLatestActivity() async throws {
        let model = NaruRemoteAppModel()

        model.markTransientFrameDeliveryInteractionActivityForTesting()
        try await Task.sleep(for: .milliseconds(100))
        model.markTransientFrameDeliveryInteractionActivityForTesting()
        try await Task.sleep(for: .milliseconds(90))

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.viewportNavigationFrameDeliveryCoalescingDelay,
            "The first transient lease expiry must not clear a newer interaction lease."
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testProfileSelectionClearsPersistentAndTransientFrameDeliveryReasons() async throws {
        let first = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Laptop", host: "laptop.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [first, second],
                selectedProfileID: first.id
            )
        )

        model.setComposeInputEditingActive(true)
        model.setViewportInteractionActive(true)
        model.markTransientFrameDeliveryInteractionActivityForTesting()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.textInputFrameDeliveryCoalescingDelay
        )

        model.selectProfile(id: second.id)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testComposeFocusSurvivesTransientInputLeaseExpiry() async throws {
        let model = NaruRemoteAppModel()

        model.setComposeInputEditingActive(true)
        model.markTransientFrameDeliveryInteractionActivityForTesting()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.textInputFrameDeliveryCoalescingDelay
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.textInputFrameDeliveryCoalescingDelay,
            "A transient interaction lease must not drop Compose focus back to visual frame cadence."
        )

        model.setComposeInputEditingActive(false)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testComposeFocusTakesPriorityOverViewportGestureCadence() {
        let model = NaruRemoteAppModel()

        model.setViewportInteractionActive(true)
        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.viewportNavigationFrameDeliveryCoalescingDelay
        )

        model.setComposeInputEditingActive(true)
        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.textInputFrameDeliveryCoalescingDelay,
            "IME-owned Compose input must win over viewport/navigation frame delivery."
        )

        model.setComposeInputEditingActive(false)
        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.viewportNavigationFrameDeliveryCoalescingDelay,
            "Ending Compose focus should reveal the still-active viewport navigation cadence."
        )

        model.setViewportInteractionActive(false)
        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay
        )
    }

    func testComposeFocusCoalescesConnectionQualityChromeUntilFocusLeaves() async throws {
        let model = NaruRemoteAppModel()

        model.setComposeInputEditingActive(true)
        model.seedConnectionQualityForTesting(.good)

        XCTAssertEqual(
            model.connectionQuality,
            .unknown,
            "Focused Compose should not republish chrome-only quality updates synchronously with IME events."
        )

        try await Task.sleep(for: .milliseconds(330))
        XCTAssertEqual(model.connectionQuality, .unknown)

        model.setComposeInputEditingActive(false)

        XCTAssertEqual(
            model.connectionQuality,
            .good,
            "Leaving Compose focus should flush the latest coalesced quality bucket."
        )
    }

    func testComposeFocusCoalescesHelperVideoHealthButDoesNotDeferFallback() async throws {
        let model = NaruRemoteAppModel()
        let healthy = HelperVideoStreamHealth(
            state: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: .smooth,
            decodePressure: .low
        )

        model.setComposeInputEditingActive(true)
        model.updateHelperVideoStreamHealth(healthy)

        XCTAssertEqual(
            model.helperVideoStreamHealth,
            HelperVideoStreamHealth(),
            "Focused Compose should coalesce non-critical helper-video health chrome."
        )

        model.updateHelperVideoStreamHealth(
            HelperVideoStreamHealth(
                state: .stalled,
                sustainedUpdateBand: .stalled,
                fallbackCountBucket: .one
            )
        )

        XCTAssertEqual(model.helperVideoStreamHealth.state, .fallbackToVNC)
        XCTAssertEqual(
            model.helperVideoStreamHealth.fallbackCountBucket,
            .one,
            "Functional helper-video fallback must remain immediate even during focused input."
        )

        try await Task.sleep(for: .milliseconds(330))
        XCTAssertEqual(
            model.helperVideoStreamHealth.state,
            .fallbackToVNC,
            "A pending healthy chrome sample must not overwrite an immediate fallback decision."
        )
    }

    func testComposeFocusFlushesLatestHelperVideoHealthWhenFocusLeaves() async throws {
        let model = NaruRemoteAppModel()
        let healthy = HelperVideoStreamHealth(
            state: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: .smooth,
            decodePressure: .low
        )

        model.setComposeInputEditingActive(true)
        model.updateHelperVideoStreamHealth(healthy)

        try await Task.sleep(for: .milliseconds(330))
        XCTAssertEqual(
            model.helperVideoStreamHealth,
            HelperVideoStreamHealth(),
            "Non-critical helper-video chrome should stay deferred while Compose owns first responder."
        )

        model.setComposeInputEditingActive(false)

        XCTAssertEqual(
            model.helperVideoStreamHealth,
            healthy,
            "Leaving Compose focus should publish the latest deferred helper-video health sample."
        )
    }
}
