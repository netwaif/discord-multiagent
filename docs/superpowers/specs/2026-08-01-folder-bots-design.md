# 폴더 봇 유연화 — 설계

2026-08-01 · 사용자 승인된 설계 (브레인스토밍 결과)

## 목표

"업무 = 폴더" 세션을 전용 디스코드 채널 봇으로 유연하게 추가한다.
지금은 클로드·코덱스 봇이 지정된 폴더·지정된 tmux 세션에 하드코딩돼 있다
(plist에 폴더 경로·세션명·`-n`·`--remote-control` 플래그가 박혀 있음).
이를 설정 파일로 빼고, CLAUDE.md/AGENTS.md의 디스코드 지침은 loadout 조각으로 승격한다.

확정 요구:
- 봇 추가는 **수다 층**(대화형 세션) 우선. 봇마다 **폴더별 전용 채널** — 호명 게이트 불필요.
- **모든 대화형 세션은 재시작으로 컨텍스트 관리**가 성립해야 한다
  ("세션 마감하고 재시작해" → 웹훅 알림 → "이어서하자", scripts/bot-restart.sh 흐름).
- 폴더 경로·세션명·리모트 컨트롤 이름 등은 사용자가 설정 가능해야 한다.
- 디스코드 포탈 작업(봇 계정 생성·초대·채널 생성)은 수동 — 가이드 문서로 안내.

## 현황 (실측)

- 클로드 봇 고정 지점 3곳: LaunchAgent plist(폴더·세션명·플래그) /
  `.discord-state`(토큰·페어링) / CLAUDE.md 디스코드 블록(수동 작성).
- codex-discord 브리지는 이미 다중 인스턴스 패턴 보유:
  제미나이 봇 = `--env-file=.env.gemini` + `data-gemini/` + 별도 plist. 같은 코드, 설정만 분리.
- loadout 조각 추가는 `generator/fragments/_TEMPLATE` 복사 + `meta.json` + `fragment.md`가 전부.
  소스 레포 = `~/VSCodeWorkspace/loadout`.
- `scripts/bot-restart.sh`는 plist에서 기동 명령을 실시간 추출하므로
  plist가 올바르면 새 봇에도 무수정 동작.

## 구성요소

### 1. `bots.json` — 봇 정의 설정 파일

- 위치: 하네스 레포 루트(`~/ai-folder/dev/discord-multiagent/bots.json`).
  개인값(경로·이름)이므로 **git 제외**, `bots.json.example` 동봉.
- 스키마 (봇 하나 = 한 항목):

```json
{
  "collab": {
    "engine": "claude",            // claude | codex | gemini
    "folder": "~/ai-folder/collab",
    "session": "collab-bot",       // tmux 세션명 (= -n 표시명)
    "remote_control": "collab-bot", // 생략 시 session 값. false면 비활성
    "state_dir": "~/ai-folder/collab/.discord-state",  // claude 전용
    "channel_id": "",              // codex/gemini 전용 (TUI_CHANNEL_ID)
    "autostart": true
  }
}
```

- 기존 두 봇(수다 클로드 `claude-discord`, 오케 `orchestrator`)도 이 파일로 이관해
  같은 방식으로 관리한다.

### 2. `scripts/install-autostart.sh` 확장

- `bots.json`을 읽어 봇마다 LaunchAgent plist를 멱등 생성·(재)등록한다.
  - engine=claude → 기존 CMD 패턴(cd 폴더 + DISCORD_STATE_DIR + bot-up.sh -n … --remote-control … --channels …).
  - engine=codex|gemini → codex-discord 레포에 `.env.<이름>` 생성(템플릿 + folder/channel 값 주입),
    `data-<이름>/` 준비, 데몬 plist + (live 모드) TUI plist 생성. — **2단계 범위**.
