# Feature Specification: Freshness Measured Once Per Marker Delivery

**Feature Branch**: `027-freshness-per-delivery`
**Created**: 2026-08-21
**Status**: Implemented 2026-08-21. Three stacked instrument defects removed —
debug-built measurement (spec 025), per-observation resampling of one delivery,
and false-positive marker decodes. The metric is now stable and independent of
run length: **average 125 ms, p95 135–385 ms** across 5 / 15 / 40 s runs. The
"median ~1 s, p95 7–13 s of staleness" that opened this was **entirely an
artefact**.
**Product**: Naru Remote
**Input**: Founder direction 2026-08-21 — "실용적인 수준까지 쭉 밀어봐". The
visual-freshness metric was the closest instrument to the founder's "느리다", so
it was audited before being used as a target.

## Why

`visualFreshnessLatency` is the only metric that measures what the founder
actually complains about: how old the picture on screen is. It was reading a
median of ~0.9–1.3 s of age with a p95 of 7–13 s while update latency averaged
31 ms, which would be a damning number if it were true.

It was not true, and the tell was that it did not survive changing the run
length. Varying only `--stream-shape-duration-seconds`, everything else held:

| run length | peak reported staleness |
|---|---|
| 5 s | 0.98 s |
| 15 s | 6.8 s |
| 40 s | **31.8 s** |

A 31.8 s stale region inside a 40 s run of continuously animating content is not
a plausible reading. The peak was tracking the instrument, not the picture.

The cause is that the benchmark's framebuffer is persistent, so a marker the
server has not re-sent stays on it and decodes again on every subsequent update.
The probe timed every decode, so one undelivered marker became a run of samples
whose age only grew. Visible directly in the FAIL-first output of the new test:
re-reading a single marker returned 9 ms, then 258, 262, 267 ms. Average and p95
built from that describe the probe's sampling rate.

There was a second reading the metric could not distinguish at all: a stimulus
window that is occluded, unfocused, or off-screen leaves its last marker frozen
on the captured screen. That is the *host* not painting, and it would have
reported as transport staleness indefinitely.

## Requirements

- **FR-001** A freshness sample is recorded once per marker **delivery** — the
  first time a sequence is observed — never on a re-read of an already-timed
  marker.
- **FR-002** A re-read still reports its sequence, so the summary can count it.
- **FR-003** The summary publishes how many distinct marker sequences were
  delivered and how many observations were re-reads, as counts.
- **FR-004** A fixed marker-status label separates the three cases: no marker
  decoded (`not-observed`), a marker that never advanced across at least four
  observations (`stalled`, i.e. the host stopped painting — freshness numbers
  from such a run mean nothing), and a marker that advanced (`tracking`).
- **FR-005** These fields survive the report round-trip. The summary hand-writes
  both `encode(to:)` and `init(from:)`, so a field can be read back with a
  default while never being written — which is what happened on the first
  attempt at this change.
- **FR-006** Constitution §IV: counts, permille ratios, fixed labels and
  aggregate millisecond summaries only. Marker locations stay out of the encoded
  form, as they already did.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — `testRepeatedObservationsOfOneMarkerYieldASingleFreshnessSample` | re-reads produce no sample; a real new delivery is timed again | FAIL-first: repeats returned 9 / 258 / 262 / 267 ms before the fix |
| `swift test` — `testMarkerStatusSeparatesAStalledMarkerFromAStalePicture` | the three cases and the four-observation threshold | direct |
| `swift test` — `testMarkerDeliveryAccountingSurvivesTheReportRoundTrip` | the new fields are written, not just read | FAIL-first: the first live run showed them absent from the JSON |
| `swift test` — `testAnImpossibleSequenceIsRejectedWithoutBlindingTheProbe` | a false match is rejected and does not poison the high-water mark | pins the trap this went through |
| `swift test` — `testASequenceThatGoesBackwardsIsRejected` | the marker never counts down | direct |
| Live Mac, duration sweep 5 / 15 / 40 s | reported peak no longer scales with the run length | `VNCLiveBenchmark`, release |

