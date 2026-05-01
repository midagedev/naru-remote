# Tailnet-native IME-first VNC Viewer 사양서

작성일: 2026-04-29 KST

## 1. 제품 요약

이 제품은 iPhone/iPad용 VNC viewer다. 일반적인 VNC 앱처럼 원격 화면을 보고 마우스와 키보드를 보내는 데서 멈추지 않고, 다음 세 가지를 제품의 중심 기능으로 둔다.

1. Tailscale 환경에서 자연스럽게 장비를 찾고 접속하는 Tailnet-native VNC viewer
2. iOS/iPadOS에서 완성한 다국어 문장과 음성 입력 결과를 원격 컴퓨터에 정확히 주입하는 IME-first text bridge
3. 사람이 보는 원격 세션을 AI agent에게 안전하게 넘기거나 함께 조작할 수 있는 agent-ready remote desktop

확장 차별점으로는 iPhone/iPad의 사진, 스크린샷, 파일 이미지를 원격 앱에 자연스럽게 붙여넣는 Image Paste Bridge를 둔다. 이 기능은 텍스트 입력과 같은 철학을 따른다. 사용자는 iOS에서 이미지를 고르고, 앱은 대상 환경에 맞는 가장 안정적인 주입 방식을 선택한다.

Naru Remote는 iPhone을 일차 설계 대상으로 둔다(constitution §VI). iPad는 같은 워크플로우가 더 큰 화면, 외장 키보드, Stage Manager로 자연스럽게 확장되는 형태로 지원하되, 디자인 압력은 작은 화면에서 위로 흐른다. iPhone에서의 사용은 짧은 개입에 그치지 않고, 사용자가 원격 머신의 진짜 터미널 환경(Ghostty/Wezterm/Alacritty 등)과 AI 코딩 CLI(Codex, Claude Code, aider 및 후속 도구) 세션을 폰에서 30분~수 시간 이어가는 sustained workspace transport 시나리오를 정면 use case로 둔다. 이 시나리오는 raw key 스트리밍으로는 한국어/일본어/중국어 IME가 깨지기 때문에 Compose & Send가 핵심 입력 경로가 되며, AI CLI에 한국어 프롬프트를 합성해 보내는 흐름도 같은 경로 위에서 이루어진다. iOS SSH 클라이언트의 자체 터미널 에뮬레이터로는 모던 AI CLI의 풍부한 TUI를 충실히 재현하기 어렵다는 한계가 이 포지셔닝의 시장 근거다.

핵심 제품 문장은 다음과 같다.

> iPhone에서 합성하고, Tailnet 안의 컴퓨터에 정확히 보낸다. 데스크톱 터미널과 AI 에이전트를 주머니에 — 한국어가 깨지지 않은 채로.

## 2. 배경과 문제

기존 모바일 VNC viewer의 입력 방식은 대부분 키 이벤트 중심이다. 이 구조는 영어 물리 키보드 입력에는 충분하지만, 한글, 일본어, 중국어, 악센트 문자, 이모지, 복합 기호, 받아쓰기처럼 iOS에서 먼저 조합되어야 하는 입력에는 취약하다.

대표 문제는 다음과 같다.

- 원격 컴퓨터의 키보드 레이아웃과 iOS 키보드 레이아웃이 다르면 문자가 틀어진다.
- 한글/일본어/중국어 IME 조합 과정이 키 이벤트로는 안정적으로 전달되지 않는다.
- 모바일 받아쓰기 결과를 원격 앱에 자연스럽게 넣기 어렵다.
- iPhone/iPad의 스크린샷, 사진, 이미지 파일을 원격 브라우저, 메신저, 문서, 이슈 트래커에 바로 붙여넣기 어렵다.
- 원격 클립보드 붙여넣기를 임시방편으로 쓰면 사용자 클립보드를 망가뜨리거나, 붙여넣기 금지 필드에서 실패한다.
- Tailscale을 이미 쓰는 개발자/운영자/에이전트 사용자에게도 기존 VNC viewer의 접속 흐름은 여전히 IP/포트 중심이다.

이 제품은 "원격 키보드"를 흉내 내기보다, iOS를 입력 컴포저로 쓰고 최종 텍스트를 원격 시스템에 전달하는 방향을 기본값으로 삼는다.

## 3. 목표 사용자

### 3.1 1차 사용자

- Mac, Windows, Linux 장비를 Tailscale로 묶어 쓰는 개발자
- iPhone에서 외출 중·이동 중에 원격 머신의 터미널 환경(Ghostty/Wezterm 등)과 AI 코딩 CLI(Codex, Claude Code, aider) 세션을 30분~수 시간 단위로 이어 작업하는 사용자 (constitution §VI 1차 페르소나)
- iPad에서 서버, 워크스테이션, 홈랩, 사무실 PC에 자주 접속하는 사용자
- 한글과 영어를 섞어 쓰거나, 일본어/중국어 등 IME 입력이 많은 사용자
- 원격 터미널, 브라우저, IDE, 문서 편집기, AI CLI 프롬프트 입력란에 긴 문장이나 다국어 프롬프트를 넣는 사용자

### 3.2 2차 사용자

- 원격 화면을 보며 AI agent에게 일부 작업을 맡기고 싶은 사용자
- 외부 인터넷에 원격 데스크톱 포트를 열지 않고 Tailnet 안에서만 쓰고 싶은 개인/소규모 팀
- 모바일에서 음성으로 원격 명령, 메일, 로그 검색어, 코드 코멘트를 입력하고 싶은 사용자

## 4. 제품 원칙

1. Tailscale-first, public internet optional
   - 기본 접속 흐름은 Tailnet 장비 탐색과 MagicDNS 호스트명 사용을 우선한다.
   - public IP 직접 접속은 지원하되 주된 UX로 두지 않는다.

2. Text is composed locally
   - 다국어 입력, 받아쓰기, 손글씨 입력은 iOS/iPadOS에서 먼저 완성한다.
   - 원격에는 최종 문자열을 전달한다.

3. Clipboard should not be collateral damage
   - 텍스트 주입에 클립보드를 쓰더라도 사용자 경험상 "원격 클립보드가 망가졌다"는 느낌이 없어야 한다.
   - 가능한 경우 클립보드 보존/복원 흐름을 제공한다.

4. Agent actions must be observable and interruptible
   - 에이전트가 원격 화면을 조작할 때 사용자는 보고, 승인하고, 즉시 중단할 수 있어야 한다.

5. Host helper is optional but powerful
   - 순수 VNC만으로 가능한 기능은 기본 제공한다.
   - 더 안정적인 텍스트 주입, 클립보드 복원, agent bridge, 파일 전송은 선택형 host helper로 확장한다.

## 5. 비목표

초기 버전에서는 다음을 목표로 하지 않는다.

- Tailscale VPN 자체를 앱 안에 내장하거나 대체하지 않는다.
- RDP/SSH/NoMachine 등 모든 원격 프로토콜을 한 번에 지원하지 않는다.
- 원격 오디오/마이크 스트리밍 제품으로 포지셔닝하지 않는다.
- VNC server 자체를 제공하지 않는다.
- 원격 파일 관리자나 범용 cloud drive 제품이 되지 않는다.
- AI agent를 앱 안에서 완성형 자동화 제품으로 만들지 않는다. 초기에는 안전한 관찰/입력/제어 인터페이스를 준비하는 데 집중한다.

