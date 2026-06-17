# Naru Remote Product Quality Targets

작성일: 2026-06-13 KST

이 문서는 Naru Remote가 "원활한 스트리밍, 원활한 키보드/터치패드 입력,
iPhone/iPad에서의 원활한 사용"을 달성했다고 말하기 위한 제품 기준이다.
각 feature spec은 이 문서를 참조해 더 구체적인 acceptance test와 benchmark를
정의한다.

## 1. 기준 철학

Naru Remote의 목표는 단순히 원격 화면이 보이는 것이 아니다. 사용자가
iPhone에서 실제 데스크톱 터미널과 AI CLI 세션을 30분 이상 이어가도
입력, 화면, 제스처, 열, 네트워크 변동이 작업 흐름을 끊지 않는 상태를
목표로 한다.

기준은 다음 순서로 판정한다.

1. **Physical iPhone first**: iPhone 실기기에서 통과하지 못하면 제품
   기본값으로 승격하지 않는다.
2. **iPad graceful second**: iPad는 같은 워크플로우가 더 큰 화면으로
   자연스럽게 확장되는지 검증한다.
3. **Benchmarks before claims**: "부드럽다", "쓸 만하다"는 표현은
   benchmark, fake-server test, screenshot/video review, manual device log 중
   하나 이상의 증거를 가져야 한다.
4. **Privacy-safe diagnostics**: 성능 진단은 frame content, coordinates,
   dimensions, byte counts, endpoints, tokens, exact per-frame timings,
   composed text, clipboard contents를 내보내지 않는다.

## 2. 최상위 달성 목표

### 2.1 목표 문장

Naru Remote가 "원활한 사용"을 달성했다는 말은 다음 상태를 뜻한다.

> iPhone 실기기에서 private-network Mac에 접속해 30분 이상 terminal,
> browser, IDE, AI CLI 중심 작업을 이어가도 화면 갱신, Compose 입력,
> 직접 키 입력, trackpad/gesture 조작, reconnect, thermal/traffic 변화가
> 사용자의 작업 흐름을 끊지 않는다.

iPad는 이 경험이 큰 화면, pointer, hardware keyboard, Stage Manager로
자연스럽게 확장되는지를 검증하는 두 번째 기준이다. iPad가 좋아도 iPhone
실기기에서 keyboard freeze, pan lag, black frame, heat runaway, stuck input
state가 남아 있으면 Green이 아니다.

### 2.2 Smoothness Scorecard

모든 성능/UX PR은 가능한 경우 아래 scorecard 중 어떤 축을 개선했는지 밝힌다.
한 축이라도 blocking failure가 남아 있으면 전체 목표는 Green이 아니다.

| 축 | Green pass | Gold pass | Blocking failure |
| --- | --- | --- | --- |
| Visual stream | VNC visual path가 iPhone 10fps gate를 통과하거나, helper-video primary가 physical iPhone gate를 통과하고 VNC가 control/input/fallback으로 분류된다. First useful paint와 frame freshness 기준을 만족한다. | Helper video가 24fps-class 이상으로 보이고 poor-network에서도 degradation이 예측 가능하다. | permanent black frame, repeated first-frame timeout, helper stall 후 unrecoverable state, VNC/helper가 동시에 과소비해 입력을 막는 상태 |
| Input lane | Compose, direct key, pointer event가 stream/decode backlog와 분리되어 UI freeze 없이 처리된다. Korean/CJK compose와 200자 혼합 문장 전송이 관찰 통과한다. | helper-native insertion이 기본 경로로 동작하고 clipboard/keystroke fallback 전환이 사용자 draft를 잃지 않는다. | 첫 글자 이후 soft keyboard freeze, 입력 누락/중복/순서 뒤틀림, paste 실패 후 draft 손실, pointer/video 때문에 key queue가 막히는 상태 |
| Viewport interaction | pinch, pan, zoom-fill, cursor-follow, trackpad drag가 local transform으로 즉시 반응하고 remote frame cadence에 묶이지 않는다. | 사진 앱에 가까운 pinch/pan 체감으로, stream load 중에도 local gesture long-frame spike가 사용자에게 보이지 않는다. | 손가락보다 화면이 반박자 늦음, zoomed cursor-follow pan이 뒤늦게 따라옴, fit-scale drag가 불필요하게 stream을 막는 상태 |
| Device UX | iPhone physical gate, iPad smoke, light/dark screenshot audit, keyboard-up session layout이 모두 통과한다. | iPhone과 iPad에서 30분 sustained session이 모두 통과하고 background/foreground, orientation, split view가 자연스럽다. | iPhone에서 session 진입 직후 touch/input 불능, keyboard가 화면을 과도하게 밀어냄, theme에서 핵심 UI가 안 보임 |
| Thermal, power, traffic | 30분 iPhone session에서 sustained serious thermal이 없고, poor-network mode에서 traffic proxy와 input responsiveness가 함께 유지된다. | constrained cellular 후보에서도 FPS, freshness, request area, reconnect가 균형 있게 degrade된다. | FPS만 올리고 payload/request pressure가 폭증, Low Power/Thermal에서 input responsiveness까지 희생, device heat runaway |
| Diagnostics | 실패는 privacy-safe fixed label, issue code, next action으로 재현 가능하게 남는다. | benchmark artifact가 원인 축과 다음 실험 후보를 자동으로 좁힌다. | "failed"만 있고 DNS/TCP/RFB/auth/stream/input/thermal 중 어디인지 알 수 없는 로그, 민감 정보가 export되는 로그 |

