# Naru Remote 출시 전 코드 품질 감사

- 일자: 2026-08-17
- 범위: 읽기 전용. 저장소 HEAD (`8b411895` 및 선행 `6bc3b0d2`, `2cddab84` 포함)의 앱/코어/iOS 배선.
- 목적: App Store 1.0 출시 리스크. 스타일·네이밍·주석은 제외. 동작 결함과 출시 리스크만.
- 전제 정정: AGENTS.md Empirical Facts의 “Unicode X11 keysyms never arrive”는 **구 측정**이다. `2cddab84` / constitution §I 개정(2026-08-17) / NEXT_STEPS standing constraint가 2026-07-13 실측으로 뒤집었다. 감사는 개정된 경로(키심 스트림이 Compose/Type 기본)를 기준으로 한다.

---

## P0 / P1 / P2 요약

| 심각도 | 개수 | 대표 항목 |
| --- | ---: | --- |
| **P0** (출시 차단) | **0** | 자격증명 유출, 릴리스 DEBUG 훅, 막다른 세션 상태, 권한 문자열 누락은 확인되지 않음. |
| **P1** (출시 전 권장) | **5** | ① ServerInit 이름 길이 무제한 할당 ② ServerCutText 페이로드 무제한 할당 ③ Extended Clipboard zlib inflate 출력 상한 없음 ④ 프로덕션 스트리밍 경로에서 incoming clipboard 수신이 꺼져 있음 ⑤ 원격 화면 썸네일이 iCloud 백업 제외 없이 디스크에 남음 |
| **P2** (이후) | **6** | helper video가 VNC 자동재연결 때 재부트스트랩되지 않음 · Type 모드가 재연결 중 Compose로 리셋 · 릴리스에서도 저장소 경로 env 오버라이드 · 성능 HUD 게이트가 `#if DEBUG`가 아님 · `authenticating`/`degraded` 미사용 · CADisplayLink `target: self` |

출시 차단급(P0)은 없다. 다만 P1-1~3은 **정상 macOS Screen Sharing에서도** 큰 클립보드/적대적 데스크톱 이름이면 폰이 OOM 날 수 있어, 사설망 제품이라도 출시 전에 상한을 넣는 편이 맞다.

---

## 1. 동시성 정합

### 확인한 방법

- `NaruRemoteAppModel`의 `Task.detached` / `isCurrentStream` / `isCurrentConnectionAttempt` / `isCurrentLiveTarget` / helper-video bootstrap ID 전수 열람.
- 최근 커밋이 만진 경로: `startFrameStream`(6bc3b0d2 이후에도 삼중 체크 유지), `deliverLiveInsertThroughHelper`/`Clipboard` → `completeLiveInsert`의 `isCurrentLiveTarget`, `sendAccessoryKey`/`enqueueKeyEventEmission`의 stream/session/profile/emitter 검증, `startHelperVideoStreamIfConfigured`의 `bootstrapID`.
- `@unchecked Sendable`는 앱/코어에서 `RFBNetworkClient`, `RFBFramePump`, `OutboundInputEventDispatcher`, Metal/Helper 박스에 존재. 각각 lock/NSCondition 또는 불변 캡처 주석이 있고, 남용으로 보이는 빈 `@unchecked`는 없음.
- `Task` 취소: `stopFrameStream`이 stream task + pump + application worker를 cancel하고 `activeFrameStreamID = nil`로 스테일 프레임을 버린다. `disconnect`/`selectProfile`이 reconnect sleep도 cancel.

### 발견

이 축에서 **출시 리스크 발견 0건**. 아래는 확인만 한 잔여.

- `MetalFramebufferViewDelegate.draw`의 `MainActor.assumeIsolated` (`MetalFramebufferRenderer.swift:1036`)는 MTKView 기본 메인 스레드 전제. 큐를 바꾸지 않는 한 안전. 의도적 가정이지 현재 버그로 보지 않음.
- 라이브 insert의 `Task.detached`는 완료 시 `isCurrentLiveTarget`으로 폐기한다. 세션 전환 후 헬퍼가 이미 보낸 텍스트는 원격에 남을 수 있으나, 이는 전송 후 확인 레이스의 본질이지 스테일 UI 갱신은 아니다.

