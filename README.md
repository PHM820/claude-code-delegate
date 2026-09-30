# claude-code-delegate

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Claude Code로 만드는 관리자(Opus)-작업자 계층형 코딩 위임 파이프라인. 작업자는 **Codex가 설치돼
있으면 Codex, 없으면 Claude 하위 모델(Sonnet/Haiku)** 이 자동으로 맡는다.
비싼 상위 모델은 계획·판정·구원만 맡고, 실제 코딩은 작업자에게 맡겨 비용을 줄이려는
목적으로 설계했다. 작업 단위 스킬(`/delegate`)과 프로젝트 단위 스킬(`/delegate-all`) 두 개로
구성된다.

git worktree로 작업자를 격리하고 결과는 patch로 병합하기 때문에, 관리자 세션과 원본 저장소는
작업자가 무슨 짓을 하든 안전하다. 검증은 자체 구현 없이 프로젝트의 `verify.cmd` 종료 코드에
맡긴다 — 있으면 그걸 쓰고, 없으면 즉석 판단으로 폴백한다.

## 설치

```bash
git clone https://github.com/PHM820/claude-code-delegate.git
cp -r claude-code-delegate/skills/delegate ~/.claude/skills/delegate
cp -r claude-code-delegate/skills/delegate-all ~/.claude/skills/delegate-all
```

Windows는 `%USERPROFILE%\.claude\skills\`, macOS/Linux는 `~/.claude/skills/`.

두 스킬 모두 `disable-model-invocation: true`로 설정돼 있어, Claude가 스스로 호출하지 않고
사용자가 `/delegate <작업>` 또는 `/delegate-all <설명>`으로 명시적으로 실행해야 한다.

**알려진 함정**: SKILL.md의 `model: claude-opus-5-5` 필드는 그 스킬을 호출한 응답 한 번에만
적용되고, 이어지는 사용자 메시지부터는 세션 모델(사용자가 앱에서 고른 모델)로 돌아간다(실측
확인, Claude Code 공식 동작). 관리자를 계속 Opus로 유지하려면 스킬이 뜨는 승인 확인 메시지가
안내하는 대로, **승인하기 전에 앱의 모델 선택기에서 직접 Opus를 골라야** 한다.

## 구성

- **`/delegate`** — 작업 하나를 관리자·작업자로 분해해 실행한다. 작업자를 git worktree로
  격리해 돌리고, 끝나면 결과를 patch로 병합한다. 실패하면 재시도 예산(첫 시도 무제한 + 재시도
  4회) 안에서 관리자가 원인을 보고 다시 붙인다. 승인 후 시작.
- **`/delegate-all`** — 프로젝트 전체 단위로 발견 → 기획(승인) → 마일스톤 루프(승인) → 완료를
  이어간다. 진행 상태를 파일(`docs/delegate-all/state.json`)에 남겨 세션이 끊겨도 이어서 돌릴
  수 있다.

## 작업자 엔진 — Codex 우선, 없으면 Claude

`/delegate` 시작 때 `codex-detect.ps1`이 Codex(설치·ChatGPT 로그인·모델 목록)를 확인한다.
있으면 **Codex 엔진**, 없으면 지금까지처럼 **Claude 엔진**이다. 한 실행 안에서 엔진은 하나이고,
관리자·판정·Opus 구원은 어느 쪽이든 Claude다. `--claude`를 붙이면 Codex가 있어도 Claude 엔진.

관리자는 작업을 등급으로 나눠 배정하고, 등급→모델은 `skills/delegate/engine.json`이 정한다:

| 등급 | 맡기는 일 | Claude 엔진 | Codex 엔진 |
|---|---|---|---|
| 가벼움 | 검색·파악, 이름 변경, 소규모 반복 수정 | haiku | gpt-6-luna · low |
| 일반 | 일반 구현, 원인이 분명한 버그, 새 테스트 | sonnet | gpt-6.1-sol · medium |
| 어려움 | 여러 모듈·동시성·보안 위험 코드 | opus | gpt-6.1-sol · high |

- **상위 모델은 Claude(Opus 5.5 / Sonnet 5.5)만 쓴다.** 어려움 등급(gpt-6.1-sol · high)에서도 실패하면 Codex 위로 올라가지 않고 Claude가 구원한다. gpt-6-astra는 쓰지 않는다.
- 새 모델이 나오면 `engine.json`만 고치면 된다. 모델이 목록에 없으면 대체 모델로 자동 전환.
- **Codex 한도에 닿으면 자동으로 Claude로 넘기지 않고** 멈춰서 묻는다 (Claude 한도를 몰래 쓰지 않으려고).
- Codex 샌드박스는 프로그램 실행이 막히는 경우가 있어(실측) 작업자 자체 검증은 참고용이고, 성공 판정은
  항상 관리자가 직접 실행한다.
- 상세: `skills/delegate/SKILL.md` 2장·10장. Windows 전용 (PowerShell 스크립트 2개).

## 검증(verify) 동작 방식

작업자 결과 판정은 3단계로 등급이 갈린다:

1. **`.claude/verify.cmd`가 있으면** 그 종료 코드(0/1/3)로 기계적 판정.
2. **없지만 표준 검사 명령을 즉석에서 찾을 수 있으면** (package.json, pyproject.toml 등) 그
   자리에서 명령 하나를 시도해 판정에 쓴다.
3. **그것도 없으면** 자동 판정 불가로 보고하고 수동 확인으로 넘긴다.

[claude-code-harness](https://github.com/PHM820/claude-code-harness)를 함께 설치하면 새
프로젝트에 `verify.cmd`/`smoke.cmd`를 자동으로 만들어줘서 항상 1단계로 판정할 수 있지만,
**필수 의존은 아니다** — harness 없이도 이 파이프라인은 2·3단계로 동작한다.

## 요구사항

- git이 필요하다(worktree 격리를 씀). git 없는 프로젝트에서는 격리 없이 순차 실행한다.
- Codex 엔진을 쓰려면 Codex(CLI가 든 데스크톱 앱 또는 `npm i -g @openai/codex`)를 설치하고 로그인해야 한다. 없어도 Claude 엔진으로 동작한다.
- 예시 스크립트·문서 일부는 Windows 환경(cmd.exe, PowerShell)을 기준으로 실측했다. 핵심 로직
  자체는 플랫폼 종속적이지 않지만, 다른 OS에서의 검증은 아직 없다.

## 설계 배경

`docs/`에 이 파이프라인이 지금 설계에 도달한 조사·정정 과정과 실측 근거가 있다:

1. `01-분업화-기초조사.md` — 최초 조사(일부 서술은 이후 정정됨)
2. `02-Codex-워커-Claude-구원-파이프라인.md` — Codex 하위워커+Claude 구원 구조 조사, 01 오류 정정
3. `03-Claude-단독-관리자-작업자-파이프라인.md` — **채택된 설계**: 02의 Codex 자리를 Claude Sonnet/Haiku로 교체
4. `04-효과-점검.html` — 실사용 효과 점검 리포트 (브라우저로 열어서 확인)
5. `05-Codex-작업자-전환-설계.md` — Codex 작업자 전환 설계. **구현 완료(2026-09-30)**, 실측에서 설계와 달라진 점은 문서 맨 위에 정리

## 라이선스

MIT
