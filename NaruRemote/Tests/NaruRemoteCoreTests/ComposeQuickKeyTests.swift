import XCTest
@testable import NaruRemoteCore

final class ComposeQuickKeyTests: XCTestCase {
    // MARK: - Pure emission mapping

    func testEscapeEmissionIsBareEscapeKeysym() {
        let emission = ComposeQuickKey.escape.emission
        XCTAssertEqual(emission.keysym, 0xFF1B)
        XCTAssertTrue(emission.modifiers.isEmpty)
    }

    func testTabEmissionIsBareTabKeysym() {
        let emission = ComposeQuickKey.tab.emission
        XCTAssertEqual(emission.keysym, 0xFF09)
        XCTAssertTrue(emission.modifiers.isEmpty)
    }

    func testControlCEmissionIsLowercaseCWrappedInControl() {
        let emission = ComposeQuickKey.controlC.emission
        XCTAssertEqual(emission.keysym, 0x63) // 'c'
        XCTAssertEqual(emission.modifiers, [.control])
    }

    func testArrowEmissionsAreBareArrowKeysyms() {
        XCTAssertEqual(ComposeQuickKey.up.emission.keysym, 0xFF52)
        XCTAssertTrue(ComposeQuickKey.up.emission.modifiers.isEmpty)
        XCTAssertEqual(ComposeQuickKey.down.emission.keysym, 0xFF54)
        XCTAssertTrue(ComposeQuickKey.down.emission.modifiers.isEmpty)
    }

    func testEveryQuickKeyHasNonEmptyLabels() {
        for key in ComposeQuickKey.allCases {
            XCTAssertFalse(key.label.isEmpty, "\(key) label")
            XCTAssertFalse(key.accessibilityLabel.isEmpty, "\(key) a11y label")
        }
    }

    // MARK: - Wire envelope through KeystrokeEmitter

    func testEscapeQuickKeyEmitsSingleDownUpPair() async throws {
        let recorder = RecordingKeyEventClient()
        let emitter = KeystrokeEmitter(client: recorder)
        let emission = ComposeQuickKey.escape.emission

        try await emitter.emit(keysym: emission.keysym, modifiers: emission.modifiers)

        let descriptors = await recorder.descriptors()
        XCTAssertEqual(descriptors, ["65307:true", "65307:false"]) // 0xFF1B
    }

    func testControlCQuickKeyEmitsCtrlWrappedEnvelope() async throws {
        // Byte-identical to Direct mode's armed-Ctrl + `c` path
        // (the founder's terminal Ctrl-C), proving the quick-key
        // bridge reuses the same emission contract.
        let recorder = RecordingKeyEventClient()
        let emitter = KeystrokeEmitter(client: recorder)
        let emission = ComposeQuickKey.controlC.emission

        try await emitter.emit(keysym: emission.keysym, modifiers: emission.modifiers)

        let descriptors = await recorder.descriptors()
        XCTAssertEqual(
            descriptors,
            [
                "65507:true",  // Control_L 0xFFE3 down
                "99:true",     // c 0x63 down
                "99:false",    // c 0x63 up
                "65507:false"  // Control_L 0xFFE3 up
            ]
        )
    }

    // MARK: - Recorder

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
