# App Low-Traffic Visible-Glance Live Gate Summary

Date: 2026-06-06

## Scope

Validate a startup-only `visible-glance` request region for the app's opt-in
`zrle-compression-0-rgb565` low-traffic profile under the constrained-cellular
poor-network target. The first non-incremental request uses a small centered
visible-core slice, while sustained incremental requests keep the normal
phone-portrait viewport region and fallback policy.

The live benchmark target, credential, server name, framebuffer dimensions,
coordinates, byte counts, pixels, cursor pixels, command text, and raw payloads
are intentionally not recorded.

## Command Shape

```bash
swift run VNCLiveBenchmark \
  --network-condition constrained-cellular \
  --stream-shape-stimulus external-command \
  --stream-shape-client-pressure app \
  --stream-shape-empty-backoff app \
  --stream-shape-transport request-response \
  --stream-shape-profiles zrle-compression-0-rgb565 \
  --stream-shape-request-region viewport-phone-portrait \
  --stream-shape-first-frame-request visible-glance \
  --stream-shape-practical-target iphone-poor-network-traffic-v1 \
  --stream-shape-samples 4 \
  --stream-shape-profile-iterations 1 \
  --stream-shape-frame-interval 0 \
  --continuous-update-samples 0 \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --timeout 30 \
  --idle-timeout 5 \
  --json
```

## Result

- Schema: `63`
- First-frame request mode: `visible-glance`
- First-frame request area: `108` permille
- Sustained request area: `364` permille
- First-frame total receive: about `12.0 s`
- First-frame network read: about `11.4 s`
- First-frame payload read: about `10.4 s`
- First-frame payload share: `919` permille
- Sustained received/content samples: `4/4`, `4/4`
- Sustained content FPS: about `2.34`
- Sustained average/p95 update: about `426/871 ms`
- Renderer full upload pressure: `250` permille
- Gate verdict: `fail`
- Primary issue: `first-frame-payload-read-failed`
- Primary constraint: `receivePath`
- Recommended next probe: `compareEncodingProfileGate`

## Interpretation

`visible-glance` keeps the useful part of the previous small-area experiment:
first-frame payload read drops from the earlier visible-focus app run's roughly
`14.1 s` at `192` permille to roughly `10.4 s` at `108` permille. Unlike the
center-third experiment, sustained viewport requests still receive content
updates because only the first non-incremental request is narrowed.

This is a startup usability improvement, not a full poor-network pass. The next
large unit should keep the smaller first-useful-paint policy, then compare
encoding/profile behavior and inspect the sustained wait/render tail reported
by the v63 app-candidate run.
