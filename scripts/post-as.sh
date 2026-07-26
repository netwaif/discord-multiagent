#!/usr/bin/env bash
# 워커 봇 명의 상태 게시 — 실행은 헤드리스, 게시만 봇 토큰 REST (스펙 §1 결정 5)
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then set -a; source "$ENV_FILE"; set +a; fi
usage() { echo "usage: post-as.sh <claude|codex|gemini> <channel_id> <message...>" >&2; exit 2; }
[[ $# -ge 3 ]] || usage
role="$1"; channel="$2"; shift 2; msg="$*"
case "$role" in
  claude) token="${CLAUDE_BOT_TOKEN:-}" ;;
  codex)  token="${CODEX_BOT_TOKEN:-}" ;;
  gemini) token="${GEMINI_BOT_TOKEN:-}" ;;
  *) usage ;;
esac
[[ -n "$token" ]] || { echo "post-as: $role 토큰 없음 ($ENV_FILE)" >&2; exit 3; }
payload=$(python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1][:1900], "allowed_mentions": {"parse": []}}, ensure_ascii=False))' "$msg")
url="https://discord.com/api/v10/channels/$channel/messages"
if [[ "${DRY_RUN:-0}" == "1" ]]; then echo "DRY_RUN POST $url $payload"; exit 0; fi
curl -sf -X POST "$url" -H "Authorization: Bot $token" -H "Content-Type: application/json" -d "$payload" >/dev/null
