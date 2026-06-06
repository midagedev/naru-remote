# Trackpad Follow Coupling Tuning Summary - 2026-06-07

## Goal

Physical iPhone feedback still described zoomed trackpad navigation as delayed:
the cursor moved immediately, but the viewport follow-pan felt a half-step
behind. This pass tunes only the local trackpad follow math covered by
`specs/003-session-experience` FR-007 and FR-011.

## Change

- Raised the default zoomed trackpad follow-pan coupling from `0.24` to `0.32`.
- Kept the existing cursor-sensitivity compensation, so visible cursor travel
  remains finger-paced while the viewport follows more continuously.
- Left edge-follow damping and tiny-sample caps unchanged, preserving the
  existing guards against snap-pan and backward visible cursor motion.

## Verification

- `swift test --filter PointerGestureResolverTests`
  - Result: passed.
  - Coverage: direct-touch no-wire pan, trackpad buttonless motion, zoomed
    follow-pan, near-edge damping, tiny-sample no-snap behavior, and
    finger-paced visible cursor travel.
- `swift test --filter TrackpadModeModelTests`
  - Result: passed.
  - Coverage: app-model wiring, immediate returned cursor feedback, delayed
    published cursor state, coalesced wire moves, and zoomed auto-pan return.

## Live Benchmark State

The launchctl live benchmark password environment is configured and reusable by
`scripts/run-naru-live-benchmark.sh`. Helper-video ScreenCaptureKit capture is
still blocked by the fixed `helper-video-permission-missing` setup label until
the stable helper app bundle receives macOS Screen Recording permission.

Safe launchctl-runner checks completed after the tuning:

- `preflight`: live host, port, and credential source are configured; helper
  ScreenCaptureKit remains permission-blocked with a fixed setup-action label.
- `helper-synthetic-probe`: external synthetic helper-video remains healthy and
  passes the probe-only comparison.
- `short-live-comparison`: the live VNC request/response path produced samples
  but remains below the poor-network target; the fixed next-action label is
  transport cadence tuning.

No hostnames, passwords, helper executable paths, endpoints, frame payloads,
byte counts, cursor coordinates, raw OS errors, or framebuffer pixels are stored
in this artifact.
