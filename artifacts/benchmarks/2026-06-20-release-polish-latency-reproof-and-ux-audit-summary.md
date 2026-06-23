# 2026-06-20 Release-polish: live latency re-proof + iPhone UX audit

배포 전 디테일/사용성/성능 점검. 프라이버시-세이프 집계만 기록(좌표·치수·바이트·엔드포인트·콘텐츠 미기록, `PRODUCT_QUALITY_TARGETS.md` §1.4).

## 1. VNC 지연 — 라이브 재증명 (목표: frame freshness p95 ≤ 250ms)

`VNCLiveBenchmark --stream-shape-transport both --stream-shape-profile-iterations 5`,
라이브 macOS Screen Sharing (127.0.0.1:5900), local-low-latency 프로파일.

| 지표 | 값 | 비고 |
|---|---|---|
| update freshness avg | **27 ms** | order-neutral, 5 runs / 60 samples |
| update freshness **p95** | **241 ms** | **목표 250ms 통과** |
| best single-window profile | 18 ms avg / 42 ms p95 | local-low-latency, single, full |
| network-read split (first-byte / payload) | 1000 / 0 permille | payload p95 **0 ms** |
| dominant phase | network-read → first-byte-wait | 서버 측 갱신 cadence |

**해석:** 잔여 지연은 전부 `first-byte-wait`(서버의 업데이트 cadence + 네트워크), payload 수신/디코드/렌더는 p95 0ms로 **클라이언트 파이프라인이 지연에 거의 기여하지 않음**. 이는 앱 측 3겹 페이싱을 단일 레이트 권위(`SessionFrameApplicationWorkerPacing`)로 통합하고 `frameInterval`을 0으로, request pipeline depth를 3으로 둔 기존 변경이 의도대로 동작함을 라이브로 확인한 결과.

`verdict: fail`은 지연 회귀가 아니라 (1) 정적 화면이라 content-fps 샘플 부족(`insufficient-content-samples`, 7.83 fps), (2) ContinuousUpdates가 macOS Screen Sharing 미지원이라 `not-confirmed` → 권장 액션이 `treatContinuousUpdatesAsUnsupportedForCurrentServer`(설계된 request/response 폴백). 둘 다 예상된 정상 동작이며 latency 목표 자체는 달성.

## 2. iPhone 시뮬레이터 UX 감사 (ROADMAP #477)

`UXAuditScreenshotsUITests`, iPhone 17 Pro / iOS 26.2, light. 재설계된 Compose 독 검증.

- **07 compose-text (standard):** 헤더 → Compose/Direct 피커 → 풀폭 에디터 → `[⌫][↵] … [Send]` 액션 행 항상 노출. pre-connect라 ⌫/↵ 비활성. ✅
- **16 / 18 active widescreen / trackpad:** immersive 뷰포트 + 하단 floating HUD `[⌨][A| Compose][창 컨트롤]`. 커서 오버레이 정상. ✅
- **09 direct-special:** 터미널 키(Esc·Tab·⌃·⌥·⌘·⇧·Clr·⌫·↵ + 화살표·Home·End·PgUp·PgDn·Ins·Del)가 Direct 특수 페이지에 존재 — 단축키를 Compose에서 제거하고 가상키보드 모드로 옮긴 제품 방향 충족. "IME off" 배지 정상. ✅

### 알려진 잔여 이슈 (기존, 이번 변경과 무관)

`testSessionActiveWidescreen_light` / `testSessionActiveDirectHardwareKeyboard_light` 두 스크린샷-감사 테스트가 immersive-chrome reveal 타이밍에 의존해 **flaky**. 커밋 베이스라인(작업 stash)에서도 동일하게 실패함을 확인 → compose 재설계 회귀 아님. 제품 렌더 자체는 16/18 스크린샷으로 정상 확인됨. 후속: `revealSessionControlsIfNeeded`의 chrome-reveal 견고성 개선(별도 SessionViewport 작업).

## 검증 매트릭스
- 라이브 벤치마크(RFB/펌프 층): 위 §1.
- 단위/통합: `swift build` + `swift test` 그린(라이브 스트리밍 경로 테스트 포함).
- iPhone 시뮬레이터(헌법 §VI): 위 §2 스크린샷.
- 실기기: Compose 클립보드 ⌘V 수정·키입력 모드는 사용자 iPhone 검증 대기.
