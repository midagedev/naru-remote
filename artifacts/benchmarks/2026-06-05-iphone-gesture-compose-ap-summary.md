# iPhone Gesture + Compose Follow-Up

Date: 2026-06-05

Purpose: respond to physical iPhone feedback that zoom/pan still felt choppy
and Compose still felt broken.

Changes:

- Lowered zoomed trackpad follow-pan coupling from `0.25` to `0.14`. The
  visible cursor remains finger-paced, but the viewport no longer drags as much
  during central cursor motion away from an edge.
- Reduced trackpad remote-pointer coalescing from `16 ms` to `8 ms`, and the
  published cursor mirror from `32 ms` to `16 ms`, so the actual remote cursor
  has a shorter delay behind local finger motion.
- Kept the long iOS IME stabilization window only when marked text was active
  before Compose Send. Plain/fully committed text now uses a fast stabilization
  pass instead of waiting through the full delayed-IME window.
- Compacted blocked Korean/CJK/emoji Compose failures into
  `Multilingual Compose needs helper or UTF-8 clipboard` for the dock, while
  diagnostics still retain the structured route details from schema v23.

Focused verification:

- `swift test --filter PointerGestureResolverTests`
- `swift test --filter TrackpadModeModelTests`
- `swift test --filter RemoteInputDockSyncPolicyTests --filter NaruRemoteAppSnapshotTests`
- `swift test`
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
- `NARU_RUN_SIM_BENCHMARKS=1 swift test --filter SyntheticFramePipelineBenchmarkTests`

Benchmark snapshot:

- Full framebuffer allocation/upload: monotonic average ~2.4 ms.
- Steady-state full upload: monotonic average ~0.44 ms.
- Small dirty-rect upload: monotonic average ~0.017 ms.
- Same-frame upload gate skip: effectively zero monotonic time at this scale.

Notes:

- This does not relax the strict no-helper policy for unconfirmed UTF-8 VNC
  clipboard sessions. If macOS Screen Sharing does not confirm Extended
  Clipboard UTF-8 and no helper bridge is reachable, multilingual Compose must
  fail rather than pretending a lossy legacy clipboard paste succeeded.
