# 상용급(맥 화면공유·Chrome Remote Desktop 수준) 격차 분석과 달성 경로

> **2026-08-20 갱신**: 스트리밍 성능 레버 웹 리서치가
> `artifacts/research/2026-08-20-streaming-performance-levers.md`에 있다
> (랭킹 20종 + 출처 URL). 본문 §3의 "Apple 고성능 모드는 서드파티 API 없음"은
> 이제 부분적으로 낡았다 — 2026년 역공학 구현(iShareScreen)이 Apple 사설
> 코덱(0x3e8–0x3f3)·ScaleFactor 0x08(서버측 0.5× 다운스케일, Screens 5의
> "Compression")·HP HEVC 경로를 문서화했다. 또한 spec 017 실측 정정:
> Apple 서버는 부하 시 영역 요청을 신뢰성 있게 클리핑하지 않는다
> (2026-08-20, out-of-region rect 158개 — 정확성 무해, 절약은 워크로드 의존).

작성일: 2026-07-05 KST
증거: `artifacts/benchmarks/2026-07-05-physical-iphone-release-hud-and-helper-gate-summary.md` + 본문 인용.
기준 문서: `PRODUCT_QUALITY_TARGETS.md`(품질 기준), `PRODUCT_SPEC.md`, `ROADMAP.md`, `specs/006`, `specs/007`.

목표 문장(창업자 확인, 2026-07-05): **"Chrome Remote Desktop 수준의 사용성 — 특히 compose 입력이 정말 잘 되는 상태"**. 이 문서는 그 목표와 현재 사이의 격차를 실측으로 분해하고, 달성 경로를 우선순위로 정리한다.

---

## 1. 요약

1. **클라이언트(폰 쪽) 파이프라인은 이미 상용급으로 건강하다.** iPhone 15 Pro Max 실기기 Release 실측: decode 4–14ms, GPU 업로드 0–3ms, frame apply 0ms, 입력 큐+전송 0–1ms, main-actor 블로킹 평균 12ms. 폰 하드웨어는 병목이 아니다.
2. **VNC visual path의 프레임레이트 천장은 Apple Screen Sharing 서버다.** 네트워크·콘텐츠 변수를 제거한 루프백 실측에서도 콘텐츠 ~5.6fps(networkRead p95 155–213ms)가 한계. 이 경로로는 "맥 화면공유급" 프레임레이트에 도달할 수 없다(구조적 한계).
3. **상용 제품들은 전부 VNC를 버리고 "자체 호스트 앱 + 하드웨어 비디오 코덱 + 자체 전송"으로 해결했다.** Naru의 등가물인 helper video(spec 007)는 기능 완성 상태이며, 2026-07-05 실기기 게이트를 최초 통과했다(synthetic 소스). 프레임레이트의 답은 이 경로의 승격이다.
4. **Compose가 "한 번도 스무스하지 않았던" 이유는 실측으로 분해됐다.** (a) ⌘V paste가 잘못된 modifier keysym(Alt_L)으로 macOS에서 조용히 실패해 오다 `0e5d16ea`에서야 수정됨, (b) 전송 전 로컬 안정화 최대 ~480ms + 클립보드 settle 300ms, (c) 서버 cadence 때문에 에코 표시까지 추가 ~0.5s+, (d) 성공해도 "확인 불가(unknown)" 배너. 에디터 자체(키보드 응답)는 이미 강하게 격리돼 있다(시뮬레이터 증거).
5. **CRD급 compose의 기술 기반은 오늘 라이브로 증명됐다.** VNC KeyEvent(Unicode keysym) 한글은 macOS에 도착하지 않음(실측 `no-input`) → 막힌 길. **helper text bridge 네이티브 삽입은 한글이 통제 타깃에 정확히 도착(`observed-inserted`/`matched`)** → CRD식 type-through의 열린 길.

---

## 2. 2026-07-05 실측

