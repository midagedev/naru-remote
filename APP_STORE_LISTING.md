# App Store Connect Listing — Naru Remote 1.0

작성일: 2026-06-19 KST. 이 문서는 App Store Connect에 그대로 붙여 넣을
메타데이터 초안이다. 문자수 제한은 Apple 기준(2026): 이름 30자, 부제
30자, 프로모션 텍스트 170자, 키워드 100자(쉼표 포함), 설명 4000자.

> 브랜딩 근거: `BRANDING.md`. 제품 특성/보안 경계: `PRODUCT_SPEC.md`,
> `.specify/memory/constitution.md`.

## 1. 기본

| 필드 | 값 |
| --- | --- |
| App Name (30) | `Naru Remote` |
| Subtitle (30) | `Private Network Remote Desktop` |
| Bundle ID | `com.naruremote.app` |
| Primary Category | Productivity |
| Secondary Category | Utilities |
| Age Rating | 4+ |
| Price | (미정 — Free / Free+IAP 검토) |

## 2. Promotional Text (≤170, 심사 없이 수시 교체 가능)

- EN: `Reach your Mac or Linux box over your own private network. Compose multilingual text, then send it cleanly to the remote screen.`
- KO: `사설망 안의 Mac·Linux에 연결하세요. 한글·다국어 문장을 로컬에서 완성해 원격 화면에 정확히 보냅니다.`

## 3. Keywords (≤100자, 쉼표 구분, 공백 최소화)

```
vnc,remote desktop,tailscale,ssh,mac,linux,terminal,private network,magicdns,korean,ime,keyboard
```

(주의: "Tailscale"은 키워드 검색용으로만 사용 — 설명/스크린샷에서 공식
제휴로 오인될 표현 금지. 헌법 §II.)

## 4. Description

### English

```
Naru Remote is a remote desktop built for private networks — your Mac or
Linux machine over Tailscale, a VPN, or your LAN. It is designed around one
thing other VNC viewers get wrong on a phone: getting your text in.

COMPOSE, THEN SEND
Type Korean, Chinese, Japanese, emoji, or long mixed sentences with your
normal keyboard and IME, review it locally, and send the finished text to
the remote screen. No more dropped first characters or broken IME over a
raw key stream.

DIRECT KEYSTROKE MODE
Need raw keys for a terminal or an editor? Switch to Direct mode and use a
purpose-built on-screen keyboard with a special-keys page (Esc, Tab, Ctrl,
arrows, function keys) and sticky modifiers. A clear badge reminds you IME
is off in this mode.

BUILT FOR THE PHONE
Pinch, pan, and zoom-fill so terminal text stays readable. A trackpad mode
with a real on-screen cursor. Diagnostics that tell you exactly where a
connection failed — DNS, TCP, the RFB handshake, authentication, or the
first frame — with a privacy-safe shareable report.

PRIVATE BY DESIGN
Naru Remote prefers your private network. Passwords live in the iOS
Keychain, never in plain profile storage. Diagnostics never export your
screen contents, typed text, or clipboard. Public endpoints are an
explicit, clearly-warned advanced path.

Naru Remote is an independent app and is not affiliated with Tailscale.
```

### 한국어

```
Naru Remote는 사설망을 위한 원격 데스크톱입니다. Tailscale, VPN, 또는
같은 LAN 안의 Mac·Linux에 연결하세요. 다른 VNC 뷰어가 폰에서 놓치는 단
하나, "내가 쓴 글자를 원격에 제대로 넣는 것"에 집중해 설계했습니다.

작성하고, 보내기
한글·중국어·일본어·이모지, 긴 혼합 문장을 평소 키보드와 IME로 입력해
로컬에서 확인한 뒤 완성된 텍스트를 원격 화면에 보냅니다. 첫 글자 누락,
IME 깨짐 없이.

직접 키 입력 모드
터미널·에디터에 raw 키가 필요하면 Direct 모드로 전환하세요. 특수키
페이지(Esc, Tab, Ctrl, 방향키, 펑션키)와 sticky modifier를 갖춘 전용
온스크린 키보드를 씁니다. 이 모드에선 IME가 꺼진다는 배지가 항상
표시됩니다.

폰을 위해 만든 조작
핀치·팬·zoom-fill로 터미널 글자가 읽히게. 실제 커서가 있는 트랙패드
모드. 연결이 어디서 실패했는지(DNS·TCP·RFB 핸드셰이크·인증·첫 프레임)
정확히 알려주고, 민감 정보 없는 진단 리포트를 공유할 수 있습니다.

프라이버시 우선
사설망을 우선합니다. 비밀번호는 iOS 키체인에만 저장되고 프로필에 평문
저장되지 않습니다. 진단은 화면 내용·입력 텍스트·클립보드를 내보내지
않습니다. 공개 엔드포인트는 명확히 경고되는 고급 경로입니다.

Naru Remote는 독립 앱이며 Tailscale과 제휴 관계가 아닙니다.
```

## 5. What's New (1.0)

- EN: `First release. Private-network VNC with local multilingual compose, a Direct keystroke keyboard, trackpad pointer, and privacy-safe connection diagnostics.`
- KO: `첫 출시. 로컬 다국어 작성, Direct 키 입력 키보드, 트랙패드 포인터, 민감정보 없는 연결 진단을 갖춘 사설망 VNC.`

## 6. Screenshot 캡션 (마케팅 프레임용)

기반 캡처: `artifacts/release-audit/` (시안). 6.9"/6.7" iPhone + 13" iPad
세트로 마케팅 프레임 작업 필요.

1. Connections — `Your machines, one tap away`
2. Live session (zoom-fill terminal) — `Read and drive your desktop from the phone`
3. Compose & Send (한글 입력) — `Type in any language. Send it clean.`
4. Direct keyboard (special page) — `Raw keys when the terminal needs them`
5. Diagnostics — `Know exactly why a connection failed`

## 7. Review/메타 노트 (App Review 제출 시)

- **로컬 네트워크 권한**: 사설망 VNC 연결용 (`NSLocalNetworkUsageDescription` 설정됨).
- **Background audio 모드**: PiP Watch(원격 화면 PiP 관찰) 용도.
- **수출 규정**: 표준 암호화만 사용 → `ITSAppUsesNonExemptEncryption=false`.
- **데모 계정/시연**: 심사용으로 접속 가능한 테스트 VNC 호스트 + 비밀번호를
  App Review Notes에 제공 필요(사설망이라 심사자가 자체 접속 불가).
- **개인정보 처리방침 URL**: 필수. 앱은 추적/데이터 수집 안 함
  (`PrivacyInfo.xcprivacy` = no tracking/collection) — 그 사실을 명시한 정책 1장.
```
