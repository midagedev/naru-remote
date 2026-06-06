# App Low-Traffic Visual Audit

Date: 2026-06-06

Purpose: keep the live benchmark scale sweep usable for startup traffic work
while making the visual risk of very small first-useful-paint patches explicit
before any product-default promotion.

## Configuration

- Tool: `VNCLiveBenchmark`
- Schema: v65
- Gate preset: `sustained-v2-constrained-cellular-app-low-traffic`
- Profile selection: `app-low-traffic`
- Network condition: `constrained-cellular`
- Transport: request/response
- First-frame request mode: `visible-glance`
- Visual audit model: `synthetic-terminal-grid`

The report does not emit host, password, server name, framebuffer dimensions,
pixel payloads, byte counts, command text, coordinates, cursor pixels, draft
text, marked text, or IME state. The audit emits only fixed labels and
coverage permille values derived from the configured scale.

## Synthetic Coverage

The audit is a safe coverage proxy, not a screenshot analyzer. It models how
much of the fixed visible-core area the initial `visible-glance` patch covers
before the sustained viewport-aware requests resume.

| Scale | Axis coverage | Area coverage | Omitted area | Risk label | Visual check |
| ---: | ---: | ---: | ---: | --- | --- |
| 0.25 | 250 permille | 63 permille | 937 permille | `glance-only` | required |
| 0.35 | 350 permille | 123 permille | 877 permille | `minimal-context` | required |
| 0.45 | 450 permille | 203 permille | 797 permille | `central-context` | not required by audit |

## Live Result

The v65 live audit run kept the 0.25 traffic shape from the v64 sweep and
recorded the synthetic visual-risk fields in the same redacted report. The
overall poor-network traffic verdict improved to `warning` with
`first-frame-payload-read-warning`; there were no failed profile gates in this
run.

| Profile | First-frame area | First-frame total | Payload read | Sustained samples | Avg/P95 update | Full upload |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `local-low-latency-rgb565` | 19 permille | 6.1 s | 4.9 s | 4/4 | 482/625 ms | 0 permille |
| `zrle-compression-0-rgb565` | 19 permille | 6.1 s | 4.9 s | 4/4 | 522/662 ms | 0 permille |

The 0.25 candidate is now the strongest measured startup traffic candidate, but
the v65 audit adds the missing visual-risk label: it is a glance-only patch and
should not be promoted from benchmark candidate to product default without real
iPhone visual inspection.

## Decision

Keep the product app default at 0.45 for now. Continue using 0.25 and 0.35 as
benchmark-only poor-network startup candidates, but require device screenshot
or direct iPhone inspection before changing the app default. If 0.25 is not
recognizable, 0.35 is the next candidate; if both are too sparse, keep 0.45 and
move the startup optimization effort to transport cadence or a cheaper initial
representation.
