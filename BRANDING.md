# 브랜딩 초안

작성일: 2026-04-29 KST

대상 제품: Tailnet-native IME-first VNC Viewer

## 1. 브랜드 결론

현재 1순위 후보는 `Naru` 계열이다. 단독 `Naru`가 가장 좋지만 App Store에 이미 `Naru`라는 productivity/social 앱이 있어, 실제 출시명은 `Naru Remote`, `Naru Port`, `Naru Slate` 중 하나를 검토한다. 지금 단계의 기본 추천은 `Naru Remote`다.

`NodeDeck`은 제품 구조를 정확히 설명하지만, 이름 자체가 너무 기술적이고 remote desktop 도구의 차가운 인상을 벗어나기 어렵다. `Duru`는 의미는 좋지만 브랜드 온도가 밋밋하다. `Maru`는 iPad를 작업 표면으로 보는 메타포가 좋지만 Maru OS와 desktop/mobile convergence 영역에서 충돌한다.

`Naru`는 제품의 연결 본질을 더 잘 잡는다.

- 나루: 배가 닿고 사람이 건너는 곳, ferry crossing, port
- 제품 의미: iPhone/iPad가 private network와 원격 컴퓨터 사이의 나루터가 된다.
- 텍스트/음성/이미지/파일/agent action이 local device에서 remote computer로 건너간다.
- 발음: nah-roo. 영어 사용자도 읽기 쉽고, 부드럽고 기억하기 쉽다.

`사공/Sagong`은 의미는 매력적이지만 앱 이름으로는 2순위 이하다.

- 사공: 배를 몰아 건네주는 사람
- 제품 의미: 사용자를 remote computer로 건네주는 조종자, 또는 agent를 통제하는 가이드
- 장점: 매우 한국적이고 독특하다.
- 리스크: 영어권에서 발음과 철자가 어렵고, 인물명/아티스트명으로 보일 수 있다. 제품이 사용자보다 "도구가 주체"인 느낌도 강하다.

단독 `Naru`의 리스크:

- App Store에 `Naru`라는 productivity/social 앱이 이미 있다.
- `Naru`는 일본어/인명/콘텐츠 IP에서도 흔히 보인다.
- 따라서 출시 전 App Store Connect 이름 예약과 trademark clearance가 필요하다.

단독 `Maru`의 리스크:

- Maru OS가 이미 존재한다. Maru OS는 Android phone을 desktop Linux 환경으로 바꾸는 프로젝트이고, VNC/SSH/desktop productivity와 인접한 영역이다.
- 따라서 단독 `Maru`는 검색/브랜드 혼동 가능성이 있다.
- 이 리스크를 줄이려면 App Store 표시명과 제품명은 `Maru Slate`, `Maru Console`, `Maru Remote`처럼 보조어를 붙이고, 구어체/로고에서만 `Maru`를 쓰는 방식이 좋다.

`NodeDeck`은 앱 이름이 아니라 내부 제품 개념 또는 기능명으로 남긴다.

- Node: tailnet device, remote computer, server, endpoint
- Deck: iPad command surface, input dock, control deck
- NodeDeck: `Naru Remote` 안의 session/input workbench 내부 개념으로만 사용 가능

권장 제품명:

> Naru Remote

권장 App Store 표시명:

> Naru Remote

권장 subtitle:

> Private Network Remote Desktop

한국어 설명 문장:

> iPhone/iPad에서 만든 텍스트, 음성, 이미지, 파일을 private network 안의 원격 컴퓨터에 정확하게 넣는 remote desktop 앱.

영어 설명 문장:

> A remote desktop workbench for private networks, built around reliable text, voice, image, and file input from iPhone and iPad.

브랜드 관계:

- App: Naru Remote
- Short brand: Naru
- Core surface: Remote Input Dock
- Host helper: Naru Helper
- Agent bridge: Naru Bridge
- Optional naming metaphor: Naru Port 또는 Naru Slate

### Deck 대체어 평가

`Deck`은 Steam Deck, command deck, DJ deck처럼 조작 표면의 느낌이 좋지만 이미 하드웨어/게임/컨트롤러 인상이 강하다. 이 제품은 "원격 화면을 조작하는 패드"보다 "내 기기에서 만든 입력을 안전하게 건네는 나루터"가 더 핵심이므로 `Port`나 `Slate`가 더 낫다.

