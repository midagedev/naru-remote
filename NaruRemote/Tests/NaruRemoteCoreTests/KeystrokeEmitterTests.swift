import XCTest
@testable import NaruRemoteCore

final class KeystrokeEmitterTests: XCTestCase {

    // MARK: - Empty modifier path (Phase 3 scope)

    func testEmitWithEmptyModifierSetSendsTwoKeyEvents() async throws {
        // Single-key tap: exactly one KeyEvent down + one
        // KeyEvent up, in that order.
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        try await emitter.emit(keysym: 0x0063, modifiers: [])

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot[0].keysym, 0x0063)
        XCTAssertEqual(snapshot[0].isDown, true)
        XCTAssertEqual(snapshot[1].keysym, 0x0063)
        XCTAssertEqual(snapshot[1].isDown, false)
    }

    func testEmitDefaultArgIsEmptyModifierSet() async throws {
        // The modifiers default arg of `[]` is the Phase 3 happy
        // path — Phase 4 callers explicitly pass a non-empty set.
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        try await emitter.emit(keysym: 0xFF09)  // Tab

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 2)
    }

    func testEmitMultipleSequentialKeysProducesInterleavedDownUp() async throws {
        // Typing "qwe" produces three down/up pairs in input
        // order — six events total.
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        try await emitter.emit(keysym: 0x71)  // q
        try await emitter.emit(keysym: 0x77)  // w
        try await emitter.emit(keysym: 0x65)  // e

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 6)
        XCTAssertEqual(snapshot.map { ($0.keysym, $0.isDown) }.map { "\($0.0):\($0.1)" }, [
            "113:true", "113:false",
            "119:true", "119:false",
            "101:true", "101:false"
        ])
    }

    // MARK: - Phase 4 modifier-wrapping emission

    func testEmitWithSingleModifierWrapsKeyDownUp() async throws {
        // Ctrl-c — the canonical test case from
        // contracts/keystroke-emitter.md.  Wire shows
        //   1. Control_L down (0xFFE3)
        //   2. c down          (0x0063)
        //   3. c up            (0x0063)
        //   4. Control_L up    (0xFFE3)
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        try await emitter.emit(keysym: 0x0063, modifiers: [.control])

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 4, "Ctrl-c → 2*(1+1) = 4 KeyEvents")
        XCTAssertEqual(snapshot.map { ($0.keysym, $0.isDown) }.map { "\(String($0.0, radix: 16, uppercase: true)):\($0.1)" }, [
            "FFE3:true",   // Control_L down
            "63:true",     // c down
            "63:false",    // c up
            "FFE3:false",  // Control_L up
        ])
    }

    func testEmitWithControlShiftPressOrderIsControlThenShift() async throws {
        // contracts/keystroke-emitter.md emission order: Control →
        // Shift → Alt → Meta on press; reverse on release.
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        try await emitter.emit(keysym: 0x0063, modifiers: [.shift, .control])

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 6, "Ctrl-Shift-c → 2*(1+2) = 6 KeyEvents")
        XCTAssertEqual(snapshot.map { ($0.keysym, $0.isDown) }.map { "\(String($0.0, radix: 16, uppercase: true)):\($0.1)" }, [
            "FFE3:true",   // Control_L down  (canonical first)
            "FFE1:true",   // Shift_L   down
            "63:true",     // c down
            "63:false",    // c up
            "FFE1:false",  // Shift_L   up    (reverse)
            "FFE3:false",  // Control_L up
        ])
    }

    func testEmitWithAllFourModifiersTotalsTenEvents() async throws {
        // Ctrl-Shift-Alt-Cmd-Tab.  2*(1+4) = 10 events on the wire.
        // Press order Control→Shift→Alt→Meta; release reverse.
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        try await emitter.emit(
            keysym: 0xFF09,  // Tab
            modifiers: [.meta, .alt, .shift, .control]
        )

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 10, "4 modifiers → 2*(1+4) = 10 KeyEvents")
        XCTAssertEqual(snapshot.map { ($0.keysym, $0.isDown) }.map { "\(String($0.0, radix: 16, uppercase: true)):\($0.1)" }, [
            "FFE3:true",   // Control_L
            "FFE1:true",   // Shift_L
            "FFE9:true",   // Alt_L
            "FFE7:true",   // Meta_L
            "FF09:true",   // Tab down
            "FF09:false",  // Tab up
            "FFE7:false",  // Meta_L
            "FFE9:false",  // Alt_L
            "FFE1:false",  // Shift_L
            "FFE3:false",  // Control_L
        ])
    }

    func testEmitWithMetaOnlyOrdersAtEndOfModifierGroup() async throws {
        // Just Meta — proves single-modifier ordering picks the
        // correct keysym out of the four-element ordered list.
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        try await emitter.emit(keysym: 0x09, modifiers: [.meta])  // Meta-Tab style char 0x09

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 4)
        XCTAssertEqual(snapshot[0].keysym, 0xFFE7)  // Meta_L down
        XCTAssertEqual(snapshot[0].isDown, true)
        XCTAssertEqual(snapshot[3].keysym, 0xFFE7)  // Meta_L up
        XCTAssertEqual(snapshot[3].isDown, false)
    }

    func testEmitWithAltShiftPressesAltSecondReleasesAltFirst() async throws {
        // Two-modifier order check that proves Alt comes after
        // Shift on press, before Shift on release.
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        try await emitter.emit(keysym: 0x0061, modifiers: [.alt, .shift])  // Shift-Alt-a

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 6)
        // Press: Shift then Alt (Control < Shift < Alt < Meta).
        XCTAssertEqual(snapshot[0].keysym, 0xFFE1)  // Shift_L down
        XCTAssertTrue(snapshot[0].isDown)
        XCTAssertEqual(snapshot[1].keysym, 0xFFE9)  // Alt_L   down
        XCTAssertTrue(snapshot[1].isDown)
        // Key in the middle.
        XCTAssertEqual(snapshot[2].keysym, 0x0061)
        XCTAssertEqual(snapshot[3].keysym, 0x0061)
        // Release: Alt then Shift (reverse).
        XCTAssertEqual(snapshot[4].keysym, 0xFFE9)  // Alt_L   up
        XCTAssertFalse(snapshot[4].isDown)
        XCTAssertEqual(snapshot[5].keysym, 0xFFE1)  // Shift_L up
        XCTAssertFalse(snapshot[5].isDown)
    }

    // MARK: - Throw propagation

    func testEmitRethrowsWhenClientThrows() async {
        // KeystrokeEmitter does not retry; it surfaces the
        // RFBKeyEventClient throw so the caller (model) can clear
        // sticky-armed state per contracts/keystroke-emitter.md.
        let recorder = TestKeyEventRecorder(failsAfter: 1)
        let emitter = KeystrokeEmitter(client: recorder)

        do {
            try await emitter.emit(keysym: 0x0063)
            XCTFail("emit should rethrow when the client throws")
        } catch let error as TestKeyEventRecorderError {
            XCTAssertEqual(error, .programmedFailure)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

// MARK: - Test fake

private actor TestKeyEventRecorder: RFBKeyEventClient {
    private var events: [(keysym: UInt32, isDown: Bool)] = []
    private let failsAfter: Int?
    private var sentCount = 0

    init(failsAfter: Int? = nil) {
        self.failsAfter = failsAfter
    }

    nonisolated func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        try await self.recordOrThrow(keysym: keysym, isDown: isDown)
    }

    private func recordOrThrow(keysym: UInt32, isDown: Bool) throws {
        sentCount += 1
        if let failsAfter, sentCount > failsAfter {
            throw TestKeyEventRecorderError.programmedFailure
        }
        events.append((keysym: keysym, isDown: isDown))
    }

    func snapshot() -> [(keysym: UInt32, isDown: Bool)] {
        events
    }
}

private enum TestKeyEventRecorderError: Error, Equatable {
    case programmedFailure
}
