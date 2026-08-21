# Feature Specification: Release-Configuration Measurement Instrument

**Feature Branch**: `025-release-measurement-instrument`
**Created**: 2026-08-21
**Status**: Implemented 2026-08-21 (configuration owner defaulting to release,
`buildConfiguration` on every report, `measurement-configuration-self-test` with
FAIL-first on three seeded regressions). The two contaminated judgements this
found are corrected in spec 024 and in
`NaruRemoteAppModel.defaultFrameStreamConfiguration`.
**Product**: Naru Remote
**Input**: Founder direction 2026-08-21 — "실용적인 수준까지 쭉 밀어봐" — and the
instrument audit that opened it.

## Why

`scripts/run-naru-live-benchmark.sh` is this repository's primary performance
instrument: every live latency number, every practical-target verdict, every
"where is the bottleneck" diagnosis in `NEXT_STEPS.md` and in the specs comes
out of it. The word `release` did not appear anywhere in that file. Every mode
built and ran `swift build --quiet` / `swift run --quiet`, i.e. **debug**.

Debug Swift leaves ZRLE inflate and tile apply unoptimised, and that cost
dominates everything downstream of it. Measured 2026-08-21 against the same live
target, with the same 12 Hz stimulus and the same flags, changing only the build
configuration:

| | content fps | server cadence diagnosis | practical issues |
|---|---|---|---|
| debug | 0.78 | `local-processing-dominated` | `client-processing-failed`, `very-slow-update`, `average-update-failed`, `p95-update-failed` |
| release | 7.68 | `first-byte-wait-dominated` | `client-processing-failed`, `full-upload-failed` |

Those are not two readings of one quantity. They disagree about **where the
bottleneck is** — the debug run blames the local client, the release run blames
the server's first-byte wait — and the debug one is an artefact. A ~30x debug
decode penalty had already been caught once in the DEBUG simulator perf HUD and
correctly discarded; nobody checked the benchmark script for the same defect.

Two concrete judgements were contaminated by it:

1. **A production constant.** `NaruRemoteAppModel.defaultFrameStreamConfiguration`
   sets `requestPipelineDepth: 3` and justifies it in a comment with "depth 1 →
   67 ms avg / 218 ms p95 update, 3.2 content fps; depth 3 → 27 ms avg / 175 ms
   p95, 5.2 content fps". Those magnitudes are debug-range. The constant may
   still be right, but its stated evidence does not survive re-measurement.
2. **A lead conclusion.** Spec 024 records "the server produces only 9.4 content
   fps ... so ~10 fps is Apple Screen Sharing's own cadence ceiling". That was
   measured with a **12 Hz** stimulus as the only moving content, so it was
   bounded by the stimulus, not the server. Re-measured in release at 30 Hz:
   content 13.7 fps, delivered 16.1 fps. There is no ~10 fps server ceiling.

The instrument is the defect. Fixing individual conclusions without fixing it
just re-contaminates the next round.

## Requirements

- **FR-001** A single owner decides the Swift build configuration for every
  build and run in the live benchmark script, and its default is `release`.
- **FR-002** No mode may name a live tool binary by a hardcoded configuration
  path, and no invocation may leave the configuration to Swift's default —
  including `swift build --show-bin-path`, which reports the debug path when
  asked unqualified and would otherwise silently win a candidate search.
- **FR-003** Debug remains reachable for label/argument regressions, which do
  not read timings, via an explicit `NARU_LIVE_BENCHMARK_CONFIGURATION=debug`.
- **FR-004** Every benchmark report states the build configuration it was
  produced under, so an archived report is self-describing and cannot be read as
  a measurement without that context.
- **FR-005** A text report produced in debug carries an explicit warning that
  its timings are artefacts.
- **FR-006** A gate fails when a future edit reintroduces an unqualified
  invocation, a hardcoded debug path, or a non-release default — the defect
  class, not the specific lines.
- **FR-007** Constitution §IV: the configuration label is a fixed enum value;
  no host, dimension, coordinate or user content is added to any report.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `scripts/run-naru-live-benchmark.sh measurement-configuration-self-test` | the script cannot silently return to debug measurement | FAIL-first: three seeded regressions (unqualified `swift run`, `.build/debug` path, default flipped to debug) each fail with their own safe code |
| `swift test` — `BenchmarkBuildConfigurationTests` | the configuration a report states is the one it was compiled with, and only release timings are marked trustworthy | runs under `swift test` (debug), so it pins the debug branch directly |
| Live Mac, same stimulus, debug vs release | the magnitude of the contamination this closes | recorded in the table above |
| Founder device | not applicable — this is a tooling contract | — |

## What This Does Not Fix

The re-measurement invalidates two recorded conclusions. Both are now replaced
rather than left dangling:

- The "~10 fps server ceiling" is retracted in spec 024 and `NEXT_STEPS.md`.
  Release at 30 Hz reads 13.7 content fps / 16.1 delivered.
- `requestPipelineDepth: 3` was re-measured properly: eight 15 s release runs per
  arm under an identical stimulus gave depth 1 a median of 7.7 content fps
  (range 5.1–11.6) against depth 3's 8.6 (range 5.3–10.9), with update latency
  31 ms average in both and depth 1 winning 41% of pairwise comparisons. The
  ranges overlap completely, so depth makes no measurable difference here. The
  constant stays at 3 — it is what ships and it is not worse — and its comment
  now states the release result instead of the debug numbers. A first 3-repeat
  attempt had shown a single-run gap of 10.3 vs 3.7 fps; that was noise, and
  shipping it as a constant change would have been the mistake this spec exists
  to prevent.

What the corrected instrument then found is a separate defect, closed in spec
026: a rectangle-count ceiling that was re-uploading the whole framebuffer on
174‰ of content frames.

## Residual Risk

- A cold optimised build of `VNCLiveBenchmark` takes minutes where the debug
  build took seconds, so bounded modes that wall-timeout their build step have a
  wider budget now and a cold machine will spend it.
- The gate reads the script's own source. It catches the invocation shapes named
  in FR-006; a mode that shells out to a wrapper of its own would sit outside it.
