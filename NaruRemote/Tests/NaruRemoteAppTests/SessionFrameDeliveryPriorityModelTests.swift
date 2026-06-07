import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class SessionFrameDeliveryPriorityModelTests: XCTestCase {
    func testComposeFocusKeepsInteractiveFrameDeliveryUntilFocusLeaves() {
        let model = NaruRemoteAppModel()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )

        model.setComposeInputEditingActive(true)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(50)
        )

        model.setComposeInputEditingActive(false)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )
    }

    func testViewportGestureKeepsInteractiveFrameDeliveryUntilGestureEnds() {
        let model = NaruRemoteAppModel()

        model.setViewportInteractionActive(true)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(50)
        )

        model.setViewportInteractionActive(false)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )
    }

    func testDirectKeyTapTemporarilyUsesInteractiveFrameDelivery() async throws {
        let model = NaruRemoteAppModel()

        await model.tapDirectKey(.character("a"))

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(50)
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )
    }

    func testDirectModeToggleTemporarilyUsesInteractiveFrameDelivery() async throws {
        let model = NaruRemoteAppModel()

        model.toggleDirectKeystrokeMode()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(50)
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )
    }

    func testDisconnectClearsTransientFrameDeliveryInteractionPriorityImmediately() async throws {
        let model = NaruRemoteAppModel()

        model.markTransientFrameDeliveryInteractionActivityForTesting()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(50)
        )

        model.disconnect()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
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
            .milliseconds(50),
            "The first transient lease expiry must not clear a newer interaction lease."
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
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
            .milliseconds(50)
        )

        model.selectProfile(id: second.id)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )
    }

    func testComposeFocusSurvivesTransientInputLeaseExpiry() async throws {
        let model = NaruRemoteAppModel()

        model.setComposeInputEditingActive(true)
        model.markTransientFrameDeliveryInteractionActivityForTesting()

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(50)
        )

        try await Task.sleep(
            for: NaruRemoteAppModel.transientFrameDeliveryInteractionPriorityDuration + .milliseconds(80)
        )

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(50),
            "A transient interaction lease must not drop Compose focus back to visual frame cadence."
        )

        model.setComposeInputEditingActive(false)

        XCTAssertEqual(
            model.frameStore.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )
    }
}
