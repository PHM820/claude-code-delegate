# CLAUDE_MAP — claude-code-delegate

Claude Code만으로 만드는 관리자(Opus)-작업자(Sonnet/Haiku) 계층형 코딩 위임 파이프라인.
작업 단위(`/delegate`)와 프로젝트 단위(`/delegate-all`) 두 스킬로 구성.

## 기능별 지도

| 기능 | 경로 | 설명 |
|---|---|---|
| /delegate 스킬 | `skills/delegate/SKILL.md` | 작업 하나를 관리자·작업자로 분해 실행. 작업자는 git worktree로 격리, 결과는 patch로 병합. 직접처리 A/B/C 기준, 승인 후 시작, 예산(첫 시도 무제한+재시도 4회) |
| Codex 엔진 (작업자) | `skills/delegate/{engine.json,codex-detect.ps1,codex-run.ps1,codex-report.schema.json}` | Codex가 있으면 작업자를 Codex로, 없으면 Claude로 자동 전환. `engine.json`=등급→모델 표, `codex-detect.ps1`=설치·로그인·모델 확인(JSON 한 줄), `codex-run.ps1`=작업자 1명 실행+세 신호 판정(PASS/FAIL/LIMIT), 스키마=작업자 리포트 형식. 절차는 `skills/delegate/SKILL.md` 2장·10장 |
| /delegate-all 스킬 | `skills/delegate-all/SKILL.md` | v0.11. 프로젝트 전체 단위: 발견→기획(승인)→마일스톤 루프(승인)→완료, 상태 파일로 세션 넘어 이어하기. harness는 **선택적 연동**(있으면 verify.cmd 생성·활용, 없어도 등급 2(즉석 검증 명령)·등급 3(수동 확인 안내)로 동작) — harness 저장소가 필수 의존이 아님 |
| /delegate-all 템플릿 | `skills/delegate-all/{plan,backlog,report}-template.md`, `state-template.json` | 대상 프로젝트의 `docs/delegate-all/`에 생성되는 파일의 틀 |
| 작업자 템플릿 (참고용, 미사용) | `agents/worker.md`, `worker-light.md` | 고정 작업자 파일 방식 — 즉석 편성 방식으로 대체됨 |
| 설계 조사 문서 | `docs/01~05` | 이 파이프라인이 이 설계에 도달한 조사·정정 과정과 실측 근거. 01→02→03 순서로 최초 조사, 정정, 채택된 설계. 04는 실사용 효과 점검. 05는 보류 중인 Codex 작업자 전환 설계 |

## 설치 방법

`skills/delegate/`, `skills/delegate-all/`을 각각 `~/.claude/skills/`로 복사. `disable-model-invocation: true` 설정으로 사용자가 `/delegate`로만 명시 호출하도록 되어 있음(모델이 스스로 호출 안 함).

## 핵심 설계

- **격리**: git worktree + patch 병합(`git diff --cached --binary --output=` → `git apply`). worktree 안에 junction/symlink 절대 금지(원본 삭제 위험 실측 확인).
- **비용 절감 핵심은 모델 등급보다 세션 관리**: 실측 결과 관리자가 긴 기존 대화 위에서 호출되면 호출당 토큰이 급증. `/delegate`는 긴 대화면 새 세션 권고, `/delegate-all`은 기획 1세션+마일스톤당 1세션을 강제.
- **검증은 외부 하네스에 위임**: 작업자 결과 판정은 [claude-code-harness](https://github.com/PHM820/claude-code-harness)가 만든 `.claude/verify.cmd`/`.claude/smoke.cmd`의 종료 코드로 한다 — 이 저장소 자체에는 검증 스크립트를 만들지 않음.

## 관련 프로젝트

[claude-code-harness](https://github.com/PHM820/claude-code-harness) — 이 파이프라인이 작업자 결과를 기계적으로 판정하는 데 쓰는 프로젝트 검증 환경 구축 스킬. 함께 쓰는 것을 권장하지만 독립적으로도 각각 동작한다.
