# TestFlight upload — 1.0.0 (build 7)

- Uploaded: 2026-08-21 15:44 KST
- Commit: e0dad963 (dirty tree — the only uncommitted change was
  `CURRENT_PROJECT_VERSION: 6 → 7` in `project.yml`, written by `--bump`
  immediately before the archive, and committed straight after this record)

## What is new since build 6

App behaviour:

- **spec 024** — damage rectangles are merged instead of re-uploading the
  framebuffer; `uploadRegions` is the single owner the renderer uploads from.
- **spec 026** — no rectangle count sends a frame to a full upload any more.
  Build 6 still re-uploaded the whole framebuffer on 174‰ of content frames
  under a heavy stimulus; live-measured here that is now 0‰.

Tooling only, no app code (recorded so the device pass is judged against the
right numbers): **specs 025 and 027** corrected four stacked defects in the live
benchmark. The VNC path measures **content 17.0 fps, delivered ~20 fps, picture
delivery latency 111 ms average / 135 ms p95** — not the ~8–10 fps and
seconds-of-staleness this repository recorded before today.

## Device pass to run on this build

- spec 023 T006 — trackpad live on arrival, the remote Dock reachable while
  zoomed, cursor tip landing where the tap lands.
- specs 024 and 026 — the phone-side win from eliminating full uploads
  (bandwidth, power, thermals). This is **inferred, not measured**: a desktop GPU
  absorbs a full texture upload cheaply, so this Mac cannot show it.
- Bundle: com.naruremote.app, team XEF9KH7N43
- Archive contract: version/build, bundle id, MinimumOSVersion 17.0,
  ITSAppUsesNonExemptEncryption=false, PrivacyInfo.xcprivacy present,
  no NARU_TEST_* hooks in the Release binary — all verified pre-upload.
- altool: VERIFY SUCCEEDED, UPLOAD SUCCEEDED.
- App Store Connect processingState: VALID

Produced by `scripts/testflight-upload.sh`. Credentials were read from
~/.appstoreconnect and are not recorded here.
