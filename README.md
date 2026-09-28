# claude-code-delegate

Claude Code만으로 만드는 관리자(Opus)-작업자(Sonnet/Haiku) 계층형 코딩 위임 파이프라인.
비싼 상위 모델은 계획·판정·구원만 맡고, 실제 코딩은 하위 모델 작업자에게 맡겨 비용을 줄이려는
목적으로 설계했다. 작업 단위 스킬(`/delegate`)과 프로젝트 단위 스킬(`/delegate-all`) 두 개로
구성된다.

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

- **`/delegate`** — 작업 하나를 관리자·작업자로 분해 실행. 작업자는 git worktree로 격리되고,
  결과는 patch로 병합된다. 승인 후 시작, 재시도 예산(첫 시도 무제한 + 재시도 4회) 안에서 동작.
- **`/delegate-all`** — 프로젝트 전체 단위: 발견 → 기획(승인) → 마일스톤 루프(승인) → 완료를
  상태 파일(`docs/delegate-all/state.json`)로 관리해 세션이 끊겨도 이어할 수 있다.

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
- 예시 스크립트·문서 일부는 Windows 환경(cmd.exe, PowerShell)을 기준으로 실측했다. 핵심 로직
  자체는 플랫폼 종속적이지 않지만, 다른 OS에서의 검증은 아직 없다.

## 설계 배경

`docs/`에 이 파이프라인이 지금 설계에 도달한 조사·정정 과정과 실측 근거가 있다:

1. `01-분업화-기초조사.md` — 최초 조사(일부 서술은 이후 정정됨)
2. `02-Codex-워커-Claude-구원-파이프라인.md` — Codex 하위워커+Claude 구원 구조 조사, 01 오류 정정
3. `03-Claude-단독-관리자-작업자-파이프라인.md` — **채택된 설계**: 02의 Codex 자리를 Claude Sonnet/Haiku로 교체
4. `04-효과-점검.html` — 실사용 효과 점검 리포트 (브라우저로 열어서 확인)
5. `05-Codex-작업자-전환-설계.md` — 보류 중인 설계, Codex 구독 시 작업자를 Codex로 전환하는 계획

## 라이선스

MIT
