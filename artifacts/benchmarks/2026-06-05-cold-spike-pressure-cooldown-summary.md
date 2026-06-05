# 2026-06-05 Cold Spike Pressure Cooldown Summary

## Trigger

After the ZRLE changed-bounds upload cut, localhost macOS Screen Sharing still
showed one 2 second-class client-processing/update spike at the beginning of
some sustained stream-shape runs. The app mirrored that benchmark behavior by
entering adaptive client-pressure pacing after one very-slow local-work frame,
but the recovery window was shared with sustained lag and full-upload pressure:
120 update decisions.

That was too sticky for this target. When the server only produced about two
content updates per second, one cold/profile-warm-up spike could keep the
viewer in power-saver cadence for most of a 20 second run.

## Research References

- RFC 6143 says framebuffer updates are client-requested and Cursor
  pseudo-encoding can improve perceived performance over slow links:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC documents automatic protocol selection, local cursor options,
  compression level, and preferred encodings:
  https://tigervnc.org/doc/vncviewer.html

## Change

This increment keeps the app's default `local-low-latency` encoding profile.
Cursor and ExtendedClipboard requests were not proven to be the cause of the
very-slow tail; profile-order runs showed the first stream profile could spike
whether or not those pseudo-encodings were present.

Instead, app and benchmark pressure recovery now split:

- one 1000 ms-class very-slow local-work spike: 8 update-decision recovery;
- repeated severe/moderate local-work lag or sustained full uploads: existing
  120 update-decision recovery.

`VNCLiveBenchmark` schema v29 adds
`streamShapeClientPressureVerySlowRecoveryUpdateCount` and keeps
`streamShapeClientPressureRecoveryUpdateCount` for the sustained recovery
window. The benchmark also gained ZRLE compression-0 pseudo-encoding isolation
profiles:

- `zrle-compression-0-cursor`
- `zrle-compression-0-clipboard`
- `zrle-compression-0-cursor-clipboard`

## Safe Aggregate Results

All rows are request/response, duration-capped 20 second stream-shape runs with
app client-pressure and viewport-interaction parity enabled. Reports omit host
identity, credentials, framebuffer dimensions, coordinates, pixels, cursor
pixels, byte counts, and raw samples.

| Run | Profile | Schema | Issues | Content FPS | Update p50/p95/max | Client p50/p95/max | Very slow | Full upload permille | Adaptive permille |
| --- | --- | --- | --- | ---: | --- | --- | ---: | ---: | ---: |
| v28 order-isolation baseline | `zrle-compression-0-cursor-clipboard` | 28 | `content-fps-failed`, `very-slow-update`, `adaptive-pressure-failed` | 1.80 | 156/390/2507 ms | 5/11/2147 ms | 1 | 0 | 972 |
| v29 app default | `local-low-latency` | 29 | `content-fps-failed`, `p95-update-warning`, `client-processing-failed`, `very-slow-update`, `adaptive-pressure-warning` | 1.70 | 189/549/2418 ms | 1/164/2179 ms | 1 | 0 | 395 |
| v29 cursor-only candidate | `zrle-compression-0-cursor` | 29 | `content-fps-failed`, `p95-update-warning`, `client-processing-failed`, `very-slow-update`, `adaptive-pressure-failed` | 1.70 | 160/515/2541 ms | 2/150/2154 ms | 1 | 0 | 711 |

Additional v28 pseudo-encoding isolation showed the first measured stream
profile, not a specific pseudo-encoding, was most likely to receive the
2 second-class spike. The same profile could avoid the spike when it was not
first in the run.

## Interpretation

The change does not claim that the decode/update tail is fixed. The very-slow
sample still exists, and the practical target still fails on content FPS and
client-processing tail for this local Screen Sharing target.

It does remove one important usability amplifier: a single cold spike no longer
locks the app into the same long recovery window reserved for repeated lag or
full-renderer-upload pressure. The post-change default run reduced adaptive
pressure from fail-class 972 permille to warning-class 395 permille while
keeping renderer full-upload pressure at 0.

The cursor-only candidate did not improve the result enough to justify dropping
ExtendedClipboard from the default connection profile in this increment.

## Verification

- `swift test --filter SessionStreamPressurePacingState --filter BenchmarkStreamShapePacingPolicyTests`
  - Result: passed, 32 tests, 0 failures.
- Live `VNCLiveBenchmark` local-low-latency 20 second stream-shape run
  - Result: command succeeded, schema v29, adaptive pressure warning instead of
    fail for the default profile.
- Live `VNCLiveBenchmark` cursor-only 20 second stream-shape run
  - Result: command succeeded, did not beat the current default.

## Remaining Risk

- Physical iPhone heat and hand-feel still need direct device validation.
- The remaining 2 second-class local-work spike still needs a decode/update
  tail investigation.
- Content FPS on a mostly static macOS Screen Sharing desktop is still a weak
  proxy for real typing/editor motion until the benchmark drives controlled
  host activity.