### 오탐 가능성

“`@unchecked Sendable`이 많다”는 것만으로 결함으로 세지 않았다. 프로덕션 RFB 클라이언트는 동기 `throws` 경계를 유지하려고 lock으로 감싼 설계이고, 주석에 이유가 있다.

---

## 2. RFB 프로토콜 견고성

### 확인한 방법

`NaruRemote/Sources/NaruRemoteCore/VNC/` 전 파일을 읽고, 길이 필드·할당·루프·타임아웃·disconnect 후 콜백을 추적했다.

이미 잘 막힌 것:

- 프레임버퍼 디코더: `maxDimension = 16_384`, `maxRectanglesSafetyCap = 200_000`, ZRLE 압축 64MB, Tight JPEG 16MB, Tight basic 64MB, 커서 1 024 / 1 048 576 픽셀 (`RFBFramebufferDecoder.swift:26–35, 744, 1023–1024`).
- `RFBByteReader` / `ConnectionByteReader`: 음수 count 거부, `readExactly`별 타임아웃.
- Helper 쪽 프레임(텍스트 브리지 1MB, helper-video JSON 64KB / binary 16MB)은 상한이 있다.
- `RFBNetworkClient.disconnect`/`failConnection`이 `NWConnection.cancel` + receiveState.fail. `completeReceive`는 `failure != nil`이면 다음 receive를 예약하지 않음 (`RFBNetworkClient.swift:1576–1584`).
- Handshake/프레임 read는 `timeout`을 넘긴다. 무한 대기는 확인되지 않음.

### 발견

#### P1-1. ServerInit `name-length`를 그대로 할당한다

- **위치**: `RFBNetworkClient.swift:1008-1013`, `RFBProtocolDecoder.swift:254-257`
- **왜 문제인지**: `nameLength = Int(UInt32)`라 최대 ~4 GB. `readExactly(byteCount: nameLength)`가 그 크기 Data를 만든다. 적대적/손상 서버 한 대면 핸드셰이크에서 앱이 메모리 고갈.
- **수정 방향**: 데스크톱 이름에 작은 상한(예: 4 KiB 또는 64 KiB). 초과 시 typed error로 연결 종료. 디코더와 네트워크 경로 둘 다.
- **오탐 가능성**: 정상 Screen Sharing 이름은 짧다. 사설망이고 호스트를 사용자가 고른다. 그래도 길이 필드를 신뢰하는 것은 spec 004 SP-006(“untrusted server bytes”)과 같은 파일의 ZRLE/Tight 상한과 불일치한다.

#### P1-2. ServerCutText 페이로드 길이를 그대로 할당한다

- **위치**: `RFBNetworkClient.swift:563-577` (`handleServerCutText`, **스트리밍 프레임 루프에서 호출**), `RFBNetworkClient.swift:812-819` (`receiveServerCutText`), `RFBProtocolDecoder.swift:336-357`
- **왜 문제인지**: 부호 있는 32비트 길이를 `Int`로 바꾼 뒤 `readBytes`/`readExactly`한다. 상한 없음. 프로덕션 프레임 펌프는 Bell/Fence/CutText를 프레임 사이에 소비하므로, 원격에서 큰 텍스트를 복사하면 **수신 리뷰 기능이 꺼져 있어도** 할당이 일어난다.
- **수정 방향**: 클립보드 페이로드 상한(예: 1–4 MB). 초과분은 연결을 끊거나 메시지를 건너뛰기 전에 소켓에서 폐기할 수 있는 스트리밍 skip이 필요. `receiveServerCutText`와 `handleServerCutText`에 동일 상한.
- **오탐 가능성**: 일상 복사는 작다. 그러나 로그/코드 전체를 붙인 복사는 수 MB가 흔하고, 그때 폰 RSS가 프레임버퍼(~수–수십 MB)와 겹친다. “악성 서버만의 문제”로 치우면 안 된다.