측정 원칙: 성능 판단은 반드시 Release 빌드(debug는 decode/main-actor를 10–40배 부풀림 — 2026-06-29 확인). 도구: `SessionPerformanceHUDView`(DEBUG 또는 `NARU_PERF_HUD=1`), `LiveRFBPerformanceProbeTests`, `PerfHUDLiveProbeUITests`(env 시딩으로 실기기 지원), `scripts/run-naru-live-benchmark.sh`.

### 2.1 실기기 per-stage (iPhone 15 Pro Max, Release, Wi-Fi, VNC visual path)

| 단계 | avg / max (ms) | 판정 |
|---|---|---|
| net read | 109–324 / ~3,100 | **유일한 지배 항목 — ceiling: network/server** |
| decode | 4–14 / 116 | 정상 |
| gpu upload / frame apply | 0/3 · 0/0 | 정상 |
| in queue / in op | 0/1 · 0/0 | **클라이언트 입력 경로 사실상 무지연** |
| main blk | 11–13 / 49 | 정상 |

2026-06-29의 잔여 미지수였던 "폰 CPU"가 해소됨. 남은 병목은 전부 서버·전송 측이다.

### 2.2 서버 produce rate (루프백, 데스크톱 콘텐츠, 커서 지터)

| 프로파일 | content fps | networkRead avg/p95 (ms) | clientProc avg (ms) |
|---|---|---|---|
| PROD (CU 시도+pipeline 3) | **5.6** | 33 / 213 | 3 |
| request/response depth 1 | 4.5 | 41 / 237 | 2 |
| request/response depth 3 | 5.3 | 21 / 155 | 1 |

인코딩은 전 구간 ZRLE 단독(서버가 Tight 미제공). ContinuousUpdates는 Apple 미지원(설계된 request/response 폴백 정상 동작). 기존 기본값(CU 시도 + depth 3 + frameInterval 0)은 이미 최적 근처 — **VNC 튜닝으로 더 짜낼 여지는 소진 단계.**

### 2.3 helper-video 실기기 게이트 — 최초 통과

`physical-iphone-helper-video-gate` (synthetic-encoded 리스너, 120s sustained, balanced/standard/one-hidden-frame/glance-025): **passed**. 종전 차단 사유(실기기 서명)는 `DEVELOPMENT_TEAM=… CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates`로 해소됨. 잔여: 실화면(ScreenCaptureKit) 소스 게이트는 Mac에서 helper(NaruHelperDev.app 신원)에 화면 기록 권한 부여 후 실행.

### 2.4 텍스트 전달 경로 관찰 프로브 (payload: unicode-hangul, 통제 로컬 타깃)

| 경로 | 결과 | 의미 |
|---|---|---|
| VNC KeyEvent (X11 Unicode keysym) | **`no-input`** — 전송 성공, 도착 0 | macOS screensharingd가 Unicode keysym을 무시. **type-through를 VNC로 하는 길은 막힘** |
| helper text bridge `nativeInsert` (spec 006) | **`observed-inserted` / `matched`** | Accessibility 네이티브 삽입으로 한글 정확 도착. **CRD식 type-through의 기반 확보** |
| VNC clipboard + ⌘V | 동작 (기존 E2E) | 배치 전송용 폴백으로 유지 |

---

## 3. 상용 제품은 어떻게 하나 (2026-07-05 웹 리서치, 출처는 리서치 노트)

| 제품 | 시각 전송 | 입력 |
|---|---|---|
| Apple 화면공유 고성능 모드 | HEVC 4:4:4 / UDP, 30–60fps — **Apple 클라이언트 전용, 서드파티 API 없음** | 자체 |
| Apple 화면공유 VNC 호환 모드 | ZRLE, 서드파티에 느린 인코더 (우리 실측 ~5fps) | 물리 키코드만, Unicode keysym 무시 (우리 실측 일치) |
| Jump Desktop (Fluid) | 자체 프로토콜, 60fps 목표, 적응 품질 | 자체 호스트 주입 |
| Chrome Remote Desktop | WebRTC + VP8/VP9/AV1/H.264(HW), 혼잡제어 내장 | **trackpad 기본 + 로컬 IME로 조합한 텍스트를 호스트에 네이티브 주입** |
| Parsec / Moonlight | H.264/HEVC + UDP, LAN 한 자릿수 ms | 자체 |
| Screens 5 (순수 VNC) | Apple 서버 한계 동일 — 점진 품질·서버 다운스케일로 **완화만** | VNC |

