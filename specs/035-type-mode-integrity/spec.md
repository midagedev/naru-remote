# Feature Specification: Type Mode Has To Type

**Feature Branch**: `035-type-mode-integrity`
**Created**: 2026-08-25
**Status**: Landed 2026-08-25. Founder device pass on build 12 open.
**Product**: Naru Remote
**Input**: Founder on build 11: "키보드 모드에서 키보드가 안 올라올 때가 있다. 그리고
키보드 모드일 때 키보드 위에 불필요하게 상하 높이가 높은 패널이 생기는데 더 타이트하게
조이자. 그리고 키보드 모드일 때 백스페이스 안 먹는듯."

## Why

Three reports, one surface: the keyboard-up Type dock. They are filed together
because two of them share a cause — Type mode was given no visible field
(spec 015 v1.1 FR-008), and every affordance that used to be implied by a text
box had to be re-provided explicitly. Two were not.

### The keyboard sometimes does not come up

Type mode's first responder is a 1×1pt mirror editor
(`RemoteInputDockView.liveSoftKeyRow`). Focus is requested exactly once, from
`focusComposeEditorForGrantedExpansionIfNeeded()`, and the request is
unverified: `ComposeTextCommitController.focus()` calls
`textView?.becomeFirstResponder()` and discards the result.

Three things follow. The first two were **measured during implementation**, by
building the recovery key of FR-001 and watching it fail to focus anything —
they are the actual causes, and the unverified one-shot request is what hid
them:

**The controller can be detached from the editor it names.** The commit
controller is `@State` on `RemoteInputDockView`, so a view recreation
constructs a *new* one — while UIKit keeps the same `UITextView` and never
calls `makeUIView` again. `attach()` only ran from `makeUIView`, so the new
controller's weak reference stayed nil and every `focus()` against it was a
silent no-op. Nothing in the type system says the controller a view holds is
the controller its editor is attached to.

**Gaining focus undoes itself.** Taking first responder reports focus to the
shell, which flips the dock's *placement* (floating overlay → pinned inset) —
and that recreates the view, and its `@State`, out from under the responder
just installed. The idle capsule never hit this because it requests the
expansion *first* and lets the recreated instance focus in its own `onAppear`;
anything that focuses directly races the swap and loses.

**One-shot with no confirmation.** Because the result was discarded, both of
the above presented identically to the user: nothing happened, and nothing was
reported.

**No way back.** The dock stays in its keyboard-up layout while
`showsCompactComposeEditor` holds, and that is true whenever the mirror holds a
draft (`hasDraft`). So a focus loss with text in flight — the app going to the
background, PiP, a system interruption — leaves Type mode rendering a row of
soft keys with **no keyboard and nothing that raises one**. The keyboard
*dismiss* key exists (`naru.input.keyboard-dismiss`); its opposite does not.
Compose mode has the reveal button as its way back; Type mode has none, because
its field was removed.

### The panel is taller than its row

The row is one 40pt band, and the dock's own padding brings the surface to
~56pt. That is not what the founder is seeing, and the reason the existing gate
(`KeyboardUpDockHeightUITests`) cannot see it either is that the gate's fixture
never selects a delivery tier.

On a real session with no helper, the tier locks to `clipboardChunk` or
`keyEvent` at the first commit. From that moment:

- `liveDegradedTransportDisclosureText` is non-nil, so `liveDisclosureBadge`
  renders a full-width sentence — `caption2`, up to **two** lines, 12pt of
  vertical padding — as its own row above the keys;
- `liveActionableStatusText` is non-nil for `unconfirmedClipboard` and
  `asciiLastResort`, so `liveStatusLine` renders a second sentence below them.

Two sentences plus their spacings roughly doubles the dock. Both are permanent
for the rest of the session. Spec 015 FR-006 was written to stop exactly this
and it half-worked: it kept the *nominal* transport quiet, and left the
degraded one — which is the founder's every session — holding two rows open.

The requirement behind them is real and stays: spec 009 FR-014 exists because
the clipboard path overwrites the remote clipboard and the ASCII path cannot
carry Korean at all. A user must not type into a degraded transport unaware.
What is wrong is the *form*: a persistent fact about the session is being
rendered as a sentence in the scarcest space on the phone. Spec 033 already
built the place for persistent session facts — the health affordance that stays
quiet until it has something to say.

### Backspace does not work

`NaruRemoteAppModel.liveDeleteBackward()`:

```swift
guard !liveFieldText.isEmpty else {
    liveReachedWindowStart = true
    return
}
```

`liveFieldText` is the mirror of what *this* Live window believes it delivered.
It is empty on entering Type mode, and it is cleared again after every
`Return` (`openFreshLiveWindowAfterNewline()`). So in a terminal session — type
a command, press ↵, look at the output, reach for ⌫ — backspace is a no-op at
the most common moment there is. Nothing crosses to the remote; the only
feedback is a status sentence.

This is FR-011 working as designed and the design being wrong for a keyboard.
FR-011 forbids a delete from *crossing a seal* into remote content Naru did not
type, to prevent data loss. But Compose mode's ⌫ — the same glyph, the same
identifier prefix, one mode switch away — sends a plain remote `BackSpace` key
event and always has. The user is holding what looks like a keyboard, and one
of its keys silently does nothing depending on invisible window state.

## Requirements

- **FR-001 The keyboard-up Type dock always offers a way to raise the
  keyboard.** The dismiss key becomes a two-state key: while the mirror editor
  holds focus it lowers the keyboard, and while it does not it raises it. Its
  accessibility label and symbol state which one it is.
