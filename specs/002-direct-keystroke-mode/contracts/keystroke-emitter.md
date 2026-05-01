# Contract: `RFBKeyEventClient` and `KeystrokeEmitter`

**Feature**: `specs/002-direct-keystroke-mode`
**Date**: 2026-05-02
**Phase**: Phase 1 (informs `tasks.md` and implementation; partner doc to `data-model.md`)

This contract pins the wire format, the capability protocol, and the
semantics of every method on `KeystrokeEmitter`. Tests in
`KeystrokeEmitterTests` assert against this contract verbatim — if the
contract changes, the contract file changes first, then the tests, then
the production code. (Spec Kit rule.)

---

## Wire format — RFB `KeyEvent` (RFC 6143 §7.5.4)

Every keystroke pushes exactly **8 bytes** to the RFB stream.

| Offset | Size | Field | Value |
| --- | --- | --- | --- |
| 0 | 1 | message-type | `4` (KeyEvent) |
| 1 | 1 | down-flag | `1` (press) or `0` (release) |
| 2 | 2 | padding | `0x00 0x00` |
| 4 | 4 | key | X11 keysym, **big-endian unsigned 32-bit** |

No batching. No length prefix. Each `KeyEvent` is a free-standing 8-byte
write; the RFB connection is a stream and the receiver demultiplexes by
the leading message-type byte.

**Example wire frames** (hex):

| Logical event | Wire bytes |
| --- | --- |
| Press `c` (no modifiers) | `04 01 00 00 00 00 00 63` |
| Release `c` | `04 00 00 00 00 00 00 63` |
| Press `Control_L` | `04 01 00 00 00 00 FF E3` |
| Release `Control_L` | `04 00 00 00 00 00 FF E3` |
| Press `F5` | `04 01 00 00 00 00 FF C2` |
| Press `Up` arrow | `04 01 00 00 00 00 FF 52` |

---

## `RFBKeyEventClient` — capability protocol

**Location**: `Sources/NaruRemoteCore/VNC/RFBClientBoundary.swift`
**Pattern**: peer to `RFBPointerEventClient`; composed into `RFBStreamingClient`.

```swift
public protocol RFBKeyEventClient: AnyObject, Sendable {
    /// Encode and send a single RFB KeyEvent (RFC 6143 §7.5.4) on the
    /// active connection.  Throws if the connection is not in a
    /// streaming state.
    ///
    /// Naru does NOT batch KeyEvents.  Each call writes exactly 8
    /// bytes to the wire and returns when the write completes.
    /// Callers (the `KeystrokeEmitter`) are responsible for ordering
    /// modifier downs / character downs / character ups / modifier
    /// ups.
    func sendKeyEvent(downFlag: Bool, keysym: UInt32) async throws
}

public protocol RFBStreamingClient:
    RFBAuthenticatedFirstFrameConnecting,
    RFBNoAuthSessionConnecting,
    RFBAuthenticatedSessionConnecting,
    RFBFramebufferUpdating,
    RemoteClipboardTextClient,
    RFBPointerEventClient,
    RFBKeyEventClient {}    // ← new
```

**Production adopter**: `RFBNetworkClient` in `Sources/NaruRemoteCore/VNC/RFBNetworkClient.swift`. The implementation is a 3-line method calling `RFBClientMessageEncoder.encodeKeyEvent(downFlag:keysym:)` and then the existing `sendData(_:)` helper — symmetric to the existing `sendPointerEvent(...)`.

**Test adopter**: `FakeRFBServerKit` extends its message-recorder side to capture every incoming `KeyEvent` byte sequence in a typed array. Tests inject the fake into `KeystrokeEmitter.init(client:)` directly without a real socket.

---

## `RFBClientMessageEncoder.encodeKeyEvent(downFlag:keysym:)`

**Location**: `Sources/NaruRemoteCore/VNC/RFBClientMessageEncoder.swift` (new static method peer to `encodePointerEvent`).

```swift
public static func encodeKeyEvent(downFlag: Bool, keysym: UInt32) -> Data {
    var data = Data(count: 8)
    data[0] = 4                                    // message-type
    data[1] = downFlag ? 1 : 0                     // down-flag
    data[2] = 0; data[3] = 0                       // padding
    data[4] = UInt8((keysym >> 24) & 0xFF)         // big-endian keysym
    data[5] = UInt8((keysym >> 16) & 0xFF)
    data[6] = UInt8((keysym >>  8) & 0xFF)
    data[7] = UInt8( keysym        & 0xFF)
    return data
}
```

**Contract**:

- Always returns 8 bytes.
- Pure — no I/O, no clock, no random. Same input → same output.
- Big-endian on the wire regardless of host endianness.
- `RFBClientMessageEncoderTests` covers: `(true, 0x0063) → "04 01 00 00 00 00 00 63"`, `(false, 0xFFE3) → "04 00 00 00 00 00 FF E3"`, plus boundary values `0x00000000` and `0xFFFFFFFF`.

