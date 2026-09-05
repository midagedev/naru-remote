# Feature Specification: Naru Helper Menu Bar App

**Feature Branch**: `041-helper-menu-bar-app`
**Created**: 2026-09-05
**Status**: Implemented 2026-09-06 (founder decision 2026-09-05: "응 메뉴바
앱으로 가야해"). Kit: one-process `NaruHelperListenerRuntime`, real revoke
(absent state file ⇒ refuse; providers `String?`), `NaruHelperPairingSession`
+ deterministic offer bytes (`.sortedKeys`), status catalog, login-item
seam — `swift test` 1867 green (NaruHelperKitTests 159). App:
`NaruHelper/project.yml` → `Naru Helper.app` (`com.naruremote.helper`,
`LSUIElement`, hardened runtime, no sandbox) with MenuBarExtra menu, pairing
window, `SMAppService` login item, single instance; `xcodebuild build`
green; captures in `artifacts/screenshots/helper-menu-bar/`. Release:
`scripts/release-naru-helper.sh` (Developer ID → notarytool → staple →
spctl → GitHub Release), dry-run verified to fail fast. **Residual:**
(1) macOS XCUITest on this Mac is gated by a one-time "Enable UI
Automation" authentication — `xcodebuild … test` for the app is red until a
person approves it once; the PNGs came from the same fixture launch via
`screencapture`. (2) Founder physical pass 2026-09-06 morning: the Debug app launched from
DerivedData, grants given through the window's Open Settings… routes, a real
QR scanned with TestFlight build 19, and a live helper session — founder:
"이제 되는거 같네". Not separately reported: the reboot-with-login-item and
revoke steps of quickstart §4–5. (3) First real release run (quickstart §6) — never executed by an agent.
(4) No app icon yet (system default).
**Product**: Naru Remote
**Input**: Founder, 2026-09-05, after pairing a TestFlight build against the
terminal QR of spec 040: "연결은 되는거 같네 이거 근데 앱으로 안만들고 cli로
만들었어?" → "응 메뉴바 앱으로 가야해". This feature is the "helper
production packaging" item `NEXT_STEPS.md` has carried since spec 010
(menu-bar wrapper, notarization, auto-start, status disclosure,
revoke/disable UX), now specified because the founder has met the CLI as
a user and rejected it as the shipping surface.

## Problem

Spec 040 made pairing one scan instead of a typed 44-character secret,
but everything around that scan is still a terminal transcript:

- Three separate processes (`--pair`, `--listen`, `--video-listen`) that
  the user must know about and keep alive; nothing survives a reboot.
- The QR is 93 columns × 47 rows (measured 2026-09-05, 499-byte offer at
  correction level M). In an 80-column window it wraps and cannot be
  scanned — the founder's pass succeeded only because the window was
  opened at 110 columns for them.
- TCC permissions (Accessibility, Screen Recording) are granted to an
  ad-hoc-signed `NaruHelperDev.app` whose signature changes on every
  rebuild, so grants lapse silently; the first helper session of
  2026-09-04 died on exactly that. A CLI has no place to show "granted /
  missing" except a line the user has already scrolled past.
- There is no download. The helper exists only as `.build/release/NaruHelper`
  on a Mac that has cloned the repository and installed a Swift toolchain.

A menu bar app is the shape macOS gives to "always-on, permission-bearing,
mostly invisible" software, and it is where Orca, Tailscale, and every
comparable pairing UX put the QR. `docs/PRODUCT_SPEC.md` §9.4 named
"macOS app / menu bar helper" as the deployment form from the start.

## What Changes And What Does Not

**Changes**: the helper's user-facing form. One app bundle, `Naru Helper`,
lives in the menu bar; it owns pairing (QR in a window), both listeners
(one process), permission state, auto-start, and revoke.

**Does not change**: the wire. The pairing offer (`naru://pair?code=…`,
spec 040 FR-001), the text bridge protocol (spec 006), the video transport
(spec 007), the pairing-state file and its per-connection verification
(spec 040 FR-002) are all reused verbatim. The iPhone app already on
TestFlight (build 19) pairs with the menu bar app without a client
change — that is a hard constraint, verified in the matrix below.

The CLI does not disappear: it stays as the benchmark/CI/automation
surface (`scripts/run-naru-live-benchmark.sh` and the live gates pin a
token via env and must keep working). It stops being documented as the
way a person installs the helper.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Install, Grant, Pair, Connect (Priority: P1)

A user downloads `Naru Helper.app`, opens it, sees a menu bar icon, and
from its menu chooses **Pair with iPhone…**. A window shows a QR code
sized for a phone camera and, beside it, the two permission states with a
button for each that opens the right System Settings pane. They scan the
QR with the iPhone app (or the iOS Camera), tap Save on the phone, and the
window flips to "Paired — iPhone connected" the moment the first helper
handshake arrives. Both listeners were already running; nothing else to
start.

**Why this priority**: this is the whole reason the feature exists — the
founder's own first pairing needed a repo checkout, a 110-column terminal,
and three commands.

**Independent Test**: a UI test drives the pairing window against an
injected offer and a fake handshake signal, asserting QR presence,
permission rows, and the "paired" transition, without a phone. The
physical path is the founder pass in the matrix.

**Acceptance Scenarios**:

1. **Given** the app is launched for the first time, **When** the menu
   bar icon is clicked, **Then** the menu shows helper status (Not paired /
   Paired / Connected), both permission states, **Pair with iPhone…**,
   **Start at login** (toggle), **Revoke pairing…**, and **Quit**.
2. **Given** **Pair with iPhone…** is chosen, **When** the window opens,
   **Then** a fresh token has been minted (spec 040 rotation), the QR
   encodes the same `naru://pair?code=…` offer the CLI produced, the raw
   code is one click to copy, and both listeners are accepting connections
   on 5974/5975.
3. **Given** a permission is missing, **When** the window is open,
   **Then** the row reads "Missing" with an **Open Settings…**
   button that lands on the Accessibility or Screen Recording pane, and
   the row updates to "Granted" without relaunching once the grant lands
   (polling or notification — plan decides).
4. **Given** the phone saved the profile, **When** its first helper
   handshake is accepted, **Then** the window shows "Paired" and dismisses
   the QR (the QR is credential material; it must not stay on screen
   after it has done its job).

---

### User Story 2 — Survives Reboot, Runs Without A Terminal (Priority: P1)

The user restarts the Mac. The helper is back in the menu bar before they
log in to the phone app; the phone's saved profile connects with no
action on the Mac.

**Why this priority**: an always-on helper that needs a manual launch is a
terminal in disguise. Constitution §VI's sustained-session workflow
depends on the Mac side being unattended.

**Independent Test**: the login-item registration is a pure call with an
observable status; unit-test the state machine around it and assert the
system-reported status after toggling in a manual pass.

**Acceptance Scenarios**:

1. **Given** **Start at login** is on, **When** the user logs in,
   **Then** the helper is running with both listeners up within the
   normal login-item window and no terminal or Dock icon appears.
2. **Given** the helper is running, **When** the pairing file is rotated
   by a second **Pair with iPhone…**, **Then** the running listeners honor
   the new token on the next handshake without restart (spec 040 FR-002
   still holds inside one process).
3. **Given** a listener port is occupied (a stray CLI `--listen`), **When**
   the app starts, **Then** the menu shows a fixed-catalog "Port in use"
   state naming the port, not a silent dead listener.

---

### User Story 3 — Revoke And Quit Are Real (Priority: P2)

The user chooses **Revoke pairing…**, confirms, and every phone that held
the old token is refused from its next handshake. Quit stops both
listeners. Basic VNC viewing from the phone is unaffected by either.

**Why this priority**: constitution §IV — helper capabilities must be
observable and revocable. Spec 006 T028 (helper-side revoke) has been
open since June; this is where it closes.

**Independent Test**: after revoke, the pairing state is absent and both
request handlers refuse a formerly-valid proof with the fixed `revoked`
code (unit test against the handlers with the store pointed at a temp
directory).

**Acceptance Scenarios**:

1. **Given** a paired helper, **When** **Revoke pairing…** is confirmed,
   **Then** the state file is removed, the status reads "Not paired", and
   a handshake with the old token is refused with the fixed `revoked`
   code — not accepted from a cached secret.
2. **Given** the helper is running, **When** **Quit** is chosen, **Then**
   both listeners close and the phone's next helper attempt fails with the
   existing fixed unreachable state while VNC keeps working.

---

### User Story 4 — A Stranger Can Install It (Priority: P2)

Someone who found the repository (spec 039 opened it) downloads a signed,
notarized build from GitHub Releases, opens it, and macOS launches it with
no "unidentified developer" block and no Gatekeeper bypass instructions.

**Why this priority**: an app that must be built from source is still
developer-only; the download is what makes the menu bar app a product.

**Independent Test**: `spctl --assess` and `codesign --verify --strict`
pass on the release artifact; `xcrun stapler validate` confirms the
notarization ticket.

**Acceptance Scenarios**:

1. **Given** a release artifact, **When** it is opened on a Mac that has
   never seen the repository, **Then** it launches without a Gatekeeper
   refusal, and the About/menu shows the version that matches the release
   tag.
2. **Given** the iPhone app's pairing entry, **When** the user has no
   helper yet, **Then** it points at the download in one line — no
   public-internet or Tailscale-affiliation language (constitution §II).

### Edge Cases

- Two Macs in the same tailnet each running a helper: the QR carries each
  Mac's own addresses and MagicDNS name (spec 040), so nothing changes;
  the phone matches profiles by host.
- The Mac has no tailnet address when **Pair with iPhone…** is chosen:
  the window states it plainly and offers a retry — no public-IP fallback
  (constitution §II).
- The user grants Screen Recording while the video listener is already
  serving a refused request: the next request succeeds; the current one
  fails with the existing fixed permission code.
- The pairing window is open when the screen locks or the Mac sleeps: on
  wake the QR is still valid (the token has not rotated) but the window
  re-checks permissions and tailnet address.
- The bundle identifier differs from `com.naruremote.helper.dev`: existing
  TCC grants to the dev wrapper do not carry over. The first launch shows
  both permissions as Missing; that is expected and the window says so.
- Multiple user sessions (fast user switching): the helper runs per user
  session; the listener in the inactive session refuses inserts with the
  existing `activeUserSession` fixed state (spec 006).
- The app is launched a second time while running: the second instance
  hands off to the first (single-instance) instead of fighting for the
  ports.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001 (form)**: `Naru Helper` MUST ship as a macOS app bundle with a
  menu bar item and no Dock icon or main window at launch. Its menu MUST
  expose, at minimum: status, permission states, **Pair with iPhone…**,
  **Start at login**, **Revoke pairing…**, **Quit**, and the version.
- **FR-002 (single process)**: the app MUST run the text bridge listener
  and the video listener in one process, reusing `NaruHelperKit`'s
  servers unchanged, and MUST report each listener's state (listening /
  port in use / stopped) as fixed-catalog values.
