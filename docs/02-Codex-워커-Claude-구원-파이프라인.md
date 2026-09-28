# Codex 워커 + Claude 관리자(Rescue) 계층형 파이프라인 조사

> 조사일: 2026-09-24 · 기존 문서 `Claude code 분업화 조사.md`의 후속편
> 목표: 복잡한 코딩은 가성비 좋은 **Codex(하위 워커)** 가 수행하고, 에러가 나거나 막힐 때만 **Claude(관리자)** 가 개입해 구원(Rescue)하는 구조가 지금 실제로 가능한지, 어떻게 만드는지 정리.

---

## 0. 먼저 — 기존 문서에서 바로잡을 점

기존 조사 문서는 "Claude Code에는 subagent·hooks·모델 지정 기능이 없다"고 적었지만, 2026년 9월 기준 사실과 다르다. 이 파이프라인 설계의 전제가 바뀌므로 먼저 정정한다.

| 기존 문서 주장 | 실제 (2026-09 기준) |
|---|---|
| Subagent 기능 없음 | **있음.** Agent 도구로 서브에이전트 생성, `.claude/agents/*.md`로 역할·모델·도구 권한 지정 가능 |
| 역할별 시스템 프롬프트 불가 | 서브에이전트 정의 파일이 곧 역할별 시스템 프롬프트 |
| Hooks/Commands 없음 | **있음.** `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `SessionStart` 등 이벤트에 스크립트 연결 가능 |
| 작업공간 분리 기능 없음 | 서브에이전트에 `isolation: worktree` 지정 시 git worktree 자동 분리 |
| 외부 모델 연동 불가 | 플러그인·MCP·Bash로 Codex CLI 등 외부 에이전트 호출 가능 (아래 참조) |

→ 결론: **"외부 오케스트레이터(LangChain 등)를 새로 짜야 한다"는 전제는 더 이상 필수가 아니다.** Claude Code 세션 자체가 관리자 겸 오케스트레이터가 될 수 있다.

---

## 1. 핵심 결론 (Executive Summary)

- **가능하다, 그리고 공식 도구가 이미 있다.** OpenAI가 Claude Code용 공식 플러그인 `openai/codex-plugin-cc`를 공개했다. Claude Code 안에서 `/codex:rescue`로 작업을 Codex에 넘기고, `/codex:review`로 Codex 리뷰를 받을 수 있다.
- **단, 방향 이름이 반대다.** 공식 플러그인의 "rescue"는 *Claude가 막혔을 때 Codex가 구원*하는 의미다. 사용자가 원하는 건 *Codex가 일하고 Claude가 구원*하는 것이므로, 플러그인의 **위임 기능**(`codex:codex-rescue` 서브에이전트, `--background`)을 "워커 호출기"로 쓰고, 실패 판정·에스컬레이션 규칙은 우리가 따로 얹어야 한다.
- **가장 중요한 설계 포인트는 "실패를 어떻게 믿을 만하게 감지하느냐"** 다. Codex의 "완료했습니다" 보고 하나만 믿으면 안 되고, 종료코드 + 이벤트 스트림 + 테스트 결과를 함께 봐야 한다. 그리고 Claude가 Codex 로그 전체를 읽으면 Claude 토큰이 새므로, **Codex가 짧은 구조화 리포트(JSON)만 남기게** 해야 가성비가 산다.

---

## 2. 사용할 수 있는 연결 방식 3가지

### 방식 A — 공식 플러그인 `codex-plugin-cc` (권장 출발점)

설치 (Claude Code 대화창에서):
```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```
필요 조건: ChatGPT 구독(Free 포함) 또는 OpenAI API 키, Node.js 18.18+, 로컬 Codex CLI(`npm install -g @openai/codex`). 플러그인은 별도 런타임이 아니라 **내 PC의 Codex CLI를 감싸는 것**이라 로그인·설정·체크아웃을 그대로 공유한다.

| 명령 | 역할 | 이 파이프라인에서의 쓰임 |
|---|---|---|
| `/codex:rescue <지시>` | Codex에 작업 위임 (`codex:codex-rescue` 서브에이전트) | **워커 호출** — 구현 작업 맡기기 |
| `--background` / `--wait` | 백그라운드 실행 / 완료 대기 | 긴 작업은 background로 돌리고 Claude는 다른 일 |
| `--resume` / `--fresh` | 직전 Codex 스레드 이어가기 / 새로 시작 | **1차 재시도**는 resume(에러 로그 첨부), 꼬였으면 fresh |
| `--model`, `--effort` | 모델·추론강도 지정 (예: `gpt-5.4-mini`, `low/medium/high`) | 난이도별 비용 조절 |
| `/codex:status`, `/codex:result`, `/codex:cancel` | 작업 상태/결과/취소 | 관리자가 진행 상황 점검 |
| `/codex:review`, `/codex:adversarial-review` | 읽기 전용 리뷰 | (선택) 교차 검증 |
| `/codex:setup --enable-review-gate` | Stop 훅에 Codex 리뷰 게이트 | ⚠️ README 스스로 "Claude/Codex 루프가 길어져 사용량을 빠르게 소진할 수 있다"고 경고 |

### 방식 B — Bash에서 `codex exec` 직접 호출 (세밀한 제어용)

플러그인이 감춰주는 부분을 직접 쥐고 싶을 때. 비대화형 모드 핵심 플래그:

| 플래그 | 의미 |
|---|---|
| `codex exec "<지시>"` | TUI 없이 한 번 실행하고 종료. 진행상황은 stderr, 최종 메시지는 stdout |
| `--json` | JSONL 이벤트 스트림 (`thread.started`, `item.completed`, `turn.completed` 등) |
| `-o, --output-last-message <파일>` | 최종 메시지를 파일로 저장 |
| `--output-schema <schema.json>` | **최종 응답을 JSON 스키마에 맞춰 강제** ← 구조화 리포트의 핵심 |
| `--sandbox workspace-write` | 작업 폴더 쓰기 허용, 네트워크 차단(기본) |
| `-a never` | 승인 프롬프트 없음 (헤드리스 필수 — 아래 함정 참고) |
| `codex exec resume --last` | 직전 세션 이어서 재시도 |
| `--ephemeral` | 세션 파일 저장 안 함 |

### 방식 C — MCP 서버로 연결

`tuannvm/codex-mcp-server`, `cexll/codex-mcp-server` 등 커뮤니티 MCP 래퍼가 여럿 있다. 다만 공식 플러그인이 나온 지금은 **A가 더 단순하고 유지보수도 OpenAI가 한다** → MCP는 Claude Desktop 등 다른 클라이언트에서도 쓸 때만 고려.

---

## 3. 제안 아키텍처: "Codex 우선, Claude 구원"

```
사용자 요청
   │
   ▼
