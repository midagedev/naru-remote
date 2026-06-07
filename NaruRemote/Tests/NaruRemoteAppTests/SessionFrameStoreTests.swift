import Combine
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class SessionFrameStoreTests: XCTestCase {
    func testSteadyFrameDeliveryCoalescingUsesDisplayCadence() {
        XCTAssertEqual(
            SessionFrameStore.steadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )
    }

    func testDeliveryCoalescingSeparatesNavigationAndTextInputCadence() {
        let store = SessionFrameStore()

        XCTAssertEqual(
            store.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(16)
        )

        store.setDeliveryPriority(.viewportNavigation)

        XCTAssertEqual(
            store.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(50)
        )

        store.setDeliveryPriority(.textInput)

        XCTAssertEqual(
            store.currentSteadyFrameDeliveryCoalescingDelay,
            .milliseconds(120)
        )
    }

    func testSameSizeFramesEmitEventsWithoutSwiftUIPresentationRefresh() {
        let store = SessionFrameStore()
        var presentationPublishCount = 0
        let presentationCancellable = store.objectWillChange.sink {
            presentationPublishCount += 1
        }
        var frameEvents: [SessionFrameState] = []
        let frameCancellable = store.framePublisher.sink { state in
            frameEvents.append(state)
        }

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 10, green: 0, blue: 0)
            ),
            dirtyRectangles: nil,
            changedPixelCount: nil,
            serverCursor: nil
        )

        store.flushPendingFrameDeliveryForTesting()
        XCTAssertEqual(frameEvents.count, 1)
        XCTAssertEqual(store.presentationRevision, 1)
        XCTAssertGreaterThanOrEqual(presentationPublishCount, 1)

        let presentationBaseline = presentationPublishCount
        let revisionBaseline = store.presentationRevision

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 20, green: 0, blue: 0)
            ),
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
            changedPixelCount: 1,
            serverCursor: nil
        )

        store.flushPendingFrameDeliveryForTesting()
        XCTAssertEqual(frameEvents.count, 2)
        XCTAssertEqual(store.presentationRevision, revisionBaseline)
        XCTAssertEqual(
            presentationPublishCount,
            presentationBaseline,
            "Same-size content frames should reach Metal without publishing SwiftUI presentation changes."
        )

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 4,
                height: 2,
                fill: RFBColor(red: 30, green: 0, blue: 0)
            ),
            dirtyRectangles: nil,
            changedPixelCount: nil,
            serverCursor: nil
        )

        store.flushPendingFrameDeliveryForTesting()
        XCTAssertEqual(frameEvents.count, 3)
        XCTAssertEqual(store.presentationRevision, revisionBaseline + 1)
        XCTAssertGreaterThan(presentationPublishCount, presentationBaseline)

        withExtendedLifetime((presentationCancellable, frameCancellable)) {}
    }

    func testFrameEventsDeliverAsynchronouslyAndCoalesceToLatestFrame() {
        let store = SessionFrameStore()
        var frameEvents: [SessionFrameState] = []
        let frameCancellable = store.framePublisher.sink { state in
            frameEvents.append(state)
        }

        let first = RFBRawFramebuffer(
            width: 2,
            height: 2,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let second = RFBRawFramebuffer(
            width: 2,
            height: 2,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )

        store.publish(
            framebuffer: first,
            dirtyRectangles: nil,
            changedPixelCount: nil,
            serverCursor: nil
        )
        store.publish(
            framebuffer: second,
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
            changedPixelCount: 1,
            serverCursor: nil
        )

        XCTAssertEqual(store.framebuffer, second)
        XCTAssertTrue(frameEvents.isEmpty)

        store.flushPendingFrameDeliveryForTesting()

        XCTAssertEqual(frameEvents.map(\.framebuffer), [second])
        XCTAssertEqual(frameEvents.first?.dirtyRectangles, [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)])
        XCTAssertEqual(frameEvents.first?.changedPixelCount, 1)

        withExtendedLifetime(frameCancellable) {}
    }

    func testLeavingInputOrNavigationPriorityFlushesLatestPendingFrameImmediately() {
        let store = SessionFrameStore()
        var frameEvents: [SessionFrameState] = []
        let frameCancellable = store.framePublisher.sink { state in
            frameEvents.append(state)
        }

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 1, green: 0, blue: 0)
            ),
            dirtyRectangles: nil,
            changedPixelCount: nil,
            serverCursor: nil
        )
        store.flushPendingFrameDeliveryForTesting()
        XCTAssertEqual(frameEvents.map(\.framebuffer?.pixels.first?.red), [1])

        store.setDeliveryPriority(.viewportNavigation)
        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 2, green: 0, blue: 0)
            ),
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
            changedPixelCount: 1,
            serverCursor: nil
        )
        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 3, green: 0, blue: 0)
            ),
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
            changedPixelCount: 1,
            serverCursor: nil
        )

        XCTAssertEqual(frameEvents.map(\.framebuffer?.pixels.first?.red), [1])

        store.setDeliveryPriority(.visual)

        XCTAssertEqual(
            frameEvents.map(\.framebuffer?.pixels.first?.red),
            [1, 3],
            "Leaving interactive input should flush the newest pending frame without replaying stale video frames."
        )

        withExtendedLifetime(frameCancellable) {}
    }

    func testEnteringTextInputReschedulesPendingSteadyFrameToIMEFriendlyCadence() {
        let store = SessionFrameStore()
        var frameEvents: [SessionFrameState] = []
        let frameCancellable = store.framePublisher.sink { state in
            frameEvents.append(state)
        }

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 1, green: 0, blue: 0)
            ),
            dirtyRectangles: nil,
            changedPixelCount: nil,
            serverCursor: nil
        )
        store.flushPendingFrameDeliveryForTesting()
        XCTAssertEqual(frameEvents.map(\.framebuffer?.pixels.first?.red), [1])

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 2, green: 0, blue: 0)
            ),
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
            changedPixelCount: 1,
            serverCursor: nil
        )
        XCTAssertEqual(
            store.pendingFrameDeliveryCoalescingDelayForTesting,
            .milliseconds(16)
        )

        store.setDeliveryPriority(.textInput)

        XCTAssertEqual(
            store.pendingFrameDeliveryCoalescingDelayForTesting,
            .milliseconds(120),
            "Entering text input should move already pending steady frames to the IME-friendly cadence."
        )
        XCTAssertEqual(frameEvents.map(\.framebuffer?.pixels.first?.red), [1])

        store.flushPendingFrameDeliveryForTesting()
        XCTAssertEqual(frameEvents.map(\.framebuffer?.pixels.first?.red), [1, 2])

        withExtendedLifetime(frameCancellable) {}
    }

    func testSteadyFrameFloodCoalescesToLatestFrameAtDisplayCadence() async throws {
        let store = SessionFrameStore()
        var frameEvents: [SessionFrameState] = []
        let frameCancellable = store.framePublisher.sink { state in
            frameEvents.append(state)
        }

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 1, green: 0, blue: 0)
            ),
            dirtyRectangles: nil,
            changedPixelCount: nil,
            serverCursor: nil
        )
        store.flushPendingFrameDeliveryForTesting()
        XCTAssertEqual(frameEvents.map(\.framebuffer?.pixels.first?.red), [1])

        for red in UInt8(2)...UInt8(40) {
            store.publish(
                framebuffer: RFBRawFramebuffer(
                    width: 2,
                    height: 2,
                    fill: RFBColor(red: red, green: 0, blue: 0)
                ),
                dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
                changedPixelCount: 1,
                serverCursor: nil
            )
        }

        XCTAssertEqual(
            frameEvents.map(\.framebuffer?.pixels.first?.red),
            [1],
            "A same-size frame flood should not synchronously flush every transient frame into the viewport."
        )

        try await Task.sleep(for: .milliseconds(35))

        XCTAssertEqual(
            frameEvents.map(\.framebuffer?.pixels.first?.red),
            [1, 40],
            "The display-cadence delivery should keep only the latest pending steady-state frame."
        )

        withExtendedLifetime(frameCancellable) {}
    }

    func testImmediateClearCancelsPendingSteadyFrameDelay() async {
        let store = SessionFrameStore()
        var frameEvents: [SessionFrameState] = []
        let frameCancellable = store.framePublisher.sink { state in
            frameEvents.append(state)
        }

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 10, green: 0, blue: 0)
            ),
            dirtyRectangles: nil,
            changedPixelCount: nil,
            serverCursor: nil
        )
        store.flushPendingFrameDeliveryForTesting()
        XCTAssertEqual(frameEvents.count, 1)

        store.publish(
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 2,
                fill: RFBColor(red: 20, green: 0, blue: 0)
            ),
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)],
            changedPixelCount: 1,
            serverCursor: nil
        )
        store.clear()

        for _ in 0..<10 where frameEvents.last?.hasFramebuffer == true {
            await Task.yield()
        }

        XCTAssertEqual(frameEvents.count, 2)
        XCTAssertFalse(frameEvents.last?.hasFramebuffer ?? true)

        withExtendedLifetime(frameCancellable) {}
    }
}