## 6. 핵심 기능

## 6.0 First Run Onboarding

### 사용자 가치

Naru Remote의 첫 경험은 "원격 화면 앱" 설명보다 "지금 연결을 성공시키기
위한 다음 단계"를 보여줘야 한다. 사용자는 Tailnet/private host, VNC
진단, local Compose, PiP Watch 정책을 한 화면에서 이해하고 바로 다음
행동으로 이동한다.

### 기능

- private target 체크: MagicDNS 또는 private host 프로필 생성 여부
- connection checks 체크: DNS, TCP, VNC handshake, auth, first frame 진단 상태
- compose locally 체크: 원격 세션이 열렸을 때 로컬 입력 경로가 준비됐는지
  표시
- PiP Watch 체크: 첫 frame 이후에만 가능하고, 민감 프로필에서는 비활성화될
  수 있음을 표시
- 첫 실행 체크리스트는 dismiss 가능해야 한다.

### 보안/프라이버시 원칙

- 온보딩은 composed text, credential, clipboard payload, framebuffer pixels를
  표시하거나 저장하지 않는다.
- 진단 실패는 user-safe title만 표시하고 raw detail은 쓰지 않는다.
- public endpoint는 기본 경로가 아니라 advanced/manual 상태로 표시한다.

### MVP 범위

- 앱 셸 상단에 상태 기반 first-run checklist를 표시한다.
- 체크리스트 상태는 현재 snapshot에서 파생하며, 영구 dismiss/persistence는
  settings persistence가 들어간 뒤 확장한다.

## 6.1 Tailnet Connection Hub

### 사용자 가치

사용자는 IP 주소를 기억하지 않고 Tailnet 장비를 선택해 VNC 세션을 열 수 있다.

### 기능

- Tailscale 설치 여부와 VPN 연결 상태 안내
- MagicDNS 호스트명 우선 접속
- Tailnet 장비 목록 불러오기
- 장비별 VNC 포트 후보 확인
- 접속 프로필 저장
- 최근 접속, 즐겨찾기, 태그 기반 필터
- 연결 진단 화면

### 연결 진단 항목

- Tailscale VPN 활성 여부
- MagicDNS 이름 해석 가능 여부
- 대상 host/port TCP 연결 가능 여부
- VNC RFB handshake 가능 여부
- 인증 실패 여부
- 지연 시간과 패킷 손실 추정
- subnet route 또는 exit node 사용 중인지 여부

### MVP 범위

- 수동 host 입력과 MagicDNS host 입력 지원
- 접속 프로필 저장
- 기본 연결 진단

### v1 이후

- Tailscale API 기반 장비 목록 탐색
- OAuth/read-only credential 기반 tailnet inventory
- iOS Shortcuts/App Intents로 "Tailscale 연결 후 VNC 열기" 자동화

## 6.2 VNC Session Viewer

### 기능

- RFB 3.8 호환 VNC viewer
- Tight/ZRLE/Hextile/Raw 등 주요 encoding 지원
- TLS/VeNCrypt 지원 여부 검토
- 화면 확대/축소, pan, pointer mode
- 터치 제스처 기반 left/right/middle click
- 외부 키보드 지원
- modifier key toolbar
- session reconnect
- view-only mode
- connection quality indicator

### iPhone UX (1차 설계 대상; constitution §VI)

- compose bar 우선 UX — sustained 터미널/AI CLI 세션을 폰에서 이어가는 것이 기준 시나리오다
- 화면 조작을 방해하지 않는 compact toolbar
- 한 손 thumb mode
- quick zoom to cursor — 텍스트 위주 framebuffer에서 가독성/정확성을 최우선으로 둔다
- 셀룰러↔Wi-Fi 전환과 백그라운드 복귀 시 끊김 없는 reconnect/세션 지속성
- 외장 키보드는 옵션. 외장 키보드가 없는 상태에서 Compose & Send만으로 모든 기본 입력이 가능해야 한다

### iPad UX (graceful scaling)

- 전체 화면 원격 화면
- 하단 compose bar
- 좌우 edge toolbar
- pointer/trackpad mode 전환
- command palette
- split view 대응
- Stage Manager 대응
- 외장 키보드 + 외부 디스플레이 + 펜은 layered enhancement이며, iPhone 우선순위를 흐리지 않는다

### PiP Watch Mode

PiP Watch Mode는 사용자가 iPhone/iPad에서 다른 일을 하는 동안 원격
데스크톱을 작은 창으로 계속 감시하는 기능이다. 이 기능은 조작용 미니
데스크톱이 아니라 watch-only remote monitor다.

사용자 가치:

- 빌드, 배포, 설치, 장기 테스트, agent 작업 진행 상황을 다른 앱을 쓰면서
  확인한다.
- iPhone에서도 원격 화면을 구석에 띄워 두고 이상 상태나 완료 상태를 즉시
  알아차린다.
- PiP를 탭하면 Naru Remote의 해당 세션으로 돌아와 조작을 이어간다.

기본 원칙:

- PiP 안에서는 입력, 클립보드, Compose & Send, pointer event를 보내지 않는다.
- PiP 시작은 사용자가 명시적으로 선택해야 한다.
- PiP는 제어 가능한 세션이 실제 원격 프레임을 받은 뒤에만 시작할 수 있다.
- PiP에는 원격 화면과 최소 상태 overlay만 표시한다.
- 민감한 프로필에서는 PiP 사용을 끌 수 있어야 한다.
- diagnostic export와 logs에는 PiP 프레임이나 screenshots를 저장하지 않는다.

기술 방향:

- VNC framebuffer를 watch-only video frame stream으로 변환한다.
- iOS/iPadOS에서는 AVKit Picture in Picture 경계를 검증한다.
- 메인 viewport와 PiP는 같은 locally composed framebuffer pipeline을 공유한다.
  별도 디코더를 두지 않고 dirty rectangle, changed pixel count, change
  activity를 기준으로 렌더링 비용을 조절한다.
- 변화가 적은 화면은 낮은 FPS로 유지하고, 변화가 많은 화면만 일시적으로
  프레임 전송 빈도를 올린다.
- 첫 구현은 one active controllable session + one PiP watch session을 목표로
  한다.
- 현재 foundation 구현은 profile-level opt-out, frame-gated availability,
  watch-only state, stale-frame policy, app-level PiP Watch start/stop lifecycle,
  frame change activity propagation, and AVSampleBufferDisplayLayer renderer
  boundary까지다. 앱 레이어는 원격 framebuffer를 `CVPixelBuffer` /
  `CMSampleBuffer`로 변환하고 iOS `AVPictureInPictureController` content
  source를 만들 수 있다. iOS 앱은 이 controller wrapper를 app model에
  주입하며, app model은 지원 기기에서 PiP start/stop 및 초기/후속 frame
  enqueue를 호출한다. 실제 시스템 PiP window 지원은 물리 iPhone/iPad 동작과
  background-mode 정책 검증 이후에만 완료로 표기한다.

