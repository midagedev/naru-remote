# Research & Technical Decisions: RFB Encodings

Reference: RFC 6143 (The Remote Framebuffer Protocol) §7.6–§7.7, plus the community
RFB protocol extensions (community.realvnc / TigerVNC `rfbproto`). All multi-byte
fields are **big-endian**.

## D1 — Decode-as-you-read over an incremental `RFBByteReader`

**Decision**: introduce `RFBByteReader` with big-endian typed reads
(`u8 / u16 / u32 / s32 / bytes(n)`), implemented by:
- `DataByteReader(Data)` — cursor over a fixed buffer; `read(n)` throws
  `RFBByteReaderError.insufficientData` if short. Used by all pure decoder tests
  and the kept `apply(updateData:)` shim.
- `ConnectionByteReader` — `read(n)` calls `connection.readExactly(n, timeout:)`;
  a rectangle spanning multiple TCP segments just blocks for more.

**Why**: the current `readFramebufferUpdateData` computes `w*h*bpp` per rectangle —
correct only for Raw. Hextile/ZRLE/Tight are variable-length; their length is only
known by parsing. A reader the decoder *pulls* from unifies fixed + variable +
network + fixture into one path. Keeps the pure `Data`-in test ergonomics.

## D2 — `SetEncodings` and `SetPixelFormat` wire formats

`SetEncodings` (client→server, message type 2, §7.5.2):
```
u8  message-type = 2
u8  padding = 0
u16 number-of-encodings = N
s32 × N  encoding types, in preference order (server SHOULD honor order)
```

`SetPixelFormat` (type 0, §7.5.1): `u8 type=0`, `u8[3] pad`, then the 16-byte
PIXEL_FORMAT (bpp, depth, big-endian-flag, true-colour-flag, {r,g,b}-max u16,
{r,g,b}-shift u8, `u8[3] pad`). **Decision**: Naru keeps the server's 32-bit
true-colour format; we may send `SetPixelFormat` to *re-assert* RGBA8 but do not
switch to a smaller format (keeps the existing decoder constraint). Lowest priority;
Increment 1 can skip sending it and rely on `ServerInit`'s format as today.

Preference list (Increment 1, before ZRLE/Tight): the pseudo-encoding codes are
advertised alongside real encodings so the server enables them.
```
[ Hextile(5), CopyRect(1), Raw(0),
  LastRect(-224), DesktopSize(-223), ExtendedDesktopSize(-308) ]
```
Order matters: most-preferred real encoding first; Raw last as the floor (always
present). Pseudo-encodings have no "order" effect but must be listed to be enabled.
ZRLE(16)/Tight(7) and the quality/compression codes are inserted by the
`RFBEncodingPreference` builder in later increments, ahead of Hextile when present.

## D3 — CopyRect (encoding 1, §7.7.2)

Rectangle payload after the 12-byte header is just:
```
u16 src-x-position
u16 src-y-position
```
Copy the `width × height` block from `(src-x, src-y)` of the **current** framebuffer
to `(rect.x, rect.y)`. **Subtlety**: when source and destination overlap, copy in an
order that doesn't clobber un-read source pixels (snapshot the source region first, or
iterate in the safe direction). **Decision**: snapshot the source rectangle into a
temp buffer, then write to destination — simplest and overlap-safe. Bounds-check both
src and dst against framebuffer dimensions; typed error otherwise. Damage = dst rect.

## D4 — Hextile (encoding 5, §7.7.4)

Rectangle is split into 16×16 tiles, left→right then top→bottom; the last column/row
tiles may be smaller. Each tile begins with a `u8` subencoding mask:
```
bit0 Raw                — tile is raw pixels (w*h CPIXELs); other bits ignored
bit1 BackgroundSpecified— a background PIXEL follows
bit2 ForegroundSpecified— a foreground PIXEL follows
bit3 AnySubrects        — a u8 number-of-subrects follows
bit4 SubrectsColoured   — each subrect carries its own PIXEL
```
**Carry semantics**: background/foreground PERSIST across tiles when their bit is
unset — a tile with neither Background nor Raw reuses the previous tile's background.
This is the #1 Hextile bug source; the decoder keeps `bg`/`fg` state across the tile
loop and the test `testHextileBackgroundCarry` proves it.

Non-raw tile body: if BackgroundSpecified → read PIXEL into `bg`; if ForegroundSpecified
→ read PIXEL into `fg`; fill the whole tile with `bg`; if AnySubrects → read `u8 n`,
then `n` subrects. Each subrect: if SubrectsColoured → a PIXEL, then `u8 xy` (x<<4|y)
and `u8 wh` ((w-1)<<4|(h-1)); else (foreground-coloured) just `u8 xy`,`u8 wh`. Paint
the subrect with its colour (or `fg`). Coordinates are tile-relative, 0–15.

PIXEL size here = `bytesPerPixel` (4 for our format); Hextile uses full PIXELs, not
ZRLE's CPIXEL compaction.

## D5 — ZRLE (encoding 16, §7.7.6) — Increment 2

Rectangle payload: `u32 length`, then `length` bytes of a **zlib stream**. The zlib
stream is **continuous for the whole session** — one inflate context across all ZRLE
rectangles and all updates; resetting per rectangle corrupts everything after frame 1
(this is the explicit `testZrleStreamPersistsAcrossUpdates` requirement). Inflated
output is a sequence of 64×64 tiles (last row/col smaller). Each tile:
```
u8 subencoding:
  0        : raw CPIXELs (w*h)
  1        : solid — one CPIXEL fills the tile
  2..16    : packed palette — palette of `subencoding` CPIXELs, then packed indices
             (bit width 1/2/4 by palette size), rows padded to a byte
  17..127  : unused (error)
  128      : plain RLE — runs of <CPIXEL, length> where length is 255-continued
  129      : unused
  130..255 : palette RLE — palette of `subencoding-128` CPIXELs, then RLE of
             <index, length>; index high-bit signals a run (length follows), else len 1
```
**CPIXEL**: a compacted pixel. For our 32-bpp true-colour with all 8-bit maxima and
the top byte unused, CPIXEL is **3 bytes** (the significant R/G/B), not 4. The decoder
computes CPIXEL size from the pixel format (`= 3` when bpp==32, depth≤24, and the
three 8-bit maxima fit in 3 bytes; else `bytesPerPixel`). Endianness/shift follow the
pixel format, same as the Raw decoder's `decodeColor`.

**zlib via `Compression` framework**: `compression_stream` with `COMPRESSION_ZLIB`
decodes **raw DEFLATE (RFC 1951)**, not zlib (RFC 1950). RFB's stream is RFC-1950
framed (2-byte header `0x78 …`, trailing adler32). **Decision**: on first inflate,
consume the 2-byte zlib header once, then feed the remainder as raw DEFLATE to a
persistent `compression_stream` initialized once per session. RFB servers flush each
update with `Z_SYNC_FLUSH` (emits `00 00 FF FF`); the streaming inflate yields the
available output per call without `FINALIZE`. We request exactly the bytes the tile
layout needs and stop — never finalize until session end. A thin `RFBZlibInflateStream`
wraps this with a `decompress(_ input: [UInt8], wanting maxOut) -> [UInt8]` that buffers
inflated output and refills input as the tile reader consumes it.

Alternative considered: linking system `libz` (`inflateInit/inflate`) via a SwiftPM
system-library target. Rejected for Increment 2 to avoid a module-map/system target;
revisit only if the Compression-framework raw-DEFLATE-with-manual-header approach
proves unreliable against real servers (residual-risk device task).

## D6 — Tight (encoding 7) — Increment 3 (stretch)

Most complex; uses up to four zlib streams (selectable per rectangle via a stream-reset
bitfield in the compression-control byte) plus optional JPEG. Sub-encodings: fill
(solid colour, no zlib), JPEG (a length-prefixed JPEG → decode via ImageIO/`CGImage`),
and basic (copy/palette/gradient filters through one of the zlib streams). Compact
"TPIXEL" (3 bytes when applicable). Lengths use the 7-bit-continued compact-length
format. **Decision**: implement fill + JPEG + basic-copy first (covers the common
TurboVNC/macOS cases); gradient/palette filters second. JPEG decode runs off the main
actor. Tight is explicitly optional/last — CopyRect+Hextile+ZRLE already deliver the
bandwidth win.

## D7 — Pseudo-encodings

- **LastRect (-224)**: a rectangle with this encoding and no payload terminates the
  update; servers may set the update's rectangle-count to `0xFFFF` and rely on LastRect.
  The update loop MUST break on LastRect rather than read 65535 rectangles.
- **DesktopSize (-223)**: the rectangle's `width/height` are the new framebuffer size;
  no pixel payload. Reallocate the framebuffer and surface an `RFBDesktopResize` signal;
  subsequent rectangles validate against the new size. (App re-fit reuses `specs/003`.)
- **ExtendedDesktopSize (-308)**: payload is `u8 number-of-screens`, `u8[3] pad`, then
  per-screen `{u32 id, u16 x, u16 y, u16 w, u16 h, u32 flags}`; the rectangle's x carries
  a reason code and y a result code. Parse new size from the rect width/height; treat as
  resize. Increment 3.
- **Cursor (-239) / RichCursor**: rect `width/height` = cursor size; payload = `w*h`
  PIXELs then a 1-bpp `(w+7)/8 * h` mask. Decode to an image + hotspot `(rect.x, rect.y)`.
  Does NOT touch the framebuffer. **XCursor (-240)**: 2 PIXELs (fg/bg) + bitmap + mask.
  Increment 3, optional (synthetic cursor from `specs/003` is the floor).
- **Fence (-312) / ContinuousUpdates (-313)**: flow-control extensions; Increment 3.

## D8 — Security / robustness (SP-006)

Every decoder treats server bytes as hostile: bounds-check rect against framebuffer;
cap dimensions/lengths to sane maxima (reject e.g. a 4-byte-prefixed length larger than
a frame's worth, or palette sizes > 127); never allocate from an unvalidated length;
never read past the rectangle's declared bytes; never trap (`!`, unchecked subscript,
force-unwrap) on server data. All errors are typed `RFB...DecoderError`/`RFBByteReaderError`
that the network client maps into the existing reconnect/diagnostic path. No payload,
coordinate, byte count, palette, or pixel is ever logged (SP-005) — the decode hot path
contains zero `print`/logging.

## D9 — Testing strategy

- **Pure decoders**: crafted `Data` byte arrays (mirroring `RFBRawFramebufferDecoderTests`
  helpers) → assert framebuffer pixels + dirty rects + changed count. Offline, fast.
- **ZRLE/Tight zlib**: produce fixtures by zlib-compressing known tile bytes at test
  time (deterministic) so the inflate path is exercised without a server; an explicit
  persistence test inflates two updates through one context and proves a per-rectangle
  reset corrupts the second.
- **Negotiation + CopyRect/Hextile end-to-end**: `FakeRFBServer` hex fixtures (Raw first
  frame + the encoded update) → assert decoded framebuffer + recorded `SetEncodings`.
- **Residual risk (constitution §III)**: live macOS Screen Sharing / TigerVNC ZRLE/Tight
  throughput, real CopyRect scroll, and a real resolution change are a documented manual
  device pass — no VNC server or physical device is available in this environment.

## D10 — Benchmark transport before enabling push mode by default

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- IANA RFB registry: https://www.iana.org/assignments/rfb/rfb.xhtml

**Decision**: keep the production adaptive/ContinuousUpdates gate conservative, but make
`VNCLiveBenchmark` compare stream-shape transport modes directly:
`request-response`, `continuous-updates`, or `both`.

**Why**:
- RFC 6143's core update flow is request-driven (`FramebufferUpdateRequest` →
  `FramebufferUpdate`). This remains the universal compatibility baseline.
- TigerVNC's viewer exposes auto-selection plus manual `PreferredEncoding`,
  `QualityLevel`, and `CompressLevel` controls, which is a strong signal that
  encoding/quality/transport trade-offs are server- and link-dependent rather than
  globally optimal.
- ContinuousUpdates is an extension code, not the RFC baseline. IANA records it in
  the RFB registry, but real servers differ in support and idle behavior.

**Implementation rule**: the benchmark's continuous mode applies only a fixed
Fence/ContinuousUpdates pseudo-encoding overlay to the selected encoding profile, then
runs the same stream-shape summary pipeline. Reports emit only the transport label plus
existing aggregate latency/FPS/dirty-area/renderer-upload summaries; they still omit host,
dimensions, coordinates, pixels, byte counts, cursor pixels, and raw errors.

## D11 — Active request pacing should be benchmark-backed, not fixed at 30 Hz

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- TightVNC release notes: https://www.tightvnc.com/whatsnew.php

**Decision**: use a 60 Hz-class `1/60` active content-request delay as the
production default, with the separate idle interval/backoff still governing
empty incremental replies.

**Why**:
- RFC 6143 explicitly allows a fast client to regulate incremental
  `FramebufferUpdateRequest` traffic. The right value is therefore a pacing
  policy, not an RFB wire requirement.
- TigerVNC's viewer auto-selects encoding/pixel format from link speed and
  exposes manual `PreferredEncoding`, `QualityLevel`, and `CompressLevel`
  controls; this reinforces that responsiveness vs CPU/network trade-offs must
  stay measurable per server/link.
- Tight encoding and cursor-shape support are both documented as practical
  performance wins: lower compression levels reduce CPU cost, and server cursor
  shape updates avoid framebuffer churn for mouse movement. Naru's default
  should keep those wins while avoiding an unnecessary 30 Hz client-side sleep.

**Live benchmark evidence**: local redacted request/response stream-shape runs
on 2026-06-04 compared content-frame intervals of about 33 ms, 16.7 ms, and
0 ms under the same Tight-first profile. Both faster candidates improved
content-frame FPS over 33 ms; `1/60` keeps a display-rate cap and thermal
headroom while removing most of the avoidable client-side delay.

## D12 — Low Power Mode should reduce VNC stream pressure before thermal escalation

References:
- Apple `isLowPowerModeEnabled`: https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled
- Apple `thermalState`: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property
- Apple power notifications: https://developer.apple.com/documentation/xcode/responding-to-power-notifications

**Decision**: keep thermal pacing as the emergency floor, but also sample
`ProcessInfo.processInfo.isLowPowerModeEnabled` during the frame loop. When Low
Power Mode is active, cap active content requests at 30 Hz and idle empty-update
polling at 125 ms unless thermal state requires an even slower delay.

**Why**:
- Low Power Mode is an explicit user/device power-saving signal. Waiting until
  `.fair`/`.serious` thermal states before reducing a continuous VNC polling loop
  is too reactive for sustained iPhone use.
- Apple documents power-state notifications and `isLowPowerModeEnabled` as the
  supported way to detect that state; Naru can sample the provider per frame
  without storing it in diagnostics.
- Explicit zero-delay fake/test streams remain deterministic. The low-power
  floor only applies when a real configured delay exists.

**Benchmark parity**: `VNCLiveBenchmark` schema v16 records
`streamShapePowerMode` and the fixed low-power content/idle floors so live
request/response probes can compare normal vs low-power pacing without changing
the app or exporting device power state in diagnostics.

## D13 — Sustained performance needs duration-capped VNC probes

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- IANA RFB registry: https://www.iana.org/assignments/rfb/rfb.xhtml

**Decision**: add a duration-capped stream-shape benchmark mode before making
the next production VNC pacing/encoding change. The benchmark must support
sample-capped sweeps for quick comparisons and duration-only sustained runs for
thermal/FPS investigations.

**Why**:
- RFC 6143 keeps normal framebuffer updates request-driven and explicitly says
  fast clients may regulate incremental request rate to avoid excessive traffic.
  Short sample runs are enough to catch protocol regressions, but not enough to
  detect device heat, long-tail decode stalls, or sustained idle-poll pressure.
- TigerVNC exposes auto selection, preferred encoding, compression level,
  quality level, and a 17 ms pointer-event interval. That combination is a
  practical signal that good VNC UX is server/link/device dependent and should
  be tuned from repeated measurements, not a single static encoding order.
- IANA records ContinuousUpdates/Fence as RFB extensions rather than the RFC
  baseline, so sustained experiments still need to compare request/response and
  extension transport modes side by side before changing the production gate.

**Implementation rule**: `VNCLiveBenchmark` schema v17 records
`streamShapeDurationSeconds`. Passing `--stream-shape-samples 0` with
`--stream-shape-duration-seconds` runs until the duration limit, while keeping
the existing redaction boundary: no host, server name, framebuffer dimensions,
coordinates, pixels, byte counts, cursor pixels, or raw error descriptions.
The duration cap also bounds each in-flight update wait and post-update pacing
delay to the remaining duration so long thermal runs do not drift far past
their requested wall-clock window.

## D14 — Keep ContinuousUpdates opportunistic; use duration sweeps before adaptive defaults

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- IANA RFB registry: https://www.iana.org/assignments/rfb/rfb.xhtml

**Decision**: do not force ContinuousUpdates or adaptive-full encoding
renegotiation by default yet. Keep request/response as the compatibility
baseline, keep normal-mode active content pacing at 60 Hz-class, and use the new
duration-only benchmark to collect longer physical-device evidence before
turning on automatic adaptive renegotiation in production.

**Why**:
- A 15 second live duration comparison on macOS Screen Sharing succeeded with
  request/response but failed in ContinuousUpdates mode. Since IANA records
  ContinuousUpdates/Fence as extension codes rather than the RFC baseline,
  production should keep this path opportunistic.
- A 20 second pacing/power comparison kept the 60 Hz-class content interval as
  the best responsiveness default on the measured target. The 30 Hz and
  low-power candidates lowered update pressure but also reduced delivered
  content FPS, so Low Power Mode remains an explicit heat/battery lever rather
  than the normal-mode default.
