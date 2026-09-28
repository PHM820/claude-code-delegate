# Codex 작업자 전환 설계 (보류 — Codex 구독 시 적용)

> 작성: 2026-09-25 · 상태: **설계만**. 설치된 `/delegate`(v0.7), `/delegate-all`(v0.5)은 구독 전까지 변경하지 않는다.
> 바탕: 02 문서(Codex 연동 조사), 03 문서(Claude 단독 구조), 04 보고서(실측)

---

## 1. 목표와 확정 사항

| 역할 | 담당 | 비고 |
|---|---|---|
| 관리자 | Opus 5.5 (메인 세션) | 지금과 동일. 승인 전 모델 선택기에서 Opus로 |
| 마일스톤 리드 (하위 관리자) | Opus 5.5 (서브에이전트) | 지금과 동일. 대형 모드일 때만 |
| **작업자** | **Codex** (등급별 모델) | Claude Sonnet/Haiku 서브에이전트를 대체 |
| 구원 | Opus 5.5 | Codex가 사다리 끝까지 실패하면 다른 회사 모델이 해결 |

**얻는 것**
1. 작업자 비용이 ChatGPT 구독 한도로 이동 → Claude 한도는 관리·판정·구원에만 쓴다.
2. 서로 다른 회사 모델끼리 검토 → 같은 계열끼리 볼 때보다 맹점이 덜 겹친다.

**그대로인 것**: 계획·승인 게이트·판정(관리자가 테스트 직접 실행)·예산 규칙·세션 경계·종료/중단·밤모드 규칙.
관리자 대화가 무거워지는 문제(실측 호출당 약 35만 토큰)는 Claude 쪽에 그대로 남으므로 **새 세션 규칙은 계속 필수**.

---

## 2. 모드 선택 — `클로드만` / `혼합`

### 2-1. 두 모드의 역할 배치

| 역할 | 클로드만 (`claude`) | 혼합 (`mixed`) |
|---|---|---|
| 관리자 | Opus 5.5 | Opus 5.5 |
| 마일스톤 리드 (대형일 때만) | Opus 5.5 | Opus 5.5 |
| 조사 (읽기 전용: 구조 파악, 검색) | Haiku 4.5 | Codex 가벼움 ※ |
| 일반 구현·테스트 작성 | Sonnet 5 | Codex 일반 |
| 어려운 구현 | Opus 5.5 작업자 | Codex 어려움 |
| 재시도 (사다리 1·2단계) | 같은 작업자 → 상위 Claude 모델 | Codex 이어서 → 추론 강도↑ → 상위 Codex 모델 |
| 구원 (사다리 3단계) | Opus 5.5 | Opus 5.5 (다른 회사 모델이 구원 → 교차 검증) |
| 판정 | 관리자가 테스트 직접 실행 | 동일 + Codex 세 신호 확인(5장) |
| Claude 한도 사용처 | 전부 | 관리·판정·구원만 |

※ 조사를 Haiku로 둘지 Codex로 둘지는 구독 시 결정: Codex로 하면 Claude 한도를 더 아끼고, Haiku로 하면 Codex 한도를 구현에 몰아줄 수 있다.

### 2-2. 어디서 고르나

| 시점 | 방법 |
|---|---|
| 전역 기본값 | `~/.claude/skills/delegate/engine.json`의 `default_mode` |
| `/delegate` 한 번 | 계획에 `모드: 혼합 / 클로드만` 줄 표시 → 승인 때 "클로드만으로" 등으로 변경. 또는 시작할 때 `/delegate --claude <작업>`, `/delegate --mixed <작업>` |
| `/delegate-all` 프로젝트 | 기획 승인 때 고름 → `state.json`의 `mode`에 저장 |
| `/delegate-all` 도중 | 마일스톤 승인 게이트마다 바꿀 수 있음 (진행 중인 마일스톤 안에서는 안 바꿈 — 섞이면 판정·예산 기록이 꼬임) |

```json
// ~/.claude/skills/delegate/engine.json
{
  "default_mode": "mixed",          // "claude" | "mixed"
  "codex_ready": true,              // false면 혼합 모드 선택 불가
  "mixed_research_worker": "codex", // "codex" | "haiku" (2-1 ※)
  "tiers": { ... 3장 표 ... }
}
```

### 2-3. 안전장치
- `codex_ready`가 false이거나 파일이 없으면 **혼합 모드는 고를 수 없다.** 계획에 "혼합 모드 불가 (Codex 미설정) → 클로드만으로 진행"을 표시한다. 즉 구독 전인 지금은 자동으로 `claude` 모드 = 현재 동작.
- 혼합 모드 시작 전에 `codex --version`으로 설치 여부를 한 번 확인한다 (로그인 만료 등은 첫 작업자 실패로 드러나면 그때 멈추고 알림).
- **Codex 한도 도달 시 자동으로 클로드만 모드로 바꾸지 않는다.** 멈추고 묻는다: "① 클로드만으로 이어가기(Claude 한도 사용) ② Codex 한도 회복까지 대기". `/delegate-all`이면 선택을 decisions.md에 기록.
- 보고서·log에 항상 모드를 적는다: `모드: 혼합 (작업자 Codex 5 · Claude 0, Opus 구원 1)`.
- 한 실행 안에서 모드는 하나. 단 혼합 모드의 Opus 구원은 원래 설계의 일부라 "섞임"으로 보지 않는다.

