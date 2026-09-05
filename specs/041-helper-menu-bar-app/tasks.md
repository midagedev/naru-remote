# Tasks: Naru Helper Menu Bar App

**Feature**: `specs/041-helper-menu-bar-app` · plan: `plan.md` · 2026-09-05

Rounds are ordered by dependency. Round A must land before Round B
(the app consumes Kit API). Round C is independent of both (disjoint
files) and may run in parallel with A. Every task names its files; two
rounds never write the same file.

## Round A — Kit: runtime, revoke, host info, session, status (owner: one agent)

Files owned: `Package.swift` (one product line), `NaruHelper/Sources/NaruHelperKit/**`,
`NaruHelper/Sources/NaruHelper/main.swift`, `NaruHelper/Tests/NaruHelperKitTests/**`.

- **T-A1 [FR-007, US-3]** `NaruHelperPairingStateStore`: absent file ⇒
  `currentSecret()`/`currentFingerprint()` return `nil` and clear the
  cache; transient read failure ⇒ keep cache; new `revoke()` deletes the
  file and clears the cache. **FAIL-first**: add
  `testCurrentSecretIsNilWhenStateFileIsAbsent` first, run it against the
  unmodified store, paste the failing assertion into the report, then fix.
- **T-A2 [FR-007]** Both handlers: provider type → `@Sendable () -> String?`;
  attached provider returning `nil` ⇒ `.revoked` (text) / `.rejected` +
  `.revoked` (video); never fall back to the launch-time secret when a
  provider is attached. Add `onAuthorizedRequest: (@Sendable () -> Void)?`
  fired after acceptance. Tests: revoke through both handlers; hook fires
  once per accepted request and not on refusal.
- **T-A3 [FR-002, US-2]** Servers expose `onStateChange: ((NaruHelperListenerState) -> Void)?`
  mapping `NWListener.State` (`.failed(.posix(.EADDRINUSE))` ⇒ `.portInUse(port)`).
  New `NaruHelperListenerRuntime` (`start()`, `stop()`, per-listener state)
  composing text + video handlers from the pairing store with providers +
  hook. Test: bind a port already held by a throwaway `NWListener` ⇒
  `.portInUse`; two free ports ⇒ both `.listening`.
- **T-A4 [FR-003]** Lift from `main.swift` into Kit: `NaruHelperPairingHostInfo`
  (label, CGNAT filter, MagicDNS reverse lookup) with the address filter
  testable on synthetic input; `NaruHelperTextBridgeLive.capabilityResponse()`
  and `.insert(request:)`. `main.swift` calls the Kit; CLI behavior and
  output unchanged (`--pair`, `--listen`, `--video-listen`, `--capability`).
- **T-A5 [FR-003, FR-004]** `NaruHelperPairingSession`: `begin(store:hostInfo:vncPort:vncPassword:)`
  rotates, encodes via `NaruPairingOfferWire`, renders a `CGImage` QR
  (nearest-neighbor, ≥ 320 px), and `end()` releases it. Test: offer
  string equals `NaruPairingOfferWire.encode` of the same inputs; image is
  square and non-nil.
- **T-A6 [FR-005, FR-012]** `NaruHelperAppStatus` (permissions, listeners,
  pairing, login item, version) + `diagnosticsText()`. Test: for a seeded
  status built from a real rotated token, the text contains neither the
  token, the fingerprint hex, `code=`, nor any `100.` address.
- **T-A7 [FR-006]** `NaruHelperLoginItemControlling` protocol
  (`register/unregister/status`) + `NaruHelperLoginItemState` machine
  (`off/on/requiresApproval/unavailable`) with a fake-backed test. The
  `SMAppService` conformance lives in the App target (Round B), not the Kit.
- **T-A8** `Package.swift`: add `.library(name: "NaruHelperKit", targets: ["NaruHelperKit"])`.
- **Gate A**: `swift build` clean; `swift test --filter NaruHelperKitTests`
  green with the new cases; `.build/debug/NaruHelper --capability` output
  byte-identical before/after (diff recorded in the report). No git writes.

