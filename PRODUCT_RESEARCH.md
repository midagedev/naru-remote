# 원격 데스크톱 앱 경쟁/수요 리서치

작성일: 2026-04-29 KST

## 1. 요약

아이폰/아이패드용 원격 데스크톱 시장은 이미 기능이 많은 편이다. Screens, Jump Desktop, Remotix 같은 iOS 친화 앱은 VNC/RDP/자체 프로토콜, 다중 모니터, 파일 전송, 클립보드, Apple Pencil, Tailscale, 저지연 스트리밍까지 상당히 많이 갖고 있다. Splashtop, TeamViewer, AnyDesk 계열은 원격지원/엔터프라이즈 수요를 잡고 있으며, Citrix/VMware/Windows App 계열은 기업 VDI 요구를 깊게 다룬다.

그럼에도 기회는 있다. 현재 제품들은 대체로 "원격 화면을 모바일에 잘 보여주고 키/마우스 이벤트를 보낸다"에 집중한다. 우리가 잡아야 할 차별점은 다음이다.

1. Tailnet-native 접속 경험
2. iOS/iPadOS를 입력 컴포저로 쓰는 Compose/Voice/Image bridge
3. iPad를 진짜 원격 워크스테이션 콘솔로 만드는 desk mode
4. agent가 원격 세션을 안전하게 조작하도록 하는 approval/timeline layer

제품 포지션은 다음처럼 정리된다.

> Tailscale을 쓰는 power user와 agent 시대 사용자를 위한 iPad-first remote workbench.

## 2. 경쟁 제품 지도

## 2.1 Apple-first VNC/RDP 앱

### Screens 5

강점:

- Mac/iPhone/iPad/Vision Pro universal 앱
- Tailscale 연동을 앱 안에 직접 제공
- 가상 키보드에서는 Unicode 문자 전송
- hardware keyboard와 software keyboard 입력 경로를 구분
- Curtain Mode, Observe/Control mode, Apple Pencil, toolbar customization
- Mac 대상 파일 전송
- rich clipboard, images 포함 clipboard sharing을 App Store 설명에서 강조

관찰:

- Screens는 우리가 생각한 "Tailscale-friendly VNC" 방향을 이미 일부 선점했다.
- 입력 문제도 Unicode keyboard support로 다루고 있다.
- 그러나 제품 중심은 여전히 remote screen control이고, "문장/음성/이미지 입력 bridge"를 1급 워크플로로 세우지는 않는다.

참고:

- https://help.edovia.com/en/screens-5/connecting-anywhere/tailscale
- https://support.edovia.com/en-GB/screens-5/features/keyboard-support
- https://support.edovia.com/en/screens-5/features/file-transfers-iphone
- https://support.edovia.com/en/screens-5/features/pencil-support
- https://support.edovia.com/en/screens-5/features/curtain-mode

### Jump Desktop

강점:

- RDP, VNC, 자체 Fluid 프로토콜 지원
- Fluid 2.0, hardware codecs, AV1, bandwidth/framerate controls
- iOS에서 virtual display 지원
- iPadOS background runtime 설정
- RDP folder sharing, audio streaming, remote printing
- Fluid에서 clipboard sharing
- game controller, USB HID redirection, creative control surface까지 확장
- 2026 changelog 기준 Korean/Chinese/Japanese hardware keyboard input fix를 명시

관찰:

- 성능/저지연/creative workflow에서는 매우 강하다.
- 자체 host agent/protocol이 있기 때문에 VNC만 쓰는 앱보다 할 수 있는 일이 많다.
- 우리도 장기적으로 helper/protocol을 가져야 image paste, agent handoff, virtual display 같은 기능을 reliable하게 만들 수 있다.

참고:

- https://apps.apple.com/us/app/jump-desktop-rdp-vnc-fluid/id364876095
- https://changelog.jumpdesktop.com/

### Remotix

강점:

- VNC, RDP, Apple Screen Sharing, 자체 NEAR 프로토콜
- NEAR는 H.264 기반 저지연 adaptive protocol
- Pasteboard sharing이 pictures/formatted text를 포함
- "Keyboard-through-Clipboard" 모드로 multi-language input 문제를 직접 겨냥
- file manager, file transfer, multiple displays, sound redirection, curtain mode
- local discovery, WOL, Face ID/Touch ID, master password

관찰:

- 우리가 생각한 "텍스트를 클립보드로 우회"는 이미 검증된 수요다.
- 다만 Remotix의 keyboard-through-clipboard는 설정 옵션에 가깝다. 우리는 이것을 하단 Compose/Voice/Image dock이라는 주 UX로 끌어올릴 수 있다.

참고:

- https://remotix.com/remotix-ios/
- https://remotix.com/help/ios/computer-settings/
- https://remotix.com/help/ios/connection/

### RealVNC Viewer

강점:

- VNC 표준/기업 신뢰도
- iOS clipboard support 문서화
- local network VNC service discovery prompt

관찰:

- iOS clipboard는 OS permission, app background/reconnect, "현재 clipboard를 최초 접속 시 자동으로 보내지 않음" 같은 UX 문제가 있다.
- 우리 앱의 connection/session doctor는 clipboard 상태까지 진단해야 한다.

참고:

- https://help.realvnc.com/hc/en-us/articles/7636620287133-How-do-I-enable-clipboard-copy-paste-support-in-RealVNC-Viewer-for-iOS
- https://apps.apple.com/us/app/vnc-viewer-remote-desktop/id352019548

### Mocha VNC / Remoter Pro

강점:

- 가격이 낮고 오래된 VNC 사용자층이 있다.
- WOL, Bonjour/NETBIOS, extra keys, barcode scanner, printing 같은 niche 기능을 제공한다.
- Remoter Pro는 VNC/RDP/SSH 통합과 RDP over SSH 같은 power-user 기능을 제공한다.

관찰:

- 저가/레거시 VNC 앱과 직접 싸우면 기능 대비 가격 경쟁으로 빠지기 쉽다.
- 우리는 "싸고 단순한 VNC viewer"가 아니라 "iPad-first tailnet workbench"가 되어야 한다.

참고:

- https://apps.apple.com/us/app/mocha-vnc/id284981670
- https://apps.apple.com/ie/app/remoter-pro-vnc-ssh-rdp/id519768191

## 2.2 Remote support / managed access 제품

### Splashtop

강점:

- file transfer, logging, multi-monitor, remote audio, remote print, remote reboot, remote wake
- attended/unattended support, scheduled remote access
- tablet/mobile에서 remote audio와 on-screen shortcuts를 강조
- 원격지원/IT 운영 기능이 넓다.

관찰:

- 사용자는 원격 화면만 원하는 것이 아니라 주변 작업을 함께 원한다: 깨우기, 재부팅, 파일 이동, 로그, 기록, 프린트, 오디오.
- 우리 개인/소규모 팀 제품에도 "세션 밖 액션"이 필요하다. 예: Wake, restart helper, diagnostics, recent logs.

참고:

- https://www.splashtop.com/features
- https://www.splashtop.com/multi-monitor-remote-computer-access-splashtop
- https://www.splashtop.com/blog/how-to-use-remote-desktop-on-ipad

### TeamViewer

강점:

- iPhone/iPad에서 PC/Mac/Linux/Android 등에 접속
- file transfer, chat, video/voice calls, WOL, multi-monitor, sound/video transmission
- enterprise remote support와 mobile support
- 2025년 Tia라는 intelligent agent를 발표했고, Session Insights 기반 AI 요약/분석 흐름을 강화

관찰:

- agent/AI는 이미 remote support 시장의 방향이다.
- 하지만 TeamViewer식 엔터프라이즈 AI는 IT support/documentation 중심이다.
- 우리는 개인 power user와 개발자용 "내 tailnet 안의 컴퓨터를 agent에게 잠깐 맡기는" 방향이 더 선명하다.

