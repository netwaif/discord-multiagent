# MultiAgent — Claude · Codex · Gemini Orchestration Starter

Claude Code를 오케스트레이터로 두고 Claude·Codex·Gemini를 워커로 호출하는 **파일 기반 멀티에이전트 시스템**.

## 핵심 아이디어

- **Orchestrator = Claude Code 세션** (이 폴더 안에서 실행 시 `CLAUDE.md` 자동 적용)
- **Workers** = 외부 모델 호출. 모두 승인 게이트 통과 필요.
  - `claude-main` — 메인 코딩·디버깅·설계·아키텍처·전략
  - `codex-main` — 보조 구현·코드 분석·테스트·로컬 검증·이미지 생성
  - `codex-critic` — `claude-main` 산출물 리뷰·비평 (Codex의 주된 역할)
  - `gemini` — 이미지·긴 문서·제3자 시각의 검토
- **Memory = filesystem.** 런타임 상태 없음. 모든 결정·승인·검증이 파일로 남는다.

## 폴더 구조

```
<설치한-폴더>/
├── CLAUDE.md              # 운영 규칙 전문 (이 폴더 안에서 claude 실행 시만 적용)
├── _shared/
│   ├── routing.md             # worker 선택 decision tree + 호출 명령
│   ├── approval-policy.md     # 승인 게이트 정책 (claude-main 포함)
│   ├── orchestrator-rules.md  # 세션 시작 시 자체 점검 규칙
│   └── learnings.md           # 시스템 일반 재사용 교훈 (추적·공개, append-only)
├── _templates/
│   ├── task.md            # status, goal, constraints, planned_workers, workers_approved
│   ├── context.md         # 현재 스냅샷 ≤ 1500자 / 300단어
│   ├── worker-brief.md    # ≤ 1200자 / 240단어, target_repo + write_scope
│   ├── worker-result.md   # Verification Checklist 포함
│   ├── log.md             # append-only 이력
│   └── task-folder.md     # 새 작업 폴더 생성 가이드
└── tasks/                 # 작업별 폴더 (동적 생성)
    └── <task-name>/
        ├── task.md
        ├── context.md
        ├── log.md
        ├── sources/       # 원본 자료 (선택)
        ├── workers/<role>/
        │   ├── brief.md
        │   └── result.md
        └── artifacts/     # 산출물 원본 (선택)
```

> `_local/` (git 추적 안 함, clone 시 빈 폴더): 작성자의 **프로젝트 특화** 교훈
> (`_local/learnings.md`)이 여기 쌓인다. 공개 starter에는 **시스템 일반** 교훈만
> `_shared/learnings.md`로 배포된다. 분류 규칙은 `_shared/learnings.md` 헤더 참조.

## 사용 시작

```bash
cd <설치한-폴더>
claude
```

자연어로 새 작업 요청:
> "새 작업 만들어줘. 목표는 ○○이고 ○○ worker가 필요할 것 같아."

Orchestrator가 `_templates/task-folder.md` 가이드에 따라 작업 폴더 생성 → worker 승인 요청 → 진행.

## 모니터링 (선택) — mat