### Multi-session / Session Parking

한 번에 여러 접속을 살려두는 기능은 Naru Remote의 강한 후속 차별점이다.
다만 MVP에서는 하나의 controllable session과 하나의 PiP watch boundary를
먼저 안정화한다. 멀티 세션은 별도 스펙에서 다음 단위로 설계한다.

- session parking: 연결은 유지하되 현재 조작 대상에서는 내리는 상태
- multi-view: iPad에서 2개 이상 세션을 격자/분할 보기로 감시
- focus handoff: Compose & Send와 clipboard 대상이 어느 세션인지 명확히 표시
- resource policy: 배터리, 네트워크, 백그라운드 제한에 맞춘 FPS/해상도 조절
- PiP interaction: 여러 세션 중 하나만 PiP로 승격하거나 rotating watch로 전환

현재 구현 상태:

- 앱 셸은 단일 선택 프로필과 단일 세션 모델이다.
- Add Profile, profile selection, Checks, Connect, Send는 앱 모델에 연결됐다.
- 앱 시작은 hard-coded demo profile이 아니라 app-local saved profile store를
  읽는다.
- Connect는 RFB 3.8 no-auth first-frame boundary까지 수행한다.
- outgoing UTF-8 `ClientCutText` and paste key events는 fake RFB server에서
  검증됐다.
- 32-bit true-color raw framebuffer rectangle을 RGBA pixel buffer로 디코딩하는
  foundation이 들어갔다.
- RFB client는 no-auth session을 유지한 채 같은 연결에서 raw framebuffer
  update를 반복 요청/수신/디코딩할 수 있고, fake RFB server에서 검증됐다.
- RFB client는 password가 공급되면 `VNC Authentication` security type 2를
  협상하고 challenge-response를 생성할 수 있으며, missing/rejected password
  failure를 stale session 없이 보고한다.
- Profile Editor는 optional VNC password를 받아 credential store에 저장하고,
  profile JSON에는 plaintext 대신 `credentialRef`만 남긴다. Connect는 이
  reference를 해석해 authenticated streaming connection에 전달한다.
- `RFBFramePump`는 첫 요청 full frame, 이후 incremental frame 요청을 수행하는
  cancellable loop boundary를 제공한다.
- incremental raw update는 이전 framebuffer 위에 합성되고, dirty rectangle,
  changed pixel count, change activity가 frame pump를 통해 유지된다.
- 앱 모델은 streaming-capable connector에서 long-lived frame task를 실행하고,
  이후 frame이 도착할 때마다 `latestFramebuffer`를 갱신한다.
- profile 변경 시 stale frame task를 취소하고 framebuffer 상태를 정리한다.
- PiP Watch action은 frame-bearing session에서 core watch lifecycle을 시작,
  stale refresh, stop 할 수 있다.
- app-layer PiP renderer boundary는 framebuffer를 BGRA pixel buffer와 sample
  buffer로 바꿔 `AVSampleBufferDisplayLayer`에 공급한다.
- session viewport는 sampled SwiftUI preview를 표시할 수 있다.
- full-rate SwiftUI/Metal rendering, clipboard restore/receive, broader
  pointer/keyboard events, real-device credential verification, system PiP
  window, and multi-session coordinator는 아직 구현 대상이다.

## 6.3 Compose & Send

### 위치

Compose & Send는 두 가지 원격 입력 모드 중 **기본 모드**다. 다른 모드는 §6.3.6 Direct
Keystroke Streaming Mode이며, 사용자가 Remote Input Dock의 토글로 전환한다.
Compose & Send가 기본인 이유는 다국어 텍스트, IME, 받아쓰기, 손글씨, 자동완성이
로컬에서 완성된 뒤 원격으로 한 번에 들어가는 흐름이 깨지지 않기 때문이다. 동일한
이중 모드 구조는 Chrome Remote Desktop Android가 채택한 패턴이며 (기본 = 텍스트 박스
+ Send, 토글 = "On-screen input"으로 직접 키스트로크 전송) Naru Remote도 같은 결론을
따른다.

### 사용자 가치

원격 컴퓨터의 키보드 레이아웃과 IME 상태에 상관없이, iOS/iPadOS에서 완성한 문장을 원격 앱에 넣는다.

### 기본 흐름

1. 사용자가 원격 화면에서 입력 위치를 클릭한다.
2. 하단 compose bar에 텍스트를 입력한다.
3. iOS IME, 받아쓰기, 손글씨, 외부 키보드 조합이 로컬에서 완료된다.
4. 사용자가 Send를 누른다.
5. 앱은 가장 안정적인 text injection adapter를 선택한다.
6. 원격 앱에는 완성된 문자열이 입력된다.

### 전송 모드

#### A. Clipboard Paste Mode

가장 넓은 호환성을 가진 기본 모드다.

흐름:

1. 원격 클립보드에 UTF-8 텍스트를 설정한다.
2. 대상 OS에 맞는 paste shortcut을 보낸다.
3. 가능한 경우 원격 클립보드를 이전 값으로 복원한다.

OS별 paste shortcut:

- macOS: Command+V
- Windows/Linux: Control+V
- terminal fallback: Shift+Insert 또는 bracketed paste 검토

주의:

- 레거시 VNC ClientCutText는 인코딩과 길이 제한 이슈가 있을 수 있다.
- Extended Clipboard/UTF-8 지원 여부를 handshake 또는 feature probe로 확인한다.
- 일부 password field, secure input field, elevated window에서는 paste가 실패할 수 있다.

#### B. Keystroke Fallback Mode

서버가 클립보드 입력을 지원하지 않거나 붙여넣기가 불가능한 경우 사용한다.

원칙:

- ASCII와 기본 control key 중심으로 제한한다.
- 다국어 텍스트는 품질 보장을 하지 않는다.
- UI에서 fallback임을 명확히 표시한다.

#### C. Host Helper Text Insert Mode

선택형 host helper가 설치된 경우 사용한다.

가능한 기능:

- OS 네이티브 text insertion
- 클립보드 백업/복원
- active app/window 감지
- secure input 여부 감지
- file drop
- agent bridge

OS별 구현 후보:

- macOS: Accessibility permission, NSPasteboard, CGEvent
- Windows: Clipboard API, SendInput, UI Automation 보조
- Linux X11: xdotool/xclip/xsel 계열
- Linux Wayland: desktop portal 또는 compositor별 제한 검토

### Compose Bar 기능

- 단일 줄/여러 줄 전환
- Send
- Send and Enter
- Paste only
- Clear
- Undo last send
- 최근 전송 기록
- snippets/macros
- 대상 OS별 줄바꿈 변환
- terminal-safe paste 옵션
- 민감 텍스트 표시 숨김

### Snippets

초기 내장 snippet 예시:

- 이메일 주소
- 자주 쓰는 shell command
- Git command
- 로그 검색어
- Markdown code block
- SSH config fragment
- support reply template

사용자 snippet에는 다음 필드를 둔다.

- title
- body
- target OS preference
- send behavior: insert only, insert and enter, insert and tab
- sensitive flag

