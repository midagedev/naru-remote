# ContinuousUpdates Confirmation Gate Smoke — 2026-06-06

## Purpose

Verify that a live ContinuousUpdates benchmark no longer treats
request/response fallback as a successful ContinuousUpdates transport when the
server has not confirmed the extension.

## Setup

- Benchmark schema: v43
- Profile selection: `local-low-latency`
- Transport selection: `continuous-updates`
- Gate preset: none
- Stimulus mode: off
- Live target details: redacted

## Result

- Stream-shape profile gate verdict: `fail`
- ContinuousUpdates status: `failed-before-samples`
- ContinuousUpdates failure label count:
  `stream-continuous-updates-continuous-updates-not-confirmed=1`
- ContinuousUpdates standalone probe status: `failed`
- ContinuousUpdates standalone failure label:
  `continuous-probe-enable-continuous-updates-not-confirmed`
- Recommended next action: `inspectContinuousUpdatesConnection`
- Request-response status in this smoke: `not-tested`

## Interpretation

The confirmation gate is working for the live target used in this smoke:
ContinuousUpdates remains in the comparison surface, but an unconfirmed server
extension path is reported as a compatibility investigation item instead of
being hidden by request/response fallback. Production streaming should continue
to use the request/response fallback until the sustained-usability promotion
ladder reaches a benchmark-green and physical-iPhone-green result.

## Privacy

This artifact intentionally omits host identity, credentials, port value, raw
TCP/RFB errors, framebuffer dimensions, coordinates, pixels, cursor pixels,
byte counts, raw payloads, raw FPS, raw timings, command text, command output,
draft text, marked text, and IME state.
