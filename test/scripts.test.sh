#!/usr/bin/env bash
# post-as.sh·new-thread.sh 오프라인 테스트 (DRY_RUN — 네트워크 없음)
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
t() { local name="$1"; shift; if "$@"; then echo "PASS $name"; else echo "FAIL $name"; fail=1; fi; }

# post-as.sh
ENV_FILE=/dev/null "$DIR/scripts/post-as.sh" codex 2>/dev/null; rc=$?
t "인자 부족 → exit 2" [ "$rc" -eq 2 ]
ENV_FILE=/dev/null "$DIR/scripts/post-as.sh" solbot 123 hi 2>/dev/null; rc=$?
t "알 수 없는 워커 → exit 2" [ "$rc" -eq 2 ]
ENV_FILE=/dev/null DRY_RUN=1 "$DIR/scripts/post-as.sh" codex 123 hi 2>/dev/null; rc=$?
t "토큰 없음 → exit 3" [ "$rc" -eq 3 ]
out=$(ENV_FILE=/dev/null CODEX_BOT_TOKEN=x DRY_RUN=1 "$DIR/scripts/post-as.sh" codex 123 "hello world")
t "DRY_RUN에 URL 포함" bash -c "[[ '$out' == *'/channels/123/messages'* ]]"
t "DRY_RUN에 본문 포함" bash -c "[[ '$out' == *'hello world'* ]]"
t "멘션 차단 포함" bash -c "[[ '$out' == *'\"parse\": []'* ]]"

# new-thread.sh
ENV_FILE=/dev/null "$DIR/scripts/new-thread.sh" 2>/dev/null; rc=$?
t "스레드명 없음 → exit 2" [ "$rc" -eq 2 ]
out=$(ENV_FILE=/dev/null ORCH_BOT_TOKEN=x WORK_CHANNEL_ID=777 DRY_RUN=1 "$DIR/scripts/new-thread.sh" "내 스레드")
t "스레드 DRY_RUN URL" bash -c "[[ '$out' == *'/channels/777/threads'* ]]"

# bot-up.sh — 무인 권한 모드 플래그 주입 (CLAUDE_BIN을 echo로 바꿔 최종 인자 검증)
# 락은 CLAUDE_BOT_LOCK으로 tmp 격리 — 기본 경로($HOME/.claude/…)는 fake HOME에
# 부모가 없어 mkdir이 300초 재시도 루프에 빠진다
bu() { HOME=$(mktemp -d) CLAUDE_BOT_LOCK=$(mktemp -d)/lock CLAUDE_BIN=/bin/echo \
       "$DIR/scripts/bot-up.sh" "$@" 2>/dev/null | tail -1; }
out=$(bu -n orch --channels x)
t "bot-up: --permission-mode auto 주입" bash -c "[[ '$out' == *'--permission-mode auto'* ]]"
t "bot-up: 원 인자 보존" bash -c "[[ '$out' == *'--channels x'* ]]"
out=$(bu --permission-mode plan --channels x)
t "bot-up: 호출자 지정 모드 존중" bash -c "[[ '$out' == *'--permission-mode plan'* ]] && [[ '$out' != *'auto'* ]]"

exit $fail
