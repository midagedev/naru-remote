# Release-readiness UI and performance review — 2026-07-12

## Decision

**Conditional TestFlight candidate: yes. Public 1.0 Green release: not yet.**

The current iPhone client pipeline, core session UI, local input surfaces, and
fallback logic are healthy enough for a limited internal TestFlight. The
repository does not yet have the physical, sustained evidence required by
`PRODUCT_QUALITY_TARGETS.md` to call the product Green or advertise a
Chrome-Remote-Desktop-class experience.

| Release lane | Decision | Reason |
| --- | --- | --- |
| Internal / founder TestFlight | Conditional go | Code, focused tests, iPhone simulator build, and current light/dark runtime inspection are healthy. |
| Public 1.0 | Hold | Real-screen helper video, sustained whole-product, live input, accessibility-device, and distribution gates remain. |
| CRD-class smoothness claim | Hold | The helper visual-primary path lacks a 30-minute real-screen physical gate; Apple Screen Sharing VNC remains server-limited. |

## Evidence used for the decision

- Existing physical iPhone Release measurements show decode `4–14 ms`, GPU
  upload `0–3 ms`, frame apply `0 ms`, outbound input `0–1 ms`, and average
  main-actor blocking around `12 ms`. The phone pipeline is not the measured
  bottleneck.
- The Apple Screen Sharing VNC path remains limited to about `5.6` content fps
  in loopback measurements. Further client-side VNC tuning is not the
  structural path to a 24 fps-class experience.
- The 2026-07-05 physical iPhone helper-video gate passed for 120 seconds with
  the synthetic encoded source. That proves the signed iOS decode/display
  route, but it does not prove ScreenCaptureKit real-screen capture or a
  30-minute thermal/RSS envelope.
- The latest code review found no P0/P1 correctness, concurrency, or privacy
  regression in the changed persistence, accessibility, or helper-video
  paths.

## Defects fixed in this review

### UI and accessibility

- Replaced fixed white-on-light chrome in the incoming-clipboard banner and
  Direct badge with adaptive semantic surfaces and text colors.
- Kept Direct/Live controls reachable beside compact Compose input, enlarged
  compact/floating controls to 44-point touch targets, and kept a direct
  Connections return action in profile detail.
- Prevented immersive control auto-hide and viewport/trackpad collapse while
  VoiceOver is running; added connection-card labels and a security hint for
  public-address warnings.
- Current iPhone 17 Pro runtime inspection passed for the first-run light
  screen, the active-session dark screen with the Compose surface both
  collapsed and expanded, and the dark incoming-clipboard review banner.

### Two-surface refinement

- Reduced primary navigation to **Connections → Operation**. A private card
  tap now enters Operation and starts one connection attempt immediately;
  advanced public cards retain explicit confirmation. Add/edit/delete remain
  sheet/menu actions, and iPad no longer duplicates the grid with a sidebar.
- Operation is full-height from connecting through failed/closed states. A
  persistent 44-point material diagnostic capsule shows typed state plus
  coarse quality or fixed-catalog failure and opens the full safe summary in a
  medium/large sheet.
- Connections/Disconnect now cancels the attempt/session before returning to
  the grid. Attempt/session/profile freshness guards prevent delayed
  credential, success, or failure callbacks from resurrecting a surface the
  user left.
- Failure remains on Operation with Retry, Edit, Diagnostics, and Connections.
  Immersive chrome respects VoiceOver and Reduce Motion; the capsule also
  respects Reduce Transparency.
- Phone/tablet evidence is stored in
  `artifacts/screenshots/2026-07-12-two-surface/`.

### Profile durability

- Made add/edit/delete await durable persistence before publishing success.
- Serialized mutations and added rollback for VNC, helper-text, and
  helper-video Keychain credentials, including intermediate failure cases.
- Profile editor and delete retry UI now retain the form/session context and
  show only fixed safe-catalog error text.

### Helper-video overload behavior

- Bounded live encoded-access-unit queues with a contiguous-prefix policy.
- Mapped queue overflow to a typed transport-backpressure stall.
- Proved the wire path falls back to VNC while preserving the active control
  session and Compose draft.
- Kept finite, already-materialized test adapters outside the live queue cap so
  valid batches do not produce false overflow.

## Verification

| Check | Result |
| --- | --- |
| UI/accessibility-focused SwiftPM tests | `75/75` passed |
| Helper-video backpressure/fallback tests | `62/62` passed |
| Profile persistence transaction tests | `26/26` passed |
| Frame-pacing race target | `5/5` repeated plus `10/10` adjacent passed |
| Clipboard-settle cancellation race target | `10/10` repeated plus `3/3` adjacent passed |
| SwiftPM optimized build | `swift build -c release` passed |
| iPhone 17 Pro / iOS 26.2 simulator build and launch | Passed |
| iPad Pro 13-inch (M5) / iOS 26.2 simulator build | Passed |
| Current iPad runtime visual pass | Passed: Connections grid and full-height Operation rendered without a duplicate sidebar |
| Current runtime visual inspection | Passed: iPhone Connections, active light/dark Operation, failed Operation recovery, diagnostic sheet, and iPad Connections/Operation |
| Full `swift test` | `1,511` executed / `26` skipped / `0` failures / `0` unexpected |
| Configured live Mac RFB smoke within the final full suite | `5/5` passed; five-run first-frame average `4,688 ms`, maximum `5,449 ms`, failures `0/5`; idle incremental `43 ms` empty update |
| Two-surface screenshot XCUITest | Passed: saved card → Operation → Connections return → Operation diagnostic capsule → full diagnostic sheet |
| Physical VoiceOver traversal | Open: simulator labels/values and 44-point targets are verified; physical traversal remains required |

## Remaining public-release gates

1. Run `specs/007` T030 with ScreenCaptureKit real-screen capture on a physical
   iPhone, then sustain it for 30 minutes and record privacy-safe RSS, thermal,
   frame-health, and fallback results.
2. Complete `specs/009` T021–T024: 200-character mixed Korean/English input ten
   times, per-commit p95, Unicode-KeyEvent `no-input` regression, and a
   30-minute Live session.
3. Complete one 30-minute whole-product physical iPhone session covering
   helper video, VNC fallback, Compose/Live/Direct, trackpad/zoom, reconnect,
   and PiP enter/leave.
4. Re-run the full iPhone/iPad light/dark and keyboard-up screenshot matrix and
   perform a real VoiceOver/Dynamic Type device traversal.
5. Produce and validate an App Store distribution Archive, upload to
   TestFlight, and complete the App Store Connect privacy/support/review-demo
   steps in `SUBMISSION_READINESS.md` section 5.5.

No endpoint, credential, composed user text, or host identifier is recorded in
this summary.
