# 2026-06-05 Practical iPhone VNC Baseline v1 Summary

## Trigger

After several physical iPhone passes, zoom/pan still felt stepped and Compose
input still failed in practical use. The work needed a larger target unit than
single symptom fixes: define what "usable enough to keep iterating" means, make
the benchmark report that verdict, and fold the immediate viewport/Compose
regressions into that baseline.

## Baseline Target

`iphone-practical-baseline-v1` is intentionally a floor, not the final product
goal.

- Pass content FPS: at least 8 content updates per second.
- Fail content FPS: below 4 content updates per second.
- Pass p95 update latency: at most 500 ms.
- Fail p95 update latency: above 1000 ms.
- Pass client-processing p95: at most 24 ms.
- Fail client-processing p95: above 50 ms.
- Pass renderer full-upload pressure: at most 50 permille.
- Fail renderer full-upload pressure: above 150 permille.
- Pass adaptive pacing pressure: at most 100 permille.
- Fail adaptive pacing pressure: above 500 permille.
- Minimum content samples for a confident content-FPS read: 3.

The benchmark emits fixed verdicts only: `disabled`, `pass`, `warning`, or
`fail`, plus fixed issue codes such as `content-fps-failed`,
`p95-update-failed`, `client-processing-failed`, `full-upload-warning`, and
`adaptive-pressure-failed`.

## Sources Rechecked

- RFC 6143, RFB protocol: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- TurboVNC H.264 study: https://turbovnc.org/About/H264

Relevant takeaways:

- RFB update flow is client-request driven, so request cadence is a first-class
  performance lever.
- Encoding preference and pseudo-encoding confirmation must be explicit and
  conservative.
- Mature VNC viewers expose reduced color, preferred encoding, quality, and
  pointer-event rate-limit controls, which argues for Naru's automatic policy
  to be backed by safe coarse metrics instead of raw logs.
- Frame-based/video-style approaches need coalescing and flow control; full
  uploads and long client-processing tails are practical red flags on mobile.

## App Changes

- Keep Metal framebuffer zoom/pan transforms immediate while mirroring
  published viewport state at a bounded 30 Hz cadence instead of only at
  gesture end.
- Allow unconfirmed UTF-8 VNC clipboard servers to take the explicit
  best-effort legacy paste path with `unknown` status and retained draft text.
- Keep known unsupported UTF-8 clipboard support as a failed path with
  helper-aware diagnostics.
- Do not start stored helper insertion attempts when the helper state is
  already known unreachable, permission-missing, or version-unsupported; use the
  VNC best-effort route only when VNC support is unconfirmed rather than known
  unsupported.

## Benchmark Changes

- Bump `VNCLiveBenchmark` JSON schema to v27.
- Add `practicalAssessment` to stream-shape JSON.
- Print the practical target and issue-code summary in human CLI output.
- Keep all assessment input as safe aggregates: counts, fixed mode labels,
  latency summaries, and permille ratios only.

## Live Benchmark

Command shape:

```bash
swift run VNCLiveBenchmark \
  --first-frame-profiles none \
  --stream-shape-profiles local-low-latency \
  --stream-shape-transport request-response \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 6 \
  --stream-shape-client-pressure app \
  --stream-shape-viewport-interaction app \
  --full-refresh-samples 0 \
  --timeout 8 \
  --idle-timeout 0.75 \
  --json
```

Result against the redacted local macOS Screen Sharing target: benchmark
succeeded, but the practical baseline verdict was `fail`.

Safe aggregates from the 6 second run:

- schema: 27
- target: `iphone-practical-baseline-v1`
- verdict: `fail`
- issue codes:
  - `content-fps-failed`
  - `p95-update-failed`
  - `client-processing-failed`
  - `very-slow-update`
  - `full-upload-warning`
- transport: request-response
- received samples: 8
- content updates: 7
- empty updates: 1
- content FPS: 1.17
- update latency p50/p95/max: 145/2512/2512 ms
- client-processing p50/p95/max: 2/2151/2151 ms
- renderer full-upload permille: 143
- viewport-interaction pacing permille: 1000
- actual encoding mix: ZRLE rectangles only

Short human-output smoke:

- The CLI printed
  `practical target: iphone-practical-baseline-v1 fail (...)`.
- This confirms the text report and JSON report expose the same baseline
  decision.

## Verification

- `swift test --filter BenchmarkStreamShapeSummaryTests`
  - Result: passed, 20 tests, 0 failures.
- `swift test --filter NaruRemoteAppModelTests/testStoredHelperCapabilityFailureBlocksRawHelperInsertBeforeUnsupportedVNCFailure`
  - Result: passed, 1 test, 0 failures.
- `swift test`
  - Result: passed, 786 tests, 10 skipped, 0 failures.
- Live `VNCLiveBenchmark` 6 second stream-shape run
  - Result: command succeeded, practical baseline verdict `fail`.
- `xcodegen generate --spec project.yml`
  - Result: succeeded; generated project had no tracked diff.
- `xcodebuild -project NaruRemote.xcodeproj -scheme NaruRemote -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
  - Result: succeeded.

## Next Larger Units

- Reduce client-processing tail first, because this run's p95 reached 2151 ms
  even though median client processing was 2 ms.
- Drive renderer full-upload pressure below warning level, since 143 permille is
  close to the v1 fail threshold.
- Revisit stream request cadence only after the processing/upload tail improves;
  the current result is not just "too few requests".
- Keep Compose reliability split into three clear routes: confirmed VNC UTF-8,
  best-effort legacy VNC with `unknown` status, and helper text bridge for
  reliable Korean/CJK/emoji insertion.

## Remaining Risk

- This target is a first practical floor. Physical iPhone hand-feel still needs
  retesting because simulator/unit tests cannot prove finger-to-glass latency or
  thermal comfort.
- The localhost live run can expose macOS Screen Sharing behavior, but it does
  not represent every private-network path or every server implementation.
