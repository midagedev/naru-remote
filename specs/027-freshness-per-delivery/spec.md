# Feature Specification: Freshness Measured Once Per Marker Delivery

**Feature Branch**: `027-freshness-per-delivery`
**Created**: 2026-08-21
**Status**: Implemented 2026-08-21 (one freshness sample per marker delivery;
stalled markers separated from stale pictures; delivery/repeat counts published).
The staleness this was meant to quantify is **still open** — see below.
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
| Live Mac, duration sweep 5 / 15 / 40 s | reported peak no longer scales with the run length | `VNCLiveBenchmark`, release |

## What This Found

Deliveries are rare relative to updates. Across the corrected runs, re-reads
outnumbered deliveries roughly four to one — 58 re-reads to 9 deliveries in 5 s,
119 to 25 in 15 s, 227 to 50 in 40 s, all with status `tracking`. So **about
four in five received updates carry no new marker**, even though the request
region is the full framebuffer and the marker is inside the animating window.
The server is answering with a subset of what changed.

That is a new fact about this transport, and it is the first measured thing that
plausibly matches "느리다": not a low frame rate, but a picture whose regions are
refreshed in turns.

## What Is Still Open

The corrected metric still reports maxima of 4.2–9.2 s in the longer runs, and
those are now genuine deliveries, not re-reads. That should be impossible if
every delivery carries the marker that was on screen at capture time, so either
the server delivers captures that are seconds old, or the marker search is
matching something the audit has not accounted for. The next experiment is to
publish the *distribution of delivery gaps* (how many marker sequences were
skipped between consecutive deliveries) as counts, which stays inside §IV and
distinguishes "sampled sparsely" from "delivered late" without printing a single
coordinate.

Until that resolves, freshness averages and p95 are **not** a target. Delivery
and re-read counts are the trustworthy part of this metric today.

## Residual Risk

- The `stalled` threshold (four observations of one sequence) is a judgement, not
  a measurement. A run that legitimately received only a handful of updates and
  no new marker reads as `tracking`, which errs toward not condemning a run.
- One sample per delivery lowers sample counts sharply — 46–156 observations
  became 0–36 samples in the sweep — so short runs can now produce too few
  freshness samples to summarise at all. That is honest, but a gate built on this
  metric needs a minimum-sample guard rather than trusting a two-sample average.