[Claude 관리자]  ── 작업 분해 + "작업 봉투(Task Envelope)" 작성
   │               (목표 / 수정 허용 파일 / 완료 조건=통과해야 할 테스트 / 금지사항)
   ▼
[Codex 워커]  ── codex exec 또는 /codex:rescue --background
   │            결과: JSON 리포트 1개 (status, changed_files, tests, blockers)
   ▼
[자동 판정기]  ── 사람·모델 판단 없이 스크립트로
   │   ① exit code == 0
   │   ② JSONL에 turn.completed 존재
   │   ③ 리포트 파일이 실제로 생성됨
   │   ④ 테스트/빌드 명령을 "판정기가 직접" 다시 실행해 통과
   │   ⑤ git diff가 허용 파일 범위 안
   │
   ├─ 전부 통과 → 완료 (Claude는 리포트 요약만 읽음 = 토큰 최소)
   │
   └─ 실패
       ├─ 1회차: Codex에게 resume + 실패 로그 끝부분만 첨부해 재시도 (Claude 개입 없음)
       ├─ 2회차 실패: ★ Claude 구원 발동 ★
       │     Claude가 diff + 에러 요약 + 리포트를 읽고
       │       (a) 원인 진단 후 직접 수정  또는
       │       (b) 지시를 다시 써서 Codex fresh 스레드로 재위임
       └─ Claude도 2번 실패: 사람에게 보고 (중단, 상태 보존)