#### P1-3. Extended Clipboard zlib inflate에 출력 상한이 없다

- **위치**: `RFBProtocolDecoder.swift:399-401`, `459-527` (`RFBZlibWrappedPayloadInflate.inflate`)
- **왜 문제인지**: `handleServerCutText`는 메시지를 **먼저 전부 파싱**한 다음 caps인지 본다 (`RFBNetworkClient.swift:577-583`). `provide+text`면 inflate가 돌아간다. 루프(`501-521`)는 `COMPRESSION_STATUS_OK`인 동안 64 KiB 청크를 무한 append. 작은 deflate가 거대한 출력을 만들 수 있다(zip bomb).
- **수정 방향**: inflate 출력 상한(클립보드와 동일한 1–4 MB) + 초과 시 `malformedExtendedServerCutText`. caps가 아닌 provide는 파싱 전에 스킵하는 편이 더 낫다.
- **오탐 가능성**: macOS Screen Sharing은 보통 레거시 Latin-1 CutText라 이 경로를 안 탈 수 있다. 그래도 코드는 확장 클립보드를 이해하고, UTF-8을 광고하는 서버/헬퍼가 있으면 산다. ZRLE inflate도 출력 상한은 없지만 압축 입력이 64 MB로 막혀 있어 같은 급은 아니다.

#### P2-1. 비스트리밍 `connectFirstFrame`은 사각형 헤더만 읽고 픽셀을 안 읽는다

- **위치**: `RFBNetworkClient.swift:475-490`
- **왜 문제인지**: `rectangleCount * 12` 바이트 헤더만 소비하고 픽셀 페이로드는 소켓에 남긴다. 같은 커넥션에서 이어서 스트리밍하면 스트림이 어긋난다.
- **수정 방향**: 프로덕션 `connectAndReadFirstFrame`은 `RFBStreamingClient`면 `connectSession`+pump를 쓴다 (`NaruRemoteAppModel.swift:6934-6948`). 폴백 경로만 해당. 폴백을 지우거나, 여기서도 풀 디코드를 돌리거나, 연결을 즉시 닫는다고 문서화.
- **오탐 가능성**: 설치 앱의 `RFBNetworkClient`는 스트리밍 클라이언트라 이 폴백을 안 탄다. 테스트 페이크/진단용 잔여.

---

## 3. 보안 경계

### 확인한 방법

- `ConnectionProfile` / `FileConnectionProfilePersistence` / `KeychainConnectionCredentialStore` 열람. 프로필 JSON에는 `credentialRef`만, 비밀번호 없음.
- `DiagnosticExport` + `DiagnosticExportSafeDetailCatalog` + `DiagnosticInputReport`의 allow-list. share-text/JSON은 `stageRows`와 카탈로그 문자열만.
- 앱/코어에서 `print`/`os_log`/`Logger`/`NSLog`: 프로덕션 유일 `print`는 `#if DEBUG` 진단 export 릴레이 (`NaruRemoteAppModel.swift:3304-3330`). 사용자 입력 원문 로그 없음.
- 클립보드: incoming은 Accept 전에 `UIPasteboard`를 안 만진다. outgoing Compose는 세션 중 원격 클립보드에만 쓴다.
- `NARU_TEST_INJECT_KEYCHAIN_*`는 `#if DEBUG` (`NaruRemoteApplication.swift:141-148, 741-770`).

### 발견

#### P1-4. 프로덕션 스트리밍 세션에서 incoming clipboard 리뷰가 동작하지 않는다

