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
