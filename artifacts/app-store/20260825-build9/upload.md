# TestFlight upload — 1.0.0 (build 9)

- Uploaded: 2026-08-25 15:49 KST
- Commit: 0eba39c3 (dirty tree)
- Bundle: com.naruremote.app, team XEF9KH7N43

## Why this build exists

The founder's frame rate. Builds 7 and 8 ran under five content frames per
second; this one changes the single axis that was measured to control it.

**spec 030** — incremental framebuffer update requests are full-frame instead of
scoped to the visible viewport. Measured against live Apple Screen Sharing
(release, no network conditioning, one axis at a time, three repeats):

| | viewport-scoped | full framebuffer |
|---|---|---|
| content fps | 0.49–0.74 | **5.66–7.08** |
| average update | 540–787 ms | **33 ms** |
| p95 update | ~5100 ms (the client's idle timeout) | **119–133 ms** |

No other axis moved the result — client-pressure pacing, empty-update backoff
and stimulus rate were all within noise. An iPhone showing a wide desktop is
always looking at a crop, so the scoped path was the normal one, not a zoomed-in
edge case.

Also in this build since 8: **spec 028** counts publications from the frame store
rather than from SwiftUI view rebuilds, so the export's presented/published ratio
is now meaningful.

## What to check on the device

1. **Does it feel faster, and does the export agree?** Export diagnostics from a
   session and read `contentFramesPerSecond` — it should leave `underFive`.
2. **The other half of the trade, which is NOT measured.** Full-frame
   incrementals send more damage per response. On a mobile link that is
   bandwidth for latency, and only the latency half has been measured. Watch
   `dirtyAreaPermille` and `changedPixelsPermille` in the export, and say if
   cellular data use or heat gets worse.
3. **Presentation should still be clean** — `framePresentationPresentedCount`
   tracking `contentFrameCount`, `framePresentationWatchdogReleaseCount` at 0.

## Known limits

- One server family (Apple Screen Sharing), one Mac, loopback. Other RFB servers
  may answer region requests fine, which is why the scoping machinery stays in
  place rather than being deleted.
- The measurement used a phone-portrait crop. A session zoomed much further in
  saves far more area and the trade could look different there. Untested.
- Measured RTT to the founder's iPhone is 41–500 ms (median ~185 ms, direct over
  mobile). The link is a 212 ms additive term, not the constraint (spec 029), and
  `requestPipelineDepth` is unchanged because depth 1/2/3 measured identically.
- spec 023 T006 device pass is still outstanding from build 6.
- Archive contract: version/build, bundle id, MinimumOSVersion 17.0,
  ITSAppUsesNonExemptEncryption=false, PrivacyInfo.xcprivacy present,
  no NARU_TEST_* hooks in the Release binary — all verified pre-upload.
- altool: VERIFY SUCCEEDED, UPLOAD SUCCEEDED.
- App Store Connect processingState: VALID

Produced by `scripts/testflight-upload.sh`. Credentials were read from
~/.appstoreconnect and are not recorded here.
