# First-Byte Wait Split Summary — 2026-06-06

This artifact records the first schema v50 first-byte wait split run for the
sustained v2 request/response ZRLE pacing sweep. It keeps the v49 phase-budget
shape and splits the measured `network-read` bucket into first-byte wait and
payload-read subphases.

## Commands

```sh
swift build --product VNCLiveStimulusWindow
NARU_LIVE_MAC_HOST=127.0.0.1 \
NARU_LIVE_STIMULUS_COMMAND='.build/debug/VNCLiveStimulusWindow --duration "$NARU_LIVE_STIMULUS_DURATION_SECONDS"' \
swift run VNCLiveBenchmark \
  --ask-password \
  --stream-shape-gate-preset sustained-v2-zrle-pacing-sweep \
  --json > /tmp/naru-first-byte-v50.json
```

Focused verification:

```sh
swift test --filter RFBRawFramebufferDecoderTests
swift test --filter BenchmarkStreamShapeSummaryTests
swift test --filter FakeRFBServerIntegrationTests/testContinuousReceiveTimeoutReturnsIdleFrameAndKeepsConnectionUsable
swift test --filter RFBFramePumpTests
swift run VNCLiveBenchmark --help | rg -n "schema v50|first-byte wait|phase-budget"
```

## Result

- `schemaVersion`: 50
- request cadence health:
  - `sampleStatus`: `high-content-hit`
  - `latencyStatus`: `p95-failed`
  - `recommendedNextProbe`: `inspectUpdateWaitTiming`
  - `dominantPhase`: `network-read`
  - `slowDominantPhase`: `network-read`
  - `networkReadDominantSubphase`: `first-byte-wait`
  - `slowNetworkReadDominantSubphase`: `first-byte-wait`
  - average first-byte/payload split: `1000/1` permille
  - max first-byte/payload p95: `503/1` ms
  - average update: `140` ms
  - max p95 update: `505` ms
  - average content FPS: `4.83`

| Pacing window | Usable runs | Content FPS | Avg update ms | Max p95 update ms | Phase shares network/client/request | Split first-byte/payload | Max p95 first-byte/payload |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| `zero-content-delay` | 5 | 6.40 | 127 | 505 | 912/87/2 | 1000/1 | 503/1 ms |
| `app-balanced-30hz` | 5 | 4.82 | 135 | 502 | 967/31/2 | 1000/1 | 501/1 ms |
| `stimulus-aligned-12hz` | 4 | 3.26 | 157 | 436 | 974/24/2 | 1000/0 | 434/0 ms |

The `stimulus-aligned-12hz` window had one failed run with the fixed safe label
`stream-connect-read-timeout`; aggregate numbers above use the four usable runs.

## Interpretation

The v49 `network-read` tail is almost entirely first-byte wait. Payload read is
effectively negligible in this localhost macOS Screen Sharing run.

The next large optimization unit should target server/update wait in the
request/response loop rather than socket payload buffering or decoder payload
copy work. Candidate lanes are request region/stimulus shape, outstanding
request policy, and a separately gated ContinuousUpdates/Fence follow-up only if
server confirmation and compatibility evidence remain clean.

## Privacy

This artifact intentionally records only fixed labels, aggregate counts,
aggregate millisecond summaries, and aggregate permille shares. It does not
include host identity, credentials, port values, framebuffer dimensions,
coordinates, pixels, cursor pixels, byte counts, raw TCP/RFB errors, raw
payloads, per-sample raw timings, raw FPS, stimulus command output, draft text,
marked text, IME state, or full diagnostic payloads.
