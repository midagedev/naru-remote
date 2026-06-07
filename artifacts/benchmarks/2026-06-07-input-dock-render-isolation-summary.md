# Input Dock Render Isolation Summary

Date: 2026-06-07 KST

## Purpose

Reproduce the class of failures where real-session stream churn reaches the
Compose input bridge and can make Korean/CJK IME input feel frozen after a VNC
connection starts.

## Change

`NaruRemoteAppShell` now mounts `RemoteInputDockView` through an Equatable host
whose `RemoteInputDockRenderState` includes only visible input-dock state:

- Compose text and safe send/helper status
- Direct-mode and sticky-modifier state
- Compact vs standard dock layout
- Compose quick-key availability

Stream telemetry, framebuffer presence, dirty-rect metadata, changed-pixel
counts, renderer pressure, app-frame apply timing, and MainActor responsiveness
samples are intentionally excluded so they cannot trigger fresh UIKit
`UITextView` bridge updates while local IME composition owns the editor.

## Verification

- `swift test --filter RemoteInputDockRenderStateTests`
- `swift test`

The focused test suite proves:

- Noisy stream/frame telemetry produces the same input render state.
- Compose draft text changes produce a different input render state.
- Active-session quick-key availability produces a different input render state.

Full test status: 1174 tests passed, with 14 benchmark/device-gated tests
skipped.

## Interpretation

This is an input/UI isolation fix, not a 10fps streaming success claim. It
reduces one concrete way a real VNC session can disturb Compose input while the
remaining VNC receive-path bottleneck is still measured separately by the
10fps readiness benchmark.

## Privacy

The artifact and tests use only fixed UI state labels and safe aggregate
counters. They omit host identity, credentials, request coordinates,
dimensions, pixels, byte counts, raw timings, command text, draft text,
marked text, IME state, keysyms, and pointer coordinates.
