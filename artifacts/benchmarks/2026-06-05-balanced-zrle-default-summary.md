# 2026-06-05 Balanced ZRLE Default Summary

## Trigger

Long-running goal: reduce heat and improve practical sustained iPhone VNC
sessions using simulator/live benchmarks and protocol research. The current
balanced production profile (`localLowLatency`) requested Tight first.

## Research Direction

- RFC 6143 defines `SetEncodings` as the client telling the server which
  encodings it accepts and the order it prefers; a server may still choose what
  it can actually produce.
- TigerVNC documents automatic protocol selection and exposes preferred
  encoding, compression level, quality level, and pointer-event interval because
  responsiveness is a server/link/client tradeoff.
- TightVNC notes that Tight compression levels trade CPU for compression, and
  cursor-shape updates let clients process mouse movement locally.

## Live Localhost VNC Evidence

Safety boundary: these runs are redacted aggregate benchmark output only. They
omit host, password, server name, framebuffer dimensions, coordinates, pixels,
byte counts, cursor pixels, compressed payloads, raw error descriptions, and raw
per-frame timing samples.

Command shape:

```sh
NARU_LIVE_MAC_HOST=127.0.0.1 NARU_LIVE_MAC_PORT=5900 \
NARU_LIVE_MAC_PASSWORD='[redacted]' swift run VNCLiveBenchmark \
  --attempts 1 \
  --full-refresh-samples 0 \
  --continuous-update-samples 1 \
  --first-frame-profiles none \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 20 \
  --stream-shape-profiles tight-first,zrle-compression-0 \
  --stream-shape-transport request-response \
  --stream-shape-empty-backoff app \
  --stream-shape-client-pressure app \
  --timeout 8 \
  --idle-timeout 0.75
```

Normal pacing result:

| Profile | Actual encoding | Content FPS | Update avg/p95 ms | Client-processing p95 ms | Adaptive pressure pacing | Renderer partial/full |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| tight-first | Raw only | 5.20 | 123 / 480 | 96 | 549 permille | 104 / 0 |
| zrle-compression-0 | ZRLE only | 6.35 | 114 / 477 | 8 | 0 permille | 127 / 0 |

Low-power pacing result:

| Profile | Actual encoding | Content FPS | Update avg/p95 ms | Client-processing p95 ms | Adaptive pressure pacing | Renderer partial/full |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| tight-first | Raw only | 4.20 | 146 / 466 | 100 | 720 permille | 84 / 0 |
| zrle-compression-0 | ZRLE only | 4.15 | 158 / 502 | 9 | 0 permille | 83 / 0 |

## Decision

Switch `RFBEncodingPreference.localLowLatency` from Tight-first to
ZRLE-compression-0 with server cursor and Extended Clipboard pseudo-encodings.
Keep Hextile/CopyRect/Raw fallback. Keep ContinuousUpdates and automatic
adaptive renegotiation disabled by default.

## Rationale

The decisive new signal is actual encoding mix. Tight-first was not receiving
Tight on this local macOS Screen Sharing target; it was receiving Raw. ZRLE
compression-0 consistently received actual ZRLE. For sustained iPhone sessions,
the lower local client-processing tail is more relevant to heat and stutter than
a small low-power average-latency difference.

## Verification

- `swift run VNCLiveBenchmark` normal 20 second duration run above.
- `swift run VNCLiveBenchmark` low-power 20 second duration run above.
- Post-change `local-low-latency` 12 second smoke:
  - actual encodings: ZRLE only
  - content FPS: 5.33
  - update avg/p95 ms: 139 / 489
  - client-processing p95 ms: 10
  - renderer partial/full uploads: 63 / 1
- `swift test --filter RFBEncodingTests`
- `swift test`
  - Result: passed, 619 tests, 10 skipped, 0 failures.
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`
  - Result: passed, 4 benchmarks, 0 failures.
  - Approximate monotonic-time averages: full allocation/upload ~= 3 ms,
    steady-state full upload ~= 0.5 ms, small dirty-rect upload ~= 0.02 ms,
    same-frame upload-gate skip ~= 0 ms.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' build`
  - Result: passed.

## Remaining Risk

- Physical iPhone thermal comfort still needs an on-device sustained pass.
- The result is strongest for macOS Screen Sharing on the current local target;
  other VNC servers may still prefer Tight. The explicit `tight-first` benchmark
  profile remains available for comparison.