### 2.3 Evidence Contract

품질 기준은 코드 리뷰만으로 통과 처리하지 않는다. 각 Green/Gold 주장은 다음
증거 중 하나 이상을 가져야 한다.

- benchmark artifact: mode, device class, transport mode, network profile,
  verdict, fixed failure labels, recommended next action을 포함한다.
- fake-server/protocol test: VNC/RFB behavior, input queue, fallback state를
  재현한다.
- screenshot/video/manual-device log: iPhone을 먼저 기록하고, iPad는 그 다음에
  기록한다.
- diagnostic privacy test: 성능 로그가 민감 payload를 내보내지 않음을 확인한다.

증거가 없으면 해당 항목은 "추정상 개선"일 수는 있어도 Green 근거가 아니다.
성능/UX PR은 명확한 개선 수치나 관찰 증거가 있을 때만 만든다. 예를 들어
FPS, frame freshness, gesture long-frame 비율, input responsiveness, thermal,
traffic proxy, physical-device hand-feel 중 하나 이상이 기준선보다 좋아졌다는
전후 비교가 없으면 해당 작업은 로컬 실험 또는 문서/진단 보강으로 남긴다.
일상 개발 루프에서는
`scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate`를 먼저 돌려
iPhone/iPad simulator에서 Korean/CJK Compose freeze 회귀와 viewport hot path
퇴행, viewport pressure diagnostic 회귀, trackpad viewport gesture UI 회귀를
잡는다. 이 simulator gate는 빠른 반복 기준이며, Green 승격 근거로는
manual/physical 또는 live benchmark 증거를 추가한다.

## 3. 품질 단계

| 단계 | 의미 | 제품 판단 |
| --- | --- | --- |
| Red | 연결 또는 입력이 자주 멈춘다. 진단은 가능하지만 사용 성공으로 보지 않는다. | 기본값 금지 |
| Amber | 제한된 환경에서 작업 가능하지만 끊김, 열, 입력 지연, 낮은 FPS가 남아 있다. | 실험/옵션만 가능 |
| Green | 목표 시나리오에서 30분 이상 사용할 수 있다. 주요 입력과 화면 조작이 흐름을 끊지 않는다. | 기본값 후보 |
| Gold | Chrome Remote Desktop급 체감에 근접한다. poor-network에서도 degradation이 예측 가능하다. | 목표 상태 |

## 4. 대표 시나리오

품질 목표는 아래 시나리오를 우선한다.

- iPhone에서 MagicDNS/private profile로 Mac에 접속한다.
- 원격 화면은 terminal, browser, IDE, AI CLI처럼 텍스트 중심 화면이다.
- 사용자는 Compose & Send로 한글/영어 혼합 문장을 보내고, 직접 키와
  터치패드 모드도 섞어 쓴다.
- 사용자는 zoom-fill 상태에서 읽고, 확대/축소/패닝/커서-follow를 반복한다.
- 네트워크는 Wi-Fi만이 아니라 constrained-cellular 후보도 포함한다.
- helper video는 visual primary 후보이고, VNC는 control/input/fallback
  경로로 유지된다.

## 5. 스트리밍 목표

### 5.1 Green 기준

- First useful paint: active connection에서 첫 읽을 수 있는 화면이 iPhone에서
  5초 이내에 나온다. helper-video primary 후보는 2초 이내를 목표로 한다.
- Sustained content FPS: `iphone-remote-desktop-10fps-v1` gate에서 최소
  10 content FPS를 통과해야 VNC visual path를 "원활"로 부를 수 있다.
