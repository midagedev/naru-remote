# Naru Remote 1.0 — Launch & Promotion Kit

> **Point-in-time record, 2026-07-12.** This documented the run-up to the
> **first** App Store submission — `1.0.0 (build 1)`. The app has shipped since
> and is well past that build, so read this as how the launch was prepared, not
> as a description of anything outstanding. Current work is queued in
> `NEXT_STEPS.md`; each feature's truth is the **Status** line of its
> `specs/<n>-<slug>/spec.md`.

작성일: 2026-07-12 KST · 대상: **1.0.0 (build 1)**, App Store Connect Apple ID `6790122006`

이 문서는 심사 제출 직후~공개 첫 주에 그대로 복사해 쓰는 홍보 자료 모음이다.
메타데이터 원본은 `docs/release/APP_STORE_LISTING.md`, 브랜드 근거는 `docs/BRANDING.md`,
제출 상태는 `docs/release/SUBMISSION_READINESS.md`를 따른다.

## 0. 출시 전 남은 클릭 (파운더 전용, 순서대로)

1. **스크린샷 업로드** — App Store Connect → 1.0.0 → 미디어.
   원본: `artifacts/app-store/20260712-211315/final-iphone/` (1284×2778, 5장),
   `final-ipad/` (2752×2064, 5장). 순서는 파일명 순서 그대로.
2. **계정 선언** — EU DSA(트레이더 여부) + 대한민국 규정 선언 (App Store
   Connect → 비즈니스/계약).
3. **최종 심사 제출** — Review Notes는 이미 저장돼 있음(사설망 재현 경로 포함).

## 1. 메시지 코어 (모든 채널 공통)

- **Tagline**: `Type here. Work there.`
- **One-liner (EN)**: A remote desktop for your private network that gets
  one thing right other VNC viewers miss on a phone: your text actually
  arrives — Korean, CJK, emoji, long mixed sentences.
- **One-liner (KO)**: 사설망용 원격 데스크톱. 폰에서 완성한 한글·다국어
  문장이 원격 화면에 "그대로" 들어가는 것 하나에 집중했습니다.
- **창업자 스토리 훅**: "침대에서 iPhone으로 내 Mac의 AI 코딩 CLI를 몇
  시간씩 굴린다. 기존 VNC 뷰어로는 한글 입력이 깨져서 이 앱을 만들었다."
- 지켜야 할 선 (헌법 §II / §5.4):
  - Tailscale은 "함께 잘 동작하는 예시"로만. **비제휴 고지 문구를 모든
    영문 포스트 말미에 유지**: "Naru Remote is an independent app and is
    not affiliated with Tailscale."
  - 성능은 "원활/CRD급" 같은 표현 금지 (품질 게이트 Green 전). 사실만:
    로컬 컴포즈, Direct 전용 키보드, 진단, Keychain/no-tracking.

## 2. X/Twitter 런칭 스레드

### 한국어 (5개)

1. Naru Remote 1.0을 App Store에 출시했습니다. 사설망(Tailscale·VPN·LAN)
   안의 Mac·Linux에 붙는 원격 데스크톱인데, 딱 하나에 집중했습니다 —
   **폰에서 친 한글이 원격 화면에 그대로 들어가는 것.** #NaruRemote
2. 왜 만들었나: 저는 iPhone으로 Mac의 AI 코딩 CLI를 원격으로 씁니다.
   기존 VNC 뷰어는 한글·이모지를 raw key event로 흘려보내다 깨뜨립니다.
   Naru는 문장을 **폰에서 완성(IME 로컬 컴포즈)한 뒤** 완성본을 전송합니다.
3. 터미널·에디터엔 Direct 모드: Esc/Tab/Ctrl/화살표/펑션키 + 스티키
   모디파이어를 갖춘 전용 키보드. IME가 꺼진 모드라는 걸 배지로 항상
   표시합니다.
4. 폰 우선 설계: 핀치 줌-필로 터미널 글자를 읽고, 트랙패드 모드의 실제
   커서로 조작합니다. 연결이 안 되면 DNS→TCP→RFB→인증→첫 프레임 중
   어디서 끊겼는지 진단이 알려줍니다.
5. 비밀번호는 iOS Keychain에만, 추적·수집 없음(no-tracking 라벨).
   무료입니다. → App Store 링크

### English (5 tweets)

1. Naru Remote 1.0 is on the App Store. A remote desktop for machines on
   your private network — built around the one thing phone VNC viewers get
   wrong: **your text actually arriving.** Korean, CJK, emoji, long mixed
   sentences.
2. Why: I drive an AI coding CLI on my Mac from my iPhone for hours.
   Other viewers stream fragile raw key events and IME text shatters.
   Naru lets you compose with your normal keyboard and IME *locally*,
   then sends the finished text.
3. Terminal person? Direct mode is a purpose-built on-screen keyboard:
   Esc, Tab, Ctrl, arrows, function keys, sticky modifiers — with a clear
   "IME off" badge so you always know which mode you're in.
