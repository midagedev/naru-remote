# 2026-06-04 Timed Profile Receive Comparison

Purpose: use schema v19 receive-path timing to compare the current production
`local-low-latency` profile against the `zrle-compression-0` candidate before
changing any static encoding default for sustained iPhone sessions.

Safety boundary: this artifact stores only aggregate benchmark output. It omits
host, password, server name, framebuffer dimensions, coordinates, pixels, byte
counts, cursor pixels, raw error descriptions, and raw per-frame samples.

Research note: see
`specs/004-rfb-encodings/research.md` D19 for the production-default decision
derived from this artifact.

## Command Shape

Normal pacing:

```sh
NARU_LIVE_MAC_HOST=127.0.0.1 swift run VNCLiveBenchmark \
  --attempts 1 \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 20 \
  --stream-shape-profiles local-low-latency,zrle-compression-0 \
  --stream-shape-transport request-response \
  --stream-shape-power-mode normal \
  --continuous-update-samples 1 \
  --timeout 8 \
  --idle-timeout 0.75 \
  --ask-password
```

Low-power pacing used the same command shape with
`--stream-shape-power-mode low-power`.

## Normal Pacing

| Profile | Status | Content FPS | Update avg / p95 / max | Receive avg / p95 / max | Network avg / p95 / max | Client avg / p95 / max | Full uploads | Slow samples |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | mixed, 138/138 | 6.05 | 120 / 475 / 2254 ms | 118 / 475 / 2253 ms | 99 / 473 / 519 ms | 19 / 12 / 2040 ms | 8 permille | 19 / 138 |
| `zrle-compression-0` | mixed, 141/141 | 5.90 | 113 / 478 / 513 ms | 112 / 477 / 511 ms | 99 / 474 / 507 ms | 12 / 98 / 146 ms | 0 permille | 18 / 141 |

Normal takeaway: the benchmark recommendation selected `zrle-compression-0`
because it had lower average update latency and avoided full uploads. The
current `local-low-latency` profile still had slightly higher content FPS and a
large single full-dirty/full-upload outlier, visible in `client processing max`.

## Low-Power Pacing

| Profile | Status | Content FPS | Update avg / p95 / max | Receive avg / p95 / max | Network avg / p95 / max | Client avg / p95 / max | Full uploads | Slow samples |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency` | failed | n/a | `stream-incremental-read-timeout` | n/a | n/a | n/a | n/a | n/a |
| `zrle-compression-0` | mixed, 69/69 | 2.90 | 233 / 501 / 2863 ms | 231 / 500 / 2863 ms | 162 / 496 / 670 ms | 69 / 16 / 2193 ms | 34 permille | 17 / 69 |

Low-power takeaway: `zrle-compression-0` was the only successful profile in
this short run, but it still produced two full-upload/full-dirty outliers. The
current production profile timed out, so this run is useful as a warning signal,
not as a stable default-selection proof.

## Decision

Do not change the static production encoding default from this evidence alone.
The receive split shows two different sources of pain:

- most p95 update latency still tracks network/server read wait, not local
  client processing;
- rare full-dirty/full-upload frames can dominate client-processing max and
  should be tracked separately in longer physical-device runs.

Next practical-usability work should run longer physical iPhone sessions with
screen activity held constant, compare `local-low-latency` and
`zrle-compression-0` under normal and power-saver modes, and only then consider
profile-specific selection or adaptive switching.
