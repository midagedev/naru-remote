# Startup Payload Traffic Gate Summary

Date: 2026-06-06

Purpose: make the poor-network low-traffic gate catch startup payload pressure,
not only sustained request/response pressure. The user's current target includes
traffic and degraded network behavior, and the app low-traffic live run showed
that a small first-frame request can still spend most startup time reading the
payload.

## Protocol Basis

- RFC 6143 keeps framebuffer updates client-demand-driven and explicitly allows
  clients to regulate incremental `FramebufferUpdateRequest` cadence to avoid
  excessive network traffic:
  https://www.rfc-editor.org/rfc/rfc6143#section-7.5.3
- TigerVNC's server path also treats continuous updates as a region and
  congestion-control problem through Fence/ContinuousUpdates support, which is
  why Naru's benchmark gates should separate server wait, payload read, local
  decode, and renderer-upload pressure before promoting an app profile:
  https://sources.debian.org/src/tigervnc/1.7.0%2Bdfsg-7%2Bdeb9u1/common/rfb/VNCSConnectionST.cxx/#L1850

## Implementation

- Bumped `VNCLiveBenchmark` report schema to v62.
- Added fixed issue codes:
  - `first-frame-payload-read-warning`
  - `first-frame-payload-read-failed`
- Added poor-network target thresholds for first-frame payload-read milliseconds
  and payload-read share permille.
- Profile gates now combine first-frame receive timing with request-region
  area and sustained practical assessments. If startup payload pressure fails,
  the gate's primary issue becomes `first-frame-payload-read-failed`, primary
  constraint becomes `receivePath`, and the next probe becomes
  `compareEncodingProfileGate`.
- Safety posture is unchanged: reports emit fixed labels plus aggregate
  milliseconds and permille shares only. No dimensions, coordinates, byte
  counts, pixels, payloads, host identity, command text, draft text, marked
  text, or IME state are emitted.

## Live App Low-Traffic Gate

Command shape:

```sh
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
  --ask-password \
  --json
```

Environment shape:

- Local VNC target through redacted configuration.
- External command stimulus at the preset 12 Hz cadence.
- Constrained-cellular conditioning.
- App low-traffic profile only: `zrle-compression-0-rgb565`.

Result:

- `schemaVersion`: 62
- `streamShapeOptimizationDecision.verdict`: `fail`
- `primaryIssueCode`: `first-frame-payload-read-failed`
- `primaryConstraint`: `receivePath`
- `recommendedNextProbe`: `compareEncodingProfileGate`
- First frame: about 16.0 s total
- First-frame request area: 192 permille
- First-frame receive timing: about 15.1 s network read, 0.94 s first-byte wait,
  14.2 s payload read, 0.88 s client processing
- First-frame payload-read share: 938 permille of network-read time, not total
  startup time
- Sustained samples: 4/4 content responses
- Sustained content FPS: about 2.43
- Sustained average / p95 update: about 411 / 629 ms
- Sustained renderer full-upload pressure: 0 permille
- Sustained dominant subphase: first-byte wait

## Interpretation

- View-aware request regions are still directionally correct for traffic: the
  first-frame request area stayed at 192 permille and steady requests at 364
  permille.
- This live run shows that request-area reduction alone is not enough. The
  startup payload remains too expensive for the poor-network target, so the
  next code unit should compare startup encoding/pixel-format candidates or
  stage first-useful-paint into an even smaller initial region before deciding
  whether to tune sustained request cadence.
- Sustained renderer upload pressure was clean in this run, so the earlier
  renderer-primary classification would have pointed the next PR in the wrong
  direction. v62 makes the traffic bottleneck explicit.

## Verification

```sh
swift test --filter BenchmarkStreamShapeSummaryTests
```

Result: passed, 65 tests, 0 failures.
