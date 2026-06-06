# External Helper Timeout Preflight Summary

Date: 2026-06-07

## Scope

This run verifies that `VNCLiveBenchmark --environment-preflight` does not
block indefinitely when the selected external helper executable does not answer
its safe `--video-capability` command.

No host names, passwords, ports, helper executable paths, bundle identifiers,
usernames, parent process names, endpoints, frame content, framebuffer
dimensions, byte counts, raw OS errors, stimulus command text, helper stderr,
or stimulus output are recorded here.

## Command Shape

```bash
NARU_HELPER_EXECUTABLE="<slow local helper fixture>" \
NARU_HELPER_CAPABILITY_TIMEOUT_SECONDS="<bounded timeout>" \
NARU_LIVE_MAC_HOST="<configured>" \
NARU_LIVE_MAC_PORT="<configured>" \
NARU_LIVE_MAC_PASSWORD="<configured>" \
swift run VNCLiveBenchmark \
  --environment-preflight \
  --visual-transport helper-video \
  --helper-video-probe external-helper-screen-capturekit-tcp \
  --json
```

## Result

- Environment preflight schema: `6`.
- Live benchmark runnable: `false`.
- Helper-video ScreenCaptureKit permission status: `delegatedToHelper`.
- External helper capability status: `timedOut`.
- Issue code: `helper-video-external-helper-timed-out`.
- Setup action: `inspect-helper-video-capability`.

## Interpretation

The benchmark setup now turns a non-responsive helper capability command into a
bounded fixed-label diagnostic rather than waiting forever. The same bounded
process cleanup utility is used when the external helper-video TCP smoke probe
stops its helper process after a run.