4. Phone-first: pinch and zoom-fill so terminal text stays readable, a
   trackpad mode with a real cursor, and staged diagnostics that tell you
   exactly where a connection failed (DNS → TCP → RFB → auth → first frame).
5. Passwords live in the iOS Keychain. No tracking, no data collection.
   Free. Works great over Tailscale, a VPN, or your LAN.
   (Independent app — not affiliated with Tailscale.) → App Store link

## 3. GeekNews (news.hada.io) 제출

- **제목**: iPhone에서 한글 입력이 깨지지 않는 VNC 원격 데스크톱을 만들어
  출시했습니다 (Naru Remote)
- **본문 요약**:
  아이폰으로 사설망 안의 Mac/Linux에 접속해 AI 코딩 CLI·터미널을 오래
  쓰는 사람 입장에서 만든 VNC 뷰어입니다. 기존 뷰어들은 한글/CJK를 VNC
  KeyEvent로 흘려보내는데, macOS Screen Sharing 기준 유니코드 keysym이
  실제로는 입력되지 않는 것을 실측으로 확인했습니다. 그래서 문장을 폰에서
  IME로 완성한 뒤 완성본을 전달하는 "로컬 컴포즈"를 1차 경로로 설계했고,
  터미널용 Direct 모드(전용 키보드 + 특수키/스티키 모디파이어), 단계별
  연결 진단(DNS/TCP/RFB/인증/첫 프레임), Keychain 전용 비밀번호 저장,
  no-tracking을 갖췄습니다. 1.0은 전부 무료입니다. 피드백 환영합니다.

## 4. Disquiet 프로덕트 등록

- **한 줄 소개**: 폰에서 완성한 한글이 원격 Mac에 그대로 들어가는
  사설망 전용 원격 데스크톱
- **메이커 스토리**: 침대에서 iPhone으로 Mac의 AI 에이전트를 굴리다
  한글 입력이 깨지는 문제로 직접 만든 앱. "여기서 쓰고, 저기서 일한다
  (Type here. Work there.)"라는 원칙으로 입력 신뢰성 하나에 집중.
- 스크린샷: `final-iphone/` 5장 재사용.

## 5. Reddit (영문, 자기홍보 규칙 준수 — 각 서브레딧 규칙 먼저 확인)

- 대상: r/selfhosted, r/vnc, r/iosapps (r/Tailscale은 비제휴 고지 필수 +
  커뮤니티 규칙상 셀프프로모 허용 여부 확인 후)
- **제목 (r/selfhosted)**: I built a VNC client for iPhone that composes
  CJK/multilingual text locally instead of streaming key events (free, no
  tracking)
- **본문 골자**: 문제(phone VNC + IME text = broken) → 실측 근거(macOS
  Screen Sharing이 Unicode keysym을 무시) → 해법(local compose 1차 경로,
  Direct raw-key 모드는 명시적 폴백) → 프라이버시(Keychain, 진단은
  화면/입력 내용 미포함) → 무료 → 비제휴 고지.

## 6. Product Hunt (선택, 공개 첫 주 내)

- **Name**: Naru Remote
- **Tagline (60자)**: Type here. Work there. A private-network remote desktop.
- **First maker comment**: 위 영어 스레드 1–2번 트윗을 합쳐 서술형으로.
  마지막에 "Ask me anything about VNC keysyms and why IME input breaks on
  every other viewer" 같은 기술 훅을 넣는다.

## 7. 에셋 인벤토리

| 에셋 | 위치 |
| --- | --- |
| 제출용 iPhone 스크린샷 5장 (1284×2778) | `artifacts/app-store/20260712-211315/final-iphone/` |
| 제출용 iPad 스크린샷 5장 (2752×2064) | `artifacts/app-store/20260712-211315/final-ipad/` |
| 앱 아이콘 원본/실증 (Between Worlds) | `artifacts/branding/2026-07-12/` |
| UX 상태별 라이트/다크 캡처 (SNS용 재료) | `artifacts/screenshots/ux-audit/` |
| 서포트/프라이버시 사이트 | `https://midagedev.github.io/naru-remote-support/` |
| 스토어 메타데이터 전문 | `docs/release/APP_STORE_LISTING.md` |

## 8. 공개 당일 런북

1. 심사 승인 확인 → 수동 출시 버튼 (또는 자동 출시 설정 확인).
2. App Store 링크 확보 → 이 문서의 모든 `→ App Store 링크` 자리에 삽입.
3. 게시 순서: X(KO) → X(EN) → GeekNews → Disquiet → (다음날) Reddit →
   (첫 주 내) Product Hunt. 같은 날 전부 쏘지 말 것 — 채널별 반응을 보고
   메시지를 다듬는다.
4. 첫 48시간: 리뷰·크래시(App Store Connect Analytics)와 커뮤니티 댓글
   모니터링. 재현 가능한 버그 제보는 `NEXT_STEPS.md`에 즉시 기록.
