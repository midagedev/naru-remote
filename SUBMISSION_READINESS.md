# Naru Remote — App Store Submission Readiness

작성일: 2026-06-19 KST · 대상 버전: **1.0.0 (build 1)**

이 문서는 "내일이라도 앱스토어에 제출할 수 있는 수준"을 목표로 한
릴리스 점검표다. 코드/에셋으로 해결 가능한 항목은 이 브랜치에서
처리했고, Apple 계정·인증서·App Store Connect가 필요한 항목은 사람이
해야 할 단계로 분리해 명시한다.

## 1. 이번 브랜치에서 처리한 출시 게이트

| 항목 | 이전 | 변경 후 | 비고 |
| --- | --- | --- | --- |
| **App icon** | ❌ 에셋 카탈로그 자체가 없음 (업로드 불가) | ✅ `Assets.xcassets/AppIcon.appiconset` 1024² 불투명 PNG | `scripts/generate-app-icon.swift`로 재생성 가능. 브랜드 teal 그라디언트 + 나루(ferry) 마크 |
| **Marketing version** | `0.1.0` | ✅ `1.0.0` | `project.yml` |
| **Accent color** | 기본 iOS 블루 (에셋 없음) | ✅ 브랜드 teal `AccentColor` (light `#2D7D77` / dark `#63C7BF`) | BRANDING.md §7 토큰과 일치 |
| **Launch screen** | 빈 `UILaunchScreen {}` (흰 플래시) | ✅ `LaunchBackground` 컬러셋 (canvas, light/dark) | 다크모드 진입 시 흰 깜빡임 제거 |
| **Export compliance** | 미선언 (업로드마다 수동 질문) | ✅ `ITSAppUsesNonExemptEncryption: false` | VNC DES/Apple-DH는 표준·면제 암호화 |
| **First-run UX** | 빈 홈이 split-view detail에 묻혀 stray `<` back 버튼 + 빈 사이드바로 가는 dead-end | ✅ 빈 홈을 풀스크린 root로 승격 (back 버튼/이중 빈 상태 제거) | `NaruRemoteAppShell.body` |

### 검증

- `swift test` — **green** (코어/앱/페이크 RFB; 라이브 Mac VNC 스트리밍 테스트 포함 failures=0/5)
- iPhone 17 Pro 시뮬레이터 빌드 — **green**
- iPad Pro 13" (M5) 시뮬레이터 빌드 — **green** (헌법 §VI iPad graceful)
- `NaruRemoteLaunchUITests` 빈 홈/프로필 추가 플로우 — green
- 라이트/다크 스크린샷 감사 — `artifacts/release-audit/` (contact-light.png, contact-dark.png)

## 2. 화면 인벤토리 (감사 완료)

| # | 화면 | 상태 |
| --- | --- | --- |
| 1 | First run (Add a computer) | ✅ 풀스크린 단일 CTA |
| 2 | Connections 그리드 (프로필 카드 + reachability/preview) | ✅ |
| 3 | Profile editor (add/edit, 검증·reachability 테스트) | ✅ |
| 4 | Diagnostics (DNS/TCP/RFB/auth 단계 + 안전 export) | ✅ |
| 5 | Live session viewport (Metal 렌더, zoom-fill, trackpad/direct) | ✅ |
| 6 | Remote Input Dock (Compose & Send / Direct keystroke) | ✅ |
| 7 | Incoming clipboard 리뷰 배너 | ✅ |
| 8 | Helper video / PiP Watch 레이어 (옵션) | ✅ (PiP는 watch-only, 실기기 검증 잔여) |

## 3. 제출 전 사람이 해야 할 단계 (Apple 계정 필요 — 코드로 불가)

1. ~~**서명/팀**: Apple Developer Program 가입 후 `project.yml`의 app 타깃에
   `DEVELOPMENT_TEAM` + 자동 서명 설정.~~ ✅ **해소(2026-07-05)** — `project.yml`
   app/UITests/Benchmark 타깃에 `DEVELOPMENT_TEAM: XEF9KH7N43` +
   `CODE_SIGN_STYLE: Automatic` 반영. 실기기 서명은 같은 팀으로 실증됨(§5 참조).
2. **App Store Connect 레코드 생성**: 번들 ID `com.naruremote.app` 등록,
   앱 이름 `Naru Remote` 예약(브랜딩 문서상 이름 충돌 가능성 확인 권장),
   subtitle `Private Network Remote Desktop`.
3. **스크린샷 업로드**: 6.9"/6.7" iPhone + 13" iPad 세트. `artifacts/release-audit/`
   캡처를 베이스로 마케팅 프레임 작업(시뮬레이터 캡처는 시안용).
4. **개인정보 처리방침 URL**: App Store Connect 필수. 앱은 사용자 데이터를
   수집/추적하지 않음(`PrivacyInfo.xcprivacy` = no tracking, no collection) —
   그 사실을 반영한 정책 페이지 1장이면 충분.
