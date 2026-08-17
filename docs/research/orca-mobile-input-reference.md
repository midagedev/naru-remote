# orca mobile 입력 UX 레퍼런스 — Naru 대비

작성: 2026-08-17. 읽기 전용 조사. 구현 없음.

전제: Naru는 VNC 원격 데스크톱(터미널 전용이 아님)이고, 방금 출하된 2모드(Type/Compose) 독을 유지한다. orca를 복제하지 않고, orca에서 관측된 메커니즘만 이식 후보로 올린다.

---

## 읽은 파일 목록

| # | 경로 | 확인 |
|---|------|------|
| 1 | `redhorse/CLAUDE.md` | 읽음 |
| 2 | `orca/mobile/src/terminal/terminal-accessory-keys.ts` | 읽음 |
| 3 | `orca/mobile/src/terminal/terminal-accessory-layout.ts` | 읽음 |
| 4 | `orca/mobile/src/terminal/quick-commands.ts` | 읽음 |
| 5 | `orca/mobile/src/terminal/terminal-live-input.ts` | 읽음 |
| 6 | `orca/mobile/src/terminal/terminal-live-text-commit.ts` | 읽음 |
| 7 | `orca/mobile/src/terminal/terminal-live-hangul-mirror.ts` | 읽음 |
| 8 | `orca/mobile/src/terminal/terminal-live-accessory-input.ts` | 읽음 |
| 9 | `orca/mobile/src/terminal/terminal-live-accessory-raw-send.ts` | 읽음 |
| 10 | `orca/mobile/src/terminal/terminal-live-control-send-order.ts` | 읽음 |
| 11 | `orca/mobile/src/terminal/terminal-keyboard-avoidance-lift.ts` | 읽음 |
| 12 | `orca/mobile/src/terminal/terminal-keyboard-dismiss.ts` | 읽음 |
| 13 | `orca/mobile/src/terminal/terminal-keyboard-type.ts` | 읽음 |
| 14 | `orca/mobile/src/terminal/terminal-gesture-input.ts` | 읽음 |
| 15 | `orca/mobile/src/terminal/terminal-live-dictation-routing.ts` | 읽음 |
| 16 | `orca/mobile/src/components/CustomKeyModal.tsx` | 읽음 |
| 17 | `orca/mobile/src/layout/responsive-layout-metrics.ts` | 읽음 |
| 18 | `orca/mobile/app/h/[hostId]/session/[worktreeId].tsx` | 읽음 (5300줄급; 입력·레이아웃·제스처 구간 전수, 그 외 세션 탭/파일/브라우저 경로는 검색으로 위치만 확인) |
| 19 | `NaruRemoteCore/.../AccessoryKey.swift` | 읽음 |
| 20 | `NaruRemoteCore/.../ComposeQuickKey.swift` | 읽음 |
| 21 | `NaruRemoteCore/.../StickyModifierState.swift` | 읽음 |
| 22 | `NaruRemoteCore/.../LiveTypeThroughMode.swift` | 읽음 |
| 23 | `NaruRemoteCore/.../ComposeDraft.swift` | 읽음 |
| 24 | `NaruRemote/App/.../RemoteInputDockView.swift` | 읽음 (1933줄 전수) |
| 25 | `specs/011-simplified-input-ux/spec.md` | 읽음 |

짝 테스트(설계 의도 확인용, 전수 아님): `terminal-accessory-keys.test.ts`, `terminal-accessory-layout.test.ts`, `terminal-live-hangul-mirror.test.ts`, `terminal-live-text-commit.test.ts`, `terminal-live-control-send-order.test.ts`, `terminal-live-dictation-routing.test.ts`, `terminal-keyboard-avoidance-lift.test.ts`, `terminal-webview-scroll-routing.test.ts`, `terminal-webview-tap-routing.test.ts`. 훅 본체 `use-terminal-live-input-commit.ts`, `use-terminal-live-accessory-input-commit.ts`, `use-terminal-live-pending-input-flush.ts`도 커밋 규칙을 위해 읽었다.

---

## 전제 정정 (premises)

조사 스펙이 가정한 것과 디스크가 다른 지점. 정정은 산출물이다.

1. **orca 액세서리는 페이지가 아니라 가로 스크롤 한 줄이다.** 과제 배경의 “Fn 페이지”는 Naru spec 011의 이식 형태다. orca 세션은 `ScrollView horizontal` + `keyboardShouldPersistTaps="always"` (`[worktreeId].tsx:4698-4703`).
2. **orca 액세서리 바에 sticky 수식키(armed/locked)는 없다.** 내장 키는 미리 구운 PTY 바이트(`Ctrl+C` → `\x03`)이고, 조합은 `CustomKeyModal`에서 Ctrl/Alt/Shift를 바이트에 베이크한다. Cmd는 의도적으로 없다 (`CustomKeyModal.tsx:26-29`).
3. **`terminal-gesture-input.ts`는 제스처 인식기가 아니라 PTY 바이트 검증기다.** 터치→시퀀스 변환은 WebView JS(`terminal-webview-html.ts` 등)가 하고, 이 파일은 그 바이트가 SGR/default mouse/arrow-scroll 집합인지 센다 (`terminal-gesture-input.ts:68-95`).
4. **`LiveTypeThroughMode.swift` 주석은 아직 “세션 기본값은 Compose”다** (`LiveTypeThroughMode.swift:35-39`, `74-76`). spec 011 US1과 `promoteTypeThroughDefaultOnSessionActivationIfNeeded()` (`NaruRemoteAppModel.swift:6019-6040`)가 그 기본값을 Type로 바꿨다. 타입 이름 `composeDefault`는 빈 상태 리셋용으로 남아 있다.
5. **`ComposeQuickKey` / 독 주석은 아직 “Esc/Tab/⌃C/화살표는 Direct 특수 페이지”다** (`ComposeQuickKey.swift:77-83`, `RemoteInputDockView.swift:697-703`). Direct 표면은 spec 011에서 퇴역했고, 그 키의 대부분은 `AccessoryKey` 스트립으로 갔다. **⌃C는 스트립에 없다** — `ComposeQuickKey.controlC`는 모델에만 남고 독이 렌더하지 않는다.
6. **`CLAUDE.md:18`은 활성 피처를 `005-connection-grid-diagnostics`로 적는다.** `AGENTS.md` / `.specify/feature.json` / spec 011 Status는 011이 구현 완료라고 한다. 본 조사는 spec 011을 계약으로 쓴다.