### 6.3.6 Direct Keystroke Streaming Mode

#### 위치

Compose & Send와 **나란한 두 번째 입력 모드**다. §6.3 전송 모드 안의
"B. Keystroke Fallback Mode"가 Compose & Send 안의 send-time fallback인 것과 달리,
이 모드는 Remote Input Dock 레벨에서 사용자가 명시적으로 켜는 토글 모드다. 켜지면
compose 단계가 사라지고, **앱이 직접 그리는 커스텀 소프트 키보드**(Chrome Remote Desktop
Android 패턴 — QWERTY 페이지 + 특수키 페이지 두 장, 화면 하단 도킹)의 각 탭이 즉시 RFB
KeyEvent로 원격에 스트리밍된다. iOS 시스템 키보드는 이 모드에서 사용하지 않는다 — IME
조합·자동완성·예측 입력이 raw 키스트로크 송신을 깨뜨리고, Tab/Esc/Ctrl/방향키 같은
터미널 필수 키가 없으며, 같은 키보드에서 IME 조합과 raw 송신이 섞이면 사용자가 어느
모드에 있는지 식별할 수 없기 때문이다. 다른 키보드 외형 자체가 모드 표시기로 작동한다.

이 모드는 헌법 원칙 I이 명시한 *"Remote key events MAY exist for compatibility, but
they MUST NOT be the primary design for multilingual text entry"* 의 "MAY" 영역에
해당한다. 따라서 다국어 입력의 1차 경로가 아니며, 기본값으로 켜지지 않는다.

#### 사용자 가치

- 원격 터미널에서 Ctrl+C, Ctrl+R, Tab 자동완성, 라이브 셸 입력처럼 키 단위 의미가
  있는 입력을 그대로 전달한다.
- 게임/실시간 단축키 조작처럼 compose 후 한 번에 보내는 모델이 맞지 않는 사용 사례를
  지원한다.
- 원격 OS의 IME를 그대로 쓰고 싶은 사용자에게 직접 경로를 제공한다.

#### 흐름

1. 사용자가 Remote Input Dock 상단의 segmented mode picker에서
   "Compose" / "Direct" 두 세그먼트 중 "Direct"를 선택한다(shipped UI 라벨은
   짧게 "Direct"; "Direct Keystroke"가 아니다 — 도크의 좁은 폭에 맞춘
   결정이다).
2. iOS 시스템 키보드가 내려가고 화면 하단에 Naru의 커스텀 소프트 키보드(QWERTY 페이지)가
   올라오며, 도크 헤더와 세션 HUD 두 곳에 "Direct mode" 배지가 동시에
   표시된다(도크 배지는 키보드와 함께, HUD 배지는 키보드를 접거나 다른
   시트로 전환해도 유지된다 — FR-010).
3. 첫 진입 시(세션당 1회) `confirmationDialog`로 경고가 표시된다. 본문은 영어로
   "Keystrokes go straight to the remote computer. IME input (Korean,
   Chinese, Japanese, emoji) will not work in this mode. Switch back to
   Compose & Send for multilingual text." 이며 단일 액션 버튼 "Got it"로
   닫는다(도크 chrome의 다른 영문 라벨 — Compose / Direct / Send — 과 톤을
   맞춘 결과로 영어로 출시; 한국어 로컬라이제이션은 Ship Readiness P2의
   `Localizable.strings` 작업에서 다룬다).
4. 커스텀 키보드의 각 탭이 즉시 RFB KeyEvent로 송신된다(키-다운/키-업 한 쌍). 사용자가
   특수키 페이지 토글을 누르면 Tab/Esc/Ctrl/Alt/Cmd/Shift/방향키/F1-F12/Home/End/PgUp/PgDn/
   Insert/Delete를 포함한 페이지로 전환된다(전환 자체는 KeyEvent를 발생시키지 않는다).
5. 모디파이어(Ctrl/Shift/Alt/Cmd)는 sticky 동작이다 — 1회 탭하면 armed
   상태로 들어가 다음 비-모디파이어 키 하나에만 적용된 뒤 자동 해제,
   400ms 안에 2회 탭하면 locked 상태로 lock(다시 탭할 때까지 유지). 세 가지
   상태(idle / armed / locked)는 ModifierKeyButton의 시각으로 구분되며 (헌법
   원칙: 시각이 표시기) accessibility label에도 "Control modifier, idle"
   형태로 노출된다. 페이지에는 한 번에 모든 sticky 상태를 비우는 "Clr"
   버튼이 있다(spec 초안의 "Clear modifiers" 어포던스를 좁은 키 폭에 맞게
   라벨만 단축한 것이며 동작은 동일하다 — `model.tapDirectKey(.clearModifiers)`).
6. 블루투스/Magic Keyboard가 연결돼 있으면 하드웨어 키스트로크가 동일한 키심 매핑 표를
   거쳐 RFB KeyEvent로 송신된다(`UIKeyCommand`/`pressesBegan`/`pressesEnded` 경유).
   하드웨어와 온스크린 입력은 충돌 없이 공존하며, 하드웨어 자동 반복은 원격 OS가 소유한다
   (Naru가 합성하지 않는다).
7. 사용자가 토글을 다시 끄면 iOS 시스템 키보드가 복원되고 Compose & Send 모드로 복귀한다.
   이때 Compose 작성 중이던 초안은 보존된다.

#### 제약과 경고

- iOS IME가 만든 조합 중간 상태(예: 한글 초성/중성, 일본어 변환 후보)는 그대로 키 시퀀스로
  전송되지 않을 수 있다. UI는 "이 모드에서 IME가 안 통할 수 있음"을 명시한다.
- secure input field, password field에는 Compose & Send와 마찬가지로 실패할 수 있다.
- 이 모드 사용 중에도 클립보드 paste shortcut, snippet 전송은 별개 동작으로 계속
  쓸 수 있다.
- 진단 export, 로그는 키 입력 내용을 저장하지 않는다 (헌법 원칙 IV).

#### MVP 범위

Direct Keystroke Streaming Mode는 `specs/002-direct-keystroke-mode/spec.md` 로
분리된 별도 feature이며, founder의 핵심 사용 사례(iPhone에서 지속적 AI 코딩 —
Ghostty/Codex over VNC)가 이 모드 없이는 성립하지 않으므로 출시 전 구현이 필요한
ship-blocker로 격상된다. 자세한 사용자 스토리·요구사항·검증은 그 spec에서 추적한다.

## 6.4 Voice Compose

### 사용자 가치

사용자는 원격 컴퓨터에 마이크를 연결하지 않고도 iPhone/iPad의 음성 입력으로 원격 앱에 문장을 넣을 수 있다.

### 기본 포지션

이 기능은 "원격 마이크"가 아니다. 로컬 디바이스에서 음성을 텍스트로 만든 뒤, 사용자가 검토하고 원격에 전송하는 기능이다.

### MVP 흐름

1. compose bar에서 microphone 버튼을 누른다.
2. iOS dictation 또는 앱 내 Speech pipeline으로 문장을 만든다.
3. 결과가 compose bar에 들어간다.
4. 사용자가 수정한다.
5. Send 또는 Send and Enter를 누른다.