작업 진행을 터미널에서 지켜보고 싶다면 **[mat](https://github.com/netwaif/mat)** (MultiAgent Tracker)를 함께 쓴다.
한 작업의 워커 상태(대기·실행 중·완료·에러)·goal·로그를 한 화면에서 본다.
시스템을 **읽기만** 한다 — 작업 생성·승인·워커 호출은 하지 않으므로, 켜두거나 꺼도 진행에 영향이 없다.

```bash
brew install netwaif/tap/mat
MAT_ROOT=<설치한-폴더> mat
```

설치·키 조작 등 자세한 내용은 [mat 저장소](https://github.com/netwaif/mat) 참고.

> ⚠️ mat에서 워커 한 줄 목적이 ` ```yaml `로 보이면 **알려진 경미 이슈**(KI-1)다.
> 시스템·진행에는 영향 없다. [`KNOWN_ISSUES.md`](./KNOWN_ISSUES.md) 참고.

## 알려진 이슈

해결·보류 중인 알려진 결함은 [`KNOWN_ISSUES.md`](./KNOWN_ISSUES.md)에 추적한다.

## 핵심 원칙

| 원칙 | 강제 방식 |
|------|---------|
| 모든 worker 호출 전 승인 | `task.md`의 `workers_approved` 필드 |
| 측정 가능한 컨텍스트 한도 | `wc -m` / `wc -w`로 검증 |
| append-only 로그 | `log.md` 수정·삭제 금지 |
| 최소 worker set | `routing.md` decision tree로 강제 |
| codex-main 외부 repo 쓰기 4-조건 | `target_repo` + `write_scope` + 승인 + log [APPROVAL] |

자세한 규칙은 [`CLAUDE.md`](./CLAUDE.md) 참고.

## 라이선스

개인 사용 및 학습 목적.

<!-- discord-multiagent:start -->
## Discord 하네스 층 (이 설치본의 확장)

이 폴더는 위 표준 시스템에 **Discord I/O 층**을 얹은 설치본이다. 오케스트레이터 세션이
Discord 작업 채널에서 명령을 받고, 태스크별 스레드에 워커 봇 명의로 진행상황을 미러한다.
수다 채널(오케 비관여, 호명 트리거)은 [codex-discord](https://github.com/netwaif/codex-discord)
브리지 데몬이 담당한다.

상세: [설계 스펙](docs/superpowers/specs/2026-07-24-discord-multiagent-design.md) ·
[구현 계획](docs/superpowers/plans/2026-07-24-discord-multiagent-v1.md)

### 추가 요소

| 요소 | 내용 |
|---|---|
| CLAUDE.md 말미 "Discord 운영" 블록 | 수신 규칙·승인 판정(사람 발신+APPROVER 일치)·스레드 절차·미러 규칙 |
| `scripts/post-as.sh <워커> <채널> <메시지>` | 워커 봇 토큰 REST 게시 (실행은 헤드리스, 게시만 명의) |
| `scripts/new-thread.sh <이름>` | 오케 봇 토큰으로 작업 채널에 태스크 스레드 생성 (ID 출력) |
| `.env` / `.env.example` | 채널 ID·승인 권한자·봇 토큰 4종 |
| `.discord-state/` (미추적) | 오케 봇 전용 플러그인 상태 (토큰 `.env` + `access.json`) |

### 오케스트레이터 기동

```bash
tmux new-session -d -s orchestrator -c ~/ai-folder/dev/discord-multiagent
tmux send-keys -t orchestrator \
  'export DISCORD_STATE_DIR=~/ai-folder/dev/discord-multiagent/.discord-state && exec scripts/bot-up.sh -n orchestrator --remote-control orchestrator --channels plugin:discord@claude-plugins-official' Enter
```

- `scripts/bot-up.sh` — claude를 그대로 exec 하되, 봇 여러 개가 동시 부팅할 때 discord
  플러그인의 `bun install` 경합(EEXIST → MCP 연결 실패)을 전역 락으로 직렬화한다.
  봇이 하나뿐이면 `claude`로 바로 기동해도 무방하다.
- `DISCORD_STATE_DIR` — discord 플러그인 상태를 세션별로 격리. 전역
  `~/.claude/channels/discord/`는 수다 채널 클로드 봇 소유이므로 건드리지 말 것.
- `--channels plugin:discord@claude-plugins-official` — 없으면 수신 알림이 세션에 주입되지
  않는다 (MCP 로그에 "Channel notifications skipped").
- `-n <이름>` / `--remote-control <이름>` — 세션 표시명 지정(/rename)과 Remote Control
  활성화(/remote-control)를 기동 시 자동 적용. 폰(claude.ai)에서 이름으로 세션을 찾아
  들어갈 수 있다. 원치 않으면 두 플래그를 빼면 된다.

### 테스트

```bash
bash test/scripts.test.sh   # 게시 스크립트 오프라인 테스트 (DRY_RUN, 네트워크 없음)
```
<!-- discord-multiagent:end -->