- **FR-003 (pairing window)**: **Pair with iPhone…** MUST rotate the
  pairing state (spec 040 FR-002), render the offer as a QR image at a
  size a phone camera reads from arm's length, show the raw
  `naru://pair?code=…` behind a copy button, and dismiss the QR on the
  first accepted handshake or on close. The offer bytes MUST be identical
  to what `NaruHelper --pair` produces for the same inputs (one encoder,
  `NaruPairingOfferWire`).
- **FR-004 (VNC password)**: the pairing window MUST offer an optional
  VNC password field that is included in the offer only for that QR and
  never persisted by the helper (spec 040 founder decision: full payload
  is opt-in per pairing).
- **FR-005 (permissions)**: the menu and the pairing window MUST show
  Accessibility and Screen Recording as Granted / Missing, using the
  existing fixed-catalog probes, and MUST offer a one-click route to the
  matching System Settings pane. The state MUST refresh while the app is
  running; a relaunch MUST NOT be required to observe a new grant.
- **FR-006 (login item)**: the app MUST register itself as a login item
  via the system service API when **Start at login** is on, reflect the
  system's reported status (including "requires approval" on macOS 13+),
  and unregister when it is turned off. No launchd plist is written by
  hand.
- **FR-007 (revoke)**: **Revoke pairing…** MUST require confirmation,
  remove the pairing state, and cause both listeners to refuse every
  subsequent handshake with the fixed `revoked` code. The pairing store
  MUST distinguish "file absent" (refuse) from "transient read failure"
  (keep last state) — today's `currentSecret()` falls back to its cache
  for both, which would make revoke a no-op.