| 이름 | 평가 | 장점 | 리스크 |
| --- | --- | --- | --- |
| Naru Remote | 기본 추천 | App Store에서 기능이 즉시 이해된다. `Naru`의 감성과 `Remote`의 검색성을 같이 가져간다 | 가장 시적이지는 않다 |
| Naru Port | 감성형 1순위 | 나루터, network port, private network gateway 의미가 겹쳐서 좋다 | 개발자/네트워크 도구처럼 보일 수 있다 |
| Naru Slate | iPad형 1순위 | iPad를 글쓰기/입력 표면으로 보는 느낌이 좋고 `Deck`보다 부드럽다 | remote desktop 카테고리는 subtitle로 보강해야 한다 |
| Naru Bridge | 보류 | 텍스트/이미지/파일을 건넨다는 의미가 직관적이다 | Bridge는 원격/네트워크 제품에서 너무 흔하다 |
| Naru Dock | 보류 | 하단 입력 바와 잘 맞는다 | macOS/iPadOS Dock, 하드웨어 dock과 의미가 겹친다 |
| Naru Console | 보류 | agent/ops/power user 도구로는 좋다 | 일반 iPad 사용자에게 엔터프라이즈 도구처럼 보일 수 있다 |
| Naru Ferry | 제외 | 나루 의미를 영어로 직접 옮긴 이름이다 | 교통/여행 앱처럼 보인다 |
| Sagong | 보류 | 한국적이고 스토리가 강하다 | 영어권 발음/철자가 어렵고, 앱이 사용자보다 주체처럼 느껴진다 |

## 2. 이름 조사 메모

빠른 웹/App Store 표면 조사 기준이다. 법적 trademark clearance, 도메인 확보, App Store Connect 이름 예약은 별도 작업이 필요하다.

### 경쟁 제품 이름 패턴

- Screens: 화면 중심, Apple-first, 간결함
- Jump Desktop: 이동성/접속성, RDP/VNC/Fluid 확장
- Remotix: remote + technical suffix
- RealVNC Viewer: 프로토콜 신뢰성
- Mocha VNC: 저가/레거시 VNC 앱 느낌
- Splashtop, TeamViewer, AnyDesk: 원격지원/엔터프라이즈 도구 느낌
- Parsec, RustDesk, NoMachine: 자체 기술/프로토콜 또는 개발자 친화 톤

관찰:

- "Remote", "Desk", "VNC", "Screen", "Jump", "Relay", "Bridge"는 이미 포화돼 있다.
- Tailscale에 기대는 이름은 피하는 것이 좋다. 예: TailDesk, TailView, TailBridge.
- 앱의 차별점은 화면 자체보다 input/control surface이므로, 이름도 "viewer"보다 "remote/workbench/port/slate" 쪽이 맞다.

### 조사 중 충돌이 보인 이름

- PastePort: 기존 사용 흔적이 많음
- RelayDesk: 기존 앱/서비스 충돌 가능성 큼
- ScribeDesk: 기존 사용 흔적
- DeskDock: 기존 앱/도구 충돌
- KeyDeck: 기존 사용 가능성
- DeskPilot: 기존 사용 가능성
- ScreenPort: App Store에 이미 ScreenPort 앱 존재
- GlyphDeck: glyphdeck.com 및 PyPI package 존재
- Docklet: App Store에 Docklet 앱 존재
- Decklet: decklet.app 존재
- RelayPad: 기존 SaaS/product 존재
- Podo: App Store에 Pomodoro/productivity 앱 존재
- Nori: homework/family AI 등 App Store와 Android 앱 충돌이 큼
- Tok/TokTok/Ttok: TikTok 연상, messaging/social/downloader 충돌이 큼
- Ssak/Kkok: 한국어 감각은 좋지만 기존 앱 사용 흔적이 있고 영어권 철자가 어렵다
- Jadu: AR game과 enterprise software 회사 충돌
- Mandu: 기존 iOS productivity app 사례 있음
- Dalgona: 게임/음식 밈 인상이 강함
- Maru: Maru OS가 desktop/mobile convergence 영역에서 존재. 단독 사용은 신중해야 함
- Naru: App Store에 Naru productivity/social 앱 존재
- Madi: App Store에 MaDi health 앱, MADI professional audio acronym 존재
- Kori/Gori: AI/productivity/shipping/game 등 사용 흔적이 많음