참고:

- https://www.teamviewer.com/en-us/solutions/use-cases/remote-desktop/iphone/
- https://www.teamviewer.com/en-us/products/remote/features/ai/session-insights-analytics/
- https://www.teamviewer.com/en-cis/global/company/press/2025/teamviewer-launches-tia-intelligent-agent-autonomous-it-support/

### AnyDesk / Zoho Assist / ConnectWise ScreenConnect

강점:

- attended support, unattended access, enterprise admin, audit, permissions
- support 조직용 workflow와 통합

관찰:

- 우리가 초기에 진입할 시장은 "고객 지원용 원격지원"이 아니다.
- 다만 다음 기능들은 개인용에도 유효하다: session code, view-only, approval, audit timeline, temporary access token.

참고:

- https://anydesk.com/en/downloads/ios
- https://support.anydesk.com/what-is-anydesk-for-ios-ipados-tvos

## 2.3 Enterprise VDI / workspace 앱

### Citrix Workspace for iOS

강점:

- Unicode keyboard, scancode input mode, keyboard layout sync
- external physical keyboard를 위한 모드 선택
- East-Asian language typing 개선을 문서에서 직접 언급
- shortcut 지원, Ctrl+Alt+Del toolbar, keyboard language change 표시
- microphone/camera, external webcam, multiple audio devices, adaptive audio
- client drive mapping, document scanner, session reliability, wireless trackpad

관찰:

- 키보드 입력 문제는 hobby VNC 앱만의 문제가 아니라 enterprise VDI에서도 큰 문제다.
- Citrix처럼 Unicode/scancode 모드를 노출하되, 우리 제품은 여기에 "Compose text", "Voice compose", "Paste image"라는 상위 워크플로를 더해야 한다.
- document scanner와 camera/webcam redirection은 이미지/파일 bridge 아이디어의 확장 후보가 된다.

참고:

- https://docs.citrix.com/en-us/citrix-workspace-app-for-ios/configure/peripheral-devices.html
- https://help-docs.citrix.com/en-us/citrix-workspace-app/ios/settings-menu.html

### Microsoft Windows App / Remote Desktop

강점:

- Windows/RDP native ecosystem
- 기업 Windows 365/AVD와 강하게 연결

관찰:

- iPad에서 일부 키 조합이 web app 안에서 인식되지 않는다는 피드백이 있다.
- remote app의 생산성은 "화면 품질"보다 shortcut fidelity와 text input fidelity에 크게 좌우된다.

참고:

- https://techcommunity.microsoft.com/t5/azurevirtualdesktop-feedback/remote-desktop-app-does-not-detect-certain-keyboard-combinations-for-web-apps/idi-p/3570762

## 2.4 Low-latency / creative / gaming 계열

대표:

- Jump Desktop Fluid
- Parsec
- Splashtop high-performance
- RustDesk

수요:

- 60fps 이상, frame pacing, 낮은 latency
- hardware codec, AV1/H.265/H.264
- game controller
- stylus/Apple Pencil
- USB/HID redirection
- virtual displays
- remote audio

관찰:

- 이 시장은 VNC만으로는 한계가 있다.
- 우리 MVP는 성능 경쟁을 피해야 한다.
- 다만 "개발/운영/agent 작업에 필요한 충분히 빠른 화면 + 압도적으로 좋은 입력 bridge"로 진입하면 된다.

참고:

- https://support.parsec.app/hc/en-us/articles/32381463419924-Feature-Matrix
- https://changelog.jumpdesktop.com/

## 2.5 Tailnet / self-hosted / privacy-first 흐름

Tailscale은 remote desktop을 공식적인 사용 사례로 다루고 있다.

관찰한 기능:

- RDP guide에서 port forwarding 없이 tailnet으로 접근하는 흐름을 설명
- MagicDNS로 device name 기반 접속 가능
- Services/endpoint collection에서 VNC/RDP endpoint launch를 제공
- iOS/macOS Shortcuts에서 Connect, Disconnect, Find Devices, Ping Devices, Send File 같은 action 제공
- RustDesk와 함께 쓰는 remote desktop guide도 제공

의미:

- "Tailscale-friendly"는 단순 마케팅 문구가 아니라, 실제로 원격 데스크톱 사용자의 setup pain을 줄이는 큰 축이다.
- Screens가 이미 Tailscale account linking을 제공하므로, 우리는 더 나아가 "diagnostics, endpoint discovery, Shortcuts automation, ACL awareness, Taildrop integration"까지 봐야 한다.

참고:

- https://tailscale.com/docs/solutions/access-remote-desktops-using-windows-rdp
- https://tailscale.com/docs/features/magicdns
- https://tailscale.com/docs/features/services
- https://tailscale.com/docs/features/mac-ios-shortcuts
- https://tailscale.com/blog/tailscale-rustdesk-remote-desktop-access

## 3. 사용자 수요 클러스터

## 3.1 안전한 접속: "포트포워딩 없이 내 컴퓨터에 들어가고 싶다"

수요:

- public IP/port forwarding 없이 접속
- 집/회사/서버/NAS/Raspberry Pi를 한 목록에서 보기
- 공유받은 tailnet device 접속
- 접속 안 될 때 원인을 바로 알기

기능 후보:

- Tailnet Device Radar
- MagicDNS-first profile
- endpoint discovery: VNC/RDP/SSH/HTTP
- ACL reachability check
- Tailscale status card
- "Open Tailscale" / "Connect Tailscale" Shortcut integration
- pre-flight remote access test

제품 기회:

- Tailscale을 별도 앱으로 두더라도, 사용자는 우리 앱 안에서 원인을 알아야 한다.
- 연결 진단을 잘 만들면 경쟁 제품보다 더 신뢰감이 생긴다.

## 3.2 입력 안정성: "키보드가 아니라 내가 입력한 글자가 들어가야 한다"

수요:

- 한글/영어 혼합 입력
- 일본어/중국어 IME
- 하드웨어 키보드 shortcut
- function keys, arrow keys, Esc, Ctrl+Alt+Del
- 앱별 shortcut fidelity
- 터미널에서 안전한 paste

근거:

- Screens는 software keyboard에서 Unicode characters를 보낸다고 문서화한다.
- Remotix는 Keyboard-through-Clipboard를 제공한다.
- Citrix는 Unicode/scancode input mode와 East-Asian typing 개선을 문서화한다.
- Microsoft RD Client 피드백에는 iPad에서 특정 web app shortcut이 잡히지 않는 사례가 있다.

기능 후보:

- Compose & Send
- Voice Compose
- Hardware Keyboard Mode: Unicode / scancode-like / shortcut-first
- Keyboard Doctor: 현재 입력 모드와 실패 가능성 표시
- Shortcut Palette: Ctrl+Alt+Del, F1-F12, Esc, Home/End, PageUp/PageDown
- Terminal Paste Mode
- Clipboard Preserve
- "Send as text" vs "Send as keys" 명시

제품 기회:

- 이 앱의 핵심이다.
- "문자 fidelity"를 성능/화질보다 앞에 둬야 한다.

## 3.3 음성 입력: "모바일에서 말로 원격 컴퓨터에 글을 넣고 싶다"

수요:

- iPhone/iPad 받아쓰기 사용
- 긴 문장, 메일, issue comment, 로그 검색어, 터미널 명령 입력
- 다국어 mixed speech
- 전송 전 검토

기능 후보:

- Voice Compose
- Push-to-talk
- spoken punctuation
- command mode
- "send and enter"
- voice macro
- sensitive dictation mode

제품 기회:

- 기존 원격 데스크톱 앱은 음성을 remote mic/audio 기능으로 보거나 부가 기능으로 둔다.
- 우리는 "remote text input"의 일부로 음성을 다룬다.