- **FR-008 (single instance)**: a second launch MUST activate the running
  instance and exit rather than start duplicate listeners.
- **FR-009 (identity and signing)**: the release bundle MUST carry a
  stable bundle identifier (`com.naruremote.helper`), be signed with the
  Developer ID Application certificate of team XEF9KH7N43, be notarized
  and stapled, and be published as a GitHub Release asset. The dev wrapper
  `com.naruremote.helper.dev` MUST remain a separate identity so a
  developer's TCC grants for benchmarks are not disturbed.
- **FR-010 (CLI stays for automation)**: `NaruHelper` CLI targets and
  their env-pinned launch contract MUST keep building and passing their
  existing tests; documentation MUST reposition the CLI as
  benchmark/automation-only and the app as the install path.
- **FR-011 (phone unchanged in v1)**: no change to the iPhone app is
  required for pairing or connecting; the only iPhone change in scope is
  the one-line download pointer of US-4 SC-2, and it MUST be
  independently shippable.
- **FR-012 (diagnostics)**: the app MUST expose a **Copy Diagnostics**
  action producing the fixed-catalog helper state (permissions, listener
  states, paired/not, version) with no token, fingerprint, address, or
  code in it — the same redaction rule as spec 040.

### Naru Input Requirements

- **IN-001**: N/A — no new input path. The helper's `nativeInsert` and
  video transport are unchanged.