공통 패턴 3요소: **(a) 하드웨어 비디오 코덱, (b) 코덱 비트레이트를 레버로 쓰는 자체(주로 UDP) 전송, (c) 클라이언트 하드웨어 디코드 + 무큐잉 렌더.** 그리고 입력은 전부 "호스트 앱이 네이티브로 주입"이다. CRD의 compose가 잘 되는 이유 = draft+Send가 아니라 **type-through**(폰 IME로 조합 확정된 글자가 즉시 호스트에 꽂힘) + 호스트 네이티브 주입.

결론: "Apple VNC의 한계"는 "서드파티의 한계"가 아니다. 서드파티 고성능 원격은 가능하며, 방법은 하나 — 자기 호스트 프로그램. Naru에는 이미 있다(NaruHelper).

---

## 4. 격차 분해

### 4.1 프레임레이트

- 현재: VNC visual path 콘텐츠 ~5fps(서버 한계). 10fps 제품 게이트(§`PRODUCT_QUALITY_TARGETS.md` 5.1)는 이 서버 상대로는 구조적으로 미달.
- 해법: **helper video visual primary 승격**(§5 Track A). ScreenCaptureKit(60fps) → VideoToolbox H.264 저지연 HW 인코드 → 인증 TCP → `AVSampleBufferDisplayLayer` HW 디코드. 전 구간 구현 완료, 옵트인 상태.
- VNC측 잔여 최적화(§5 Track C)는 폴백 품질용이지 패리티 수단이 아님을 명시한다.

### 4.2 인풋랙

- 클라이언트 기여분은 실측 0–1ms(큐+소켓 쓰기). 포인터 코얼레싱 8/16ms, 트랙패드 로컬 커서 에코 존재.
- 체감 인풋랙의 실체는 **"내 입력의 결과를 눈으로 확인하기까지의 지연"** = 서버 frame cadence(p95 155–629ms) 지배. 입력 파이프를 더 깎아도 체감은 변하지 않는다 — 에코를 빠르게 하는 것(=helper video + 아래 compose 개선)이 유일한 레버.

### 4.3 Compose — "한 번도 스무스하지 않았다"의 해부

**이미 강한 부분(시뮬레이터 증거):** 키스트로크 핫패스는 철저히 격리돼 있다 — UITextView가 텍스트 소유(포커스 중 model 무기록·디스크 무기록), equatable host의 포커스 프리즈, 크롬 업데이트 코얼레싱, textInput 프레임 페이싱(33ms floor + 8ms 코얼레싱), off-main 픽셀 스테이징, marked-text(한글 조합) 보호. "첫 음절 후 키보드 프리즈" 클래스는 시뮬레이터 스톰에서 수정 증명됨(spec 003 T015 계열). **단, 전부 실기기 미검증** — 서명 차단이 오늘 풀렸으므로 실기기 재검증 대상.

**그럼에도 안 스무스했던 이유 — 전송 체감 시간 예산:**

| 구간 | 지연 | 성격 |
|---|---|---|
| ① Send 전 로컬 안정화 (marked-text commit 대기) | 최대 ~480ms (30스냅샷×16ms) | 클라이언트 설계 |
| ② 클립보드 settle | 300ms 고정 | 클라이언트 설계 |
| ③ ⌘V → 원격 반영이 화면에 보이기까지 | ~0.5s+ (서버 cadence, p95 629ms) | 서버 한계 |
| ④ 결과 표시 | "확인 불가/unknown" 배너 | VNC 구조상 확인 불가 |

