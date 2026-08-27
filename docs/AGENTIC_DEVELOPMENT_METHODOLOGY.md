# 에이전트 기반 개발 방법론

작성일: 2026-04-29 KST

대상 제품: Tailnet-native IME-first VNC Viewer

## 1. 결론

이 제품은 에이전트로 개발하기 좋은 부분과 나쁜 부분이 뚜렷하다.

좋은 부분:

- VNC/RFB 프로토콜 조사와 compatibility matrix 작성
- iOS UI prototype 반복
- XCTest/XCUITest test scaffold 작성
- 문서화, 리서치, 경쟁 제품 분석
- snippet/shortcut/diagnostics 같은 독립 기능 구현
- macOS helper prototype
- 실패 케이스 수집과 재현 테스트 작성

나쁜 부분:

- 전체 아키텍처를 한 번에 맡기는 일
- 보안/권한/네트워크 경계 결정
- App Store 심사 리스크 판단
- Tailscale/NetworkExtension 관련 정책 판단
- VNC clipboard/image paste 호환성을 검증 없이 가정하는 구현
- iOS 입력/IME/음성 UX를 실제 기기 테스트 없이 "코드상 맞다"고 끝내는 일

따라서 방법론은 다음 한 문장으로 정리한다.

> 사람은 제품 의도, 아키텍처 경계, 검증 기준을 설계하고, 에이전트는 작고 검증 가능한 task를 병렬로 구현하며, 모든 결과는 테스트/시뮬레이터/실기기/리뷰로 닫는다.

## 2. 리서치에서 얻은 원칙

## 2.1 에이전트는 검증 수단이 있을 때 강하다

Anthropic Claude Code best practices는 "테스트, 스크린샷, 기대 출력처럼 agent가 자기 작업을 검증할 방법을 주는 것"을 가장 높은 레버리지로 설명한다. OpenAI Codex 소개도 에이전트가 test harness, linter, type checker를 실행하고 terminal log와 test output으로 작업을 검증할 수 있게 설계했다고 설명한다.

제품 적용:

- 모든 coding task는 "어떤 명령으로 성공을 검증할지"를 포함해야 한다.
- UI 작업은 screenshot 비교 또는 XCUITest가 있어야 한다.
- VNC/clipboard/IME 작업은 fake server, integration server, 실기기 matrix 중 최소 하나로 닫아야 한다.

참고:

- https://code.claude.com/docs/en/best-practices
- https://openai.com/index/introducing-codex/

## 2.2 Explore -> Plan -> Implement -> Verify가 기본이다

Claude Code 문서는 복잡한 변경에서 먼저 read-only 탐색을 하고, 계획을 만든 뒤 구현하라고 권장한다. GitHub Copilot cloud agent도 repository research, implementation plan, branch change, PR review 흐름을 기본 모델로 둔다.

제품 적용:

- protocol, renderer, input bridge, helper, security는 곧바로 구현하지 않는다.
- 먼저 spike 문서와 compatibility table을 만들고, 그 다음 vertical slice를 구현한다.

참고:

- https://code.claude.com/docs/en/tutorials
- https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent

## 2.3 병렬 에이전트는 worktree/branch 격리가 필요하다

Codex app은 multi-agent workflow에서 worktree와 isolated copy를 강조한다. Copilot cloud agent도 독립 branch에서 작업하고 PR 중심으로 리뷰하는 구조다.

제품 적용:

- agent 하나는 branch 하나, worktree 하나, 소유 파일 영역 하나를 가진다.
- 같은 파일을 여러 agent가 동시에 수정하지 않는다.
- 병렬화는 research, tests, docs, 독립 module에만 건다.

참고:

- https://openai.com/index/introducing-the-codex-app/
- https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent

## 2.4 iOS/모바일 agent 성공률은 아직 낮다

SWE-Bench Mobile은 production iOS codebase 기반 task에서 여러 상용/오픈소스 agent를 평가했고, best configuration도 12% task success rate라고 보고했다. 또한 agent design이 model capability만큼 중요하고, defensive programming prompt가 복잡한 prompt보다 나았다고 보고했다.

제품 적용:

- iOS app core는 agent 산출물을 그대로 믿지 않는다.
- 에이전트에게는 defensive code, explicit error handling, small interface, tests를 요구한다.
- 실제 iPad/iPhone verification 없이 UX 기능을 완료로 보지 않는다.

참고:

- https://arxiv.org/abs/2602.09540

## 2.5 AI 생산성은 task selection에 크게 의존한다

METR의 2025 연구는 숙련된 오픈소스 개발자가 익숙한 mature codebase에서 AI 도구를 쓰면 오히려 19% 느려졌다고 보고했다. 다만 2026 업데이트에서는 최신 agent 도입과 task selection 변화 때문에 측정 자체가 어려워졌고, AI가 잘하는 task를 개발자가 선별하는 현상이 강해졌다고 설명한다.

제품 적용:

- 모든 일을 agent에게 주지 않는다.
- "agent가 잘하는 형태로 task를 재구성하는 일"을 개발 프로세스의 일부로 둔다.
- productivity 지표는 느낌이 아니라 PR lead time, test pass, review churn, reopened bug로 본다.

참고:

- https://arxiv.org/abs/2507.09089
- https://metr.org/blog/2026-02-24-uplift-update/

## 2.6 AGENTS.md와 skills는 필수 인프라다

AGENTS.md는 AI coding agent용 README 역할을 하는 공개 포맷이다. Codex, Copilot, Claude 계열 모두 repository instruction, skills, hooks, MCP 같은 구성 방식을 지원한다.

제품 적용:

- repo root에 짧고 구체적인 AGENTS.md를 둔다.
- module별로 필요한 경우 하위 AGENTS.md를 둔다.
- 반복 task는 skill 또는 script로 만든다.
- "테스트 명령", "빌드 명령", "시뮬레이터 명령", "금지된 가정"을 명시한다.

참고:

- https://github.com/agentsmd/agents.md
- https://openai.com/index/introducing-the-codex-app/
- https://code.claude.com/docs/en/best-practices

## 3. 개발 운영 모델

## 3.1 역할 분리

### Human Product Lead

책임:

- 제품 방향
- target user
- MVP 범위
- 보안/프라이버시 기준
- App Store 리스크 판단
- 최종 UX 승인

agent에게 맡기지 않는 결정:

- Tailscale을 앱 내부에 넣을지 여부
- helper 권한 모델
- agent bridge public exposure 여부
- telemetry 수집 범위
- 가격/패키징

### Human Tech Lead

책임:

- 아키텍처 경계
- module ownership
- protocol/library 선택
- CI/test strategy
- merge 승인

### Research Agents

책임:

- 경쟁 제품 조사
- VNC/RFB extension 조사
- iOS API/정책 조사
- Tailscale integration 조사
- App Store guideline 조사

산출물:

- 짧은 research memo
- source links
- risk list
- recommendation

### Implementation Agents

책임:

- 작은 vertical slice 구현
- test 작성
- docs 업데이트
- failure log 추가

제약:

- 하나의 task는 명확한 file ownership을 가진다.
- shared architecture 변경은 사전 승인 후 진행한다.
- test 없이 core logic PR을 만들지 않는다.

### Verification Agents

책임:

- PR review
- edge case 탐색
- security review
- UI screenshot 비교
- compatibility matrix 업데이트

원칙:

- 구현 agent와 verification agent는 분리한다.
- verification agent는 코드를 수정하기보다 finding과 reproduction을 우선 낸다.

## 3.2 기본 루프

모든 feature는 다음 흐름을 따른다.

1. Spec
   - 사용자 시나리오, acceptance criteria, non-goals, privacy/security notes를 쓴다.

2. Spike
   - 불확실한 API/protocol/server behavior를 작은 실험으로 확인한다.

3. Task Decomposition
   - agent가 처리할 수 있는 0.5-1일 단위 task로 쪼갠다.

4. Agent Implementation
   - isolated branch/worktree에서 구현한다.

5. Agent Verification
   - unit/integration/UI/performance/security check를 실행한다.

6. Human Review
   - architecture, UX, privacy, maintainability를 본다.

7. Merge
   - CI green, review addressed, docs updated 상태에서만 병합한다.

8. Memory Update
   - 배운 호환성 이슈, 실패 케이스, 명령어를 docs/AGENTS.md/test matrix에 반영한다.