## The Third Defect: False Marker Matches

Sampling once per delivery was not enough — maxima still tracked the run length
(0.2 s in a 5 s run, 9.2 s in 15 s, **35.2 s in 40 s**). Two further hypotheses
were tested rather than assumed:

1. **Paint scheduling.** The sidecar timestamp was written from the frame timer,
   before the repaint it requested, so it meant "this sequence was *intended* at
   this time" — and AppKit defers drawing for a window that is not front. The
   sidecar now records from `draw`, so it means "this sequence was rendered".
   This was worth fixing on its own, but it did **not** move the maxima:
   re-measured, they got slightly worse. Hypothesis rejected.
2. **False marker matches.** The decoder scans every cell size from 96 down to 8
   across several framebuffer bands, returns the first match, and tests only four
   sentinel nibbles plus a four-bit checksum — twenty bits against millions of
   candidate positions per frame, so accidental matches are expected rather than
   exceptional. A false match preempts the real marker because it is found
   first, and if its bogus sequence happens to exist in the sidecar the probe
   charges the entire elapsed run to the transport.

Three properties of the stimulus reject those reads, and **the order matters**: a
sequence the host never rendered cannot be on screen, a sequence beyond the
newest rendered one cannot exist yet, and the on-screen marker never counts
down. The first two are checked before the monotonic high-water mark is touched.
Doing it the other way round is a trap this implementation went through: one
false match with a huge sequence sets the mark out of reach and every later true
read is rejected forever, which *looked* like success — maxima collapsed — while
the probe had actually gone nearly blind (deliveries fell from 22–37 to 1–8 per
run). That failure mode is now its own test.

## What This Found

With all three defects removed, freshness is stable and independent of run
length:

| run length | average | p95 | max | deliveries |
|---|---|---|---|---|
| 5 s | 125–126 ms | 135–146 ms | 135–146 ms | 4–6 |
| 15 s | 122–154 ms | 145–385 ms | 149–385 ms | 17–28 |
| 40 s | 125–129 ms | 141–149 ms | 148–315 ms | 23–31 |

So a rendered frame reaches the client in about **125 ms**, with a p95 near
150 ms. There is no multi-second staleness, and there never was — it was a debug
build, then resampling, then false matches.

Note what this number is: the age of a marker **at the moment it arrives**, i.e.
end-to-end delivery latency for a region that was delivered. It is not average
screen staleness. Re-reads still outnumber deliveries about five to one (121–157
re-reads against 23–31 deliveries), so a given region is refreshed roughly once
per five updates — the server answers with a subset of what changed. Both
quantities are now trustworthy; neither shows a seconds-scale problem.

This puts the founder's "느리다" back where spec 024 first placed it: the content
frame rate (~8 fps here, 13.7 measured against a 30 Hz stimulus), not picture
lag. The measured answer to frame rate remains the helper video transport
(`upTo30`, `smooth`, `decodePressure: low`), blocked on physical iPhone pairing
(spec 010 T014).

## Residual Risk

- The `stalled` threshold (four observations of one sequence) is a judgement, not
  a measurement. A run that legitimately received only a handful of updates and
  no new marker reads as `tracking`, which errs toward not condemning a run.
- One sample per delivery lowers sample counts sharply — 46–156 observations
  became 3–30 samples in the sweep — so short runs can now produce too few
  freshness samples to summarise at all. That is honest, but a gate built on this
  metric needs a minimum-sample guard rather than trusting a three-sample
  average.
- The rejection rules are properties of *this* stimulus (a monotonically
  advancing marker whose every rendered value is logged). They are not a
  strengthened marker encoding, so a false match whose sequence happens to be
  rendered, in range, and ahead of the high-water mark still gets through. The
  structural fix would be a wider sentinel; the rules were chosen because they
  cost nothing and needed no change to the marker's on-screen size.
- `regressedObservationCount` is exposed on the probe but not yet published in
  the report, so the rejection rate is not visible in an archived run.
