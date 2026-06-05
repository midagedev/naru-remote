# 2026-06-06 Live Preflight Action Hints Summary

Target: `iphone-sustained-usability-v2`

## Purpose

The sustained usability contract requires live benchmark gates before physical
iPhone promotion, but a missing host or controlled stimulus command can stop the
loop before any VNC samples are collected. This increment makes
`VNCLiveBenchmark --environment-preflight` more actionable while preserving the
redaction boundary.

## What Changed

- Environment preflight schema is now v2.
- Reports include `setupActionLabels`, a fixed-label list that says what to do
  next without printing configured values.
- Current labels:
  - `set-naru-live-mac-host`
  - `fix-naru-live-mac-port`
  - `provide-credential-or-ask-password`
  - `set-naru-live-stimulus-command`
  - `run-live-gate`
- Text output now prints the same setup action labels.
- v1 JSON without `setupActionLabels` still decodes and derives the matching
  action labels from the existing status fields.

## Current Local Preflight

The local shell still lacks live target setup:

- issue codes: `missing-host`, `missing-stimulus-command`
- safe setup actions: `set-naru-live-mac-host`,
  `set-naru-live-stimulus-command`

No live VNC session or password prompt was attempted for this artifact.

## Verification

- `swift test --filter BenchmarkLiveEnvironmentPreflightTests`
- `swift run VNCLiveBenchmark --environment-preflight
  --stream-shape-gate-preset sustained-v2-core --ask-password --json`

## Safe Reporting

Preflight output may include fixed status labels, fixed issue codes, and fixed
setup action labels only. Do not store host identity, credentials, port values,
stimulus command text, raw TCP/RFB errors, framebuffer dimensions, coordinates,
pixels, cursor pixels, byte counts, raw payloads, raw FPS, raw timings, command
output, draft text, marked text, or IME state.