- Helper video primary: sustained screen-capture/helper-video probe가
  `pass`, `healthy`, `smooth`, `readyForPhysicalGate`를 내야 한다.
- Frame freshness: 터미널/AI CLI의 새 출력이 250ms-class p95 update band 안에
  보인다. 이 기준을 넘으면 원인 라벨을 `receivePath`, `clientDecode`,
  `rendererUpload`, `viewportInteraction`, `thermal`, `serverCadence` 중 하나로
  분류한다.
- Fallback continuity: helper video stall, permission loss, decoder rejection,
  auth failure가 발생해도 VNC control/input session과 Compose draft는 유지된다.
- Long session: iPhone에서 30분 세션 동안 crash, permanent black frame,
  unrecoverable reconnect loop, stuck input state가 없어야 한다.

### 5.2 Gold 기준

- Helper video visual path는 terminal/AI CLI 화면에서 24fps-class 이상으로
  보이고, local zoom/pan 중 화면이 정지한 것처럼 느껴지지 않는다.
- VNC fallback은 helper video가 꺼진 경우에도 10fps gate를 통과하거나,
  통과하지 못하면 명확히 control/fallback path로만 분류된다.
- Poor-network mode는 startup survival, content freshness, request-region
  traffic pressure, reconnect behavior를 함께 만족한다. FPS만 높고 traffic이나
  tail latency가 악화되면 Gold가 아니다.

### 5.3 필수 측정

- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness`
- `scripts/run-naru-live-benchmark.sh helper-sustained-screen-probe`
- `scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark`
- physical iPhone helper-video/input gate
- sustained session diagnostic export privacy test

## 6. 키보드와 텍스트 입력 목표

### 6.1 Compose & Send

- Korean/CJK IME composition 중 첫 글자 이후 키보드가 freeze되면 Red다.
- 한글/영어/숫자/기호가 섞인 200자 문장을 10회 전송했을 때 누락, 중복,
  순서 뒤틀림, 조합 중간문자 전송이 없어야 Green이다.
- helper-native text bridge가 가능하면 composed text insertion이 기본 후보이고,
  VNC clipboard/keystroke fallback은 실패 원인이 fixed label로 남아야 한다.
- 전송 실패 시 사용자의 local draft는 보존되고, 재시도/대체 경로가 가능해야 한다.

### 6.2 Direct Keys And Hardware Keyboard

- 직접 키 입력은 pointer/stream backlog와 별도 lane에서 처리되어야 한다.
- 60초 동안 반복 key taps를 보내도 input queue가 pointer move나 video decode
  때문에 head-of-line blocking되지 않아야 한다.
- modifier lock/armed/idle 상태는 dark/light theme와 soft keyboard 위에서
  명확히 구분되어야 한다.

### 6.3 필수 측정

- helper text observed probe: ascii, latin1, unicode-hangul
- direct keystroke app-model tests
- Compose focus frame-application pacing test
- physical iPhone soft-keyboard manual run
- iPad hardware-keyboard smoke run

## 7. 터치패드, 커서, 제스처 목표

### 7.1 Zoom/Pan

- Pinch, pan, double-tap zoom은 local compositor path에서 즉시 반응해야 한다.
- 제스처 중 local transform은 60Hz-class로 따라가야 하며, gesture long-frame
  비율이 진단에서 상승하면 `viewportInteraction` 문제로 분류한다.
- zoom-fill baseline에서 패닝 경계가 튀거나 한 박자 늦게 따라오면 Amber 이하로
  본다.
- direct pinch/pan은 remote framebuffer publication을 보수적으로 defer할 수
  있지만, 손가락 밑 화면 움직임 자체는 remote frame cadence에 의존하면 안 된다.

### 7.2 Trackpad Mode

- Trackpad mode에서는 실제 remote cursor shape가 있으면 그것을 우선 표시한다.
  없을 때만 synthetic cursor를 쓴다.
- Zoomed trackpad drag에서는 cursor movement와 viewport pan이 함께 일어나야
  한다. 커서가 화면 가장자리에 붙어 있다가 뒤늦게 pan되는 체감은 실패다.
- Fit-scale trackpad drag는 viewport interaction을 소유하지 않는다. 불필요한
  frame deferral이나 upload suspension을 만들면 안 된다.
- Pointer move, click, drag, key event는 서로 다른 dispatcher/queue가 막지
  않아야 한다.

### 7.3 필수 측정

- `ViewportInputHotPathDriverTests`
- `PointerGestureResolverTests`
- `ViewportGestureRedrawThrottleTests`
- `scripts/run-naru-live-benchmark.sh simulator-input-viewport-gate`
- viewport-interaction live benchmark trace
- physical iPhone zoomed trackpad manual run

## 8. iPhone UX 목표

- 첫 화면은 connection grid이고, 각 profile은 마지막 preview와 reachable 상태를
  빠르게 보여준다.
- active session은 화면 영역이 기본 우선이다. keyboard가 올라와도 remote screen
  영역이 불필요하게 collapse되면 안 된다.
- immersive controls는 자동으로 숨고, 필요할 때 한 번의 tap으로 복귀해야 한다.
- light/dark theme에서 session, grid, diagnostics, compose, direct-key,
  trackpad cursor UI가 모두 읽혀야 한다.
- PiP mode는 watch-only이며 input을 보내지 않는다.
- background/foreground, Wi-Fi/cellular 전환 후 reconnect 상태가 fixed label로
  설명되어야 한다.

## 9. iPad UX 목표

- iPhone과 같은 session/input model을 유지하되, 더 큰 화면에서는 toolbar와
  compose dock이 답답하지 않게 확장되어야 한다.
- portrait, landscape, split view, Stage Manager에서 주요 버튼과 status badge가
  겹치거나 잘리지 않아야 한다.
- hardware keyboard와 pointer가 있을 때도 Compose & Send와 trackpad mode의
  의미가 바뀌면 안 된다.
- iPad-only affordance는 enhancement이며, iPhone gate를 우회하는 근거가 될 수
  없다.

## 10. Thermal And Power 목표

- 30분 iPhone session에서 thermal state가 sustained `serious` 이상으로 가면
  Green이 아니다.
- Low Power Mode 또는 thermal pressure가 감지되면 visual freshness를 낮추더라도
  keyboard/Compose responsiveness가 우선되어야 한다.
- helper-video primary 상태에서는 VNC visual sampling이 control/fallback 용도로
  낮아져야 하며, helper video와 VNC가 동시에 열과 bandwidth를 과소비하면 안 된다.

## 11. Poor-Network And Traffic 목표

- Traffic 목표는 FPS와 동급이다. 낮은 network에서 FPS만 올리고 request area,
  first-byte wait, payload pressure, timeout이 악화되면 실패다.
- Request-region/visible-glance 후보는 `requestRegionAreaPermille`와
  `firstFrameRequestAreaPermille` 같은 privacy-safe proxy로 평가한다.
- ContinuousUpdates는 10fps를 통과하거나 명확한 failure label을 남겨야 한다.
  실패 시 request-response fallback이 유지되어야 한다.
- Helper video가 Green이면 VNC는 visual primary가 아니라 input/control/fallback
  baseline으로 재분류할 수 있다.

## 12. Diagnostics 목표

진단은 우리가 디버깅할 수 있을 만큼 상세해야 하지만, 민감 정보는 안전해야 한다.

필수 포함:

- build/schema/run id, trigger, started/finished bucket
- profile host kind, port configured 여부, credential reference 여부
- DNS/TCP/RFB/auth/first-frame/helper-video/text-bridge/input-lane 단계별 fixed status
- stream health, decode pressure, renderer pressure, input queue pressure,
  viewport interaction pressure, thermal/power bucket
- recommended next action labels

금지:

- host name, IP, endpoint, password, token, exact timing, frame pixels,
  screenshots, framebuffer dimensions, coordinates, byte counts, composed text,
  clipboard content, raw OS error

## 13. Release Gate Checklist

기본값 승격 전에는 아래가 모두 필요하다.

- iPhone physical gate: pass
- iPad simulator/device smoke: pass
- `remote-desktop-10fps-readiness`: VNC path pass 또는 helper-video primary
  pass + VNC fallback classification
- helper video screen/app bootstrap: pass
- Compose unicode observed insertion: pass
- Direct key and trackpad focused tests: pass
- Light/dark screenshot audit: pass
- 30-minute sustained iPhone manual log: pass
- diagnostic export privacy tests: pass

## 14. 현재 기준 해석

현재 VNC-only path가 10fps gate를 통과하지 못하면 제품 목표 미달로 본다.
다만 helper-video path가 physical iPhone gate까지 통과하면, VNC는 visual primary
목표가 아니라 control/input/fallback 목표로 재분류할 수 있다.

즉, "원활한 사용"의 최종 판정은 다음 중 하나다.

1. VNC visual path가 iPhone 10fps/product gate를 통과한다.
2. Helper video visual path가 iPhone physical gate를 통과하고, VNC가 control,
   input, fallback 역할을 안정적으로 수행한다.

둘 다 실패하면 아직 Green이 아니다.