- **IN-002..005**: N/A (inherited from specs 006/007).

### Tailnet / Connection Requirements

- **TN-001**: Private-network assumption unchanged: the offer carries the
  Mac's CGNAT addresses and MagicDNS name; the app refuses to pair with no
  tailnet address rather than falling back to a LAN or public address.
- **TN-002**: Diagnostics shown: permission states, listener states,
  paired state, "no tailnet address" — all fixed catalog.
- **TN-003**: Public internet posture: unsupported; no copy suggests
  opening ports or that Naru replaces Tailscale.

### Security & Privacy Requirements

- **SP-001**: Data crossing local/remote: unchanged from specs 006/007/040
  (helper token, fingerprint, optional VNC password in the QR; inserted
  text and video frames over the paired channels).
- **SP-002**: Data retained on device (iPhone): unchanged (Keychain refs).
- **SP-003**: Data retained on the Mac: `~/.naru/helper-pairing-state.json`
  (0600; token + fingerprint + created-at) and the login-item
  registration. The optional VNC password is never written by the helper.
  The QR image lives only in the pairing window's memory and is dropped
  on dismiss.
- **SP-004**: Actions needing confirmation: **Revoke pairing…**; a second
  **Pair with iPhone…** while paired warns that existing phones will need
  to re-scan.
- **SP-005**: Logging rule: no token, fingerprint, code, address, or
  inserted text in logs or diagnostics; the `naru://pair?code=` redaction
  pattern of spec 040 applies to anything the app writes.

### Key Entities