- A 10 second profile sweep showed adaptive-good-full as promising, but the
  sample is too short and local-low-latency/tight-first variance is high enough
  that enabling automatic adaptive renegotiation by default would be premature.

**Benchmark evidence**: see
`artifacts/benchmarks/2026-06-04-sustained-duration-candidates-summary.md`.

**Revisit criterion**: consider enabling adaptive-full defaults only after a
physical iPhone duration run of at least 5 minutes shows equal-or-better content
FPS or tail latency without worsening thermal pressure, and after the target
server class passes the ContinuousUpdates/Fence path when that extension is part
of the proposed default.

## D15 — Expose power-saver stream pacing as an explicit viewer control

References:
- Apple `isLowPowerModeEnabled`: https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html

**Decision**: add a persisted, non-secret app setting for `balanced` vs
`power-saver` stream pacing. `balanced` remains the default and still encodes as
an empty `{}` settings file; `power-saver` reuses the same 30 Hz content-frame
and 125 ms idle floors that Low Power Mode already applies.

**Why**:
- The 20 second live pacing/power comparison showed low-power pacing reduces
  update pressure but also reduces delivered content FPS, so it should stay an
  explicit user heat/battery lever instead of silently replacing the responsive
  default.
- Users can feel thermal discomfort before iOS reports Low Power Mode or elevated
  thermal state. A viewer-local toggle lets them reduce polling pressure during a
  long session without leaving the remote-control surface.
- RFC 6143 keeps incremental updates client-request-driven, and TigerVNC exposes
  comparable responsiveness-vs-resource controls. Making the trade-off explicit
  keeps Naru measurable across server/link/device combinations.

**Privacy rule**: the setting may be persisted locally as app preference JSON and
reported as fixed `balanced|power-saver` diagnostic context. Diagnostics and
benchmarks must still avoid device power state, target identity, dimensions,
coordinates, pixels, byte counts, cursor pixels, and raw power/latency samples;
only the existing coarse thermal bucket remains allowed for stream-performance
triage.

## D16 — Add benchmark-derived profile recommendations before changing defaults

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- IANA RFB registry: https://www.iana.org/assignments/rfb/rfb.xhtml
- Apple Metal resource options: https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html
- Apple Metal frame-rate guidance: https://developer-mdn.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html

**Decision**: extend the live benchmark report with a safe
request/response-profile recommendation instead of changing production encoding
defaults from a single localhost run.

**Why**:
- RFC 6143 makes RFB framebuffer updates client-request-driven, so profile
  choice, request pacing, and server update shape all interact. A recommendation
  derived from the same aggregate stream-shape probes gives each target/link a
  measurable answer rather than hard-coding one static profile.
- The IANA registry marks ContinuousUpdates/Fence as extensions, and the latest
  localhost run still failed in the ContinuousUpdates receive phase. The
  recommendation therefore ranks request/response candidates only.
- The latest synthetic renderer benchmark showed full uploads are still much
  more expensive than dirty-rect partial uploads and same-frame skips, while the
  live run showed renderer uploads are mostly partial. That points the next
  default-tuning decision toward encoding/profile evidence, not another redraw
  loop change.

**Benchmark evidence**: see
`artifacts/benchmarks/2026-06-04-profile-recommendation-summary.md`.

**Privacy rule**: the recommendation may include only fixed profile labels,
transport mode, aggregate update latency summaries, content FPS, renderer
full-upload permille, slow-sample counts, and received/content sample counts. It
must not include host, server name, framebuffer dimensions, coordinates, pixels,
byte counts, cursor pixels, raw latency samples, raw power state, or raw errors.

## D17 — Request server cursor by default, keep encoding default conservative

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- IANA RFB registry: https://www.iana.org/assignments/rfb/rfb.xhtml
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html

**Decision**: keep the production `localLowLatency` real-encoding order
Tight-first quality-8/compression-1 with Hextile/Raw fallback, but add
Cursor/XCursor pseudo-encodings to the default request. Keep ZRLE compression 0
as a benchmark candidate rather than the static production default. Keep
ContinuousUpdates and adaptive-full renegotiation disabled by default.

**Why**:
- RFC 6143 makes `SetEncodings` client-preference ordered and keeps the normal
  framebuffer stream request/response compatible. The same section defines
  pseudo-encoding requests as extension declarations that unsupported servers
  ignore, so Cursor/XCursor is a safer default improvement than flipping the real
  encoding order on mixed evidence.
- RFC 6143 says a client that requests Cursor pseudo-encoding declares it can
  draw the pointer locally, which can significantly improve perceived performance
  on slow links. Naru already decodes server cursor shapes and draws them in the
  trackpad cursor overlay, with a synthetic fallback when no server cursor exists.
- IANA records ZRLE as a registered RFB encoding, while ContinuousUpdates/Fence
  are extension codes. The safer production move is therefore to keep the
  request/response transport and make server cursor support the default
  extension request.
- TigerVNC exposes automatic encoding selection plus manual compression controls;
  that aligns with keeping ZRLE compression 0 available in benchmarks until a
  future server/profile-specific selector can choose it with stronger evidence.

**Benchmark evidence**: one 60 second redacted localhost/macOS Screen Sharing
run under normal pacing selected `zrle-compression-0`, but a follow-up 60 second
pairwise run selected `tight-first` (6.47 content FPS / 104 ms average update)
over the temporary ZRLE default (6.30 content FPS / 110 ms average update).
Low-power pacing was also close. This is not stable enough to flip the static
real-encoding default, but it is enough to keep ZRLE compression 0 in the
benchmark candidate set.

**Implementation rule**: this default change MUST NOT enable ZRLE,
ContinuousUpdates/Fence, or adaptive-full renegotiation by default. Unsupported
Cursor/XCursor pseudo-encodings must remain harmless; the UI keeps the synthetic
cursor fallback when no server cursor arrives.

## D18 — Split live receive timing before further heat/FPS default changes

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- TightVNC viewer manual: https://www.tightvnc.com/vncviewer.1.php
- TurboVNC H.264 study: https://turbovnc.org/About/H264

**Decision**: extend `VNCLiveBenchmark` with aggregate receive-path timing
before changing more production stream defaults. Each live framebuffer update
may now carry optional safe timing for total receive time, socket-read
waiting/copy time, and derived client-processing time; stream-shape summaries
aggregate those values as avg/p50/p95/min/max.

**Why**:
- RFC 6143's normal framebuffer stream is request/response: a single observed
  update latency includes request write, network/server wait, compressed payload
  reads, decoder work, framebuffer mutation, and local dispatch. Existing
  benchmark fields could show that a frame was slow, but not whether the client
  was burning time locally.
- TigerVNC documents automatic protocol selection that switches between
  stronger compression and faster-to-generate encodings based on link speed.
  TightVNC/TurboVNC documentation likewise frames quality/compression as a CPU
  vs bandwidth tradeoff. Naru needs the same evidence before choosing a static
  encoding or adaptive policy for sustained iPhone sessions.
- Recent local evidence shows renderer full uploads are usually avoided; heat
  therefore needs a benchmark split that can point at network/server wait versus
  local decode/dispatch pressure.

**Privacy rule**: timing fields are aggregate millisecond summaries only. They
must not include host, server name, framebuffer dimensions, coordinates, pixels,
byte counts, cursor pixels, raw per-frame logs, or raw errors. They are emitted
only in benchmark stdout/JSON, not persisted as user diagnostics by default.

## D19 — Keep static encoding default unchanged after timed receive-profile comparison

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- TightVNC viewer manual: https://www.tightvnc.com/vncviewer.1.php
- TurboVNC H.264 study: https://turbovnc.org/About/H264

**Decision**: keep the production `localLowLatency` static encoding default
unchanged after the first schema v19 timed receive-profile comparison. Continue
to treat `zrle-compression-0` as an important benchmark candidate, not a global
default, until longer physical-iPhone evidence is stable across normal and
power-saver modes. Benchmark artifact:
`artifacts/benchmarks/2026-06-04-timed-profile-receive-comparison.md`.

**Why**:
- A 20 second normal-pacing localhost run selected `zrle-compression-0` by lower
  average update latency and zero full-upload samples, but the current
  `local-low-latency` profile still had slightly higher content FPS. This is a
  useful candidate signal, not a decisive default switch.
- A matching low-power run saw `local-low-latency` fail with
  `stream-incremental-read-timeout`, while `zrle-compression-0` completed but
  produced full-dirty/full-upload outliers. The profile evidence is still
  sensitive to pacing and screen state.
- The receive split showed most p95 latency still tracks network/server read
  wait, while rare full-dirty/full-upload frames dominate client-processing max.
  That points the next work toward longer physical-device runs with controlled
  screen activity and thermal observation, not another static default flip.
- RFC 6143's request/response stream gives the client pacing control, while
  TigerVNC/TightVNC/TurboVNC documentation all frame compression choice as a
  CPU/bandwidth/latency tradeoff. Naru should preserve compatibility until the
  benchmark evidence can distinguish profile choice from server repaint shape.

**Follow-up criterion**: revisit the static default or add adaptive
profile-specific switching only after a physical iPhone run shows the same
profile winning across normal and power-saver modes without increasing
full-upload outliers, timeouts, or client-processing tails.

## D20 — Share coarse receive-timing buckets from the app diagnostic path

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- TightVNC viewer manual: https://www.tightvnc.com/vncviewer.1.php

**Decision**: bump app diagnostics to schema v6 and include only coarse
receive-timing buckets for active-session reports: average/max total receive,
average/max network read, and average/max client processing. Buckets are fixed
catalog values: `notMeasured`, `subFrame`, `interactive`, `lagging`, and
`stalled`.

**Bucket thresholds**: `subFrame` is below 16 ms, roughly inside one 60 Hz
display frame. `interactive` is below 80 ms, where a single update can still
feel responsive enough for remote-control input. `lagging` is below 250 ms,
where the session is visibly delayed but still progressing. `stalled` covers
250 ms and above, which is the support signal for checking server/network wait,
decode pressure, or renderer outliers before changing defaults.

**Why**:
- The live benchmark now splits receive timing, but the physical iPhone support
  path still needs enough data to tell whether a hot/low-FPS session is mostly
  waiting on the server/network or spending time in local decode/dispatch.
- RFC 6143's request/response stream rolls server wait, network payload reads,
  decoding, framebuffer mutation, and local dispatch into one visible update.
  Coarse buckets let support triage that path without exporting raw telemetry.
- TigerVNC/TightVNC expose encoding/compression choices because the useful
  trade-off depends on server, link, and client CPU. App diagnostics should
  provide the same high-level evidence before Naru changes more defaults.

**Privacy rule**: diagnostics must not include raw milliseconds, raw timing
samples, host identity, framebuffer dimensions, rectangle coordinates, pixels,
byte counts, device power state, or raw errors. Missing timing from older app
paths decodes as `notMeasured` so older support payloads remain analyzable.

## D21 — Benchmark actual server encoding mix, not just requested profile

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- TightVNC viewer manual: https://www.tightvnc.com/vncviewer.1.php

**Decision**: extend `VNCLiveBenchmark` schema v20 with safe actual encoding
mix counts per stream-shape sample and per summary. Counts use fixed catalog
labels (`raw`, `copyRect`, `hextile`, `zrle`, `tight`, cursor/desktop pseudo
labels, and ContinuousUpdates end events) rather than raw unsupported encoding
codes.

**Why**:
- RFC 6143 defines `SetEncodings` order as a client preference hint; servers can
  still choose based on what they support or what is easier to produce. Profile
  labels therefore prove what Naru requested, not what the server sent.
- TigerVNC and TightVNC expose preferred encoding, quality, and compression
  controls because practical VNC performance is server/link/client dependent.
  Naru needs actual server encoding evidence before changing static defaults or
  enabling adaptive renegotiation.
- Recent timed receive comparisons showed close and sometimes conflicting
  Tight-first vs ZRLE-compression-0 results. Actual encoding mix lets future
  benchmark runs distinguish a profile's negotiated outcome from screen-content
  repaint shape, without adding sensitive telemetry.

**Privacy rule**: benchmark reports may include only aggregate counts of known
safe encoding labels. They must not include host identity, framebuffer
dimensions, rectangle coordinates, pixels, compressed bytes, byte counts,
cursor pixels, unsupported raw encoding codes, raw errors, or per-rectangle
payload details.

## D22 — Adaptive client-pressure pacing should be local and temporary

References:
- Apple power notifications: https://developer.apple.com/documentation/xcode/responding-to-power-notifications
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html

**Decision**: when the live app observes repeated content frames whose local
client-processing time is in the lagging bucket, temporarily apply the same
power-saver pacing floor already used by the explicit viewer setting and iOS Low
Power Mode. Keep this state memory-only, per stream, and reset it naturally
after a bounded number of subsequent update decisions.

**Why**:
- Apple recommends reducing screen-update and networking frequency under power
  or thermal pressure. Users can feel heat before `thermalState` escalates, and
  the app already measures enough receive-path timing to distinguish client work
  from server/network wait.
- RFC 6143 keeps incremental framebuffer requests client-driven and explicitly
  allows fast clients to regulate request rate to avoid excessive traffic.
- TigerVNC exposes automatic and manual performance controls because encoding,
  bandwidth, latency, and client CPU costs vary by server/link. Naru should keep
  the responsive default but protect sustained iPhone sessions when the local
  frame path repeatedly looks expensive.

**Privacy rule**: the trigger uses raw timing only in memory while the stream is
alive. Diagnostics continue to export only coarse timing buckets, power mode,
thermal bucket, renderer aggregates, and safe encoding counts.

**Rejected**: automatically changing the persisted `balanced|power-saver`
setting or renegotiating encodings from this signal. Those are user-visible or
server-affecting policy changes and still need longer physical-device evidence.

## D23 — Benchmark app-style client-pressure pacing before further defaults

References:
- Apple power notifications: https://developer.apple.com/documentation/xcode/responding-to-power-notifications
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html

**Decision**: extend `VNCLiveBenchmark` with an opt-in
`--stream-shape-client-pressure app` mode that mirrors the app's local
client-processing pressure trigger: repeated lagging content frames temporarily
apply the same power-saver pacing floor for subsequent stream-shape requests.
Keep the default `off` so historical benchmark runs remain comparable.

**Why**:
- The app can now protect hot sustained sessions by backing off when local
  client-processing repeatedly looks expensive. The live benchmark needs the
  same mode before physical iPhone/Mac runs can compare normal pacing against
  adaptive client-pressure pacing using the same target, screen state, profile,
  and transport.
- The trigger continues to distinguish local decode/dispatch pressure from
  socket/server wait by looking only at the derived client-processing timing.
- This is safer than changing encoding defaults: it adds a measurement mode
  first, so future defaults can be based on whether adaptive pacing improves
  heat/FPS/tail-latency observations without hiding profile or server behavior.

**Privacy rule**: schema v22 reports only the selected fixed mode label, fixed
app threshold/recovery constants, and aggregate adaptive pacing sample
count/permille. Raw timing samples, host identity, framebuffer dimensions,
coordinates, pixels, byte counts, cursor pixels, and raw errors remain
excluded.

## D24 — Power-saver sessions should request the sustained ZRLE candidate

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- TightVNC viewer manual: https://www.tightvnc.com/vncviewer.1.php

**Status**: historical decision, superseded for balanced sessions by D25. The
power-saver policy still uses the same ZRLE compression-0 profile, but D25 also
promotes that profile to the balanced default.

**Decision**: keep the default `balanced` app path on `localLowLatency`, but
when the explicit viewer power-saver setting or system Low Power Mode is active
at session start, re-advertise a request/response sustained profile that
prefers ZRLE with compression level 0 and still requests server cursor
pseudo-encodings. This is an automatic power policy, not a manual encoding
picker.

**Why**:
- Prior redacted macOS Screen Sharing runs repeatedly identified
  `zrle-compression-0` as the strongest sustained request/response candidate,
  including a low-power timed run where `local-low-latency` timed out while
  `zrle-compression-0` completed.
- The evidence is still too mixed to flip the global static default; balanced
  should preserve the Tight-first profile with server cursor support.
- RFC 6143 makes `SetEncodings` a client preference list that can be resent
  safely on an active session. TigerVNC/TightVNC both expose compression
  controls, reinforcing that power/bandwidth/latency tradeoffs are legitimate
  session policy.

**Privacy rule**: the app sends only fixed catalog encoding and
pseudo-encoding codes. It does not log or export host identity, framebuffer
dimensions, coordinates, pixels, byte counts, compressed payloads, raw timing
samples, raw power state, or raw errors.

## D25 — Balanced sessions should also request the sustained ZRLE candidate

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- TightVNC release notes: https://www.tightvnc.com/whatsnew.php

**Decision**: switch the production `localLowLatency` balanced encoding profile
from Tight-first to request/response ZRLE with compression level 0, retaining
Hextile/CopyRect/Raw fallback, server cursor pseudo-encodings, and Extended
Clipboard. Leave ContinuousUpdates and automatic adaptive renegotiation disabled
by default.

**Why**:
- Schema v20+ benchmark output now records the actual encoding mix, not only the
  requested profile. On the local macOS Screen Sharing target, repeated
  duration runs showed the Tight-first profile being served as Raw, while
  `zrle-compression-0` negotiated actual ZRLE.
- In the 2026-06-05 normal 20 second run, Tight-first delivered 5.20 content FPS
  with Raw-only updates, client-processing p95 96 ms, and adaptive
  client-pressure pacing active for 549 permille of samples. ZRLE compression-0
  delivered 6.35 content FPS, actual ZRLE-only updates, client-processing p95
  8 ms, and no full-upload samples.