### 한글/음식/의성어 확장 후보

이름 기준:

- 2-3음절
- 영어권에서 발음 가능
- App Store subtitle 없이도 너무 엉뚱하게 보이지 않음
- 음식 앱으로 오인되지 않음
- 기능을 직접 설명하지 않아도 브랜드로 성장 가능
- 한국어 의미를 설명할 때 제품 철학과 연결 가능

| 이름 | 출처/느낌 | 평가 | 장점 | 리스크 |
| --- | --- | --- | --- | --- |
| Naru Remote | 나루 + remote | 1순위 | 의미, 발음, 기능 이해, App Store 검색성의 균형이 가장 좋음 | 단독 `Naru` 앱이 이미 있어 clearance 필요 |
| Naru Port | 나루터 + network port | 1.5순위 | 나루터/사설망/전송 지점 의미가 제품 구조와 잘 맞음 | 개발자 도구처럼 보일 수 있음 |
| Naru Slate | 나루 + input slate | 1.5순위 | iPad를 문장/음성/이미지 입력 표면으로 보는 감각이 좋음 | 원격 데스크톱임을 subtitle에서 보강해야 함 |
| Naru | 나루 | 2순위 | 가장 짧고 부드럽고, ferry crossing 의미가 remote bridge와 잘 맞음 | App Store에 Naru 앱 존재 |
| Maru Slate | 마루 + slate | 2순위 | `Maru Deck`보다 부드럽고 iPad-native 입력 표면 느낌이 좋음 | Maru OS와 인접 충돌 |
| Maru Console | 마루 + console | 2.5순위 | ops/agent/tooling 방향과 맞음 | power-user 도구로 강하게 좁혀짐 |
| Sagong | 사공 | 2.5순위 | 나루 세계관과 잘 맞고 독특함 | 영어권 발음/철자와 의미 전달이 어렵다 |
| Bori | 보리 | 3순위 | 따뜻하고 짧고 기억 쉬움. grain/node/seed metaphor 가능 | food/웰니스 앱처럼 보일 수 있음 |
| Madi | 마디 | 3순위 | node, segment, text chunk, agent step과 의미가 잘 맞음 | MaDi health 앱과 MADI audio acronym 존재 |
| Duru | 두루 | 3순위 | all-around/private network/멀티 입력과 의미가 잘 맞고 발음이 쉬움 | 사용자가 느끼는 브랜드 온도가 다소 밋밋함 |
| Dubu | 두부 | 보류 | 귀엽고 부드럽고 기억성 강함. soft input bridge 이미지 | 개발자/운영 도구로는 너무 가벼울 수 있음 |
| Hodu | 호두 | 보류 | 단단한 shell, secure core 은유 가능 | 음식 앱/건강식품 느낌, clearance 필요 |
| Gori/Kori | 고리 | 보류 | link/ring 의미가 connection과 정확히 맞음 | Kori/Gori 기존 앱과 서비스 사용 흔적이 많음 |
| Chak | 착 | 보류 | "착 붙는다", precise paste 느낌이 좋음 | 영어권에서 발음/철자 설명이 필요하고 이미 사용 흔적 있음 |
| Tok | 똑 | 보류 | precise, knock, smart 느낌. send microinteraction에 좋음 | TikTok/TokTok 연상과 충돌이 큼 |
| Kkok | 꼭 | 보류 | 확실함/반드시의 의미가 좋음 | kk 철자가 어렵고 앱 이름으로 딱딱함 |
| Ssak | 싹 | 보류 | 빠르고 깔끔하게 처리하는 느낌 | 영어권 발음이 어렵고 기존 앱 충돌 |
| Jjan | 짠 | 제외 | 한국적이고 발랄함 | 술집/엔터테인먼트 느낌, 운영 도구와 안 맞음 |
| Podo | 포도 | 제외 | 귀엽고 짧음 | Pomodoro/productivity 앱 충돌이 크고 음식 앱처럼 보임 |
| Nori | 김/놀이 느낌 | 제외 | 발음 쉬움 | 기존 앱 충돌이 매우 많음 |
| Yuzu | 과일 | 제외 | 글로벌하게 예쁨 | 이미 식품/도구/앱에서 매우 흔함 |
| Omija | 오미자 | 제외 | 한국적이고 독특함 | 영어권 발음/철자가 어렵고 제품 의미와 약함 |

