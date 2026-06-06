# Degraded Network Benchmark Harness Summary

Date: 2026-06-06

## Scope

This artifact records the first schema v55 live smoke for the benchmark-local
network conditioning proxy. The goal is to make poor-network traffic work
measurable without changing OS-wide networking or exporting target details.

Command shape:

```sh
swift run VNCLiveBenchmark \
  --ask-password \
  --network-condition wan-latency \
  --first-frame-profiles none \
  --stream-shape-profiles zrle-compression-0-clipboard \
  --stream-shape-transport request-response \
  --stream-shape-request-region viewport-phone-portrait \
  --stream-shape-samples 12 \
  --stream-shape-stimulus external-command \
  --continuous-update-samples 0 \
  --full-refresh-samples 0 \
  --attempts 1 \
  --timeout 8 \
  --idle-timeout 1.5 \
  --json
```

The target host, credential, proxy port, upstream host, framebuffer dimensions,
coordinates, pixels, byte counters, raw TCP/RFB errors, command output, and raw
payloads were not recorded in this artifact.

## Result

- `schemaVersion`: 55
- `networkCondition`: `wan-latency`
- `streamShapeProfiles`: `zrle-compression-0-clipboard`
- `streamShapeTransportModes`: `request-response`
- `streamShapeRequestRegions`: `viewport-phone-portrait`
- `requestRegionAreaPermille`: 364
- Failure label: none
- Attempted / received / content samples: 12 / 12 / 11
- Delivered FPS: 1.62
- Content FPS: 1.48
- Average update latency: 580 ms
- P95 update latency: 1928 ms
- Average first-byte wait: 451 ms
- P95 first-byte wait: 590 ms
- Request cadence health:
  - sample status: `high-content-hit`
  - latency status: `p95-failed`
  - dominant phase: `network-read`
  - dominant network-read subphase: `first-byte-wait`
  - recommended next probe: `compareRequestResponseEncodingProfiles`

## Interpretation

The local TCP conditioning proxy is now usable for poor-network VNC comparisons:
the report emits only the fixed `networkCondition` label, the conditioned VNC
path completed without reconnect/failure labels, and the latency profile shifts
to first-byte wait as intended.

This smoke is intentionally short. It does not promote viewport request regions
or any production default by itself. It gives the next traffic PR a repeatable
way to compare region, encoding, pacing, and pixel-format candidates under a
controlled degraded link instead of relying only on localhost behavior.