- In the matching low-power-paced run, Tight-first had slightly lower aggregate
  update latency but still produced Raw-only updates and client-processing p95
  100 ms. ZRLE compression-0 kept client-processing p95 to 9 ms. Since the user
  report is heat and low FPS during sustained iPhone use, lower local processing
  tails are the stronger default signal than a small low-power average-latency
  difference.
- A post-change 12 second `local-low-latency` smoke confirmed the label now
  receives actual ZRLE-only updates on this target, with client-processing p95
  10 ms.
- RFC 6143 treats `SetEncodings` order as a preference list and lets clients
  regulate request traffic. TigerVNC/TightVNC both expose encoding,
  compression, quality, and cursor-shape controls, reinforcing that a practical
  viewer should choose defaults from measured server behavior rather than a
  static theory of which encoding should win.

**Privacy rule**: the app and benchmark use only fixed catalog encoding
pseudo-encoding codes and aggregate safe labels. They must not log or export
host identity, framebuffer dimensions, coordinates, pixels, byte counts,
compressed payloads, raw timing samples, raw power state, cursor pixels, or raw
errors.

## D26 — App frame-apply timing should be measured separately from receive timing

References:
- Apple Metal frame-rate guidance: https://developer-mdn.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html
- Apple power notifications: https://developer.apple.com/documentation/xcode/responding-to-power-notifications
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143

**Decision**: add a coarse app-frame-apply timing signal to active-session
diagnostics and the adaptive client-pressure trigger. This measures the
MainActor work after a frame has been received and decoded: session state
publication, preview throttling, framebuffer forwarding, cursor/liveness
bookkeeping, and PiP/renderer handoff. It is intentionally separate from the
RFB receive timing split, which covers socket wait plus decoder/client
processing before the frame enters the app model.

**Why**:
- A hot or stuttery physical iPhone session can be caused by local app apply /
  render-handoff pressure even when RFB network-read and decode timing look
  healthy. Prior diagnostics could not distinguish that case.
- Apple frame-rate guidance emphasizes staying within the display frame budget;
  a repeated app-apply bucket above the interactive threshold is therefore a
  local pressure signal, not a server/network wait signal.
- RFC 6143 keeps normal framebuffer updates demand-driven by the client. When
  local apply work repeatedly lags, applying the existing temporary
  power-saver pacing floor to subsequent requests is a compatible way to reduce
  sustained client pressure without changing persisted settings or
  renegotiating encodings.

**Privacy rule**: diagnostics export only sample count plus fixed
`notMeasured|subFrame|interactive|lagging|stalled` buckets for average/max app
frame apply timing. They must not export raw milliseconds, raw samples,
dimensions, coordinates, pixels, byte counts, power state, target identity, or
raw errors. The adaptive trigger may use raw timing in memory only while the
stream is alive.

## D27 — Adaptive pressure should catch sustained 30fps-budget misses

References:
- Apple Metal frame-rate guidance: https://developer-mdn.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html
- Apple `CADisplayLink.preferredFrameRateRange`: https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143

**Decision**: keep the existing severe adaptive pacing trigger at 80 ms for 3
consecutive content frames, and add a sustained moderate trigger at 34 ms for 8
consecutive content frames. Both client-processing timing and app-frame-apply
timing feed the runtime trigger; the benchmark `app` client-pressure mode
mirrors the receive-side client-processing portion.

**Why**:
- The old severe trigger caught obvious stalls, but it let a device continue
  requesting at the balanced 60 Hz-class cadence when local work repeatedly sat
  just above the 30 fps frame budget. That is exactly the heat / low-FPS zone
  reported during sustained iPhone sessions.
- A 34 ms threshold is intentionally just above the 30 fps budget. Requiring 8
  consecutive content frames avoids backing off for isolated decode/apply
  spikes, while still reacting before the session spends minutes in a marginal
  local-processing regime.
- RFC 6143 framebuffer updates are client-regulated in the request/response
  path, so applying the existing temporary power-saver pacing floor is a
  protocol-compatible backpressure mechanism that does not change persisted
  viewer settings or encoding negotiation.

**Privacy rule**: raw timing stays memory-only. Diagnostics and benchmark
reports continue to export only fixed labels, aggregate activation counts, and
bucketed timing summaries; they must not export raw milliseconds, dimensions,
coordinates, pixels, byte counts, host identity, power state, or raw errors.

## D28 — Balanced request cadence should start at the sustained 30fps floor

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html

**Decision**: set the production balanced request/response content-frame
cadence to 30fps-class pacing (`1/30s`) instead of 60fps-class pacing, and make
`VNCLiveBenchmark` use the same default stream-shape frame interval. Keep
explicit zero-delay fake/test paths and caller-provided benchmark intervals
unchanged.

**Why**:
- RFC 6143 notes that a fast client may regulate incremental
  `FramebufferUpdateRequest` rate to avoid excessive network traffic. Naru is
  demand-driven against macOS Screen Sharing, so the client cadence is a real
  power/latency lever rather than only a display preference.
- TigerVNC documents automatic selection of encoding/pixel format based on link
  speed and exposes compression/quality knobs. Naru does not yet expose a manual
  viewer-performance panel, so the balanced default should be conservative
  enough for the primary sustained iPhone workflow.
- A redacted localhost macOS Screen Sharing run on 2026-06-05 showed the
  current ZRLE default did not gain meaningful content FPS from 60fps-class
  requests, but did create much worse client-processing tail work. The 60fps run
  reported content FPS 4.75 and client-processing p95 138ms with adaptive
  pacing active for 319 permille of samples. A 30fps run reported content FPS
  4.33 and client-processing p95 8ms with no adaptive activation. A 45fps probe
  had one full-dirty/full-upload outlier and a very large max
  client-processing sample, so it is not the balanced default.

**Privacy rule**: benchmark evidence is aggregate-only. It omits host, password,
server name, framebuffer dimensions, coordinates, pixels, byte counts, cursor
pixels, compressed payloads, raw errors, and raw per-frame timing samples.

## D29 — Viewport transforms should be display-linked during gestures

References:
- Apple Metal frame-rate guidance: https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html
- Apple `CADisplayLink.preferredFrameRateRange`: https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html

**Decision**: keep local viewport navigation on the UIKit/Core Animation layer
transform path, but coalesce pinch, zoomed-pan, and trackpad auto-pan transform
applications onto a one-shot `CADisplayLink`. Parent-driven sync, layout, and
gesture-end flushes still apply immediately so the final state cannot lag behind
the model.

**Why**:
- Apple frame-rate guidance emphasizes stable presentation cadence and says
  apps that cannot sustain a frame budget should reduce work to avoid jitter.
  Applying a layer transform for every raw gesture callback can exceed the
  display cadence on a hot iPhone even though only the newest transform is
  visible at the next refresh.
- TigerVNC documents a default 17 ms pointer-event interval, showing that
  practical VNC viewers already rate-limit high-frequency input traffic to a
  screen-scale cadence. Naru already coalesces trackpad pointer moves on the
  wire; the local viewport transform should follow the same principle.
- RFC 6143 keeps framebuffer updates client-regulated in the request/response
  path. Reducing local per-sample viewport work complements the 30fps request
  cadence and adaptive client-pressure pacing without changing protocol
  correctness or persisted viewer settings.

**Privacy rule**: this change only changes local transform scheduling. It must
not log or export gesture coordinates, framebuffer dimensions, pixels, cursor
pixels, raw timestamps, raw timing samples, host identity, or raw errors.

## D30 — Visible viewport transforms should stay immediate under touch

References:
- Apple Metal frame-rate guidance: https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html
- Apple `CADisplayLink.preferredFrameRateRange`: https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html

**Decision**: supersede the visible-transform part of D29. Keep pinch,
zoomed-pan, and trackpad auto-pan layer transforms immediate on the
UIKit/Core Animation hot path so the framebuffer tracks the user's finger.
Continue to defer SwiftUI/PiP viewport-state publication until gesture end and
keep incoming framebuffer upload suspension/redraw throttling during viewport
gestures.

**Why**:
- Physical-device feedback after the display-link transform experiment showed
  the viewport felt sticky and stepped during zoom/pan. For photo-viewer-like
  navigation, input-to-visible-transform latency is more important than
  coalescing a cheap layer matrix write.
- The expensive work is not the affine transform itself; it is SwiftUI state
  invalidation, PiP focus sync, framebuffer upload, and redraw churn. Those
  paths remain deferred/throttled by the existing gesture interaction guard.
- Apple frame-rate guidance still supports stable pacing for rendering work,
  but this path is a compositor transform over the current texture. TigerVNC's
  pointer-event interval remains useful for wire traffic, not for delaying
  local content under the active touch point.

**Privacy rule**: this change must not log or export gesture coordinates,
framebuffer dimensions, pixels, cursor pixels, raw timestamps, raw timing
samples, host identity, or raw errors. Compose commit hardening must not log or
export draft text.

## D31 — Pacing diagnostics should explain low-FPS and heat reports

References:
- Apple Energy Efficiency Guide, Low Power Mode: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LowPowerMode.html
- Apple `ProcessInfo.thermalState`: https://developer.apple.com/documentation/foundation/processinfo/1417480-thermalstate
- Apple rendering efficiency guidance: https://developer.apple.com/documentation/xcode/improving-your-app-s-rendering-efficiency

**Decision**: extend active-session diagnostics with aggregate stream pacing
signals: pacing-delay sample count, average/max pacing-delay buckets, and sample
counts where the effective delay was raised by thermal pacing, power-saver
pacing, or sustained empty-update backoff.

**Why**:
- Hot-device reports need to separate “the app is overloaded” from “the app is
  intentionally backing off.” Existing diagnostics expose FPS, receive/apply
  timing, renderer upload timing, viewport redraw pressure, adaptive pressure,
  and latest thermal bucket, but they do not say which pacing floor actually
  shaped the stream loop.
- Apple documents Low Power Mode as a state where iOS may reduce CPU/GPU
  performance and recommends apps reduce work such as animations/frame rates or
  networking. Apple also documents `thermalState` as a signal to reduce system
  usage. Naru already reacts to both; diagnostics should show when those
  reactions were active so a low-FPS trace is interpretable.
- Empty-update backoff is a healthy behavior on static screens. Counting it
  prevents a static terminal from being mistaken for stream starvation or
  decode/render pressure.

**Privacy rule**: diagnostics export only fixed labels, counts, and timing
buckets. They must not export raw delays, raw timing samples, device power
state, host identity, dimensions, coordinates, pixels, byte counts, cursor
pixels, or draft text.

## D32 — Live benchmark should reproduce viewport-interaction pacing

References:
- RFC 6143: https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer options: https://tigervnc.org/doc/vncviewer.html
- Apple Energy Efficiency Guide, Minimize Networking:
  https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeNetworking.html

**Decision**: extend `VNCLiveBenchmark` with an opt-in
`--stream-shape-viewport-interaction off|app` mode. The `app` mode mirrors the
production temporary viewport-interaction pacing floors used during zoom/pan
interaction: 15fps-class content-frame requests and 125 ms idle polling. Bump
the benchmark report to schema v25 and export the fixed mode/floors plus
aggregate viewport-interaction pacing sample count and permille.

**Why**:
- Physical-device feedback still reports unnatural zoom/pan, low frame rate,
  heat, and broken Compose input. The benchmark needs to reproduce the stream
  cadence used while local viewport interaction is active before subsequent UX
  tuning can compare normal, low-power, client-pressure, and
  viewport-interaction runs on the same target.
- RFC 6143 explicitly allows a fast client to regulate incremental
  `FramebufferUpdateRequest` rate to avoid excessive traffic. That makes
  viewer-side request pacing a protocol-compatible way to keep network/decode
  work from competing with local gesture rendering.
- TigerVNC exposes viewer-side rate/encoding controls such as pointer-event
  interval and preferred encoding. Practical VNC clients therefore treat
  viewer pacing and encoding choices as operational performance controls, not
  server-only behavior.
- Apple's networking energy guidance recommends reducing repeated transfers and
  minimizing network work. During pinch/pan, locally responsive compositor
  transforms are more important than requesting every possible remote frame, so
  the live benchmark should make that temporary reduction measurable.

**Privacy rule**: reports export only fixed mode labels, fixed pacing floors,
aggregate pacing sample counts, and permille ratios. They must not export
coordinates, dimensions, pixels, cursor pixels, byte counts, raw delays, raw
timing samples, host identity, raw errors, or Compose draft text.

## D33 — Zoomed trackpad pan should preserve visible cursor travel

References:
- Apple Metal command buffer guidance:
  https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/CommandBuffers.html
- RFC 6143 pointer event message:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: reduce the default zoomed trackpad pan coupling from `0.72` to
`0.48`. The viewport still pans with the cursor while zoomed, but at least half
of a representative touch delta remains visible as cursor travel on screen
before edge-reveal auto-pan contributes additional movement.

**Why**:
- Physical iPhone feedback reported that zoom/pan and trackpad navigation still
  felt choppy and unnatural. The previous coupling made the viewport cancel too
  much of the visual cursor movement, so the cursor appeared to lag or stick
  while the framebuffer moved.
- Apple Metal guidance warns that excessive command-buffer work and CPU/GPU
  synchronization can cause stalls; the app should keep navigation on the
  UIKit/Core Animation transform path rather than reintroducing per-sample
  Metal redraws. This tuning changes pure gesture math instead of adding render
  work.
- RFB pointer moves remain coalesced separately from the local cursor path,
  preserving protocol order while bounding socket pressure.

**Verification**:
- `PointerGestureResolverTests.testZoomedTrackpadCursorKeepsMostTouchTravelVisible`
  proves a zoomed trackpad drag leaves at least 50% of the touch delta as
  visible cursor travel.
- Existing auto-pan tests continue to prove viewport pan still starts before
  the cursor reaches the edge and does not snap to the full reveal delta.

## D34 — Marked-text Compose changes should refresh local binding state

**Decision**: while UIKit reports marked text, the Compose bridge now adopts the
resolved current `UITextView` string into the local SwiftUI binding, but still
does not propagate draft changes to the app model until marked text commits.

**Why**:
- Korean/CJK IMEs can keep candidate text in UIKit even when SwiftUI's binding
  snapshot is stale. Leaving the binding stale made later external model sync or
  send stabilization more likely to compare against an old prefix.
- Writing the local binding is safe because `updateUIView` still defers writes
  back into `UITextView` while marked text exists. The data flow is one-way
  UIKit -> local state during composition, not SwiftUI -> UIKit overwrite.
- The product boundary remains unchanged: Compose & Send still sends only when
  the user taps Send, and marked text is not treated as a remote injection
  event.

**Verification**:
- `RemoteInputDockSyncPolicyTests.testAdoptsUIKitComposeTextChangeWhileMarkedTextUpdatesLocalBinding`
  covers the local adoption policy.
- `RemoteInputDockSyncPolicyTests.testDefersLocalComposeTextPropagationWhileMarkedTextIsActive`
  continues to prove model propagation is blocked during active marked text.

## D35 — Viewport stutter diagnostics need ratios, not raw samples

References:
- Apple `CADisplayLink.preferredFrameRateRange`:
  https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- Apple battery-use guidance:
  https://developer.apple.com/documentation/xcode/reducing-your-app-s-battery-use
- RFC 6143 framebuffer update request:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: active-session diagnostics schema v18 exports two additional
safe aggregate viewport ratios: `viewportGestureLongFramePermille` and
`viewportIncomingFrameDeferredPermille`. The existing
`viewportRedrawRequestCount` and `viewportRedrawFlushCount` counters are also
wired to the UIKit viewport hot path so their companion counts reflect actual
gesture-time redraw decisions.

**Why**:
- Physical iPhone feedback says zoom/pan still feels choppy, but raw gesture
  timestamps, coordinates, frame dimensions, or pixels cannot leave the device.
  Counts alone show that long frames happened; permille ratios show whether the
  issue is rare or dense enough to explain a “stair-step” feel.
- Apple notes that display-link callback frequency is affected by device
  capability, system policy, Low Power Mode, and thermal state. A safe ratio
  lets reports remain interpretable even when the device shifts between 120,
  60, or lower refresh behavior.
- RFC 6143 allows fast clients to regulate incremental
  `FramebufferUpdateRequest` traffic. The deferred-incoming-frame ratio helps
  separate intentional viewer-side stream throttling during touch interaction
  from local gesture-loop stalls.

**Privacy rule**: diagnostics export only aggregate counts, permille ratios,
catalog buckets, and fixed labels. They must not export gesture coordinates,
display dimensions, pixels, cursor pixels, byte counts, raw timestamps, raw
timing samples, host identity, raw errors, device model, or Compose draft text.

## D36 — Viewport stutter diagnostics need a fixed hint label

References:
- Apple MetricKit `MXAnimationMetric`:
  https://developer.apple.com/documentation/metrickit/mxanimationmetric
- Apple MetricKit overview:
  https://developer.apple.com/documentation/metrickit
- RFC 6143 framebuffer update request:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: active-session diagnostics schema v19 derives a fixed-catalog
`viewportStutterHint` from the safe v18 viewport ratios:
`notMeasured`, `none`, `gestureLoopPressure`, `incomingFrameDeferral`, or
`mixedViewportPressure`.

**Why**:
- Physical iPhone feedback can arrive as a copied diagnostic JSON without raw
  trace files. A fixed label gives the next debugging turn an immediate branch:
  tune the local gesture/render loop, tune stream redraw deferral, or investigate
  both.
- Apple MetricKit treats animation hitches as ratios rather than raw frame
  timestamps in its aggregate animation metrics. Naru's hint follows that same
  privacy-preserving shape while remaining session-local and manually shared.
