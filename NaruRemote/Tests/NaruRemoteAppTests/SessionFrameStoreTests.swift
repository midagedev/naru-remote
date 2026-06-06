import Combine
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class SessionFrameStoreTests: XCTestCase {
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

        XCTAssertEqual(frameEvents.count, 3)
        XCTAssertEqual(store.presentationRevision, revisionBaseline + 1)
        XCTAssertGreaterThan(presentationPublishCount, presentationBaseline)

        withExtendedLifetime((presentationCancellable, frameCancellable)) {}
    }
}
