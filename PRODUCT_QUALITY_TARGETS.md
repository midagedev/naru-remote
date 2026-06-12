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

## 2. 품질 단계

| 단계 | 의미 | 제품 판단 |
| --- | --- | --- |
| Red | 연결 또는 입력이 자주 멈춘다. 진단은 가능하지만 사용 성공으로 보지 않는다. | 기본값 금지 |
| Amber | 제한된 환경에서 작업 가능하지만 끊김, 열, 입력 지연, 낮은 FPS가 남아 있다. | 실험/옵션만 가능 |
| Green | 목표 시나리오에서 30분 이상 사용할 수 있다. 주요 입력과 화면 조작이 흐름을 끊지 않는다. | 기본값 후보 |
| Gold | Chrome Remote Desktop급 체감에 근접한다. poor-network에서도 degradation이 예측 가능하다. | 목표 상태 |

## 3. 대표 시나리오

품질 목표는 아래 시나리오를 우선한다.

- iPhone에서 MagicDNS/private profile로 Mac에 접속한다.
- 원격 화면은 terminal, browser, IDE, AI CLI처럼 텍스트 중심 화면이다.
- 사용자는 Compose & Send로 한글/영어 혼합 문장을 보내고, 직접 키와
  터치패드 모드도 섞어 쓴다.
- 사용자는 zoom-fill 상태에서 읽고, 확대/축소/패닝/커서-follow를 반복한다.
- 네트워크는 Wi-Fi만이 아니라 constrained-cellular 후보도 포함한다.
- helper video는 visual primary 후보이고, VNC는 control/input/fallback
  경로로 유지된다.

## 4. 스트리밍 목표

### 4.1 Green 기준

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

### 4.2 Gold 기준

- Helper video visual path는 terminal/AI CLI 화면에서 24fps-class 이상으로
  보이고, local zoom/pan 중 화면이 정지한 것처럼 느껴지지 않는다.
- VNC fallback은 helper video가 꺼진 경우에도 10fps gate를 통과하거나,
  통과하지 못하면 명확히 control/fallback path로만 분류된다.
- Poor-network mode는 startup survival, content freshness, request-region
  traffic pressure, reconnect behavior를 함께 만족한다. FPS만 높고 traffic이나
  tail latency가 악화되면 Gold가 아니다.

### 4.3 필수 측정

- `scripts/run-naru-live-benchmark.sh remote-desktop-10fps-readiness`
- `scripts/run-naru-live-benchmark.sh helper-sustained-screen-probe`
- `scripts/run-naru-live-benchmark.sh helper-screen-app-bootstrap-benchmark`
- physical iPhone helper-video/input gate
- sustained session diagnostic export privacy test

## 5. 키보드와 텍스트 입력 목표

### 5.1 Compose & Send

- Korean/CJK IME composition 중 첫 글자 이후 키보드가 freeze되면 Red다.
- 한글/영어/숫자/기호가 섞인 200자 문장을 10회 전송했을 때 누락, 중복,
  순서 뒤틀림, 조합 중간문자 전송이 없어야 Green이다.
- helper-native text bridge가 가능하면 composed text insertion이 기본 후보이고,
  VNC clipboard/keystroke fallback은 실패 원인이 fixed label로 남아야 한다.
- 전송 실패 시 사용자의 local draft는 보존되고, 재시도/대체 경로가 가능해야 한다.

### 5.2 Direct Keys And Hardware Keyboard

- 직접 키 입력은 pointer/stream backlog와 별도 lane에서 처리되어야 한다.
- 60초 동안 반복 key taps를 보내도 input queue가 pointer move나 video decode
  때문에 head-of-line blocking되지 않아야 한다.
- modifier lock/armed/idle 상태는 dark/light theme와 soft keyboard 위에서
  명확히 구분되어야 한다.

### 5.3 필수 측정

- helper text observed probe: ascii, latin1, unicode-hangul
- direct keystroke app-model tests
- Compose focus frame-application pacing test
- physical iPhone soft-keyboard manual run
- iPad hardware-keyboard smoke run

## 6. 터치패드, 커서, 제스처 목표

### 6.1 Zoom/Pan