합계: **한 문장 보낼 때마다 1–1.3초+ 의 침묵, 끝나도 성공인지 모름.** 여기에 결정타 —

**⑤ ⌘V 자체가 조용히 실패해 왔다.** `RFBClientMessageEncoder.pasteCommand`가 ⌘ 대신 Alt_L(0xffe9)을 보내고 있었고, macOS Screen Sharing에서 paste가 실패할 수 있었다. `0e5d16ea`(현 HEAD)에서야 Meta_L(0xffe7)로 수정. 즉 **지금까지의 체감 대부분의 기간 동안 Send가 실제로 안 꽂히는 일이 잦았다** — "한 번도 스무스한 적 없다"는 감각과 정확히 부합한다.

**모델 차이가 근본 격차다.** CRD = type-through(글자 확정 즉시 주입, 별도 Send 없음). Naru = draft+Send(배치). 배치 모델은 장문 검토·음성·이미지 합성에 강점이 있지만(헌법 §I), "짧은 대화형 타이핑"(터미널·AI CLI 프롬프트)에서는 위 시간 예산을 매번 지불한다.

### 4.4 기타 UX 갭

- 스크롤: 24pt/틱 휠 이벤트, **모멘텀·내추럴 방향 토글 없음**, 부분 틱 버림 → 미세 스크롤 불가.
- 지연 가시화: quality chip(Good/Fair/Poor)뿐. "지금 프레임이 오래된 상태"(staleness) 표시 없음.
- 회전/외부 디스플레이 명시 대응 없음(사이즈 클래스 적응만).
- 강점 유지: 로컬 핀치/팬(컴포지터 경로), 더블탭 줌, 커스텀 직접 키보드(QWERTY+특수 페이지+F1–12+스티키 모디파이어), PiP watch.

---

## 5. 달성 전략 — 3 트랙

> 구현은 Spec Kit 절차를 따른다. Track B의 신규 동작(연속 삽입 모드)은 구현 전 `$speckit-specify`로 spec을 만든다(기존 spec 006/007의 증분일 수 있음). 헌법 §I에 따라 각 입력 경로는 주입 어댑터와 포커스 상실·차단 시 동작을 명시한다.

### Track A — helper video visual primary 승격 (프레임레이트 패리티)

1. Mac에서 `helper-dev-app-setup` 실행 → NaruHelperDev.app에 화면 기록 권한 부여(1회, 사용자 클릭 필요).
2. `helper-video-live-gate` → 실화면 소스 실기기 게이트(`physical-iphone-helper-video-gate`, listener auto) 통과 기록.
3. `PRODUCT_QUALITY_TARGETS.md` §14 기준 충족 시 helper 구성 프로파일에서 visual primary를 기본값 후보로 승격. VNC는 control/input/fallback 재분류.
4. 백로그(승격 후): `requestKeyframe`/`stopStream` 와이어업(현재 미배선 — 스톨 복구용), 스톨 재시도 계약(현재 terminal→VNC 폴백만), HEVC, 전송 개선(UDP류) 검토.

### Track B — CRD식 type-through Compose (입력 패리티, **사용자 최우선**)

핵심: **"Live 입력 모드"** 추가 — 폰 네이티브 키보드(IME 포함)로 조합이 **확정된 단위(글자/단어)** 를 즉시 원격에 주입. Send 버튼 불필요.