### 기술형 이름 후보 평가

| 이름 | 평가 | 장점 | 리스크 |
| --- | --- | --- | --- |
| NodeDeck | 기술형 1순위 | tailnet node + command deck 의미가 좋고, product architecture와 맞음 | 앱 이름으로는 차갑고 설명적임 |
| InputDeck | 기술형 2순위 | 기능을 직설적으로 설명함 | generic하고 technical, 브랜드 감도 약함 |
| Remote Slate | 보류 | 완성된 문장/음성/이미지 입력 표면을 설명하기 좋음 | 브랜드명보다는 기능명에 가까움 |
| Input Port | 보류 | private network로 입력을 건네는 경로가 명확함 | infra product처럼 보이고 차갑다 |
| GlyphDock | 보류 | 다국어/문자 입력 차별점과 맞음 | Glyph hardware dock, Glyphs app 등 주변 충돌과 text-only 인상이 있음 |
| BridgeBoard | 보류 | bridge 개념이 명확함 | 컨설팅/하드웨어/레트로 컴퓨팅 충돌, 다소 딱딱함 |
| DeskLane | 보류 | desk workflow와 lane metaphor | physical desk cable product와 충돌, 덜 앱스러움 |
| ComposeDesk | 보류 | Compose & Send를 직접 설명함 | Jetpack Compose/Remote Compose와 개념 충돌, 이름이 길고 설명적 |

## 3. 브랜드 포지셔닝

## 3.1 카테고리

기존 카테고리:

> VNC Viewer

우리 카테고리:

> Remote Desktop Workbench

더 좁은 카테고리:

> iPhone-first remote input workbench for private networks (iPad-graceful)

이 좁은 카테고리는 constitution §VI("Phone-First, iPad-Graceful")의 결과다. 일차 설계 대상은 iPhone이며, 사용 시나리오에는 원격 머신의 터미널 환경과 AI 코딩 CLI 세션을 폰에서 30분~수 시간 이어가는 sustained workspace transport가 포함된다.

## 3.2 차별화 문장

짧은 문장:

> Remote desktops, composed locally.

제품 설명:

> Naru Remote turns your iPhone or iPad into a precise input surface for computers on your private network.

한국어:

> Naru Remote는 iPhone/iPad를 private network 안의 컴퓨터를 위한 정밀 입력 표면으로 바꾼다.

## 3.3 브랜드 원칙

1. Quiet confidence
   - 개발자/운영자가 매일 쓰는 도구다. 과장된 미래감보다 차분한 신뢰감이 우선이다.

2. Input-first
   - 브랜드의 중심은 "원격 화면 보기"가 아니라 "원격에 정확히 넣기"다.

3. Network-aware
   - Tailscale-friendly, MagicDNS, reachability, diagnostics가 제품 경험의 일부다.

4. Human-supervised agents
   - agent 기능은 자동화 과시가 아니라 관찰, 승인, 중단, 기록이 가능한 조심스러운 작업 위임이어야 한다.

5. iPhone-first, iPad-graceful (constitution §VI)
   - 일차 설계 대상은 iPhone이다. 작은 화면, 셀룰러 네트워크, 짧은 attention window 위에서도 사용자가 원격 머신의 데스크톱 터미널과 AI 에이전트 세션을 깨끗하게 이어갈 수 있어야 한다.
   - iPad는 같은 워크플로우의 자연스러운 확장이다. 외장 키보드, Stage Manager, 펜, 외부 디스플레이를 제대로 쓰되, 그 풍요로움이 iPhone 경험의 디자인 우선순위를 흐리지 않는다.
   - 데스크톱 앱을 작게 만든 느낌이 아니라, iOS의 키보드, 음성, 사진, 파일, 클립보드를 제대로 쓰는 느낌이어야 한다.

## 4. 메시징

### One-liner

> Naru Remote is a remote desktop workbench for private networks.

### Value proposition

> Connect to computers on your private network, then send text, voice, images, files, shortcuts, and agent actions from your iPhone or iPad with control and precision.

### App Store short description

> A VNC remote desktop built for private networks, reliable multilingual text input, voice compose, and image paste from iPhone and iPad.

### Korean short description

