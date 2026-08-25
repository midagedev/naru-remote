# Feature Specification: Measure The Path The Product Actually Runs On

**Feature Branch**: `029-measure-the-real-path`
**Created**: 2026-08-25
**Status**: Measured 2026-08-25. **The premise did not survive the experiment.**
The RTT measurement stands and is valuable (41-500 ms to the founder's phone,
median ~185 ms). The conclusion drawn from it — that the session is round-trip
bound and pipeline depth is therefore the dominant term — is **not supported**:
depth 1, 2 and 3 are indistinguishable both with and without conditioning,
because the binding constraint under the measured workload is roughly 1.27 s per
update that is present at zero added latency. The shipped constant is unchanged.
What this work does leave behind is a validated conditioning harness and two
instrument fixes.
**Product**: Naru Remote
**Input**: Spec 028's first device export — the founder's build 8 session was
presenting every frame it received and still receiving under five content frames
per second, with `averageNetworkReadTimingBucket: stalled` and eight transport
idle timeouts.

## Why

Every frame-rate number in this repository was measured against Apple Screen
Sharing on **127.0.0.1**, with `--network-condition none`. Spec 027's headline —
17.0 content fps, 111 ms delivery latency — describes a path with essentially
zero round-trip time.

No user has that path. Measured 2026-08-25 with `tailscale ping` from this Mac to
the founder's iPhone, which is connected **direct** over a mobile network:

| sample | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| RTT (ms) | 41 | 56 | 232 | 372 | 416 | 65 | 137 | 500 |

Median ≈ 185 ms, minimum 41 ms, maximum 500 ms — a **twelve-fold spread**. This
is the product's real transport, and two of this repository's standing
conclusions do not survive contact with it.

### 1. The request-response loop is round-trip bound

Apple Screen Sharing does not negotiate ContinuousUpdates, so the session runs
request→response. With `requestPipelineDepth` requests in flight, the ceiling is

    frames per second ≈ pipeline depth ÷ round-trip time

At the shipped depth of 3: **16 fps at the median RTT, 6 fps at the observed
maximum.** The founder measured `underFive`. And more than half of those round
trips carried nothing — the same export shows `emptyUpdatePermille: 558`, so 24
of 43 responses were empty updates. Round trips spent on empty responses are
round trips not spent on pixels, which drags the effective content rate well
below the ceiling.

This is a hypothesis with arithmetic behind it, not a measurement, and this spec
exists to measure it rather than assert it.

### 2. The pipeline-depth conclusion is uninformative, not wrong

`NaruRemoteAppModel.swift` currently carries, in a comment justifying
`requestPipelineDepth: 3`, the finding that "depth makes no measurable
difference", from eight release runs per arm. Those runs were on loopback, where
RTT is approximately zero — **the one condition under which pipelining cannot
matter by construction.** The measurement was sound and its conclusion does not
transfer. That comment is currently the reason nobody has revisited the
constant, which makes correcting it part of this work.

The depth argument is also capped at 3 by the benchmark's own option parser
(`--stream-shape-request-pipeline-depth 1...3`). At 185 ms RTT, reaching 20 fps
would need a depth near 4, and reaching it at the 500 ms tail would need closer
to 10. The cap was chosen when the only measured path had no round-trip time to
hide, so it has never been evaluated against a path where depth is the dominant
term.

## Requirements

- **FR-001** The network-condition set gains profiles derived from the
  measurement above rather than invented: a median-mobile profile and a
  tail-mobile profile. The RTT samples that produced them are recorded in the
  profile's own source so the next person can see what they describe.
- **FR-002** The conditioning proxy supports **jitter**, not just a fixed delay.
  A twelve-fold spread is the defining feature of this link; a fixed-delay model
  reproduces the mean and none of the behaviour that depends on variance —
  including, specifically, whether `transportIdleTimeoutCount` is firing on
  slow responses rather than dead ones.
- **FR-003** The stream-shape headline figures are re-measured across the
  condition axis in a release build, and no frame-rate claim is recorded anywhere
  in this repository without the condition it was measured under attached.
- **FR-004** The pipeline-depth A/B is re-run under the mobile profiles. The
  benchmark's depth cap is raised for the experiment; whether the **shipped**
  constant changes is decided by that measurement, not by the arithmetic in this
  document.
- **FR-005** The empty-update share is measured as a first-class cost, because at
  this RTT an empty response is not free — it consumes a pipeline slot and a
  round trip. If it is as large as the device export suggests, the lever is
  avoiding wasted round trips, and that is a different fix from raising depth.
- **FR-006** Constitution §IV throughout: counts, ratios, fixed labels and
  aggregate millisecond summaries only.

## Verification Matrix