## 4. Repository 구조 제안

초기 repo는 다음처럼 agent-friendly하게 만든다.

```text
/
  AGENTS.md
  PRODUCT_SPEC.md
  PRODUCT_RESEARCH.md
  AGENTIC_DEVELOPMENT_METHODOLOGY.md
  docs/
    architecture/
    decisions/
    research/
    compatibility/
    test-plans/
  ios/
    VNCViewer.xcodeproj
    App/
    RFB/
    InputBridge/
    Diagnostics/
    Tests/
    UITests/
  helper/
    macos/
    windows/
    linux/
  tools/
    vnc-test-server/
    text-injection-harness/
    image-paste-harness/
    scripts/
```

## 5. AGENTS.md 설계

root AGENTS.md에는 다음만 둔다.

- 제품 한 줄 설명
- architecture overview
- build/test 명령
- verification matrix 위치
- coding style
- security constraints
- "실제 검증 없이 성공이라고 말하지 말 것"
- module ownership 규칙
- PR/commit 규칙

나쁜 AGENTS.md:

- 긴 철학 문서
- 당연한 말
- 서로 충돌하는 규칙
- 테스트 명령 없는 "테스트 잘 해라"

좋은 AGENTS.md:

- `xcodebuild test -scheme VNCViewer -destination 'platform=iOS Simulator,name=iPad Pro ...'`
- `tools/vnc-test-server/run.sh --clipboard=utf8`
- 서버별 클립보드 지원 표 업데이트 (문서 미작성 — 현재 근거는 `TestFixtures/FakeRFBServer/Fixtures/`의 트랜스크립트)
- `InputBridge` 변경 시 `TextInjectionAdapterTests` 필수

## 6. Task 설계 규칙

## 6.1 Definition of Ready

agent에게 넘기기 전 task는 다음을 만족해야 한다.

- 목표가 한 문장으로 설명된다.
- 수정 가능한 파일/모듈 범위가 정해져 있다.
- acceptance criteria가 있다.
- 검증 명령 또는 수동 검증 절차가 있다.
- 관련 문서/스펙 링크가 있다.
- 하지 말아야 할 일이 명시돼 있다.

## 6.2 Definition of Done

agent task 완료 기준:

- 구현 완료
- 관련 테스트 추가/수정
- 지정된 검증 통과
- 실패하거나 못 한 검증 명시
- docs/compatibility matrix 업데이트
- diff가 task 범위를 벗어나지 않음
- 리뷰어가 재현 가능한 설명을 받음

## 6.3 좋은 task 예시

```markdown
Title: Implement TextInjectionRequest model and adapter protocol

Context:
- See PRODUCT_SPEC.md section 9.3.
- This is interface-only. Do not implement VNC clipboard transport yet.

Ownership:
- ios/InputBridge/TextInjectionRequest.swift
- ios/InputBridge/TextInjectionAdapter.swift
- ios/Tests/InputBridgeTests/

Acceptance criteria:
- Supports source, behavior, targetOS, sensitive, preserveClipboard.
- Unit tests cover Codable roundtrip and behavior enum.
- No UI changes.

Verify:
- xcodebuild test -scheme VNCViewer -only-testing:InputBridgeTests
```

## 6.4 나쁜 task 예시

```markdown
Make text input work like Chrome Remote Desktop.
```

문제가 있다.

- protocol path가 불명확하다.
- target OS가 없다.
- 테스트가 없다.
- helper 사용 여부가 없다.
- 클립보드 보존 기준이 없다.

## 7. 병렬화 전략

## 7.1 병렬화해도 되는 일

- 경쟁 제품별 리서치
- VNC server별 compatibility 조사
- 독립 UI prototype
- unit test generation
- docs cleanup
- sample VNC server harness
- macOS helper spike와 iOS UI spike

## 7.2 직렬화해야 하는 일

- RFB client abstraction
- TextInjectionAdapter interface
- Credential storage
- Security model
- Agent bridge permission model
- app navigation architecture

## 7.3 worktree 규칙