- **위치**: `NaruRemoteAppModel.swift:3774-3786` (주석: task #30, 프레임 펌프와 `receiveServerCutText` 레이스). `startIncomingClipboardReceive` 호출은 비스트리밍 첫 프레임 경로뿐 (`3610-3611`). 테스트: `IncomingClipboardReviewTests.swift:148-160`이 `XCTSkip`.
- **왜 문제인지**: 설치 앱은 항상 `RFBStreamingClient`로 연결한다. `handleServerCutText`는 caps만 반영하고 사용자 텍스트는 버린다. `SUBMISSION_READINESS.md` 화면 인벤토리 #7은 incoming clipboard를 ✅로 적어 두었으나, 실제 세션에서는 배너가 뜨지 않는다. 원격→로컬 붙여넣기 리뷰라는 보안 UX가 빠진다.
- **수정 방향**: 주석이 요구하는 단일 RFB 멀티플렉서. 그때까지 제품 카피/스토어 스크린샷에서 incoming clipboard를 빼거나 “미지원”으로 표시.
- **오탐 가능성**: 픽스처/비스트리밍 커넥터에서는 루프가 돈다. 출시 바이너리의 경로가 아니다. 의도적 게이트이므로 “회귀”라기보다 **출시 범위와 문서가 어긋난 미완**.

#### P1-5. 원격 화면 썸네일이 백업 제외 없이 Application Support에 남는다

- **위치**: `FileProfilePreviewStore.saveThumbnail` (`ProfilePreviewStore.swift:261-276`). 디렉터리: `NaruRemoteApplication.swift:802-808` → `Application Support/NaruRemote/profile-previews/`. `isExcludedFromBackup` / `NSURLIsExcludedFromBackupKey` **저장소 전무**.
- **왜 문제인지**: 썸네일은 원격 데스크톱 픽셀(터미널, 메일, 비밀)이다. 프로필 삭제는 `deleteThumbnail`을 호출한다 (`NaruRemoteAppModel.swift:2407`). 그러나 파일이 iCloud/Finder 백업에 들어가면 기기 밖 신뢰 경계로 나간다. constitution §IV(스크린샷 보존).
- **수정 방향**: preview 디렉터리(및 가능하면 profiles/settings)에 `URLResourceValues.isExcludedFromBackup = true`. 선택적으로 Data Protection / complete-until-first-unlock.
- **오탐 가능성**: Apple 개인정보 라벨의 “개발자가 수집하는 데이터”는 아니다(온디바이스). 그래도 원격 화면이 사용자 iCloud 백업에 실리는 것은 제품 보안 경계다. 320×200이라 용량은 작다.

자격증명·진단 export·로그 원문에 대한 **추가 발견 없음**. `DiagnosticExport.summary`는 caller `safeTitle`을 붙이지만 share 경로는 `stageRows`+카탈로그만 쓰고, 구조체는 Codable이 아니다.

---

## 4. 리소스·수명

### 확인한 방법

- 프레임 태스크: `stopFrameStream`이 cancel + ID nil + queue close (`NaruRemoteAppModel.swift:5545-5565`). 재연결은 새 `streamID`.
- Metal: `MetalFramebufferRenderer.deinit`이 staged upload task cancel (`306-308`). 텍스처는 enqueue/draw에서 교체.
- PiP: `PiPWatchPictureInPictureController.stop`이 컨트롤러 stop + `AVAudioSession` deactivate (`PiPWatchSampleBufferRenderer.swift:473-493`). watch-only, 입력 표면 아님.
- 타이머: 앱 코드에 `Timer`/`NotificationCenter` 상주 구독 없음. 뷰포트 `CADisplayLink`는 `willMove(toWindow: nil)`에서 invalidate (`MetalFramebufferView.swift:1086-1089`).
- 파일 핸들: 프로필/설정/썸네일은 요청 단위 open/close. 장기 핸들 없음.

### 발견

#### P2-2. Helper video가 VNC 자동재연결 때 다시 안 뜬다

- **위치**: `handleStreamFailure` 재연결 분기 (`NaruRemoteAppModel.swift:5244-5268`)는 helper를 멈추지 않고, `runScheduledReconnect` (`5406-5455`)는 `startHelperVideoStreamIfConfigured`를 안 부른다. 전체 실패/disconnect만 `stopHelperVideoStreamBootstrap`.
- **왜 문제인지**: 같은 네트워크 끊김에 helper TCP도 죽는 경우가 많다. 러너가 VNC fallback을 해도, 이후 자동재연결은 VNC(~5 fps)에 남고 helper는 수동 재연결까지 안 돌아온다.
- **수정 방향**: 재연결 성공(또는 시도 시작) 시 helper bootstrap을 다시 돌리거나, 실패 시 명시적으로 stop 후 VNC-only로 고정.
- **오탐 가능성**: constitution §V — helper는 MVP 옵션. 1.0이 VNC-only로 팔리면 출시 차단은 아니다. helper를 켠 사용자에게는 체감 품질 회귀.

#### P2-3. CADisplayLink가 `target: self`이고 `deinit`에서 invalidate하지 않는다

- **위치**: `MetalFramebufferView.swift:1534-1540`, `1771`. `deinit`(`1027-1029`)은 커서 태스크만 cancel.
- **왜 문제인지**: CADisplayLink는 target을 retain. `willMove(toWindow: nil)`이 빠지는 경로면 사이클. 정상 제거에서는 willMove가 불린다.
- **수정 방향**: `deinit`에서도 invalidate하거나, target을 proxy로.
- **오탐 가능성**: UIView는 보통 window에서 빠질 때 willMove가 온다. 재현은 드묾.

스트림 태스크 누수(재연결 반복)는 `streamID` 교체와 cancel로 구조적으로 닫혀 있다. 별도 P1 없음.

---

## 5. 에러 경로 UX 정합

### 확인한 방법

`RemoteSession` 전이(`RemoteSession.swift`)와 모델의 `markFailed` / `markReconnecting` / `markFirstFrameReceived` / `disconnect` 호출부를 읽었다.

| 상황 | 전이 | 재시도 |
| --- | --- | --- |
| 초기 연결 실패(TCP/핸드셰이크/인증) | `.connecting` → `.failed`, 카탈로그 타이틀 | `showsConnectButton` + Operation Retry (`NaruRemoteAppShell.swift:280-290, 325-336`) |
| 자격증명 없음 | `.failed` “Credential unavailable” (`3505-3525`) | 동일 Retry/Edit |
| 스트리밍 중 절단, 시도 남음 | `.reconnecting(n/max)`, 마지막 프레임 유지 | 자동. Disconnect 가능 |
| 재연결 소진 | `.failed` “Connection lost…”, 프레임 클리어 | Retry |
| 사용자 Disconnect | `.closed` | Connect 다시 표시 |
| 명시적 disconnect 중 late failure | `explicitlyDisconnected` + `isCurrentStream`로 무시 | 재연결 안 함 |

막다른 상태(버튼도 자동 재시도도 없음)는 없다.

### 발견

#### P2-4. Type(기본) 표면이 재연결 중 Compose로 리셋된다

- **위치**: `handleStreamFailure`가 재연결 전에 `resetLiveTypeThroughState()` (`5237`, `6090-6098`). `hasAppliedTypeThroughDefaultForCurrentSession = false`라 첫 프레임에서 Type이 다시 promote된다. 재연결 중 `showsInputDock`은 true (`NaruRemoteAppShell.swift:359-368`).
- **왜 문제인지**: 재연결 몇 초 동안 독이 Compose로 바뀌고 키보드가 접혔다 다시 Type으로 올라갈 수 있다. 명시적으로 Type을 고른 경우 `hasUserSelectedDockModeThisSession`이 살아 있어 promote가 스킵되면 Compose에 남을 수 있다.
- **수정 방향**: 재연결 중에는 Live/Type 상태를 유지하고 emitter만 끊기. 성공 시에만 재바인딩. 명시적 Type 선택을 세션 플래그로 보존.
- **오탐 가능성**: `NaruRemoteAppReconnectTests`는 프레임/자격증명만 보고 독 모드를 안 본다. 기본 Type 사용자는 재연결 성공 후 복구된다. 중간의 깜빡임이 본문.

#### P2-5. `.authenticating` / `.degraded`는 UI만 있고 모델이 안 넣는다

- **위치**: enum `RemoteSession.swift:13-21`. 앱 모델에 `state = .authenticating` / `.degraded` 할당 없음. HUD는 문자열을 갖고 있다 (`SessionDiagnosticCornerView.swift:72-107`).
- **왜 문제인지**: 인증 중에도 “Connecting”만 보인다. 실패 UX는 카탈로그로 충분해서 막다른 길은 아님.
- **수정 방향**: 핸드셰이크 인증 단계에서 `.authenticating`을 넣거나, 미사용 케이스를 문서화.
- **오탐 가능성**: 고의적 단순화일 수 있다. 동작 버그는 아님.

---

## 6. iOSApp 배선·설정

### 확인한 방법

`Info.plist`, `project.yml`, `PrivacyInfo.xcprivacy`, `NaruRemoteApplication.swift`, `#if DEBUG` 훅, 권한 사용처 grep.

| 항목 | 판정 |
| --- | --- |
| `NSLocalNetworkUsageDescription` | 사용함(NWConnection). en/ko strings 일치. |
| 마이크/카메라/사진/음성인식 usage | **없음**. `SFSpeech`/`UIImagePicker`/`PHPicker`/`NSMicrophone` 사용 없음. 받아쓰기는 시스템 키보드. |
| `UIBackgroundModes: audio` | PiP용 `AVAudioSession` playback + mixWithOthers. 과다로 보이지 않음. 리뷰 노트에 용도 명시(SUBMISSION_READINESS §4). |
| ATS | `NSAllowsArbitraryLoads` 없음. VNC/helper는 raw TCP라 ATS 비대상. |
| `ITSAppUsesNonExemptEncryption: false` | 프로젝트가 VNC DES를 면제로 본 상태(SUBMISSION_READINESS). 본 감사가 뒤집지는 않음. |
| `CADisableMinimumFrameDurationOnPhone` | 120 Hz 허용. 출시 부적격 아님. |
| PrivacyInfo | no-tracking / 수집 없음 / accessed API 빈 배열. `UserDefaults` 없음. `attributesOfItem`은 UITest만. |
| DEBUG → 릴리스 | 픽스처, 키체인 주입, 스토어 스킵, 테스트 스톰은 `#if DEBUG`. `UXAuditFixtures.swift` 전체가 `#if DEBUG`. |

### 발견

#### P2-6. 릴리스에서도 저장소 경로를 환경변수로 바꿀 수 있다

- **위치**: `NaruRemoteApplication.swift:784-808` (`NARU_PROFILE_STORE_URL` / `NARU_SETTINGS_STORE_URL` / `NARU_PREVIEW_STORE_URL`) — `#if DEBUG` 없음. `SessionPerformanceHUDGate` (`SessionPerformanceHUDView.swift:8-13`) + `NaruRemoteAppShell.swift:618-620`도 `#if DEBUG` 없이 `NARU_PERF_HUD`.
- **왜 문제인지**: App Store iOS는 사용자가 launch env를 못 넣는다. 탈옥/개발자 서명/맥 카탈리스트가 아니면 실익 없음. 그래도 테스트 훅이 릴리스 바이너리에 남는 것은 출시 위생.
- **수정 방향**: 경로 오버라이드와 HUD 게이트를 `#if DEBUG`로. HUD는 주석이 이미 “DEBUG-only”라고 한다.
- **오탐 가능성**: 스토어 빌드에서 트리거 불가. 심사 리스크는 사실상 0.

권한 과다/과소로 심사 거절될 항목은 보이지 않는다.

---

## 7. 테스트 갭

위 P1/P2에 대응하는 기존 커버리지:

| 위험 | 기존 테스트 | 갭 |
| --- | --- | --- |
| P1-1 이름 길이 | `RFBProtocolDecoderTests`는 정상 `"Desk"`만 | 거대 `name-length` 거부 테스트 없음 |
| P1-2 CutText 길이 | FakeRFB 클립보드 통합은 정상 크기 | 스트리밍 중 거대 CutText / 상한 테스트 없음 |
| P1-3 inflate 상한 | `NaruHelperNetworkCodecTests` oversized는 **헬퍼 코덱만** | `RFBZlibWrappedPayloadInflate` 출력 상한 테스트 없음 |
| P1-4 incoming clipboard | `IncomingClipboardReviewTests.testStreamingConnectorTriggersReceiveLoop…`가 **의도적 skip** | 멀티플렉서 전까지 프로덕션 경로 미커버 |
| P1-5 백업 제외 | `ProfilePreviewStoreTests`는 로드/세이브 | 백업 플래그 단언 없음 |
| P2-2 helper 재연결 | Helper runner/fallback 단위 테스트는 있음 | VNC auto-reconnect 후 helper 재시작 단언 없음 |
| P2-4 Type × reconnect | `NaruRemoteAppReconnectTests` — 독 모드 미검사 | 재연결 전후 `remoteInputDockMode` 단언 없음 |
| `.authenticating` | corner state 픽스처만 | 모델이 상태를 넣는 테스트 없음(넣을 코드가 없음) |

`swift test` 전체는 돌리지 않았다(점유). 필요한 필터도 코드 읽기로 충분해 생략.

---

## swift build

작업 트리에서 실행. 이미 빌드된 아티팩트에 대한 incremental.

```
[0/1] Planning build
Building for debugging...
[0/11] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.44s)
EXIT:0
```

exit code: **0**.

---

## 이 감사가 다루지 못한 것

1. **물리 iPhone + 실 Mac 30분 세션** — NEXT_STEPS P0. Type/Compose IME, 재연결, PiP, helper-video 실화면, 열/RSS는 코드 감사로 대체 불가.
2. **Xcode Archive / App Store 제출 바이너리** — SwiftPM `swift build`(macOS)만 실행. `xcodebuild` Release, bitcode/strip, `PrivacyInfo` 번들 포함, 심사 스크린샷 슬롯은 미검증.
3. **NaruHelper 호스트 프로세스** — 출시 앱은 헬퍼 없이 동작해야 한다(constitution §V). 헬퍼 CLI의 Accessibility/Screen Recording, HMAC 구현, 토큰 argv 실수는 앱 1.0 범위 밖에서  superficially만 보았다.
4. **XCUITest / 접근성 / Dynamic Type / VoiceOver 실기기** — 코드상 버튼 trait 수정은 문서화되어 있으나 이번 라운드에서 UI 테스트를 돌리지 않음.
5. **암호화 수출 준수 법률 판단** — `ITSAppUsesNonExemptEncryption: false`와 자체 DES(VNC Auth) 조합은 기존 제출 문서를 따랐고, 법률 재감정은 하지 않음.

---

## 읽은 트랩 문서 (적용된 조항)

확인한 파일: `CLAUDE.md`, `AGENTS.md`, `.specify/memory/constitution.md`, `Package.swift`, `NEXT_STEPS.md`, `SUBMISSION_READINESS.md`. `docs/decisions/` 없음. 중첩 `CLAUDE.md` 없음.

적용:

- constitution §IV / AGENTS: 자격증명은 Keychain `credentialRef`만 — 프로필 파일에 암호 없음(준수).
- constitution §IV / AGENTS: DiagnosticExport는 고정 카탈로그 — share 경로 준수. caller `safeTitle`은 in-memory `summary`에만.
- constitution §IV: 로그에 사용자 입력 원문 금지 — 프로덕션 print/os_log 원문 없음.
- AGENTS: `isCurrentStream` 삼중 체크를 새 async 흐름에 유지 — 6bc3b0d2 Type/Compose·라이브 insert는 지킴.
- constitution §V: 헬퍼 옵션 — helper 재부트스트랩 공백을 P0로 올리지 않은 근거.
- constitution §VI / NEXT_STEPS: 물리 iPhone 게이트는 잔여 — “다루지 못한 것”에 기록.
- AGENTS: DirectKeystrokeMode / StickyModifierState는 액세서리 스트립이 재사용 — 죽은 코드로 보고하지 않음.
- AGENTS: PiP는 watch-only — 입력 표면화 없음.

---

## 의도적으로 손대지 않은 것

읽기 전용 계약. 코드·테스트·설정 미수정. `scratch/code-audit-2026-08-17.md`와 `scratch/progress-code-audit.log`만 기록.

DONE-CODEAUDIT