- `bots.json`이 없으면 기존 동작(오케 단일 설치) 유지 — 하위 호환.
- `~/.local/bin/bot-restart` 심링크 생성(조각이 경로 없이 호출할 수 있도록).
- launchctl bootout 주의사항(부팅 시 tmux 서버를 띄운 job을 내리면 프로세스 그룹째 죽는 문제)은
  기존 결정 유지: 파일 갱신 후 다음 부팅 적용을 기본으로 하고, 즉시 기동은 tmux 직접 기동으로.

### 3. loadout 조각 "디스코드 봇" 신설 (소스: `~/VSCodeWorkspace/loadout`)

- 내용(정적 텍스트 — 폴더별 값 없음):
  - 전용 채널 응대 규칙: 이 세션은 discord 플러그인으로 전용 채널에 연결된 봇이다.
    채널 메시지 처리·reply 사용·긴 작업 시 진행 편집 등 기본 규약.
  - **세션 재시작 절**: 사용자가 재시작을 요청하면 ① 세션 마감(SESSION.md 갱신 —
    session-handoff 조각과 짝) ② 짧게 답장 ③ `bot-restart $(tmux display-message -p '#S')`
    실행. 하네스 레포 경로는 머신마다 다르므로 조각에는 경로를 박지 않는다 —
    install-autostart.sh가 `~/.local/bin/bot-restart` 심링크를 만들어 PATH로 해결.
  - 봇이 자기 tmux 세션명을 `tmux display-message -p '#S'`로 알아내므로 조각에
    세션별 값이 들어가지 않는다.
- `fragment.codex.md` (AGENTS.md flavor): codex 폴더 봇용 동등 규칙 — **2단계 범위**.
- 기존 수다 클로드 CLAUDE.md의 수동 블록은 조각 설치로 대체(중복 제거).

### 4. 새 봇 추가 절차 (사용자 관점, 가이드 문서화)

1. 디스코드 포탈: 봇 계정 생성 → 토큰 발급 → 서버 초대 / 서버에 전용 채널 생성
2. 대상 폴더에서 토큰 페어링: `/discord:configure` (state_dir 지정)
3. `bots.json`에 항목 추가
4. `scripts/install-autostart.sh` 실행
5. loadout으로 "디스코드 봇" + "세션 이어가기" 조각 설치

이후: 채널에서 대화 → 컨텍스트 차면 "세션 마감하고 재시작해" → 웹훅 확인 → "이어서하자".

## 에러 처리

- install-autostart: bots.json 파싱 실패·필수 키 누락 시 해당 봇 건너뛰고 명시 보고(전체 중단 아님).
- 동시 부팅 경합은 기존 bot-up.sh 락이 해결(봇 수가 늘어도 직렬화 유지).
- bot-restart: 레지스트리 도입 후에도 현행 plist 추출 방식 유지(정본은 plist — bots.json은 생성 입력).

## 검증 기준

- bots.json에 시험 봇 항목 추가 → install-autostart 실행 → plist 생성·기동·채널 연결(MCP 로그) 확인.
- 재시작 흐름: 새 봇에서 bot-restart.sh 자기 세션명 탐지 → respawn → 웹훅 통지 확인.
- loadout doctor 통과 + 조각 설치/반품 멱등성.
- 기존 두 봇 이관 후 재부팅 스모크(3봇 연결 판정 절차 재사용).

## 비범위 (YAGNI)

- 중앙 매니저 데몬, 작업 채널(오케층) 다중화, 봇 간 대화, 채널 자동 생성(포탈 API).
- 공개 릴리즈·매뉴얼 반영은 1단계 검증 후 별도 결정.

## 구현 순서

1. **1단계**: bots.json + install-autostart 확장(claude) + loadout "디스코드 봇" 조각(CLAUDE.md flavor) + 기존 봇 이관 + 시험 봇 1개(협업 폴더) 검증
2. **2단계**: codex/gemini 인스턴스 자동화 + fragment.codex.md
3. **3단계**: 가이드 문서·매뉴얼 반영·릴리즈(사용자 결정)
