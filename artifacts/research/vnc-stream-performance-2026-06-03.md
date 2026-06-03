# VNC Stream Performance Research

Date: 2026-06-03 KST

Sources:

- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC `vncviewer` options: https://tigervnc.org/doc/vncviewer.html
- TightVNC change notes: https://www.tightvnc.com/whatsnew.php
- TurboVNC H.264 study: https://turbovnc.org/About/H264

Findings:

- RFB is framebuffer/rectangle based. RFC 6143 describes updates as
  demand-driven: servers send an update only after an explicit client
  request. That makes client request cadence the basic flow-control
  primitive.
- RFC 6143 says servers should only use Raw unless the client asks for
  another encoding. Efficient streaming therefore starts with a correct
  `SetEncodings` list and a Raw fallback.
- TigerVNC exposes automatic encoding/pixel-format selection plus
  quality/compression controls and reduced-color modes for slow links.
  Naru should eventually make the same decisions automatically from safe
  coarse performance buckets rather than a public settings maze.
- TightVNC notes that cursor-shape pseudo-encodings let the viewer handle
  mouse movement locally, avoiding framebuffer updates for pointer motion.
  Naru already decodes server cursor shape, but physical-device validation
  should verify that trackpad mode is seeing the real cursor path.
- Tight/TurboVNC research points toward bounded compression levels,
  larger/coalesced update regions, reduced copies, and frame-rate
  governors as practical performance levers. TurboVNC's H.264 study also
  warns that full-frame video-style processing is a poor fit for small 2D
  updates unless updates are coalesced/capped.

Near-term strategy:

- Restore client-side backpressure with an active frame cadence cap.
- Measure live update shape: delivered FPS, empty/content ratio, dirty
  rect count/area bucket, full-upload fallback rate, and coarse thermal
  state on device.
- Keep dirty-rectangle metadata alive across the app/model/render
  boundary; full Metal uploads are much more expensive than small
  dirty-rect uploads in the synthetic benchmark.
- Treat ContinuousUpdates as opportunistic until live macOS compatibility
  is proven.
- Defer risky encoding-profile changes until live benchmarks cover more
  samples and physical iPhone behavior.
