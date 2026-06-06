# App Low-Traffic Glance Scale Tuning

Date: 2026-06-06

Purpose: reduce first-useful-paint payload pressure for the app low-traffic
path while preserving sustained viewport-aware streaming behavior.

## Configuration

- Tool: `VNCLiveBenchmark`
- Schema: v63
- Gate preset: `sustained-v2-constrained-cellular-app-low-traffic`
- Profile selection: `app-low-traffic`
- Profiles compared:
  - `local-low-latency-rgb565`
  - `zrle-compression-0-rgb565`
- Network condition: `constrained-cellular`
- Transport: request/response
- First-frame request mode: `visible-glance`
- Startup glance scale: 0.45
- First-frame request area: 61 permille
- Sustained request area: 364 permille
- Stimulus: redacted external command through the live benchmark environment

The report did not emit host, password, server name, framebuffer dimensions,
pixel payloads, byte counts, command text, coordinates, cursor pixels, draft
text, marked text, or IME state.

## Live Result

Compared with the prior 0.60 visible-glance app-low-traffic run, the first-frame
request area dropped from 108 to 61 permille. First-frame payload read improved
from about 10.4 s to about 8.1-8.2 s.

| Metric | `local-low-latency-rgb565` | `zrle-compression-0-rgb565` |
| --- | ---: | ---: |
| First-frame total | about 9.6 s | about 9.5 s |
| First-frame network read | about 9.1 s | about 9.1 s |
| First-frame payload read | about 8.2 s | about 8.1 s |
| First-frame request area | 61 permille | 61 permille |
| Sustained request area | 364 permille | 364 permille |
| Received samples | 4/4 | 4/4 |
| Content samples | 4/4 | 4/4 |
| Content FPS | 2.26 | 2.19 |
| Average update latency | 443 ms | 457 ms |
| P95 update latency | 626 ms | 620 ms |
| Max client-processing p95 | 13 ms | 12 ms |
| Max payload-read p95 | 0 ms | 0 ms |
| Renderer full-upload pressure | 0 permille | 0 permille |

The order-neutral recommendation remained `local-low-latency-rgb565` because it
had the lower average update latency in this run.

## Rejected Hydration Experiment

A local uncommitted experiment tried to keep the first 0.60 glance and then
hydrate the larger viewport region with a second non-incremental startup
request. Under the same constrained-cellular gate, that second request timed
out before sustained samples and produced a safe failure label of
`stream-incremental-not-connected`.

That experiment was not kept. It would make startup less reliable unless a
separate timeout/cadence strategy exists for the hydration request.

## Decision

Keep the simpler 0.45 startup glance scale in the app and benchmark kit. This
is still not a production-default promotion: the poor-network gate fails on
first-frame payload-read pressure, so the next unit should investigate startup
transport/cadence or lower-cost initial representations.
