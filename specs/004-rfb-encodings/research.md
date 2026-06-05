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
