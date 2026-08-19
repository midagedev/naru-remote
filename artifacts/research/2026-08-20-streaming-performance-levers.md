# Web research — remote-desktop streaming levers for Naru Remote

Read-only round. No tree changes. Progress log not written (write-block). Sources are URLs below.

---

## 1. Premise corrections

The measured VNC ceiling (~5.6 fps ZRLE, no Tight, no RFB ContinuousUpdates) is still the right description **for an RFC-compliant third-party client**. Three nuances change the *unpulled-lever* picture:

**A. Apple is not Tight-less — it is *Apple-codec-only* for Mac clients.** Native Screen Sharing / Screens 5 Adaptive Quality ride Apple still-image encodings `0x3e8` / `0x3e9` / `0x3ea` / `0x3f3` and an optional Adaptive-media HEVC path, not Tight JPEG. A client that only advertises ZRLE/Raw/CopyRect gets ZRLE. A client that speaks Apple encodings can leave that path. Primary: reverse-engineered spec [iShareScreen `apple_vnc_rfc.md`](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md); Screens docs [Adaptive Quality is Mac-only](https://help.edovia.com/en/screens-5/features/images-quality).

**B. “Encoding 16/17, Apple pseudo-encodings 1100–1105” is a numbering mix-up.** IANA Tight *encoding* is **7**; Tight *security type* is **16**; Ultra is **17**. Apple’s observed FBU encodings sit at `0x3e8`–`0x3f3` (1000–1011) and `0x44f`–`0x456` (1103–1110). So **1103–1105 match** (`0x44f` rekey, `0x450` cursor, `0x451` display layout); 16/17 are not Apple framebuffer codecs. [IANA RFB](https://www.iana.org/assignments/rfb/rfb.xhtml); iShareScreen RFC §8.9 / §8.3–8.4.

**C. High-Performance screen sharing is no longer “no public third-party path.”** Apple still documents it as Apple-Silicon ↔ Apple-Silicon, HEVC 4:4:4, UDP 5900–5902, 30/60 fps ([Apple ARD guide](https://support.apple.com/guide/remote-desktop/use-high-performance-screen-sharing-apdf8e09f5a9/mac)). A 2026 reverse-engineering client ([iShareScreen](https://github.com/renegadelink/iShareScreen); [LibVNC #696](https://github.com/LibVNC/libvncserver/issues/696)) implements HEVC RExt 4:4:4 over SRTP/UDP keyed in-band. It is unofficial, AGPL, legally/technically heavy — but the “no API” claim from 2026-07-05 is stale.

**D. Apple has a *proprietary* server-push, not RFB CU.** `AutoFrameBufferUpdate` (`0x09`) arms free-running framebuffer/cursor updates. That is CU-shaped, Apple-only. [iShareScreen RFC §8.11](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md).

**E. WWDC21 VideoToolbox low-latency rate control was announced as H.264-only.** HEVC hardware encode exists independently (`kVTCompressionPropertyKey_RealTime` + no reordering). Whether `EnableLowLatencyRateControl` applies to HEVC is **not documented** in that session. [WWDC21 10158](https://developer.apple.com/videos/play/wwdc2021/10158/).

No public source found that Apple Screen Sharing serves Tight or RFB ContinuousUpdates to third-party clients. The ~5.6 fps ZRLE ceiling for the current Naru VNC path stands.

---

## 2. Ranked improvement candidates

| Rank | Idea | Path | Works vs Apple Screen Sharing? | Expected impact | Effort | Key source |
|------|------|------|-------------------------------|-----------------|--------|------------|
| 1 | Wire `requestKeyframe` / stall recovery + VT low-latency properties (`EnableLowLatencyRateControl`, `RealTime`, no B-frames, `MaxAllowedFrameQP`) | helper | n/a (own encoder) | latency, stall recovery, sharper text under loss | S | [WWDC21 10158](https://developer.apple.com/videos/play/wwdc2021/10158/) |
| 2 | Adaptive bitrate on helper (RTT/loss → target bitrate + optional FPS drop; cap on `isExpensive`) | helper | n/a | bandwidth, latency on tailnet/cellular | M | [Parsec BUD](https://parsec.app/blog/a-networking-protocol-built-for-the-lowest-latency-interactive-game-streaming-1fd5a03a6007); [RustDesk `enable-abr`](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/) |
| 3 | Advertise Apple `ScaleFactor` `0x08` at 0.5 (Screens “Compression”) when zoomed-out / cellular / 5K hosts | VNC | **yes** (Mac-only msg) | bandwidth ~4× pixel cut, fps up | S–M | [Screens Compression](https://help.edovia.com/en/screens-5/features/images-quality); [iShareScreen §8.10](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md) |
| 4 | HEVC (then 4:4:4 if VT allows) on helper instead of H.264 4:2:0 | helper | n/a | bandwidth ↓, text sharpness ↑ | M | [Apple High Perf](https://support.apple.com/guide/remote-desktop/use-high-performance-screen-sharing-apdf8e09f5a9/mac); [Parsec HEVC](https://support.parsec.app/hc/en-us/articles/32381568346644-Hardware-and-Software-Compatibility) |
| 5 | Cellular / Low Power / background policy: `NWPath.isExpensive`/`isConstrained`, `ProcessInfo.isLowPowerModeEnabled`, pause helper on background (PiP stays watch-only) | client | yes (client-only) | power, cellular cost, no fps gain on Wi-Fi | S | [NWPath](https://useyourloaf.com/blog/network-path-monitoring/); [Low Power Mode](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LowPowerMode.html) |
| 6 | Local cursor (RFB Cursor / Apple `0x450`) so pointer motion is not a full-frame ZRLE | VNC | **yes** for `0x450` if Apple auth path; unknown for RFC Cursor vs 3rd-party VNC password | perceived latency, some bandwidth | M | [rfbproto Cursor](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst); [iShareScreen §8.3](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md) |
| 7 | Apple still-image codecs `0x3e8/0x3e9/0x3ea/0x3f3` (“Adaptive Quality”) | VNC | **yes**, Mac-only | fps/bandwidth vs ZRLE; still not 60 fps | L | [iShareScreen §8.9](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md); [Screens Adaptive Quality](https://help.edovia.com/en/screens-5/features/images-quality) |
| 8 | Apple `AutoFrameBufferUpdate` `0x09` (server-push) | VNC | **yes**, Apple auth/record-layer | latency vs request/response (depth 3 already near-optimal) | M | [iShareScreen §8.11](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md) |
| 9 | UDP/SRTP or Network.framework QUIC for helper media (TCP stays for control) | helper | n/a | HOL-blocking, loss recovery | L | [Parsec BUD](https://parsec.app/technology); [Apple QUIC WWDC21](https://developer.apple.com/videos/play/wwdc2021/10094/); datagram caveats [DitchOoM #173](https://github.com/DitchOoM/socket/issues/173) |
| 10 | FEC (Sunshine-style Reed-Solomon ~20%) + IDR-on-loss | helper | n/a | lossy tailnet/cellular | M | [Sunshine `fec_percentage`](https://docs.lizardbyte.dev/projects/sunshine/master/md_docs_2configuration.html); [Sunshine #3323](https://github.com/LizardByte/Sunshine/issues/3323) |
| 11 | VT Long-Term Reference (`EnableLTR`) instead of IDR-on-every-nack | helper | n/a | recovery size vs keyframe | M | [WWDC21 10158 LTR](https://developer.apple.com/videos/play/wwdc2021/10158/) |
| 12 | Tight + JPEG QualityLevel for **non-Apple** servers (TigerVNC / x11vnc / TurboVNC) | VNC | **no** | fps/bandwidth on those hosts | M | [rfbproto Tight](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst) |
| 13 | Advertise CopyRect / CompressLevel | VNC | unknown (Apple); yes Tiger/Ultra | scroll/window-move bandwidth | S | [rfbproto CopyRect](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst) |
| 14 | Host `net.inet.tcp.delayed_ack=0` note (not a product lever) | host | yes (anecdotal) | VNC TCP latency | S (docs only) | [remote.it thread](https://forum.remote.it/t/settings-necessary-to-make-vnc-client-to-macos-screen-sharing-usable/842) |
| 15 | Implement Apple High-Performance HEVC/UDP (iShareScreen-class) | VNC/Apple | **yes** unofficial | 30–60 fps, 4:4:4 | **XL** + legal | [Apple HP](https://support.apple.com/guide/remote-desktop/use-high-performance-screen-sharing-apdf8e09f5a9/mac); [iShareScreen](https://github.com/renegadelink/iShareScreen) |
| 16 | RFB Open H.264 (encoding 50) | VNC | **no** (Apple) | only LibVNC-class servers | L | [rfbproto Open H.264](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst) |
| 17 | TurboVNC lossless-refresh / JPEG subsample | VNC | **no** | Tiger/Turbo only | M | [TurboVNC features](https://turbovnc.org/About/Features) |
| 18 | AV1 screen-content coding | helper | n/a | bitrate for UI | XL (no VT SCC API) | [WebRTC AV1 SCC](https://webrtchacks.com/the-hidden-av1-gift-in-google-meet/) |
| 19 | 8-bit colormap `SetPixelFormat` | VNC | historically **no**/broken | — | skip | [Apple Discussions](https://discussions.apple.com/thread/2729410) |
| 20 | Fence + RFB CU | VNC | **no** on Apple | TigerVNC WAN | S advertise / ignore | [IANA -312/-313](https://www.iana.org/assignments/rfb/rfb.xhtml) |

**Read of the ranking:** helper video (1–2, 4, 9–11) is the fps-parity path; the only *cheap Apple-VNC* leftover that commercial clients actually use is **ScaleFactor 0.5** (rank 3) plus optional Apple codecs (7–8). Implementing High Performance as a third-party VNC client is a product fork, not a tweak.

---

## 3. Per-question findings

### Q1 — VNC/RFB client-side levers

Canonical registry: [rfbproto.rst](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst), [IANA RFB](https://www.iana.org/assignments/rfb/rfb.xhtml).

| Lever | Server coop? | Apple SS | TigerVNC | x11vnc | RealVNC | UltraVNC | noVNC/websockify |
|-------|--------------|----------|----------|--------|---------|----------|------------------|
| Encoding order (Tight/ZRLE/Hextile/Raw) | yes (server picks from client list) | ZRLE (3rd-party); Apple codecs if advertised | Tight+JPEG, ZRLE | Tight, ZRLE, CopyRect | ZRLE, Tight (enterprise) | Tight, Ultra, CopyRect | Tight/TightPNG via websockify |
| JPEG QualityLevel (−23…−32) | Tight servers only | no | yes | yes | some | yes | yes (if Tight) |
| CompressLevel (−247…−256) | Tight/zlib servers | no | yes | yes | some | yes | yes |
| JPEG fine-grained / chroma subsample | TurboVNC | no | Turbo fork | no | no | no | Turbo if used |
| CopyRect | server emits | unknown (not in Apple still-image list) | yes (regression history [Tiger #908](https://github.com/TigerVNC/tigervnc/issues/908)) | yes | yes | yes | yes |
| Cursor / XCursor / AlphaCursor (−239/−240/−314) | server | Apple uses **`0x450`**, not RFC AlphaCursor | yes | yes | yes | yes | yes |
| Fence (−312) + CU (−313) | TigerVNC-family | **no** RFB CU; proprietary `0x09` | yes | CU on some builds | no | no | CU if server supports |
| SetDesktopSize / ExtendedDesktopSize | virtual-desktop servers | **no**; Apple `0x1d` + ScaleFactor | yes | RandR | limited | limited | yes (noVNC+Tiger) |
| Open H.264 (50) | rare | no | no | no | no | no | no |
| Tight without zlib (−317) | Tight | no | some | some | no | no | no |
| TurboVNC lossless refresh | TurboVNC | no | no | no | no | no | no |
| Apple `ScaleFactor` `0x08` | Apple daemon | **yes** (`scale < 1` → downscale) | no | no | no | no | no |
| Apple still-image `0x3e8–0x3f3` | Apple | **yes** | no | no | no | no | no |
| Apple Adaptive HEVC `0x3f2` + `0x1c` | Apple HP | **yes** (HP session) | no | no | no | no | no |

**Mechanics that still matter for Naru’s VNC fallback**

- RFB is client-pull. CU/Fence exist to hide RTT; Naru already pipelines depth 3. Extra CU advertising is free and harmless (server ignores unknown encodings) — [rfbproto §5](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst).
- Tight JPEG is the only widely deployed *lossy* RFB path. QualityLevel is a **hint**; without it, Tight must not use JPEG.
- CopyRect is the classic scroll/window-move win. Worth advertising; do not expect Apple to emit it.
- Local cursor is the other classic WAN win (cursor motion stops being framebuffer damage). Apple’s native path uses cached STORE/SELECT `0x450`, not RFC Cursor.
- Server-side downscale in standard RFB is `SetDesktopSize` (virtual X) or client-side scale. **Apple’s equivalent is `ScaleFactor` 0.5**, which Screens documents as “Compression.” Screens cannot change Mac display resolution through Screen Sharing ([same page](https://help.edovia.com/en/screens-5/features/images-quality)).
- Newer (2023–2026) RFB: Open H.264 encoding 50 in rfbproto; Apple High-Performance reverse-eng (2026). No new Tight generation.

### Q2 — Apple Screen Sharing / commercial Mac VNC clients

**What Screens 5 actually does (documented, not reverse-eng):**

- **Adaptive Quality** — “progressive JPEG-like multi-pass,” **Mac only**. That is the Apple still-image ladder (`0x3e8` 4-bit → `0x3e9` 8-bit YCoCg → `0x3ea` RGB565 zlib → `0x3f3` DCT tiles), not Tight. [Edovia](https://help.edovia.com/en/screens-5/features/images-quality); codec table [iShareScreen §8.9.2](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md).
- **Compression (Display Scaling)** — client sends a request for a **50% scaled desktop**. Example: 2560×1440 → 1280×720. Matches `ScaleFactor` `0x08` with `f64` scale 0.5 (`HandleSetServerScalingMessage`, scale `< 1.0` sets downscale). Same Edovia page + iShareScreen §8.10.
- Tight quality 4/9 is used **only against TightVNC on Windows**, not against Mac.

**Jump Desktop**

- VNC mode: ZRLE/Tight/CopyRect/Hextile; **8- and 16-bit color** to cut bandwidth; “OS X Screen Sharing support.” [Jump App Store / Spiceworks listing](https://community.spiceworks.com/t/jump-desktop-rdp-vnc/995901). Tight is unused vs Apple.
- **Fluid** is a separate host-agent protocol, 60 fps, ~1/10 VNC bandwidth — same structural answer as NaruHelper, not a VNC trick. [Jump Fluid](https://support.jumpdesktop.com/hc/en-us/articles/216423983-General-Fluid-Remote-Desktop).

**Royal TSX**

- Ships **three** VNC plugins. The Apple Screen Sharing plugin advertises “adaptive and full quality” because it **is** Apple’s client. The Chicken/RoyalVNC plugins are ordinary VNC (JPEG + CopyRect). [Royal TSX features](https://www.royalapps.com/ts/mac/features-all).

**Pixel formats**

- Third-party RFB `SetPixelFormat` RGB565 is the documented opt-in Naru already has. Apple’s *own* “High Quality” still-image codec `0x3ea` is internally RGB 5-6-5 + zlib. 8-bit colormap against Apple has a long history of “full colors only / weird colours” ([Discussions](https://discussions.apple.com/thread/2729410)). Prefer Apple `0x3e8`/`0x3e9` over colormap if you implement Apple codecs. No public confirmation that Apple honors 8-bit colormap from a 3rd-party VNC-password client.

**ARD codecs 16/17 vs 1100–1105**

- See premise B. Usable third-party implementations of Apple still-image + HP HEVC: iShareScreen (AGPL, 2026). Whether they “beat ZRLE”: yes on motion (HEVC 60 fps / DCT tiles); still-image path is the Screens Adaptive Quality feel, not 60 fps. Native HP is the one that beats ZRLE structurally.

**macOS settings**

- No supported `AppleVNCServer` pref that turns Tight or CU on for 3rd-party clients (no public source found).
- Anecdote, host-side only: `sudo sysctl net.inet.tcp.delayed_ack=0` made Windows→Mac VNC “usable” but not native. [remote.it / StackExchange chain](https://forum.remote.it/t/settings-necessary-to-make-vnc-client-to-macos-screen-sharing-usable/842). Do not ship as a required host tweak; mention in a helper/onboarding note at most.
- High Performance: both Macs Apple silicon, macOS 14+, UDP 5900–5902, ~75 Mbps/4K rec., one session, virtual display up to 4K. [Apple](https://support.apple.com/guide/remote-desktop/use-high-performance-screen-sharing-apdf8e09f5a9/mac).

### Q3 — Helper video path (Mac→iPhone, 1 viewer, tailnet)

**(a) VideoToolbox low-latency**

From [WWDC21 10158](https://developer.apple.com/videos/play/wwdc2021/10158/) (primary):

| Property | Role |
|----------|------|
| `kVTVideoEncoderSpecification_EnableLowLatencyRateControl` | encoder spec at session create; one-in/one-out, faster RC; **announced H.264** |
| `kVTCompressionPropertyKey_RealTime` | realtime hint (also in Sunshine `vt_realtime`) |
| no frame reordering / `MaxFrameDelayCount = 0` | kill B-frames / GOP delay |
| `AverageBitRate` | target |
| `MaxAllowedFrameQP` (1–51) | floor on quality; encoder drops frames rather than blur — **explicitly recommended for screen content on a poor network** |
| Constrained Baseline / Constrained High | interoperability |
| `BaseLayerFrameRateFraction` + `BaseLayerBitRateFraction` | temporal SVC (0.5 fps / ~0.6 bitrate on base). **One-viewer Naru: skip unless you want an easy 30 fps “poor network” layer** |
| `EnableLTR` + `RequireLTRAcknowledgementToken` + `AcknowledgedLTRTokens` + `ForceLTRRefresh` | recovery with predicted LTR-P instead of IDR |

Also set `kVTCompressionPropertyKey_AllowFrameReordering = false`. `PrioritizeEncodingSpeedOverQuality` appears in later VT headers; no WWDC citation for screen share — treat as optional A/B, not a contract.

Sunshine macOS encoder exposes `vt_realtime`, `vt_coder` (cabac/cavlc), `vt_software` ([Sunshine config](https://docs.lizardbyte.dev/projects/sunshine/master/md_docs_2configuration.html)).

**(b) ABR / congestion (1-viewer LAN/VPN)**

Industry pattern is **one live encode, bitrate is the lever**, not HLS ladders:

- **Parsec BUD**: UDP + custom CC, no video buffer; on loss **cut encoder bitrate**; host `encoder_bitrate` cap; `network_cg_level` sensitive/relaxed. Overlay shows current vs max bitrate and congestion events. [Parsec protocol post](https://parsec.app/blog/a-networking-protocol-built-for-the-lowest-latency-interactive-game-streaming-1fd5a03a6007); [advanced opts](https://support.parsec.app/hc/en-us/articles/32381443626516-All-Advanced-Configuration-Options).
- **Sunshine/Moonlight**: client-chosen bitrate; host `max_bitrate`, `minimum_fps_target`, `fec_percentage` default 20 (Reed-Solomon per frame). Recovery = **IDR on frame loss**, not intra-refresh ([Sunshine #3323 closed: they want a full IDR, not intra slices](https://github.com/LizardByte/Sunshine/issues/3323)). Moonlight still has no shipping GCC-style ABR ([moonlight-qt #802](https://github.com/moonlight-stream/moonlight-qt/issues/802)).
- **Chrome Remote Desktop**: WebRTC (VP8→VP9/AV1/H.264 HW) + GCC/TWCC. Screen share in Meet uses `contentHint=detail` and AV1 SCC when available ([WebRTChacks](https://webrtchacks.com/the-hidden-av1-gift-in-google-meet/)). Heavy stack for a 1-viewer tailnet.
- **RustDesk**: `enable-abr=Y` default; HW H.264/H.265 + VP8/VP9/AV1; `custom-fps` 5–120. [docs](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/).

Practical Naru ABR (TCP first): measure send-queue / ACK RTT / decode-stall; multiplicative decrease on stall, additive increase toward a cap; on cellular start at a lower cap; drop FPS (30→15) before QP blows past `MaxAllowedFrameQP`.

**(c) Transport**

| | TCP (current) | Network.framework QUIC | WebRTC |
|--|---------------|------------------------|--------|
| HOL | yes — one lost packet stalls GOP | streams avoid HOL; **datagrams on Apple are still rough** ([DitchOoM #173](https://github.com/DitchOoM/socket/issues/173): datagrams vs inbound streams) | UDP + GCC, mature |
| iOS 17–26 | sockets / NWConnection TCP | QUIC streams since iOS 15 ([WWDC21 10094](https://developer.apple.com/videos/play/wwdc2021/10094/)); Swift concurrency NW in iOS 26 ([WWDC25 250](https://developer.apple.com/videos/play/wwdc2025/250/)) | extra ICE/DTLS |
| Tailscale | TCP-over-WireGuard = double CC; fine on direct LAN | UDP/QUIC maps naturally onto WG UDP; Tailscale invested in UDP GSO ([Tailscale QUIC blog](https://tailscale.com/blog/quic-udp-throughput)) | same |
| Auth | already HMAC TCP | must re-bind pairing | DTLS |
| Verdict | **keep TCP until helper is visual-primary and ABR exists** | next transport if HOL shows up on lossy cellular | overkill for 1-viewer private net |

Apple HP and Parsec both chose **UDP + DTLS/SRTP**, not TCP, for the media plane.

**(d) Keyframe / recovery**

- Default: IDR on stall (`requestKeyframe` — already on Naru’s backlog). Matches Sunshine.
- Better on poor nets: **LTR** (WWDC21) so refresh is an LTR-P, not a large IDR.
- Intra-refresh: NVENC has it; Sunshine declined it. **No public VideoToolbox intra-refresh property found.**
- Periodic IDR (1–2 s) as a safety heartbeat even on TCP.

**(e) HEVC vs H.264 vs SCC**

- HEVC ~50% bitrate at similar quality when both ends HW-decode (iPhone 15 class does). Parsec documents this. Apple HP uses HEVC RExt **4:4:4** specifically so text stays sharp ([Apple](https://support.apple.com/guide/remote-desktop/use-high-performance-screen-sharing-apdf8e09f5a9/mac)).
- **VideoToolbox SCC (HEVC screen-content / IBC/palette): no public API found.** AV1 SCC lives in libaom/WebRTC, not VT. For Naru, “SCC” ≈ HEVC + low `MaxAllowedFrameQP` + 4:4:4 if VT exposes it + don’t chroma-subsample UI.
- WWDC21 low-latency mode ≠ HEVC. Encode HEVC with `RealTime` + no reordering; measure whether `EnableLowLatencyRateControl` is accepted.

### Q4 — Cellular / power-aware client behavior

Apple APIs (all iOS 17+):

- `NWPath.isExpensive` — cellular or personal hotspot. `isConstrained` — Low Data Mode. Simulator always false. [Use Your Loaf](https://useyourloaf.com/blog/network-path-monitoring/).
- `ProcessInfo.processInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`. Apple’s energy guide: drop frame rates, stop extra work. [Energy Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LowPowerMode.html). Low Power Mode also kills background refresh ([Apple Support](https://support.apple.com/en-us/101604)).
- Screens: Adaptive Quality / Compression can be “always / only when connecting remotely / never” — a product pattern for WAN vs LAN ([Edovia](https://help.edovia.com/en/screens-5/features/images-quality)).
- Jump VNC: explicit 8/16-bit color modes for bandwidth.
- RustDesk Android: software-encode half-scale above 1200px; `keep-screen-on`; ABR on mobile ([RustDesk](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/)).
- PiP Watch is watch-only (constitution) — background should **pause encode** or drop to a glance FPS, not become an input surface.

**Applicable to Naru (zoom-scoped + power-saver):**

| Signal | VNC | Helper |
|--------|-----|--------|
| `isExpensive` / `isConstrained` | ScaleFactor 0.5; skip full-frame heartbeat except every Nth; keep zoom-region | bitrate cap, 30 fps, maybe 720p canvas |
| Low Power Mode | already-low ZRLE; don’t fight | 15–30 fps cap, HEVC if cheaper to decode |
| App background | stop FBUR except PiP | `stopStream` (unwired) / keyframe-less pause |
| Zoom-in | already region +64 px, 10th full-frame, 10% threshold | crop/scale encode to visible backing (ScreenCaptureKit filter or VT scale) — **this is the helper analogue of 017** |
| Heartbeat | 10th full-frame is the prefetch; suppress on cellular | periodic IDR only |

### Q5 — 2023–2026 techniques that actually move a phone-first VNC+helper product

1. **Own-encoder + UDP/HW codec is the category.** Jump Fluid, Parsec BUD, Apple HP, Moonlight, RustDesk, CRD — none of them beat Apple ZRLE *as VNC*. NaruHelper is the correct architecture. Why it matters: VNC Track C cannot reach 10 fps product gates against Apple SS.
2. **Apple High-Performance reverse-eng (2026).** iShareScreen shows HEVC 4:4:4 + virtual displays + ScaleFactor + Apple codecs are implementable. Why: a *second* visual primary that needs no NaruHelper install — but it is an unofficial Apple protocol (auth 30/33/35/36, AES-CBC record layer, SRTP). Legal/maintenance cost is the issue, not feasibility.
3. **Virtual display / phone-sized canvas.** Apple HP and Sunshine `dd_resolution_option` resize the *server* framebuffer to the client. Why: a 1179×2556 phone looking at a 5K iMac is the real bandwidth bug; ScaleFactor 0.5 is the cheap Apple-VNC version; helper can capture a scaled IOSurface.
4. **AV1 SCC in WebRTC.** ~25% smaller screen-share frames in Meet. Why: not available in VideoToolbox; do not block the roadmap on it. Revisit if Apple ships VT AV1 screen encode.
5. **FEC + IDR-on-loss, not intra-refresh, for 1:1 streams.** Sunshine’s production choice. Why: TCP hides loss; the day helper goes UDP, copy this, not NVENC intra-refresh.
6. **LTR frames (WWDC21).** Why: helper stall recovery without IDR bitrate spikes — pairs with the unwired `requestKeyframe`.
7. **4:4:4 / “true color” as a quality mode** (Apple HP, Parsec `client_decoder_444`, RustDesk `i444`). Why: terminal/AI-CLI text is Naru’s job; 4:2:0 is the thing that makes fonts crawl.
8. **RustDesk-class ABR + HW codec + UDP hole-punch as a product checklist**, not a protocol to copy. Why: closest OSS analogue of “self-hosted, phone client, private net.”

---

## 4. What I could not determine

| Unknown | Measurement that would settle it |
|---------|----------------------------------|
| Does Apple honor RFC CopyRect / Cursor / RGB565 from a **VNC-password** (non-Apple-auth) client, and does RGB565 change produce-rate vs 32-bit ZRLE? | FakeRFB-style capture against live `screensharingd` with Naru’s current handshake; count encodings in FBUs. RGB565 is shipped — compare content-fps on the same Mac. |
| Does `ScaleFactor` 0.5 work on the **VNC-password** path, or only after Apple auth + record layer? | Send `0x08` after ServerInit on both auth types; see if framebuffer size changes. Screens implies Apple auth. |
| Can a 3rd-party VNC-password client get `0x3e8/0x3ea/0x3f3` by advertising them in `SetEncodings` without Apple auth 33? | Advertise those encodings; if the server never emits them, Apple auth is mandatory (iShareScreen implies yes). |
| HEVC + `EnableLowLatencyRateControl` on macOS 14/15 VideoToolbox | `VTSessionCopySupportedPropertyDictionary` on an HEVC session; then encode 60 fps ScreenCaptureKit and read encode-time vs H.264. |
| VT 4:4:4 / 4:2:2 for HEVC screen | Query encoder pixel-format support; if only NV12, 4:4:4 is Apple-HP-only. |
| QUIC datagrams usable for media on iOS 17–26 without breaking the control stream | Small NWConnectionGroup prototype (known failure mode in [DitchOoM #173](https://github.com/DitchOoM/socket/issues/173)). |
| Tailscale direct-path vs DERP impact on helper TCP HOL | Live `tailscale status` + loss/RTT while scrolling; if DERP-relayed, UDP/QUIC jump in priority. |
| Apple `delayed_ack=0` effect on Naru’s depth-3 ZRLE | One live Mac A/B with HUD networkRead p95 (anecdotal only so far). |
| Intra-refresh in VT | No public key found; confirm via supported-property dump. |
| Whether Screens Adaptive Quality is still-image only or also HP HEVC | Packet capture of Screens 5 ↔ modern Apple silicon (iShareScreen RFC is from native Screen Sharing.app, not Screens). |

---

## Self-verification (research round)

1. **Trap docs:** `PERFORMANCE_PARITY_ANALYSIS.md` (client pipeline healthy; Apple ZRLE ~5.6 fps; helper is the structural answer; Track C leftover listed Tight+JPEG and Screens-style downscale — this round confirms those two, and adds that Screens downscale is `ScaleFactor` 0.08). `AGENTS.md` / constitution: helper optional, iPhone-first, no public-internet-first. Unicode-keysym “solved” is out of scope here. Global memory file missing at the Codex path; skipped.
2. **New mappings:** none implemented. Encoding-number clarification vs spec’s 16/17 / 1100–1105 is in premise B.
3. **Other surfaces:** Naru has one VNC client + one helper; no web/TUI. Compared against Screens, Jump, Royal TSX, Moonlight/Sunshine, Parsec, CRD, RustDesk.
4. **Existing behavior removed:** none (no code).
5. **User-facing copy:** none.
6. **Test assertions:** none.
7. **Spec conflicts:** “ZRLE-only / no CU / no Tight” vs Apple private codecs — reported, did not silently drop either. File whitelist: no writes.
8. **Hot-path cost:** n/a.

**Could not implement:** file writes / progress log (write-block). Did not audit the Naru codebase.

**Deliberately left untouched:** all repo files; no network probes against a Mac; no iShareScreen code copied.

---

DONE-PERFRESEARCH