- Pinch, pan, double-tap zoom은 local compositor path에서 즉시 반응해야 한다.
- 제스처 중 local transform은 60Hz-class로 따라가야 하며, gesture long-frame
  비율이 진단에서 상승하면 `viewportInteraction` 문제로 분류한다.
- zoom-fill baseline에서 패닝 경계가 튀거나 한 박자 늦게 따라오면 Amber 이하로
  본다.
- direct pinch/pan은 remote framebuffer publication을 보수적으로 defer할 수
  있지만, 손가락 밑 화면 움직임 자체는 remote frame cadence에 의존하면 안 된다.

### 6.2 Trackpad Mode

- Trackpad mode에서는 실제 remote cursor shape가 있으면 그것을 우선 표시한다.
  없을 때만 synthetic cursor를 쓴다.
- Zoomed trackpad drag에서는 cursor movement와 viewport pan이 함께 일어나야
  한다. 커서가 화면 가장자리에 붙어 있다가 뒤늦게 pan되는 체감은 실패다.
- Fit-scale trackpad drag는 viewport interaction을 소유하지 않는다. 불필요한
  frame deferral이나 upload suspension을 만들면 안 된다.
- Pointer move, click, drag, key event는 서로 다른 dispatcher/queue가 막지
  않아야 한다.

### 6.3 필수 측정

- `ViewportInputHotPathDriverTests`
- `PointerGestureResolverTests`
- `ViewportGestureRedrawThrottleTests`
- viewport-interaction live benchmark trace
- physical iPhone zoomed trackpad manual run

## 7. iPhone UX 목표

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

## 8. iPad UX 목표

- iPhone과 같은 session/input model을 유지하되, 더 큰 화면에서는 toolbar와
  compose dock이 답답하지 않게 확장되어야 한다.
- portrait, landscape, split view, Stage Manager에서 주요 버튼과 status badge가
  겹치거나 잘리지 않아야 한다.
- hardware keyboard와 pointer가 있을 때도 Compose & Send와 trackpad mode의
  의미가 바뀌면 안 된다.
- iPad-only affordance는 enhancement이며, iPhone gate를 우회하는 근거가 될 수
  없다.

## 9. Thermal And Power 목표

- 30분 iPhone session에서 thermal state가 sustained `serious` 이상으로 가면
  Green이 아니다.
- Low Power Mode 또는 thermal pressure가 감지되면 visual freshness를 낮추더라도
  keyboard/Compose responsiveness가 우선되어야 한다.
- helper-video primary 상태에서는 VNC visual sampling이 control/fallback 용도로
  낮아져야 하며, helper video와 VNC가 동시에 열과 bandwidth를 과소비하면 안 된다.

## 10. Poor-Network And Traffic 목표

- Traffic 목표는 FPS와 동급이다. 낮은 network에서 FPS만 올리고 request area,
  first-byte wait, payload pressure, timeout이 악화되면 실패다.
- Request-region/visible-glance 후보는 `requestRegionAreaPermille`와
  `firstFrameRequestAreaPermille` 같은 privacy-safe proxy로 평가한다.
- ContinuousUpdates는 10fps를 통과하거나 명확한 failure label을 남겨야 한다.
  실패 시 request-response fallback이 유지되어야 한다.
- Helper video가 Green이면 VNC는 visual primary가 아니라 input/control/fallback
  baseline으로 재분류할 수 있다.

## 11. Diagnostics 목표

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

## 12. Release Gate Checklist

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

## 13. 현재 기준 해석

현재 VNC-only path가 10fps gate를 통과하지 못하면 제품 목표 미달로 본다.
다만 helper-video path가 physical iPhone gate까지 통과하면, VNC는 visual primary
목표가 아니라 control/input/fallback 목표로 재분류할 수 있다.

즉, "원활한 사용"의 최종 판정은 다음 중 하나다.

1. VNC visual path가 iPhone 10fps/product gate를 통과한다.
2. Helper video visual path가 iPhone physical gate를 통과하고, VNC가 control,
   input, fallback 역할을 안정적으로 수행한다.

둘 다 실패하면 아직 Green이 아니다.