- RFC 6143 permits a fast client to regulate incremental update requests to
  avoid excessive traffic. That makes `incomingFrameDeferral` a legitimate
  protocol-side signal, not automatically a local rendering failure.

**Privacy rule**: diagnostics export only the fixed hint label and the existing
aggregate counts/ratios/buckets. They must not export raw gesture timestamps,
coordinates, display dimensions, pixels, cursor pixels, byte counts, raw
network errors, device model, host identity, or Compose draft text.

## D37 — Viewport interaction should trickle remote frames and give IME more settle time

References:
- Apple `CADisplayLink.preferredFrameRateRange`:
  https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- Apple battery-use guidance:
  https://developer.apple.com/documentation/xcode/reducing-your-app-s-battery-use
- RFC 6143 framebuffer update request:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: replace strict gesture-time remote redraw suspension with a
15fps redraw trickle that allows the first incoming frame during pinch/pan, and
treat every trackpad drag as a viewport interaction for purposes of keeping
SwiftUI stream-frame churn out of the pointer hot path. Tighten trackpad
pointer/cursor coalescing to a one-refresh-class cadence and extend Compose
send stabilization to cover slower Korean/CJK marked-text commits.

**Why**:
- Physical iPhone feedback still reports stepped zoom/pan and low apparent
  frame rate. A fully suspended remote redraw path keeps the current texture
  moving locally, but it can make the remote session look frozen while the user
  is navigating. A 15fps trickle keeps video continuity without returning to
  unbounded upload pressure.
- Trackpad mode now paints the hot cursor in the Metal host immediately, but
  the remote pointer write cadence must also stay tight enough that server-side
  hover/cursor echoes do not feel detached from the finger.
- UIKit IME commit timing can lag the button tap that initiates Compose send.
  A wider stabilization window is a bounded UX cost and is safer than sending a
  prefix of marked Korean/CJK text.

**Privacy rule**: the change exports no new raw data. Gesture timings,
coordinates, pixels, cursor pixels, dimensions, byte counts, host identity,
device identity, and Compose draft text remain out of diagnostics.

## D38 — Physical viewport state should not lag until gesture end, and Mac paste should use documented VNC modifier mapping

References:
- Apple `CADisplayLink.preferredFrameRateRange`:
  https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- RealVNC Mac keyboard mapping:
  https://help.realvnc.com/hc/en-us/articles/360002250597-Keyboard-Mapping-To-and-From-a-Mac
- RFC 6143 KeyEvent:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: keep visible pinch, zoomed-pan, deceleration, and trackpad
auto-pan transforms immediate on the UIKit/Core Animation path, but publish the
coalesced viewport transform to SwiftUI/PiP state on a display-link cadence
instead of waiting exclusively for gesture end. For Compose & Send to macOS VNC
targets, emit `Alt_L+v` for `.commandV` and wait 300 ms after clipboard set
before the paste shortcut.

**Why**:
- Physical iPhone feedback still reports zoom/pan as stepped and unnatural.
  Deferring every SwiftUI/PiP viewport-state update until gesture end keeps the
  visible layer responsive, but leaves surrounding state one gesture behind.
  A display-link publish keeps state fresh at screen cadence while avoiding
  per-sample SwiftUI churn.
- RealVNC's Mac mapping documentation lists the default left Command mapping
  as `Alt_L` and the right Command path as Windows/Super keysyms. `Meta_L` is a
  protocol keysym in RFC 6143, but it is not the documented Mac Command default
  mapping for common VNC viewer/server combinations. Using `Alt_L+v` therefore
  better matches Mac Screen Sharing paste behavior.
- `ClientCutText` and paste key events are independent RFB client messages, so
  the server may apply clipboard text asynchronously. A 300 ms local-only
  settle window is still short to the user, but protects slower macOS Screen
  Sharing paths better than a 120 ms window.

**Privacy rule**: this change exports no new raw data. It must not log or
export gesture coordinates, timing samples, display dimensions, pixels, cursor
pixels, byte counts, host identity, device identity, raw key events, or Compose
draft text.

## D39 — Do not treat unconfirmed UTF-8 clipboard sends as reliable Compose

References:
- RFC 6143 ClientCutText:
  https://www.rfc-editor.org/rfc/rfc6143
- RFC 6143 pseudo-encoding confirmation rule:
  https://www.rfc-editor.org/rfc/rfc6143
- RealVNC Mac paste guidance:
  https://help.realvnc.com/hc/en-us/articles/360002253738-Copying-and-Pasting-Text
- RealVNC Mac keyboard mapping:
  https://help.realvnc.com/hc/en-us/articles/360002250597-Keyboard-Mapping-To-and-From-a-Mac

**Decision**: keep ASCII/Latin-1 legacy `ClientCutText` as an unconfirmed VNC
clipboard path, but reject Korean/CJK/emoji Compose payloads unless the active
server has confirmed Extended Clipboard UTF-8 text provide support. Preserve the
documented Mac `Alt_L+v` paste mapping, but classify UTF-8 payloads on
unconfirmed clipboard sessions as a safe failure before writing clipboard bytes
or paste key events.

**Why**:
- RFC 6143 defines `ClientCutText` / `ServerCutText` as ISO 8859-1 only and
  explicitly states that text outside Latin-1 cannot be transferred through the
  base message. The same RFC says pseudo-encoding support must be assumed absent
  until extension-specific confirmation arrives.
- RealVNC documents `Alt+V` as the non-Mac-to-Mac paste gesture and `Alt_L` as
  the default left Command keysym mapping, so the paste shortcut choice is not
  the primary blocker for multilingual Compose.
- A local redacted macOS Screen Sharing probe on 2026-06-05 connected over VNC,
  sent `ClientCutText` for ASCII and UTF-8 probe strings, and observed that the
  macOS pasteboard did not adopt either payload. Treating a socket write as
  successful Compose therefore produces a false-positive UX on the founder's
  target path.
- The product's local-composition promise is better served by an honest failure
  plus future helper/confirmed-clipboard path than by sending Korean/CJK/emoji
  through a channel known to be Latin-1 or unacknowledged.

**Privacy rule**: the probe and app behavior must not log or export the VNC
password, raw clipboard contents, Compose draft text, host name, framebuffer
pixels, coordinates, raw key events, byte payloads, or exact timing samples.

## D40 — Re-try 30 Hz mid-gesture redraw as a bounded smoothness candidate

References:
- RFC 6143 framebuffer updates and encodings:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC automatic protocol selection:
  https://tigervnc.org/doc/vncviewer.html
- Apple `CADisplayLink.preferredFrameRateRange`:
  https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange

**Decision**: raise the active viewport-gesture incoming-frame redraw trickle
from 15 Hz to 30 Hz while keeping framebuffer uploads suspended except for the
bounded throttle slot and the final gesture-end flush.

**Why**:
- Physical iPhone feedback after the 15 Hz recovery path still reports
  zoom/pan as visibly low frame rate. The local viewport transform remains on
  the UIKit/Metal hot path, but remote content changes behind that transform
  can still look frozen when only 15 redraw slots per second are allowed.
- RFC 6143 treats updates as rectangle batches and commonly deployed clients
  rely on encoding/pixel-format selection to trade bandwidth, CPU, and
  interaction feel. TigerVNC documents this as starting conservative and
  switching to less expensive generation when the link can support it. A 30 Hz
  gesture redraw cap follows the same middle path: improve perceived motion
  without reopening an unbounded 60 Hz texture-upload path.
- Prior physical feedback showed that pushing too much stream/render work into
  the gesture loop can make phones hot. Keeping this as a capped redraw trickle
  instead of continuous uploads preserves diagnostics: `viewportStutterHint`,
  redraw deferral ratios, renderer-upload buckets, stream pacing buckets, and
  thermal pacing counts can decide whether 30 Hz is a net win on the device.

**Privacy rule**: the change exports no new raw data. Gesture coordinates,
raw timing samples, display dimensions, pixels, cursor pixels, byte counts,
host identity, device identity, power state, and Compose draft text remain out
of diagnostics and benchmark artifacts.

## D41 — Prefer strict local continuity during gestures and best-effort UTF-8 unknown sends

References:
- RFC 6143 framebuffer updates and ClientCutText:
  https://www.rfc-editor.org/rfc/rfc6143
- Apple `CADisplayLink.preferredFrameRateRange`:
  https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange

**Decision**: supersede the D40 production behavior for physical iPhone
sessions: while a local viewport gesture is active, do not allow a first or
periodic pending framebuffer upload bypass. Keep pinch/pan/trackpad viewport
navigation on the current Metal texture and flush the latest deferred remote
frame when the gesture settles. Also hold the immersive control-bar auto-hide
transition while the viewport is being manipulated so SwiftUI chrome animation
does not overlap the UIKit/Metal hot path.

For Compose, supersede the D39 "unknown equals failure" behavior without
claiming reliability: if a UTF-8 payload needs more than Latin-1 and the helper
text bridge is reachable, route through the helper first. If the VNC server has
explicitly reported UTF-8 clipboard as unsupported, fail before writing
clipboard bytes. If support is still unknown and no helper route is available,
attempt a legacy VNC clipboard paste as best-effort and leave the result
`unknown` with a warning that Korean/CJK text may paste incorrectly.

**Why**:
- Physical feedback after the D40 30 Hz redraw candidate still reports choppy
  zoom/pan. On small iPhone thermal budgets, local continuity is more important
  than sampling fresh remote content mid-gesture; a single gesture-end flush is
  easier to reason about and matches the Photos-like local navigation target.
- The app model already coalesces incoming changed frames while viewport
  interaction is active. Making the Metal host strict as well closes race
  windows where a SwiftUI update can still ask for a gesture-time upload.
- RFC 6143 keeps base `ClientCutText` constrained to ISO 8859-1, so unknown
  UTF-8 cannot be reported as reliable. However, failing before any attempt is
  too conservative for real private-network VNC deployments that may accept
  UTF-8 bytes without confirming Extended Clipboard caps. Status `unknown`
  preserves honesty while giving the user a practical retry path.

**Privacy rule**: the change exports no new raw data. Gesture coordinates,
raw timing samples, display dimensions, pixels, cursor pixels, byte counts,
host identity, device identity, power state, paste payload bytes, and Compose
draft text remain out of diagnostics and benchmark artifacts.

## D42 — Cool the RFB stream more aggressively during local viewport gestures

References:
- RFB 3.8 framebuffer update flow:
  https://vnc.alice.ws/novnc/docs/rfbproto-3.8.pdf
- TigerVNC automatic protocol selection and pointer event pacing:
  https://tigervnc.org/doc/vncviewer.html

**Decision**: while a local viewport gesture is active, keep strict
framebuffer publish/upload deferral from D41 and also lower the app-side
RFB request/decode cadence floor from the previous 15 Hz-class interaction
floor to an 8 Hz-class content floor, with idle polls no faster than 200 ms.
Mirror these values in `VNCLiveBenchmark` through shared Core defaults so
future stream-shape probes continue to match production.

**Why**:
- D41 means incoming VNC frames are not published to SwiftUI or uploaded to
  Metal until the gesture settles. Sampling remote content at 15 Hz during the
  gesture therefore spends network/decode/allocator work mostly to replace the
  single deferred "latest" frame. On a physical iPhone this can still compete
  with touch tracking and contribute to heat.
- RFB is request-driven: a `FramebufferUpdate` is sent in response to a
  `FramebufferUpdateRequest`, and the client can regulate how often it asks
  for more. TigerVNC's documented auto-selection does the same kind of
  link/device trade-off by choosing encodings and pixel formats from measured
  speed rather than assuming one global optimum.
- Redacted local Screen Sharing benchmarks on 2026-06-05 showed actual ZRLE
  stream-shape updates with small dirty areas and partial renderer uploads,
  but ContinuousUpdates overlay failed on this server. The same run family also
  showed occasional full-dirty / full-upload tails when interaction pacing was
  off. This supports keeping the universal request/response path and giving
  local gestures a stricter stream-pressure budget instead of trying to push
  more mid-gesture remote frames.

**Privacy rule**: no new raw data is exported. Benchmark and diagnostics may
continue to report only aggregate frame/update counts, coarse latency
summaries, renderer-upload strategy counts, fixed pacing constants, and
permille ratios. Host identity, password, framebuffer dimensions, coordinates,
pixels, cursor pixels, byte counts, exact per-frame timings, and Compose draft
text remain out of artifacts.

## D43 — Pause new RFB requests during local viewport gestures and keep Compose draft live

References:
- RFB 3.8 framebuffer update flow:
  https://vnc.alice.ws/novnc/docs/rfbproto-3.8.pdf

**Decision**: supersede the D42 "8 Hz-class mid-gesture request cadence" as the
default iPhone behavior. While a local viewport gesture is active and an
existing framebuffer is visible, pause new `FramebufferUpdateRequest` work
entirely and poll only the local gesture-active flag. If a request was already
in flight when the gesture began, keep D41's strict deferred publish/upload and
flush the latest frame once the gesture settles.

For Compose, keep the UIKit rule that SwiftUI must not write binding text back
into a `UITextView` while marked text is active, but allow local marked-text
changes to propagate to the app model draft. This keeps the field, send button,
diagnostic input summary, and model state aligned without injecting text into
the remote session until the user taps Send.

**Why**:
- Fresh physical iPhone feedback after D42 still reports stepped, unnatural
  zoom/pan. Because RFB is client-request-driven, the cleanest way to protect
  the touch loop is to stop asking the server for new framebuffer work while
  the user is manipulating the already-visible texture.
- The app already presents local viewport navigation from the current Metal
  texture and coalesces the latest remote frame for gesture-end presentation.
  Continuing decode/request work during the gesture primarily consumes CPU,
  memory bandwidth, and socket work for pixels that will not be shown
  immediately.
- Compose feedback indicates that protecting UIKit marked text is not enough if
  the app model draft remains stale. One-way local propagation keeps state
  current while the existing stale-binding guard still prevents SwiftUI from
  clobbering IME composition.

**Privacy rule**: no new raw data is exported. The request pause exports no
gesture coordinates, timestamps, dimensions, pixels, cursor pixels, byte counts,
host identity, device identity, power state, or Compose draft text.

## D44 — Benchmark request-pause windows, not obsolete viewport pacing floors

References:
- RFC 6143 framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer encoding/compression controls:
  https://manpages.debian.org/bookworm/tigervnc-viewer/vncviewer.1.en.html
- noVNC viewport and quality controls:
  https://novnc.com/noVNC/docs/API.html

**Decision**: bump `VNCLiveBenchmark` to schema v26 and change
`--stream-shape-viewport-interaction app` from post-frame pacing-floor parity
to request-pause parity. After the first visible frame, the benchmark inserts a
configurable synthetic local-gesture pause window before incremental stream-shape
requests, sleeping in the same fixed poll interval the app uses while waiting
for viewport interaction to settle. Keep the old viewport-interaction content
and idle floor constants in the report as in-flight fallback constants only;
do not treat them as the normal app path.

**Why**:
- The production app now uses RFB's client-demanded update flow directly: if a
  local viewport gesture is active and a framebuffer is already visible, the app
  stops issuing new `FramebufferUpdateRequest` messages and polls only local
  gesture state. A benchmark mode that merely adds an 8 Hz post-frame delay
  therefore measures a policy the app no longer uses.
- RFC 6143 explicitly describes framebuffer updates as sent in response to
  explicit client requests and notes this gives the protocol an adaptive update
  rate. The benchmark should model that control point when evaluating iPhone
  heat/FPS trade-offs.
- TigerVNC and noVNC expose separate levers for encoding/compression/quality and
  local viewport handling. Keeping request-pause as its own benchmark dimension
  lets future live runs compare encoding or transport choices without confusing
  them with touch-loop protection.

**Privacy rule**: request-pause benchmark output may include only fixed mode
labels, configured synthetic pause duration, fixed poll interval, aggregate
paused request count/permille, aggregate poll count, and aggregate paused
milliseconds. It must not emit host identity, password, framebuffer dimensions,
coordinates, pixels, cursor pixels, byte counts, raw per-request timestamps, raw
per-frame timings, device identity, power state, or Compose draft text.

## D45 — Export viewport request-pause diagnostics as buckets on-device

References:
- RFC 6143 framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: bump diagnostic export to schema v21 and record app-side
viewport request-pause activity as safe aggregate diagnostics:
`viewportInteractionRequestPauseCount`,
`viewportInteractionRequestPausePollCount`,
`averageViewportInteractionRequestPauseBucket`, and
`maxViewportInteractionRequestPauseBucket`. Count each visible-frame pause
window in `waitForViewportInteractionToSettle`; count local poll iterations;
export duration only through the existing fixed timing bucket catalog.

**Why**:
- T371 changed the production behavior from slower mid-gesture stream pacing to
  suppressing new `FramebufferUpdateRequest` messages while the user is locally
  manipulating an already-visible framebuffer. Physical iPhone reports need to
  prove that this protection actually activated; `viewportInteractionPacing`
  staying zero is now expected and insufficient.
- RFC 6143's demand-driven update model makes request suppression a first-class
  client performance lever. The diagnostic should therefore distinguish
  intentional request-pause windows from local gesture long frames and incoming
  framebuffer publish deferrals.
- On-device diagnostics are more privacy-sensitive than local benchmark output,
  so exact paused milliseconds are reduced to the same coarse timing buckets
  already used for receive, app-apply, renderer-upload, and pacing-delay
  diagnostics.

**Privacy rule**: diagnostic export may include only aggregate pause counts,
aggregate poll counts, and fixed timing buckets. It must not emit raw pause
timestamps, raw per-pause milliseconds, host identity, password, framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, device identity,
power state, or Compose draft text.

## D46 — Keep IME marked text local and lower trackpad mirror pressure

