# TestFlight upload — 1.0.0 (build 10)

- Uploaded: 2026-08-25 17:22 KST
- Commit: 8af8b89c (dirty tree)
- Bundle: com.naruremote.app, team XEF9KH7N43

## Why this build exists

Build 9 was fast and soft. This one keeps the speed and stops throwing away
pixels.

**spec 031** — the server-side downscale (spec 018's Apple ScaleFactor message)
now runs only in power saver or iOS Low Data Mode. On the default `balanced` mode
the session stays at the server's native resolution.

Why it was safe to stop: the downscale was a compensation for slowness, and spec
030 found the slowness was viewport-scoped request regions — Apple answered those
in 540–787 ms instead of 33 ms. The runs that showed 5.66–7.08 content fps after
that fix were taken at **full 3024×1964**, because the live benchmark never sends
ScaleFactor at all. The pixels were buying nothing that was still needed.

Also: it is not the compressor. The session negotiates ZRLE, which is lossless,
and a direct probe of this Mac's Screen Sharing confirms it serves 3024×1964 at
32 bits per pixel true colour. Nothing upstream of the client reduces anything.

The applied downscale is now in the diagnostic export as `appleServerDownscaleRung`
(`full` / `half`). Its absence is why the softness could not be attributed from
the build 8 report.

## What to check on the device

1. **Is it sharp now, and still fast?** Both, or the trade below has bitten.
2. **Data use, heat, and stutter.** This is the half that is **not measured**:
   full resolution is roughly four times the pixels per full frame and you are on
   a mobile link (measured RTT 41–500 ms, direct cellular). Watch
   `dirtyAreaPermille` and `changedPixelsPermille` in the export, and say if
   cellular data or heat gets worse — power saver is the switch that trades back.
3. `appleServerDownscaleRung` should read `full` on balanced.

## Known limits

- **The client's upscaler was deliberately not touched.** It samples with a
  single linear tap, which is a poor filter both magnifying and minifying, so
  zoomed-in text will still soften. That is a real improvement to make, and it
  was kept out of this build so that this change and that one stay separately
  attributable.
- 5.66–7.08 fps at full resolution comes from one gate preset on one machine, and
  spec 029 recorded the same machine measuring 17 fps under a different harness
  configuration. That discrepancy is still unexplained.
- spec 023 T006 device pass is still outstanding from build 6.
- Archive contract: version/build, bundle id, MinimumOSVersion 17.0,
  ITSAppUsesNonExemptEncryption=false, PrivacyInfo.xcprivacy present,
  no NARU_TEST_* hooks in the Release binary — all verified pre-upload.
- altool: VERIFY SUCCEEDED, UPLOAD SUCCEEDED.
- App Store Connect processingState: VALID

Produced by `scripts/testflight-upload.sh`. Credentials were read from
~/.appstoreconnect and are not recorded here.