- branch 이름: `agent/<area>/<short-task>`
- worktree 이름: `../worktrees/<branch-name>`
- agent 하나당 branch 하나
- 하루 이상 묵은 agent branch는 재검토
- merge 전 main rebase와 full CI
- 같은 파일 소유권 충돌 시 새 agent를 만들지 않고 lead가 통합

## 8. 권장 agent 팀 구성

## 8.1 Phase 0/1

### Lead Agent

역할:

- task decomposition
- interface consistency
- merge review
- docs update

### Protocol Research Agent

역할:

- RFB 3.8, VeNCrypt, Extended Clipboard, encoding 조사
- VNC server matrix 작성

### iOS Prototype Agent

역할:

- SwiftUI shell
- session screen
- compose bar prototype
- Voice Compose prototype

### Test Harness Agent

역할:

- fake RFB server
- clipboard simulation
- text/image injection test fixtures

### QA/Compatibility Agent

역할:

- macOS Screen Sharing, TigerVNC, RealVNC, TightVNC, UltraVNC, x11vnc, wayvnc matrix
- 실기기 테스트 script 작성

## 8.2 MVP 이후

### Helper Agent

- macOS helper
- Windows helper
- Linux helper

### Security Agent

- Keychain
- LocalAuthentication
- session token
- helper pairing
- agent bridge permission

### Release Agent

- TestFlight checklist
- changelog
- App Store privacy nutrition label draft
- crash/telemetry review

## 9. 검증 전략

## 9.1 테스트 피라미드

### Unit

- RFB message parser
- TextInjectionRequest
- keyboard shortcut mapping
- OS paste behavior
- image normalization
- diagnostics classification

### Integration

- fake VNC server
- clipboard UTF-8 roundtrip
- paste shortcut dispatch
- reconnect behavior
- helper pairing mock

### UI

- compose bar states
- voice compose flow
- attachment picker flow
- connection doctor
- error surfaces

### Device

- iPad Pro + Magic Keyboard
- iPhone compact layout
- external display
- Tailscale VPN on/off
- Korean/Japanese/Chinese IME
- dictation

### Compatibility Lab

- macOS Screen Sharing
- RealVNC
- TigerVNC
- TightVNC
- UltraVNC
- x11vnc
- wayvnc

## 9.2 CI

Apple 공식 문서는 Xcode Cloud가 Git 기반 CI/CD, simulator testing, TestFlight delivery를 통합한다고 설명한다. 초기에는 GitHub Actions와 local Xcode를 써도 되지만, TestFlight 단계에서는 Xcode Cloud를 검토한다.

필수 gate:

- build
- unit tests
- UI smoke tests
- SwiftLint/format
- static checks
- secret scan
- docs link check

참고:

- https://developer.apple.com/documentation/Xcode/About-Continuous-Integration-and-Delivery-with-Xcode-Cloud
- https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html

## 10. 에이전트용 산출물

프로젝트에 다음 문서를 유지한다.

```text
docs/architecture/overview.md
docs/architecture/input-bridge.md
docs/architecture/rfb-client.md
docs/architecture/helper.md
docs/compatibility/vnc-server-matrix.md
docs/compatibility/text-input-matrix.md
docs/compatibility/image-paste-matrix.md
docs/test-plans/mvp-test-plan.md
docs/test-plans/device-test-plan.md
docs/decisions/ADR-0001-rfb-client-choice.md
docs/decisions/ADR-0002-text-injection-strategy.md
docs/decisions/ADR-0003-helper-security-model.md
```

이 문서들은 agent context의 source of truth다. 구현 중 알게 된 사실은 반드시 여기에 돌아와야 한다.

## 11. MCP와 외부 도구 연결

MCP는 agent가 외부 도구와 데이터를 쓰게 하는 표준 경로지만, 보안 표면도 넓힌다. MCP tools는 모델이 자동으로 발견하고 호출할 수 있으므로 민감 작업에는 사용자 확인, 최소 권한, audit log가 필요하다.

프로젝트 적용:

- read-only docs/search MCP는 적극 활용
- Jira/GitHub/Linear MCP는 task 생성/조회 위주
- Apple account, signing, App Store Connect, cloud credentials는 agent 직접 접근 금지
- production telemetry, crash logs는 redacted export만 제공
- helper pairing secret, VNC password, Tailscale token은 agent context에 넣지 않음