## 3.4 이미지/파일 bridge: "내 iPad의 자료를 원격 앱에 바로 붙이고 싶다"

수요:

- iPad screenshot을 원격 Slack/Jira/GitHub/Confluence에 붙여넣기
- Photos/Files 이미지를 원격 브라우저 upload field에 넣기
- PDF/로그/이미지를 원격 머신으로 보내기
- remote screenshot을 로컬 Files/Photos로 저장

근거:

- Remotix는 pasteboard sharing에 pictures/formatted text를 포함한다고 설명한다.
- Screens는 iPhone/iPad에서 Mac으로 file transfer와 drag/drop을 지원한다.
- Apple Remote Desktop은 shared clipboard로 text/images transfer와 file drag/drop을 지원한다.
- Splashtop/TeamViewer는 file transfer를 주요 기능으로 둔다.

기능 후보:

- Paste Image
- Paste Screenshot
- Save to Remote
- Upload to Remote
- Image compression and metadata stripping
- Taildrop Send File shortcut
- temporary file drop via host helper
- agent artifact paste

제품 기회:

- 이미지 붙여넣기는 pure VNC만으로 신뢰하기 어렵다.
- helper를 설치했을 때의 강력한 Pro 가치로 설계하는 것이 맞다.

## 3.5 iPad desk mode: "iPad를 진짜 원격 워크스테이션처럼 쓰고 싶다"

수요:

- external monitor
- Stage Manager
- Magic Keyboard / trackpad / physical mouse
- virtual display matching iPad resolution
- stable pointer, pixel-precise scroll
- app background 유지
- desk setup에서 shortcut 충돌 최소화

근거:

- Jump Desktop은 iOS virtual display, framerate/bandwidth controls, background runtime 설정을 추가했다.
- Citrix는 external monitor 관련 known issue와 session reliability, wireless trackpad, mouse 옵션을 다룬다.
- Reddit/지원 포럼에는 Stage Manager/external monitor/trackpad 문제와 shortcut 문제 피드백이 반복된다.

기능 후보:

- Desk Mode profile
- external display layout assistant
- hardware keyboard shortcut remapper
- pointer acceleration profiles
- virtual display via helper
- keep-awake/session background policy
- connection HUD: fps, latency, bandwidth, encoding

제품 기회:

- iPad Pro + Magic Keyboard + Tailscale 조합의 사용자는 이미 노트북 대체를 시도한다.
- 경쟁 제품은 많지만, "입력 문제 없는 desk mode" 포지션은 아직 선명하지 않다.

## 3.6 Unattended / headless reliability

수요:

- 재부팅 후 다시 접속
- 잠자기 방지
- WOL
- headless machine에서 cursor/display 유지
- display 없는 Mac mini/server에서 안정적인 해상도
- reconnect

근거:

- Tailscale/Screens 문서 모두 "Tailscale이 로그인 후 시작하면 재부팅 후 접속이 끊길 수 있음"을 다룬다.
- Splashtop은 remote wake/reboot를 주요 기능으로 둔다.
- Jump Desktop은 sleep override, persistent virtual displays, virtual mouse driver, headless setup 개선을 언급한다.

기능 후보:

- Availability Doctor
- Wake over LAN
- helper keep-awake
- reconnect policy
- headless display profile
- remote reboot warning: "Tailscale may not be available until login"

제품 기회:

- 원격 앱은 "접속되면 좋은 앱"보다 "필요할 때 반드시 붙는 앱"이 가치가 크다.

## 3.7 보안/프라이버시

수요:

- public internet 노출 회피
- credential protection
- Face ID/Touch ID
- view-only
- curtain/privacy mode
- audit log
- session-scoped access
- dangerous action approval

근거:

