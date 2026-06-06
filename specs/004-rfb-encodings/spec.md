# Feature Specification: RFB Encodings — Efficient Streaming For Real VNC Servers

**Feature Branch**: `004-rfb-encodings`
**Created**: 2026-05-31
**Status**: Draft
**Product**: Naru Remote
**Input**: Goal — make Naru Remote's VNC streaming as good as it can possibly be ("할수있는한 최고의 vnc 스트리밍"). The MVP renders **Raw** encoding only: every framebuffer update ships uncompressed 32-bit pixels. A 1920×1080 desktop is ~8.3 MB per full frame and re-sends every changed region as raw pixels. Over a phone's cellular link — the canonical ICP scenario (sustained terminal/AI-CLI sessions from an iPhone, constitution §VI) — Raw is unusable: a single full repaint is ~66 Mbit. Real VNC servers (macOS Screen Sharing, TigerVNC/TurboVNC, RealVNC, x11vnc, TightVNC) default to **Hextile / ZRLE / Tight** and pseudo-encodings (CopyRect for scroll, DesktopSize for resize, Cursor for client-side pointer). Naru currently sends no `SetEncodings`, so servers fall back to Raw, and the client *rejects* any non-Raw rectangle it receives. This feature makes Naru a real RFB client: it negotiates encodings, decodes the efficient ones, and adapts quality to the link. It is the **protocol layer**; it does not change the viewport/pointer presentation layer (that is `specs/003-session-experience`, shipped).

## Why This Feature

Measured against Google Remote Desktop (the usability bar for this product) and against any production VNC viewer, three protocol gaps make Naru's stream the weakest part of the product:

1. **Raw-only is bandwidth-fatal on cellular.** `RFBRawFramebufferDecoder` throws `unsupportedEncoding` for anything but encoding 0, and `RFBNetworkClient.readFramebufferUpdateData` pre-computes each rectangle's byte count as `width*height*bytesPerPixel` — a model that *only* works for fixed-size Raw. The most common real-server encodings are variable-length and compressed. Result: against a server that honors our (absent) preference list we get Raw; against a server that insists on its default we get a decode error. Neither is acceptable.
2. **No `SetEncodings` negotiation.** There is no client message to advertise supported encodings (RFC 6143 §7.5.2, message type 2) and no encoder for it. Without it the server has no way to know Naru can do better than Raw, and pseudo-encodings (CopyRect, DesktopSize, Cursor, LastRect, continuous updates) are never enabled.
3. **No flow control or adaptivity.** Every frame is a fresh full/incremental `FramebufferUpdateRequest` round-trip with no continuous-updates / fence pacing, and no quality/compression-level negotiation tied to the connection-quality bucket that `specs/003` already computes. On a good tailnet we leave latency on the table; on a poor cellular link we have no lever to trade fidelity for responsiveness.

Closing these makes Naru usable on the exact link its ICP lives on, and makes "it works against my actual Mac/Linux box" true instead of aspirational.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Scrolling A Terminal Doesn't Re-Send The Screen (Priority: P1)

A user scrolls a full-screen terminal or moves a window on the remote Mac. Instead of the server re-transmitting every changed pixel as Raw, it sends a **CopyRect** ("copy this on-screen region to there") plus a small Raw/Hextile patch for the newly exposed strip. Naru applies the copy locally — near-zero bytes for the bulk of the motion.

**Why this priority**: Scrolling and window motion are the dominant interactions in a terminal/AI-CLI session (the ICP). CopyRect is the single highest bytes-saved-per-line-of-code encoding, is fully deterministic, and is unit-testable with no compression dependency.

**Independent Test**: Unit — decode a `FramebufferUpdate` containing one CopyRect rectangle `(dst=(0,0,w,h-10), src=(0,10))` against a known previous framebuffer; assert the destination region equals the source region shifted, with no other pixels touched, and that the damage rect covers exactly the destination. Integration — a `FakeRFBServer` hex fixture replaying a Raw first frame then a CopyRect update; assert the decoded second framebuffer.

