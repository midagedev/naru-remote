# Naru Remote — App Store Submission Readiness

작성일: 2026-07-12 KST · 대상 버전: **1.0.0 (build 1)**

이 문서는 "내일이라도 앱스토어에 제출할 수 있는 수준"을 목표로 한
릴리스 점검표다. 코드/에셋으로 해결 가능한 항목은 이 브랜치에서
처리했고, Apple 계정·인증서·App Store Connect 실행 상태도 아래에 함께
기록한다.

## 1. 이번 브랜치에서 처리한 출시 게이트

| 항목 | 이전 | 변경 후 | 비고 |
| --- | --- | --- | --- |
| **App icon** | ❌ 에셋 카탈로그 자체가 없음 (업로드 불가) | ✅ `Assets.xcassets/AppIcon.appiconset` 1024² 불투명 PNG | `Between Worlds` 마크. imagegen 원본을 보관하고 `scripts/generate-app-icon.swift`로 1024² opaque sRGB 정규화 |
| **Marketing version** | `0.1.0` | ✅ `1.0.0` | `project.yml` |
| **Accent color** | 기본 iOS 블루 (에셋 없음) | ✅ 브랜드 Signal Blue `AccentColor` (light `#2D7DFF` / dark `#5B9BFF`) | BRANDING.md §7 토큰과 일치 |
| **Launch screen** | 빈 `UILaunchScreen {}` (흰 플래시) | ✅ `LaunchBackground` 컬러셋 (canvas, light/dark) | 다크모드 진입 시 흰 깜빡임 제거 |
| **Export compliance** | 미선언 (업로드마다 수동 질문) | ✅ `ITSAppUsesNonExemptEncryption: false` | VNC DES/Apple-DH는 표준·면제 암호화 |
| **First-run UX** | 빈 홈이 split-view detail에 묻혀 stray `<` back 버튼 + 빈 사이드바로 가는 dead-end | ✅ 빈 홈을 풀스크린 root로 승격 (back 버튼/이중 빈 상태 제거) | `NaruRemoteAppShell.body` |

### 검증

- `swift test` — **green** (코어/앱/페이크 RFB; 라이브 Mac VNC 스트리밍 테스트 포함 failures=0/5)
- iPhone 17 Pro 시뮬레이터 빌드 — **green**
- iPad Pro 13" (M5) 시뮬레이터 빌드 — **green** (헌법 §VI iPad graceful)
- `NaruRemoteLaunchUITests` 빈 홈/프로필 추가 플로우 — green
- 라이트/다크 스크린샷 감사 — `artifacts/release-audit/` (contact-light.png, contact-dark.png)

## 2. 화면 인벤토리 (코드 확인; 현재 변경 재캡처 잔여)

