#if os(iOS) && canImport(UIKit)
import Combine
import XCTest
@testable import NaruRemoteApp

@MainActor
final class ComposeInputSessionIsolationTests: XCTestCase {
    func testTextSnapshotControllerIsNotASwiftUIObservableModel() {
        let controller = ComposeTextCommitController()

        XCTAssertFalse(
            controller is any ObservableObject,
            "Compose text input snapshots must stay outside SwiftUI observation while UIKit owns an active IME session."
        )
        controller.updateCurrentTextSnapshot("ㅎ")

        XCTAssertEqual(controller.currentText, "ㅎ")
    }
}
#endif
