# Sustained iPhone VNC Performance Plan

Date: 2026-06-06

## Goal

Naru Remote should feel usable for sustained iPhone sessions: UI work must not
block on network I/O, zoom/pan/trackpad movement must stay local and continuous,
the VNC stream must survive poor links with less traffic pressure, and decode /
render work must avoid unnecessary CPU, GPU, and thermal load.

This note expands the prior VNC stream research into an implementation plan
grounded in protocol and platform behavior, then records the first product
change made from that plan.

## Source Findings

- RFC 6143 makes RFB framebuffer updates request-driven: the client asks for a
  framebuffer update, can mark requests incremental, and includes an interest
  rectangle. That means Naru can reduce traffic by controlling requested region,
  cadence, pixel format, and encoding preference rather than treating VNC as a
  fixed full-screen video feed.
  Source: https://www.rfc-editor.org/rfc/rfc6143
- The community RFB protocol extension record documents pseudo-encodings such
  as cursor and continuous updates. These are useful but optional; the app must
  keep a compatible request/response fallback and prove server behavior with
  live gates before making them default.
  Source: https://github.com/rfbproto/rfbproto
- Apple responsiveness guidance keeps UI smooth by moving blocking work away
  from the main thread and reducing hangs during interaction. For Naru this
  means socket writes, RFB reads, decode, preview save, and benchmark collection
  cannot sit on the MainActor hot path.
  Source: https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- UIKit's scroll/zoom interaction model treats panning and zooming as local
  view transforms. Naru should follow that shape: pinch, pan, and zoomed
  trackpad cursor-follow must redraw the already-decoded texture immediately,
  while network frames arrive asynchronously behind it.
  Source: https://developer.apple.com/documentation/uikit/uiscrollview
- Apple's Metal best-practice guidance emphasizes avoiding CPU/GPU
  synchronization stalls and keeping data movement efficient. For Naru, dirty
  rectangle upload, texture reuse, upload gates, and avoiding full texture
  replacement during gestures are the relevant levers.
  Source:
  https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/
- VideoToolbox is the right Apple framework for hardware video compression and
  decompression, but it does not accelerate raw VNC rectangles by itself. It
  belongs to future PiP/helper-transcoded video work, not to the pure RFB
  decoder path unless Naru introduces a helper protocol that emits H.264/HEVC
  frames.
  Source: https://developer.apple.com/documentation/videotoolbox
- TurboVNC's H.264 analysis reinforces a useful caution: full-frame video
  compression can help some remote display workloads, but small 2D update
  streams need coalescing, caps, and careful latency tradeoffs. Naru should not
  blindly turn VNC into video without a helper-mode spec and benchmark proof.
  Source: https://turbovnc.org/About/H264

## Current Product Gap

Recent benchmark artifacts show that Naru already moved several important
pieces into place:

- Input writes are off MainActor and ordered through one outbound queue.
- Incremental low-traffic app streams can request viewport-aware regions.
- RGB565/ZRLE low-traffic mode exists as an opt-in profile.
- Poor-network gates now separate request area, first-byte wait, payload read,
  renderer upload, and startup timing.

The active blocker is narrower: the app low-traffic live gate still failed
because first-frame payload read dominated startup under constrained-cellular
conditioning, even though sustained renderer upload pressure was clean. The
next improvement should therefore reduce first-useful-paint traffic before
changing production defaults or chasing renderer work.

## Product Strategy

1. Keep UI non-blocking.
   - All socket writes and frame reads stay off MainActor.
   - SwiftUI publication during gestures is coalesced; Metal/UIView applies hot
     local transforms directly.
   - Diagnostics collect fixed coarse labels and aggregate timings only.

2. Make zoom, pan, and trackpad local-first.
   - Pinch and pan update local transform immediately.
   - Trackpad mode displays the server cursor shape when the RFB cursor
     pseudo-encoding is available; fallback cursor remains a local overlay.
   - When zoomed, cursor-follow auto-pan is local; VNC pointer movement and
     viewport panning are decoupled from frame arrival.

3. Reduce traffic with request control before protocol risk.
   - Standard profile remains full-frame compatible.
   - Opt-in low-traffic profile uses RGB565/ZRLE and viewport request regions.
   - First-frame visible-focus requests are allowed only behind the same
     low-traffic gate, with full-frame fallback when no viewport information is
     available or power-saver/low-power override is active.
   - ContinuousUpdates stays opportunistic until live gates prove it.

