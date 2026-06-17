# NAR-5 VNC Receive-Path And Traffic Triage - 2026-06-13

## Scope

Close the NAR-5 triage question using the current redacted VNC and
helper-video benchmark evidence:

- Can a VNC profile or request cadence candidate pass the
  `iphone-remote-desktop-10fps-v1` gate?
- Does weak-network traffic tuning justify a production VNC visual default?
- Is the remaining blocker server cadence, transport mode, local decode,
  renderer upload, helper permission, or physical-device setup?

## Evidence Reviewed

- `artifacts/benchmarks/2026-06-07-remote-desktop-10fps-readiness-summary.md`
- `artifacts/benchmarks/2026-06-07-remote-desktop-10fps-transport-cadence-drilldown-summary.md`
- `artifacts/benchmarks/2026-06-09-request-pipeline-diagnosis-summary.md`
- `artifacts/benchmarks/2026-06-09-request-pipeline-stability-summary.md`
- `artifacts/benchmarks/2026-06-09-helper-video-live-gate-granted-summary.md`
- `artifacts/benchmarks/2026-06-13-continuous-updates-unsupported-diagnosis-summary.md`
- `artifacts/benchmarks/2026-06-13-viewport-interaction-trace-summary.md`
- `PRODUCT_QUALITY_TARGETS.md`
- `specs/004-rfb-encodings/spec.md`
- `specs/007-host-helper-video-stream/spec.md`

## Triage Result

VNC does not have a current 10fps visual-primary candidate.

The latest fixed-shape evidence points to receive-path/server cadence as the
primary VNC blocker:

- The 10fps readiness dashboard records VNC at about `1.99` content FPS with
  `receivePath` as the primary constraint and first-byte wait around the
  same order as the p95 update tail.
- The viewport-interaction trace still fails on `first-byte-wait-failed` with
  both baseline and app-pacing candidates, so local viewport pacing is not the
  limiting factor for the visual stream.
- The transport cadence drilldown shows request/response can deliver samples
  but still fails the 10fps target, while ContinuousUpdates fails before usable
  samples on the current Mac Screen Sharing target.
- The ContinuousUpdates follow-up maps the unconfirmed extension to
  `treatContinuousUpdatesAsUnsupportedForCurrentServer`, so repeatedly probing
  that extension is not the next useful path for this target class.
- The request-pipeline diagnosis briefly showed depth `3` improving short-run
  content FPS, but the longer stability gate marked it `notHelpful`: depth `3`
  stayed near `1.83` content FPS, left first-byte wait unchanged, and worsened
  p95 update latency.

Weak-network traffic work produced useful opt-in benchmark candidates, but not
a production visual-primary default. The `0.25` visible-glance startup shape
and app low-traffic RGB565 profiles reduce request-area pressure and preserve
privacy-safe traffic proxies, but the sustained path still fails the 10fps
product target from first-byte/update wait. These candidates should remain
benchmark or opt-in experiments until a physical iPhone gate confirms readable
first useful paint, hand feel, thermal comfort, and Compose reliability.

## Product Decision

Classify VNC as the control/input/fallback visual baseline for now. Do not
promote a new VNC visual profile, request pipeline depth, ContinuousUpdates
transport, startup-glance scale, or request-region default from the current
evidence.

Helper-video is the smooth visual-primary candidate. The latest granted helper
live gate shows true ScreenCaptureKit helper-video and app bootstrap passing
through helper TCP framing and the H.264 sample-buffer factory. The remaining
promotion blocker is physical iPhone signing/provisioning and then the physical
helper-video hand-feel/thermal gate, not macOS helper permission.

## Next Actions

1. Keep production VNC request pipeline depth at `1`.
2. Treat ContinuousUpdates as unsupported for the current Mac Screen Sharing
   target unless a future server confirms the extension.
3. Keep app low-traffic VNC profiles and startup-glance scale as explicit
   opt-in or benchmark-only candidates.
4. Run the physical iPhone helper-video gate after Xcode account/provisioning
   setup is available.
5. Revisit VNC visual promotion only if a future receive-path/server-cadence
   change reaches the 10fps gate without worsening traffic proxies.

## Evidence Status

This triage uses existing benchmark artifacts and targeted self-tests rather
than a fresh live VNC run. No new live credentials were required. The evidence
is sufficient for the product decision branch in NAR-5, but it is not a Green
smoothness claim for either VNC or helper-video on a physical iPhone.

## Safety

This artifact contains only fixed labels and aggregate benchmark values copied
from redacted summaries. It does not include hostnames, IP addresses,
credentials, ports, helper paths, raw stdout/stderr, raw TCP/RFB errors,
framebuffer pixels, screenshots, dimensions, coordinates, byte counts, command
text, draft text, marked text, IME state, keysyms, helper endpoints, pairing
material, or physical device identifiers.