- **FR-002 A focus request is verified, not assumed.**
  `ComposeTextCommitController.focus()` reports whether the editor took first
  responder, and a granted expansion retries across a bounded number of
  runloop turns before giving up. The retry is bounded so a genuinely
  unfocusable editor cannot spin. Two structural halves come with it: the
  coordinator re-attaches the current controller to the live text view on every
  `updateUIView`, so a controller can never name an editor it is not attached
  to; and **every** path that raises the keyboard requests the dock expansion
  before focusing, so no caller races the placement swap.
- **FR-003 The degraded-transport disclosure keeps its guarantee and loses its
  row.** Spec 009 FR-014 still holds — a degraded transport is disclosed
  whenever it is in force — but on the compact keyboard-up dock it is disclosed
  as a **persistent inline badge inside the existing row** (a glyph plus one
  word naming the transport), not as a full-width sentence on a row of its own.
  The full sentence remains reachable: the session health affordance and the
  diagnostic export both carry it.
- **FR-004 The per-window status line earns its row or does not appear.** On
  the compact dock only a status the user must act on — a retained failure —
  takes a row. "Sent via clipboard, confirmation unavailable" and "typed as
  ASCII" are properties of the transport, and FR-003's badge is where they are
  now stated.
- **FR-005 A numeric height contract for the keyboard-up dock**, measured as
  the surface's own extent above the keyboard, and measured **in the degraded
  configuration** — because that is the configuration the founder is in, and
  the existing gate's blindness to it is why this report reached a device.
  Type mode: one row, and the chrome above the keyboard stays inside the
  single-row budget.
- **FR-006 In Type mode, ⌫ is a backspace key.** When the Live window has
  graphemes it delivered, ⌫ un-types one, exactly as now — the mirror stays
  truthful and the coalescing/cancel-local behaviour is unchanged. When it has
  none, ⌫ emits one remote `BackSpace` on the key lane, which is what Compose
  mode's identical control already does.
- **FR-007 The fall-through is bounded and reported.** It emits **one**
  backspace per tap, never a clamped count, and it is counted in the
  diagnostic export as a fixed-catalog count so a session can be asked how
  often the mirror was behind. No coordinates, no text (constitution §IV).
- **FR-008 Repeat-hold on ⌫ is unchanged.** The accessory strip's hold-repeat
  cadence already emits discrete keys; FR-006 does not add a second repeat
  path.

## Key Decisions

**D1 — FR-011's boundary moves from "the key does nothing" to "the key does one
thing".** The rule that a *diff-driven* delete may not cross a seal is kept:
the window still clamps its own reconciliation. What changes is that a user's
explicit keypress at the window start is no longer swallowed. This is a
deliberate narrowing of FR-011, and the reason it is safe is that one
`BackSpace` is what the user asked for by pressing a backspace key, is what the
same key already sends in Compose mode, and cannot delete more than one
character per tap.

**D2 — the disclosure moves, the guarantee does not.** Removing the sentence
from the dock would violate spec 009 FR-014. Replacing it with a permanent
badge that names the transport satisfies the same requirement in less space and
more legibly than a two-line caption the user stops reading on day two.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — model | ⌫ at the window start emits one remote BackSpace, and ⌫ with delivered graphemes still un-types locally | FAIL-first: the current source returns early and sends nothing |
| `swift test` — model | the fall-through count reaches the diagnostic export as a count, and the export carries no text | direct |
| `swift test` — snapshot | the compact dock's status line is actionable-failures-only, and the degraded transport is still disclosed somewhere | direct |
| iPhone simulator UITest | a Type dock holding a draft with no keyboard offers a key that raises one, the mirror editor takes focus, and the key turns back into the one that lowers it | `KeyboardUpDockHeightUITests.testTypeModeWithADraftAndNoKeyboardCanStillRaiseOne` — and it **failed twice before passing**, which is how both real causes were found. It needs the draft: with an empty mirror the dock collapses back to the capsule and recovery already worked, so the first version of this test passed for the wrong reason |
| iPhone simulator UITest | the keyboard-up Type dock is one row and inside the height budget **with a degraded tier locked in**; the badge is present and the sentence row is gone | `testTypeModeStaysOneRowWithADegradedTransport`, measured 1 row / 56pt span. The fixture could not exist until `NaruRemoteAppModel(snapshot:)` stopped dropping `liveTypeThroughMode` and `liveFieldText` — which is the reason this reached a device |
| **Founder device, build 12** | the keyboard comes up every time; ⌫ deletes; the dock is one row | the judgement these three reports are |

## Non-Goals

- Restoring a visible text field in Type mode. The founder asked for it gone
  (spec 015 v1.1) and this spec does not bring it back; FR-001 gives the row
  the affordance the field used to imply.
- Making ⌫ delete more than one character per tap, or making a *held* ⌫ cross
  a seal in bulk.
- Changing Compose mode's ⌫, which was already a plain remote key.
- Re-tuning the accessory strip's key set or order.

## Residual Risk

- FR-006 means a ⌫ tap can now delete a remote character Naru did not type.
  That is the intent of a backspace key, and it is what Compose mode has always
  done, but it is a genuine behaviour change on a destructive key. The bound is
  one character per tap.
- FR-002's retry is bounded, so an editor that cannot take first responder at
  all still ends with no keyboard — FR-001 is what makes that recoverable
  rather than terminal.
- The height budget is checked on a simulator at one width. A larger Dynamic
  Type setting can still grow the badge; the badge is one word and clipped
  rather than wrapped, so it costs no row, but it can truncate.
