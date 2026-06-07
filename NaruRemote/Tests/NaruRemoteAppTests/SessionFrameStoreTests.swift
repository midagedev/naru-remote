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