참고:

- https://modelcontextprotocol.io/docs/concepts/tools
- https://docs.github.com/en/copilot/concepts/coding-agent/mcp-and-coding-agent
- https://docs.github.com/en/copilot/responsible-use/copilot-cloud-agent

## 12. 보안 운영

GitHub Copilot cloud agent 책임 문서는 agent를 replacement가 아니라 tool로 쓰고, 생성 코드에는 테스트, IP scan, security scan, review가 필요하다고 설명한다. 또한 branch 제한, secret 제한, audit trail 같은 제어를 둔다.

우리 프로젝트 규칙:

- agent는 main에 직접 push하지 않는다.
- agent는 signing credential에 접근하지 않는다.
- agent-authored PR은 사람 리뷰 필수.
- 네트워크/권한/App Store 관련 코드는 security checklist 필수.
- helper/agent bridge 변경은 threat model 업데이트 없이 merge하지 않는다.
- 코드에 secret이 들어간 경우 해당 branch는 폐기하고 secret rotate를 검토한다.

참고:

- https://docs.github.com/en/copilot/responsible-use/copilot-cloud-agent

## 13. 측정 지표

agent 도입 효과는 다음으로 측정한다.

### Throughput

- created PR count
- merged PR count
- median PR lead time
- issue to first patch time

### Quality

- CI pass rate on first PR
- review comments per PR
- reopened bugs
- post-merge regression count
- test coverage delta

### Agent Efficiency

- accepted agent PR ratio
- human rework time
- failed agent task ratio
- tasks abandoned after agent attempt

### Product-Specific

- text injection compatibility cases completed
- image paste compatibility cases completed
- device matrix pass count
- VNC server matrix coverage

## 14. 단계별 실행 계획

## Phase A. Agent-Ready Repo Setup

목표:

- agent가 안전하게 일할 수 있는 뼈대 만들기

작업:

- root AGENTS.md 작성
- docs 구조 생성
- ADR template 생성
- task template 생성
- GitHub issue template 생성
- CI skeleton
- Swift project scaffold

완료 기준:

- 새 agent가 AGENTS.md만 보고 build/test/doc 위치를 이해한다.

## Phase B. Research Swarm

목표:

- 기술 불확실성 제거

병렬 research:

- RFB client/library 후보
- VNC server clipboard matrix
- iOS text input and dictation APIs
- image clipboard/file paste options
- Tailscale API/Shortcuts/Services
- App Store remote desktop/helper 정책

완료 기준:

- 각 research memo에 recommendation, risks, next spike가 있다.

## Phase C. Spike Factory

목표:

- 가정이 아니라 작동 증거 확보

spike:

- fake VNC server
- iOS RFB connection
- UTF-8 clipboard paste
- Korean/Japanese/Chinese Compose & Send
- Voice Compose
- image normalization and paste attempt
- Tailscale MagicDNS connection

완료 기준:

- compatibility matrix가 실제 테스트 결과로 채워진다.

## Phase D. MVP Vertical Slices

목표:

- 사용자 가치가 닫힌 slice 구현

slice:

1. Connect to MagicDNS VNC host
2. View and interact with remote screen
3. Compose Korean/English text and send
4. Dictate, edit, and send
5. Diagnose connection/input failure
6. Save profile securely

완료 기준:

- TestFlight dogfood 가능.

## Phase E. Beta Hardening

목표:

- 실제 사용자가 매일 쓸 수준으로 안정화

작업:

- crash/performance telemetry
- compatibility doctor 개선
- image paste lab
- desk mode
- WOL/reconnect
- TestFlight feedback triage automation

## Phase F. Helper/Agent Platform

목표:

- Pro 기능과 장기 차별화

작업:

- macOS helper
- reliable native text insert
- reliable image paste/drop
- clipboard restore
- `/session/text`
- `/session/image`
- action timeline
- approval overlay

## 15. Prompt/Task 템플릿

## 15.1 Research Agent Prompt

```markdown
You are researching one bounded question for the Tailnet-native IME-first VNC Viewer.

Question:
<question>

Output:
- Short answer
- Evidence with source links
- Risks
- Recommendation
- Follow-up spike

Constraints:
- Use primary/official sources where possible.
- Do not propose implementation without identifying verification.
- Keep output under 2 pages.
```

