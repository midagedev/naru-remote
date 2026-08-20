# Feature Specification: Network-Constrained Stream Caps (Low Data Mode)

**Feature Branch**: `020-network-constrained-stream-caps`
**Created**: 2026-08-20
**Status**: Implemented 2026-08-20 (grok round + lead review; `swift test`
1668/0 failures, iPhone simulator build green). One spec correction during
implementation: `NetworkPathConditionsMonitor` is public, not internal —
the public model initializer's default expression cannot reference an
internal symbol. Founder device Low Data Mode pass residual.
**Product**: Naru Remote
**Input**: Founder direction 2026-08-20 "ㅇ진행해줘" continuing the
performance-lever queue (NEXT_STEPS 1f lever ②: "helper adaptive bitrate +
cellular caps via NWPath.isExpensive/Low Power Mode",
`artifacts/research/2026-08-20-streaming-performance-levers.md`).

## Ground Truth (code-read 2026-08-20)

- The app has **zero network-path awareness**: no `NWPathMonitor`, no
  `isExpensive`/`isConstrained` reads anywhere in production code.
- The helper video lane picks its stream parameters once, at start, via
  `HelperVideoStartRequestPolicy`
  (`NaruRemote/App/AppShell/HelperVideoStartRequestPolicy.swift`):
  quality hardcoded `.readability`; frame rate drops to `upTo15` only for
  `streamPowerMode == .powerSaver`, system Low Power Mode, or thermal
  pressure. The helper maps buckets to bitrate
  (`NaruHelperVideoRateControlPolicy`: readability@15 = 1.2 Mbps,
  readability@30 = 1.8 Mbps).
- The VNC lane's sustained encoding preference
  (`NaruRemoteAppModel.configuredSustainedEncodingPreference`, around line
  5252) returns `.powerSaverSustained` for `powerSaver` mode or Low Power
  Mode, and `initialStreamPixelFormatPreference` (around line 5280)
  disables the RGB565 override under the same two signals — a deliberate
  pairing.
- Existing model tests already assert
  `connector.renegotiatedPreferences == [.powerSaverSustained]` through the
  `lowPowerModeProvider` seam (`NaruRemoteAppModelTests` around lines
  2810/3385) — the exact analog seam this feature extends.

## Why

iOS users tell the system when data is precious: **Low Data Mode**
(`NWPath.isConstrained`). Naru currently ignores it — a constrained hotspot
session gets the same 1.8 Mbps helper stream and full VNC profile as home
Wi-Fi. Respecting the signal is cheap (both lanes already have a "saver"
configuration; only the trigger is missing) and constitution-aligned.

Deliberate non-goals, both constitution-driven (§VI phone-first: *cellular
is the baseline scenario, not an exception*):

- `isExpensive` (cellular/hotspot as such) MUST NOT degrade anything by
  itself. The founder's core workflow is sustained AI-CLI work over
  cellular; auto-degrading on cellular would break the product's promise.
  The bit is captured in the conditions value for future diagnostics only.
- No Wi-Fi quality upgrade (readability → balanced) in this round — that is
  a product-feel tradeoff for the founder to judge on device, not a cap.
- No mid-stream helper renegotiation: a path flip (Wi-Fi → cellular) tears
  the TCP connections, and reconnect re-evaluates every policy naturally.
  Live helper bitrate *changes* need new wire vocabulary (schema v2) — out
  of scope.

## Requirements

- **FR-001 (conditions value + provider)**: A pure Core value
  `NetworkPathConditions` (create file `NetworkPathConditions.swift` inside
  `NaruRemote/Sources/NaruRemoteCore/SessionViewer/`) with `isExpensive`
  and `isConstrained` Bools and a `.unknown` default of both-false (errs
  toward NOT capping). `NaruRemoteAppModel` gains a
  `networkPathConditionsProvider: @Sendable () -> NetworkPathConditions`
  init parameter alongside `lowPowerModeProvider`, defaulting to the live
  monitor below; tests inject fakes.
- **FR-002 (live monitor)**: An `NWPathMonitor`-backed
  `NetworkPathConditionsMonitor` (create file
  `NetworkPathConditionsMonitor.swift` inside
  `NaruRemote/App/AppShell/`, `canImport(Network)`-guarded) — a
  lock-guarded snapshot (`current`) updated by the monitor's path handler
  on a utility queue, started once lazily (shared instance). Before the
  first path update it reports `.unknown`. No path details beyond the two
  Bools are stored, logged, or exported (constitution §IV — interface
  names, SSIDs, and endpoint data never cross into app state).
- **FR-003 (helper lane cap)**: `HelperVideoStartRequestPolicy` gains
  `isNetworkConstrained: Bool`. When true, `maxFrameRateBucket` is
  `upTo15` regardless of power/thermal state (quality stays `.readability`,
  today's only production value). With all other inputs nominal and
  constrained false, behavior is byte-identical to today.
- **FR-004 (VNC lane cap)**: `isConstrained` joins `powerSaver` mode and
  Low Power Mode in BOTH members of the existing pairing:
  `configuredSustainedEncodingPreference()` returns `.powerSaverSustained`,
  and `initialStreamPixelFormatPreference()` returns nil. Constrained
  reuses the existing saver configuration exactly — no novel
  encoding/pixel-format combination is introduced.
- **FR-005 (evaluation points)**: Conditions are read where the other
  providers are read: helper `helperVideoStartRequestBody()` (model, around
  line 2109) and the VNC stream-start / sustained-renegotiation paths that
  already consult `lowPowerModeProvider()`. No new periodic polling loop;
  a mid-session Low Data Mode toggle takes effect from the next stream
  (re)start, mirroring how Low Power Mode behaves today.
- **FR-006 (privacy)**: The two Bools MAY appear in internal state; no new
  diagnostic-export fields, no logging of network interface details.

## Verification Matrix

| Layer | What it proves |
| --- | --- |
| `swift test` — `HelperVideoStartRequestPolicy` tests (extend the existing block in `NaruRemoteAppModelTests`) | constrained → upTo15 under otherwise-nominal inputs (**FAIL-first**: unmodified policy returns upTo30); constrained false → today's table unchanged |
| `swift test` — model tests through `networkPathConditionsProvider` | constrained provider → sustained renegotiation lands `.powerSaverSustained` (**FAIL-first** via the existing `renegotiatedPreferences` seam); expensive-only provider → preferences identical to the nominal run (the §VI guard) |
| `swift test` — monitor unit test | handler-driven snapshot: before first update `.unknown`; after a synthesized update the two Bools reflect it (drive the handler directly; do not depend on live network state in CI) |
| iPhone simulator build | app target builds with the new AppShell file (`project.yml` untouched; regenerate with `xcodegen generate --spec project.yml`) |
| Founder device pass (residual) | Low Data Mode toggled on a real phone: helper stream visibly drops to 15 fps and VNC falls to the saver profile on next connect |

## Residual Risk

- `NWPathMonitor` semantics on simulator differ from device (often reports
  unconstrained Wi-Fi); the device pass covers the real signal.
- A user in Low Data Mode who *wants* full quality has no override in v1;
  if the founder's pass says the cap feels wrong, the escape hatch is a
  settings toggle (own spec).
- Mid-stream toggles apply on next (re)connect only — documented behavior,
  same as Low Power Mode today.