## 3. 등급별 Codex 모델 표 (구독 시 채움)

| 등급 | 맡기는 일 (지금의 haiku/sonnet/opus 기준 그대로) | Codex 모델 | 추론 강도(effort) |
|---|---|---|---|
| 가벼움 | 검색·파악, 이름 변경, 반복 소규모 수정, 패턴 따르는 테스트 보강 | `____` | low |
| 일반 | 일반 기능 구현, 원인이 분명한 버그, 새 테스트 작성 | `____` | medium |
| 어려움 | 여러 모듈에 걸친 구현, 동시성·보안 위험 코드 | `____` | high |

- 조사 당시(2026-09) 공식 플러그인 README의 예시 모델: `gpt-5.4-mini`, `spark` — **구독 시점 목록으로 다시 확인**.
- 이 표는 `engine.json`에 넣어 스킬 본문을 고치지 않고 바꿀 수 있게 한다:
  ```json
  { "tiers": { "light": {"model": "____", "effort": "low"},
               "normal": {"model": "____", "effort": "medium"},
               "hard": {"model": "____", "effort": "high"} } }
  ```
- **설계 판단은 Codex에 맡기지 않는다.** 여러 안 중 선택·구조 결정은 관리자(Opus)가 지시서에 확정해서 넘긴다.

## 4. 호출 방식

### 4-1. 기본: `codex exec` (명령줄 직접 실행) — 권장
메인 세션이든 마일스톤 리드(서브에이전트)든 Bash/PowerShell로 똑같이 부를 수 있고, 플래그를 전부 제어할 수 있다.

```powershell
# 1) 작업자 전용 작업 폴더 (Codex는 worktree를 자동으로 안 만들어 줌)
git worktree add ..\wt-T1-1 -b dlg/T1-1

# 2) 지시서는 파일로 (따옴표·줄바꿈 문제 방지)
#    .dlg\T1-1\brief.md  ← /delegate 3장 지시서 그대로

# 3) 실행 (플래그는 구독 시 `codex exec --help`로 재확인)
codex exec -C ..\wt-T1-1 -a never --sandbox workspace-write `
  -m <등급 모델> -c model_reasoning_effort="<강도>" `
  --output-schema ~\.claude\skills\delegate\codex-report.schema.json `
  -o .dlg\T1-1\report.json --json (Get-Content .dlg\T1-1\brief.md -Raw) `
  > .dlg\T1-1\events.jsonl
```
- 여러 작업자를 동시에 돌릴 땐 각각 백그라운드 실행으로 띄운다 (동시 수는 속도 설정: 빠르게 3 / 천천히 1).
- `events.jsonl`은 관리자가 **읽지 않는다**. 판정기(아래 5장)만 본다.

### 4-2. 대안: 공식 플러그인 `codex-plugin-cc`
- `/codex:rescue --background --model <모델> --effort <강도>` 또는 플러그인의 `codex:codex-rescue` 서브에이전트.
- 장점: 설치·로그인 연동이 쉽다. 단점: 리포트 형식 강제(`--output-schema`)·worktree 지정 등 세밀한 제어가 되는지 미확인, 서브에이전트 안에서 슬래시 명령이 되는지 미확인.
- → 구독 후 두 방식을 작은 작업으로 비교해 하나로 확정한다.

### 4-3. 리포트 스키마 (지금 쓰는 JSON과 동일)
`~/.claude/skills/delegate/codex-report.schema.json`
```json
{
  "type": "object",
  "required": ["status", "changed_files", "verify", "summary"],
  "properties": {
    "status": { "enum": ["done", "failed", "blocked"] },
    "changed_files": { "type": "array", "items": { "type": "string" } },
    "verify": { "type": "string" },
    "summary": { "type": "string", "maxLength": 600 },
    "blocker": { "type": "string" }
  }
}
```

## 5. 판정 — 세 가지 신호 + 관리자 직접 검증

Codex는 "완료" 신호 하나만 믿으면 틀리는 사례가 보고돼 있다 (02 문서, cc-orchestrator).
1. 종료 코드 0
2. `events.jsonl`에 `turn.completed` 존재
3. `report.json` 파일이 실제로 생김
4. 위 셋이 모두 참이면 → 관리자가 worktree에서 완료 조건 명령을 **직접** 실행 (지금 /delegate 4장과 동일)
5. `changed_files`가 [수정 허용] 밖이면 실패