- 주입 어댑터 사다리(헌법 §I 명명): ① helper text bridge `nativeInsert`(한글 도착 실측 확인, observed 확인 가능) → ② VNC clipboard+⌘V 청크(helper 부재 시; settle 지연 고지) → ③ ASCII는 VNC KeyEvent 직접. Unicode VNC KeyEvent는 macOS 상대 금지(실측 `no-input`).
- 기존 draft+Send(배치 Compose)는 장문·검토·음성·이미지용으로 **공존** — 모드 전환은 독에서 1탭.
- 단기 quick win(신규 spec 없이도 가능한 기존 동작 개선):
  - ①의 480ms 안정화 창을 marked-text 상태 이벤트 기반으로 단축(고정 30×16ms 폴링 대신 커밋 감지 시 즉시).
  - ②의 300ms settle을 helper 존재 시 생략(네이티브 삽입은 클립보드 미사용).
  - ④ helper 경로에선 `observed-inserted`를 그대로 성공 확인 UI로 노출("확인 불가" 배너 탈출).
- 검증: 실기기 한글 200자 혼합 문장 게이트(§`PRODUCT_QUALITY_TARGETS.md` 6.1) + `helper-text-observed-probe`(자동) + 실기기 수동 30분 세션.

### Track C — VNC 폴백 품질 + UX 폴리시

- 24MB COW 복사 제거(디코드 중 이전 프레임 배열 refcount≥2 → 첫 쓰기에서 전체 복사; fps보다 발열·메모리대역 개선. 스냅샷 격리 유지 리팩터 필요 — 위험 관리하며).
- 스크롤 모멘텀 + 부분 틱 누적 + 내추럴 방향 토글.
- 프레임 staleness 인디케이터(quality chip 보완).
- Tight+JPEG 광고 옵션(TigerVNC류 서버 대상 — Apple 서버엔 무효), adaptive 재협상 실험, 서버측 다운스케일(Screens의 "Compression" 접근) 조사.
- 벤치 스크립트 잔버그: `PHYSICAL_GATE_ISSUE_CODES[@]: unbound variable`(bash 3.2 빈 배열) 수정.

**우선순위: B(단기 quick win) → A(권한 부여 즉시 착수 가능) → B(type-through spec/구현) → C.** A와 B는 독립적으로 병행 가능(B의 helper text bridge는 video와 별개 기능이며 이미 구현됨).

---

## 6. 검증 매트릭스 (헌법 §VI: iPhone 먼저)

| 항목 | 증거 수단 | 상태 |
|---|---|---|
| 클라이언트 per-stage 건강 | 실기기 Release HUD (`PerfHUDLiveProbeUITests`) | ✅ 2026-07-05 |
| 서버 cadence 한계 | `LiveRFBPerformanceProbeTests` (release, 루프백) | ✅ 2026-07-05 |
| helper video 실기기 (synthetic) | `physical-iphone-helper-video-gate` (manual listener) | ✅ 2026-07-05 |
| helper video 실기기 (실화면) | 위 게이트 + Screen Recording 권한 | ⬜ 권한 부여 대기 |
| 한글 type-through 기반 | `text-keystroke-observed-probe`(❌ 확정) / `helper-text-observed-probe`(✅) | ✅ 2026-07-05 |
| Compose 실기기 스톰(프리즈 클래스) | `ComposeInputResponsivenessUITests`를 실기기로 | ⬜ 서명 해소로 실행 가능해짐 |
| 한글 200자×10회 무결성 | 실기기 수동 + observed probe | ⬜ |
| 30분 sustained 세션 | 실기기 수동 로그 | ⬜ |

## 7. 리스크·미결

- Apple 서버 fps 상한은 공식 문서가 없고 실측·정황 기반(우리 실측 포함). 변할 수 있음 — helper 경로가 이를 무의미하게 만드는 것이 전략.
- helper 실화면 게이트·Compose 실기기 게이트는 사용자 액션(권한 클릭·기기 잠금 해제 유지)이 선행돼야 함.
- COW 제거는 렌더러 스냅샷 격리와 얽혀 있어 동시성 리스크 — 단독 PR + 전후 실측 필수.
- type-through의 보안 경계(헌법 §IV): helper 삽입은 로컬→원격 텍스트 이동이므로 spec에서 전송 범위·로그 배제·revocation을 명시할 것(로그에 composed text 금지 규칙 유지).