> private network 안의 컴퓨터에 접속하고, iPhone/iPad에서 완성한 텍스트, 음성, 이미지, 파일을 정확히 전송하는 VNC remote desktop.

### Tagline 후보

1. Remote desktops, composed locally.
2. Your iPad input surface for private desktops.
3. Type here. Work there.
4. Speak here. Paste there.
5. A precise input port for every remote computer.
6. Private remote access, native iPad input.

추천:

> Type here. Work there.

이유:

- 짧고 기억하기 쉽다.
- 텍스트 입력 문제를 바로 건드린다.
- Voice/Image/File까지 확장할 때도 "여기서 만들고 저기서 일한다"는 구조가 유지된다.

## 5. 네이밍 시스템

앱 이름은 `Naru Remote`를 기본으로 두고, 기능명은 직설적으로 간다. 감성 언어는 `Naru`와 `Port/Slate`에 머물고, 실제 UI 컴포넌트는 `Remote Input Dock`처럼 기능을 바로 알 수 있게 쓴다.

### Core Features

- Remote Input Dock
- Compose & Send
- Voice Compose
- Image Paste
- File Drop
- Snippets
- Shortcut Palette
- Compatibility Doctor
- Tailnet Radar
- Agent Handoff
- Action Timeline
- Desk Mode

### Pro/Helper Features

- Naru Helper
- Native Text Insert
- Reliable Image Paste
- Clipboard Restore
- Headless Display
- Agent Bridge

### 피해야 할 기능명

- Magic Input
- AI Desktop
- Universal Control
- Screen Share Pro
- TailDesk
- Tailscale Desktop
- Chrome-like Input

이유:

- generic하거나 기존 제품/플랫폼과 충돌한다.
- 구현 보장보다 과장된 인상을 준다.
- Tailscale/Apple/Google 브랜드에 불필요하게 기대게 된다.

## 6. 디자인 컨셉

추천 디자인 컨셉은 `Quiet Ops Console`이다.

## 6.1 Quiet Ops Console

### 의도

개발자와 power user가 매일 켜두는 운영 콘솔처럼 보이되, iPad 앱답게 터치와 입력이 편해야 한다. 화려한 원격 데스크톱 앱이 아니라 "문제가 생겼을 때 믿고 여는 앱"이어야 한다.

### 감성 키워드

- precise
- quiet
- private
- operational
- native
- controlled
- legible

### 피해야 할 감성

- cyberpunk
- gaming overlay
- VPN hacker aesthetic
- enterprise helpdesk portal
- glossy SaaS dashboard
- decorative gradient hero

## 6.2 Visual Metaphor

메타포:

> Local input crossing into private remote nodes.

UI에서 반복되는 형태:

- node: 원격 장비
- lane: 전송 경로
- port: private network로 들어가는 접점
- slate: iPad에서 입력을 완성하는 표면
- dock: 하단 입력/명령 표면
- pulse: 텍스트/이미지/파일 전송 상태
- gate: agent approval과 sensitive action

## 6.3 App Icon 방향

추천 아이콘:

> rounded square 안에 작은 port/slate와 세 개의 remote node가 연결된 형태.

구성:

- 배경: graphite 또는 near-black
- 중심: 얇은 line으로 연결된 3개 node
- 하단: input surface를 상징하는 가로 slot
- slot에서 위 node로 올라가는 작은 signal pulse
- 텍스트/음성/이미지를 직접 그리지 않고, "local input이 private node로 건너가는" 구조만 상징

피해야 할 아이콘:

- 모니터 + 커서만 있는 아이콘
- VNC 글자 로고
- Tailscale 로고와 유사한 점 배열
- 구름/cloud 아이콘
- 마이크만 강조한 아이콘
- 과도한 네온/그라디언트

## 7. 컬러 시스템

목표:

- 운영 도구의 선명함
- iPadOS와 어울리는 차분함
- 상태를 색으로 명확히 구분
- 한 가지 hue로 뒤덮이지 않기

### Light Theme

