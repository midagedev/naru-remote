# Feature Specification: Full Resolution By Default

**Feature Branch**: `031-full-resolution-by-default`
**Created**: 2026-08-25
**Status**: Drafted 2026-08-25.
**Product**: Naru Remote
**Input**: Founder on build 9 — "와.. 빨라졌어.. 그런데 이거 해상도 너무 낮은데",
then "그냥 다운스케일 되면 그러려니 하겠는데 왜 이렇게 뭉개지지".

## Why

Build 9 fixed the frame rate (spec 030). What is left is that the picture is
soft, and the founder is right that it is not the compressor: the session
negotiates ZRLE, which is lossless, so nothing in the encoding path can smear a
pixel. Measured directly against this Mac's `screensharingd`: it serves
**3024×1964 at 32 bits per pixel, true colour** — a full Retina framebuffer with
no colour reduction. The mush is introduced after that, by resolution.

Spec 018 sends Apple's proprietary ScaleFactor message to halve the server-side
framebuffer whenever it judges the result "visually lossless". The rule is

    displayScale(full framebuffer) × displayPixelsPerPoint ≤ 0.5

An iPhone aspect-fitting a 3024-wide desktop sits at roughly 0.14 × 3 = **0.43**,
so the rule fires on the ordinary phone path and the session runs at 1512×982.
Two things are wrong with that today.

### The latency it was buying has already been bought

The downscale is a compensation, and what it compensated for turned out to be a
different defect. Spec 030 found that viewport-scoped incremental requests made
Apple Screen Sharing answer in 540–787 ms instead of 33 ms, and fixing that took
content frame rate from 0.49–0.74 to 5.66–7.08.

**Those measurements were taken at full 3024×1964 resolution** — the live
benchmark never sends ScaleFactor at all. So the path already delivers
5.66–7.08 content fps with 33 ms average update latency without any downscale,
and the pixels were being spent on a problem that no longer exists.

### "Visually lossless" was an inequality, not an observation

The rule reasons about framebuffer pixels per device pixel and concludes that
halving is free. It has never been checked against a phone screen, which
constitution §III requires before a claim like that counts. The founder looked at
it and the answer is no. The margin also explains why it fails in practice
rather than in theory: after halving, 1512 framebuffer pixels cover about 1290
device pixels, which is 1.17 per pixel — so the *moment* the user zooms to read
anything, the client is magnifying a half-resolution source through a single
bilinear tap.

### It is invisible and it is not controllable

The applied rung appears in no diagnostic export, which is why the founder's
build 8 report could not answer this and why it took a direct RFB probe to
establish what the server was even serving. There is also no user control: a
silent 2× resolution cut with no switch and no readout.

## Requirements

- **FR-001** The server-side downscale is off on the default (`balanced`) power
  mode. It stays available where the user has asked for less data — power saver
  and iOS Low Data Mode — so the trade becomes something the user chooses rather
  than something the app infers.
- **FR-002** The applied rung is published in the diagnostic export as a fixed
  label (`full` / `half`), never as a scale factor tied to dimensions
  (constitution §IV, and spec 018's own note about dimension-derived scales).
- **FR-003** A test pins that a balanced-power Apple session requests no
  downscale, failing against the current default.
- **FR-004** The policy itself is unchanged. It is correct about what it claims
  to compute; what changes is when the app asks it.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — downscale default test | a balanced Apple session sends no ScaleFactor | FAIL-first against today's default |
| `swift test` — power-saver test | power saver still downscales | direct |
| Live Mac, release | full resolution sustains the spec 030 frame rate | already measured: 5.66–7.08 fps at 3024×1964 |
| Founder device, build 10 | the picture is sharp, and `framePresentationHeldReason` / `contentFramesPerSecond` do not regress | founder device pass |

## Non-Goals

- Removing the ScaleFactor machinery or spec 018. The message works, it is
  Apple-gated for a good reason, and it is the right lever for a user who has
  asked for less data.
- The client's sampler. `filter::linear` with a single tap is a poor minification
  filter and a poor magnification filter, and mipmaps or a sharper upscale would
  be a real improvement. That is a separate change and it should not be bundled
  with a resolution default, because then neither could be attributed.

## Residual Risk

- **The bandwidth half of this is unmeasured, again.** Full resolution means
  roughly four times the pixels per full frame, and the founder is on a mobile
  link. The frame-rate evidence is from loopback; if the real link is
  bandwidth-bound, this trades sharpness for stutter and the founder will see it
  before any instrument here does. `dirtyAreaPermille` and
  `changedPixelsPermille` in the export are what to watch.
- Power saver is now the only automatic path to a downscale, so a user on a
  metered link who never opens settings gets full resolution. That is a
  deliberate choice of the default the founder can see over the default they
  cannot.
- The measurement that motivated this — 5.66–7.08 fps at full resolution — comes
  from one gate preset's stimulus on one machine. Spec 029 already recorded that
  the same machine measures 17 fps under a different harness configuration, and
  that discrepancy is still unexplained.