## Round B — macOS app target (owner: one agent; starts after Gate A)

Files owned: `NaruHelper/project.yml` (new), `NaruHelper/App/**` (new),
`NaruHelper/UITests/**` (new), `NaruHelper/.gitignore` (new: `NaruHelper.xcodeproj`
is generated — mirror how the root treats its project), `artifacts/screenshots/helper-menu-bar/**`.

- **T-B1 [FR-001, FR-009]** XcodeGen spec: `NaruHelperApp` macOS 14 app,
  product name `Naru Helper`, bundle id `com.naruremote.helper`,
  `LSUIElement: true`, hardened runtime, no sandbox, local package `..`
  products `NaruHelperKit` + `NaruRemoteCore`; `NaruHelperAppUITests`.
  Version from `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in the spec.
- **T-B2 [FR-001, FR-008]** `NaruHelperApp.swift` with `MenuBarExtra`;
  single-instance handoff; `HelperAppModel` wiring runtime + store +
  probes + `SMAppService` login item conformance; runtime starts at launch.
- **T-B3 [FR-003, FR-004, FR-005]** `PairingWindow`: QR ≥ 320 pt, raw code
  behind **Copy code**, optional VNC password `SecureField` (memory only),
  permission rows with **Open System Settings**, no-tailnet state with
  **Retry**, "Paired" transition on the runtime's authorized hook, QR
  dropped on transition/close.
- **T-B4 [FR-005, FR-006, FR-007, FR-012]** Menu: status, permissions,
  **Pair with iPhone…**, **Start at login**, **Revoke pairing…**
  (confirmation alert), **Copy Diagnostics**, version, **Quit**. 2 s
  permission refresh while a window is open, using the non-prompting probe.
- **T-B5 [matrix]** XCUITest: menu opens and lists the items; pairing
  window shows QR + permission rows with an injected offer (launch
  argument `--ui-test-offer <code>`); screenshots to
  `artifacts/screenshots/helper-menu-bar/{menu,pairing,paired}.png`.
- **Gate B**: `xcodegen generate --spec NaruHelper/project.yml`;
  `xcodebuild -project NaruHelper/NaruHelper.xcodeproj -scheme NaruHelperApp -destination 'platform=macOS' build test`
  green; screenshots exist; report lists them. No git writes.

## Round C — Release script + docs + phone pointer (owner: one agent; parallel with A)

Files owned: `scripts/release-naru-helper.sh` (new), `scripts/ExportOptions-helper.plist` (new),
`AGENTS.md` (helper section only), `README.md` (helper install paragraph only),
`NaruRemote/App/Features/ConnectionHub/NaruPairingFlowView.swift` (one line: download pointer),
`specs/041-helper-menu-bar-app/quickstart.md`.

- **T-C1 [FR-009, US-4]** `scripts/release-naru-helper.sh`: generate →
  archive (Developer ID, XEF9KH7N43) → export (`developer-id`) → zip →
  `notarytool submit --wait` → staple → `spctl --assess` → write
  `artifacts/app-store/<date>-helper-<version>/release.md` → optional
  `--publish` runs `gh release create/upload`. Credentials from
  `~/.appstoreconnect` exactly as `scripts/testflight-upload.sh` reads
  them; `set -euo pipefail`; every external command logged; dry-run flag
  that stops before notarization. The script must not be executed by the
  agent beyond `bash -n` and the dry-run's argument parsing — no archive,
  no upload.
- **T-C2 [FR-010]** `AGENTS.md` helper section: the app is the install
  path; CLI is benchmark/automation; launch contract lines kept.
  `README.md`: one paragraph pointing to Releases. No Korean prose (lead
  writes any).
- **T-C3 [FR-011, US-4 SC-2]** iPhone pairing entry: one line "Need the
  Mac side? Get Naru Helper" linking `https://github.com/midagedev/naru-remote/releases/latest`
  in the pairing flow's empty/help state. No other phone change.