---

## 1. 액세서리 키 인벤토리·배치

### 1.1 orca 내장 키 (canonical 순서)

`TERMINAL_ACCESSORY_KEYS` (`terminal-accessory-keys.ts:202-248`). 전송 단위는 X11 keysym이 아니라 **PTY 바이트 문자열**.

| 순서 | `id` | 라벨 | bytes | `repeatable` |
|------|------|------|-------|--------------|
| 1 | `escape` | Esc | `\x1b` | 아니오 |
| 2 | `tab` | Tab | `\t` | 아니오 |
| 3 | `enter` | Enter | `\r` | 아니오 |
| 4 | `shiftTab` | Shift+Tab | `\x1b[Z` | 아니오 |
| 5 | `space` | Space | ` ` | 아니오 |
| 6 | `backspace` | ⌫ | `\x7f` | **예** |
| 7 | `delete` | Del | `\x1b[3~` | **예** |
| 8–11 | `arrowUp/Down/Left/Right` | ↑↓←→ | CSI A/B/D/C | **예** |
| 12 | `ctrlC` | Ctrl+C | `\x03` | 아니오 |
| 13 | `ctrlD` | Ctrl+D | `\x04` | 아니오 |
| 14 | `ctrlL` | Ctrl+L | `\x0c` | 아니오 |
| 15 | `ctrlZ` | Ctrl+Z | `\x1a` | 아니오 |
| 16 | `ctrlR` | Ctrl+R | `\x12` | 아니오 |
| 17 | `ctrlA` | Ctrl+A | `\x01` | 아니오 |
| 18 | `ctrlE` | Ctrl+E | `\x05` | 아니오 |
| 19 | `ctrlW` | Ctrl+W | `\x17` | 아니오 |
| 20 | `ctrlU` | Ctrl+U | `\x15` | 아니오 |

정렬 이유(코드·테스트에서 읽히는 범위):

- Shift+Tab은 “터미널이 `ESC [ Z`를 reverse-tab으로 인식한다”는 주석 (`terminal-accessory-keys.ts:206-207`).
- Space는 Enter/Tab/Shift+Tab 근처, Backspace/Delete/화살표보다 앞 (`terminal-accessory-keys.test.ts:26-38`, `terminal-accessory-layout.test.ts:35-47`).
- 반복은 명시적 집합만: `backspace`, `delete`, 네 화살표 (`terminal-accessory-keys.test.ts:52-64`). 주석: “non-repeatable keys fire once (holding is destructive)” (`[worktreeId].tsx:3371`).
- Ctrl 코드 키는 터미널 관용 코드(인터럽트/EOF/클리어/서스펜드/역검색/행 이동/단어·행 삭제)로, sticky 수식키가 아니라 **완성된 바이트 버튼**.

내장 키에 **Home/End/PgUp/PgDn/Ins/F1–F12는 없다.** 그 집합은 커스텀 단축키 피커 `TERMINAL_SHORTCUT_SPECIAL_KEYS` (`terminal-accessory-keys.ts:168-200`)와 `SPECIAL_KEY_GROUPS` (`CustomKeyModal.tsx:36-54`: Editing / Navigation / Function)에만 있다.

### 1.2 그룹·페이지·스크롤

페이지 전환 없음. 한 줄 가로 스크롤 (`[worktreeId].tsx:4671-4861`).

고정(스크롤 밖):

