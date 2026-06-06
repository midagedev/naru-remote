# App Low-Traffic RGB565 Profile Comparison

Date: 2026-06-06

Purpose: compare the two app-side RGB565 low-traffic candidates after the
visible-glance startup policy, using the same redacted live poor-network gate
that the app profile toggle is meant to exercise.

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
- First-frame request area: 108 permille
- Sustained request area: 364 permille
- Stimulus: redacted external command through the live benchmark environment

The report did not emit host, password, server name, framebuffer dimensions,
pixel payloads, byte counts, command text, coordinates, cursor pixels, draft
text, marked text, or IME state.

## Live Result

The preset correctly expanded `app-low-traffic` to both app RGB565 candidates
and selected `local-low-latency-rgb565` as the recommendation.

| Metric | `local-low-latency-rgb565` | `zrle-compression-0-rgb565` |
| --- | ---: | ---: |
| Received samples | 4/4 | 4/4 |
| Content samples | 4/4 | 3/4 |
| Content sample permille | 1000 | 750 |
| Content FPS | 2.27 | 1.18 |
| Average update latency | 440 ms | 622 ms |
| P95 update latency | 617 ms | 1282 ms |
| Max client-processing p95 | 4 ms | 119 ms |
| Max payload-read p95 | 0 ms | 472 ms |
| Renderer full-upload pressure | 0 permille | 333 permille |
| Very-slow update samples | 0 | 1 |

First-frame payload read remained the main blocker for both candidates:

| Metric | `local-low-latency-rgb565` | `zrle-compression-0-rgb565` |
| --- | ---: | ---: |
| First-frame total | about 11.9 s | about 12.0 s |
| First-frame network read | about 11.3 s | about 11.3 s |
| First-frame payload read | about 10.4 s | about 10.4 s |

## Same-Day Rotate Check

Before the app preset was wired to compare both labels, a two-iteration
rotating comparison showed the same direction:

- `local-low-latency-rgb565`: 8/8 content samples, average update about
  424 ms, p95 update about 617 ms, content FPS about 2.37, and 0 permille
  renderer full-upload pressure.
- `zrle-compression-0-rgb565`: 6/8 content samples, average update about
  537 ms, p95 update about 1134 ms, content FPS about 1.37, and 250 permille
  renderer full-upload pressure.

## Decision

Add `local-low-latency-rgb565` as an app opt-in mode and include it in the
`app-low-traffic` benchmark selection beside `zrle-compression-0-rgb565`.

This is not a production-default promotion. The overall poor-network gate still
failed with `first-frame-payload-read-failed`, so the next optimization unit
should focus on startup payload/cadence reduction while keeping
`local-low-latency-rgb565` available for app-side sustained hand-feel testing.