```

**왜 "2번"인가:** 사용자 CLAUDE.md의 "2번 실패하면 방법이 아니라 목적을 다시 본다" 규칙과 그대로 맞물린다. Codex 재시도 1회 → 그래도 안 되면 같은 방식으로 3번째 두드리지 말고 상위(Claude)로 올린다. 같은 규칙을 Claude 자신에게도 적용해 무한 루프를 막는다(서킷 브레이커).

### 3-1. 작업 봉투 예시 (Claude → Codex)

```
[목표] 로그인 화면에 "비밀번호 표시" 토글 추가
[수정 허용] lib/screens/login_screen.dart, test/login_screen_test.dart
[수정 금지] pubspec.yaml, lib/services/*
[완료 조건] `flutter test test/login_screen_test.dart` 통과
[막히면] 추측으로 계속 고치지 말고 status="blocked"와 이유를 리포트에 적고 종료
```

마지막 줄이 중요하다 — Codex가 스스로 "막혔다"고 일찍 손들게 해야 헛도는 비용이 줄고, Claude 구원 타이밍이 빨라진다.

### 3-2. 리포트 스키마 예시 (`--output-schema`)

```json
{
  "type": "object",
  "required": ["status", "changed_files", "tests_run", "summary"],
  "properties": {
    "status": { "enum": ["done", "failed", "blocked"] },
    "changed_files": { "type": "array", "items": { "type": "string" } },
    "tests_run": { "type": "string" },
    "summary": { "type": "string", "maxLength": 600 },
    "blocker": { "type": "string" }
  }
}
```

단, 리포트의 `status: "done"`은 **참고만** 한다. 성공 판정은 반드시 판정기가 테스트를 직접 다시 돌린 결과로 한다(가짜 완료 보고 방지).

### 3-3. Claude Code 쪽 구현 조각

| 조각 | 구현 위치 | 내용 |
|---|---|---|
| 워커 호출 스킬 | `.claude/skills/delegate-to-codex/SKILL.md` | 작업 봉투 작성 → `codex exec` 호출 → 판정기 실행 → 결과 분기 절차를 문서화 |
| 판정기 스크립트 | `scripts/verify_codex_run.ps1` (또는 .sh) | 위 ①~⑤ 체크, 결과를 `pass/fail + 사유 3줄`로만 출력 |
| 로그 요약 | 판정기 내부 | 실패 시 전체 로그 대신 에러 끝 40줄만 Claude에 전달 (토큰 절약) |
| 병렬 워커 | `git worktree` 워커별 1개 | 실무 권장 동시 3개 이하 (4개부터 Codex 사용량 한도와 충돌 보고 있음) |
| 이력 | `.codex-runs/<task-id>/` | 봉투·리포트·판정 결과를 파일로 남김 → 재시도·Claude 구원 시 문맥 전달용 "칠판" |

---

## 4. 알아둘 함정 (커뮤니티 실전 보고 기반)

1. **`--full-auto`는 완전 자동이 아니다.** 실제로는 "요청 시 승인 + workspace-write"라서, 헤드리스 실행 중 승인 대기로 멈춰버릴 수 있다 → `-a never`를 명시. (`--full-auto`는 이제 deprecated)
2. **샌드박스 네트워크 기본 차단.** `npm install`, `flutter pub get` 같은 의존성 설치는 실패한다 → 의존성은 판정기/관리자 쪽에서 미리 설치하거나, 필요할 때만 네트워크 허용 설정.
3. **완료 신호 하나만 믿지 말 것.** exit code 0인데 실제론 중단된 경우 등이 보고됨 → 3중 신호 + 테스트 재실행.
4. **장시간 작업은 쪼갤 것.** 한 번의 Codex 실행을 25~30분 이내 조각으로. 너무 길면 컨텍스트 압축 과정에서 세션이 죽는 사례 보고.
5. **자기 검증의 맹점.** 같은 모델이 쓴 코드를 같은 모델이 리뷰하면 놓치는 게 많다는 보고 → 여기서는 "Codex 작성, Claude 검토"가 자연스럽게 교차 검증이 된다(이 구조의 숨은 장점).
6. **Windows.** Codex CLI의 Windows 네이티브 샌드박스는 지원되지만 아직 "experimental" 표기. 현재 권장은 네이티브 우선, Linux 도구가 필요한 프로젝트면 WSL2.

---

## 5. 비용 관점 — 정말 가성비가 나오나?

- **Codex 쪽:** ChatGPT 구독 사용량 한도에서 차감(API 키면 종량제). 플러그인 README도 "Codex 사용량 한도에 포함된다"고 명시.
- **Claude 쪽 절약 포인트:** 이 구조에서 Claude는 (1) 작업 봉투 작성, (2) 짧은 리포트 읽기, (3) 실패 시 구원 — 세 순간에만 토큰을 쓴다. 절약 효과는 **Claude가 Codex의 원본 로그·diff 전체를 읽지 않는 것**에서 대부분 나온다. 로그를 통째로 읽으면 절약분이 거의 사라진다.
- **역효과 조건:** 작업이 너무 작으면(수정 몇 줄) 봉투 작성 + 판정 오버헤드가 더 크다 → Claude가 직접 하는 게 싸다. **"파일 3개 이상 or 테스트 작성 포함" 같은 위임 기준선**을 두는 것을 권장.
- **리뷰 게이트 주의:** 모든 Claude 응답마다 Codex 리뷰를 거는 `--enable-review-gate`는 양쪽 한도를 빠르게 소진할 수 있다 → 이 파이프라인에는 불필요.

---

## 6. 단계별 도입 로드맵

| 단계 | 할 일 | 확인할 것 |
|---|---|---|
| 1. 수동 체험 | 플러그인 설치 후 작은 작업 몇 개를 `/codex:rescue`로 직접 위임 | Codex 결과 품질, 소요 시간, 사용량 소모 체감 |
| 2. 판정기 | `verify_codex_run` 스크립트 작성, 수동 위임 결과에 돌려보기 | 가짜 완료를 실제로 걸러내는지 |
| 3. 스킬화 | "봉투 작성 → 위임 → 판정 → 1회 재시도 → Claude 구원" 절차를 스킬 하나로 | Claude가 구원 시 읽는 토큰량 |
| 4. 병렬화 | worktree 2~3개로 독립 작업 동시 위임 | 충돌 빈도, 사용량 한도 |
| 5. (선택) 밤모드 연동 | 밤모드 중 Codex에 구현을 맡기고 Claude는 판정·구원만 | 무인 실행 시 권한/샌드박스 안전성 |

---

## 7. 가능성 재평가 (기존 13장 표 갱신)

| 질문 | 기존 결론 | 갱신된 결론 |
|---|---|---|
| 최상급 모델이 하위 모델을 직접 관리할 수 있는가? | 불가능 | **가능** — Claude Code가 플러그인/Bash로 Codex 호출·상태조회·취소 |
| 서로 다른 모델(회사)을 역할별로 배치? | API 조합 시 가능 | **가능** — Claude(관리) + Codex(구현) 공식 플러그인 |
| 실패 자동 감지? | 부분 가능 | **가능 (판정 스크립트 필요)** — JSONL 이벤트 + exit code + 테스트 재실행 |
| 실패 시 상위 모델로 자동 Escalation? | 불가능 | **가능 (규칙은 직접 작성)** — 스킬/훅으로 "2회 실패 → Claude 구원" |
| 하위 모델 병렬 실행? | 불가능 | **가능** — `--background` + worktree, 실무 3개 이하 권장 |
| 작업 공간 분리? | 부분 가능 | **가능** — git worktree (Claude 서브에이전트는 자동 지원) |
| 사용자 승인 없는 완전 자동? | 부분 가능(위험) | 여전히 **부분 가능** — 샌드박스는 있으나 병합·배포는 사람 승인 유지 권장 |

**검증 수준 구분:** 위 내용은 공식 README·문서와 커뮤니티 보고를 읽어 정리한 것이며, 이 PC에서 직접 설치·실행해 확인한 것은 아니다. 특히 "동시 3개 권장", "30분 한계", "자기검증 맹점 수치" 등은 개별 블로그/저장소의 경험치라 환경에 따라 다를 수 있다.

---

## 출처
- [openai/codex-plugin-cc (공식 플러그인)](https://github.com/openai/codex-plugin-cc) · [README](https://github.com/openai/codex-plugin-cc/blob/main/README.md)
- [Codex 비대화형 모드 공식 문서](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Codex Windows 샌드박스 공식 문서](https://developers.openai.com/codex/windows)
- [p3nchan/cc-orchestrator — Claude Code 오케스트레이터 + Codex 워커 플레이북](https://github.com/p3nchan/cc-orchestrator)
- [Codex CLI Headless/Batch 모드 가이드](https://codex.danielvaughan.com/2026/04/18/codex-cli-headless-batch-mode-automation/)
- [Codex CLI Windows: 네이티브 샌드박스 vs WSL](https://codex.danielvaughan.com/2026/04/01/codex-cli-windows-native-sandbox-wsl/)
- [Orchestrating Claude Code and Codex Together (Nimbalyst)](https://nimbalyst.com/blog/orchestrating-claude-code-and-codex-together/)
- [tuannvm/codex-mcp-server](https://github.com/tuannvm/codex-mcp-server) · [cexll/codex-mcp-server](https://github.com/cexll/codex-mcp-server)
- [sendbird/cc-plugin-codex (반대 방향: Codex 안에서 Claude 호출)](https://github.com/sendbird/cc-plugin-codex)