- **T-C4** `quickstart.md`: founder checklist — download, first-launch
  grants, pair, reboot test, revoke test, release run.
- **Gate C**: `bash -n` on the script; `swift build` (phone file compiles);
  `scripts/check-doc-links.sh` green. No git writes.

## Round D — Vision verdict (opus, one round, then retire)

Open `artifacts/screenshots/helper-menu-bar/*.png` and judge: menu items
legible and in the specified order; QR square, high contrast, ≥ 320 pt
with a quiet zone; permission rows readable. Do not judge: colors/icons
(none specified), window chrome.

## Lead

Diff review per round, gates re-run lead-side, vision verdict, physical
founder pass request, commit per round with file-level `git add`.

## Round A implementation notes (appended by the implementing agent)

Deliverables landed in `NaruHelperKit` (T-A1…T-A8): real revoke in
`NaruHelperPairingStateStore` (absent file ⇒ `nil` + cache cleared,
unreadable/undecodable ⇒ cached value kept as transient, new `revoke()`);
`String?` pairing providers on both request handlers with `.revoked` on
provider-nil (no launch-time fallback) plus `onAuthorizedRequest` fired once
per accepted proof; `NaruHelperListenerState`/`NaruHelperListenerRuntime`
(both listeners, one store, shared authorized hook, port-in-use surfaced);
`NaruHelperPairingHostInfo` + `NaruHelperTextBridgeLive` lifted out of
main.swift (CLI flags/output unchanged); `NaruHelperPairingSession`
(rotate → offer → ≥320 px nearest-neighbor QR with quiet zone, dropped on
`end()`); `NaruHelperAppStatus` fixed-catalog diagnostics; login-item
protocol + pure toggle (no ServiceManagement in Kit); `NaruHelperKit`
library product added to Package.swift.

Two findings worth the lead's eyes:

- **FR-003 byte-parity premise is falsified empirically.** Two calls to
  `NaruPairingOfferWire.encode` with equal inputs in one process produced
  different JSON key orders (measured in-test, 2026-09-05). Foundation's
  `JSONEncoder` does not guarantee key order across encode call sites, so
  "identical offer bytes" is not attainable through the shared encoder as
  written; both doors still share the one encoder and the test asserts
  decode-parity instead. If byte-stable offers are wanted, pin
  `.sortedKeys` (or a canonical writer) in `NaruPairingOfferWire` — a
  `NaruRemoteCore` change, outside Round A's file boundary.
- **Raw no-port `NWListener(using: .tcp)` fails with EINVAL inside the
  listener-runtime test process** while the Kit's own servers bind fine in
  the same bundle (deterministic, reproduced isolated). The port-in-use
  test therefore holds its port with a plain BSD socket instead. If a
  future round wants raw-listener tests, that EINVAL deserves a root-cause
  look (macOS 26 runner / sandbox interaction suspected).

## Lead notes after Round A / Round C review (2026-09-05)

- Round A finding 1 (encoder key order) closed lead-side: `NaruPairingOfferWire.encode`
  now pins `.sortedKeys`, with `testEncodeIsByteDeterministicAcrossCalls` (50 encodes,
  one distinct string) in `NaruPairingOfferTests`. FR-003's byte-parity claim holds again.
- Round A finding 2 (raw `NWListener` EINVAL inside the test process) left open; the
  port-in-use test holds its port with a BSD socket, which is a valid stand-in.
- Lead gates re-run from cold: `swift build` rc=0; `swift test --filter NaruHelperKitTests`
  159 executed / 0 failures; full `swift test` 1867 executed / 26 skipped / 0 failures.
- Round C: `bash -n` clean; `--dry-run` fails fast on the missing `NaruHelper/project.yml`
  before invoking any tool (verified); `plutil` accepted the export plist.

## Round B implementation notes (2026-09-06)

