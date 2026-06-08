# Text Keystroke Live Probe Summary - 2026-06-09

## Scope

This artifact records the first privacy-safe live VNC compatibility probe for
bounded Compose text KeyEvent experiments. It is a benchmark-only probe and
does not enable key-event text as the default Compose send route.

## Command

```bash
scripts/run-naru-live-benchmark.sh text-keystroke-probe -- --timeout 5
```

The wrapper imported the live target configuration from launchctl. The report
omits target identity, credentials, raw text, keysyms, bytes, framebuffer
dimensions, pixels, raw errors, and exact timings.

## Result

### Unconditioned

- `status`: `sent`
- `payload`: `unicode-hangul`
- `payloadEncoding`: `utf8ExtensionRequired`
- `usesUnicodeKeysyms`: `true`
- `connectStatus`: `passed`
- `firstFrameStatus`: `passed`
- `transcodeStatus`: `passed`
- `sendStatus`: `passed`
- `eventCountBucket`: `one-to-five`
- `networkConditionProfile`: `none`

### Constrained Cellular

```bash
scripts/run-naru-live-benchmark.sh text-keystroke-probe -- --network-condition constrained-cellular --timeout 5
```

- `status`: `failed`
- `payload`: `unicode-hangul`
- `payloadEncoding`: `utf8ExtensionRequired`
- `usesUnicodeKeysyms`: `true`
- `connectStatus`: `passed`
- `firstFrameStatus`: `failed`
- `transcodeStatus`: `passed`
- `sendStatus`: `not-run`
- `failureLabel`: `text-probe-first-frame-read-timeout`
- `eventCountBucket`: `one-to-five`
- `networkConditionProfile`: `constrained-cellular`

## Interpretation

The live Mac VNC target accepted the handshake and first-frame request, and
the benchmark enqueued the fixed Unicode-keysym KeyEvent down/up sequence on
the active RFB transport.

Under constrained-cellular conditioning, the probe did not reach the send phase
because the first-frame read timed out. That supports keeping poor-network
startup and traffic reduction as a separate product gate before key-event text
promotion.

This does not confirm that the focused remote editor inserted the text. The
next evidence slice should add a separate remote-side observation path before
promoting key-event text beyond probe-only status.