---

## `KeystrokeEmitter.emit(keysym:modifiers:)` — semantics

**Location**: `Sources/NaruRemoteCore/RemoteInputDock/KeystrokeEmitter.swift`

```swift
public func emit(
    keysym: UInt32,
    modifiers: Set<StickyModifierState.Modifier>
) async throws
```

For one logical "press a key" event with the given active modifier set, emit the following sequence in order:

1. For each modifier in the deterministic order `[.control, .shift, .alt, .meta]`, if it is in `modifiers`, send `KeyEvent(downFlag: true, keysym: keysymOf(modifier))`.
2. Send `KeyEvent(downFlag: true, keysym: keysym)`.
3. Send `KeyEvent(downFlag: false, keysym: keysym)`.
4. For each modifier in the **reverse** deterministic order `[.meta, .alt, .shift, .control]`, if it is in `modifiers`, send `KeyEvent(downFlag: false, keysym: keysymOf(modifier))`.

Total `KeyEvent`s on the wire: `2 * (1 + modifiers.count)`.

**Why this order**:

- Modifiers down → key down → key up → modifiers up matches what physical hardware does (you press and hold Ctrl, *then* press and release c, *then* release Ctrl). VNC servers expect this; an out-of-order emission produces lost or sticky modifiers on the remote.
- The deterministic Control → Shift → Alt → Meta ordering and its mirror release ordering make the wire bytes byte-for-byte identical between the on-screen and hardware paths (SC-005). Tests assert against literal hex strings.

**Error semantics**:

- If the underlying `RFBKeyEventClient.sendKeyEvent(...)` throws on any of the writes, the emitter rethrows immediately. The caller (`NaruRemoteAppModel.tapDirectKey`) MUST clear sticky-armed state on throw to avoid stranding the user with phantom-armed modifiers (the wire saw a partial emission).
- The emitter does **not** retry, deduplicate, or rate-limit.

---

## `KeystrokeEmitter.emitHardware(keysym:modifiers:)` — semantics

Identical contract to `emit(keysym:modifiers:)` — same emission order, same byte count, same error semantics. The separate name exists only to make the call site explicit about the source of the modifier set:

- `emit(keysym:modifiers:)` is called from on-screen taps where the modifier set comes from `StickyModifierState.activeModifiers`. The caller consumes armed state after.
- `emitHardware(keysym:modifiers:)` is called from `pressesBegan` / `pressesEnded` where the modifier set comes from `UIKey.modifierFlags`. The caller does *not* consume sticky state — the OS owns the hardware modifier release.

Wire output for the same `(keysym, modifiers)` pair MUST be byte-identical between the two methods. Tests in `KeystrokeEmitterTests.testHardwareAndOnScreenAreByteIdentical` exercise both paths and `XCTAssertEqual` the recorder's `keyEvents` arrays.

---

## What is **not** in this contract

- **Auto-repeat synthesis** — neither path repeats. `emit` and `emitHardware` send exactly one down + one up for the keysym. Press-and-hold on either source produces no wire repetition. The remote OS's auto-repeat (which fires while a key's `down` is held) is not reachable from Naru on the soft path because we send `up` immediately after `down`. This is the locked FR-016 trade-off.
- **Modifier mask** — the wire never carries a separate "modifier mask" byte. Modifier state is expressed as adjacent down / up `KeyEvent`s for the modifier keysyms.
- **Compose & Send** — `KeystrokeEmitter` is a Direct-mode-only path. Compose & Send continues to use `RemoteClipboardTextClient` and never touches `KeystrokeEmitter`.

---

## Verification ownership

| Contract clause | Test target | Evidence |
| --- | --- | --- |
| 8-byte wire frame for every `KeyEvent` | `RFBClientMessageEncoderTests` | hex-string equality |
| Big-endian keysym | `RFBClientMessageEncoderTests` | boundary values `0xFFE3`, `0xFFFFFFFF`, `0x0000` |
| Modifier press order Control → Shift → Alt → Meta | `KeystrokeEmitterTests` | recorder `keyEvents` array equality |
| Modifier release order reverse of press | `KeystrokeEmitterTests` | recorder `keyEvents` array equality |
| Total `KeyEvent`s = `2 * (1 + modifiers.count)` | `KeystrokeEmitterTests` | `recorder.keyEvents.count == 2 * (1 + modifiers.count)` |
| `emit` and `emitHardware` byte-identical for same input | `KeystrokeEmitterTests.testHardwareAndOnScreenAreByteIdentical` | `XCTAssertEqual` on both recorder arrays |
| Throw on partial wire failure → caller clears sticky-armed | `NaruRemoteAppModelTests.testThrowingEmitClearsArmedModifiers` | model-level integration test |
| `RFBNetworkClient` adopts `RFBKeyEventClient` and routes through `encodeKeyEvent` | `RFBNetworkClientTests` (integration) | `FakeRFBServerKit` socket-level verification |
