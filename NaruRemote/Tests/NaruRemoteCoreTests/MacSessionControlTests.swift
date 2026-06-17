import XCTest
@testable import NaruRemoteCore

final class MacSessionControlTests: XCTestCase {
    func testMissionControlUsesControlUpArrow() {
        let emission = MacSessionControl.missionControl.emission
        XCTAssertEqual(emission.keysym, 0xFF52)
        XCTAssertEqual(emission.modifiers, [.control])
    }

    func testAppWindowsUsesControlDownArrow() {
        let emission = MacSessionControl.appWindows.emission
        XCTAssertEqual(emission.keysym, 0xFF54)
        XCTAssertEqual(emission.modifiers, [.control])
    }

    func testSwitchApplicationUsesCommandTab() {
        let emission = MacSessionControl.switchApplication.emission
        XCTAssertEqual(emission.keysym, 0xFF09)
        XCTAssertEqual(emission.modifiers, [.meta])
    }

    func testShowDesktopUsesF11DefaultShortcut() {
        let emission = MacSessionControl.showDesktop.emission
        XCTAssertEqual(emission.keysym, 0xFFC8)
        XCTAssertTrue(emission.modifiers.isEmpty)
    }

    func testSpaceNavigationUsesControlArrows() {
        XCTAssertEqual(MacSessionControl.spaceLeft.emission.keysym, 0xFF51)
        XCTAssertEqual(MacSessionControl.spaceLeft.emission.modifiers, [.control])
        XCTAssertEqual(MacSessionControl.spaceRight.emission.keysym, 0xFF53)
        XCTAssertEqual(MacSessionControl.spaceRight.emission.modifiers, [.control])
    }

    func testEveryControlHasNonEmptyPresentationMetadata() {
        for control in MacSessionControl.allCases {
            XCTAssertFalse(control.label.isEmpty, "\(control) label")
            XCTAssertFalse(control.accessibilityLabel.isEmpty, "\(control) accessibilityLabel")
            XCTAssertFalse(control.systemImageName.isEmpty, "\(control) systemImageName")
        }
    }

    func testCommandTabEnvelopeUsesMetaModifier() async throws {
        let recorder = RecordingKeyEventClient()
        let emitter = KeystrokeEmitter(client: recorder)
        let emission = MacSessionControl.switchApplication.emission

        try await emitter.emit(keysym: emission.keysym, modifiers: emission.modifiers)

        let descriptors = await recorder.descriptors()
        XCTAssertEqual(
            descriptors,
            [
                "65511:true",  // Meta_L 0xFFE7 down
                "65289:true",  // Tab 0xFF09 down
                "65289:false", // Tab 0xFF09 up
                "65511:false"  // Meta_L 0xFFE7 up
            ]
        )
    }

    actor RecordingKeyEventClient: RFBKeyEventClient {
        private(set) var events: [(keysym: UInt32, isDown: Bool)] = []

        func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
            events.append((keysym: keysym, isDown: isDown))
        }

        func descriptors() -> [String] {
            events.map { "\($0.keysym):\($0.isDown)" }
        }
    }
}
