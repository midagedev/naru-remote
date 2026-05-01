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

    // MARK: - Phase 3 modifier guard (will be removed in Phase 4)

    func testEmitWithNonEmptyModifierSetThrowsUnsupportedInPhase3() async {
        // Phase 4 will land the modifier-wrapping path; until
        // then the emitter throws so callers cannot silently use
        // a half-implemented modifier path.
        let recorder = TestKeyEventRecorder()
        let emitter = KeystrokeEmitter(client: recorder)

        do {
            try await emitter.emit(keysym: 0x0063, modifiers: [.control])
            XCTFail("emit with non-empty modifier set should throw in Phase 3")
        } catch let error as KeystrokeEmitterError {
            XCTAssertEqual(error, .unsupportedModifierSet)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.count, 0, "no KeyEvent should reach the wire when emit throws")
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