| Layer | What it proves | Gate |
|---|---|---|
| `swift test` — profile/jitter unit tests | the jitter model produces the intended distribution and is deterministic under a fixed seed | direct |
| Live Mac, release, condition sweep | the fps ceiling tracks depth ÷ RTT | `VNCLiveBenchmark`, release, all profiles |
| Live Mac, release, depth A/B under mobile profiles | whether depth is the dominant term on the real path | **FAIL-first: depth must show a difference here, or the round-trip-bound hypothesis is wrong and this spec's premise fails** |
| Founder device, build 9 | the export's content fps and empty-update share move in the predicted direction | founder device pass |

The third row is the one that can kill this spec. If depth still shows no
difference at 185 ms RTT, the ceiling is not the request loop and the arithmetic
above is a story rather than a diagnosis.

## What The Experiment Actually Found

Three depth arms (1, 2, 3), release build, same gate preset and stimulus, run
under two link conditions. `streamShapeOrderNeutralRecommendation`:

| condition | avg update | idle probe | content fps at depth 1 / 2 / 3 |
|---|---|---|---|
| `none` | 1276 ms | 2-35 ms | 0.78 / 0.79 / 0.79 |
| `tailnet-mobile-median` (184 ms modelled RTT) | 1488 ms | 165 ms | 0.67 / 0.67 / 0.68 |

**Depth does nothing, in either condition.** FR-004's FAIL-first bar — "depth must
show a difference here, or the round-trip-bound hypothesis is wrong" — was not
met, so the hypothesis is rejected rather than the measurement doubted. The
arithmetic in *Why* remains arithmetic: it describes a ceiling that would bind if
nothing else bound first, and something else binds first.

That something is worth naming precisely: **1276 ms per update with no
conditioning at all.** Adding a 184 ms modelled round trip moves it to 1488 ms —
a delta of 212 ms, which is the round trip and nothing more. The network is a
small additive term on top of a per-update cost that is already six times larger.

### The conditioning harness is accurate, and that is now measured

The `none` versus `tailnet-mobile-median` delta (212 ms against 184 ms modelled)
and the idle probe (165 ms against 184 ms modelled) both land where the model
says they should. This matters because it was doubted: the proxy was read as
charging a fresh one-way delay per 16 KB slice, which would have meant every
conditioned measurement in this repository described a link far worse than its
name. A test written to prove that **passed** against the unmodified proxy in
176 ms, and the delta above confirms it independently. The hypothesis was wrong,
and the rewrite it motivated was reverted — it scheduled chunks independently on
an absolute timeline, which with per-chunk jitter lets a later chunk overtake an
earlier one and corrupt the RFB stream rather than merely slow it down.

### A preset was silently overriding an explicit flag

`--network-condition tailnet-mobile-median` passed alongside a gate preset was
discarded: `applyStreamShapeGatePreset` assigned `networkConditionProfile`
unconditionally, and the first "latency" sweep therefore ran under
`constrained-cellular` while reporting numbers as if it had not. The only thing
that caught it was the report echoing back the condition it had actually used.
An explicit flag now wins over a preset's default. Two runs' worth of numbers
were discarded because of this.

The first sweep also showed why `constrained-cellular` cannot answer a latency
question: at its 1 Mbps cap every depth reported 0.55 content fps, because the
link was bandwidth-saturated and extra requests in flight only queued. The
profiles added here leave throughput uncapped for exactly that reason.

### The caveat that limits all of the above

This workload comes from the `sustained-v2-constrained-cellular-app-low-traffic`
preset and yields only four content updates in twelve seconds, with app-side
client-pressure pacing and empty-update backoff both active. A 1.27 s per-update
cost may be that preset pacing itself rather than anything about the transport,
and 0.78 content fps is nowhere near the 17 fps spec 027 measured on the same
machine with a different harness configuration. **The next question is why this
configuration is two orders of magnitude slower than that one**, and until that
is answered these numbers characterise the preset as much as the product.

## Non-Goals

- Changing `requestPipelineDepth` on the strength of the arithmetic. Spec 025
  exists because a single-run difference was nearly shipped as a constant change;
  the same bar applies here, and the arithmetic is a prediction to be tested.
- Helper video. It remains the higher ceiling and is blocked on physical pairing
  (spec 010 T014). This spec is about the VNC path the founder is actually on.
- Reproducing the founder's exact network. The profiles model it; they are not
  it, and a run under a model is evidence about the model.

## Residual Risk

- The RTT samples are one eight-sample burst from one moment on one link. They
  establish the order of magnitude and the presence of large jitter; they are not
  a characterisation of mobile networks, and the profiles inherit that limit.
- `tailscale ping` measures the tailnet path to the phone. The VNC session runs
  the other direction, phone to Mac, over the same tunnel — assumed symmetric,
  which is not verified.
- A conditioning proxy runs on the same machine as the server and the client, so
  it models delay and throughput but not competing traffic, radio state changes,
  or the phone's own scheduling. A run that looks healthy under the model can
  still be unusable on the device.
- Raising the pipeline depth increases the number of requests a server has
  outstanding. Apple Screen Sharing's behaviour under a deeper pipeline is
  unmeasured, and spec 017 already recorded that it does not reliably clip region
  requests under load.