## 15.2 Implementation Agent Prompt

```markdown
Implement this task in an isolated branch/worktree.

Spec:
<link>

Ownership:
<files/modules>

Acceptance criteria:
<bullets>

Do not:
<bullets>

Verify:
<commands/manual checks>

Final response:
- changed files
- tests run
- risks/limitations
- anything not completed
```

## 15.3 Verification Agent Prompt

```markdown
Review this branch for correctness, regressions, and missing tests.

Focus:
<area>

Check:
- spec conformance
- edge cases
- security/privacy implications
- test quality
- compatibility matrix updates

Output findings first with file/line references.
Do not rewrite the implementation unless asked.
```

## 16. 이 제품에서 특히 주의할 에이전트 실패 패턴

### 16.1 "VNC supports clipboard"를 과신

대응:

- 서버별 matrix 없이는 완료 처리하지 않는다.
- text, image, file을 분리해서 검증한다.

### 16.2 iOS simulator에서만 검증

대응:

- dictation, IME, Magic Keyboard, external display, Tailscale VPN은 실기기 test gate를 둔다.

### 16.3 helper 권한을 느슨하게 설계

대응:

- helper는 MVP 필수가 아니다.
- threat model과 pairing model을 먼저 쓴다.

### 16.4 agent가 테스트를 과도하게 mock

대응:

- protocol parser는 fixture 기반 테스트.
- integration은 fake server를 사용.
- mock-only success를 금지한다.

### 16.5 긴 세션에서 맥락 오염

대응:

- task별 새 세션.
- research와 implementation 분리.
- 실패한 접근을 두 번 넘기면 새 prompt와 새 세션.

## 17. 즉시 할 일

1. root AGENTS.md 작성
2. docs 디렉터리와 ADR/task template 생성
3. RFB client 후보 research task 3개로 분리
4. fake VNC server/test harness 설계
5. iOS Swift project scaffold 결정
6. MVP verification matrix 작성
7. 첫 10개 agent-ready issue 작성

## 18. 첫 10개 agent-ready issue 후보

1. Research: RFB client/library candidates for iOS
2. Research: VNC clipboard and Extended Clipboard compatibility
3. Research: iOS dictation/TextField/UITextInput constraints
4. Research: Tailscale MagicDNS/API/Shortcuts integration
5. Scaffold: SwiftUI app shell and session placeholder
6. Scaffold: TextInjectionRequest and adapter protocols
7. Scaffold: fake VNC server test harness
8. Prototype: Compose bar UI states
9. Prototype: Voice Compose flow
10. Prototype: image picker and normalization pipeline

## 19. 참고 링크

- OpenAI Codex overview: https://openai.com/codex/
- Introducing Codex: https://openai.com/index/introducing-codex/
- Codex app and multi-agent workflows: https://openai.com/index/introducing-the-codex-app/
- How OpenAI uses Codex: https://openai.com/business/guides-and-resources/how-openai-uses-codex/
- Unrolling the Codex agent loop: https://openai.com/index/unrolling-the-codex-agent-loop/
- Claude Code best practices: https://code.claude.com/docs/en/best-practices
- Claude Code common workflows: https://code.claude.com/docs/en/tutorials
- GitHub Copilot cloud agent: https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent
- GitHub responsible use for Copilot cloud agent: https://docs.github.com/en/copilot/responsible-use/copilot-cloud-agent
- AGENTS.md standard: https://github.com/agentsmd/agents.md
- SWE-agent: https://github.com/SWE-agent/SWE-agent
- SWE-Bench Verified: https://openai.com/index/introducing-swe-bench-verified/
- SWE-Bench Mobile: https://arxiv.org/abs/2602.09540
- METR productivity study: https://arxiv.org/abs/2507.09089
- METR 2026 productivity update: https://metr.org/blog/2026-02-24-uplift-update/
- Xcode Cloud: https://developer.apple.com/documentation/Xcode/About-Continuous-Integration-and-Delivery-with-Xcode-Cloud
- Xcode UI Testing: https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html
- MCP tools: https://modelcontextprotocol.io/docs/concepts/tools