4. Treat video encode/decode as a separate helper track.
   - Pure VNC optimization focuses on rectangle decode, dirty uploads, and
     request cadence.
   - VideoToolbox becomes relevant for PiP watch output and a future helper
     transport that intentionally transcodes the host display.

## Detailed Plan

Phase A: first-useful-paint traffic

- Use the session viewport size before the first frame exists.
- After RFB handshake, combine that viewport size with `ServerInit`
  framebuffer dimensions to derive a crop-fill visible-focus request region.
- Apply it only when `streamEncodingMode == zrle-compression-0-rgb565` and
  power-saver / system low-power mode are not active.
- Keep standard profile and incompatible/stale viewport cases on full-frame
  first requests.
- Benchmark with `sustained-v2-constrained-cellular-app-low-traffic`.

Phase B: interaction smoothness

- Keep incoming frame publication deferred or capped while viewport gestures
  are active.
- Add a physical-iPhone diagnostic pass that records fixed pass/fail labels for
  pinch continuity, pan continuity, zoomed trackpad cursor-follow, and Compose
  commit reliability.
- Investigate any residual stepped motion as local transform scheduling first,
  then renderer upload, then network cadence.

Phase C: sustained stream adaptation

- Promote only gates that pass both `iphone-sustained-usability-v2` and
  `iphone-poor-network-traffic-v1`.
- Use traffic pressure to choose between smaller request regions, encoding /
  pixel-format comparison, and cadence tuning.
- Treat first-byte wait as server/update-wait behavior and payload read as
  encoding/traffic pressure.

Phase D: render/decode efficiency

- Preserve dirty rectangle metadata through app model and Metal upload.
- Avoid full texture upload when damage is small or framebuffer is unchanged.
- Keep texture allocation stable and measure upload timing with aggregate
  buckets.
- Use VideoToolbox only for PiP/helper video paths after a separate spec.

## This PR's First Implementation Unit

The first implementation unit applies Phase A in the app:

- `SessionViewportView` now reports the viewport container size to the app
  model even before framebuffer pixels exist.
- `NaruRemoteAppModel` uses that size plus RFB `ServerInit` dimensions to build
  an opt-in visible-focus first-frame request region for the
  `zrle-compression-0-rgb565` low-traffic profile.
- If a live viewport transform already exists and matches the server
  dimensions, the model uses it; otherwise it derives a crop-fill focus region
  from the last viewport size.
- If the profile is standard, power-saver is active, low-power mode is active,
  no safe viewport size exists, or dimensions are invalid, the first request
  remains full-frame.

## Verification

Targeted app-model tests passed:

```sh
swift test \
  --filter NaruRemoteAppModelTests/testModelKeepsFullInitialStreamRequestInStandardProfile \
  --filter NaruRemoteAppModelTests/testModelRequestsVisibleViewportRegionForLowTrafficInitialStreamFrame \
  --filter NaruRemoteAppModelTests/testModelUsesViewportSizeForLowTrafficInitialStreamFrameWithoutPriorFramebuffer \
  --filter NaruRemoteAppModelTests/testModelKeepsFullLowTrafficInitialRequestWhenViewportDoesNotMatchServer \
  --filter NaruRemoteAppModelTests/testModelRequestsVisibleViewportRegionForLowTrafficIncrementalStreamFrames
```

Result: passed, 5 tests, 0 failures.

Full package verification also passed:

```sh
swift test
```

Result: passed, 964 tests executed, 10 skipped, 0 failures.

After the live benchmark environment was configured, the app low-traffic
poor-network gate also ran:

```sh
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
  --json
```

Result: the gate failed with fixed primary issue
`first-frame-payload-read-failed`. The first-frame request area stayed low at
192 permille, but payload read still took about 14.1 s of the 15.9 s first
frame. See
`artifacts/benchmarks/2026-06-06-app-low-traffic-visible-focus-live-gate-summary.md`.

## Privacy Boundary

This plan and implementation do not log, persist, or export framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, raw timings,
payloads, host identity, command text, draft text, marked text, or IME state.
The viewport size and derived request region are memory-only control inputs for
the RFB request path.
