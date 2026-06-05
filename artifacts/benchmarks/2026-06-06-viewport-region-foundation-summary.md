# Viewport Region Foundation Summary

Date: 2026-06-06 KST

Command shape:

```bash
NARU_LIVE_MAC_HOST=... \
NARU_LIVE_STIMULUS_COMMAND='...' \
swift run VNCLiveBenchmark --ask-password \
  --stream-shape-gate-preset sustained-v2-zrle-viewport-region \
  --json
```

Report schema: v52 for the live run below. The implementation follow-up in this
PR bumps future reports to schema v53 by adding the redacted
`requestRegionAreaPermille` traffic-pressure proxy.

Preset:

- `sustained-v2-zrle-viewport-region`
- Profile: `zrle-compression-0-clipboard`
- Transport: `request-response`
- Pacing window: `single`
- Request regions: `full`, `viewport-phone-portrait`,
  `viewport-phone-portrait-heartbeat`
- Iterations: 5, rotated
- Controlled stimulus cadence: 12 Hz

## Result

The only stable candidate remained `full`.

| Request region | Usable/total | Failed | Avg update ms | Max p95 ms | Content FPS | Received/content samples | Full-upload permille | Failure labels |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `full` | 5/5 | 0 | 124 | 501 | 6.76 | 384/338 | 0 | none |
| `viewport-phone-portrait` | 1/5 | 4 | 116 | 493 | 6.91 | 81/70 | 0 | `stream-incremental-not-connected` x4 |
| `viewport-phone-portrait-heartbeat` | 0/5 | 5 | n/a | n/a | n/a | 0/0 | n/a | `stream-incremental-not-connected` x5 |

Request cadence health:

- sample status: `high-content-hit`
- latency status: `p95-failed`
- recommended next probe: `inspectUpdateWaitTiming`
- dominant phase: `network-read`
- dominant network-read subphase: `first-byte-wait`
- average first-byte/payload split: `1000/1` permille
- max first-byte/payload p95: `501/0` ms

Report-level decision:

- optimization verdict: `fail`
- primary issue: `probe-failed`
- primary constraint: `receivePath`
- recommended next probe: `inspectServerTransportCadence`
- transport diagnosis next action: `tuneTransportCadence`

## Interpretation

Viewport-derived regions are a better product model than static center regions,
but this benchmark does not justify a production default change. The
phone-portrait viewport candidate produced one usable run and four failed runs,
while the heartbeat/fallback candidate failed every run.

The failure label indicates the current request/response connection is not yet
robust enough to recover from this region experiment by simply following with a
full request. The next large unit should inspect request/response transport
cadence and region-timeout recovery semantics before app-side viewport request
regions are enabled.

Until that is solved, production request/response streaming should keep
full-framebuffer incremental requests.

## Traffic Goal

Viewport-aware regions are expected to help traffic because they let the client
ask for only the visible framebuffer area instead of the whole desktop. That
goal is now explicit: future schema v53 reports include
`requestRegionAreaPermille`, a 0...1000 requested-area ratio where `full` is
1000 and narrower regions should be lower.

This remains a promotion gate, not an automatic win. A candidate must reduce
requested-area pressure while keeping usable runs, hit-rate, p95 update tail,
failure labels, and fallback/heartbeat behavior at least as stable as the
incumbent full-request path.

## Privacy

This artifact intentionally omits target identity, credentials, port values,
framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts, raw
TCP/RFB errors, raw payloads, per-sample raw timings, raw FPS, stimulus command
text, command output, draft text, marked text, IME state, and full diagnostic
payloads.
