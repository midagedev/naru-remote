# 2026-07-05 실기기(iPhone 15 Pro Max) Release HUD 실측 + 서버 cadence 재증명 + helper-video 실기기 게이트 최초 통과

프라이버시-세이프 집계만 기록(좌표·치수·바이트·엔드포인트·콘텐츠 미기록, `PRODUCT_QUALITY_TARGETS.md` §1.4). 모든 측정은 Release 빌드(디버그 수치는 디코드/메인액터를 10–40배 부풀림 — 2026-06-29 확인).

## 1. 실기기 per-stage HUD 실측 (VNC visual path)

`PerfHUDLiveProbeUITests` (env 기반 `NARU_TEST_SEED_PROFILE_*` 시딩으로 실기기 지원하도록 개편), iPhone 15 Pro Max, Release + `ENABLE_TESTABILITY=YES`, Wi-Fi(LAN), 라이브 macOS Screen Sharing. idle 8초 → 드래그 6라운드(로컬 뷰포트 팬) → 탭 3라운드(원격 클릭). `SessionPerformanceHUDView` 스크린샷 판독.

| 단계 | avg / max (ms) | 판정 |
|---|---|---|
| net read | 109–324 / ~3,100 | **유일한 지배 항목 (ceiling: network/server)** |
| decode | 4–14 / 116 | 정상 (M-series Mac 대비 ~4배지만 여유) |
| gpu upload | 0 / 3 | 정상 |
| frame apply | 0 / 0 | 정상 |
| pacing | 30–67 / 200 | 드래그 중 viewport 귀속 (설계된 스로틀) |
| in queue / in op | 0 / 1 · 0 / 0 | **클라이언트 입력 경로 사실상 무지연** |
| main blk | 11–13 / 49 | 정상 |

encoding mix: zrle 단독. 캐비앳: 측정 시점에 원격 Mac이 잠금 화면(정적 콘텐츠)이라 content fps(1–2)는 콘텐츠 조건이 지배 — per-stage 비용 판정에는 영향 없음. **결론: 폰 하드웨어(CPU/GPU/입력)는 병목이 아님. 2026-06-29의 "남은 미지수 = 폰 CPU"가 해소됨.**

## 2. 서버 produce-rate 재증명 (데스크톱 콘텐츠, 루프백)

`LiveRFBPerformanceProbeTests` (release, 127.0.0.1 라이브 Screen Sharing, 잠금 해제 + 커서 지터로 콘텐츠 변화 유발, 각 6초):

| 프로파일 | content fps | networkRead avg / p95 / max (ms) | clientProc avg (ms) |
|---|---|---|---|
| PROD (CU 시도 + pipeline 3) | **5.6** | 33 / 213 / 881 | 3 |
| request/response depth 1 | 4.5 | 41 / 237 / 812 | 2 |
| request/response depth 3 | 5.3 | 21 / 155 / 808 | 1 |

encoding mix: 전 구간 zrle 단독(서버가 Tight 미제공). **해석: 네트워크·클라이언트 변수를 제거해도 Apple Screen Sharing이 서드파티 VNC 클라이언트에 내주는 콘텐츠 produce rate는 ~5fps대. VNC visual path의 fps 천장은 서버 측이며, 기존 기본값(CU 시도 + depth 3)은 이미 최적 근처.**

## 3. 실기기 helper-video 게이트 — 최초 통과

`scripts/run-naru-live-benchmark.sh physical-iphone-helper-video-gate`, listener mode **manual**: `NaruHelper --video-listen --video-source synthetic-encoded` (Screen Recording 권한 불요 변형). 후보: `iphone-sustained-usability-v2`, 120s sustained, balanced / standard / one-hidden-frame / glance-025, compose skip.

```
"status": "passed", "xcodebuildTestStatus": "passed"
```

이 게이트는 종전에 `xcode-account-missing` / `ios-provisioning-profile-missing`으로 차단돼 있었다(spec 007 T030의 잔여 리스크). 이번 실행으로 **실기기 서명 차단 해소 + helper-video 구성 세션의 sustained 게이트 통과**가 처음으로 기록됨. 잔여: (a) 실화면(ScreenCaptureKit) 소스 게이트는 Screen Recording 권한 부여 후 별도 실행 필요, (b) 게이트 스크립트 말미 `PHYSICAL_GATE_ISSUE_CODES[@]: unbound variable` (bash 3.2 빈 배열 확장, status 출력 이후라 결과 무영향 — 후속 수정 대상).

## 실행 정보 (재현용)

- 실기기 UDID는 `xcrun devicectl list devices`의 Identifier가 아니라 xcodebuild destination용 UDID(`xcodebuild -showdestinations`) 사용.
- 실기기 Release 테스트: `DEVELOPMENT_TEAM=<team> CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates ENABLE_TESTABILITY=YES` + `TEST_RUNNER_NARU_E2E_*` 환경변수.
- 스크린샷 추출: `xcrun xcresulttool export attachments`.