### 고급 흐름

- Push-to-talk
- continuous dictation
- partial transcript 표시
- final transcript만 전송
- 음성 명령과 일반 텍스트 구분
- 언어 자동 감지 또는 수동 언어 선택
- 마침표/쉼표/줄바꿈/탭 같은 spoken punctuation 처리

### Voice Command Mode

초기에는 기본 입력과 분리된 명령 모드로 둔다.

명령 예시:

- "전송"
- "전송하고 엔터"
- "줄바꿈"
- "탭"
- "방금 보낸 것 취소"
- "터미널 모드로 보내"
- "마크다운 코드블록으로 감싸"
- "왼쪽 클릭"
- "더블클릭"
- "아래로 스크롤"
- "복사"
- "붙여넣기"

명령 모드 안전 원칙:

- destructive action은 자동 실행하지 않는다.
- 비밀번호, 결제, 삭제, 외부 전송 관련 동작은 사용자 확인을 요구한다.
- 음성 인식 confidence가 낮으면 compose bar에만 넣고 실행하지 않는다.

### Privacy

- 기본은 로컬 iOS 입력 시스템과 on-device 가능한 경로를 우선한다.
- 서버 전사 기능을 제공할 경우 opt-in으로 분리한다.
- 음성 원본은 기본 저장하지 않는다.
- transcript history는 사용자가 끌 수 있어야 한다.
- sensitive mode에서는 transcript, snippet, clipboard log를 저장하지 않는다.

## 6.5 Clipboard & Text Safety

### 문제

텍스트 주입에 클립보드를 쓰면 다음 문제가 생긴다.

- 원격 클립보드가 사용자의 기존 값에서 바뀐다.
- 로컬 클립보드와 원격 클립보드 동기화가 엉킨다.
- iOS pasteboard 권한 prompt가 UX를 방해할 수 있다.
- 보안 필드에서는 paste가 실패하거나 의도와 다르게 동작할 수 있다.

### 설계

- 기본적으로 로컬 iOS pasteboard를 직접 건드리지 않는다.
- 원격 VNC clipboard channel을 사용한다.
- remote clipboard restore는 best-effort로 제공한다.
- helper가 있으면 확정적인 clipboard backup/restore를 제공한다.
- "preserve remote clipboard" 옵션을 기본 ON으로 둔다.
- 실패 시 사용자가 fallback action을 고를 수 있게 한다.

### 실패 메시지 예시

- "이 서버는 UTF-8 clipboard를 확인할 수 없습니다. ASCII fallback 또는 host helper를 사용하세요."
- "현재 원격 앱이 붙여넣기를 차단한 것 같습니다."
- "클립보드 복원은 이 서버에서 보장되지 않습니다."

## 6.6 Image Paste Bridge

### 사용자 가치

사용자는 iPhone/iPad의 사진, 스크린샷, Files 앱의 이미지, Safari에서 복사한 이미지를 원격 브라우저, 메신저, 문서 편집기, 이슈 트래커, IDE에 붙여넣을 수 있다.

이 기능은 특히 다음 상황에서 가치가 크다.

- iPad에서 캡처한 화면을 원격 Slack, Jira, GitHub, Notion, Confluence, Google Docs에 붙여넣기
- iPhone 사진을 원격 브라우저 업로드 필드나 문서에 삽입
- 원격 환경에서만 로그인된 웹앱에 로컬 이미지를 빠르게 첨부
- agent가 보고서나 이슈에 screenshot artifact를 첨부하도록 승인

### 핵심 원칙

1. Image paste는 text paste보다 호환성 리스크가 크다.
   - RFB의 기본 clipboard는 텍스트 중심이다.
   - Extended Clipboard에는 DIB, Files 같은 포맷 개념이 있으나 서버/클라이언트별 구현 편차가 크다.

2. 사용자는 "파일 전송"보다 "붙여넣기"로 느껴야 한다.
   - UX는 Photos/Files/Clipboard에서 이미지를 고르고 Send/Paste를 누르는 흐름이다.
   - 내부 구현은 clipboard, temp file, drag/drop, helper API 중 가장 안정적인 경로를 선택한다.

3. Reliable image paste는 host helper의 핵심 가치다.
   - 순수 VNC 경로는 best-effort로 둔다.
   - host helper가 있으면 OS 네이티브 clipboard에 PNG/DIB/TIFF 등 적절한 포맷을 올리고 paste shortcut을 실행한다.

### 입력 소스

- iOS Photos picker
- Files picker
- system share sheet
- iOS clipboard image
- screenshot capture
- drag and drop from another iPad app
- agent-generated image artifact

### 전송 모드

#### A. Extended Clipboard Image Mode

가능한 경우 VNC Extended Clipboard의 image/file format을 활용한다.

후보 포맷:

- DIB/BMP 계열
- PNG 변환 후 file-like payload
- file transfer extension이 있는 서버의 파일 전송 경로

주의:

- 서버 호환성이 낮을 수 있다.
- 원격 OS clipboard에 실제 이미지로 올라가는지, 파일 경로 텍스트로만 들어가는지 검증이 필요하다.
- MVP 필수 기능으로 두기보다 compatibility lab에서 검증한다.

#### B. Host Helper Clipboard Image Mode

권장 reliable 경로다.

흐름:

1. iOS 앱이 이미지를 PNG/JPEG로 정규화한다.
2. helper로 이미지 bytes와 metadata를 전송한다.
3. helper가 원격 OS clipboard에 이미지 포맷을 설정한다.
4. 앱이 대상 OS paste shortcut을 보낸다.
5. 가능한 경우 helper가 이전 clipboard를 복원한다.

OS별 후보:

- macOS: NSPasteboard에 PNG/TIFF representation 등록
- Windows: Clipboard API에 CF_DIB/PNG fallback 등록
- Linux X11: image/png MIME clipboard 등록
- Linux Wayland: desktop portal 또는 compositor별 clipboard 경로 검토

#### C. Host Helper Temporary File Drop Mode

이미지 clipboard paste가 막힌 앱을 위한 fallback이다.

흐름:

1. helper가 이미지를 임시 파일로 저장한다.
2. 원격 OS에 파일 drag/drop 또는 upload target assist를 제공한다.
3. 실패 시 파일 위치를 사용자에게 보여준다.

사용 사례:

- 원격 브라우저 file input
- 원격 파일 탐색기
- 앱이 이미지 clipboard paste를 지원하지 않는 경우

#### D. Remote Web Upload Assist

장기 기능 후보다.

흐름:

1. 앱이 이미지를 Tailnet-local temporary URL로 노출한다.
2. 원격 브라우저에 URL 또는 다운로드 명령을 주입한다.
3. 사용자가 원격에서 다운로드/업로드한다.

주의:

- 보안과 만료 정책이 중요하다.
- 기본 기능으로 두기보다 power-user fallback으로 둔다.

### UI

Compose bar 옆에 attachment 버튼을 둔다.

메뉴:

- Photo
- File
- Clipboard Image
- Screenshot
- Recent Images

전송 버튼:

- Paste Image
- Paste Image and Enter
- Save to Remote
- Copy to Remote Clipboard

상태 표시:

- image size
- file type
- compressed size
- selected injection path
- helper required 여부

### 이미지 처리

- 기본 포맷: PNG
- 사진 기본 포맷: JPEG 원본 유지, 필요 시 PNG 변환
- 최대 크기 제한
- 압축 품질 선택
- EXIF metadata 제거 기본 ON
- sensitive image history 저장 금지
- alpha channel 보존
- color profile 처리 검토

### MVP 범위

MVP에는 이미지 붙여넣기를 정식 보장 기능으로 넣지 않는다. 대신 Phase 1/2에서 spike를 진행하고, UI/아키텍처가 image attachment를 수용할 수 있게 설계한다.

MVP에서 가능한 최소 범위:

- Photos/Files picker prototype
- PNG normalization
- helper 없이 가능한 VNC image clipboard compatibility test
- image paste failure reason logging

### v1 이후 목표

- macOS helper 기반 image paste beta
- Windows helper 기반 image paste beta
- Linux X11 helper 기반 image paste alpha
- drag/drop 또는 temp file fallback
- agent artifact paste

## 6.7 Agent Handoff

### 사용자 가치

사용자는 원격 화면을 보고 있다가 특정 작업을 AI agent에게 넘길 수 있고, agent의 행동을 관찰하고 중단할 수 있다.

### MVP 이후 기능

- 현재 화면 screenshot 제공
- pointer click, scroll, keyboard shortcut, text injection API
- Compose & Send와 동일한 text injection path 사용
- user approval gate
- action timeline
- emergency stop
- view-only observe mode

### Agent Bridge 모드

1. 사용자가 session에서 "Share with Agent"를 누른다.
2. 앱이 local bridge 또는 host helper bridge를 연다.
3. agent는 제한된 API만 호출한다.
4. 모든 action은 timeline에 기록된다.
5. 위험 action은 사용자 승인을 거친다.

### 보안 원칙

- 기본적으로 Tailnet 안에서만 bridge를 노출한다.
- public tunnel은 기본 제공하지 않는다.
- session-scoped token을 사용한다.
- token은 짧은 TTL을 가진다.
- screen, clipboard, keystroke, file access 권한을 분리한다.

## 7. 정보 구조

### Home

- Favorites
- Recent sessions
- Tailnet devices
- Manual connection
- Diagnostics
- Settings

### Connection Profile

필드:

- profile id
- display name
- host
- port
- protocol: VNC
- target OS: auto, macOS, Windows, Linux
- auth method
- username
- password/keychain reference
- Tailscale device id optional
- MagicDNS name optional
- text injection preference
- clipboard preserve preference
- helper status
- tags

### Session

- remote display viewport
- compose bar
- toolbar
- modifier keys
- pointer mode
- voice compose
- image paste
- snippets
- agent handoff
- connection quality

## 8. UX 상세

## 8.1 첫 실행

1. 제품의 핵심 가치를 짧게 보여준다.
2. Tailscale 사용 여부를 묻는다.
3. Tailscale 앱 설치/연결 상태를 확인하거나 안내한다.
4. 직접 host 입력 또는 Tailnet 탐색을 선택한다.
5. 테스트 연결 후 프로필을 저장한다.

첫 실행 문구 후보:

> Tailnet 안의 컴퓨터에 접속하고, iPhone/iPad에서 완성한 문장을 그대로 입력하세요.

## 8.2 접속 화면

입력 항목:

- Host or MagicDNS
- Port
- Password
- Target OS
- Save profile

보조 버튼:

- Test connection
- Diagnose
- Open Tailscale

## 8.3 세션 화면

기본 상태:

- 원격 화면이 전체 공간을 차지한다.
- 하단 compose bar는 접혀 있다.
- 텍스트 필드를 탭하면 compose bar가 열린다.

Compose bar 상태:

- collapsed: 아이콘과 한 줄 preview
- expanded: multi-line editor
- voice: transcript 상태와 cancel/send
- sensitive: 입력값 숨김과 저장 금지

## 8.4 음성 입력 UX

상태:

- idle
- listening
- transcribing
- ready to send
- command detected
- low confidence
- failed

사용자 제어:

- hold to talk
- tap to start/stop
- language picker
- command/text toggle
- send confirmation

## 9. 기술 아키텍처

## 9.1 iOS/iPadOS 앱

주요 모듈:

- Connection Manager
- Tailscale Integration
- RFB Client
- Framebuffer Renderer
- Input Router
- Compose Engine
- Voice Compose Engine
- Image Paste Engine
- Clipboard Manager
- Credential Store
- Diagnostics
- Agent Bridge

권장 기술 선택:

- Swift/SwiftUI for app shell
- Metal 또는 Core Animation 기반 framebuffer rendering
- Network framework 기반 TCP connection
- Keychain for credentials
- LocalAuthentication for biometric unlock
- Speech framework 또는 system dictation integration 검토

## 9.2 RFB Client Layer

책임:

- handshake
- security negotiation
- framebuffer updates
- pointer events
- key events
- clipboard messages
- encoding decode
- reconnect
- metrics

검토 선택지:

1. 기존 C/C++ 라이브러리 바인딩
   - 장점: encoding과 protocol 호환성을 빨리 확보
   - 단점: iOS 빌드, memory safety, Swift interop 비용

2. Swift native RFB client
   - 장점: 앱 구조와 통합이 깔끔함
   - 단점: encoding 호환성과 성능 검증 비용이 큼

권장:

- Phase 0/1에서는 기존 라이브러리 바인딩으로 feasibility를 빠르게 확인한다.
- 제품화 단계에서 Swift wrapper를 정리하고, 필요한 부분만 native 최적화한다.

## 9.3 Text Injection Adapter

공통 인터페이스:

```swift
protocol TextInjectionAdapter {
    var capability: TextInjectionCapability { get }
    func canInject(_ request: TextInjectionRequest) async -> TextInjectionReadiness
    func inject(_ request: TextInjectionRequest) async throws -> TextInjectionResult
}
```

요청 모델:

```swift
struct TextInjectionRequest {
    let text: String
    let targetOS: TargetOS
    let behavior: SendBehavior
    let preserveClipboard: Bool
    let sensitive: Bool
    let source: TextSource
}
```

Send behavior:

- insertOnly
- insertAndEnter
- insertAndTab
- pasteOnly
- terminalPaste

Adapter 우선순위:

1. HostHelperTextInsertAdapter
2. ExtendedClipboardPasteAdapter
3. LegacyClipboardPasteAdapter
4. KeystrokeFallbackAdapter

## 9.4 Host Helper

초기에는 별도 제품 컴포넌트로 설계하되 MVP 필수로 두지 않는다.

책임:

- text insert
- image clipboard insert
- clipboard backup/restore
- active window/app metadata
- file receive
- temporary file drop
- agent bridge endpoint
- health check

통신:

- Tailnet IP 또는 localhost reverse connection
- mTLS 또는 session token
- pairing code
- per-session permission

배포:

- macOS app/menu bar helper
- Windows tray helper
- Linux daemon

