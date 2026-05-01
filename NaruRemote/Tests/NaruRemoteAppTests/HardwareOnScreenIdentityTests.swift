#if canImport(UIKit)
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Phase 5 / US-3 / T030.
///
/// SC-005 lock test.  For a fixed input `(keysym, modifiers)` pair,
/// `KeystrokeEmitter.emit(...)` (the on-screen path) and
/// `KeystrokeEmitter.emitHardware(...)` (the hardware-keyboard path)
/// must produce **byte-identical** recorder arrays.  This is the
/// contract clause from `contracts/keystroke-emitter.md`:
///
/// > Wire output for the same `(keysym, modifiers)` pair MUST be
/// > byte-identical between the two methods.
///
/// Why identity holds even though the call sites differ:
///
/// On-screen Ctrl-c (StickyModifierState reports `[.control]` armed,
/// then the user taps `c`):
///   1. Control_L down (0xFFE3)
///   2. c             down (0x0063)
///   3. c             up   (0x0063)
///   4. Control_L     up   (0xFFE3)
///
/// Hardware Ctrl-c — the OS reports `modifierFlags = [.control]` on
/// the UIPress for `c`.  `emitHardware` wraps with the same canonical
/// modifier-down → key-down → key-up → modifier-up envelope, so the
/// recorder sees the identical four-frame sequence.  This is
/// intentional: hardware-side modifier press/release UIPress events
/// flow through `KeysymMapping.keysym(forUIKeyCode:)` for their own
/// keysyms when the OS reports them as separate presses (Caps-style
/// UX), but the canonical emit-with-wrap path still applies here
/// because `UIPress.key.modifierFlags` already carries the active
/// modifier set on the character press itself.
///
/// If the caller wants raw "send a single keysym down/up without
/// wrapping" semantics (e.g. when synthesizing a modifier-key
/// release that the OS reported as its own UIPress), it can pass
/// `modifiers: []` to `emitHardware` — then both paths still match
/// byte-for-byte.
final class HardwareOnScreenIdentityTests: XCTestCase {

    func testCtrlCByteIdentity() async throws {
        // Path A — on-screen tap of `c` while Ctrl is armed.
        let recorderA = TestKeyEventRecorder()
        let emitterA = KeystrokeEmitter(client: recorderA)
        try await emitterA.emit(keysym: 0x0063, modifiers: [.control])
        let snapshotA = await recorderA.snapshot()

        // Path B — hardware UIPress of `c` with `.control` in
        // modifierFlags, mapped through KeysymMapping+UIKit.
        let recorderB = TestKeyEventRecorder()
        let emitterB = KeystrokeEmitter(client: recorderB)
        try await emitterB.emitHardware(keysym: 0x0063, modifiers: [.control])
        let snapshotB = await recorderB.snapshot()

        XCTAssertEqual(
            snapshotA.map { ($0.keysym, $0.isDown) }.map { "\($0.0):\($0.1)" },
            snapshotB.map { ($0.keysym, $0.isDown) }.map { "\($0.0):\($0.1)" },
            "SC-005 byte-identity must hold for Ctrl-c"
        )
        XCTAssertEqual(snapshotA.count, 4)
        XCTAssertEqual(snapshotB.count, 4)
    }

    func testEmptyModifiersByteIdentity() async throws {
        // Plain `c` — no modifiers on either path.  Two events
        // each, identical bytes.
        let recorderA = TestKeyEventRecorder()
        let recorderB = TestKeyEventRecorder()
        let emitterA = KeystrokeEmitter(client: recorderA)
        let emitterB = KeystrokeEmitter(client: recorderB)

        try await emitterA.emit(keysym: 0x0063, modifiers: [])
        try await emitterB.emitHardware(keysym: 0x0063, modifiers: [])

        let a = await recorderA.snapshot()
        let b = await recorderB.snapshot()
        XCTAssertEqual(a.map { "\($0.keysym):\($0.isDown)" },
                       b.map { "\($0.keysym):\($0.isDown)" })
        XCTAssertEqual(a.count, 2)
    }

    func testAllFourModifiersByteIdentity() async throws {
        // Ctrl-Shift-Alt-Cmd-Tab: 10 events on each path.  Modifier
        // press order Control → Shift → Alt → Meta; release reverse.
        let recorderA = TestKeyEventRecorder()
        let recorderB = TestKeyEventRecorder()
        let emitterA = KeystrokeEmitter(client: recorderA)
        let emitterB = KeystrokeEmitter(client: recorderB)

        try await emitterA.emit(
            keysym: 0xFF09,  // Tab
            modifiers: [.meta, .alt, .shift, .control]
        )
        try await emitterB.emitHardware(
            keysym: 0xFF09,
            modifiers: [.control, .shift, .alt, .meta]
        )

        let a = await recorderA.snapshot()
        let b = await recorderB.snapshot()
        XCTAssertEqual(a.count, 10)
        XCTAssertEqual(b.count, 10)
        XCTAssertEqual(a.map { "\($0.keysym):\($0.isDown)" },
                       b.map { "\($0.keysym):\($0.isDown)" })
    }
}

// MARK: - Test fake (mirrors the one in KeystrokeEmitterTests)

private actor TestKeyEventRecorder: RFBKeyEventClient {
    private var events: [(keysym: UInt32, isDown: Bool)] = []

    nonisolated func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        await self.append(keysym: keysym, isDown: isDown)
    }

    private func append(keysym: UInt32, isDown: Bool) {
        events.append((keysym: keysym, isDown: isDown))
    }

    func snapshot() -> [(keysym: UInt32, isDown: Bool)] {
        events
    }
}
#endif