**Acceptance Scenarios**:

1. **Given** a previous framebuffer and an update with a CopyRect rectangle, **When** decoded, **Then** the destination rectangle's pixels equal the source rectangle's pixels (copied from the *previous* frame state, per RFC 6143 §7.7.2) and the damage rect equals the destination rectangle.
2. **Given** a CopyRect whose source or destination falls outside the framebuffer, **When** decoded, **Then** the decoder rejects it with a typed error (never traps, never reads out of bounds).
3. **Given** a mixed update (CopyRect + Raw rectangles in one `FramebufferUpdate`), **When** decoded, **Then** rectangles are applied in wire order and the final framebuffer reflects all of them.

---

### User Story 2 — A Full Repaint Costs Kilobytes, Not Megabytes (Priority: P1)

A user opens a window or a page repaints. The server sends the region as **Hextile** (16×16 tiles, each Raw or background+foreground+subrects) and/or **ZRLE** (zlib-compressed RLE/palette tiles). Naru decodes both. A mostly-solid desktop region that was ~8 MB of Raw becomes a few KB.

**Why this priority**: Hextile is universally supported, zlib-free, and fully unit-testable — it is the dependency-free bandwidth win and the safe floor every real server speaks. ZRLE is the bandwidth centerpiece for cellular (TigerVNC/macOS default-tier) and the biggest single fidelity-per-byte improvement; its decode logic is unit-testable with crafted zlib fixtures, with real-server throughput as a residual-risk device pass.

**Independent Test**: Hextile — unit-decode tiles exercising every subencoding-mask bit (Raw tile, BackgroundSpecified, ForegroundSpecified, AnySubrects, SubrectsColoured) against crafted bytes; assert pixels and that background/foreground carry across tiles when their bits are unset (per §7.7.4). ZRLE — unit-decode a zlib stream (produced by zlib at test time) carrying RLE-plain, palette, and palette-RLE tiles; assert pixels and that the **single zlib stream persists across rectangles and across updates** within a session.

**Acceptance Scenarios**:

1. **Given** a Hextile rectangle whose tiles use background-carry (no BackgroundSpecified bit), **When** decoded, **Then** each such tile reuses the previous tile's background colour (§7.7.4).
2. **Given** a Hextile tile with `AnySubrects | SubrectsColoured`, **When** decoded, **Then** each coloured subrect paints its own colour at its tile-relative `(x,y,w,h)`.
3. **Given** a ZRLE rectangle, **When** decoded, **Then** the zlib-inflated tile stream paints solid / RLE / palette / palette-RLE tiles correctly, and the inflate context is **not** reset between rectangles or between successive updates (a reset would corrupt every subsequent frame).
4. **Given** a truncated/oversized compressed payload, **When** decoded, **Then** a typed error surfaces (no trap, no infinite read).

---

### User Story 3 — Naru Tells The Server What It Can Do (Priority: P1)

On connect, Naru sends a `SetEncodings` advertising — in server-honored priority order — the encodings it decodes plus the pseudo-encodings it wants (CopyRect, DesktopSize/ExtendedDesktopSize, LastRect, Cursor, continuous updates, and the quality/compression-level hints). The server then uses an efficient encoding instead of falling back to Raw.

**Why this priority**: Without `SetEncodings` every other encoding in this spec is dead code — the server never sends them. It must ship with, and before, the decoders are useful end-to-end.

**Independent Test**: Unit — `RFBClientMessageEncoder.setEncodings([...])` produces the exact wire bytes (type 2, padding, big-endian count, then each `Int32` big-endian) for a known list. Integration — connect the real `RFBNetworkClient` to a `FakeRFBServer`; assert the recorded client transcript contains a well-formed `SetEncodings` with CopyRect/Hextile ahead of Raw, and Raw present as the guaranteed floor.

**Acceptance Scenarios**:

1. **Given** a connected session, **When** the handshake completes, **Then** Naru sends exactly one `SetEncodings` whose list begins with the most-preferred supported encoding, includes every encoding Naru can decode, always includes Raw (0) as the universal fallback, and includes the requested pseudo-encodings.
2. **Given** a server that ignores preferences and sends Raw anyway, **When** frames arrive, **Then** Naru still renders (Raw remains fully supported) — negotiation is an optimization, never a correctness dependency.
3. **Given** a server that sends an encoding Naru did **not** advertise, **When** that rectangle is received, **Then** Naru surfaces a typed `unsupportedEncoding` mapped to an actionable diagnostic stage, without crashing the stream.

---

### User Story 4 — The Remote Resolution Can Change Mid-Session (Priority: P2)

The user changes the remote display resolution, plugs in a monitor, or rotates an iPad-as-host. The server sends a **DesktopSize** (-223) / **ExtendedDesktopSize** (-308) pseudo-rectangle. Naru resizes its framebuffer and the viewport re-frames to the new size (the presentation re-fit is `specs/003`'s already-built `ViewportTransform` recompute).

**Why this priority**: Without this, a resolution change desyncs the framebuffer dimensions and every subsequent rectangle is "out of bounds" — the stream dies. It is required for a session to survive real desktop use, but is rarer than scroll/repaint.

**Independent Test**: Unit — decode an update whose first pseudo-rectangle is DesktopSize `(new w,h)`; assert the returned framebuffer is reallocated to the new size and a "desktop resized" signal is surfaced so the App layer recomputes fit. ExtendedDesktopSize — assert the screen-array payload is parsed for its width/height and the reason/result codes are handled.

**Acceptance Scenarios**:

1. **Given** an active session, **When** a DesktopSize pseudo-rectangle arrives, **Then** the framebuffer is reallocated to the new dimensions (preserving content where it overlaps is **not** required), and subsequent rectangles validate against the new bounds.
2. **Given** an ExtendedDesktopSize with a client-initiated vs server-initiated reason code, **When** decoded, **Then** the result code is interpreted per RFC and a resize signal (not an error) is produced.
3. **Given** a resize signal reaches the App layer, **When** the viewport re-renders, **Then** it re-fits to the new aspect ratio (reusing `specs/003` transform recompute) — no hardcoded ratio, no stuck pan.

---

### User Story 5 — A Crisp Pointer Without A Round-Trip (Priority: P3)

The remote cursor shape and position are delivered as **Cursor (-239) / RichCursor / XCursor (-240)** pseudo-encodings and drawn locally, so the on-screen pointer tracks the user's input without waiting for a server repaint of the area under the cursor.

**Why this priority**: A nice-to-have polish that reduces cursor lag and matches GRD's feel. It is independent of the bandwidth-critical encodings and lower risk to defer. Note `specs/003` already draws a **synthetic** trackpad cursor; this story is about the **server-provided** cursor shape for direct-touch fidelity and is explicitly optional.

**Independent Test**: Unit — decode a Cursor pseudo-rectangle (pixels + 1bpp mask) into a cursor image + hotspot; assert dimensions, hotspot, and that masked-out pixels are transparent. Assert no framebuffer pixels are modified by a cursor pseudo-rectangle.

**Acceptance Scenarios**:

1. **Given** a Cursor pseudo-rectangle, **When** decoded, **Then** a cursor image + hotspot is produced and the main framebuffer is unchanged.
2. **Given** the cursor pseudo-encoding was not negotiated or not sent, **When** rendering, **Then** the existing synthetic cursor (`specs/003`) is used — server cursor is additive, never a dependency.

---

### User Story 6 — The Stream Adapts To The Link (Priority: P3)

On a poor connection-quality bucket (`specs/003`'s `ConnectionQuality`), Naru requests a lower JPEG quality / higher compression level (Tight quality-level −23…−32, compression-level 0…−9 pseudo-encodings) and/or enables continuous updates + fence pacing to keep the session responsive; on a good bucket it requests higher fidelity.

**Why this priority**: The adaptive lever is what turns "decodes efficiently" into "feels good on cellular." It depends on Tight/continuous-updates being in place and on the quality bucket, so it sequences last.

**Independent Test**: Unit — given a quality bucket, the encoding-preference builder emits the corresponding quality/compression pseudo-encoding codes in `SetEncodings`; given a fence request, the fence response is well-formed. Assert no latency value or pixel content is logged when the bucket drives a re-negotiation.

**Acceptance Scenarios**:

1. **Given** a `poor` quality bucket, **When** the preference list is (re)built, **Then** it includes a lower JPEG-quality and higher-compression pseudo-encoding code than for a `good` bucket.
2. **Given** continuous updates are supported and enabled, **When** the server sends an EndOfContinuousUpdates / fence, **Then** Naru responds per RFC and frames keep flowing without an explicit per-frame request.
3. **Given** any re-negotiation, **When** it happens, **Then** no latency sample, coordinate, or pixel value is written to any log or diagnostic export (constitution §IV).

### Edge Cases

- **Server insists on Raw**: fully supported — Raw is the floor and never removed from the advertised list.
- **Server sends an un-advertised encoding**: typed `unsupportedEncoding(code)` mapped to a diagnostic stage; the stream surfaces a clear error rather than silently corrupting or trapping.
- **zlib stream desync (ZRLE/Tight)**: the per-session inflate context must persist; if a decode consumes the wrong number of bytes the whole session corrupts. Decoders MUST consume exactly the declared compressed length and surface a typed error on mismatch rather than reading ahead.
- **Variable-length rectangle spanning multiple TCP reads**: the incremental byte reader MUST block for more bytes (up to timeout) mid-rectangle; it must never assume one `recv` yields a whole rectangle.
- **ContinuousUpdates idle timeout**: after ContinuousUpdates is enabled, a receive timeout with **zero bytes consumed for the next server message** is treated as a zero-change transport-idle tick and MUST NOT close the socket. If any bytes from a server message were already consumed before timeout/close, the stream MUST fail rather than pretending the partial message was idle.
- **CopyRect from a region the client hasn't painted yet**: applies whatever is currently in the framebuffer (server's responsibility to order); decoder copies from current state, in wire order within the update.
- **DesktopSize shrink while zoomed/panned**: framebuffer reallocates; `specs/003` transform re-clamps pan so no out-of-bounds reveal (already handled there for the dimension-change case).
- **LastRect (-224)**: an update may declare 0xFFFF rectangles and terminate with a LastRect pseudo-rectangle; the reader MUST stop at LastRect instead of trying to read 65535 rectangles.
- **PiP watch path**: unchanged — decoding feeds the same `RFBRawFramebuffer`; PiP remains watch-only (constitution + ROADMAP Phase 6).
- **Pixel format**: Naru advertises/uses 32-bit true-colour (the existing `RFBRawFramebufferDecoder` constraint). If `SetPixelFormat` is sent, all decoders MUST honor the negotiated format consistently; if not sent, the server's `ServerInit` format is used as today.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Naru MUST send exactly one `SetEncodings` (RFC 6143 §7.5.2, message type 2) after `ServerInit`/`ClientInit`, listing supported encodings in server-honored preference order, always including Raw (0) as the universal fallback.
- **FR-002**: The framebuffer-update read path MUST decode rectangles incrementally from a byte stream (an `RFBByteReader`) rather than pre-computing a fixed per-rectangle byte count, so variable-length encodings are supported. The pure decoder API (`Data + serverInit + previousFramebuffer → RFBFramebufferUpdateResult`) MUST be preserved for unit testing by wrapping the `Data` in a reader.
- **FR-003**: Naru MUST decode **CopyRect** (encoding 1, §7.7.2): copy a source rectangle of the current framebuffer to the destination rectangle; reject out-of-bounds src/dst with a typed error.
- **FR-004**: Naru MUST decode **Hextile** (encoding 5, §7.7.4): 16×16 tiles left-to-right, top-to-bottom; per-tile subencoding mask (Raw, BackgroundSpecified, ForegroundSpecified, AnySubrects, SubrectsColoured); background/foreground carry across tiles when their bits are unset.
- **FR-005**: Naru MUST decode **ZRLE** (encoding 16, §7.7.6): a 4-byte length-prefixed zlib stream carrying 64×64 tiles (raw, solid, palette, plain-RLE, palette-RLE). The zlib inflate context MUST persist for the lifetime of the session (one stream across all rectangles and updates), never reset per rectangle.
- **FR-006**: Naru SHOULD decode **Tight** (encoding 7): basic-copy / fill / gradient / JPEG sub-encodings using up to four persistent zlib streams and JPEG via the platform image decoder. JPEG decode MUST happen off the framebuffer hot path's main actor. (Tight is the lowest-priority encoding and MAY ship after CopyRect/Hextile/ZRLE.)
- **FR-007**: Naru MUST handle the **LastRect** (-224) pseudo-encoding: stop reading rectangles when LastRect is seen, supporting updates declared with the 0xFFFF "unknown count" sentinel.
- **FR-008**: Naru MUST handle **DesktopSize** (-223) and SHOULD handle **ExtendedDesktopSize** (-308): reallocate the framebuffer to the new dimensions and surface a resize signal so the App layer re-fits the viewport (reusing `specs/003`). Subsequent rectangles validate against the new bounds.
- **FR-009**: Naru SHOULD decode the **Cursor (-239) / XCursor (-240)** pseudo-encodings into a cursor image + hotspot without modifying the framebuffer; this is additive to the existing synthetic cursor and never a dependency.
- **FR-010**: A server-sent encoding that Naru did not advertise MUST surface a typed `unsupportedEncoding(code)` that maps to an actionable diagnostic stage (reusing the existing diagnostics catalog), without trapping or corrupting the stream.
- **FR-011**: Decoders for incremental encodings (CopyRect, Hextile, ZRLE, Tight) MUST mutate the previous framebuffer in place and report accurate `dirtyRectangles` + `changedPixelCount` in `RFBFramebufferUpdateResult`, consistent with the existing Raw decoder contract.
- **FR-012**: The encoding-preference list builder MUST be a pure function of (supported decoders, requested pseudo-encodings, connection-quality bucket) so it is unit-testable and so the quality bucket from `specs/003` can adapt JPEG-quality / compression-level pseudo-encodings (FR-013).
- **FR-013**: Naru SHOULD adapt the advertised Tight quality-level (-23…-32) and compression-level (0…-9) pseudo-encodings to the current `ConnectionQuality` bucket; and SHOULD negotiate continuous updates / fence (-312/-313) pacing when available. These are optimizations gated behind the encodings they ride on.
- **FR-014**: All multi-byte protocol fields MUST be parsed/serialized big-endian per RFC 6143; decoders MUST never read past the declared length of a rectangle or compressed block.
- **FR-015**: Naru MAY expose a fixed-catalog, opt-in app stream profile experiment gate for benchmark candidates before any production default changes. The gate MUST default to the existing automatic profile, persist only a safe fixed label, apply no earlier than the next connection unless a separately tested live renegotiation path exists, and be recorded in diagnostics only as that fixed label.
- **FR-016**: Benchmark promotion for poor-network usability MUST treat traffic pressure as a first-class target. Request-region candidates MUST report a redacted framebuffer-relative `requestRegionAreaPermille` traffic proxy alongside hit-rate, latency, dirty-area, first-frame startup latency, and renderer-upload aggregates; reports MUST NOT emit raw byte counts, framebuffer dimensions, coordinates, pixels, or payloads. A production request-region default MUST preserve full-frame fallback/heartbeat behavior and must not be promoted solely on FPS if it increases unanswered requests, timeout/failure labels, startup delay, or tail latency.

### Naru Input Requirements *(mandatory if feature handles input)*

- **IN-001 Local composition path**: unchanged — this is a server→client *rendering* feature. It introduces no text path and does not touch Compose & Send (constitution §I).
- **IN-002 Remote injection behavior**: the only client→server messages added are `SetEncodings` (type 2) and optionally `SetPixelFormat` (type 0), fence responses, and EnableContinuousUpdates — all session/transport control, not user input. Pointer/key paths are unchanged (`specs/002`/`003`).
- **IN-003 Fallback behavior**: if negotiation yields nothing better, Raw is used (existing path). If a needed encoding fails to decode, the typed error tears the stream down cleanly into the reconnect path (`ReconnectPolicy`), not a crash.
- **IN-004 Clipboard impact**: none. `ServerCutText`/`ClientCutText` paths are unchanged.
- **IN-005 User confirmation**: none for the production default path - encoding negotiation is automatic transport behavior. Temporary benchmark experiment gates are allowed only as fixed-catalog opt-ins under FR-015.

### Tailnet / Connection Requirements

- **TN-001 Private-network assumption**: inherited from MVP; rides the existing VNC session over the tailnet.
- **TN-002 Diagnostics shown to user**: the negotiated encoding *name* (e.g. "ZRLE") MAY be surfaced as a safe diagnostic label from the fixed catalog. Pixel content, compressed bytes, rectangle coordinates, byte counts, and latency values MUST NOT appear in any diagnostic export (constitution §IV).
- **TN-003 Public internet posture**: inherited — unchanged. Compression does not alter the trust posture; it is the same byte stream, encoded.

### Security & Privacy Requirements *(mandatory)*

- **SP-001 Data crossing local→remote**: only `SetEncodings` / `SetPixelFormat` / fence / continuous-update control messages (no user content). Server→client framebuffer pixels are the same data class as today, merely compressed.
- **SP-002 Data retained on device**: the per-session zlib inflate context and the current framebuffer are in-memory only and torn down on disconnect/profile change (same lifecycle as `clientFramebuffer` today). No compressed payload, tile, coordinate, or byte count is persisted or logged.
- **SP-003 Data retained on remote host**: unchanged — Naru does not control server-side logging.
- **SP-004 Sensitive actions needing approval**: none new.
- **SP-005 Logging rule**: rectangle coordinates, tile data, palette entries, compressed/decompressed byte counts, JPEG payloads, cursor pixels, and pixel values MUST NOT be written to any log, diagnostic, telemetry, or crash report. Only fixed-catalog safe labels (encoding name, generic stage status) may surface. The decode hot path MUST contain no `print`/logging of payload.
- **SP-006 Decoder robustness as security**: all decoders MUST treat server bytes as untrusted — bounds-checked, length-honoring, allocation-bounded (reject absurd dimensions/lengths), and trap-free. A malformed or hostile server stream MUST surface a typed error and tear down, never an out-of-bounds read, unbounded allocation, or crash.

### Key Entities *(include if feature involves data)*

- **RFBEncoding** — the encoding/pseudo-encoding code registry (Raw=0, CopyRect=1, Hextile=5, Tight=7, ZRLE=16; pseudo: LastRect=-224, DesktopSize=-223, ExtendedDesktopSize=-308, Cursor=-239, XCursor=-240, DesktopName=-307, Fence=-312, ContinuousUpdates=-313, JPEG-quality −23…−32, compression-level 0…−9). Pure constants in `NaruRemoteCore`.
- **RFBEncodingPreference** — pure builder: (supported decoders, requested pseudo-encodings, quality bucket) → ordered `[Int32]` for `SetEncodings`. Unit-testable; the adaptivity seam (FR-012/013).
- **RFBByteReader** — incremental byte cursor: `read(_ count) throws -> [UInt8]` / typed primitives (u8/u16/u32/s32 big-endian). Backed by a fixed `Data` (tests) or the live connection (`readExactly`). The decode-as-you-read seam (FR-002).
- **RFBRectangleDecoder** — per-encoding decoder consuming exactly its rectangle's bytes from an `RFBByteReader` and mutating the framebuffer; dispatched by `encodingType`. Raw/CopyRect/Hextile/ZRLE/Tight conform.
- **RFBZlibInflateStream** — session-lifetime persistent zlib inflate (Compression-framework streaming, zlib/RFC-1950 framing) shared by ZRLE and Tight; reset only on a fresh session.
- **RFBFramebufferUpdateResult** — unchanged contract (framebuffer + dirtyRectangles + changedPixelCount + capturedAt); every new decoder produces it.
- **RFBDesktopResize** — signal value (new width/height + reason) surfaced from a DesktopSize pseudo-rectangle to the App layer.
- **RFBServerCursor** — decoded cursor image + hotspot from the Cursor pseudo-encoding (optional, US5).

## Acceptance Test Matrix *(mandatory)*

Per constitution §VI/§III, every scenario lists an iPhone path before any iPad path, and protocol/streaming claims are proven against the fake RFB server before "done."

| Scenario | Verification Type | Device Class | Required Evidence |
| --- | --- | --- | --- |
| `SetEncodings` wire bytes for a known list | Unit | iPhone (simulator) | `RFBClientMessageEncoder.setEncodings` byte-exact test |
| Preference list ordering (CopyRect/Hextile ahead of Raw; Raw always present) | Unit | iPhone (simulator) | `RFBEncodingPreference` builder test |
| Client sends well-formed `SetEncodings` end-to-end | Integration (Fake RFB) | iPhone (simulator) | recorded client transcript contains the message |
| CopyRect copies src→dst, bounds-checked, damage = dst | Unit + Fake RFB | iPhone (simulator) | decoder pixel asserts + hex-fixture integration |
| Hextile: every subencoding-mask bit; bg/fg carry across tiles | Unit | iPhone (simulator) | crafted-bytes decoder asserts |
| ZRLE: raw/solid/palette/RLE/palette-RLE tiles; persistent zlib across rects+updates | Unit | iPhone (simulator) | zlib-fixture decoder asserts; context-persistence test |
| Tight: fill/copy/gradient/JPEG sub-encodings | Unit | iPhone (simulator) | crafted + JPEG-fixture decoder asserts (if shipped) |
| LastRect terminates a 0xFFFF-count update | Unit | iPhone (simulator) | reader stops at LastRect |
| DesktopSize reallocates framebuffer; resize signal surfaced | Unit | iPhone (simulator) | reallocation + signal asserts |
| Un-advertised encoding → typed error mapped to diagnostic stage | Unit | iPhone (simulator) | error-mapping test; no trap |
| Malformed/truncated/hostile payload → typed error, no trap/OOB | Unit | iPhone (simulator) | fuzz-style robustness asserts |
| No pixel/coord/byte-count/latency in diagnostic export | Unit + static review | iPhone (simulator) | `DiagnosticExport` render test; grep of decode path |
| Adaptive: quality bucket changes preference codes | Unit | iPhone (simulator) | builder test across buckets |
| ContinuousUpdates idle timeout preserves connection; partial message timeout fails | Fake RFB | iPhone (simulator) | `RFBNetworkClient` integration tests for idle zero-byte timeout and partial-message failure |
| Real Mac (Screen Sharing) + TigerVNC: live ZRLE/Tight throughput, scroll via CopyRect, resolution change | Manual device | iPhone (physical) | Manual log (residual risk — no VNC server/device in env) |
| Encoded stream renders + viewport re-fit on iPad | Screenshot | iPad (simulator) | screenshot after iPhone path recorded |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Against a `FakeRFBServer` Raw-then-CopyRect transcript, a scroll-style update is decoded correctly with the destination region copied from the previous frame — proving Naru no longer needs full Raw re-sends for motion (unit + integration).
- **SC-002**: A full repaint encoded as Hextile of a mostly-solid region decodes to the correct framebuffer using a fraction of Raw's bytes (a 1920×1080 solid fill is < 1 KB of Hextile vs ~8 MB Raw) — verified by decoding a crafted Hextile fixture and comparing payload size to the equivalent Raw.
- **SC-003**: A ZRLE stream spanning multiple rectangles and multiple successive updates decodes correctly using one persistent zlib context; resetting the context between rectangles is proven (by test) to corrupt frame 2+, confirming the persistence requirement is real and met.
- **SC-004**: Naru sends a well-formed `SetEncodings` advertising CopyRect/Hextile (and ZRLE/Tight where shipped) ahead of Raw, with Raw always present; verified in the recorded `FakeRFBServer` client transcript.
- **SC-005**: A server-sent un-advertised or malformed encoding never crashes or hangs the client — it always surfaces a typed error that maps to a diagnostic stage and the reconnect path (verified by negative-path unit tests).
- **SC-006**: No pixel value, tile/palette datum, rectangle coordinate, compressed/decompressed byte count, JPEG payload, cursor pixel, or latency value appears in any diagnostic export or log (constitution §IV) — verified by a `DiagnosticExport` rendering test plus static review of the decode path.
- **SC-007**: Viewport-aware request-region candidates are considered promotion-ready for poor network conditions only when the benchmark shows a meaningful requested-area reduction versus `full` (reported as `requestRegionAreaPermille`), while matching or improving the incumbent's first-frame startup band, usable-run count, content FPS band, hit-rate band, p95 update tail, and failure-label profile. A candidate that saves area but destabilizes startup or the sustained stream remains a research result, not a production default.

### Default-Change Promotion Contract

Current production-default changes that affect streaming or interaction behavior
must follow
`artifacts/benchmarks/2026-06-06-sustained-usability-candidate-contract.md`:
benchmark-green first, physical iPhone green second, and rollback note before
changing transport, encoding, preflight, pacing, or interaction defaults.

## Assumptions

- 32-bit true-colour pixel format remains the working assumption (existing `RFBRawFramebufferDecoder` constraint); ZRLE's "CPIXEL" compaction (3-byte pixels when the format allows) is handled where applicable but the framebuffer stays RGBA8.
- The platform `Compression` framework provides streaming zlib inflate sufficient for RFB's continuous zlib stream (RFC 1950 framing handled by consuming the 2-byte header once and feeding the remainder as raw DEFLATE to a persistent stream, honoring `Z_SYNC_FLUSH` boundaries). This is the single new platform dependency; CopyRect/Hextile need none.
- The Metal renderer re-uploads the full framebuffer per frame today; incremental encodings produce a correct full `RFBRawFramebuffer`, so no GPU partial-upload change is required for correctness (a dirty-rect GPU upload is a later optimization, not in scope).
- Real-server behavior (macOS Screen Sharing's ZRLE/Tight quirks, TigerVNC's Tight-JPEG, RealVNC's proprietary tiers) cannot be fully verified without physical servers; per constitution §III those claims are explicit residual-risk device-pass tasks, while all decode logic is proven against crafted fixtures first.
- iPhone-first per constitution §VI; iPad is graceful scaling and rides the same decode path.

## Non-Goals

- **Proprietary RealVNC encodings** (e.g. their adaptive/ZRLEE variants) and **Apple Remote Desktop's encrypted ARD-specific tiers** — standard RFB encodings only.
- **Encoding (client→server) of a framebuffer** — Naru is a viewer, not a server; only decode is in scope.
- **GPU dirty-rectangle partial upload / Metal renderer optimization** — correctness-first; the full re-upload stays. A later perf spec may add it.
- **Audio / file-transfer / RemoteFX / H.264 (open-h264 VNC) extensions** — out of scope.
- **Changing the viewport/pointer presentation** — that is `specs/003` (shipped); this feature only changes what bytes are decoded into the framebuffer.
- **A permanent production user-facing encoding picker** - negotiation is automatic by default; manual override is not a product goal. A fixed-catalog benchmark experiment gate is allowed only under FR-015 and must not imply the selected candidate is the recommended default.
- **`SetPixelFormat` to a non-32bpp format** — Naru keeps 32-bit true-colour; sending `SetPixelFormat` (if at all) only re-asserts that format.
