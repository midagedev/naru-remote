# Request/Response Pipeline Benchmark Summary

Date: 2026-06-06 KST

## Change

- Added a benchmark-only send-only `FramebufferUpdateRequest` boundary to
  `RFBNetworkClient`.
- Added `VNCLiveBenchmark --stream-shape-request-pipeline-depth 1...3`.
- Bumped `VNCLiveBenchmark` output schema to v66.
- Kept production app frame delivery unchanged: depth 1 remains the existing
  send-then-receive request/response baseline.

## Why

The constrained-cellular app-low-traffic live gate showed the sustained stream
is dominated by first-byte wait, not by request-loop, payload-read,
client-processing, or renderer-upload pressure. RFC 6143 allows multiple
`FramebufferUpdateRequest` messages to be outstanding, and a single
`FramebufferUpdate` may satisfy multiple requests. That makes bounded
request-pipeline depth a protocol-compatible live experiment before considering
any product default change.

## Safety

- Depth is clamped to 1...3.
- Depth above 1 is rejected for `continuous-updates`.
- Region-timeout fallback clears the requested region but stays incremental;
  it is not a forced non-incremental full refresh.
- Reports emit only the clamped depth integer plus existing aggregate
  timing/permille fields.
- Reports do not emit outstanding-request coordinates, dimensions, byte
  counts, pixels, payloads, host identity, credentials, command text, draft
  text, marked text, or IME state.
- Live credentials stay in environment variables. Do not pass or print the
  password on the command line.

## Live Compare Command Shape

Run the same preset three times, changing only depth:

```bash
NARU_LIVE_MAC_HOST="$(launchctl getenv NARU_LIVE_MAC_HOST)" \
NARU_LIVE_MAC_PORT="$(launchctl getenv NARU_LIVE_MAC_PORT)" \
NARU_LIVE_MAC_PASSWORD="$(launchctl getenv NARU_LIVE_MAC_PASSWORD)" \
NARU_LIVE_STIMULUS_COMMAND="$(launchctl getenv NARU_LIVE_STIMULUS_COMMAND)" \
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
  --stream-shape-first-frame-visible-glance-scale 0.25 \
  --stream-shape-request-pipeline-depth 1 \
  --json
```

Then repeat with depths `2` and `3`.

## Promotion Boundary

Depth 2 or 3 may become an app candidate only if it reduces sustained
first-byte wait and update latency under the same controlled stimulus without
regressing content hit rate, first-frame traffic, client processing, renderer
upload pressure, thermal behavior, or physical iPhone hand-feel. Until then it
is a benchmark-only research result.

## Live Result

Same v66 build, constrained-cellular app-low-traffic preset, visible-glance
scale 0.25:

| Depth | Profile | Content | FPS | Avg/P95 update ms | First-byte P95 ms | First-frame payload ms | Full upload permille | Verdict |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | local-low-latency-rgb565 | 4/4 | 2.75 | 364/579 | 577 | 5089 | 0 | fail |
| 1 | zrle-compression-0-rgb565 | 3/4 | 1.31 | 556/927 | 599 | 5038 | 333 | fail |
| 2 | local-low-latency-rgb565 | 4/4 | 1.90 | 524/614 | 610 | 5135 | 0 | fail |
| 2 | zrle-compression-0-rgb565 | 4/4 | 2.11 | 473/616 | 607 | 5060 | 0 | fail |
| 3 | local-low-latency-rgb565 | 4/4 | 2.48 | 402/623 | 618 | 5053 | 0 | fail |
| 3 | zrle-compression-0-rgb565 | 4/4 | 1.96 | 509/635 | 629 | 5126 | 0 | fail |

All depths still failed the poor-network profile gate with
`first-frame-payload-read-failed` as the primary issue. Depth 2/3 did not reduce
the sustained first-byte tail versus the depth 1 local-low-latency RGB565
baseline, so request pipelining should remain benchmark-only for now.
