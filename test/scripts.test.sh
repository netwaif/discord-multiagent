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

exit $fail
