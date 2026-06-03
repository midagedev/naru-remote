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
