# Feature Specification: Open To Developers

**Feature Branch**: `039-open-to-developers`
**Created**: 2026-08-27
**Status**: Landed 2026-08-27. Repository publication and founder device pass open.
**Product**: Naru Remote
**Input**: Founder, 2026-08-27, after the spec 038 round: "이건 근데 내가 이야기한
것만 고친거고 전반적인 개선을 더 해볼 부분은 없니? 나는 이 앱이 개발자에게 사랑받았으면
좋겠고 고품질이었으면 좋겠어. 그리고 이거 깃이 퍼블릭이니? 그럼 이슈나 피알 만들라고
어딘가 넣고 내 트위터 핸들 @midagedev도 넣고 여튼 전반적 개선이 필요해"

Decisions taken in the same exchange: **publish the repository**, licensed
**MIT**.

## Why

Spec 038 closed eight defects the founder had named. This round is the other
question — what is wrong that nobody has reported — asked of an app that wants
to be liked by the kind of person who reads its source.

The audit found the answer split cleanly in two. One half is that the project
has no public face at all: no README, no license, no contribution path, and —
inside the app — no About surface, meaning no version, no way to reach the
author, no acknowledgement of its one dependency, and no answer to "what does
this send anywhere". The other half is two defects that the design target
guarantees every user meets, and that no gate was watching.

## Findings

### The repository is private

`gh repo view` reports `visibility: PRIVATE`. Every "file an issue" affordance
this round adds would have been a 404 for anyone but the author.

The founder's decision is to publish, MIT. A full-history scan ran first — 868
commits, searched for key material, credential-shaped assignments, App Store
Connect identifiers, and committed key/env files. It found none: every ASC
identifier is an environment-variable reference, and every password-shaped
literal is a test fixture. Three non-routable private addresses appear in
fixtures and comments; one of them was a real tailnet address of the author's
and has been replaced with a placeholder — not because it was sensitive, but
because a fixture should look like a fixture.

**FR-001.** The repository carries a README, a LICENSE, a CONTRIBUTING guide, a
SECURITY policy, and issue/PR templates before it is published.

### 1. The app has no About surface

Measured: no `Settings`, `About`, or `Help` view exists anywhere under
`NaruRemote/App`, and no source file contains a `github.com`, `mailto:`, or any
other outbound URL. The version string is readable only inside the diagnostic
share text.

**FR-002.** The app carries an About & Feedback surface with the build version,
a route to report a problem and to request a feature, the author, the source,
the open-source acknowledgement, and a plain statement of what leaves the
device.

**FR-002a.** It is reachable from **both** home states. The Connections header
is the obvious place and it is not sufficient: the grid does not exist until a
profile does, so a user who cannot get their first connection working — the one
most likely to want to say something — would have been the one unable to find
it.

### 2. A live session does not hold the screen awake

`isIdleTimerDisabled` appears nowhere in the codebase. The device auto-locks on
its normal timer during a session.

This is not a small omission for this product. The canonical session is watching
a build, a test run, or an agent work for minutes without touching the screen —
and "minutes without touching the screen" is exactly what auto-lock is measuring
when it decides the phone has been put down. The single most common thing a user
does with this app is the single thing that makes the screen go out.

**FR-003.** An open connection holds off auto-lock while the app is frontmost.
Leaving the app, ending the session, or switching the preference off releases the
hold — every one of them, because a raised idle-timer flag that no path lowers is
a phone that does not sleep again until it is force-quit.

**FR-003a.** The rule is one function of the whole state, not a flag raised at
each call site. The default is on; the switch lives in the session tools menu
next to the session it applies to.

### 3. Hostname fields open on a Korean keyboard

Spec 016 FR-010 already declared this closed, in these words: "a hostname is
machine text — autocorrection 'fixing' `studio` to `studios`, leading-capital
`Studio.tailnet…`, or the field opening on a Korean IME page are functional
defects." It closed it with `.keyboardType(.URL)`.

That fixes the layout and not the language. A keyboard type selects which plane
of the *current* input mode appears; the input mode stays whatever the user
typed with last. On a phone whose keyboards are Korean-then-English — the
configuration of this product's own founder, and of a large share of its
intended users — the URL keyboard is the Korean keyboard with `.com` and `/`
added. The 2026-08-25 audit capture of the add-profile form shows ㅂㅈㄷㄱ and
`.com` in one frame.

**Why no gate saw it.** There wasn't one. Spec 016 stated the rule in prose and
verified it by writing the modifier. The rule is about which keys appear, and
nothing was reading the keys.

**FR-004.** A hostname field opens on a Latin keyboard whatever the device's
last-used input mode was, and a gate reads the keys to say so.

