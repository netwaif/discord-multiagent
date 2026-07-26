#!/usr/bin/env bash
# 작업 채널에 태스크 스레드 생성 (오케 봇 토큰) — stdout에 스레드 ID 한 줄
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then set -a; source "$ENV_FILE"; set +a; fi
[[ $# -ge 1 ]] || { echo "usage: new-thread.sh <thread-name>" >&2; exit 2; }
[[ -n "${ORCH_BOT_TOKEN:-}" && -n "${WORK_CHANNEL_ID:-}" ]] || { echo "new-thread: ORCH_BOT_TOKEN·WORK_CHANNEL_ID 필요 ($ENV_FILE)" >&2; exit 3; }
payload=$(python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1][:90], "type": 11, "auto_archive_duration": 1440}, ensure_ascii=False))' "$1")
url="https://discord.com/api/v10/channels/$WORK_CHANNEL_ID/threads"
if [[ "${DRY_RUN:-0}" == "1" ]]; then echo "DRY_RUN POST $url $payload"; exit 0; fi
curl -sf -X POST "$url" -H "Authorization: Bot $ORCH_BOT_TOKEN" -H "Content-Type: application/json" -d "$payload" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
