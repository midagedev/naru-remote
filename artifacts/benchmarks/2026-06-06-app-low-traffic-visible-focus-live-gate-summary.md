# App Low-Traffic Visible-Focus Live Gate Summary

Date: 2026-06-06

## Scope

Run the app-aligned poor-network live gate after configuring the local macOS
Screen Sharing target, credential, and controlled stimulus environment. This
checks whether the new app-side visible-focus first-frame path matches the
existing benchmark shape and whether the next optimization unit can be chosen
from schema v62's fixed decision surface.

## Command Shape

```sh
swift run VNCLiveBenchmark \
  --stream-shape-gate-preset sustained-v2-constrained-cellular-app-low-traffic \
  --json
```

The command used environment-provided host, port, credential, and stimulus
values. Those values are intentionally not recorded here.

## Result

- `schemaVersion`: 62
- `streamShapeGatePreset`: `sustained-v2-constrained-cellular-app-low-traffic`
- `streamShapeProfiles`: `app-low-traffic`
- `streamShapeFirstFrameRequestMode`: `visible-focus`
- `streamShapeRequestRegions`: `viewport-phone-portrait`
- `streamShapeOptimizationDecision.verdict`: `fail`
- `primaryIssueCode`: `first-frame-payload-read-failed`
- `primaryConstraint`: `receivePath`
- `recommendedNextProbe`: `compareEncodingProfileGate`

First frame:

- Total: about 15.9 s
- First-frame request area: 192 permille
- Network read: about 15.1 s
- First-byte wait: about 0.93 s
- Payload read: about 14.1 s
- Client processing: about 0.89 s
- Payload-read share: 938 permille of network-read time

Sustained samples:

- Received samples: 4/4
- Content samples: 3/4
- Content FPS: about 1.37
- Average / p95 update: about 532 / 1206 ms
- Renderer full-upload pressure: 0 permille
- Dominant sustained phase: `network-read`
- Dominant sustained subphase: `first-byte-wait`
- Practical assessment primary issue: `client-processing-failed`

## Interpretation

- The app low-traffic path remains aligned with the benchmark's fixed
  visible-focus shape: first-frame request area stayed at 192 permille and
  sustained request area stayed at 364 permille.
- Request-area reduction alone still does not solve poor-network startup. The
  first-frame payload read dominates startup, so the next code unit should
  compare encoding / pixel-format startup candidates or add a smaller
  first-useful-paint strategy before promoting any default.
- Sustained renderer upload is not the primary blocker in this run.

## Verification Boundary

This artifact stores only fixed labels plus aggregate timings, counts, and
permille ratios. It does not store host identity, credentials, port value,
stimulus command text, command output, framebuffer dimensions, coordinates,
pixels, cursor pixels, byte counts, raw payloads, raw errors, draft text,
marked text, or IME state.
