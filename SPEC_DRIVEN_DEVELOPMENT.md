# Naru Remote Spec-Driven Development Setup

작성일: 2026-04-29 KST

## 1. 결정

Naru Remote는 `GitHub Spec Kit`을 기본 골격으로 쓴다. 단, 기본 템플릿을 그대로 쓰지 않고 iOS/VNC/Tailscale/IME 제품에 맞춘 constitution, spec template, plan template, task template을 적용한다.

결론:

- 기본 도구: GitHub Spec Kit `v0.8.2`
- 에이전트 실행 환경: Codex + repository `AGENTS.md` + Spec Kit skills
- 대안 참조: Kiro의 requirements/design/tasks 흐름과 EARS식 acceptance criteria
- 보강 원칙: 모든 기능은 local composition, remote injection, security boundary, verification matrix를 먼저 정의한다.

이유:

- Spec Kit은 오픈소스이고 repo-native라서 특정 IDE에 묶이지 않는다.
- Codex integration과 skills mode를 공식 지원한다.
- Naru Remote는 모바일/프로토콜/권한/실기기 검증이 중요하므로, 문서가 repo 안에 남아야 한다.
- Kiro는 워크플로우가 좋지만 IDE 중심이다. 이 프로젝트는 Codex worktree, GitHub PR, Xcode, 실기기 검증까지 섞어야 하므로 repo-native가 더 맞다.

## 2. 리서치 요약

### GitHub Spec Kit

Spec Kit은 spec-driven development를 "specifications become executable"이라는 방향으로 정의한다. GitHub README는 공식 설치 패키지를 GitHub repo에서 직접 설치하라고 안내하고, existing project에는 `specify init . --integration ...` 형태로 초기화할 수 있다고 설명한다. 2026-04-28 기준 최신 릴리스는 `v0.8.2`다.

이 프로젝트에 적용한 명령:

```bash
uvx --from git+https://github.com/github/spec-kit.git@v0.8.2 specify init --here --integration codex --integration-options="--skills" --branch-numbering sequential --force
```

생성된 핵심 파일:

- `.specify/memory/constitution.md`
- `.specify/templates/spec-template.md`
- `.specify/templates/plan-template.md`
- `.specify/templates/tasks-template.md`
- `.agents/skills/speckit-*`
- `AGENTS.md`

### Kiro

Kiro의 requirements-first workflow는 `requirements.md` -> `design.md` -> `tasks.md` -> implementation 흐름을 제공한다. 공식 문서는 requirements phase에 user stories, acceptance criteria, EARS 형식의 system behavior, edge cases를 포함한다고 설명한다. design phase는 architecture, sequence diagrams, data models, interfaces, testing strategy를 생성하고, tasks phase는 discrete tasks와 dependencies를 만든다.

Naru Remote에 가져올 점:

- requirements를 EARS처럼 testable하게 쓰기
- design 전에 edge case와 success criteria를 닫기
- tasks를 실행 가능한 단위로 쪼개기
- bugfix/design-first 흐름은 나중에 brownfield가 생긴 뒤 도입

채택하지 않는 점:

- Kiro IDE 자체를 표준 도구로 고정하지 않는다.
- `.kiro/specs` 구조를 repo 표준으로 삼지 않는다.

### AGENTS.md / Codex

AGENTS.md는 agent용 README 역할을 하는 공개 포맷이다. 프로젝트 context, build/test commands, code style, security notes를 담기 좋다. Codex app의 worktree 기능은 독립 작업을 병렬로 처리하는 데 맞고, Spec Kit의 task 단위 작업과 잘 맞는다.

Naru Remote 적용:

- root `AGENTS.md`에 memory bridge, 제품 문서, Spec Kit workflow, build/test placeholder를 둔다.
- 실제 Xcode project가 생기면 build/test commands를 AGENTS.md에 추가한다.
- 병렬 에이전트 작업은 file ownership이 분리된 task에만 쓴다.

### Thoughtworks Radar 신호

Thoughtworks Technology Radar는 2026년 4월 GitHub Spec Kit을 `Assess`로 올렸다. 유용한 constitution은 project scope, domain context, technology versions, coding standards, repository structure를 담아야 한다고 보고했고, instruction bloat/context rot 위험 때문에 reusable guidance를 skills로 분리하는 접근을 언급했다.

Naru Remote 적용:

- Constitution은 짧고 강한 원칙만 둔다.
- 세부 반복 절차는 Spec Kit skills와 templates에 둔다.
- 기능별 세부 맥락은 `specs/*` 아래에 둔다.

## 3. 대안 평가

| 선택지 | 평가 | 장점 | 리스크 | 결정 |
| --- | --- | --- | --- | --- |
| GitHub Spec Kit | 1순위 | 오픈소스, repo-native, Codex skills 지원, constitution/plan/tasks 구조가 명확함 | 기본 템플릿은 generic하고 markdown이 과해질 수 있음 | 채택 |
| Kiro Specs | 좋은 참고 | requirements/design/tasks UX가 깔끔하고 EARS 흐름이 좋음 | IDE 종속, repo 밖 사용성이 약함 | 방법론만 차용 |
| 순수 AGENTS.md + 수동 docs | 단순 | 도구 의존성 낮음, 원하는 대로 설계 가능 | feature lifecycle, task traceability를 계속 수동 관리해야 함 | 보조로 사용 |
| Jira/Linear 중심 | 나중에 유용 | backlog, assignee, release tracking에 강함 | 제품/기술 스펙의 source of truth로는 약함 | spec 이후 연동 |
| BDD/Cucumber 중심 | 부분 적용 | acceptance criteria를 테스트화하기 좋음 | iOS/VNC/clipboard/manual-device 검증 전체를 커버하지 못함 | 특정 테스트에만 사용 |
| OpenAPI/contract-first only | 부분 적용 | helper/API contract에는 강함 | UI, VNC session, IME UX에는 좁음 | contracts/에서 사용 |

