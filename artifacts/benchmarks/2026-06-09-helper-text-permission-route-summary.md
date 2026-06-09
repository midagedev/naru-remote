# Helper Text Permission Route Summary - 2026-06-09

## Scope

Make `helper-text-live-gate` more useful as a compact Compose input diagnostic
by copying granular route permission states into `liveGateSummary`.

## Result

The current live `NaruHelperDev.app` gate reports:

- Overall gate state: `blockedByHelperTextPermission`
- Permission process kind: `appBundle`
- Permission grant hint: `grantAppBundle`
- Permission request result: `notGranted`
- Permission watch status: `timedOut`
- Native insert ready: `false`
- Accessibility value insert: `missing`
- Unicode keyboard event: `missing`
- Pasteboard fallback: `missing`
- Missing route labels:
  - `accessibility-value-insert-missing`
  - `unicode-keyboard-event-missing`
  - `pasteboard-fallback-missing`
- Observed probe status: `failed`
- Observation status: `no-input`
- Observed safe failure code: `helper.permissionMissing`

Interpretation:

- The selected helper app bundle is installed and is the correct permission
  target, but none of the non-VNC Compose insertion routes are currently
  available.
- The next manual setup step is still granting text insertion permission to
  `NaruHelperDev.app`, relaunching it, and rerunning `helper-text-live-gate`.
- The summary is now sufficient to see the missing route classes without
  expanding the setup, watch, and observed-probe subreports.

## Verification

```bash
bash -n scripts/run-naru-live-benchmark.sh
scripts/run-naru-live-benchmark.sh helper-text-live-gate-summary-self-test
NARU_HELPER_TEXT_PERMISSION_SETTINGS_OPEN=skip \
NARU_HELPER_TEXT_PERMISSION_WATCH_MAX_POLLS=1 \
NARU_HELPER_TEXT_PERMISSION_WATCH_INTERVAL_SECONDS=0 \
NARU_HELPER_TEXT_OBSERVED_PROBE_DURATION_SECONDS=1 \
scripts/run-naru-live-benchmark.sh helper-text-live-gate
```

## Safety

The artifact records only fixed status, route, issue, and action labels. It
does not include helper executable paths, app paths, endpoints, credentials,
raw text, clipboard bytes, focused app titles, raw OS errors, pixels, byte
counts, exact timings, key events, or physical device identifiers.