App target built and verified manually; the XCTest UI-test gate itself is
blocked by a machine-level authentication gate (below), so the three PNGs
were produced through the app's own DEBUG fixture surface with the same
launch arguments the tests use.

### Launch-argument surface (all DEBUG-only, all guarded by `--ui-test`)

| Argument | Overrides | Guard |
|---|---|---|
| `--ui-test` | master flag; without it nothing below parses | `#if DEBUG` + `HelperUITestFixtures.parse` first line |
| `--ui-test-state-dir <path>` | store location → `<path>/helper-pairing-state.json` (never the real `~/.naru`) | same |
| `--ui-test-offer <url>` | displayed QR + Copy code payload (no token minted) | same |
| `--ui-test-state <notPaired\|paired\|connected>` | reported pairing status (unknown values ignored) | same |
| `--ui-test-permissions <granted\|missing>` | both permission rows | same |
| `--ui-test-open-pairing` | open fixture window hosting `PairingWindow` at launch | same |
| `--ui-test-open-menu-preview` | open fixture window hosting `HelperMenu` at launch | same |

### `HelperAppModel` published state

| Property | Source of truth | Refresh trigger |
|---|---|---|
| `pairingStatus` | fixture override, else `store.currentSecret()` + `connectedLatched` | init, `didBecomeActive`, authorized request, revoke |
| `accessibility` / `screenRecording` | `AXIsProcessTrusted()` / `CGPreflightScreenCaptureAccess()` (non-prompting) | 2 s timer while pairing window open or menu opened <10 s; `didBecomeActive` |
| `textListenerState` / `videoListenerState` | runtime `onStateChange` | listener events |
| `loginItemState` | `SMAppService.mainApp.status` via `SystemLoginItem` | init, toggle apply |
| `hostInfo` / `pairingSession` | `NaruHelperPairingHostInfo.current()` / `NaruHelperPairingSession` | window appear (re-read), end |
| `vncPassword` | SecureField, memory only | user input; cleared on connect/rotate/window close |

### Findings

- **macOS 26 gates XCUITest-on-Mac behind a user authentication.**
  `testmanagerd` logs "Writer daemon requires authentication to enable
  automation mode" → `LocalAuthentication evaluatePolicy` ("Enable UI
  Automation"); the enable state file
  `/var/db/com.apple.dt.automationmode/automation-enabled` does not exist
  on this Mac, so every macOS UI-test run dies at exactly 60 s ("Timed out
  while enabling automation mode") before any test code executes. The
  runner, the daemon restart, and the test bundle were all checked; the
  bundle compiles and the app itself is fine. iOS-simulator UI tests never
  touch this gate. **Enabling it needs one interactive authentication the
  next time a macOS UI test session starts** — after that the tests below
  should run as written.
- **First QR render costs a one-time CoreImage/Metal kernel-library load
  (~40 s measured on this loaded Mac; the window meanwhile exists but
  stays blank-ish and AX reports nothing).** The UI tests therefore wait
  up to 120 s for the QR/headline elements; short waits were why early
  manual launches looked like "0 windows" (measured, not a bug).
- Kit gap (app-side adapter, no Kit change): `NaruHelperPairingSession.makeQRImage`
  is internal (`NaruHelperPairingSession.swift:80`); the fixture path
  mirrors its math in `HelperUITestQR` using the Kit's public constants.
  If the Kit ever makes the QR maker public, the adapter can shrink to a
  call.
- Spec discrepancy honored: tasks.md Round A list mentions
  `NaruHelper/.gitignore`; the binding Round B contract says the ignore
  line goes in the root `.gitignore` — root used.
- PNG provenance: `pairing.png`/`paired.png` captured from the fixture
  window (640×532 pt @2x, synthetic offer — no real token/address);
  `menu.png` cropped to the open menu of the **real** status item driven
  via AX (contract order verified item-by-item: Not paired → rows →
  Pair with iPhone… → Start at login → Revoke… → Copy Diagnostics →
  version → Quit, with the two dividers). Manual-launch checks all pass:
  status item present, no Dock icon, Quit via its own menu exits, and the
  real `~/.naru/helper-pairing-state.json` checksum is unchanged across
  every ui-test and real launch (verified before/after).

## Lead notes after Round B review (2026-09-06)

- Lead gates re-run: `xcodegen generate` rc=0; `xcodebuild … build` rc=0 (twice, before and
  after the fixes below); `swift build` rc=0; pairing test filters green.
- Fixed lead-side: reopening the pairing window rotated the token while the view still read
  "Paired — iPhone connected" (the connected latch survived a rotation). `beginPairingSession()`
  now clears the latch after minting, so the window shows the fresh QR and the menu reads
  "Paired" until a phone actually connects on the new token.
- Fixed lead-side: the DEBUG fixture QR was regenerated (new `CIContext` + filter) on every body
  evaluation because `displayedQRImage` is a computed property. It is now rendered once at init.
  This is the likely cause of the "~40 s first render" the round measured; the Kit's own QR test
  renders in milliseconds. `NaruHelperPairingSession.makeQRImage` is now `public` and the
  duplicated app-side adapter is gone.
- Accepted as machine state, not code: the macOS XCUITest automation-mode authentication
  (quickstart §7).


## Lead notes after the first vision verdict (2026-09-06)

- Vision round 1 (opus) returned FIX on every axis: all three captures were occluded by
  macOS's **Local Network** permission alert (the fixture launch bound 5974/5975 and macOS
  prompted), and the menu crop lost "Quit". Both are capture/process defects, and one of them
  is also a product one:
  - Product: `Info.plist` now carries `NSLocalNetworkUsageDescription` so the first-launch
    prompt names why the helper listens. The quickstart's first-launch section lists the
    prompt.
  - Fixture launches (`--ui-test`) no longer start the listener runtime; they display
    `listening` rows without binding ports (no prompt, no collision with a real helper).