## 9.5 Agent Bridge API

초기 API 후보:

```http
GET /session/screenshot
POST /session/click
POST /session/scroll
POST /session/key
POST /session/text
POST /session/image
POST /session/file
POST /session/shortcut
POST /session/stop
GET /session/timeline
```

원칙:

- `/session/text`는 Compose & Send와 같은 adapter path를 사용한다.
- `/session/image`는 Image Paste Bridge와 같은 adapter path를 사용한다.
- screenshot은 rate limit을 둔다.
- 모든 write action은 audit log에 남긴다.
- sensitive session에서는 clipboard, image, file, screenshot 접근을 제한한다.

## 10. 보안과 개인정보

### 저장

- 접속 비밀번호는 Keychain에 저장한다.
- 프로필 metadata는 로컬 DB에 저장한다.
- biometric unlock 옵션을 제공한다.
- sensitive profile은 앱 시작 때마다 인증을 요구할 수 있다.

### 네트워크

- public VNC 접속은 지원하되 경고를 표시한다.
- Tailnet/MagicDNS 접속을 권장한다.
- agent bridge는 기본적으로 Tailnet 또는 local network에만 노출한다.

### 입력 데이터

- compose history는 기본 짧은 기간만 보존하거나 opt-in으로 둔다.
- sensitive mode에서는 history를 저장하지 않는다.
- 음성 원본은 저장하지 않는다.
- transcript는 전송 전 사용자에게 보인다.

### 로그

- VNC password, clipboard text, transcript, screen content는 기본 로그에서 제외한다.
- crash report에는 세션 host를 익명화한다.

## 11. 제품 분석 지표

개인정보를 침해하지 않는 범위에서 다음 event만 수집할 수 있다.

- connection success/failure category
- text injection mode used
- text injection success/failure category
- voice compose started/completed/cancelled
- image paste mode used
- image paste success/failure category
- diagnose issue category
- session duration bucket
- reconnect count

수집하지 않는 것:

- 원격 화면
- 입력 텍스트
- 음성 원본
- 이미지 원본
- 클립보드 내용
- 비밀번호

## 12. MVP 범위

MVP는 "Tailscale 환경에서 접속하고, iPad/iPhone에서 문장과 음성을 안정적으로 원격에 입력한다"를 증명한다.

### 포함

- iPhone/iPad universal app
- manual VNC connection
- MagicDNS host 접속
- saved profiles
- basic VNC viewer
- touch pointer controls
- external keyboard 기본 지원
- compose bar
- UTF-8 clipboard paste mode
- target OS별 paste shortcut
- remote clipboard preserve best-effort
- iOS dictation 기반 Voice Compose
- snippets
- connection diagnostics
- Keychain credential storage

### 내부 검증 포함

- Photos/Files picker 기반 image paste spike
- PNG/JPEG normalization
- VNC Extended Clipboard image/file capability probe
- image paste failure category logging

### 제외

- Tailscale API device discovery
- host helper
- agent bridge
- reliable image paste
- reliable file transfer
- RDP/SSH
- multi-monitor advanced layout
- team sync/cloud account

## 13. MVP 성공 기준

### 기능 기준

- 사용자가 MagicDNS host와 VNC password로 1분 안에 접속 프로필을 만들 수 있다.
- 한글/영어 혼합 문장을 macOS, Windows, Linux 대상 앱에 입력할 수 있다.
- iOS dictation 결과를 compose bar에서 수정한 뒤 원격에 보낼 수 있다.
- 이미지 붙여넣기 spike 결과로 서버/OS별 compatibility table을 만들 수 있다.
- 실패 시 왜 실패했는지 사용자가 이해할 수 있다.
- 저장된 접속 정보는 Keychain으로 보호된다.

### 품질 기준

- 일반 Wi-Fi/Tailscale 환경에서 typing injection latency p95 1초 이하
- compose send 성공률 95퍼센트 이상. 대상은 지원 VNC server와 일반 text field 기준
- 앱 foreground/background 전환 후 session 복구 가능
- crash-free session 99퍼센트 이상을 목표

### 테스트 매트릭스

대상 OS:

- macOS
- Windows
- Ubuntu 또는 Debian Linux

대상 앱:

- text editor
- terminal
- browser text field
- browser image paste/upload target
- document image insertion target
- login/password field
- IDE/editor

입력 언어:

- Korean
- English
- Japanese
- Chinese simplified
- emoji
- punctuation-heavy command

이미지 소스:

- Photos
- Files
- iOS clipboard image
- screenshot

## 14. 로드맵

## Phase 0. Discovery and Proofs

기간: 1-2주

목표:

- RFB client 선택
- UTF-8 clipboard paste feasibility 확인
- image clipboard/file paste feasibility 확인
- iOS compose bar UX prototype
- Tailscale/MagicDNS 접속 UX 검증

산출물:

- protocol spike
- target VNC server compatibility table
- text injection test harness
- image paste compatibility table 초안
- UX wireframe

결정해야 할 것:

- 기존 VNC 라이브러리 바인딩 vs Swift native
- clipboard extension 지원 범위
- image clipboard를 MVP 이후 기능으로 둘지, beta lab 기능으로 노출할지
- MVP 대상 VNC server 목록

## Phase 1. Technical Prototype

기간: 2-4주

목표:

- 실제 iPad에서 VNC 접속
- frame rendering
- pointer event
- basic key event
- compose bar에서 clipboard paste injection
- Photos/Files에서 선택한 이미지의 VNC clipboard/file paste spike
- MagicDNS host 접속

완료 기준:

- macOS/Windows/Linux 중 최소 2개 대상에 접속 가능
- 한글/영어 문장 전송 성공
- 최소 1개 대상에서 image paste 또는 image file drop path 검증
- paste shortcut OS 분기 동작
- 실패 로그가 진단 화면에 표시됨

## Phase 2. MVP Build

기간: 6-8주

목표:

- 제품으로 쓸 수 있는 첫 버전
- 저장 프로필
- Keychain credential
- snippets
- voice compose
- image attachment UI placeholder
- diagnostics
- reconnect
- iPhone/iPad layout polish

완료 기준:

- TestFlight 배포 가능
- 10명 내외 dogfood 사용 가능
- 주요 crash 없이 30분 이상 session 사용
- compose send 성공률 측정 가능
- image paste는 내부 lab flag로만 측정 가능

## Phase 3. Private Beta

기간: 4-6주

목표:

- Tailscale 사용자 중심으로 beta 운영
- 호환성 문제 수집
- 입력 실패 케이스 정리
- UX 반복 개선

포함 후보:

- Tailscale API device discovery
- App Intents/Shortcuts
- advanced snippets
- terminal paste mode
- image paste beta
- clipboard restore 개선
- gesture customization

완료 기준:

- beta 사용자 50-100명
- 주요 VNC server별 compatibility table 공개
- onboarding completion rate 측정
- compose send failure category 상위 5개 해결 또는 명확한 문서화
- image paste 지원/미지원 조건을 문서화

## Phase 4. v1 Launch

기간: 4주

목표:

- App Store 출시
- 개인 사용자와 power user를 위한 안정 버전

