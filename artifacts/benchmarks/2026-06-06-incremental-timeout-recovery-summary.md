# Incremental Timeout Recovery Benchmark Summary

Date: 2026-06-06

## Scope

This run validates schema v54 request/response behavior after incremental
`FramebufferUpdateRequest` zero-byte read timeouts became recoverable idle
frames. The goal is poor-network traffic work: viewport-aware request regions
must reduce requested framebuffer area without turning region misses into
disconnect/reconnect artifacts.

Command shape:

```sh
swift run VNCLiveBenchmark \
  --ask-password \
  --stream-shape-gate-preset sustained-v2-zrle-viewport-region \
  --json
```

The target host, credential, framebuffer dimensions, coordinates, pixels, byte
counts, raw TCP/RFB errors, command output, and raw payloads were not recorded
in this artifact.

## Result

- `schemaVersion`: 54
- `streamShapeGatePreset`: `sustained-v2-zrle-viewport-region`
- `streamShapeProfiles`: `zrle-compression-0-clipboard`
- `streamShapeTransportModes`: `request-response`
- `streamShapePracticalTarget`: `iphone-sustained-usability-v2`
- Request regions: `full`, `viewport-phone-portrait`,
  `viewport-phone-portrait-heartbeat`
- All 15 request-region runs completed without a safe failure label.
- Prior v52 evidence showed viewport region candidates collapsing into
  `stream-incremental-not-connected`; this v54 run removes that reconnect
  artifact.

| Request region | Runs | Avg request area permille | Attempted | Received | Content updates | Avg content FPS | Avg update ms | Max p95 update ms | Max p95 first-byte wait ms | Failures |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `full` | 5 | 1000 | 378 | 378 | 328 | 6.56 | 127 | 514 | 507 | 0 |
| `viewport-phone-portrait` | 5 | 364 | 383 | 383 | 330 | 6.55 | 123 | 509 | 508 | 0 |
| `viewport-phone-portrait-heartbeat` | 5 | 491 | 414 | 414 | 365 | 7.22 | 116 | 505 | 505 | 0 |

Top-level request cadence health remained `high-content-hit` /
`p95-failed`, with `network-read` and `first-byte-wait` still dominant. That
means the next bottleneck is still server/update wait timing rather than
payload read, client decode, or reconnect churn.

## Interpretation

Viewport-aware request regions are now measurable as traffic candidates instead
of being masked by connection teardown. `viewport-phone-portrait` requested
about 36.4% of full-frame area while matching the full candidate's content FPS
and failure profile. The heartbeat variant requested about 49.1% of full-frame
area and delivered the strongest content FPS in this local run.

This is not enough to enable request regions as a production default. The p95
tail still misses the sustained usability target, and the physical iPhone
thermal/interaction gate has not passed. The next large unit should compare
region candidates under degraded-network simulation and continue attacking
first-byte wait/server update cadence.