**FR-004a.** It also opens on a plane that carries `.` and `/`. A hostname is
mostly separators — `studio.tailnet.ts.net` is four dots — and a keyboard the
user must leave for every one of them is a different defect, not a fix.

**The first attempt failed FR-004a and the capture caught it.**
`.keyboardType(.asciiCapable)` passed the Latin assertion and opened a **bare
alphabet**: measured, `q…p / a…l / z…m / delete numbers`, no period. That turns
one globe tap — the actual cost of the original defect — into twelve taps to
the numbers plane and back. The gate now asserts the period too, and failed on
`.asciiCapable` before the second attempt.

Neither `keyboardType` value can deliver both, because `keyboardType` chooses a
layout and never a language. `HostnameTextField` takes `.URL` for the layout and
overrides `textInputMode` on a `UITextField` for the language, which is the only
API iOS offers for the second half. The globe key stays: pinning the *initial*
mode is the whole intent, and a user who wants another keyboard in this field
can still ask for one.

### 4. Dead code

`ProfileListView.swift` — 243 lines, a complete view with its own delete-confirm
alert, status dots, swipe actions and accessibility labels — is referenced from
nowhere. Not from the shell, not from another view, not from a test. It was
superseded by `ConnectionGridView` in spec 013 and never removed.

**FR-005.** It goes. A view that renders nowhere is a view that gets maintained,
reviewed, and read for orientation by the next person, at full cost and zero
value.

## Verification

| Requirement | How |
|---|---|
| FR-001 | The files exist; full-history secret scan recorded above. |
| FR-002, FR-002a | `AboutAndFeedbackUITests` — reachable from the empty home and from the Connections header; version renders from the real bundle keys rather than its fallback; every route present. |
| FR-003 | `ScreenWakePolicyTests` (13) over the decision for every session state, plus settings default/round-trip; `ScreenWakeCoordinatorTests` (6) over the writes, including the property that every ordering ends with the hold released. |
| FR-004, FR-004a | `HostFieldKeyboardUITests.testTheHostFieldOpensOnALatinKeyboardEvenWhenTheDeviceTypesKorean` — reads the on-screen keys: a Latin letter present, no Hangul, and the period on the plane that opened. FAIL-first confirmed for both halves, the second against the first attempt at the fix. Skips narrowly when no non-Latin keyboard is installed, because there the outcome is unproducible. |
| FR-005 | `swift build` (nothing referenced it) plus a repository-wide search for its identifiers. |
| All | iPhone 17 Pro simulator; founder device pass on the build that carries this. |

## Measured

FAIL-first, `HostFieldKeyboardUITests` against the pre-fix source, iPhone 17 Pro
with the simulator's keyboards set Korean-then-English (`AppleKeyboards =
("ko_KR@sw=Korean", "en_US@sw=QWERTY", "emoji")`, `AppleLocale = ko_KR`):

```
error: The host field came up on a non-Latin keyboard. …
       Keys present: Padding-Left Padding-Right … ㅂ ㅈ ㄷ ㄱ ㅅ ㅛ
error: ㅂ is on screen, so the Korean plane is the one that opened
```

After `.keyboardType(.asciiCapable)`: the Latin assertions passed, and the
period assertion failed with the plane it had opened:

```
error: The period is not on the plane that opened, so typing a MagicDNS name
       means switching planes for every dot. Keys present: q w e r t y u i o p
       a s d f g h j k l  z x c v b n m  delete numbers
```

After `HostnameTextField` (`.URL` layout, `textInputMode` pinned): all three
assertions pass — Latin letters present, no Hangul, `.` on the opening plane —
with `.` `/` `.com` visible in the capture.

## Residual risk

`HostnameTextField` is a `UIViewRepresentable`, so it does not participate in
SwiftUI focus and the editor's `@FocusState` is bridged to it by hand. Focus is
driven one way — into the field — because resigning from `updateUIView` as well
would let a stale `isFocused` snatch the keyboard back from whatever the user
tapped next. The cost is that dismissing the keyboard without moving to another
field leaves `focusedField` pointing at the host row; nothing reads it in that
state, and `onEditingEnded` records the visit that the inline error caption
needs, so the visible behaviour is unchanged. It is still a hand-maintained
bridge where there used to be a modifier.

Holding the screen awake spends battery, by design, and the case it is built for
— a long unattended session — is also the case where a user may put the phone
down and walk away. Backgrounding the app releases the hold, so the exposure is
a phone left face-up on a desk with the session in front. The switch is one tap
away in session tools and the setting persists. Whether the default survives
contact with a real day on a real battery is a device-pass question.

The About screen's "what leaves this device" section is a claim about the whole
app, maintained by hand. If a future feature sends something new anywhere, that
section is a place the change has to reach — and nothing enforces that but
review.
