import XCTest
@testable import NaruRemoteCore

/// Spec 012 US2-1 — the orca-measured repeatable set lives on
/// `AccessoryKey.repeatable`. Backspace is not a strip key.
final class AccessoryKeyTests: XCTestCase {
    func testRepeatableIsExactlyArrowsAndDelete() {
        let expected: Set<AccessoryKey> = [
            .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .delete,
        ]
        for key in AccessoryKey.allCases {
            XCTAssertEqual(
                key.repeatable,
                expected.contains(key),
                "\(key.rawValue) repeatable flag"
            )
        }
        XCTAssertEqual(expected.count, 5)
        XCTAssertFalse(
            AccessoryKey.allCases.contains { $0.rawValue == "backspace" },
            "Backspace is not on the accessory strip (orca set)."
        )
    }

    func testPrimaryStripStillEndsWithDeleteAndExcludesControlC() {
        XCTAssertEqual(AccessoryKey.primaryStripKeys.last, .delete)
        XCTAssertFalse(AccessoryKey.primaryStripKeys.map(\.rawValue).contains("controlC"))
    }
}
