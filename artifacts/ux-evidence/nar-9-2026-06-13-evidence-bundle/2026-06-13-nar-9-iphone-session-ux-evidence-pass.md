# NAR-9 iPhone-First Session UX Evidence Pass

Date: 2026-06-13 KST
Agent: Naru UX Researcher
Scope: active session controls, Compose dock behavior, zoom/pan evidence, trackpad cursor affordance, keyboard-up layout, iPad graceful scaling.

## Evidence Reviewed

- Existing screenshot audit PNGs in `artifacts/screenshots/ux-audit/`.
- Focused visual review:
  - `16-session-active-widescreen-iphone-dark.png`
  - `16-session-active-widescreen-iphone-light.png`
  - `17-session-active-keyboard-iphone-dark.png`
  - `17-session-active-keyboard-iphone-light.png`
  - `18-session-active-trackpad-cursor-iphone-dark.png`
  - `18-session-active-trackpad-cursor-iphone-light.png`
  - `07-compose-text-iphone-dark.png`
  - `13-pip-disabled-iphone-dark.png`
  - `07-compose-text-ipad-portrait-dark.png`
  - `07-compose-text-ipad-landscape-dark.png`
- Screenshot dimensions sampled with `sips`:
  - iPhone active session captures: `1206x2622`.
  - iPad portrait compose capture: `1206x2622`.
  - iPad landscape compose capture: `2622x1206`.
- Simulator gate attempted:

```sh
NARU_SIMULATOR_PHONE_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
NARU_SIMULATOR_PAD_DESTINATION='platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' \
NARU_SIMULATOR_GATE_INCLUDE_IPAD=1 \
NARU_SIMULATOR_GATE_BENCHMARK_ITERATIONS=1 \
NARU_SIMULATOR_GATE_BENCHMARK_SAMPLES=120 \
scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate
```

Result:

- Overall: `failed`.
- `swift-focused-unit-slice`: `passed`.
- `iphone-viewport-hotpath-benchmark`: `passed`.
- `iphone-compose-storm-ui-tests`: `failed`; the log shows several Korean/CJK compose stress tests passing, then the test runner restarted after unexpected exit/test timeout during the full interaction storm path.
- `ipad-compose-storm-ui-tests`: interrupted when the long-running gate was stopped; no reliable iPad compose verdict from this run.

Global memory note: `/Users/hckim/.codex/memories/claude-global.md` and `/Users/hckim/.codex/memories/claude-user/MEMORY.md` were absent in this workspace, so no durable user-memory instructions beyond `AGENTS.md` were available.

## Findings

### High - Visual Stream / Active Session Content

Affected viewport: iPhone portrait active session, dark and light.

Expected: Active-session screenshot evidence should show a representative readable remote framebuffer, ideally text-heavy terminal or desktop content, so UX review can judge crop-to-fill, text legibility, light/dark clarity, and screen priority.

Observed: The active-session screenshots reserve most of the phone for the remote viewport, but the framebuffer area is a flat dark field with no readable remote content. This proves layout dominance but does not prove a readable session.

Evidence:

- `artifacts/screenshots/ux-audit/16-session-active-widescreen-iphone-dark.png`
- `artifacts/screenshots/ux-audit/16-session-active-widescreen-iphone-light.png`
- `artifacts/screenshots/ux-audit/17-session-active-keyboard-iphone-dark.png`
- `artifacts/screenshots/ux-audit/18-session-active-trackpad-cursor-iphone-dark.png`

Product quality axis: Visual stream, Device UX, light/dark visual clarity.

### Medium - Keyboard-Up Session Layout

Affected viewport: iPhone portrait active session with Korean software keyboard.

Expected: The soft keyboard should not collapse the remote screen into a sliver; Compose controls should remain reachable without hiding the remote session.

Observed: The keyboard-up screenshot keeps a large remote viewport above the dock and keyboard. The Compose field remains focused, the dock controls remain reachable, and the remote viewport is not crushed. This is a positive layout signal, with the visual-content caveat above.

Evidence:

- `artifacts/screenshots/ux-audit/17-session-active-keyboard-iphone-dark.png`
- `artifacts/screenshots/ux-audit/17-session-active-keyboard-iphone-light.png`

Product quality axis: Device UX, Input lane.

### High - Compose Storm Simulator Gate Is Not Green

Affected device class: iPhone simulator first; iPad simulator inconclusive in this run.

Expected: `simulator-input-viewport-gate` should pass the Korean/CJK compose freeze regression and viewport hot-path checks before any UX claim says keyboard, frame pressure, and trackpad pressure coexist smoothly.

Observed: The unit slice and pure viewport hot-path benchmark passed. The iPhone compose storm UI-test step failed after several individual tests passed, including a runner restart during the full interaction storm path. The iPad compose step was interrupted when the long-running gate was stopped, so it should not be treated as a product failure yet.

Evidence:

- Command and structured result recorded above.
- Xcode result bundle referenced by local xcodebuild output:
  - `/Users/hckim/Library/Developer/Xcode/DerivedData/NaruRemote-fgftwgglnlcdcigtdcnegzionaiw/Logs/Test/Test-NaruRemote-2026.06.13_15-30-30-+0900.xcresult`

Product quality axis: Input lane, Viewport interaction, Device UX.

### Medium - Trackpad Cursor Affordance Static Pass, Gesture Feel Gap

Affected viewport: iPhone portrait active session trackpad mode.

Expected: Trackpad mode should show the real remote cursor when available, and zoomed cursor-follow pan should feel immediate rather than lagging behind the finger.

Observed: Static screenshot evidence shows a server-shaped cursor with strong contrast in dark and light screenshot variants. It does not prove movement latency, cursor-follow panning, or Photos-like zoom/pan feel.

Evidence:

- `artifacts/screenshots/ux-audit/18-session-active-trackpad-cursor-iphone-dark.png`
- `artifacts/screenshots/ux-audit/18-session-active-trackpad-cursor-iphone-light.png`
- `iphone-viewport-hotpath-benchmark`: `passed` in the attempted simulator gate.

Product quality axis: Viewport interaction, Trackpad mode.

### High - iPad Screenshot Evidence Is Not Reliable Enough

Affected device class: iPad portrait and iPad landscape screenshot audit.

Expected: iPad graceful-scaling evidence should be captured on the iPad simulator with portrait and landscape images visually oriented for review, with controls and text readable in the saved PNG.

Observed: The sampled iPad portrait compose PNG has the same `1206x2622` pixel dimensions as the iPhone portrait screenshots. The sampled iPad landscape compose PNG has landscape dimensions (`2622x1206`) but visually renders sideways in review. This makes the current iPad screenshot evidence unreliable for a graceful-scaling pass/fail judgment.

Evidence:

- `artifacts/screenshots/ux-audit/07-compose-text-ipad-portrait-dark.png`
- `artifacts/screenshots/ux-audit/07-compose-text-ipad-landscape-dark.png`

Product quality axis: iPad graceful scaling, Device UX, screenshot audit reliability.

### Low - PiP Watch Evidence Gap

Affected viewport: iPhone PiP/watch-only mode.

Expected: PiP Watch should be validated as watch-only and should not imply input delivery while in PiP.

Observed: Current screenshot evidence covers only the disabled PiP button before a session frame. It does not cover active-session PiP availability, enter/exit behavior, or physical iPhone PiP.

Evidence:

- `artifacts/screenshots/ux-audit/13-pip-disabled-iphone-dark.png`

Product quality axis: Device UX, PiP, security/input boundary.

## Follow-Up Tasks Proposed

### 1. Make Active-Session Screenshot Fixtures Readable

Owner specialty: iOS UI / Session Viewer.

Task: Update the active-session UX audit fixture so state 16/17/18 renders representative non-secret remote framebuffer content with text and window structure. Regenerate iPhone light/dark active, keyboard-up, and trackpad screenshots.

Acceptance gate:

- Targeted `UXAuditScreenshotsUITests` state 16/17/18 run on iPhone simulator.
- Screenshot review confirms remote content is readable, true aspect ratio is preserved, and keyboard-up layout still leaves useful screen area.

### 2. Stabilize the Compose Storm Simulator Gate

Owner specialty: Input / UI test infrastructure.

Task: Triage why the iPhone compose storm UI-test runner restarts or times out during full interaction storm. Separate product regressions from runner flake if needed, but keep the gate meaningful.

Acceptance gate:

- `scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate` passes with iPhone coverage.
- iPad compose coverage either passes or is explicitly split into a tracked follow-up with a non-flaky reproduction.

### 3. Repair iPad Screenshot Orientation And Device Coverage

Owner specialty: iOS screenshot QA / UI infrastructure.

Task: Ensure `UXAuditScreenshotsUITests.testIPadStates` produces real iPad portrait and landscape screenshots, visually upright and reviewable, without reusing phone-scale captures.

Acceptance gate:

- iPad portrait and landscape screenshots have expected iPad simulator dimensions and visually upright content.
- At least connection grid, Compose dock, and Direct keyboard states are captured in light and dark.

### 4. Run Physical iPhone Session Feel Pass

Owner specialty: QA / physical-device UX.

Task: Run a privacy-safe physical iPhone manual pass against a non-secret test host or fixture path. Cover active session, keyboard-up Compose, pinch/pan, trackpad cursor drag, and PiP watch-only note.

Acceptance gate:

- Manual-device note records device model, iOS version bucket, test route, pass/fail per axis, and explicit gaps.
- No endpoints, credentials, clipboard payloads, screenshots with secrets, or typed user content are recorded.

## Disposition

NAR-9 evidence pass is complete as a UX research artifact. It should not be read as a Green product claim. Current evidence supports: iPhone active-session viewport priority, keyboard coexistence layout, static trackpad cursor visibility, and pure viewport hot-path benchmark pass. It does not support: readable active-session visual quality, physical iPhone gesture feel, reliable iPad graceful-scaling screenshots, or full simulator compose-storm gate pass.
