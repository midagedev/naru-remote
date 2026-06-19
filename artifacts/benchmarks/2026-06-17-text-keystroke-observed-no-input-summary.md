# Text Keystroke Observed No-Input Refresh - 2026-06-17

## Scope

This artifact records the current observed VNC KeyEvent fallback behavior
against a controlled local Mac text target.

This is not a Compose native insertion pass, physical iPhone input pass, or
proof that decomposing composed Korean text into key events is viable. It is a
diagnostic comparison between ASCII and Hangul payloads after adding an
observed-probe focus prelude.

## Probe Adjustment

The observed text-keystroke probe now performs a pointer focus prelude before
sending key events:

- It launches the controlled local text target.
- It receives the first VNC framebuffer.
- It computes the text target's fixed center in RFB coordinates without
  exporting coordinates.
- It sends pointer move/down/up to focus the target.
- It then sends the KeyEvent sequence.

The report safety copy now states that observed mode may enqueue a pointer
focus prelude and still omits coordinates, keysyms, text, dimensions, pixels,
endpoints, credentials, byte counts, raw OS errors, and exact timings.

## Verification

Commands:

```bash
swift test --filter BenchmarkTextKeystrokeProbeReportTests
swift build --product VNCLiveBenchmark
scripts/run-naru-live-benchmark.sh text-keystroke-observed-probe -- --text-keystroke-probe-payload ascii
scripts/run-naru-live-benchmark.sh text-keystroke-observed-probe
```

Logs:

```text
/tmp/naru-text-keystroke-observed-probe-20260617-ascii-after-focus-prelude-safety.log
/tmp/naru-text-keystroke-observed-probe-20260617-unicode-hangul-after-focus-prelude.log
```

Result:

| Payload | Transcode | Connect | First frame | Send | Observation | Failure |
| --- | --- | --- | --- | --- | --- | --- |
| `ascii` | `passed` | `passed` | `passed` | `passed` | `no-input` | `text-probe-observation-no-input` |
| `unicode-hangul` | `passed` | `passed` | `passed` | `passed` | `no-input` | `text-probe-observation-no-input` |

Interpretation:

- The VNC connection and KeyEvent enqueue path are alive.
- The controlled local target did not observe inserted text for either ASCII or
  Hangul.
- Because ASCII also fails, the current blocker is not primarily Hangul
  Unicode keysym transcoding. It is a VNC KeyEvent observed-delivery/focus or
  Screen Sharing control-path issue.
- This reinforces helper-native text insertion as the preferred Compose
  delivery path once helper text permissions are granted.

## Remaining Risk

- The probe still cannot prove whether the remote Mac ignored key events,
  whether Screen Sharing control permission is restricted, whether the target
  focus is isolated from the VNC control session, or whether another remote
  focus surface consumed the events.
- The helper-native observed probe is separately blocked by helper text
  Accessibility/value-insert permission.
- Do not claim keyboard fallback works until an observed probe reaches
  `observed-inserted` for at least ASCII and the desired composed-text payload
  class.

## Privacy

This artifact contains only fixed payload labels, fixed stage labels, aggregate
pass/fail observations, fixed failure labels, and local log paths. It omits raw
text, keysyms, target app/window identity, coordinates, framebuffer dimensions,
pixels, endpoints, credentials, hostnames, clipboard contents, byte counts, raw
OS errors, and exact timing series.