- Screens/Remotix/Apple Remote Desktop 모두 Curtain/Observe/Control 계열 기능을 제공한다.
- TeamViewer/Splashtop 계열은 enterprise logging, permissions, support workflow를 강조한다.
- Tailscale은 ACL과 endpoint visibility를 통해 누가 접근 가능한지 다룬다.

기능 후보:

- Face ID app lock
- sensitive session
- local-only history
- action timeline
- approval overlay
- temporary share token
- "who can reach this endpoint" display

제품 기회:

- agent handoff를 하려면 보안 UX가 먼저 있어야 한다.

## 3.8 Agent-ready remote session

수요:

- 사람이 보는 화면을 agent에게 넘기기
- agent 행동 감시
- 자동 요약/기록
- 위험 동작 승인
- agent가 텍스트/이미지/파일을 원격 앱에 붙여넣기

근거:

- TeamViewer는 Session Insights와 Tia intelligent agent를 발표했다.
- OpenAI/Anthropic computer-use 흐름은 화면/키보드/마우스 기반 automation을 일반화하고 있다.

기능 후보:

- Agent Handoff
- screenshot/click/scroll/key/text/image API
- approval gate
- action timeline
- session summary
- "take over" emergency button
- Tailnet-only bridge

제품 기회:

- TeamViewer는 IT support agent 쪽이다.
- 우리는 개인 개발자/운영자/agent-heavy user가 "내 원격 컴퓨터를 agent에게 맡기는" 쪽이다.

## 4. 차별화 가능한 제품 기능 후보

## 4.1 Remote Input Dock

하단 compose bar를 텍스트 입력창이 아니라 remote input dock으로 확장한다.

포함:

- Text
- Voice
- Image
- File
- Snippet
- Shortcut
- Secret
- Send behavior

차별점:

- 기존 앱의 toolbar/keyboard overlay보다 더 명확한 작업 단위다.
- 사용자는 "키를 누른다"가 아니라 "원격에 콘텐츠를 넣는다"고 느낀다.

## 4.2 Tailnet Device Radar

Tailscale 기반 장비/서비스 탐색 화면이다.

포함:

- MagicDNS device list
- VNC/RDP/SSH/HTTP endpoint discovery
- online/offline 상태
- ACL reachability
- latency ping
- last successful connection
- "why unavailable" diagnosis

차별점:

- Screens의 Tailscale 연동보다 더 operational하다.
- Tailscale Services alpha의 VNC/RDP launch 개념을 iOS 앱 UX로 가져온다.

## 4.3 Paste Anything Bridge

텍스트, 이미지, 파일, 스크린샷, 링크를 원격으로 주입하는 통합 기능이다.

Adapter:

- VNC clipboard
- Extended Clipboard
- OS paste shortcut
- Taildrop
- helper clipboard
- helper temp file
- helper native insert

차별점:

- "클립보드 동기화"가 아니라 "목적지에 넣기"라는 사용자 모델을 제공한다.

## 4.4 Voice Macro

음성으로 긴 문장과 명령을 만들어 remote input dock에 넣는다.

예시:

- "터미널에 입력하고 엔터"
- "마크다운 코드블록으로 감싸"
- "이슈 댓글로 보낼 문장"
- "방금 입력 취소"
- "줄바꿈 세 번"

차별점:

- 원격 오디오/마이크가 아니라 local dictation + remote injection.

## 4.5 Compatibility Doctor

서버/OS/앱별로 무엇이 되는지 표시한다.

검사:

- VNC handshake
- encoding
- clipboard text
- clipboard UTF-8
- image clipboard
- paste shortcut
- keyboard mode
- reconnect
- helper status
- Tailscale status

차별점:

- 원격 앱의 실패는 사용자가 디버깅하기 어렵다.
- 진단을 잘하면 power user에게 신뢰를 얻는다.

## 4.6 Agent Session Layer

에이전트용 screen/input API와 사용자 승인 UI다.

포함:

- observe
- approve
- interrupt
- action timeline
- session summary
- text/image/file injection

차별점:

- 일반 remote support AI가 아니라 "내 iPad에서 보고 있는 개인 tailnet machine을 agent에게 잠깐 맡김"이다.

## 5. 기능 우선순위 제안

## P0: MVP에서 반드시 증명

- Manual VNC profile
- MagicDNS host 접속
- 기본 connection doctor
- VNC viewer, pointer/touch controls
- Compose & Send
- UTF-8 clipboard paste
- OS별 paste shortcut
- clipboard preserve best-effort
- Voice Compose
- snippets
- shortcut palette
- Keychain + Face ID
- text injection compatibility log

## P1: Private Beta에서 강하게 차별화

- Tailnet inventory
- Tailscale Shortcuts integration
- endpoint discovery prototype
- Image Paste lab
- Photos/Files/Screenshot attachment UI
- file send via helper/Taildrop 실험
- external display / desk mode
- performance HUD
- reconnect policy
- WOL
- terminal paste mode

## P2: Pro/Helper 가치

- macOS helper
- reliable native text insert
- reliable image paste
- remote clipboard backup/restore
- temp file drop
- virtual display profile
- headless helper
- agent bridge
- action timeline
- session summary

## P3: 장기 확장

- Windows helper
- Linux helper
- RDP support
- SSH terminal companion
- PiKVM mode
- team sharing
- SSO/SCIM
- policy controls
- multi-user observe
- remote camera/document scanner bridge

## 6. 피해야 할 함정

1. "VNC viewer + 기능 몇 개"로 보이면 안 된다.
   - Screens/Jump/Remotix가 이미 강하다.

2. 초기에 성능 경쟁으로 들어가면 안 된다.
   - Jump Fluid, Parsec, Splashtop이 강한 영역이다.

3. helper 없이 모든 입력/이미지/파일 문제를 해결한다고 약속하면 안 된다.
   - VNC 서버별 clipboard/file/image 호환성이 다르다.

4. Tailscale VPN을 앱 안에 대체 구현하려 하면 안 된다.
   - iOS VPN/NetworkExtension 제약과 App Store 운영 리스크가 크다.

5. enterprise remote support 기능을 너무 빨리 따라가면 안 된다.
   - 초기 사용자는 개인 power user, 개발자, homelab, agent-heavy 사용자로 좁혀야 한다.

## 7. 제품 방향 업데이트

기존 사양의 방향은 맞다. 다만 리서치 후 더 선명해진 점은 다음이다.

### 기존 핵심

- Tailnet-native
- IME-first
- Voice Compose
- Image Paste
- Agent-ready

### 더 강하게 밀어야 할 표현

- Remote Input Dock
- Paste Anything Bridge
- Tailnet Device Radar
- Compatibility Doctor
- Desk Mode
- Agent Session Layer

### 한 줄 포지션

> 기존 VNC 앱은 화면을 잘 보여준다. 이 앱은 iPhone/iPad에서 만든 텍스트, 음성, 이미지, 파일, agent action을 Tailnet 안의 컴퓨터에 안전하게 넣는다.

## 8. 다음 리서치/검증 과제

1. Screens/Jump/Remotix를 실제 iPad에서 사용해 입력/이미지/파일 UX를 비교한다.
2. VNC server별 clipboard capability matrix를 만든다.
3. macOS Screen Sharing, RealVNC, TigerVNC, TightVNC, UltraVNC, x11vnc, wayvnc를 대상으로 텍스트/이미지/파일 테스트를 한다.
4. iOS dictation 결과가 compose bar에서 어떤 UX로 가장 자연스러운지 prototype을 만든다.
5. Tailscale Services API/endpoint collection을 앱에서 사용할 수 있는지 조사한다.
6. Taildrop을 image/file bridge fallback으로 쓸 수 있는지 검증한다.
7. macOS helper MVP의 permission surface를 정리한다.
8. agent bridge를 MCP/HTTP/local websocket 중 무엇으로 노출할지 검토한다.