5. **연령 등급 / 카테고리**: Productivity(또는 Utilities) 추천.
6. **앱 설명 텍스트**: BRANDING.md의 한/영 설명 문장 재사용 가능.
7. **TestFlight 내부 테스트** 1회 후 심사 제출 권장.

## 4. 심사 시 유의 (제품 특성)

- **로컬 네트워크 권한**: `NSLocalNetworkUsageDescription` 설정됨. 심사에서
  사설망 VNC 용도임을 설명.
- **Background audio 모드**: PiP Watch 때문에 선언됨 — 리뷰 노트에 PiP 용도 명시.
- **Tailscale 비제휴**: 설명/스크린샷에서 Tailscale 공식 제휴로 오인될 표현 금지
  (헌법 §II).

## 5. 2026-07-05 갱신 — 빠른 1.0 출시 재점검

2026-06-19 이후 이동한 항목을 현재 리포지토리 기준으로 재감사했다.

### 5.1 코드/에셋 게이트 재확인 (여전히 존재)

| 항목 | 상태 | 위치 |
| --- | --- | --- |
| App icon (1024² 불투명) | ✅ | `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |
| AccentColor (브랜드 teal) | ✅ | `Assets.xcassets/AccentColor.colorset` |
| LaunchBackground 컬러셋 | ✅ | `Assets.xcassets/LaunchBackground.colorset` (`UILaunchScreen.UIColorName`) |
| Export compliance | ✅ | `project.yml` `ITSAppUsesNonExemptEncryption: false` |
| **PrivacyInfo.xcprivacy** | ✅ 이미 존재·번들 포함 | `NaruRemote/iOSApp/PrivacyInfo.xcprivacy` (앱 타깃 소스 디렉터리 → 리소스로 자동 포함). no-tracking / no-collection / no-required-reason-API 선언 |
| 마케팅 버전 | ✅ `1.0.0 (build 1)` | `project.yml` |
| 스토어 리스팅 초안 | ✅ (PR #490) | `APP_STORE_LISTING.md` (이름/부제/키워드/설명 한·영) |
| 풀스크린 빈 홈 + 브랜드 폴리시 | ✅ (#489/#492) | 화면 인벤토리 §2 유효 |

### 5.2 실기기 서명 실증 (§3.1 차단 해소)

- 물리 iPhone 15 Pro Max(UDID `00008130-000C15D80C43001C`)에서
  `DEVELOPMENT_TEAM=XEF9KH7N43 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates`로
  **build + test 성공**. 이에 따라 `project.yml` app/UITests/Benchmark 타깃에
  동일 설정을 고정했다. Automatic 스타일이라 시뮬레이터 빌드는 그대로 동작.

### 5.3 실기기 helper-video 게이트 최초 통과 (합성 소스)

- `artifacts/benchmarks/2026-07-05-physical-iphone-release-hud-and-helper-gate-summary.md`
  참조. Release 빌드, iPhone 15 Pro Max, `NaruHelper --video-listen
  --video-source synthetic-encoded`(Screen Recording 권한 불요 변형), 120s
  sustained 게이트 `"status": "passed"`. 종전 `xcode-account-missing` /
  `ios-provisioning-profile-missing` 차단이 해소됨(spec 007 T030 잔여 리스크).
- per-stage HUD 실측 결과 폰 CPU/GPU/입력은 병목 아님(지배 항목 = network/server
  read). VNC visual path fps 천장은 Apple Screen Sharing 서버 측(~5fps대)으로 재증명.
- 잔여: (a) 실화면(ScreenCaptureKit) 소스 게이트는 Screen Recording 권한 부여 후
  별도 실행, (b) PiP Watch 렌더러/컨트롤러 실기기 검증(§2 #8).

### 5.4 남은 사람 단계 (App Store Connect — 코드로 불가)

1. **App Store Connect 레코드 생성**: 번들 ID `com.naruremote.app` 등록, 앱 이름
   `Naru Remote` 예약, 부제 `Private Network Remote Desktop`. 메타데이터는
   `APP_STORE_LISTING.md` 그대로 붙여넣기.
2. **스크린샷 업로드**: 6.9"/6.7" iPhone + 13" iPad 세트. `artifacts/release-audit/`
   캡처 기반 마케팅 프레임.
3. **개인정보 처리방침 URL**: 필수. 앱은 no-tracking/no-collection
   (`PrivacyInfo.xcprivacy`) — 그 사실을 반영한 정책 페이지 1장.
4. **연령 등급 / 카테고리**: Productivity(주) / Utilities(부), 4+.
5. **TestFlight 내부 테스트** 1회 후 심사 제출.

> 요약: 코드/서명/에셋 게이트는 이 리포지토리에서 모두 닫혔다. 남은 것은
> App Store Connect 계정 작업(레코드·스크린샷·정책 URL·TestFlight)뿐이다.
