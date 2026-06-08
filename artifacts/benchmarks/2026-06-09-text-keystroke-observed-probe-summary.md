# Text Keystroke Observed Probe Summary - 2026-06-09

## Scope

This artifact records the first live probe that separates RFB KeyEvent enqueue
from actual focused-editor insertion. It uses a controlled local
`VNCLiveStimulusWindow --text-probe` AppKit text target and records only
fixed observation labels.

The probe remains benchmark-only. It does not enable key-event text as the
default Compose send route.

## Commands

```bash
scripts/run-naru-live-benchmark.sh text-keystroke-observed-probe -- --timeout 5 --text-keystroke-observation-timeout 3 --text-keystroke-probe-payload ascii
scripts/run-naru-live-benchmark.sh text-keystroke-observed-probe -- --timeout 5 --text-keystroke-observation-timeout 3 --text-keystroke-probe-payload unicode-hangul
scripts/run-naru-live-benchmark.sh text-keystroke-probe -- --timeout 5 --text-keystroke-probe-payload unicode-hangul
```

The wrapper imports live VNC target configuration from launchctl and builds
the local observation target. Reports omit target identity, credentials, raw
text, keysyms, byte counts, framebuffer dimensions, pixels, raw errors, exact
timings, and the local observation executable path.

## Results

### Observed ASCII

- `status`: `failed`
- `payload`: `ascii`
- `payloadEncoding`: `ascii`
- `usesUnicodeKeysyms`: `false`
- `connectStatus`: `passed`
- `firstFrameStatus`: `passed`
- `transcodeStatus`: `passed`
- `sendStatus`: `passed`
- `observationStatus`: `no-input`
- `failureLabel`: `text-probe-observation-no-input`
- `eventCountBucket`: `six-to-twenty`
- `networkConditionProfile`: `none`

### Observed Hangul

- `status`: `failed`
- `payload`: `unicode-hangul`
- `payloadEncoding`: `utf8ExtensionRequired`
- `usesUnicodeKeysyms`: `true`
- `connectStatus`: `passed`
- `firstFrameStatus`: `passed`
- `transcodeStatus`: `passed`
- `sendStatus`: `passed`
- `observationStatus`: `no-input`
- `failureLabel`: `text-probe-observation-no-input`
- `eventCountBucket`: `one-to-five`
- `networkConditionProfile`: `none`

### Send-Only Control

- `status`: `sent`
- `payload`: `unicode-hangul`
- `observationStatus`: `not-run`
- `connectStatus`: `passed`
- `firstFrameStatus`: `passed`
- `sendStatus`: `passed`

## Interpretation

The current local Apple Screen Sharing target accepts the VNC connection and
the benchmark enqueues KeyEvent down/up sequences, but a controlled focused
AppKit text target receives no text for both ASCII and Hangul payloads.

This is evidence against promoting raw VNC KeyEvents as a Compose text route
on the founder Mac path. The next Compose reliability work should continue to
favor helper-native insertion and use this observed probe as a regression gate
for any future RFB-keyevent compatibility claims.
