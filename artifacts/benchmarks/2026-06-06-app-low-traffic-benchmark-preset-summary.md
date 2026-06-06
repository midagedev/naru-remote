# App Low-Traffic Benchmark Preset Summary — 2026-06-06

## Scope

- Adds a focused poor-network benchmark gate for the app's opt-in low-traffic
  VNC stream profile.
- New profile selection: `app-low-traffic`.
- New gate preset: `sustained-v2-constrained-cellular-app-low-traffic`.

## Preset Shape

- Network condition: `constrained-cellular`.
- Practical target: `iphone-poor-network-traffic-v1`.
- Transport: request/response.
- First-frame request mode: `visible-focus`.
- Sustained request region: phone-portrait viewport region.
- Stream profile matrix: only `zrle-compression-0-rgb565`.
- Samples: four sustained content samples per profile run.

## Why

The broader constrained-cellular visible-focus preset remains useful for
comparing full-color and RGB565 candidates, but full-color first-frame failures
can dominate the report. This focused preset measures the same fixed label the
app exposes as its low-traffic opt-in profile, so live CLI and physical iPhone
runs can evaluate the actual user-selectable traffic candidate.

## Verification

- `swift test --filter BenchmarkStreamShapeProfileSelectionTests --filter BenchmarkStreamShapeGatePresetTests`
  passed: 19 tests, 0 failures.
- `swift run VNCLiveBenchmark --help` lists both
  `sustained-v2-constrained-cellular-app-low-traffic` and `app-low-traffic`.
- `swift test` passed: 956 tests executed, 10 skipped, 0 failures.

## Promotion Rule

This is not a production-default promotion. A default-changing PR still needs
the sustained-usability benchmark gate, the poor-network traffic gate, and a
physical iPhone hand-feel/thermal/Compose pass. The preset is intended to decide
whether the next large unit should focus on first-useful-paint traffic,
sustained update-wait/cadence, or another encoding/profile candidate.

## Privacy

Artifacts for this preset may include fixed labels, aggregate verdicts,
aggregate timing summaries, and permille traffic proxies only. They must not
store host identity, credentials, device identifiers, ports, framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, raw samples, raw
payloads, raw errors, command text, command output, draft text, marked text, or
IME state.