References:
- Apple `UITextInput.markedTextRange`:
  https://developer.apple.com/documentation/uikit/uitextinput/markedtextrange
- Apple `UITextInput.unmarkText()`:
  https://developer.apple.com/documentation/uikit/uitextinput/unmarktext%28%29

**Decision**: supersede the Compose half of D43. While UIKit reports active
`markedTextRange`, keep the evolving Korean/CJK composition inside the
`UITextView`/commit controller and do not adopt it into the SwiftUI binding or
propagate it to the app model draft. On marked-text commit or Send,
`unmarkText()`/stabilized reads produce the committed text, and only that value
updates SwiftUI/model state. Separately, keep Metal-host trackpad cursor and
zoomed auto-pan immediate, but lower remote trackpad pointer-write coalescing to
a 60 Hz-class cadence and publish SwiftUI cursor mirror snapshots at a lower
cadence because the Metal host already paints the hot cursor locally.

**Why**:
- Apple defines marked text as provisional multistage input that still requires
  user confirmation. Treating that provisional text as a model-synchronized
  draft causes avoidable SwiftUI updates and model echo while the keyboard is
  still composing.
- Physical iPhone feedback after T371 still reports unreliable Compose. The
  safest local-composition boundary is therefore: UIKit owns marked text;
  Naru owns committed text and explicit Send.
- Physical iPhone feedback also reports stepped zoom/pan. The local visual path
  is already immediate in `MetalFramebufferHostingView`, so remote pointer
  writes and SwiftUI cursor mirror state should not race every touch sample.

**Privacy rule**: this change exports no new user content or coordinates.
Marked text, committed text, cursor positions, touch deltas, host identity,
framebuffer dimensions, pixels, byte counts, and exact timings remain out of
diagnostics and benchmark artifacts.

## D47 — Interpret viewport request-pause activation in diagnostic logs

References:
- RFC 6143 framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: bump diagnostic export to schema v22 and add a fixed-catalog
`viewportRequestPauseHint` derived from safe aggregate viewport signals:
viewport interaction count, viewport request-pause count, gesture long-frame
permille, and incoming-frame deferral permille. The catalog distinguishes
`notMeasured`, `notObservedDuringInteraction`, `activeNoViewportPressure`,
`activeGestureLoopPressure`, `activeIncomingFrameDeferral`, and
`activeMixedViewportPressure`.

**Why**:
- Physical iPhone feedback still reports stepped zoom/pan after touch-first
  request suppression. The raw v21 counters show whether pause windows happened,
  but they require manual cross-reading with `viewportStutterHint`.
- RFB's request/response update model makes missing request suppression a
  different failure mode from successful suppression that still leaves local
  gesture-loop pressure. The support log should make that distinction directly
  so the next fix can target either the local UIKit/Metal path or the incoming
  frame/request path.
- Keeping the hint as a fixed catalog preserves the diagnostic collection
  contract while making reports useful enough to debug without raw per-frame
  timestamps.

**Privacy rule**: diagnostic export may include only the derived catalog value
and the already-safe aggregate counts/permille inputs. It must not emit raw
gesture timestamps, raw pause timestamps, raw per-pause milliseconds, host
identity, password, framebuffer dimensions, coordinates, pixels, cursor pixels,
byte counts, device identity, power state, or Compose draft text.

## D48 — Restore touch-first viewport pacing and unconfirmed UTF-8 fallback

References:
- Apple `MTKView.enableSetNeedsDisplay` on-demand drawing:
  https://developer.apple.com/documentation/metalkit/mtkview/enablesetneedsdisplay
- Apple `CADisplayLink.preferredFrameRateRange`:
  https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- Apple ProMotion frame pacing guidance:
  https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
- RFC 6143 RFB framebuffer update and cut-text flow:
  https://datatracker.ietf.org/doc/rfc6143/

**Decision**: after physical iPhone feedback still reports choppy zoom/pan and
broken Compose, restore the active viewport-interaction content cadence to an
8 Hz-class floor in the shared app/benchmark defaults and allow UTF-8 Compose
payloads to attempt best-effort legacy VNC paste when clipboard UTF-8 support
is unknown. Helper routing remains preferred when configured/reachable, and
servers that explicitly report unsupported UTF-8 clipboard support still fail
with helper-aware diagnostics instead of sending text that is known unreliable.

**Why**:
- Naru's visible pinch/pan path is a local `UIView.transform` on top of a
  paused, event-driven `MTKView`. Apple documents this `MTKView` mode as
  responding to `setNeedsDisplay()` only when invalidated, which matches the
  goal: redraw for remote content changes, not for every touch sample.
- Apple's display-link guidance says apps should request rates they can
  consistently maintain and prepare for system throttling from thermal or power
  conditions. Real-device feedback and the live localhost benchmark still show
  tail-latency pressure, so mid-gesture remote decode/upload work should be
  rarer than the local compositor path.
- RFC 6143 makes framebuffer updates client-demanded and therefore gives the
  viewer a legitimate request/pacing control point. During local viewport
  manipulation, preserving touch tracking is more important than maximizing
  remote freshness.
- RFC 6143's base cut-text path is legacy text, while UTF-8 clipboard behavior
  depends on extensions. Unknown UTF-8 support therefore should not be reported
  as confirmed success, but a best-effort paste with `unknown` status is more
  useful on macOS-style VNC targets than refusing to try.

**Evidence**:
- `swift run VNCLiveBenchmark --ask-password --first-frame-profiles none
  --stream-shape-profiles local-low-latency --stream-shape-samples 0
  --stream-shape-duration-seconds 6 --stream-shape-client-pressure app
  --stream-shape-viewport-interaction app --json`
  - Result: passed against the redacted local target.
  - Schema v26 reported
    `streamShapeViewportInteractionContentFrameIntervalSeconds: 0.125`,
    `viewportInteractionPacingPermille: 1000`, request/response transport,
    ZRLE rectangles only, 11 received samples, 10 content updates, 1 empty
    update, 90% partial uploads, 10% full uploads, average update latency
    406 ms, p95 update latency 2519 ms, and one very-slow update.
- Focused tests plus full `swift test` passed after the correction.

**Privacy rule**: benchmark and diagnostics may report only fixed mode labels,
aggregate counts, aggregate permille values, and aggregate latency summaries.
They must not emit host identity, password, framebuffer dimensions, pixels,
cursor pixels, coordinates, raw text, byte counts, or raw per-frame samples.

## D49 — Prioritize local touch smoothness and require confirmed UTF-8 Compose

References:
- Apple `MTKView.enableSetNeedsDisplay` on-demand drawing:
  https://developer.apple.com/documentation/metalkit/mtkview/enablesetneedsdisplay
- Apple ProMotion frame pacing guidance:
  https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
- RFC 6143 RFB framebuffer update and cut-text flow:
  https://datatracker.ietf.org/doc/rfc6143/
- Host helper text bridge spec:
  `specs/006-host-helper-text-bridge/spec.md`

**Decision**: supersede the pacing and Compose-routing parts of D48. After
physical iPhone feedback still reports unnatural zoom/pan and Compose text not
actually arriving on the remote Mac, reduce active viewport-interaction content
request cadence to a conservative 4 Hz-class floor and lower zoomed trackpad
pan coupling so the local cursor remains finger-paced without over-dragging the
viewport. For Korean/CJK/emoji Compose, treat unconfirmed VNC UTF-8 clipboard
support the same as the helper spec requires: route through a reachable helper
when available; otherwise fail before writing clipboard bytes or sending paste.
Confirmed Extended Clipboard UTF-8 remains valid, and ASCII / Latin-1 legacy
Compose remains allowed with `unknown` remote confirmation status.

**Why**:
- During pinch, zoomed pan, and zoomed trackpad auto-pan, Naru's visible
  movement is a local Core Animation transform on a paused, on-demand `MTKView`.
  Mid-gesture RFB decode/upload can only refresh remote content; it does not
  improve finger-following. Lowering this work from 8 Hz to 4 Hz gives touch
  tracking and the compositor more room on hot physical iPhones while still
  preserving stream liveness and a newest-frame flush at gesture end.
- Trackpad mode needs the viewport to follow the real cursor while zoomed, but
  coupling too much pan into every central cursor move makes the remote desktop
  feel like it is swimming under the finger. A lower coupling keeps central
  cursor movement calmer and leaves reveal-zone auto-pan to do more of the
  edge-follow work.
- RFC 6143's base cut-text path is not proof of UTF-8 clipboard support. The
  helper feature explicitly exists because Apple Screen Sharing-style targets
  may ignore or mishandle legacy VNC clipboard updates. Reporting best-effort
  legacy UTF-8 paste as merely `unknown` is not honest enough when the user
  observes no remote text.

**Evidence**:
- `swift run VNCLiveBenchmark --ask-password --first-frame-profiles none
  --stream-shape-profiles local-low-latency --stream-shape-samples 0
  --stream-shape-duration-seconds 6 --stream-shape-client-pressure app
  --stream-shape-viewport-interaction app --json`
  - Result: passed against the redacted local target.
  - Schema v26 reported
    `streamShapeViewportInteractionContentFrameIntervalSeconds: 0.25`,
    `viewportInteractionPacingPermille: 1000`, request/response transport,
    7 received samples over 6 seconds, 4 content updates, 3 empty updates,
    75% partial uploads, 25% full uploads, average update latency 647 ms, p95
    update latency 2707 ms, and one very-slow update.
- Focused tests passed for pointer resolver behavior, model-level trackpad
  dispatch, viewport redraw pacing, text-injection policy, and no-helper
  unconfirmed UTF-8 Compose failure.

**Privacy rule**: benchmark, diagnostics, and tests may report only fixed mode
labels, aggregate counts, aggregate permille values, and aggregate latency
summaries. They must not emit host identity, password, framebuffer dimensions,
pixels, cursor pixels, coordinates, raw Compose text, byte counts, or raw
per-frame samples.

## D50 — Keep zoomed trackpad edge-follow from reversing visible cursor travel

References:
- Apple app responsiveness guidance:
  https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- Apple `MTKView.enableSetNeedsDisplay` on-demand drawing:
  https://developer.apple.com/documentation/metalkit/mtkview/enablesetneedsdisplay
- RFC 6143 framebuffer update request pacing:
  https://datatracker.ietf.org/doc/rfc6143/

**Decision**: add a trace-level smoothness invariant for zoomed trackpad
edge-follow. The viewport may pan with the cursor while zoomed, but the
auto-pan reveal step for a tiny high-refresh touch sample must not exceed the
sample enough to make the visible cursor travel opposite the user's finger.
Cap the reveal-only follow step to a fraction of the touch sample while keeping
a generous cap for large deliberate drags.

**Why**:
- Physical iPhone feedback still describes zoom/pan as stepped and unnatural.
  The prior single-sample tests allowed a near-edge 4 pt rightward trackpad
  sample to produce a much larger leftward reveal pan. That keeps the cursor
  technically visible, but the cursor appears to move backward on screen,
  which reads as a hitch or snap.
- Apple's responsiveness guidance treats jerky foreground drawing as a frame
  deadline problem. In Naru's hot path the local compositor transform is the
  right place for finger-following; extra RFB freshness cannot repair a local
  transform that reverses direction within a touch sample.
- RFC 6143 gives the viewer control over incremental update request pacing, so
  local navigation smoothness should remain the first priority during viewport
  interaction. Remote updates can stay bounded and aggregate-only in
  diagnostics.

**Evidence**:
- A new `PointerGestureResolverTests` trace reproduces the old issue: before
  the fix, a 4 pt rightward sample near the reveal margin moved the visible
  cursor about 9.6 pt backward on screen.
- The fixed trace asserts 24 consecutive tiny near-edge samples keep visible
  cursor travel positive and no greater than the finger sample plus tolerance.
- Focused `PointerGestureResolverTests` and `TrackpadModeModelTests` pass after
  the correction.

**Privacy rule**: gesture smoothness tests and artifacts may report only fixed
mode labels and aggregate/synthetic trace deltas. They must not emit remote
host identity, pixels, cursor pixels, real coordinates, raw text, byte counts,
or raw per-frame samples from a live session.

## D51 — Export Compose route readiness before Send

**Decision**: bump diagnostic collection schema to v23 and include pre-send
Compose route fields under the safe input report: draft payload encoding,
planned injection path, active UTF-8 clipboard support, and a fixed route
blocker. The fields are derived from local model state and helper availability,
not from raw Compose text or remote pixels.

**Why**:
- Physical iPhone feedback still reports "Compose input does not work", but a
  post-failure message alone is too late to separate local IME capture,
  confirmed UTF-8 clipboard, helper-ready, helper-not-configured, and
  no-active-session cases.
- Apple Screen Sharing-style targets may not confirm UTF-8 clipboard support.
  Without a reachable helper, Korean/CJK/emoji drafts must fail honestly before
  writing legacy clipboard bytes; the diagnostic export needs to show that
  decision path in a fixed catalog.
- The same fields make helper setup problems debuggable from a screenshot or
  exported log while preserving the constitution privacy boundary.

**Evidence**:
- `DiagnosticExportTests` now assert schema v23 preserves only safe enum values
  for `composeDraftPayloadEncoding`, `composePlannedPath`,
  `composeUTF8ClipboardSupport`, and `composeRouteBlocker`, and clamps arbitrary
  strings to nil.
- Focused `NaruRemoteAppModelTests` prove a Korean/CJK/emoji draft on an
  unconfirmed UTF-8 session without helper exports `helperNotConfigured`, while
  a reachable helper preflight exports planned path `helperTextBridge`.

**Privacy rule**: route diagnostics may report only fixed enum labels and
booleans. They must not emit raw draft text, host identity, helper endpoint,
pairing fingerprint, clipboard bytes, key events, coordinates, pixels, timing
samples, or byte counts.

## D52 — Split single-spike pressure cooldown from sustained pressure recovery

References:
- RFC 6143 framebuffer update requests and Cursor pseudo-encoding:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer protocol/encoding auto-selection and cursor/compression
  options: https://tigervnc.org/doc/vncviewer.html

**Decision**: keep `local-low-latency` as the default encoding profile for now,
but split adaptive client-pressure recovery into two windows. A single
1000 ms-class local-work spike enters an 8 update-decision cooldown, while
repeated severe/moderate lag or sustained full renderer uploads keep the
existing 120 update-decision recovery. Mirror the split in `VNCLiveBenchmark`
schema v29 and add ZRLE compression-0 cursor/clipboard isolation profiles.

**Why**:
- Post-ZRLE changed-bounds benchmarks showed full renderer upload pressure at
  0 permille, so long low-FPS periods were no longer explained by GPU upload
  pressure.
- 20 second pseudo-encoding isolation runs showed the first measured stream
  profile could receive a 2 second-class cold/profile-warm-up spike regardless
  of whether Cursor or ExtendedClipboard was requested. Dropping those
  pseudo-encodings would lose real-cursor/Compose capability without a stable
  performance win.
- One cold spike should briefly cool the request loop, but it should not borrow
  the same long recovery window reserved for repeated lag or full-upload
  pressure. On a target producing about two content updates per second, 120
  update decisions can keep adaptive pressure active for most of a sustained
  run.

**Evidence**:
- v28 order-isolation baseline with `zrle-compression-0-cursor-clipboard`
  first: adaptive pressure 972 permille, one very-slow sample, full-upload
  pressure 0.
- v29 default `local-low-latency` single-profile run: adaptive pressure 395
  permille, one very-slow sample, full-upload pressure 0.
- v29 cursor-only run did not beat the default: adaptive pressure 711 permille.
- Focused app and benchmark pacing tests assert single very-slow cooldown
  recovers faster than the sustained pressure window while repeated lag still
  uses the long recovery.

**Privacy rule**: benchmark artifacts may include only fixed labels,
aggregate counts, permille ratios, and latency summaries. They must not emit
host identity, credentials, framebuffer dimensions, coordinates, pixels, cursor
pixels, byte counts, raw samples, or raw error text.

## D53 — Report tail position without raw samples

**Decision**: extend `BenchmarkStreamShapeTailSummary` with optional ordinal
aggregates for the first slow and first very-slow update, plus their
content-update ordinals. Bump `VNCLiveBenchmark` to schema v30 and print the
first slow and first very-slow ordinals in the human report.

**Why**:
- After T382, the remaining practical-baseline failure is not renderer upload
  pressure or a clearly bad encoding profile. The next question is whether the
  1000 ms-class tail is a cold first-content-frame event, a late recurring
  decode/apply stall, or profile-order variance.
- Raw per-frame samples remain intentionally absent from benchmark JSON. A
  one-based ordinal aggregate gives enough diagnostic shape for PR-level
  decisions without exporting timestamps, frame dimensions, coordinates, pixels,
  byte counts, or raw payloads.

**Evidence**:
- Existing v29 runs can show one very-slow sample, but cannot say where it
  occurred without inspecting non-exported local scratch data.
- The new unit test covers mixed content/empty updates and proves the ordinal
  counts are based on safe received-update and content-update sequence numbers.

**Privacy rule**: tail-position telemetry may report only one-based ordinals
and aggregate counts. It must not include per-frame arrays, raw timestamps,
dimensions, coordinates, pixels, cursor pixels, byte counts, host identity,
credentials, or raw error text.

## D54 — Split ZRLE inflate from tile/apply before optimizing the next bottleneck

References:
- RFC 6143 ZRLE definition and single zlib stream requirement:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer preferred encoding / quality / compression options:
  https://tigervnc.org/doc/vncviewer.html

**Decision**: add safe aggregate ZRLE phase timing to the benchmark path before
spending another large unit on decoder micro-optimization. `RFBFramebufferDecoder`
now records coarse per-update ZRLE inflate time separately from ZRLE tile
parse/framebuffer-apply time, and `VNCLiveBenchmark` schema v31 aggregates those
fields as `zrleInflateLatency` and `zrleTileApplyLatency`.