포함:

- Tailnet-first onboarding
- polished session UX
- reliable compose and voice compose
- connection doctor
- privacy-first telemetry
- help docs

가격 후보:

- paid app
- freemium with pro features
- subscription for agent/helper/team features

권장:

- 초기에는 paid app 또는 small subscription으로 power user를 겨냥한다.
- host helper/agent bridge/team features는 Pro tier 후보로 둔다.

## Phase 5. Helper and Agent Platform

기간: v1 이후 8-12주

목표:

- host helper 기반 안정적 text insert
- host helper 기반 안정적 image paste/drop
- clipboard restore 확정성 개선
- agent handoff
- action timeline
- Tailnet-only bridge

완료 기준:

- macOS helper alpha
- `/session/text` API
- `/session/image` API
- screenshot/click/scroll API
- user approval overlay
- session-scoped token

## 15. 주요 리스크

### RFB clipboard 호환성

위험:

- VNC server별 clipboard 구현이 다르다.
- UTF-8/Extended Clipboard 지원이 일관되지 않다.
- 이미지/DIB/Files 포맷은 텍스트보다 더 일관성이 낮다.

대응:

- compatibility table을 제품 일부로 관리한다.
- fallback adapter를 명확히 둔다.
- host helper를 장기 해결책으로 설계한다.

### Image paste 호환성

위험:

- 원격 앱마다 image clipboard, file paste, drag/drop 지원 방식이 다르다.
- 브라우저, 문서 편집기, 메신저, IDE의 paste target behavior가 다르다.
- Linux Wayland 환경에서는 clipboard와 drag/drop 자동화 제약이 크다.

대응:

- 이미지 붙여넣기는 helper 기반 reliable path를 v1 이후 핵심 기능으로 둔다.
- 순수 VNC image clipboard는 compatibility lab 기능으로 검증한다.
- 사용자가 "Paste Image", "Save to Remote", "Copy to Remote Clipboard" 중 선택할 수 있게 한다.

### iOS pasteboard와 dictation UX

위험:

- iOS 버전별 pasteboard permission, dictation behavior가 달라질 수 있다.

대응:

- 로컬 pasteboard 의존을 줄인다.
- system TextField/dictation을 우선 활용한다.
- 앱 내 Speech pipeline은 opt-in 고급 기능으로 둔다.

### Tailscale API/인증 UX

위험:

- Tailnet device discovery를 위해 credential 설정이 복잡해질 수 있다.

대응:

- MVP에서는 MagicDNS/manual host를 우선한다.
- API discovery는 beta 이후로 미룬다.
- read-only credential과 최소 권한을 원칙으로 한다.

### Host helper permission

위험:

- macOS Accessibility, Windows elevated app, Linux Wayland 제약이 크다.

대응:

- helper를 MVP 필수로 두지 않는다.
- OS별 helper capability를 분리한다.
- helper 설치 전후의 사용자 가치를 명확히 설명한다.

### Agent safety

위험:

- agent가 잘못된 화면에 입력하거나 위험 작업을 실행할 수 있다.

대응:

- 기본은 observe plus approval이다.
- destructive action을 자동 실행하지 않는다.
- timeline과 emergency stop을 필수로 둔다.

## 16. 경쟁 제품 관찰 포인트

검토할 축:

- iOS에서 다국어 입력이 얼마나 안정적인가
- 클립보드 기반 입력을 어떻게 설명하는가
- 이미지/파일 붙여넣기를 얼마나 안정적으로 지원하는가
- Tailscale 또는 VPN 환경을 얼마나 자연스럽게 지원하는가
- 음성 입력을 원격 데스크톱 UX로 다루는가
- agent/computer-use 시대의 화면 조작 API를 제공하는가

관찰 대상:

- Screens
- Jump Desktop
- Remotix
- RealVNC Viewer
- Mocha VNC
- Chrome Remote Desktop
- RustDesk
- Parsec

초기 가설:

- Screens는 Tailscale 친화성과 iOS UX에서 강하다.
- Remotix는 clipboard paste 기반 키보드 우회 옵션을 갖고 있다.
- Chrome Remote Desktop은 "모바일에서 완성한 텍스트를 원격에 넣는다"는 사용자 기대치를 만든다.
- 이미지 붙여넣기는 많은 원격 데스크톱 제품에서 file transfer, clipboard sync, drag/drop 사이에 걸쳐 있어 일관된 모바일 UX로 만들 여지가 있다.
- 대부분의 VNC viewer는 agent handoff와 voice-first remote text input을 제품 중심으로 두지 않는다.

## 17. 참고 링크

- Tailscale iOS VPN On Demand: https://tailscale.com/docs/features/client/ios-vpn-on-demand
- Tailscale services and endpoint collection: https://tailscale.com/docs/features/services
- Tailscale macOS/iOS Shortcuts: https://tailscale.com/docs/features/mac-ios-shortcuts
- Screens 5 Tailscale setup: https://help.edovia.com/en/screens-5/connecting-anywhere/tailscale
- Screens keyboard support: https://support.edovia.com/en-GB/screens-5/features/keyboard-support
- Remotix iOS computer settings: https://remotix.com/help/ios/computer-settings/
- RealVNC iOS clipboard help: https://help.realvnc.com/hc/en-us/articles/7636620287133-How-do-I-enable-clipboard-copy-paste-support-in-RealVNC-Viewer-for-iOS
- LibVNCClient API: https://libvnc.github.io/doc/html/group__libvncclient__api.html
- LibVNCServer/LibVNCClient globals, Extended Clipboard constants: https://libvnc.github.io/doc/html/globals_r.html
- Apple NetworkExtension Packet Tunnel Provider: https://developer.apple.com/documentation/NetworkExtension/packet-tunnel-provider
- OpenAI Computer-Using Agent: https://openai.com/index/computer-using-agent/
- Anthropic computer use: https://docs.anthropic.com/en/docs/build-with-claude/computer-use

## 18. 다음 액션

우선순위 순서:

1. RFB client/library 후보 조사
2. iOS에서 VNC clipboard paste spike
3. iOS 이미지 소스에서 원격 image paste/file drop spike
4. macOS, Windows, Linux 대상별 text injection compatibility test
5. compose bar와 attachment UI prototype
6. voice compose prototype
7. Tailscale MagicDNS connection flow prototype
8. MVP TestFlight scope 확정

가장 먼저 검증해야 하는 질문:

- 순수 VNC clipboard path만으로 한글/일본어/중국어 입력을 어느 정도 안정적으로 해결할 수 있는가?
- 원격 클립보드 보존/복원이 helper 없이 어느 수준까지 가능한가?
- 이미지 붙여넣기는 순수 VNC로 충분한가, 아니면 helper가 사실상 필수인가?
- Photos/Files/Screenshot 이미지를 어느 포맷과 크기로 정규화해야 UX가 가장 안정적인가?
- iPad에서 compose bar가 실제 원격 조작을 방해하지 않는가?
- Tailscale API discovery 없이도 Tailnet-first 제품 느낌을 충분히 줄 수 있는가?
- voice compose가 단순 dictation 이상의 차별점으로 느껴지는가?