## 4. Naru Remote SDD 원칙

### 4.1 Feature는 네 가지 질문에 답해야 한다

1. 사용자는 어떤 원격 작업을 더 정확하게 하게 되는가?
2. 입력은 local device에서 어떻게 완성되는가?
3. 완성된 입력은 remote system에 어떤 경로로 들어가는가?
4. 실패, 권한, 보안, 로그, 검증은 어떻게 닫는가?

### 4.2 구현 전 산출물

모든 feature는 최소한 다음을 가진다.

- `spec.md`: 사용자 시나리오, functional requirements, security/privacy, acceptance matrix
- `plan.md`: architecture, adapter, data flow, verification matrix
- `research.md`: 불확실한 API/protocol/policy/library 결정
- `tasks.md`: user story별 작은 구현 task와 test evidence

### 4.3 Feature gate

계획 단계에서 아래가 하나라도 빠지면 구현하지 않는다.

- Local composition path
- Remote injection adapter
- Fallback behavior
- Clipboard impact
- Tailnet/private-network posture
- Data crossing and retention
- Verification matrix
- Manual-device residual risk

### 4.4 Verification matrix

Feature별로 필요한 최소 검증을 선택한다.

| Feature Type | Required Verification |
| --- | --- |
| Pure parsing/encoding/state | Unit tests |
| RFB/VNC behavior | Fake RFB server or fixture tests |
| iOS UI/input | XCTest plus XCUITest or screenshot/manual-device check |
| IME/dictation/hardware keyboard | Manual iPhone/iPad matrix until automation exists |
| Image paste/file staging | Fixture tests plus remote OS manual matrix |
| macOS helper | Unit/integration tests plus permission-state manual check |
| Agent bridge | Approval/interrupt/logging tests plus security review |

## 5. Repo Layout

Current planning files:

```text
AGENTS.md
BRANDING.md
PRODUCT_SPEC.md
PRODUCT_RESEARCH.md
AGENTIC_DEVELOPMENT_METHODOLOGY.md
SPEC_DRIVEN_DEVELOPMENT.md
.specify/
.agents/skills/
specs/
```

Target implementation layout after Xcode project creation:

```text
NaruRemote/
├── App/
├── Features/
│   ├── ConnectionHub/
│   ├── SessionViewer/
│   ├── InputBridge/
│   ├── VoiceCompose/
│   ├── ImagePaste/
│   ├── Diagnostics/
│   └── AgentHandoff/
├── VNC/
├── Tailnet/
└── Tests/

NaruHelper/
├── Sources/
└── Tests/

TestFixtures/
└── FakeRFBServer/
```

## 6. First Feature Sequence

### 001 Naru Remote MVP

Scope:

- Saved private VNC profile
- Manual host/MagicDNS host entry
- Basic connection diagnostics
- RFB handshake and view-only session
- Compose & Send through VNC clipboard paste
- Clear failure states

Why first:

- It proves the product thesis without needing host helper or agent bridge.
- It creates test harnesses for connection, RFB, clipboard, and iOS UI.
- It avoids overinvesting in image/voice/agent before the core input bridge works.

### 002 Voice Compose

Scope:

- Dictation result lands in local compose surface
- User reviews before send
- Confidence/failure states
- No automatic execution by default

### 003 Image Paste Bridge

Scope:

- Pick image from Photos/Files
- Preferred route: helper when available, VNC clipboard/file fallback otherwise
- Remote OS compatibility matrix

### 004 Naru Helper

Scope:

- Optional macOS helper
- Native text insert
- Clipboard restore
- Image/file staging
- Permission UI and revocation

### 005 Agent Handoff

Scope:

- Observe, request control, approval, interrupt, action timeline
- No autonomous destructive actions without approval

## 7. Operating Commands

Create or refine a feature:

```text
$speckit-specify [feature description]
$speckit-clarify
$speckit-plan [technical constraints and stack decisions]
$speckit-tasks
$speckit-implement
```

Manual current-feature selection without changing git branch:

```json
{
  "feature_directory": "specs/001-naru-remote-mvp"
}
```

This is stored in `.specify/feature.json` so Spec Kit can find the active feature
even while the repository is still on `main`.

## 8. Sources

- GitHub Spec Kit README: https://github.com/github/spec-kit
- GitHub Spec Kit `v0.8.2` release: https://github.com/github/spec-kit/releases/tag/v0.8.2
- Kiro requirements-first workflow: https://kiro.dev/docs/specs/feature-specs/requirements-first/
- Kiro design-first and bugfix specs: https://kiro.dev/blog/specs-bugfix-and-design-first/
- AGENTS.md format: https://agents.md/
- Codex worktrees: https://developers.openai.com/codex/app/worktrees
- Thoughtworks Radar on GitHub Spec Kit: https://www.thoughtworks.com/en-us/radar/languages-and-frameworks/github-spec-kit