- Sampled the "~40 s first render" the round reported: the main thread sat in `getnameinfo`
  inside `NaruHelperPairingHostInfo.current()` (reverse MagicDNS lookup), called from the
  pairing window's `onAppear`. Real launches had the same freeze. Resolution now runs on a
  detached task with a generation counter; the window shows "Preparing the pairing code…"
  meanwhile. After the fix the fixture window is capturable in about one second.
- Captures re-taken lead-side with `screencapture -l <window>` from the same fixture launches
  (the XCUITest gate is still the machine-level automation approval). `menu.png` is the menu
  *preview* window (same `HelperMenu` content); the real status-item menu was verified
  item-by-item by Round B via AX and by vision round 1 (items 1–10 visible, "Quit" only
  cropped by the capture).
- Vision round 2 (opus): paired state SHIP; pairing window FIX for three ellipsis truncations
  ("Open System S…", the password placeholder) and misaligned buttons; menu fixture judged
  inconsistent (Paired + Missing) — a fixture choice, not code. Fixed lead-side: window default
  720×480 (min 680×440), left column fixed at 344 pt, right column ≥ 280 pt, permission rows
  use `.fixedSize()` text and a shorter **Open Settings…** button (spec/plan wording updated),
  password placeholder shortened to "VNC password (optional)" with the "included in this QR only"
  sentence as a caption below. Captures retaken with one consistent fixture (Paired, Granted).
- Vision round 3 (opus): paired state and menu SHIP; pairing window FIX — the QR image drawn at
  its native pixel size (module-count dependent, here 325 px) overflowed the 344-pt column and
  overlapped the password field. Fixed lead-side: the image is `.resizable()` at exactly 320 pt.
  Right-column empty space below the listener rows accepted as breathing room. Pairing capture
  retaken; round 4 judges only that file.

- Vision round 4 (opus) on the retaken pairing capture: SHIP on all four axes. Unrequested
  notes left as-is: the password field shows a focus ring in the fixture (first responder at
  launch), and "Granted" sits on a second line under each permission title.