**Why**:
- RFC 6143 defines ZRLE as a 4-byte compressed length followed by zlib data,
  decoded through one session-lifetime zlib stream, then interpreted as 64x64
  tiles. That makes inflate and tile/apply the two useful local decode phases
  to separate.
- TigerVNC exposes preferred encoding and compression/quality knobs, so a
  practical viewer must be able to tell whether changing encoding profile or
  compression level is actually helping local work rather than moving pressure
  to server/network wait.
- Prior v30 telemetry showed where slow/very-slow updates occur but still
  grouped inflate, tile parsing, framebuffer mutation, and result construction
  into one client-processing number. That was not enough to choose the next
  large work unit.

**Evidence**:
- Focused decoder/frame-pump tests pass with decode metrics preserved through
  legacy JSON, `withTiming`, and frame-pump metadata.
- Focused benchmark summary tests pass with ZRLE phase latency aggregation and
  legacy JSON omission handling.
- v31 localhost Screen Sharing 20 second `local-low-latency` run:
  practical verdict `warning`, issue `content-fps-warning`, 142 received
  updates, 123 content updates, content FPS 6.15, update p50/p95/max
  28/488/552 ms, network read p50/p95/max 21/487/549 ms, client processing
  p50/p95/max 3/12/28 ms, 142 ZRLE rectangles, ZRLE inflate avg/p50/p95/max
  0/0/0/23 ms, ZRLE tile/apply avg/p50/p95/max 3/3/11/18 ms, renderer
  full-upload pressure 0 permille, adaptive client-pressure pacing 0 permille,
  and no 1000 ms-class very-slow updates.

**Interpretation**:
- The first v31 run did not reproduce the earlier 2 second-class first-content
  tail. In this baseline, local ZRLE decode is not the p95 bottleneck: client
  processing and ZRLE tile/apply stay in the low-millisecond range while p95
  update latency tracks receive/network wait.
- The next larger unit should therefore compare request/response against
  ContinuousUpdates/Fence and encoding profiles over longer sustained runs,
  then repeat the same v31 shape on a physical iPhone to capture thermal/FPS
  behavior.

**Privacy rule**: ZRLE phase timing may report only aggregate millisecond
summaries attached to fixed encoding labels. It must not include host identity,
credentials, framebuffer dimensions, rectangle coordinates, tile coordinates,
pixels, cursor pixels, compressed or decompressed byte counts, raw samples, raw
payloads, or raw error text.

## D55 — Use a named core matrix as the larger practical optimization unit

References:
- RFC 6143 client-to-server update and encoding negotiation flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer preferred encoding / compression / quality options:
  https://tigervnc.org/doc/vncviewer.html

**Decision**: add `--stream-shape-profiles core-matrix` to `VNCLiveBenchmark`.
The named set expands to `local-low-latency`, `zrle-compression-0`,
`tight-first`, and `adaptive-good-full`, preserving that order. Use it with
`--stream-shape-transport both` as the first benchmark for larger practical
optimization PRs before falling back to exhaustive `all` sweeps or targeted
long runs.

**Why**:
- The user asked to move from narrow fix PRs to larger goal-oriented units. The
  benchmark needs a stable middle size between single-profile smoke tests and
  slow all-profile transport sweeps.
- RFC 6143 keeps encoding negotiation and update cadence under explicit client
  control, while common VNC viewers expose encoding/compression/quality knobs.
  Naru should therefore compare a fixed candidate matrix before changing a
  production default.
- The v31 ZRLE phase baseline showed local ZRLE work was not the p95 bottleneck
  on the first successful run, so the next unit should compare transport,
  profile, and server compatibility together.

**Evidence**:
- `core-matrix` selection tests pass, including usage text, fixed order, and a
  guard that fails if a candidate label is removed or renamed.
- v31 localhost Screen Sharing 8 second `core-matrix` run:
  `local-low-latency`, `zrle-compression-0`, and `tight-first` completed under
  request/response; all three failed the practical baseline only on
  `content-fps-failed`. Client-processing p95 stayed 9 to 15 ms, renderer
  full-upload pressure stayed 0 permille, and network-read p95 stayed 365 to
  403 ms. `local-low-latency` was recommended by lowest average update latency
  among successful request/response profiles. Every ContinuousUpdates matrix
  probe failed with the safe `stream-continuous-updates-connection-failed`
  label, and the standalone ContinuousUpdates probe failed with
  `continuous-probe-receive-connection-failed`.

**Interpretation**:
- Keep `local-low-latency` as the production default for now.
- Treat ContinuousUpdates as a compatibility investigation, not a production
  candidate, on this macOS Screen Sharing target.
- The next larger unit should add a controlled dynamic-content stimulus to the
  live benchmark so content FPS is measured against repeatable screen activity,
  then repeat `core-matrix` on a physical iPhone for thermal and hand-feel
  evidence.

**Privacy rule**: core-matrix artifacts may report only fixed profile labels,
fixed transport labels, aggregate timing summaries, aggregate FPS, aggregate
renderer/upload counts, practical verdict codes, and safe failure labels. They
must not include host identity, credentials, framebuffer dimensions, rectangle
coordinates, pixels, cursor pixels, byte counts, raw samples, raw payloads, or
raw error text.

## D56 — Stimulate live content before changing streaming defaults

References:
- RFC 6143 client-driven framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html

**Decision**: add a controlled dynamic-content stimulus path to live
stream-shape benchmarks before changing request cadence, transport, or encoding
defaults again. `VNCLiveBenchmark` schema v32 adds
`--stream-shape-stimulus off|external-command`,
`streamShapeStimulusMode`, and `streamShapeStimulusWarmupSeconds`.
`VNCLiveStimulusWindow` provides a repo-native macOS animated-window helper for
local Screen Sharing runs.

**Why**:
- PR #223's `core-matrix` baseline showed useful profile/transport shape, but
  live content FPS still depended on incidental desktop motion. That is too
  weak for larger default-changing PRs.
- RFB update flow is client-driven unless extensions alter it, so benchmark
  runs must separate "we did not ask fast enough" from "the screen did not
  change enough".
- External stimulus must not widen the diagnostic privacy boundary. The
  benchmark therefore records only fixed stimulus mode/warmup labels, starts
  the child from a minimal launch environment, adds only fixed
  duration/profile/transport hints, and never emits the command text or output.

**Evidence**:
- Focused stimulus/failure-label tests pass.
- `VNCLiveBenchmark` and `VNCLiveStimulusWindow` products build.
- Help output exposes the stimulus flags and environment contract.
- v32 local Screen Sharing `core-matrix` request/response run with external
  animated-window stimulus:
  - `local-low-latency`: content FPS 1.33, update p50/p95 133/2497 ms, network
    p95 438 ms, client p95 2213 ms, ZRLE tile/apply p95 2155 ms, full-upload
    pressure 0 permille, one very-slow update.
  - `zrle-compression-0`: content FPS 1.83, update p50/p95 196/374 ms,
    network p95 371 ms, client p95 7 ms, ZRLE tile/apply p95 6 ms,
    full-upload pressure 0 permille.
  - `tight-first`: content FPS 1.83, actual Raw, update p50/p95 204/407 ms,
    client p95 7 ms, full-upload pressure 0 permille.
  - `adaptive-good-full`: content FPS 1.83, actual ZRLE, update p50/p95
    187/404 ms, network p95 363 ms, client p95 153 ms, ZRLE tile/apply p95
    151 ms, full-upload pressure 0 permille.

**Interpretation**:
- The stimulus path makes content updates repeatable enough to reveal profile
  differences. Under animated content, `local-low-latency` can still hit a
  very-slow local ZRLE tile/apply frame, while pure ZRLE compression 0 stayed
  low on client-processing p95 in the same matrix.
- Keep the production default unchanged until the next stimulated isolation run
  compares `local-low-latency`, `zrle-compression-0`,
  `zrle-compression-0-cursor`, and `zrle-compression-0-clipboard`.

**Privacy rule**: stimulus artifacts may report only fixed stimulus/profile/
transport labels, aggregate timing summaries, aggregate FPS, aggregate
renderer/upload counts, practical verdict codes, and safe failure labels. They
must not include host identity, credentials, framebuffer dimensions, rectangle
coordinates, pixels, cursor pixels, byte counts, raw samples, raw payloads,
external command text, command output, or raw error text.

## D57 — Isolate ZRLE extension profiles under dynamic stimulus before default changes

References:
- RFC 6143 client-driven framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html

**Decision**: add `--stream-shape-profiles zrle-isolation` as a named live
benchmark matrix for the current default, pure ZRLE compression 0, and
cursor/ExtendedClipboard extension combinations. Keep the production default
unchanged after the first stimulated isolation run.

**Why**:
- D56 showed repeatable dynamic-content measurement, but the `core-matrix`
  result could not tell whether the ZRLE tail was caused by compression,
  server-cursor, ExtendedClipboard, or first-profile ordering.
- A named selection makes this investigation reproducible without asking every
  future optimization PR to spell out five comma-separated labels.

**Evidence**:
- `BenchmarkStreamShapeProfileSelectionTests` pass with `zrle-isolation` usage,
  fixed ordering, and missing-label safety coverage.
- Help output exposes `zrle-isolation` in both the synopsis and option text.
- v32 local Screen Sharing request/response run with external animated-window
  stimulus:
  - `local-low-latency`: content FPS 1.33, update p50/p95 165/2667 ms, network
    p95 466 ms, client p95 2200 ms, ZRLE tile/apply p95 2132 ms, full-upload
    pressure 0 permille, one very-slow update.
  - `zrle-compression-0`: content FPS 2.00, update p50/p95 153/373 ms,
    network p95 370 ms, client p95 3 ms, ZRLE tile/apply p95 3 ms,
    full-upload pressure 0 permille.
  - `zrle-compression-0-cursor`: content FPS 2.00, update p50/p95 189/395 ms,
    network p95 393 ms, client p95 161 ms, ZRLE tile/apply p95 158 ms,
    full-upload pressure 0 permille.
  - `zrle-compression-0-clipboard`: content FPS 2.00, update p50/p95
    149/368 ms, network p95 368 ms, client p95 2 ms, ZRLE tile/apply p95
    1 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-cursor-clipboard`: content FPS 2.00, update p50/p95
    158/443 ms, network p95 431 ms, client p95 12 ms, ZRLE tile/apply p95
    12 ms, full-upload pressure 0 permille.

**Interpretation**:
- `local-low-latency` and `zrle-compression-0-cursor-clipboard` request the
  same request/response ZRLE compression-0, server-cursor, and
  ExtendedClipboard preference. The 2 second-class tail appearing only on the
  first profile is therefore an order/cold-start confound, not enough evidence
  to change the production default.
- The next larger unit should make candidate scoring order-neutral with
  repeated iterations, profile rotation, or an explicit warm-up profile before
  scoring.

**Privacy rule**: ZRLE isolation artifacts may report only fixed
stimulus/profile/transport labels, aggregate timing summaries, aggregate FPS,
aggregate renderer/upload counts, practical verdict codes, and safe failure
labels. They must not include host identity, credentials, framebuffer
dimensions, rectangle coordinates, pixels, cursor pixels, byte counts, raw
samples, raw payloads, external command text, command output, or raw error
text.

## D58 — Rotate live profile order before scoring encoding defaults

References:
- RFC 6143 client-driven framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html

**Decision**: add schema v33 order-neutral stream-shape scoring before changing
the production encoding default. `VNCLiveBenchmark` now supports
`--stream-shape-profile-iterations N` and
`--stream-shape-profile-order fixed|rotate`, records fixed per-probe
iteration/order ordinals, and emits per-profile aggregates plus
`streamShapeOrderNeutralRecommendation`.

**Why**:
- D57 showed `local-low-latency` and
  `zrle-compression-0-cursor-clipboard` request the same request/response
  ZRLE compression-0, server-cursor, and ExtendedClipboard preference, but the
  first profile in the ordered run could still hit a 2 second-class tile/apply
  tail.
- A single ordered matrix is therefore too weak for default-changing decisions.
  It can report a startup/session warm-up artifact as if it were an encoding
  preference difference.

**Evidence**:
- Focused order-mode, profile-selection, and stream-shape summary tests pass.
- v33 local Screen Sharing request/response run with external animated-window
  stimulus, `zrle-isolation`, 5 iterations, and rotated order:
  - `local-low-latency`: 5/5 usable runs, average update 447 ms, max p95 update
    2452 ms, average content FPS 1.73, max client p95 2139 ms, max ZRLE
    tile/apply p95 2066 ms, full-upload pressure 0 permille, one very-slow
    update.
  - `zrle-compression-0`: 5/5 usable runs, average update 221 ms, max p95
    update 395 ms, average content FPS 1.80, max client p95 172 ms, max ZRLE
    tile/apply p95 159 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-cursor`: 5/5 usable runs, average update 234 ms, max
    p95 update 570 ms, average content FPS 1.93, max client p95 173 ms, max
    ZRLE tile/apply p95 168 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-clipboard`: 4/5 usable runs, average update 226 ms,
    max p95 update 443 ms, average content FPS 2.08, max client p95 15 ms, max
    ZRLE tile/apply p95 14 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-cursor-clipboard`: 5/5 usable runs, average update
    205 ms, max p95 update 375 ms, average content FPS 1.99, max client p95
    15 ms, max ZRLE tile/apply p95 11 ms, full-upload pressure 0 permille.

**Interpretation**:
- Order-neutral scoring selects `zrle-compression-0-cursor-clipboard`, which
  matches the production `local-low-latency` request/response preference. The
  next optimization target is therefore explicit warm-up/preflight behavior and
  server/network pacing, not a production default flip.
- Keep reporting the single-probe recommendation for compatibility, but use
  `streamShapeOrderNeutralRecommendation` for default-changing decisions.

**Privacy rule**: order-neutral artifacts may report only fixed
stimulus/profile/transport labels, fixed iteration/order ordinals, aggregate
timing summaries, aggregate FPS, aggregate renderer/upload counts, practical
verdict codes, and safe failure labels. They must not include host identity,
credentials, framebuffer dimensions, rectangle coordinates, pixels, cursor
pixels, byte counts, raw samples, raw payloads, external command text, command
output, or raw error text.

## D59 — Test hidden stream-shape preflight before app default changes

References:
- RFC 6143 client-driven framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html

**Decision**: add `VNCLiveBenchmark` schema v34 with
`--stream-shape-preflight-frames N`. The benchmark consumes the requested
number of hidden incremental frames after the stream-shape first frame and
before measured samples. Keep the production app default unchanged until a
physical iPhone run proves that hiding one incremental update improves hand
feel without making the just-connected screen feel stale.

**Why**:
- D58 showed that order-neutral scoring can identify cold-start tails, but it
  does not tell whether the tail can be absorbed before the user starts
  interacting.
- Hidden preflight is a bounded experiment: it warms the server/client stream
  state without logging hidden frame contents, dimensions, byte counts, raw
  timings, or payloads.

**Evidence**:
- `swift build --product VNCLiveBenchmark` passes.
- Focused stream-shape summary, profile-selection, and profile-order tests
  pass.