1~3 확인은 작은 판정 스크립트(`codex-verify.ps1`)로 만들어 `pass/fail + 사유 3줄`만 출력 → 관리자 토큰 절약.

## 6. 실패 시 사다리 (Codex 버전)

| 단계 | 클로드만 모드 | 혼합 모드 |
|---|---|---|
| 1 | 같은 작업자에게 SendMessage | `codex exec resume <세션ID>` + 에러 끝 40줄 첨부 (세션 ID는 `thread.started` 이벤트에서. 병렬이라 `--last`는 쓰지 않음) |
| 2 | 한 등급 위 모델 | 같은 모델 추론 강도 ↑ → 그래도 실패면 한 등급 위 Codex 모델 |
| 3 | 관리자 직접 구원 | **Opus가 구원** (관리자 직접, 또는 opus 서브에이전트) |
| 4 | 사용자 보고 | 동일 |

예산: Codex 재시도(1·2단계)가 재시도 예산(4회 / 마일스톤 12회)을 쓴다. opus 한도(2회 / 4회)는 3단계 Opus 서브에이전트 구원에만 쓴다.

## 7. Codex 환경 주의사항 → 규칙화

| 문제 | 대응 규칙 |
|---|---|
| 샌드박스 인터넷 차단 → 패키지 설치 실패 | 의존성 설치는 관리자가 작업 전에 미리. 설치가 필요한 Task는 지시서에 "설치 금지, 필요하면 blocked" |
| 승인 대기로 멈춤 | 항상 `-a never` (`--full-auto`는 승인 대기가 남아 있어 쓰지 않음) |
| 긴 작업에서 세션이 죽는 사례 (25~30분) | Task를 25분 안에 끝날 크기로 (지금 쪼개기 기준으로 대부분 충족) |
| Windows 네이티브 샌드박스가 아직 experimental | 문제가 나면 WSL2 쪽 Codex로. 전환 첫날 확인 항목 |
| **Codex 사용량 한도 도달** | 자동으로 Claude 작업자로 넘어가지 않는다 (Claude 한도를 몰래 쓰게 됨). 멈추고 사용자에게 "Claude 작업자로 이어갈지 / 한도 회복까지 대기할지" 묻는다 → **구독 시 최종 결정** |

## 8. 바뀔 파일 (영향 범위)

| 파일 | 변경 |
|---|---|
| `delegate/SKILL.md` | 2장 계획에 `모드:` 줄 + `--claude`/`--mixed` 인자 / 3장 지시서를 파일로 저장 / 4장에 세 신호 판정 / 5장 사다리 표에 codex 열 / 새 10장 "혼합 모드" (4·5·7장 내용) |
| `delegate/engine.json` (신규) | 기본 모드, 혼합 모드 조사 작업자, 등급별 모델 표 |
| `delegate/codex-report.schema.json` (신규) | 리포트 스키마 |
| `delegate/codex-verify.ps1` (신규) | 세 신호 판정 스크립트 |
| `delegate-all/SKILL.md` | 3장 기획 승인에 모드 선택 / 4-4 승인 게이트에서 모드 변경 허용 / 10-3 리드 지시에 "혼합 모드면 codex exec로" |
| `delegate-all/state-template.json`, `plan-template.md` | `mode` 칸 (`claude` / `mixed`) |
| 전역 CLAUDE.md | 변경 없음 |

구현 난이도: 스킬 문서 수정 + 작은 스크립트 1개 + 설정 파일 2개. 반나절 이내 예상.

## 9. 구독한 날 체크리스트

1. `npm install -g @openai/codex` → `codex login`
2. `codex exec --help`로 4-1의 플래그(`-C`, `-a`, `-m`, `-c`, `--output-schema`, `-o`, `--json`, `resume`) 실제 이름 확인
3. 사용 가능한 모델 목록 확인 → 3장 표 채우기
4. 작은 작업 1개로 4-1(`codex exec`)과 4-2(플러그인) 비교 → 하나 확정
5. 7장 "사용량 한도 도달 시" 동작 결정
6. 8장 파일 수정 → 원본 고치고 설치본 재복사 (BOM 없는 UTF-8)
7. `engine.json`의 `codex_ready: true`, `default_mode` 결정 (혼합 / 클로드만), 조사 작업자 결정 (Codex / Haiku)
8. 첫 실제 `/delegate`에서 확인: 세 신호 판정, 병렬 worktree, Opus 구원 흐름

## 10. 미검증 (구독 전이라 확인 불가)
- `codex exec` 플래그의 정확한 이름·조합 (특히 `-C`와 `-c model_reasoning_effort`)
- 서브에이전트(마일스톤 리드) 안에서 플러그인 명령이 되는지
- Windows 네이티브 샌드박스에서 worktree 경로·백그라운드 병렬 실행이 문제없는지
- Codex 등급별 실제 품질 — 가벼움 등급이 이 프로젝트들에서 쓸 만한지