- **HelperAppStatus**: fixed-catalog aggregate of listener states,
  permission states, and pairing state; drives the menu, the window, and
  **Copy Diagnostics**.
- **PairingSession**: one **Pair with iPhone…** invocation — the rotated
  state, the encoded offer, the QR image, and the "first accepted
  handshake" signal that ends it.
- **LoginItemRegistration**: desired (on/off) vs. system-reported status.

## Acceptance Test Matrix *(mandatory)*

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| Offer bytes from the app equal `--pair` output for the same inputs | XCTest (NaruHelperKit) | N/A | test over a shared encoder with fixed inputs |
| Both listeners up in one process; port-in-use surfaces as fixed state | XCTest (NaruHelperKit) | N/A | test binding a taken port, asserting the catalog value |
| Revoke: file absent ⇒ both handlers return `revoked`; transient read failure ⇒ last state kept | XCTest (NaruHelperKit) | N/A | test with the store on a temp dir; FAIL-first against today's cache fallback |
| Pairing window: QR present, permission rows, copy, dismiss on handshake | XCUITest (macOS) | N/A | screenshot + assertions with injected offer and fake handshake signal |
| Menu contents and status transitions | XCUITest (macOS) | N/A | screenshot per state |
| Login item toggle reflects system status | manual Mac | N/A | checklist: toggle, `sfltool dumpbtm` or Settings shows the item; reboot brings the icon back |
| TestFlight build 19 pairs against the app's QR and connects (text insert + video) with no phone change | physical iPhone + Mac | iPhone | founder pass; `helperTextBridgeState`/video state in the phone's diagnostics |
| Release artifact launches clean on a fresh Mac | manual Mac | N/A | `spctl --assess -vv`, `codesign --verify --strict`, `stapler validate` outputs recorded |
| Existing CLI gates unchanged | `swift test` + benchmark script | N/A | green run of the helper test targets and one benchmark invocation with env-pinned token |

No iPad-specific path: the feature has no iPad surface beyond the
unchanged phone-side pairing flow, which spec 040 already covers.

## Success Criteria *(mandatory)*

- **SC-001**: From download to first paired handshake in under three
  minutes on a Mac that has never run the helper, with no terminal opened
  (founder pass, timed).
- **SC-002**: After a reboot with **Start at login** on, the phone's saved
  profile connects to the helper with zero actions on the Mac.
- **SC-003**: A lapsed permission is visible in the menu within five
  seconds of the app noticing it and never manifests as an unexplained
  handshake failure.
- **SC-004**: Revoke refuses a previously accepted token on the very next
  handshake, verified by test.
- **SC-005**: The release artifact passes Gatekeeper assessment with no
  user override.

## Assumptions

- macOS 14+ (the package's existing floor); the menu bar and login-item
  system APIs available there are sufficient — no third-party dependency.
- Distribution outside the Mac App Store: Accessibility and Screen
  Recording as used here are incompatible with the App Sandbox, so the
  channel is Developer ID + notarization + GitHub Releases. The repository
  is public (spec 039), so Releases is a natural home.
- The App Store Connect API key already used by `scripts/testflight-upload.sh`
  is acceptable for notarization; the Developer ID Application
  certificate is present on the founder's Mac (verified 2026-09-05).
- The pairing-state file location stays `~/.naru/`, shared with the CLI,
  so a developer can mix CLI and app during the transition.

## Non-Goals

- Per-device tokens (spec 040 open question 2) — single active token
  remains; the app makes rotation visible, not multi-phone.
- Windows tray / Linux daemon helpers (`docs/PRODUCT_SPEC.md` §9.4) — this
  spec is macOS only.
- Mac App Store distribution, Sparkle-style auto-update, Homebrew cask —
  candidates once a release cadence exists.
- Redesigning the phone-side pairing UI — spec 040's confirm sheet and
  scanner are reused as-is.
- Shrinking the terminal QR (correction level L, dropping the derivable
  fingerprint) — moot once the QR is an image; the CLI keeps its current
  renderer for automation.
