# 2026-06-04 Default Cursor Profile Summary

Safety boundary: this artifact preserves only aggregate benchmark outputs. It
omits host, password, server name, framebuffer dimensions, coordinates, pixels,
byte counts, cursor pixels, and raw error descriptions.

## Research Context

- RFC 6143 makes `SetEncodings` client-preference ordered and says unsupported
  pseudo-encodings are ignored by the server.
- RFC 6143 also notes that requesting the Cursor pseudo-encoding lets the client
  draw the pointer locally, which can significantly improve perceived
  performance on slow links.
- IANA records ZRLE as a registered RFB encoding while ContinuousUpdates/Fence
  remain extension codes, so request/response remains the production
  compatibility path.
- TigerVNC exposes automatic encoding selection plus manual encoding and
  compression controls, which supports benchmark-backed profile choice rather
  than a single universal encoding order.

References:

- https://www.rfc-editor.org/rfc/rfc6143
- https://www.iana.org/assignments/rfb/rfb.xhtml
- https://tigervnc.org/doc/vncviewer.html

## 60-Second Encoding Evidence

Command shape:

```sh
swift run VNCLiveBenchmark \
  --attempts 1 \
  --first-frame-profiles none \
  --full-refresh-samples 0 \
  --stream-shape-samples 0 \
  --stream-shape-duration-seconds 60 \
  --stream-shape-profiles local-low-latency,zrle-compression-0,adaptive-good-full \
  --stream-shape-transport request-response \
  --continuous-update-samples 1 \
  --timeout 8 \
  --idle-timeout 0.75 \
  --json
```

Normal pacing, pre-change comparison:

| Profile | Content FPS | Update avg / p95 ms | Renderer full uploads | Very slow samples |
| --- | ---: | ---: | ---: | ---: |
| prior `local-low-latency` Tight-first | 6.06 | 115 / 479 | 3 permille | 1 |
| `zrle-compression-0` | 6.50 | 107 / 478 | 0 permille | 0 |
| `adaptive-good-full` | 6.23 | 111 / 480 | 0 permille | 0 |

Low-power pacing, pre-change comparison:

| Profile | Content FPS | Update avg / p95 ms | Renderer full uploads | Very slow samples |
| --- | ---: | ---: | ---: | ---: |
| prior `local-low-latency` Tight-first | 4.00 | 155 / 499 | 0 permille | 0 |
| `zrle-compression-0` | 4.20 | 159 / 498 | 0 permille | 0 |
| `adaptive-good-full` | 4.00 | 160 / 496 | 0 permille | 0 |

Follow-up normal pairwise comparison after a temporary local ZRLE default:

| Profile | Content FPS | Update avg / p95 ms | Renderer full uploads | Very slow samples |
| --- | ---: | ---: | ---: | ---: |
| temporary `local-low-latency` ZRLE compression 0 | 6.30 | 110 / 480 | 0 permille | 0 |
| `tight-first` | 6.47 | 104 / 478 | 0 permille | 0 |

## Decision

Do not switch the production request/response default from Tight-first to ZRLE
compression 0 yet. The longer runs show both profiles are viable and screen-state
variance can flip the recommendation. Keep ZRLE compression 0 as a benchmark
candidate for a future server/profile-specific selector.

Make the safe default improvement that does not alter the real encoding path:
request Cursor/XCursor pseudo-encodings in `RFBEncodingPreference.localLowLatency`.
Naru already decodes server cursor shapes and draws them in the trackpad cursor
overlay, and unsupported pseudo-encodings are ignored by compliant servers.

## Post-Change Verification

- `swift test` passed: 564 tests, 10 benchmark tests skipped by design.
- `swift run VNCLiveBenchmark` with a 12 second `local-low-latency`
  request/response stream succeeded after Cursor/XCursor were added to the
  default profile: mixed updates, 76 received samples, 65 content samples, and
  no stream failure.
- `xcodegen generate --spec project.yml` succeeded.
- iPad simulator app build succeeded for `iPad Pro 13-inch (M5), OS 26.2`.
- Generic iPhoneOS build succeeded with `CODE_SIGNING_ALLOWED=NO`.

Residual risk:

- These are localhost/macOS Screen Sharing runs, not a 5+ minute physical iPhone
  thermal pass.
- Cursor pseudo-encoding behavior remains server-dependent; unsupported servers
  should ignore it, and Naru keeps its synthetic cursor fallback.
- Installing onto the connected physical iPhone is still blocked by local
  development-team signing configuration, not by compile errors.
