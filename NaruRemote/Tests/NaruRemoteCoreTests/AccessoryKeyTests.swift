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

    /// Spec 012 US2-3: the strip modifiers render as macOS glyphs so
    /// the row fits Esc/Tab/⌃C at iPhone width. Latin words regress it.
    func testStickyModifierStripLabelsAreMacGlyphs() {
        XCTAssertEqual(
            StickyModifierState.Modifier.stripOrder.map(\.stripLabel),
            ["⌃", "⌥", "⌘", "⇧"]
        )
        for modifier in StickyModifierState.Modifier.stripOrder {
            XCTAssertEqual(
                modifier.stripLabel.count,
                1,
                "\(modifier.rawValue) must stay a single glyph to fit 36pt."
            )
        }
    }

    func testPrimaryStripStillEndsWithDeleteAndExcludesControlC() {
        XCTAssertEqual(AccessoryKey.primaryStripKeys.last, .delete)
        XCTAssertFalse(AccessoryKey.primaryStripKeys.map(\.rawValue).contains("controlC"))
    }
}