1. 키보드가 떠 있을 때만 **Dismiss** (`keyboardLift > 0`, `[worktreeId].tsx:4673-4696`). 주석: ScrollView 밖에 두어 스크롤로 사라지거나 숨겨지지 않게 (#5106).
2. 그 다음 ScrollView 안 선두: **phone/desktop 표시 모드**, **live⇄buffered 토글**, 조건부 **Paste**, 내장 키, 커스텀 키, **+** (커스텀 추가).

가시성·순서는 `TerminalAccessoryLayoutPreference` version 2 (`terminal-accessory-layout.ts:7-14`, `86-122`). AsyncStorage 키 `orca:terminal-accessory-layout`. 새 내장 키는 “끝에 매달지 말고 canonical 이웃 옆에 삽입” (`terminal-accessory-layout.ts:48-75`).

### 1.3 키 반복

`repeatable`만 `onPressIn`에서 즉시 1회 + 400 ms 후 45 ms 간격 (`[worktreeId].tsx:3371-3396`, `4792-4808`). 비반복 키는 `onPress` 1회. 탭 전환/언마운트 시 `stopAccessoryRepeat`. 콜백은 ref로 잡아 홀드 중 탭 전환이 옛 터미널로 나가지 않게 한다 (`3374-3376`).

### 1.4 커스텀 키 모델

`CustomKey` (`CustomKeyModal.tsx:17-22`): `{ id, label, bytes, enter }`. 저장 키 `orca:custom-accessory-keys`. 작성 플로우는 두 종류 (`Step`, `CustomKeyModal.tsx:24`, `209-226`):

- **Shortcut Combo**: Ctrl/Alt/Shift + 인쇄 가능 키 또는 special key. `buildTerminalShortcutKey`가 바이트를 만든다. Alt는 ⌥ 글리프 — “macOS 호스트에서 Option만이 터미널이 읽을 ESC-prefix를 만든다”. **Cmd는 의도적으로 없음** — “macOS가 셸에 닿기 전에 삼킨다” (`CustomKeyModal.tsx:26-34`).
- **Text Macro**: 라벨 + 본문 + `Press Enter` 스위치. Enter면 `bytes = text + '\r'` (`CustomKeyModal.tsx:167-175`). 저장된 `enter` 필드는 항상 `false`(이미 바이트에 `\r`을 넣음).

롱프레스(400 ms)로 커스텀 키 삭제 (`[worktreeId].tsx:4834-4838`).

특수키 피커 그룹 (`CustomKeyModal.tsx:36-54`): Editing 4열, Navigation 4열, Function 6열. 주석: “한 줄 wrap이면 F7–F12가 잘린다”.

### 1.5 Quick commands (액세서리와 별층)

`quick-commands.ts`는 데스크톱과 동일한 저장 커맨드/에이전트 프롬프트 런처다. 액세서리 바와 모델이 다르다. 세션 탭 스트립의 Quick Commands 버튼으로 연다 (`[worktreeId].tsx:4466-4482`). Naru VNC 독과 1:1이 아니다. 가까운 대응은 아래 텍스트 매크로.

---

## 2. 수식키 의미론

### 2.1 orca: sticky 없음, 바이트가 조합

액세서리 바의 Ctrl+C 등은 수식키 슬롯이 아니다. 이미 `\x03` 같은 완성 바이트다.

커스텀 단축키의 수식키 순서: `['ctrl', 'alt', 'shift']` (`terminal-accessory-keys.ts:36`, `379-382`). CSI 파라미터는 xterm 규칙 `1 + shift+1 + alt+2 + ctrl+4` (`347-358`). 미수정 F1–F4는 SS3(`ESC O P/S`), 수식키가 있으면 CSI `1;N` (`285-288`).

### 2.2 raw send vs 라이브 입력 우선순위

액세서리 탭 → `createTerminalLiveAccessoryInput` (`terminal-live-accessory-input.ts:13-21`): `backspace`/`delete`만 `localEdit` 부착.

그다음 `handleLiveInputAccessoryBytes` (`use-terminal-live-accessory-input-commit.ts:54-96`)가 `getTerminalLiveAccessoryBytesDecision` (`terminal-live-text-commit.ts:52-67`)으로 분기:

| 조건 | kind | 동작 |
|------|------|------|
| `localEdit`이고 `heldText` 또는 `sentText`가 있음 | `local-edit` | 필드만 고치고 미러 diff가 PTY erase를 냄. raw 바이트 금지 (이중 삭제 방지, `terminal-live-text-commit.ts:39-43`) |
| `heldText.length > 0` | `commit-held-then-send` | held 음절을 먼저 flush한 뒤 컨트롤 바이트 |
| 그 외 | `send-now` | in-flight 미러 flush를 기다린 뒤 raw 허용 |

`send-now`의 raw 경로: `handleAccessoryKey`가 `allow-raw`일 때만 `sendTerminalLiveAccessoryRawBytes` (`[worktreeId].tsx:2965-2982`). 타깃이 바뀌었으면 버린다 (`terminal-live-accessory-raw-send.ts:19-27`, `terminal-live-accessory-raw-send-target.ts:12-17`).

컨트롤 바이트는 항상 **pending 텍스트 flush 이후** (`terminal-live-control-send-order.ts:3-12`). flush 실패면 컨트롤을 보내지 않는다 (테스트 `terminal-live-control-send-order.test.ts:5-26`).

라이브가 꺼진 핸들: pending flush만 기다린 뒤 `allow-raw` (`use-terminal-live-accessory-input-commit.ts:16-19`, `58-59`). 버퍼 모드에서도 액세서리는 PTY로 바로 간다.

### 2.3 Naru 대응

Naru는 **sticky 수식키**가 스트립 선두다.

- 순서: `control, alt, meta, shift` — “맥 키보드 하단 열” (`AccessoryKey.swift:3-10`).
- 슬롯: `idle` / `armed` / `locked`. 400 ms 더블탭으로 lock (`StickyModifierState.swift:14-22`, `57`).
- 다음 비수식 방출 후 armed만 해제 (`StickyModifierState.swift:108-116`).
- 스트립 키는 `sendAccessoryKey`가 `activeModifiers`로 감싸고 `consumeAfterNonModifierEmission()` (`NaruRemoteAppModel.swift:6815-6842`).
- 하드웨어 키는 sticky를 건드리지 않는다 (`NaruRemoteAppModel.swift:6730-6735`).
- 수식키 탭은 세션이 없어도 상태만 갱신할 수 있다 (`NaruRemoteAppModel.swift:6657-6664`).
- `ComposeQuickKey`는 sticky를 읽지 않고 고정 modifier를 싣는다 (`NaruRemoteAppModel.swift:6788-6790`). 독은 지금 ⌫/↵만 이 경로로 그린다.

**충돌 규칙 공백:** Naru `sendAccessoryKey`는 라이브 창·marked IME·pending insert를 보지 않는다. 조합 중 Esc를 누르면 키심이 즉시 나가고, 로컬 IME 후보는 그대로다. orca의 `commit-held-then-send`에 해당하는 장벽이 없다.

---

## 3. 라이브 입력·한글

### 3.1 orca 커밋 단위

단어 debounce가 아니다.

- ASCII: 코드포인트마다 즉시 미러 (`terminal-live-hangul-mirror.test.ts:93-100`).
- 한글: **마지막 코드포인트만 hold**. 앞 음절은 확정되어 PTY로 나간다 (`terminal-live-hangul-mirror.ts:23-37`).
- hold 확정: 300 ms 타이머 `TERMINAL_LIVE_HELD_SYLLABLE_COMMIT_DELAY_MS` (`terminal-live-hangul-mirror.ts:1-3`, 타이머 장전 `use-terminal-live-pending-input-flush.ts:107-112`).
- 조기 확정이 틀리면 DEL로 지우고 다시 hold (`terminal-live-hangul-mirror.ts:1-2`, `23-26`; 테스트 `간→가나`는 중간 음절을 보내지 않음, `하` 타이머 확정 후 `한`은 `\x7f` 보정).
- 뒤에 공백/ASCII가 오면 hold가 풀린다 (테스트 `terminal-live-hangul-mirror.test.ts:102-116`).
- 범위: Hangul Jamo / Compatibility Jamo / Extended-A / 음절 (`terminal-live-hangul-mirror.ts:7-14`).
- payload = `DEL × eraseCount + appendText` (`terminal-live-hangul-mirror.ts:59-61`).
- 상한 256 KiB (`terminal-live-input.ts:3`, `[worktreeId].tsx:2991-2994`).

RN에 composition 이벤트가 없어서 “끝 음절만 hold + DEL 보정”으로 우회한다 (`terminal-live-hangul-mirror.ts:23-26`).

### 3.2 로컬 미러 UX

라이브 필드는 **숨김** `TextInput`: `opacity: 0`, `1×1` (`mobile-session-command-input-styles.ts:189-195`, `[worktreeId].tsx:4901-4921`). 보이는 면은 `MobileTerminalLiveInputStatus` — 제목 `Live input` / `Listening` / …, 상세는 `liveInputText` 또는 `Tap to show keyboard` (`MobileTerminalLiveInputStatus.tsx:21-36`, `[worktreeId].tsx:4865-4885`).

JS는 필드를 원문 그대로 두고, PTY 미러만 `normalizeTerminalTextInput` (`use-terminal-live-input-commit.ts:121-125`). 주석: iOS는 JS가 native 텍스트와 다른 값을 쓰면 dictation/IME를 죽인다.

버퍼 모드: 보이는 `Type a command…` 필드 + Send (`[worktreeId].tsx:4924-4978`). 오프라인에서도 조합 가능 (`editable={canCompose}`, `#6713`).

### 3.3 IME 중 액세서리

위 2.2. Backspace/Delete는 필드가 비어 있지 않으면 로컬 편집 (`terminal-live-text-commit.ts:39-43`, `69-83`). accessory Delete(forward)는 필드 텍스트를 지우지 않는다 — “hidden input 끝의 forward-delete를 미러할 뿐”.

특수키(Tab/Esc/화살표) + held → `commit-held-then-send` (`terminal-live-text-commit.test.ts:35-42`). Enter는 `onSubmitEditing`만 — key map에 넣으면 CR이 두 번 나간다 (`terminal-live-input.ts:33-35`).

연결이 끊기면 미러 상태를 버린다. “PTY에 뭐가 갔는지 모르므로 낡은 미러가 재접속 첫 전송을 오염시킨다” (`use-terminal-live-input-commit.ts:73-77`).

### 3.4 Dictation

`routeDictationTranscript(transcript, liveInputActive)` (`terminal-live-dictation-routing.ts:9-16`):

- live → `{ kind: 'live-insert' }` — PTY에 텍스트만, **자동 Return 없음** (`terminal-live-dictation-routing.ts:1-3`).
- buffered → `{ kind: 'buffered-append' }` — 기존 텍스트 뒤에 공백 하나 (`18-25`).

세션 화면은 native chat이 보이면 채팅 작성란으로 가로채고, 아니면 위 라우터 (`[worktreeId].tsx:1113-1147`). live-insert 전에 `flushPendingLiveInputBeforeExternalSend` — “외부 바이트(dictation/paste)는 필드 에코 뒤에 와야 이후 diff가 그것을 지우지 않는다” (`use-terminal-live-input-commit.ts:105-106`).

### 3.5 Naru 대응

Naru Type은 UIKit `markedTextRange`를 커밋 경계로 쓴다. RN hold-음절 우회가 아니다.

- marked 텍스트는 보내지 않는다 (`RemoteInputDockView.swift:953-956`, `LiveEditingWindow.swift:51-52`).
- 커밋 스냅샷은 grapheme-cluster prefix diff (`LiveEditingWindow.swift:204-227`).
- insert 사다리: `helperNativeInsert` → `clipboardChunk` → Unicode keysym `keyEvent` (`LiveDeliveryLadder.swift:10-15`). 컨트롤(BackSpace/Return)은 항상 key lane (`LiveDeliveryLadder.swift:6-8`).
- 같은 배치에서 delete가 insert보다 앞 (`LiveEditingWindow.swift:88-90`, `NaruRemoteAppModel.swift:6284-6293`).
- 봉인 후 삭제는 이 창이 보낸 글자만 (`LiveEditingWindow.swift:39-44`, `123-127`).
- Return은 newline + seal + 새 창 (`LiveEditingWindow.swift:146-154`, `NaruRemoteAppModel.swift:6149-6163`).
- 포인터가 삽입점을 옮길 수 있으면 seal (`NaruRemoteAppModel.swift:6188-6196`).
- 에디터는 보이는 `UITextView`. live일 때 모델의 `liveFieldText`가 권위 미러 (`NaruRemoteAppShell.swift:801-805`).
- marked 중에는 모델이 필드를 덮어쓰지 않는다 (T015, `RemoteInputDockView.swift:968-974`, `NaruRemoteAppModel.swift:6120-6122`).
- Compose 전파는 포커스 중 억제, 120 ms 디바운스 (`RemoteInputDockView.swift:22`, `1157-1166`, `1244-1250`).
- 독 액션 ⌫/↵는 Type에서 `liveDeleteBackward` / `liveNewline`, Compose에서 `ComposeQuickKey` (`RemoteInputDockView.swift:733-743`).

Naru Core에는 dictation 라우터가 없다. 시스템 키보드 받아쓰기는 에디터로 들어가 일반 Type/Compose 커밋을 탄다. orca처럼 “완성 transcript를 live-insert vs buffered-append로 가르는” 층이 없다.

---

## 4. 키보드·레이아웃 메커니즘

### 4.1 Keyboard avoidance (orca)

Expo SDK 55 edge-to-edge는 IME가 윈도우를 줄이지 않는다. 높이를 직접 재고 **translate**한다. PTY를 리사이즈하지 않는다 (`[worktreeId].tsx:876`, `4663-4668`).

- iOS: `keyboardHeight - insets.bottom` (홈 인디케이터가 키보드 높이에 포함됨). Android: `keyboardHeight` 그대로 (`4168-4173`).
- 독: `transform: [{ translateY: -keyboardLift }]` (`4668`).
- 터미널: `computeActiveTerminalKeyboardLift` (`terminal-keyboard-avoidance-lift.ts:9-29`).
  - lift≤0 → 0
  - 메트릭/행/프레임 없음 → 전체 lift
  - `altScreen` → 전체 lift (TUI 푸터가 캐럿 아래일 수 있음, `23-24`)
  - 그 외: `anchorRow = max(cursorY, contentBottomRow)`가 독 상단+행 여백 아래로 가도록 **필요한 만큼만** lift, 상한은 전체 키보드 높이.

### 4.2 Dismiss

`dismissTerminalKeyboard` (`terminal-keyboard-dismiss.ts:10-17`): (1) pending live-focus 타이머 취소 (2) live blur (3) command blur (4) `Keyboard.dismiss()`. 순서 이유: “Hide 직후 지연 포커스가 iOS 키보드를 다시 연다”.

고정 Dismiss 버튼은 키보드가 떠 있을 때만 (`[worktreeId].tsx:4673-4685`). a11y: `Dismiss keyboard` / `Hides the software keyboard and keeps the current terminal session open.`

선택 모드가 켜지면 `Keyboard.dismiss()` (`[worktreeId].tsx:3424-3431`). 탭 액션 시트는 키보드가 내려간 뒤에 연다 (`3049-3079`).

### 4.3 Keyboard type

양쪽 다 `'default'`만 반환 (`terminal-keyboard-type.ts:2-17`). 주석: “default는 비라틴 IME를 남긴다. ASCII-only는 IME를 숨긴다.” 시그니처의 platform/autocomplete 인자는 호출부 안정용, 더 이상 키보드를 바꾸지 않는다.

Naru 에디터는 시스템 `UITextView` 기본 키보드. ASCII-only `keyboardType`을 강제하지 않는다 (`RemoteInputDockView.swift:1708-1715`).

### 4.4 Responsive metrics (orca)

`getResponsiveLayoutMetrics` (`responsive-layout-metrics.ts:29-44`):

| 상수 | 값 | 역할 |
|------|-----|------|
| `WIDE_LAYOUT_MIN_WIDTH` | 700 | 가로만으로는 폰 가로모드가 잡힘 |
| `TABLET_LAYOUT_MIN_SHORT_SIDE` | 600 | 짧은 변 — 좁은 iPad 스플릿은 폰 레이아웃 |
| `CONTENT_MAX_WIDTH` | 720 | |
| `MODAL_MAX_WIDTH` | 480 | |
| `horizontalPadding` | wide면 `spacing.xl`, 아니면 `lg` | |

`isWideLayout = width≥700 && isTabletLayout`. 세션은 `isWideLayout`일 때 파일을 옆에 도킹 (`[worktreeId].tsx:753-763`, `session-panel-host.ts:33-42`). 필요 폭 = dock + 메인 최소 360.

### 4.5 세션 화면 배분 (orca)

위에서 아래 (`[worktreeId].tsx:4316-4982`, 스타일 `mobile-session-frame-styles.ts`):

1. **상단 크롬** (`sessionChrome`, top safe area만): 뒤로 / 워크트리 제목+연결 메타 / Files / Source Control / More. `sessionTopBar` minHeight 44.
2. **탭 스트립** maxHeight 36 + 고정 `+` + Quick Commands. `keyboardShouldPersistTaps="handled"` (#5106).
3. **콘텐츠** `flex:1` (`terminalFrame` / markdown / file / browser). 터미널이 남는 높이를 다 먹는다.
4. **커맨드 독** (마크다운/파일/브라우저/네이티브챗이 아닐 때): 액세서리 바 + 입력 바(라이브 숨김 또는 버퍼). 키보드와 함께 위로 translate. zIndex 20.
5. wide면 오른쪽 `SessionDockColumn`.

라이브 입력 포커스 지연 50 ms (`terminal-live-input.ts:217-228`). Android는 IME가 내려가도 hidden TextInput이 포커스를 유지할 수 있어 blur 후 refocus (`231-248`).

### 4.6 Naru 대응

세션은 원격 화면이 hero다 (`SessionViewportView.swift:113-123`). 키보드가 화면을 찌그러뜨리지 않고, 라이브 세션은 독이 inset/overlay로 높이를 줄인다.

독 배치 (`NaruRemoteAppShell.swift:475-535`, `824-837`):

- 유휴 라이브: **플로팅** Type/Compose 알약 (`RemoteInputDockView.swift:340-406`). 하드웨어 키 리스너는 키보드가 내려 있어도 Type에서 산다 (`347-355`).
- 포커스/확장 요청: **compact** 핀 — 모드 토글 + 에디터 + 액세서리 + ⌫/↵ (`312-328`, `433-476`).
- 플로팅→핀은 키보드가 오르기 **전에** 옮겨, 새 인스턴스가 first responder를 갖게 한다 (`NaruRemoteAppShell.swift:787-790`, `RemoteInputDockView.swift:495-508`).

Dismiss 전용 해치는 없다. `UITextView.keyboardDismissMode = .interactive` (`RemoteInputDockView.swift:1715`). 플로팅으로 돌아가려면 포커스를 잃고 초안이 비어야 한다 (`891-898`).

폰/아이패드: 독은 `horizontalSizeClass == .compact`일 때 폭을 캡한다 (`RemoteInputDockView.swift:247-250`). orca식 700/600 마스터-디테일 분기와는 다른 축이다.

표준 레이아웃(비라이브/홈이 아닌 상세)은 세그먼트 Type/Compose + 스트립 + 에디터 (`266-296`). 라이브 세션의 일상 경로는 플로팅/컴팩트다.

---

## 5. 제스처

### 5.1 orca `terminal-gesture-input`이 정의하는 것

인식이 아니라 **바이트 화이트리스트** (`terminal-gesture-input.ts`):

허용 시퀀스:

- 화살표 스크롤: `ESC [ A/B`, `ESC O A/B` (`55-65`)
- SGR 마우스: `ESC [<` + button `0|32|64|65` + col/row + `M/m` (`5-7`, `29-53`). button 0은 press/release, 그 외는 `M`(press/motion)만
- 기본 마우스: `ESC [ M` + button 32/35/64/96/97, col/row 33–126 (`9-27`)

가드: 길이 1–2048, 시퀀스 ≤32 (`2-3`, `68-91`). 하나라도 아니면 `null` → 세션이 버린다 (`[worktreeId].tsx:3328-3338`).

세션 게이트: alt-screen이거나 mouse-tracking 모드일 때만 (`3327-3331`). 토큰 버킷으로 SSH-safe rate limit (`3190-3213`). 큐는 재접속 뒤 낡은 화살표가 TUI를 밀지 않게 TTL을 둔다 (`3242`).

실제 터치 분류는 WebView JS(이 과제 필수 목록 밖, 테스트로만 확인):

- 일반 버퍼 스크롤 vs alt-screen/mouse-tracking 휠 (`terminal-webview-scroll-routing.test.ts:50-68`)
- 탭은 URL/파일 탭과 선택 롱프레스를 가른다. 탭이 롱프레스 slop를 공유하면 몇 픽셀 jitter에 삼켜진다 (`terminal-webview-tap-routing.test.ts:1-5`)
- 선택 모드가 키보드를 내린다 (`[worktreeId].tsx:3424-3431`)
- 핀치 줌은 로컬 텍스트 스케일, PTY 입력이 아님 (`[worktreeId].tsx:4621-4625`)

**추정(필수 파일을 넘어서므로):** 커서 이동은 액세서리 화살표 또는 마우스 트래킹이 켜진 TUI의 셀 클릭이다. 일반 버퍼에서 한 손가락 드래그는 스크롤백이지 커서 이동이 아니다.

### 5.2 Naru 대응 (VNC 포인터)

인식은 `MetalFramebufferHostingView` (`MetalFramebufferView.swift:527-532`, `782-873`). 계약은 spec 011 US3:

| 제스처 | Naru | 비고 |
|--------|------|------|
| 단탭 | 즉시 좌클릭. **더블탭/롱프레스/두 손가락 탭에 failure requirement 없음** (`788-794`) | orca 교훈을 spec이 명시 |
| 더블탭 | 두 번째 좌클릭. 줌 아님 (`796-799`, `1126-1138`) | |
| 롱프레스 0.5 s | 우클릭 (`816-821`, `1142-1148`) | |
| 두 손가락 탭 | 두 모드 모두 우클릭 (`807-814`) | |
| 한 손가락 드래그 | direct: 포인트에서 원격 드래그(움직임 후에만 down). trackpad: 상대 커서 | 탭-슬롭을 안 넘기면 클릭만 (`839-850`) |
| 두 손가락 드래그 | 원격 휠 (`823-828`) | 핀치 중이면 스크롤로 안 봄 (`680-683`) |
| 핀치 | 로컬 줌만 (`531-532`, `832-837`) | |

`PointerGestureResolver`가 모드별 결과를 순수 함수로 낸다 (`PointerGestureResolver.swift:69-72`). 핀치/팬만 하면 RFB가 비다 (`33-36`). 기본 모드는 `.directTouch` (`PointerControl.swift:17-20`).

도메인 차이: orca 제스처는 **PTY 바이트**(xterm 마우스/스크롤백)이고, Naru는 **RFB PointerEvent + 로컬 뷰포트**다. 바이트 검증기를 Naru에 옮길 대상이 아니다.

---

## 6. Naru 갭 분석·채택 권고

권고는 orca에서 관측된 메커니즘의 이식만. 새 스트립 디자인·새 모드·새 카피는 없음. 전제: Type/Compose 2모드, 헌법 §I(로컬 조합 + 주입 어댑터 명시), §VI(폰 소프트키보드 + 장시간 터미널/AI-CLI), Helper optional.

### 6.1 질문 1 — 액세서리 인벤토리

| 축 | orca | Naru | 차이 |
|----|------|------|------|
| 전송 | PTY bytes | X11 keysym + sticky wrap | 프로토콜이 다름. 복제 금지 |
| 내장 집합 | Esc Tab Enter S-Tab Space ⌫ Del 화살표 + Ctrl+C/D/L/Z/R/A/E/W/U | Esc Tab Del 화살표 + Fn(Home End Pg Ins F1–12) + sticky ⌃⌥⌘⇧ | orca는 완성 코드 버튼. Naru는 수식키×다음 키. Naru에 Enter/Space/S-Tab/Ctrl 코드가 스트립에 없음 |
| 배치 | 가로 스크롤 1행, 순서 저장 | 고정 primary + Fn 토글 2행 | spec 011이 아이폰 폭 때문에 페이지를 고름 (`AccessoryKey.swift:138-150`, `RemoteInputDockView.swift:795-863`) |
| 반복 | 400/45 ms, 파괴 키는 1회 | 탭 1회, 오토리핏 없음 | |
| 커스텀 | Shortcut Combo + Text Macro, show/hide/reorder | 없음 | |
| ⌃C 원탭 | 내장 `ctrlC` | `ComposeQuickKey.controlC`는 모델만. 스트립 미렌더 | Direct 퇴역 후 공백 |

| 우선 | 권고 (orca에서 관측) | 예상 편집 | 리스크 |
|------|----------------------|-----------|--------|
| **P0** | 스트립 화살표·Del에 **홀드 리핏** (400 ms 후 45 ms). 비반복 키는 1회 | `RemoteInputDockView.swift` 버튼; 리핏 타이머는 App 또는 뷰. `AccessoryKey`에 `repeatable` | 리핏이 라이브 창 delete 클램핑/봉인과 어긋나면 원격만 밀림. 세션  multipath에서 타이머 타깃을 고정해야 함 |
| **P0** | **원탭 Ctrl+C** (orca `ctrlC`). 이미 `ComposeQuickKey.controlC` → `Ctrl down→c→up` (`ComposeQuickKey.swift:61-65`). primary 스트립에 그 키만 노출 | `AccessoryKey`에 chord case를 두거나 스트립이 `ComposeQuickKey.controlC`를 그리기; `RemoteInputDockView.swift` primary 행 | 폭. sticky ⌃ + `c`와 봉투는 같아야 함 (spec 011 US2). IME 켜진 Type에서 `c`를 문자로 받으면 안 됨 — chord는 key lane |
| **P1** | 내장 가시성·순서 저장 (layout preference v2 + 새 키는 이웃 옆) | 새 Core 모델 + 기존 설정/시트. `AccessoryKey.swift`, persistence | 설정 화면은 spec 011 Out of scope. 시트 추가면 별 spec |
| **P1** | 커스텀 **Shortcut Combo + Text Macro** (Cmd 제외는 orca 이유 — VNC 데스크톱에선 ⌘가 유효하므로 Naru는 기존 sticky ⌘를 쓰고, 매크로 빌더의 수식키는 ⌃⌥⇧ + 기존 ⌘ sticky와 맞출 것) | `CustomKeyModal`에 해당하는 Naru 시트; 방출은 `KeystrokeEmitter` | 매크로 본문을 로그에 넣지 말 것 (§IV). 텍스트 매크로는 Type insert 사다리로 (한글), 키 코드는 key lane |
| **P2** | Enter / Space / Shift+Tab을 스트립에 (orca 내장) | `AccessoryKey` cases + primary 또는 Fn | Shift+Tab은 sticky ⇧+Tab으로 이미 가능. 원탭은 폭을 대가 |

⌘V 등은 이미 `MacSessionControl` 메뉴. orca 터미널 바에 없는 것이므로 여기서 늘리지 않는다.

### 6.2 질문 2 — 수식키·충돌

| 축 | orca | Naru | 차이 |
|----|------|------|------|
| sticky | 없음 | armed/locked 400 ms | Naru가 VNC 데스크톱에 맞음. 유지 |
| 조합 순서 | 바이트 빌더 ctrl-alt-shift; CSI 1+1+2+4 | `KeystrokeEmitter`가 modifier down→key→up | 유지 |
| IME/held vs 액세서리 | flush 후 컨트롤; 실패 시 컨트롤 생략 | `sendAccessoryKey`가 즉시 키심 | **갭** |
| raw vs live | live면 local-edit / commit-held; 아니면 raw | 모드 不分, 같은 keysym 경로 | Type 창과 직교하지 않음 |

| 우선 | 권고 | 예상 편집 | 리스크 |
|------|------|-----------|--------|
| **P0** | orca `commit-held-then-send` + `sendTerminalLiveControlAfterPendingFlush`: 액세서리/퀵키 전에 **marked 텍스트를 커밋하거나, pending live insert를 드레인한 뒤** 키심. flush 실패 시 컨트롤 생략 | `NaruRemoteAppModel.sendAccessoryKey` / `sendComposeQuickKey`; `RemoteInputDockView`는 탭 전에 marked commit을 넘김 | 커밋이 IME 후보를 원격에 흘릴 수 있음 — orca도 300 ms 조기 커밋을 DEL로 고친다. Naru는 marked를 커밋 경계에서만 보내므로 “커밋 후 방출”이 더 안전. 포커스 없는 스트립 탭이 IME를 깨면 T015와 충돌 — 그때는 방출을 미루거나 marked가 있을 때 스트립을 잠시 무시 (orca local-edit와 같은 클래스) |
| **P1** | Type 필드에 글자가 있을 때 스트립 Del/⌫는 **로컬 창 편집**(orca local-edit). 빈 필드일 때만 원격 delete | `sendAccessoryKey(.delete)` vs `liveDeleteBackward`; `AccessoryKey.delete` vs 독 ⌫ | 두 delete의 의미가 갈라짐(forward vs back). 라벨은 기존 `Del` / `Forward delete` (`AccessoryKey.swift:52`, `82`)를 유지 |

sticky armed/locked 자체는 orca에 없으므로 “orca처럼 없애기”는 권고하지 않는다. spec 011 US2가 의도적으로 넣은 층이다.

### 6.3 질문 3 — 라이브·한글

| 축 | orca | Naru | 차이 |
|----|------|------|------|
| 커밋 | 끝 한글 코드포인트 hold + 300 ms + DEL 보정 | UIKit marked → grapheme 창 | Naru가 iOS IME에 맞음. hold 타이머를 이식하지 말 것 |
| 미러 UX | 숨김 1×1 + 상태 한 줄 | 보이는 에디터 + `liveFieldText` | VNC 에코가 느려 보이는 미러가 맞음. 숨김 필드 이식 금지 |
| IME+액세서리 | 위 표 | 장벽 없음 | P0 (6.2) |
| dictation | live-insert vs buffered-append, 자동 Return 없음 | 시스템 IME가 에디터로 | 전용 마이크 버튼은 orca+데스크톱 STT. Naru에 데스크톱 STT  multipath가 없으면 버튼 발명 |

| 우선 | 권고 | 예상 편집 | 리스크 |
|------|------|-----------|--------|
| **P1** | 완성 transcript가 생기면 orca `routeDictationTranscript`와 같게: Type이면 insert(Return 없음), Compose면 초안 append(공백 하나) | 새 Core 순수 함수(파일 대응 `terminal-live-dictation-routing.ts`) + 독/모델. 호출은 시스템 dictation 커밋 훅이 있을 때만 | 훅이 없으면 라우터만 두고 연결은 후속. 원문을 로그/진단에 넣지 말 것 |
| — | 300 ms hangul hold / DEL 미러 | — | **하지 않음.** Naru는 marked 경계를 이미 갖고 있고, Unicode keysym은 음절 단위로 검증됨 (spec 011 live log). PTY echo 패치가 아님 |

`LiveTypeThroughMode`의 “Compose default” 주석은 문서 부채. 동작은 Type 승격이 맞다.

### 6.4 질문 4 — 키보드·레이아웃

| 축 | orca | Naru | 차이 |
|----|------|------|------|
| avoidance | 독 translate, PTY 크기 고정, 캐럿 기준 최소 lift | 뷰포트가 inset으로 줄고 로컬 줌 유지 | 도메인이 다름. PTY-fit lift를 VNC에 이식하지 말 것 |
| dismiss | 고정 해치 + pending-focus 취소 | interactive swipe, 해치 없음 | |
| keyboardType | 항상 `default` | 시스템 기본 | 이미 동일 의도 |
| wide | 700×600 마스터-디테일 | compact width cap + 전체 화면 hero | iPad는 우아한 스케일 (§VI) |
| 유휴 HUD | 없음(독 상시) | Type/Compose 알약 | spec 011. 유지 |

| 우선 | 권고 | 예상 편집 | 리스크 |
|------|------|-----------|--------|
| **P1** | 키보드가 떠 있을 때 **스크롤 밖 고정 Dismiss** (orca #5106). 기존 a11y 문장 재사용 가능: 코드에 `Dismiss keyboard` / `Hides the software keyboard…` (`[worktreeId].tsx:4683-4684`) — Naru에 동일 카피가 없으면 **새 카피 발명 금지**. 이미 있는 시스템 dismiss/포커스 상실 경로에 버튼을 붙이거나, 카피는 spec에 먼저 적을 것 | `RemoteInputDockView` compact 액세서리 행 선두 | 카피 계약. 해치가 좁은 primary 행을 더 줄임 |
| **P2** | dismiss 시 pending live-focus / expansion 타이머를 먼저 지운다 (`terminal-keyboard-dismiss.ts:11-13`) | `NaruRemoteAppShell` expansion + `schedule`된 focus | 작음. 이미 포커스 상실이 expansion을 접음 (`RemoteInputDockView.swift:891-898`) |

터미널 캐럿에 맞춘 부분 lift는 VNC 프레임버퍼에 대응 앵커가 없다. “키보드가 원격 해상도를 바꾸지 않는다”는 Naru가 이미 로컬 뷰포트로 지킨다.

### 6.5 질문 5 — 제스처

| 축 | orca | Naru | 차이 |
|----|------|------|------|
| 역할 | PTY 마우스/휠 바이트 검증 + WebView 스크롤백/선택 | RFB 포인터 + 로컬 핀치/팬 | |
| 즉시 탭 | WebView 탭이 롱프레스 slop에 안 먹히게 | failure requirement 제거 (011 US3) | **이미 이식됨** |
| 선택 vs 커서 | 선택 모드가 키보드를 내림; 마우스 트래킹일 때만 셀 클릭 | 탭=클릭, 핀치=줌, 두 손가락=휠 | VNC에 “선택 모드” PTY 개념 없음 |

추가 이식 없음. orca 스크롤백/xterm 마우스는 원격 앱이 터미널일 때 그 앱이 먹는다.

남는 잔여(spec 011 Residuals): 실기기에서 즉시 탭/더블클릭/우클릭 손맛. 코드 갭이 아니라 검증 갭.

### 6.6 우선순위 한 장 (구현 순서)

1. **P0** Type/Compose 공통: 액세서리 방출 앞 IME/pending flush (orca control-send-order).
2. **P0** 화살표·Del 홀드 리핏 (400/45, 파괴 키 제외).
3. **P0** 원탭 Ctrl+C (`ComposeQuickKey.controlC`를 스트립에). AI-CLI 인터럽트. Helper 불필요, key lane.
4. **P1** 필드가 있을 때 Del 로컬 편집; 떠 있는 키보드 Dismiss 해치(카피 계약 후); dictation 라우터 함수; 커스텀 키/레이아웃은 별 spec.
5. **P2** Enter/Space/S-Tab 원탭, dismiss 타이머 정리.

하지 말 것: 숨김 1×1 라이브 필드, 300 ms jamo hold, PTY 리사이즈 회피 lift, xterm 마우스 바이트 검증, Cmd 없는 단축키 빌더를 VNC에 그대로, Quick Commands 에이전트 런처(호스트가 orca 데스크톱이 아님).

---

## 인용 자가검증

본문에 쓴 orca 인용 중 5개를 `sed -n '<line>p'`로 다시 열었다. 첫 시도에서 `terminal-accessory-keys.ts:209`를 Space로 적었으나 209는 Backspace이고 Space는 208이다. 아래는 교정 후 재실행 출력이다.

```text
$ sed -n '208p' /Users/hckim/repo/orca/mobile/src/terminal/terminal-accessory-keys.ts
  { id: 'space', label: 'Space', bytes: ' ', accessibilityLabel: 'Space' },

$ sed -n '3p' /Users/hckim/repo/orca/mobile/src/terminal/terminal-live-hangul-mirror.ts
export const TERMINAL_LIVE_HELD_SYLLABLE_COMMIT_DELAY_MS = 300

$ sed -n '24p' /Users/hckim/repo/orca/mobile/src/terminal/terminal-keyboard-avoidance-lift.ts
  const anchorRow = Math.max(metrics.cursorY, metrics.contentBottomRow)

$ sed -n '28p' /Users/hckim/repo/orca/mobile/src/components/CustomKeyModal.tsx
// can read. Cmd is intentionally absent — macOS swallows it before keystrokes

$ sed -n '3371p' "/Users/hckim/repo/orca/mobile/app/h/[hostId]/session/[worktreeId].tsx"
  // Why: hold-to-repeat matches iOS cadence (400ms then 45ms); non-repeatable keys fire once (holding is destructive).
```

같은 세션에서 추가로 맞춘 것: `shiftTab` 주석은 `terminal-accessory-keys.ts:206`; hangul hold 이유 주석은 같은 파일 `:1-2`; dismiss 순서 주석은 `terminal-keyboard-dismiss.ts:11-12`.

---

## 이 보고서가 다루지 못한 것

1. **`[worktreeId].tsx` 비입력 경로 전수.** 파일/디프/브라우저/네이티브챗/워크트리 생성은 검색으로 위치만 봤다. 입력 독과 겹치는 리스는 `use-mobile-attachment-input-lease-gate` 등으로 추정되고, 바이트 단위로 안 읽었다.
2. **WebView JS 제스처 본체** (`terminal-webview-html.ts`, `terminal-webview-*-injected.ts`). 질문 5의 터치→시퀀스 변환은 테스트와 `terminal-gesture-input.ts`로만 재구성했다. 셀 클릭 vs 선택 vs 스크롤백의 픽셀 임계는 추정.
3. **Naru 실기기/시뮬레이터에서 독·키보드를 띄워 보지 않음.** 플로팅 vs compact 전환, interactive dismiss, 스트립이 키보드에 가리는지, 리핏이 없을 때의 손맛은 코드만.
4. **`KeystrokeEmitter` 와이어 봉투와 orca PTY 바이트의 바이트 단위 대조 없음.** sticky ⌃+c 와 orca `\x03`은 프로토콜이 다르다. “의미론적으로 인터럽트”만 같다.
5. **orca 데스크톱 STT / `use-mobile-dictation` 구현.** 라우팅 함수와 세션 연결만 읽었다. 호스트 전사 실패·권한 시트는 입력 UX 이식 범위 밖으로 남긴다.

---

## 읽지 않고 고의로 남겨 둔 것

- `orca/mobile/node_modules/**` — 과제 금지.
- orca/Naru 소스 수정, 스펙/NEXT_STEPS 편집 — 쓰기 화이트리스트 밖.
- `NaruRemote/App/Features/SessionViewer/SessionViewportView.swift` 전체(제스처 주석·fillsAvailableHeight만).
- `specs/011` 외 피처 스펙. 011 Status를 계약으로 사용.
- Quick Commands 데스크톱 공유 모듈 (`src/shared/terminal-quick-commands`) — 모바일 래퍼만.

DONE-ORCAREF
