# Request Region Sweep Summary

Date: 2026-06-06 KST

Command shape:

```bash
NARU_LIVE_MAC_HOST=... \
NARU_LIVE_STIMULUS_COMMAND='...' \
swift run VNCLiveBenchmark --ask-password \
  --stream-shape-gate-preset sustained-v2-zrle-region-sweep \
  --json
```

Report schema: v51

Preset:

- `sustained-v2-zrle-region-sweep`
- Profile: `zrle-compression-0-clipboard`
- Transport: `request-response`
- Pacing window: `single`
- Request regions: `full`, `center-half`, `center-third`
- Iterations: 5, rotated
- Controlled stimulus cadence: 12 Hz

## Result

The only usable candidate was `full`.

| Request region | Usable/total | Avg update ms | Max p95 ms | Content FPS | Received/content samples | Full-upload permille | Dominant phase | Network subphase |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `full` | 5/5 | 120 | 505 | 6.68 | 384/334 | 0 | `network-read` | `first-byte-wait` |
| `center-half` | 0/5 | n/a | n/a | n/a | 0/0 | n/a | `unknown` | `unknown` |
| `center-third` | 0/5 | n/a | n/a | n/a | 0/0 | n/a | `unknown` | `unknown` |

Gate verdicts:

- `full`: fail, with mixed content-FPS / p95 / client-processing pressure.
- `center-half`: fail, `probe-failed`, failure label `stream-incremental-read-timeout`.
- `center-third`: fail, `probe-failed`, failure label `stream-incremental-read-timeout`.

Request cadence health:

- sample status: `high-content-hit`
- latency status: `p95-failed`
- recommended next probe: `inspectUpdateWaitTiming`
- dominant phase: `network-read`
- dominant network-read subphase: `first-byte-wait`
- average first-byte/payload split: `1000/0` permille
- max first-byte/payload p95: `505/0` ms

## Interpretation

Static center-region incremental requests are not safe as a production default.
In this controlled run they starved the stream because the requested region was
not coupled to the changing content or the user's actual visible viewport.

The next request-region optimization should be viewport-aware and should include
a full-request fallback or heartbeat after region timeouts. Until that exists,
the production request/response stream should keep full-framebuffer incremental
requests.

## Privacy

This artifact intentionally omits target identity, credentials, port values,
framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts, raw
TCP/RFB errors, raw payloads, per-sample raw timings, raw FPS, stimulus command
text, command output, draft text, marked text, IME state, and full diagnostic
payloads.