| # | 화면 | 상태 |
| --- | --- | --- |
| 1 | First run (Add a computer) | ✅ 풀스크린 단일 CTA |
| 2 | Connections 그리드 (프로필 카드 + reachability/preview) | ✅ |
| 3 | Profile editor (add/edit, 검증·reachability 테스트) | ✅ |
| 4 | Diagnostics (DNS/TCP/RFB/auth 단계 + 안전 export) | ✅ |
| 5 | Live session viewport (Metal 렌더, zoom-fill, trackpad/direct) | ✅ |
| 6 | Remote Input Dock (Type / Compose) | ✅ 코드·단위 테스트, 키보드-up XCUITest 재실행 잔여 |
| 7 | Incoming clipboard 리뷰 배너 | ⚠️ **프로덕션 세션에서 비활성** — 배너·리뷰 UI와 단위 테스트는 완비지만, 설치 앱이 쓰는 스트리밍 경로에서는 `startIncomingClipboardReceive`가 호출되지 않는다(`NaruRemoteAppModel.swift:3765-3786` 주석의 task #30: 클립보드 리더와 프레임 펌프가 같은 `NWConnection`에서 경쟁 → 단일 RFB 멀티플렉서 전까지 의도적 차단). 2026-08-17 코드 감사 P1-4. 스토어 카피·스크린샷에서 원격→로컬 클립보드 리뷰를 주장하지 말 것 |
| 8 | Helper video / PiP Watch 레이어 (옵션) | ✅ (PiP는 watch-only, 실기기 검증 잔여) |

## 3. App Store Connect 실행 현황

1. ~~**서명/팀**: Apple Developer Program 가입 후 `project.yml`의 app 타깃에
   `DEVELOPMENT_TEAM` + 자동 서명 설정.~~ ✅ **해소(2026-07-05)** — `project.yml`
   app/UITests/Benchmark 타깃에 `DEVELOPMENT_TEAM: XEF9KH7N43` +
   `CODE_SIGN_STYLE: Automatic` 반영. 실기기 서명은 같은 팀으로 실증됨(§5 참조).
2. ~~**App Store Connect 레코드 생성**~~ ✅ **완료(2026-07-12)** — 번들 ID
   `com.naruremote.app`, Apple ID `6790122006`, 이름 `Naru Remote`, 부제
   `Private Network Remote Desktop`.
3. **스크린샷**: ✅ iPhone 1284×2778 및 iPad 2752×2064를 5장씩 생성·시각
   검증했다. 정확한 제출 파일은 `artifacts/app-store/20260712-211315/`에
   보존했다. App Store Connect 웹 슬롯 업로드만 남았다.
4. ~~**개인정보 처리방침 / App Privacy**~~ ✅ 공개 정책 URL을 연결했고
   no-tracking/no-collection 라벨을 게시했다.
5. ~~**연령 등급 / 카테고리 / 가격**~~ ✅ Productivity(주), Utilities(부),
   4+, Free, 175개 국가 또는 지역으로 설정했다.
6. ~~**메타데이터 / Review Notes**~~ ✅ `APP_STORE_LISTING.md`의 영문 설명,
   키워드, 지원 URL과 사설망 심사 메모를 저장했다.
7. ~~**Distribution 검증**~~ ✅ Release archive의 버전/번들 ID/암호화 선언,
   코드 서명, Privacy manifest·현지화 포함 여부와 테스트 표식 부재를 검증했다.
   build 1 업로드 및 Apple 처리 후 버전 1.0.0 연결·저장까지 완료했다. 남은 것은
   스크린샷 웹 업로드, 계정의 EU DSA·대한민국 규정 선언과 최종 심사 제출이다.

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
| AccentColor (브랜드 Signal Blue) | ✅ | `Assets.xcassets/AccentColor.colorset` |
| LaunchBackground 컬러셋 | ✅ | `Assets.xcassets/LaunchBackground.colorset` (`UILaunchScreen.UIColorName`) |
| Export compliance | ✅ | `project.yml` `ITSAppUsesNonExemptEncryption: false` |
| **PrivacyInfo.xcprivacy** | ✅ 이미 존재·번들 포함 | `NaruRemote/iOSApp/PrivacyInfo.xcprivacy` (앱 타깃 소스 디렉터리 → 리소스로 자동 포함). no-tracking / no-collection / no-required-reason-API 선언 |
| 마케팅 버전 | ✅ `1.0.0 (build 1)` | `project.yml` |
| 스토어 리스팅 초안 | ✅ (PR #490) | `APP_STORE_LISTING.md` (이름/부제/키워드/설명 한·영) |
| 풀스크린 빈 홈 + 브랜드 폴리시 | ✅ (#489/#492) | 화면 인벤토리 §2 유효 |

### 5.2 실기기 서명 실증 (§3.1 차단 해소)

- 물리 iPhone 15 Pro Max에서
  `DEVELOPMENT_TEAM=XEF9KH7N43 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates`로
  **build + test 성공**. 이에 따라 `project.yml` app/UITests/Benchmark 타깃에
  동일 설정을 고정했다. Automatic 스타일이라 시뮬레이터 빌드는 그대로 동작.
- 이 증거에 더해 2026-07-12 App Store distribution archive와 자동 배포 서명,
  App Store Connect upload가 성공했다. build 1은 Apple 처리 후 버전 1.0.0에
  연결·저장되었다.

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

### 5.3.1 2026-07-12 UI 재감사 상태

- iPhone 17 Pro simulator 앱 빌드와 새 접근성/레이아웃 단위 테스트는 통과했다.
- 기존 screenshot에서 발견한 dark clipboard 대비, 키보드 AutoFill과 mode
  control 충돌, grid 복귀, VoiceOver control auto-hide를 코드로 수정했다.
- 최신 빌드의 light first-run, dark active-session/Compose, dark incoming
  clipboard 상태를 simulator runtime에서 직접 재검사했다. 상세 판정은
  `artifacts/benchmarks/2026-07-12-release-readiness-ui-performance-summary.md`.
- 최종 `swift test`: 1,511 executed / 26 skipped / 0 failures. 구성된 live Mac
  RFB smoke도 5/5 통과했다.
- 현재 로컬 XCUITest runner는 AX loaded notification 단계에서 test body 실행 전
  중단/정지한다. 따라서 변경 후 light/dark/keyboard-up screenshot 재캡처와 실제
  VoiceOver traversal은 제출 전 잔여 증거다.

### 5.3.2 2026-07-12 브랜드 자산 갱신

- 기존 `3 node + connector + input slot` 도식을 형이상학적 `Between Worlds`
  아이콘으로 교체했다. 두 graphite plane 사이의 Signal-Blue seam과 경계를
  건너는 off-white thought가 local composition → remote action을 상징한다.
- shipping PNG는 1024×1024, 8-bit RGB, opaque이며 Asset Catalog 빌드 경고가
  없다. imagegen 원본·최종 prompt·light/dark 및 SpringBoard 실증은
  `artifacts/branding/2026-07-12/`에 보관했다.
- iPhone 17 Pro / iOS 26.2에서 build+run, App Library 검색 결과의 실제 아이콘
  크기, light/dark first-run 화면을 시각 검증했다. 집중 launch XCUITest도 1/1
  통과했다.
- Launch Screen은 별도 로고 splash를 추가하지 않았다. adaptive
  `LaunchBackground`가 첫 실제 프레임과 정확히 이어지는 현재 구성이 Apple의
  launch guidance와 returning-user 전환에 더 적합하다.

### 5.4 제출 전에 남은 제품 품질 게이트

아래 항목은 App Store의 기계적 업로드 요건과 별개다. 저장소의
`PRODUCT_QUALITY_TARGETS.md`가 정의한 Green 판정 전에는 공개 1.0을
"원활/CRD급"으로 표현하지 않는다.

1. `specs/007`의 실제 ScreenCaptureKit 화면 helper-video 물리 iPhone 게이트.
2. `specs/009` T021–T024: 200자 혼합 입력 10회, per-commit p95,
   Unicode-KeyEvent 회귀, 30분 지속 Live 입력/thermal 점검.
3. 전체 30분 iPhone 세션에서 helper RSS/thermal, Compose, trackpad, PiP
   enter/leave와 VNC fallback을 함께 확인.

### 5.5 App Store Connect 제출 실행 기록

1. ✅ 앱 레코드와 명시적 App ID 생성.
2. ✅ 제출용 iPhone/iPad 원본 확보 — 2026-08-18에 스토어 전용 상태로 전면
   재촬영했다(아래 #10). iPhone 5장, iPad 4장을 업로드한다.
3. ✅ 공개 Support/Privacy 사이트 배포 및 URL 연결.
4. ✅ Productivity/Utilities, 글로벌 4+, Free, 175개 지역 설정.
5. ✅ no-tracking/no-collection App Privacy 라벨 게시.
6. ✅ 실제 개인 VNC 비밀번호 없이 재현 경로와 개인정보 경계를 Review Notes에
   기록.
7. ✅ Distribution archive 검증, App Store Connect build 1 업로드·처리,
   버전 1.0.0 연결·저장.
8. ✅ **build 2 업로드·처리 완료(2026-08-18)** — build 1은 2026-07-12 빌드라
   spec 011(Type/Compose 2모드 + 액세서리 스트립) · 012(외부 마우스/트랙패드,
   스트립 홀드 리핏·⌃C·IME flush 장벽, iPad 독 캡) · 013(실패 복구 화면 제거)이
   전혀 들어 있지 않았다. `CURRENT_PROJECT_VERSION`을 2로 올려 Release 아카이브
   → App Store 서명 export → `altool --validate-app`(VERIFY SUCCEEDED) →
   `--upload-app`(UPLOAD SUCCEEDED) 순으로 올렸고, App Store Connect API 조회로
   `build 2 processingState=VALID`을 확인했다. 아카이브 검증 실측: 버전 1.0.0 /
   build 2, 번들 `com.naruremote.app`, 팀 XEF9KH7N43, `PrivacyInfo.xcprivacy`
   포함, `ITSAppUsesNonExemptEncryption=false`, MinimumOSVersion 17.0,
   `NARU_TEST_*` 표식 없음. 자격증명은 환경변수 간접 참조로만 다뤘다.
9. ⏳ **남은 것 (계정 소유자 웹 작업)**: TestFlight 내부 테스터 그룹에 build 2
   배정 → 실기 검증 → 스토어 스크린샷 웹 업로드 → EU DSA 거래자 선언·대한민국
   규정 선언 → 심사 제출.
10. ✅ **스토어 스크린샷 재촬영 완료(2026-08-18)**: 폐기된 Direct 모드 컷을
   포함한 2026-07-12 세트와, 감사용 상태라 절반만 쓸 수 있던 첫 재촬영을 모두
   버리고 **스토어 전용 상태 5종**을 새로 만들어 찍었다 —
   ① 호스트 목록(8대, 전부 reachable + 데스크톱 미리보기) ② 라이브 세션
   ③ 한글 초안이 든 Compose 에디터 + 액세서리 스트립 ④ 라이브 세션 위 Fn 확장
   ⑤ 첫 프레임까지 전부 통과한 진단. iPhone 6.9"(1320×2868, 슬롯 2는 가로
   2868×1320) / iPad 13"(2752×2064), 라이트·다크 각 10장이
   `artifacts/screenshots/store/`에 있다. 절차와 프레이밍 근거는
   `docs/store-screenshots.md`. **업로드는 다크 세트로 한다** — 라이트 세트는
   독 대비 결함(#11, 2026-08-19 수정)이 있던 상태로 찍힌 것이라, 라이트로
   올리려면 재촬영이 필요하다.
   `saveStoreScreen`이 App Store Connect가 거부할 파일을 캡처 단계에서 바로
   실패시킨다 — 허용되지 않는 픽셀 크기, 그리고 **알파 채널**. 회전 캡처가
   `UIGraphicsImageRenderer`를 지나는데 P3 기기에서는 `format.opaque`가 무시돼
   프리멀티플라이드 알파가 남았고(가로·iPad 컷 전부 RGBA로 나왔다), 알파 없는
   비트맵으로 재인코딩해 막았다. iPad는 진단 시트가 마지막 행을 잘라내므로
   슬롯 1~4만 올린다(`NEXT_STEPS.md` P1).
11. ✅ **라이트 모드 독 대비 결함 — 수정됨(2026-08-19)**: 라이브 세션 위 독이
   `.ultraThinMaterial`이라 대비가 원격 화면 픽셀에 따라 정해졌고(어두운
   데스크톱 + 라이트 테마에서 약 2:1), 상태 문구는 `.secondary`였다. 원격 화면
   위에 뜨는 크롬(독·상태줄·몰입형 컨트롤 바)은 이제 `remoteChromeSurface()`로
   Surface Raised를 불투명하게 칠하고 텍스트는 브랜드 토큰을 쓴다 — 재질은
   게이트할 수 없지만 토큰은 계산할 수 있기 때문이다. 팔레트는 `NaruPalette`로
   데이터화됐고 `NaruColorContrastTests`가 앱이 만드는 모든 (텍스트, 배경)
   조합을 두 테마에서 검사한다(본문 4.5:1). 그 과정에서 Light Muted Ink가
   독 위 4.41:1로 AA 미달임이 드러나 `#5F6773`으로 조정됐다(`BRANDING.md` §7).

> 요약: 코드/에셋과 UI 제출 자료는 Green이고 최종 `swift test`는 1,565 tests,
> 26 skipped, 0 failures다. App Store Connect 레코드·메타데이터·개인정보·가격은
> 완료됐고, distribution **build 2**가 버전 1.0.0에 연결 가능한 상태(VALID)다.
> 스토어 스크린샷 원본도 확보됐다. 남은 제출 게이트는 웹 업로드와 계정
> 소유자의 법적 자격 선언, 그리고 TestFlight 실기 검증이다. 장시간 물리 기기
> 품질 게이트는 §5.4처럼 출시 후에도 계속 추적한다.