| Token | Hex | 용도 |
| --- | --- | --- |
| Canvas | `#F7F8F5` | 기본 배경 |
| Surface | `#FFFFFF` | 패널, modal |
| Surface Raised | `#EEF1F4` | toolbar, dock background |
| Ink | `#171A1F` | 기본 텍스트 |
| Muted Ink | `#68707D` | 보조 텍스트 |
| Hairline | `#D9DEE5` | 경계선 |
| Signal Blue | `#2D7DFF` | primary action, selected |
| Link Green | `#2FBF71` | connected, success |
| Amber | `#E5A13A` | warning, degraded |
| Coral | `#E85D4F` | error, blocked |
| Violet | `#7A5CFF` | agent accent only |

### Dark Theme

| Token | Hex | 용도 |
| --- | --- | --- |
| Canvas | `#111318` | 기본 배경 |
| Surface | `#1A1E25` | 패널 |
| Surface Raised | `#242A33` | dock, toolbar |
| Ink | `#F3F5F7` | 기본 텍스트 |
| Muted Ink | `#9AA3AF` | 보조 텍스트 |
| Hairline | `#303845` | 경계선 |
| Signal Blue | `#5B9BFF` | primary action |
| Link Green | `#45D483` | connected |
| Amber | `#F0B957` | warning |
| Coral | `#FF756B` | error |
| Violet | `#9B87FF` | agent accent only |

### 사용 규칙

- Blue는 사용자가 누를 수 있는 주요 행동에 쓴다.
- Green은 상태를 의미할 때만 쓴다. 버튼 색으로 남용하지 않는다.
- Violet은 agent 기능의 보조 색이다. 전체 테마 색으로 쓰지 않는다.
- Red/Coral은 destructive 또는 blocked 상태에만 쓴다.
- 배경을 dark blue/slate 계열로만 밀지 않는다. graphite + neutral + status accents로 유지한다.

## 8. Typography

기본:

- SF Pro Text
- SF Pro Display
- SF Mono

규칙:

- host, port, IP, MagicDNS, command, shortcut은 SF Mono
- 본문과 label은 SF Pro Text
- hero-scale type은 landing/onboarding에서만 사용
- toolbar와 dock 내부는 compact heading을 사용
- letter spacing은 0
- viewport width 기반 font scaling 금지

## 9. Layout System

## 9.1 Home

목표:

- "접속 가능한 장비를 고른다"가 첫 화면에서 즉시 보여야 한다.

구성:

- 좌측 또는 상단: Tailnet Radar
- 중앙: Favorites / Recent Nodes
- 우측 또는 하단: Diagnostics summary
- quick action: Manual Connection

피해야 할 것:

- 마케팅 hero
- 큰 설명 카드
- 장식용 illustration

## 9.2 Session

목표:

- 원격 화면이 주인공이고, 입력 dock/slate는 필요할 때만 강하게 나타난다.

구성:

- full-bleed remote viewport
- bottom Remote Input Dock
- compact connection HUD
- edge toolbar
- floating shortcut palette
- agent approval overlay

Remote Input Dock modes:

- Text
- Voice
- Image
- File
- Snippet
- Shortcut
- Secret

## 9.3 Diagnostics

목표:

- 사용자가 "왜 안 되는지"를 앱 안에서 이해한다.

구성:

- Tailscale status
- DNS/MagicDNS
- TCP reachability
- VNC handshake
- auth
- clipboard text
- UTF-8
- image paste
- helper
- agent bridge

디자인:

- checklist 형태
- status icon + 짧은 원인 + action
- log는 접을 수 있게

## 10. Interaction

### Send Interaction

텍스트/이미지/파일 전송 시:

1. dock에서 Send를 누른다.
2. dock 위에 300-500ms 정도의 subtle pulse가 나타난다.
3. HUD에 `Sent as UTF-8 Clipboard`, `Pasted via Helper`, `Saved to Remote` 같은 실제 경로를 표시한다.
4. 실패 시 경로와 원인을 표시한다.

### Voice Interaction

상태:

- idle
- listening
- transcribing
- ready
- low confidence
- command detected

규칙:

- 자동 실행보다 검토 후 전송을 기본으로 둔다.
- command mode는 색과 label을 명확히 분리한다.
- confidence가 낮으면 compose text로만 넣고 실행하지 않는다.

### Agent Interaction

상태:

- observe
- request control
- acting
- needs approval
- paused
- stopped

규칙:

- agent가 할 일을 timeline에 보여준다.
- destructive action은 approval sheet를 거친다.
- stop 버튼은 항상 visible 영역에 둔다.

## 11. Voice and Tone

브랜드 톤:

- 짧고 구체적
- 원인과 해결책을 같이 제시
- 과장하지 않음
- "AI가 알아서"보다 "사용자가 승인하고 통제"를 강조

좋은 문구:

- `Ready to paste`
- `Sent as UTF-8 text`
- `Tailscale is connected`
- `MagicDNS resolved`
- `Paste blocked by the remote app`
- `Helper required for reliable image paste`
- `Agent is waiting for approval`

나쁜 문구:

- `Something went wrong`
- `AI magic`
- `Ultra secure`
- `Universal paste always works`
- `Connected to Tailscale` when only DNS resolved

## 12. Onboarding Concept

첫 실행은 기능 설명보다 실제 접속으로 바로 간다.

화면 순서:

1. Choose a node
2. Check private network
3. Connect with VNC
4. Try Compose & Send

온보딩 문구:

> Pick a computer on your private network.

> Type or speak on your iPad. Naru sends the finished input to the remote computer.

> For image paste and native text insert, install Naru Helper later.

## 13. Website/Landing 방향

첫 viewport:

- 제품명 `Naru Remote`
- 실제 iPad session 화면 또는 generated product screenshot
- Remote Input Dock이 보이는 상태
- Tailnet node list가 힌트로 보이는 layout

H1 후보:

> Naru Remote

Supporting copy:

> A remote desktop workbench for private networks. Compose text, dictate, paste images, send files, and hand off controlled actions from iPhone or iPad.

CTA:

- Join TestFlight
- Read the Spec

피해야 할 것:

- 추상 gradient hero
- floating card-heavy SaaS landing
- "AI-powered remote desktop"만 앞세우는 문구
- Tailscale 공식 제품처럼 보이는 디자인

## 14. Product UI Naming Map

| Product Area | User-facing Name | Internal Name |
| --- | --- | --- |
| 장비 탐색 | Tailnet Radar | TailnetConnectionHub |
| 하단 입력 바 | Remote Input Dock | InputDock |
| 문장 입력 | Compose & Send | TextInjection |
| 음성 입력 | Voice Compose | VoiceCompose |
| 이미지 주입 | Image Paste | ImagePasteBridge |
| 파일 주입 | File Drop | FileDropBridge |
| 진단 | Compatibility Doctor | Diagnostics |
| 에이전트 위임 | Agent Handoff | AgentBridge |
| 작업 기록 | Action Timeline | AgentTimeline |
| 책상형 iPad 사용 | Desk Mode | DeskMode |

## 15. 다음 액션

1. `Naru Remote`, `Naru Port`, `Naru Slate` 이름에 대해 App Store Connect 이름 예약 가능성 확인
2. `Naru Remote`, `Naru Helper`, `Naru Bridge` 상표/도메인/소셜 핸들 조사
3. 단독 `Naru`를 사용할 경우 기존 App Store 앱과의 혼동/상표 리스크 검토
4. `Maru Slate`, `Maru Console`을 백업 후보로 유지할지 결정
5. App icon rough 3안 제작
6. Home, Session, Diagnostics 3개 화면 와이어프레임 제작
7. Remote Input Dock component visual prototype
8. Light/Dark palette를 실제 iPad screenshot 위에서 검증
9. App Store subtitle과 keyword 후보 작성

## 16. 참고 링크

- Screens 5 App Store: https://apps.apple.com/app/apple-store/id1663047912
- Screens Tailscale: https://help.edovia.com/en/screens-5/connecting-anywhere/tailscale
- Screens keyboard support: https://support.edovia.com/en-GB/screens-5/features/keyboard-support
- Jump Desktop App Store: https://apps.apple.com/us/app/jump-desktop-rdp-vnc-fluid/id364876095
- Jump Desktop changelog: https://changelog.jumpdesktop.com/
- Remotix iOS: https://remotix.com/remotix-ios/
- Remotix iOS settings: https://remotix.com/help/ios/computer-settings/
- RealVNC Viewer App Store: https://apps.apple.com/us/app/vnc-viewer-remote-desktop/id352019548
- Tailscale MagicDNS: https://tailscale.com/docs/features/magicdns
- Tailscale Services: https://tailscale.com/docs/features/services
- Naru App Store 충돌 메모: https://apps.apple.com/us/app/naru/id6473922056
- Maru OS 충돌 메모: https://maruos.com/