- v34 local Screen Sharing request/response run with external animated-window
  stimulus, `zrle-isolation`, 5 iterations, rotated order, and
  `--stream-shape-preflight-frames 1`:
  - `local-low-latency`: 5/5 usable runs, average update 200 ms, max p95
    update 506 ms, average content FPS 1.80, max client p95 172 ms, max ZRLE
    tile/apply p95 162 ms, full-upload pressure 0 permille, no very-slow
    updates.
  - `zrle-compression-0`: 5/5 usable runs, average update 243 ms, max p95
    update 502 ms, average content FPS 1.73, max client p95 171 ms, max ZRLE
    tile/apply p95 166 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-cursor`: 5/5 usable runs, average update 204 ms, max
    p95 update 419 ms, average content FPS 1.93, max client p95 15 ms, max
    ZRLE tile/apply p95 10 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-clipboard`: 5/5 usable runs, average update 203 ms,
    max p95 update 380 ms, average content FPS 1.73, max client p95 8 ms, max
    ZRLE tile/apply p95 7 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-cursor-clipboard`: 5/5 usable runs, average update
    217 ms, max p95 update 497 ms, average content FPS 1.66, max client p95
    14 ms, max ZRLE tile/apply p95 13 ms, full-upload pressure 0 permille.

**Interpretation**:
- One hidden preflight frame removed the previous `local-low-latency`
  very-slow cold tail: v33 had 447 ms average update, 2452 ms max p95 update,
  2139 ms max client-processing p95, and one very-slow update; v34 preflight
  had 200 ms average update, 506 ms max p95 update, 172 ms max
  client-processing p95, and zero very-slow updates.
- The order-neutral recommendation selects `local-low-latency`, reinforcing
  that production encoding defaults should not change yet.
- Preflight does not solve the practical-use target by itself. Content FPS is
  still below 2 fps under controlled stimulus, so the next large unit should
  combine physical iPhone thermal hand-feel testing with request/server cadence
  work.

**Privacy rule**: preflight artifacts may report only fixed
stimulus/profile/transport labels, fixed requested preflight counts, fixed
iteration/order ordinals, aggregate timing summaries, aggregate FPS, aggregate
renderer/upload counts, practical verdict codes, and safe failure labels. They
must not include host identity, credentials, framebuffer dimensions, rectangle
coordinates, pixels, cursor pixels, byte counts, raw samples, raw payloads,
external command text, command output, hidden preflight frame contents, hidden
preflight timings, or raw error text.

## D60 — Promote sustained usability to the default benchmark gate

References:
- RFC 6143 client-driven framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html
- Apple `ProcessInfo.thermalState`:
  https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property

**Decision**: add `VNCLiveBenchmark` schema v35 with
`--stream-shape-practical-target
iphone-practical-baseline-v1|iphone-sustained-usability-v2`, and make
`iphone-sustained-usability-v2` the default CLI practical target for new
streaming work. Keep `iphone-practical-baseline-v1` available for legacy
artifact comparison and direct summary construction.

**Target bands**:
- Pass controlled-stimulus content FPS: at least 8 fps; fail below 4 fps.
- Pass average update latency: at most 180 ms; fail above 250 ms.
- Pass post-warm-up p95 update latency: at most 350 ms; fail above 500 ms.
- Pass client-processing p95: at most 24 ms; fail above 50 ms.
- Pass renderer full-upload pressure: 0 permille; fail above 50 permille.
- Pass adaptive client-pressure pacing: at most 100 permille; fail above 500
  permille.
- Require at least 8 content samples for a confident content-FPS read.
- Treat any very-slow update sample as fail-class.
- Keep the physical iPhone gate: 10 minutes with immediate local zoom/pan,
  deterministic Compose route diagnostics, and no `.serious` or `.critical`
  thermal state.

**Why**:
- v34 preflight removed one startup tail but content FPS stayed around 2 fps,
  so the next optimization unit must judge sustained usability rather than only
  cold-start behavior.
- Mature VNC viewers expose encoding, quality, color, and pointer-rate controls;
  Naru should keep defaults automatic, but the automation needs a stricter
  phone-first benchmark gate before changing stream cadence, app preflight, or
  encoding defaults.

**Evidence**:
- `swift build --product VNCLiveBenchmark` passes.
- `swift build --product VNCLiveStimulusWindow` passes.
- `swift run VNCLiveBenchmark --help` shows
  `--stream-shape-practical-target`.
- `swift test --filter BenchmarkStreamShapeSummaryTests` passes, including v2
  target selection, average-update issue codes, and v2 JSON encoding.
- v35 local Screen Sharing request/response run with external animated-window
  stimulus, `zrle-isolation`, 5 rotated iterations,
  `--stream-shape-preflight-frames 1`, and
  `--stream-shape-practical-target iphone-sustained-usability-v2`:
  - `local-low-latency`: 5/5 usable runs, average update 335 ms, max p95
    update 2623 ms, average content FPS 1.50, max client p95 2319 ms, max ZRLE
    tile/apply p95 2247 ms, full-upload pressure 0 permille, one very-slow
    update.
  - `zrle-compression-0`: 5/5 usable runs, average update 214 ms, max p95
    update 484 ms, average content FPS 1.85, max client p95 185 ms, max ZRLE
    tile/apply p95 178 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-cursor`: 5/5 usable runs, average update 254 ms, max
    p95 update 524 ms, average content FPS 1.80, max client p95 16 ms, max
    ZRLE tile/apply p95 16 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-clipboard`: 5/5 usable runs, average update 250 ms,
    max p95 update 507 ms, average content FPS 1.85, max client p95 14 ms, max
    ZRLE tile/apply p95 13 ms, full-upload pressure 0 permille.
  - `zrle-compression-0-cursor-clipboard`: 5/5 usable runs, average update
    210 ms, max p95 update 379 ms, average content FPS 1.90, max client p95
    17 ms, max ZRLE tile/apply p95 16 ms, full-upload pressure 0 permille.

**Interpretation**:
- The v35 order-neutral recommendation selected
  `zrle-compression-0-cursor-clipboard`, but it still failed v2 on content FPS:
  1.90 fps is below the 4 fps fail threshold and far below the 8 fps pass band.
- The selected profile is warning-class on average update and p95 update, not
  fail-class: 210 ms average and 379 ms max p95.
- Renderer full-upload pressure remains solved at 0 permille.
- App-side preflight, server/request cadence, and physical iPhone thermal
  hand-feel should be evaluated against v2 before production defaults change.

**Privacy rule**: v2 target artifacts may report only fixed target names, fixed
verdicts, fixed issue codes, fixed stimulus/profile/transport labels, fixed
requested preflight counts, fixed iteration/order ordinals, aggregate timing
summaries, aggregate FPS, aggregate renderer/upload counts, and safe failure
labels. They must not include host identity, credentials, framebuffer
dimensions, rectangle coordinates, pixels, cursor pixels, byte counts, raw
samples, raw payloads, external command text, command output, hidden preflight
frame contents, hidden preflight timings, or raw error text.

## D61 — Stage app-side startup preflight behind an explicit gate

References:
- RFC 6143 client-driven framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html

**Decision**: add an injectable `SessionStreamStartupPreflightPolicy` to the
app model, default it to disabled, and cap it to one hidden incremental update
after the first visible frame has already been published. The app stream loop
may use this policy during controlled physical-device experiments, but
production defaults remain unchanged until T390's 10 minute iPhone
hand-feel/thermal gate and sustained v2 benchmark comparison pass.

**Why**:
- D59 showed that one hidden preflight frame can remove a cold-start tail in
  the benchmark harness, while D60 showed that sustained content FPS still
  fails the practical-use target. App-side preflight is therefore useful as a
  controlled startup variable, not as a standalone production fix.
- Publishing the first frame before preflight prevents the just-connected
  screen from feeling blank or stale while still allowing a bounded hidden
  incremental request to warm the stream.
- Keeping the policy injectable avoids a silent runtime default change and
  lets physical iPhone validation decide whether the gate should ever be
  enabled by default.

**Evidence**:
- `swift test --filter NaruRemoteAppModelTests/testStartupPreflight` passes.
- `swift test --filter
  NaruRemoteAppModelTests/testModelKeepsStreamingFramesAfterFirstFramebuffer`
  passes.
- Fake-stream tests prove that a hidden incremental request does not update
  `latestFramebuffer` or `sessionStreamStats`, and that a subsequent visible
  incremental frame still publishes normally.
- PR review feedback folded in a cancellation handler so disconnect or profile
  change cancels the hidden preflight task and frame pump instead of waiting
  only for the bounded request timeout.

**Interpretation**:
- This is an app-pipeline foundation PR, not a practical-usability pass claim.
  The baseline target remains `iphone-sustained-usability-v2`; the next larger
  unit should attack sustained content FPS, direct zoom/pan hand feel, and
  deterministic Compose routing under the same target.
- Before enabling app-side preflight by default, mirror the final runtime
  boundary into the active app-stream spec/plan as well as this benchmark
  feature note.

**Privacy rule**: app-side preflight artifacts may report only fixed policy
labels, fixed requested hidden-frame counts, safe test names, and pass/fail
verification status. They must not include host identity, credentials,
framebuffer dimensions, rectangle coordinates, pixels, cursor pixels, byte
counts, raw samples, raw payloads, hidden preflight frame contents, hidden
preflight timings, or raw error text.

## D62 — Treat viewport hand-feel and Compose reliability as one v2 gate

References:
- Apple Core Animation Programming Guide, implicit animations:
  https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/
- Apple Text Programming Guide for iOS, managing text views:
  https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/

**Decision**: before enabling app-side stream preflight by default, run a
larger interaction/input correction behind the sustained usability target:
increase zoomed trackpad cursor-follow coupling, keep visible viewport motion
on the UIKit/Core Animation hot path with SwiftUI/PiP state mirrored at gesture
boundaries, and extend marked-text Compose Send stabilization.

**Why**:
- User feedback says the blocking experience is not only stream FPS; zoom,
  pan, trackpad cursor-follow, and Compose must feel reliable as one session
  loop.
- The Metal host already transforms the `MTKView` layer immediately. Publishing
  SwiftUI viewport state during the same gesture adds avoidable main-thread
  layout work, while the host can still reconcile the final transform when the
  gesture settles.
- A stronger central trackpad follow-pan makes a zoomed desktop move with the
  real cursor, but the resolver compensates cursor sensitivity so the visible
  cursor still moves at the finger's pace.
- Korean/CJK marked text can commit after `unmarkText()` with a short delay, so
  Compose Send should spend a bounded extra stabilization window only when
  marked text was active.

**Evidence**:
- `PointerGestureResolverTests` cover central zoomed trackpad samples that pan
  smoothly while preserving finger-paced visible cursor travel.
- `TrackpadModeModelTests` cover the app-model zoomed trackpad return path.
- `RemoteInputDockSyncPolicyTests` cover the longer marked-text stabilization
  window.

**Interpretation**:
- This is still a pre-physical-gate correction. It reduces known local hot-path
  causes of stepped navigation and text loss, but T390 remains open until the
  10 minute physical iPhone hand-feel/thermal pass and sustained v2 benchmark
  comparison are recorded.
- Because marked-text Compose Send now waits through a longer bounded
  stabilization window, T390 should explicitly check perceived send latency
  during multilingual entry before this tuning is treated as production-good.

**Privacy rule**: interaction artifacts may report only fixed test names,
fixed tuning labels, safe pass/fail verification status, and target names. They
must not include host identity, credentials, framebuffer dimensions, rectangle
coordinates, pixels, cursor pixels, byte counts, raw samples, raw payloads,
raw text entered by a user, hidden preflight contents, or raw error text.

## D63 — Add safe Compose Send preparation diagnostics before T390

References:
- Apple Text Programming Guide for iOS, managing text views:
  https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/

**Decision**: bump diagnostic JSON to schema v24 and export three safe fields
for the latest Compose Send preparation step: fixed mode
(`fastSnapshot` or `markedTextStabilization`), bounded snapshot count, and a
coarse `DiagnosticTimingBucket` duration.

**Why**:
- T393 deliberately widened marked-text stabilization to avoid delayed Korean
  or CJK IME commit loss, but that can make Send feel slower. T390 needs enough
  diagnostic detail to distinguish a normal fast Compose Send from a
  marked-text stabilization Send without exporting draft text.
- The preparation step happens in the local input dock before app-model text
  injection begins, so `latestInjectionDurationBucket` alone cannot explain
  user-perceived delay before paste dispatch.
- Mode, count, and bucket are fixed catalog/aggregate signals. They explain the
  local input path while preserving the project's diagnostic privacy boundary.

**Evidence**:
- `RemoteInputDockSyncPolicyTests` cover fast vs marked-text preparation plans.
- `NaruRemoteAppModelTests` prove the diagnostic export includes preparation
  mode/count/bucket without exporting the Compose draft, and clears stale
  preparation diagnostics when the user edits the draft.
- `DiagnosticExportTests` cover schema v24, JSON rendering, decoding, and
  unsafe catalog value clamping.

**Interpretation**:
- During the physical iPhone T390 pass, a `markedTextStabilization` mode paired
  with a lagging/stalled bucket means the extra local IME settle window is a
  plausible contributor to perceived send delay. A `fastSnapshot` mode with a
  sub-frame/interactive bucket points the investigation back to paste transport
  or remote app behavior.

**Privacy rule**: Compose Send preparation diagnostics may report only fixed
mode labels, bounded snapshot count, and coarse timing bucket. They must not
include draft text, marked text, raw timings, raw IME state, host identity,
credentials, framebuffer dimensions, coordinates, pixels, cursor pixels, byte
counts, raw payloads, or raw errors.

## D64 — Add a top-level sustained session diagnostic assessment

References:
- Apple `ProcessInfo.thermalState`:
  https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property
- RFC 6143 framebuffer update request flow:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: bump diagnostic JSON to schema v25 and add
`sustainedSessionAssessment` at the collection level. The assessment reports
only the fixed target `iphone-sustained-usability-v2`, a fixed verdict
(`notMeasured`, `pass`, `warning`, or `fail`), and fixed issue codes derived
from active stream diagnostics, thermal state, viewport pressure hints, Compose
route readiness, and Compose Send preparation buckets.

**Why**:
- T390 needs a 10 minute physical iPhone thermal/hand-feel pass, but raw
  stream counters alone make the next debugging step too slow. A single
  top-level assessment lets a device log immediately say whether the session is
  content-FPS-bound, receive/decode/apply-bound, renderer-upload-bound,
  thermal-bound, viewport-pressure-bound, or input-route-bound.
- `VNCLiveBenchmark` v35 already has the formal v2 target. The app diagnostic
  path cannot export raw FPS or raw milliseconds, so it uses exact content FPS
  only in memory to choose fixed issue codes and exports only coarse buckets and
  catalog values.
- Combining stream and input at the collection level avoids treating Compose
  route failures as a stream-performance field while still keeping one JSON
  object sufficient for physical-device triage.

**Evidence**:
- `DiagnosticExportTests` cover schema v25, content FPS bucket export,
  sustained assessment classification, pass classification, and unsafe catalog
  sanitization.
- `NaruRemoteAppSnapshotTests` cover the safe content FPS bucket inside the
  stream performance report.
- `NaruRemoteAppModelTests` prove active-session JSON includes
  `sustainedSessionAssessment` with fixed issue codes while still omitting host,
  raw timing field names, and raw target details.

**Interpretation**:
- A `contentFrameRateFailed` issue means the session is still below the v2
  content-FPS floor and the next PR should attack server/request cadence,
  encoding profile, or stimulus/control assumptions.
- Receive/client/apply/renderer issue codes point to local pipeline pressure.
  Thermal and viewport issue codes indicate that reducing foreground work may
  be more important than raising stream cadence.
- `composeRouteBlocked` or `composeSendPreparationStalled` means the practical
  failure is input-path-bound even if the stream looks acceptable.

**Privacy rule**: sustained assessment diagnostics may report only fixed
target names, fixed verdict labels, fixed issue codes, and existing aggregate
bucket fields. They must not include host identity, credentials, framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, raw FPS, raw
timings, raw samples, raw payloads, draft text, marked text, IME state, or raw
errors.

## D65 — Gate app-side startup preflight through persisted viewer settings

References:
- RFC 6143 framebuffer update request flow:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: keep startup preflight disabled by default, but expose the
one-hidden-frame app preflight as a persisted `startupPreflightMode` viewer
setting and bump Diagnostic JSON to schema v26. The app stream loop uses the
setting when no test override is injected, consumes at most one hidden
post-first-frame incremental update, and records only safe startup preflight
mode, requested/consumed hidden-frame counts, and fixed outcome labels
(`notRequested`, `consumed`, `timedOut`, `cancelled`, `staleSession`, `failed`).

**Why**:
- T390 needs a physical iPhone comparison before changing production defaults,
  but an initializer-only gate is not enough for real-device hand-feel testing.
  A persisted viewer setting lets the same installed build compare disabled vs
  one-hidden-frame warm-up without rebuilding.
- D59/D61 showed hidden preflight can remove a cold startup tail but is not a
  complete sustained-FPS fix. Keeping the default disabled prevents a hidden
  warm-up from masking stale startup perception or thermal regressions before
  T390 evidence exists.
- Reporting fixed outcome labels makes physical logs actionable: a run can show
  whether warm-up was not requested, actually consumed, timed out, cancelled by
  navigation/session change, or failed without leaking raw errors or hidden
  frame data.

**Evidence**:
- `AppSettingsCodableTests` cover default `{}` encoding, persisted
  `startupPreflightMode`, and toggle/count semantics.
- `NaruRemoteAppModelTests` cover settings load/persist, settings-driven
  hidden preflight with no injected override, hidden-frame consumption after
  the first visible frame, continued visible streaming after preflight, and
  active-session diagnostic export.
- `DiagnosticExportTests` cover schema v26, safe top-level
  `viewerStartupPreflightMode`, stream preflight requested/consumed/outcome
  fields, legacy decode defaults, and unsafe catalog clamping.

**Interpretation**:
- If a physical T390 log shows `viewerStartupPreflightMode` =
  `one-hidden-frame` and `startupPreflightOutcome` = `consumed`, compare
  sustained assessment issue codes against a disabled run. If content FPS or
  receive/apply/renderer issues do not improve, the next large unit should
  attack request cadence, server stimulus, encoding mix, or renderer upload
  pressure instead of promoting preflight.
- `timedOut`, `cancelled`, `staleSession`, or `failed` means the experiment did
  not actually warm the stream. Do not use that run as evidence for changing
  production defaults.

**Privacy rule**: startup preflight diagnostics may report only fixed mode
labels, bounded hidden-frame counts, fixed outcome labels, safe test names, and
existing aggregate buckets. They must not include host identity, credentials,
framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts, raw
FPS, hidden frame timings, hidden frame contents, raw samples, raw payloads,
raw errors, draft text, marked text, IME state, or external command output.

## D66 — Add stream-shape hit-rate diagnostics before changing cadence again

References:
- RFC 6143 framebuffer update request flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html
- Apple thermal behavior guidance:
  https://support.apple.com/en-us/118431

**Decision**: bump `VNCLiveBenchmark` to schema v36 and add safe aggregate
hit-rate fields to each stream-shape summary:
`attemptedSamples`, `receivedSamplePermille`, `unansweredSamplePermille`,
`contentSamplePermille`, `emptyResponsePermille`, and
`contentResponsePermille`. Also carry content hit-rate permille into per-profile
aggregates and recommendations.

**Why**:
- RFC 6143 makes incremental updates client-request driven and explicitly notes
  that a fast client may regulate request rate to avoid excess traffic. Naru
  therefore needs to know whether a low content-FPS result comes from slow
  responses, unanswered waits, or responses that mostly contain no content.
- TigerVNC exposes automatic encoding/pixel-format selection plus compression,
  quality, preferred encoding, and pointer-rate knobs. That reinforces that
  cadence and profile changes should be based on measured server/link behavior,
  not a single global default.
- Apple documents that warm iPhone conditions can reduce frame rates or
  increase processing times. Before raising request cadence on a hot physical
  iPhone, benchmark reports should show whether the existing cadence is actually
  receiving content-bearing updates efficiently.

**Evidence**:
- `BenchmarkStreamShapeSummaryTests` cover mixed content/empty updates,
  timeout-only runs, explicit attempted-sample hit-rate calculation, legacy JSON
  decode defaults, aggregate hit-rate fields, and safe permille clamping.
- `swift build --product VNCLiveBenchmark` passes.
- Live benchmark execution was not run in this increment because the current
  environment did not provide redacted `NARU_LIVE_MAC_HOST`,
  `NARU_LIVE_MAC_PASSWORD`, or `NARU_LIVE_STIMULUS_COMMAND` values. The next
  T390/T397 physical or localhost run should use schema v36 so the same report
  can distinguish content-hit-rate failures from slow-response failures.

**Interpretation**:
- Low `receivedSamplePermille` or high `unansweredSamplePermille` points toward
  request timeout, server wait, transport compatibility, or stimulus/control
  problems rather than renderer upload pressure.
- High `receivedSamplePermille` but low `contentResponsePermille` means the
  client is getting responses, but the server is often reporting empty updates;
  the next benchmark unit should improve controlled stimulus or request region
  assumptions before changing app defaults.
- High `contentResponsePermille` with low content FPS points back to update
  latency, network/server wait, decode/apply, or local thermal pressure.

**Privacy rule**: hit-rate diagnostics may report only aggregate sample counts
and permille ratios. They must not include per-frame request arrays, raw
timestamps, target identity, credentials, framebuffer dimensions, coordinates,
pixels, cursor pixels, byte counts, raw samples, raw payloads, external command
text, command output, hidden frame contents, hidden frame timings, raw errors,
draft text, marked text, or IME state.

## D67 — Promote profile-level gates for larger sustained optimization units

References:
- RFC 6143 framebuffer update request flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html
- Apple thermal behavior guidance:
  https://support.apple.com/en-us/118431

**Decision**: bump `VNCLiveBenchmark` to schema v37 and add top-level
`streamShapeProfileGates`. A gate summarizes every profile/transport pair with
the fixed practical target name, fixed verdict, fixed issue-code union,
pass/warning/fail/disabled run counts, total run count, and aggregate hit-rate
permille means.

**Why**:
- The work is moving from small tuning PRs to larger units that may change
  cadence, encoding profile, startup preflight, or viewport-interaction stream
  policy. Those decisions need a profile-level gate instead of manually scanning
  many individual stream-shape probes.
- RFC 6143's client-driven request flow means a profile can fail for different
  reasons: unanswered request waits, empty server responses, or slow
  content-bearing responses. Schema v36 exposes those ratios; schema v37 groups
  them at the same profile/transport level used for default-candidate decisions.
- TigerVNC exposes profile-like performance choices through preferred encoding,
  compression, quality, and pointer-rate knobs. Naru should likewise evaluate
  candidate profiles as units, not as isolated per-run samples.
- Apple documents that warm iPhone conditions can reduce frame rate or
  processing responsiveness. A `pass` profile gate therefore only graduates a
  candidate to a physical iPhone hand-feel/thermal pass; it does not by itself
  approve a production default change.

**Interpretation**:
- `fail`: do not promote the profile until the issue-code union is resolved.
- `warning`: require an explicit benchmark artifact judgment before using the
  profile as a candidate.
- `pass`: eligible for physical iPhone verification, subject to the 10 minute
  hand-feel/thermal gate.
- `disabled`: the profile did not produce meaningful stream-shape evidence.

**Privacy rule**: profile gates may report only fixed target names, fixed
verdicts, fixed issue-code labels, aggregate run counts, and aggregate permille
ratios. They must not include host identity, credentials, framebuffer
dimensions, coordinates, pixels, cursor pixels, byte counts, raw FPS, raw
timings, raw samples, raw payloads, raw errors, external command text, command
output, draft text, marked text, or IME state.

## D68 — Use the v2 gate as the next larger-unit goal

References:
- RFC 6143 framebuffer update request flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html
- Apple thermal behavior guidance:
  https://support.apple.com/en-us/118431

**Decision**: treat `iphone-sustained-usability-v2` plus schema v37
`streamShapeProfileGates` as the standard entry gate for larger optimization
PRs. A production default change must have:

- A redacted live v37 profile-gate run with controlled stimulus.
- A clear artifact judgment for every `fail` or intentionally accepted
  `warning` gate.
- A physical iPhone 10 minute hand-feel and thermal pass before enabling the
  change by default.

Keep simulator synthetic frame-pipeline benchmarks as a local renderer
regression guard, not as the final usability proof.

**Why**:
- Recent work already removed obvious renderer full-upload pressure from the
  selected profiles. The latest iPhone simulator run also shows the local Metal
  upload path completing well below a frame budget for 1920x1080 test frames:
  steady-state full upload averaged about 4 ms, small dirty upload averaged
  about 0.5 ms, and same-frame upload-gate skip was effectively zero-cost.
- The remaining practical failures have been content-FPS, update latency,
  hit-rate, cold-tail, Compose preparation, and thermal hand-feel. Those are
  live-stream and device-behavior questions, so the next larger units should
  start from v37 profile gates and then close on a physical iPhone.
- RFC 6143's client-driven update requests make low content FPS ambiguous
  without hit-rate evidence. TigerVNC's exposed encoding and pointer-rate
  controls reinforce that cadence/profile decisions should be profile-level.
  Apple's thermal guidance means a simulator pass cannot approve a sustained
  phone default by itself.

**Evidence**:
- `NARU_RUN_SIM_BENCHMARKS=1` simulator benchmark on iPhone 17 Pro simulator,
  1920x1080, 10 iterations:
  - Full framebuffer allocation plus upload: 9 ms clock, 5 ms CPU.
  - Steady-state full upload: 4 ms clock, 2 ms CPU.
  - Small dirty-rectangle upload: about 0.5 ms clock, about 0.6 ms CPU.
  - Same-frame upload-gate skip: about 0.003 ms clock, about 0.3 ms CPU.
- The final clean benchmark run succeeded. A redacted live v37 run was not
  executed in this increment because the current shell did not provide live
  target or stimulus environment values.

**Interpretation**:
- If a future v37 gate fails with low received/content hit-rate, prioritize
  server request cadence, transport, stimulus assumptions, or target
  reachability before renderer work.
- If a future v37 gate passes but the physical iPhone feels hot or stepped,
  prioritize device pacing, thermal policy, viewport interaction scheduling, or
  input/Compose routing before promoting defaults.
- Renderer upload work should re-enter the main path only when simulator
  benchmarks regress materially or live diagnostics show renderer full-upload
  pressure above the v2 gate.

**Privacy rule**: large-unit artifacts may report fixed target names, fixed
profile/transport labels, fixed verdicts, fixed issue-code labels, aggregate
run counts, aggregate permille ratios, aggregate timing buckets, simulator test
names, and simulator aggregate benchmark means. They must not include host
identity, credentials, framebuffer dimensions from a live target, coordinates,
pixels, cursor pixels, byte counts, raw live samples, raw live payloads, raw
errors, external command text, command output, draft text, marked text, or IME
state.

## D72 - Add an app stream profile experiment gate

References:
- RFC 6143 SetEncodings flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html
- Apple thermal behavior guidance:
  https://support.apple.com/en-us/118431

**Decision**: add a settings-backed `streamEncodingMode` app experiment gate
that defaults to `standard` and cycles through fixed benchmark candidates:

- `standard`
- `zrle-compression-0`
- `adaptive-good-full`

The gate is not a production recommendation or permanent user-facing encoding
picker. It exists so a physical iPhone session can reproduce the same candidate
families being compared by `sustained-v2-core` and
`sustained-v2-pixel-format` before any default changes. Non-standard selections
are applied when the next frame stream connects. Power saver still takes
precedence because heat and sustained usability are the current primary
failure mode.

**Why**:
- Benchmark-only presets are useful, but they do not prove that the app's real
  session lifecycle selects the same RFB preferences under touch, keyboard, and
  viewport pressure.
- Keeping the candidate list fixed prevents diagnostics and settings from
  becoming arbitrary transport logs.
- Applying the selection at connect time avoids a larger active-session
  renegotiation surface until that path has its own fake-server and live tests.

**Evidence**:
- App settings Codable tests cover default omission, decode, encode, and the
  fixed candidate cycle.
- App model tests cover persistence, configured ZRLE renegotiation on connect,
  and power saver overriding a configured stream profile.
- Diagnostic export tests cover schema v27, safe fixed-label export, and
  sanitizer rejection of arbitrary stream-encoding strings.

**Interpretation**:
- Use this gate after a sustained v2 benchmark candidate looks promising and
  before changing the default stream profile.
- A candidate that feels worse, heats the phone, lowers hit-rate, or regresses
  compose/viewport interaction should stay opt-in and feed the next benchmark
  axis instead of becoming the default.
- The next larger units should be measured against practical usability:
  sustained frame smoothness, phone heat, natural zoom/pan, and reliable local
  composition.

**Privacy rule**: app diagnostics may emit only the fixed
`viewerStreamEncodingMode` label. They must not include host identity,
credentials, port value, framebuffer dimensions, coordinates, pixels, cursor
pixels, byte counts, raw timings, raw payloads, draft text, marked text, or IME
state.

## D69 — Add a redacted live benchmark environment preflight

References:
- RFC 6143 framebuffer update request flow:
  https://www.rfc-editor.org/rfc/rfc6143

**Decision**: add `VNCLiveBenchmark --environment-preflight` as a safe
readiness report before live v37 gate runs. The command emits only fixed
readiness labels for host, port, credential source, stimulus mode, stimulus
command requirement, `canRunLiveBenchmark`, and stable issue codes. It exits
before opening a VNC socket and before reading a password prompt.

**Why**:
- The next larger units depend on live schema v37 profile gates, but local
  shells can be missing target, credential, or stimulus setup. A redacted
  preflight lets a diagnostic summary show exactly why a live gate was not
  attempted without requiring the user to paste secrets or raw target values.
- `--ask-password` is still useful for real benchmark runs, but a preflight
  should never block waiting for secret input. It reports `promptRequested`
  instead, making the runbook actionable while preserving the secret boundary.
- RFC 6143 compatibility work still needs real connection attempts after
  readiness passes. This preflight does not replace TCP/RFB probing; it only
  separates local benchmark setup failures from live protocol behavior.

**Evidence**:
- `BenchmarkLiveEnvironmentPreflightTests` cover configured environments,
  missing required fields, prompt-requested credential source without reading a
  password, invalid port labels, and JSON redaction of host/password/command
  values.
- CLI smoke with current empty live environment:
  `VNCLiveBenchmark --environment-preflight --stream-shape-stimulus
  external-command --json` reported fixed issues `missing-host`,
  `missing-credential`, and `missing-stimulus-command`.
- CLI smoke with `--environment-preflight --ask-password` did not prompt and
  reported credential status `promptRequested`.

**Interpretation**:
- `missing-host` means configure the benchmark target before interpreting any
  stream-shape result.
- `missing-credential` means provide a password source through the environment
  or use `--ask-password` for the real run.
- `missing-stimulus-command` means controlled-stimulus v37 gates cannot be
  compared yet.
- `invalid-port` means the configured port value is malformed before any TCP or
  RFB question can be answered.

**Privacy rule**: environment preflight reports may emit only fixed status
labels, fixed issue codes, `canRunLiveBenchmark`, fixed stimulus mode labels,
and schema version. They must not include host identity, credentials, port
value, stimulus command text, command output, TCP errors, RFB errors,
framebuffer dimensions, coordinates, pixels, cursor pixels, byte counts, raw
payloads, draft text, marked text, or IME state.

## D70 — Add a standard sustained v2 gate preset

References:
- RFC 6143 framebuffer update request flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html
- Apple thermal behavior guidance:
  https://support.apple.com/en-us/118431

**Decision**: bump `VNCLiveBenchmark` output to schema v38 and add
`--stream-shape-gate-preset sustained-v2-core`. The preset records
`streamShapeGatePreset` in benchmark reports and fixes the standard larger-unit
gate shape:

- `attempts = 1`
- `fullRefreshSamples = 0`
- `streamShapeSamples = 0`
- `streamShapeDurationSeconds = 10`
- `streamShapeFrameIntervalSeconds = 1/60`
- `streamShapeIdleFrameIntervalSeconds = 0.05`
- app empty backoff, normal power mode, app client-pressure pacing, app
  viewport-interaction pacing
- external-command stimulus with 0.25 second warmup
- zero hidden stream-shape preflight frames
- `iphone-sustained-usability-v2`
- first-frame profiles `none`
- stream-shape profiles `core-matrix`
- stream-shape transport `both`
- five rotated profile iterations
- timeout 6 seconds, idle timeout 1 second

**Why**:
- The large-unit gate should be repeatable. Long hand-built commands are easy
  to drift between PRs, especially around preflight-frame count, transport
  comparison, profile iterations, and app-parity pacing.
- The preset intentionally does not hide the custom option surface. It gives
  default-changing PRs one reproducible starting point while leaving custom
  experiments on the existing explicit flags.
- Preflight now understands the preset because applying the preset sets
  stimulus mode to `external-command`, so missing controlled stimulus is caught
  before any connection attempt.

**Evidence**:
- `BenchmarkStreamShapeGatePresetTests` cover stable raw values and usage
  description.
- `swift build --product VNCLiveBenchmark` passes with schema v38 report
  wiring.
- CLI smoke with
  `--environment-preflight --stream-shape-gate-preset sustained-v2-core
  --ask-password --json` reported `promptRequested`,
  `missing-stimulus-command`, and `external-command` without prompting.
- CLI smoke with dummy host/password/stimulus environment values reported
  `canRunLiveBenchmark: true` without exposing those values.

**Interpretation**:
- Use `sustained-v2-core` as the first live profile-gate command for larger
  cadence, transport, profile, startup preflight, and viewport-scheduling PRs.
- If the preset gate fails, inspect the v37/v38 profile-gate issue union and
  hit-rate fields before making a production default change.
- If the preset gate passes, it still only graduates the candidate to the
  physical iPhone 10 minute hand-feel/thermal pass.

**Privacy rule**: gate preset reports may emit only fixed preset labels, fixed
target/profile/transport/stimulus labels, aggregate gate counts, aggregate
permille ratios, aggregate timing summaries, and existing safe benchmark
fields. They must not include host identity, credentials, port value, stimulus
command text, command output, TCP errors, RFB errors, framebuffer dimensions,
coordinates, pixels, cursor pixels, byte counts, raw payloads, draft text,
marked text, or IME state.

## D71 — Add a benchmark-only pixel-format isolation gate

References:
- RFC 6143 SetPixelFormat and framebuffer update flow:
  https://www.rfc-editor.org/rfc/rfc6143
- TigerVNC viewer performance knobs:
  https://tigervnc.org/doc/vncviewer.html
- Apple thermal behavior guidance:
  https://support.apple.com/en-us/118431

**Decision**: bump `VNCLiveBenchmark` output to schema v39 and add
benchmark-only RGB565-in-32 pixel-format profiles. The new
`--stream-shape-profiles pixel-format-isolation` selection compares:

- `local-low-latency`
- `local-low-latency-rgb565`
- `zrle-compression-0`
- `zrle-compression-0-rgb565`

The new `--stream-shape-gate-preset sustained-v2-pixel-format` uses the same
large-unit gate shape as `sustained-v2-core`: controlled stimulus, both
transports, five rotated iterations, app client-pressure/viewport pacing, ten
second duration, zero hidden stream-shape preflight frames, first-frame
profiles disabled, and the `iphone-sustained-usability-v2` target.

**Why**:
- Low-color VNC modes can reduce server encode and client decode/upload
  pressure only when the server honors `SetPixelFormat`. That is server-specific
  behavior, so app defaults should not change from a code-only assumption.
- Keeping the format 32 bits per pixel with 16-bit RGB565 channel precision lets
  Naru stay on the existing supported true-color framebuffer path while testing
  lower channel precision under live RFB negotiation.
- The same v2 gate shape keeps pixel-format comparisons from being confused by
  different stimulus, transport, pacing, or profile-order conditions.

**Evidence**:
- `RFBEncodingTests` cover full-color and RGB565 SetPixelFormat wire bytes.
- `RFBRawFramebufferDecoderTests` cover non-byte-aligned RGB565 channel decode
  through the existing 32-bit true-color path.
- `BenchmarkStreamShapeProfileSelectionTests` cover
  `pixel-format-isolation` expansion and missing-profile failures.
- `BenchmarkStreamShapeGatePresetTests` cover stable
  `sustained-v2-pixel-format` CLI contract.
- `FakeRFBServerIntegrationTests` cover a production `RFBNetworkClient`
  sending `SetPixelFormat` before `SetEncodings` over a loopback fake RFB
  socket, then decoding the first RGB565 raw framebuffer update.
- `swift build --product VNCLiveBenchmark` passes with schema v39 report
  wiring.

**Interpretation**:
- Use `sustained-v2-pixel-format` only after the core gate shows profile or
  transport pressure that might benefit from lower color precision.
- Treat any RGB565 win as a candidate for physical iPhone verification, not a
  production default change by itself.
- If RGB565 produces decode failures, color artifacts, or worse hit-rate/gate
  results, keep the current app default and continue with cadence, transport,
  or server-side alternatives.

**Privacy rule**: pixel-format benchmark reports may emit only fixed profile
labels, fixed preset labels, aggregate gate counts, aggregate permille ratios,
aggregate timing summaries, and existing safe benchmark fields. They must not
include host identity, credentials, port value, stimulus command text, command
output, TCP errors, RFB errors, framebuffer dimensions, coordinates, pixels,
cursor pixels, byte counts, raw payloads, draft text, marked text, or IME
state.
