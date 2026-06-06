# App Low-Traffic Glance Scale Sweep

Date: 2026-06-06

Purpose: make the app-low-traffic first-frame startup area tunable in the live
benchmark so smaller first-useful-paint candidates can be compared without
editing product code between runs.

## Configuration

- Tool: `VNCLiveBenchmark`
- Schema: v64
- Gate preset: `sustained-v2-constrained-cellular-app-low-traffic`
- Profile selection: `app-low-traffic`
- Profiles compared:
  - `local-low-latency-rgb565`
  - `zrle-compression-0-rgb565`
- Network condition: `constrained-cellular`
- Transport: request/response
- First-frame request mode: `visible-glance`
- Sustained request area: 364 permille
- Scale candidates:
  - 0.35, reported as 350 permille
  - 0.25, reported as 250 permille
- Stimulus: redacted external command through the live benchmark environment

The reports did not emit host, password, server name, framebuffer dimensions,
pixel payloads, byte counts, command text, coordinates, cursor pixels, draft
text, marked text, or IME state.

## Live Result

The prior app default candidate was 0.45, with a 61 permille first-frame request
area and about 8.1-8.2 s first-frame payload read. The benchmark-only scale
override showed that smaller startup regions continue to reduce payload-read
time while preserving the sustained 4/4 content sample shape in this run.

| Scale | First-frame area | Profile | First-frame total | Payload read | Sustained samples | Avg/P95 update | Full upload |
| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 0.35 | 37 permille | `local-low-latency-rgb565` | 8.0 s | 6.7 s | 4/4 | 505/612 ms | 0 permille |
| 0.35 | 37 permille | `zrle-compression-0-rgb565` | 8.1 s | 6.7 s | 4/4 | 515/649 ms | 0 permille |
| 0.25 | 19 permille | `local-low-latency-rgb565` | 6.3 s | 5.1 s | 4/4 | 492/624 ms | 0 permille |
| 0.25 | 19 permille | `zrle-compression-0-rgb565` | 6.2 s | 5.1 s | 4/4 | 468/616 ms | 0 permille |

Both scale candidates still failed the poor-network profile gate on
`first-frame-payload-read-failed`. The per-profile sustained assessment moved
the remaining pressure to first-byte wait and update latency warnings rather
than payload-read latency.

## Decision

Keep the product app default at the already-merged 0.45 until a device visual
check proves that a smaller first-useful-paint patch is still useful to a real
iPhone user. Keep the new benchmark override so the next product-default PR can
compare 0.35 and 0.25 without recompiling between trials.

The next practical unit should pair this scale sweep with screenshot/device
inspection of first-useful-paint quality. If 0.25 looks too small, 0.35 is the
safer candidate; if it remains recognizable, 0.25 is the stronger poor-network
startup traffic candidate.
