#!/usr/bin/env bash
# 봇 세션 원격 재시작 — 디스코드에서 "세션 재시작해" 요청을 받은 봇이 자기 pane을 갈아끼운다.
#
# 문제: 봇이 자기 자신을 죽이면 재기동을 마저 할 수 없다 (respawn-pane -k가 자기 프로세스를 죽임).
# 해법: 재시작 작업을 tmux 서버에 위탁(run-shell -b)하고 즉시 반환 — pane이 죽어도 스크립트는
#       tmux 서버 아래에서 살아남아 respawn을 수행한다. 기동 명령은 LaunchAgent plist에서
#       실시간 추출(단일 정본 유지), 연결 판정은 bot-up.sh와 같은 MCP 로그 감시.
#       결과는 웹훅(선택)으로 통지 — 봇이 죽은 뒤에도 사용자 폰에 성패가 도착한다.
#
# 사용: bot-restart.sh <tmux-세션명>   (예: bot-restart.sh orchestrator)
#       - 대상 봇의 LaunchAgent plist(tmux new-session -s <세션명> ...)가 설치돼 있어야 한다.
#       - 웹훅: $BOT_RESTART_WEBHOOK 또는 ~/.config/usage-coach/discord.json 의 webhook_url. 없으면 생략.
set -uo pipefail

NAME="${1:-}"
[[ -n "$NAME" ]] || { echo "사용법: bot-restart.sh <tmux-세션명>" >&2; exit 1; }

CONNECT_TIMEOUT="${BOT_RESTART_CONNECT_TIMEOUT:-300}"  # 재기동 후 MCP 연결 판정 대기 상한
REPLY_GRACE="${BOT_RESTART_REPLY_GRACE:-8}"            # 호출한 봇의 마지막 디스코드 답장이 나갈 시간

TMUX_BIN=$(command -v tmux || true)
[[ -z "$TMUX_BIN" && -x /opt/homebrew/bin/tmux ]] && TMUX_BIN=/opt/homebrew/bin/tmux
[[ -z "$TMUX_BIN" && -x /usr/local/bin/tmux ]] && TMUX_BIN=/usr/local/bin/tmux
[[ -n "$TMUX_BIN" ]] || { echo "tmux를 찾을 수 없음" >&2; exit 1; }

LOG="${BOT_RESTART_LOG:-$HOME/.claude/logs/bot-restart.log}"
mkdir -p "$(dirname "$LOG")"
log() { echo "[bot-restart $(date '+%F %T')] $*"; }

# --- 1단계(봇이 직접 호출): tmux 서버에 위탁하고 즉시 반환 ---
if [[ "${BOT_RESTART_DETACHED:-}" != 1 ]]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  ENVS="BOT_RESTART_DETACHED=1"
  for v in BOT_RESTART_CONNECT_TIMEOUT BOT_RESTART_REPLY_GRACE BOT_RESTART_WEBHOOK BOT_RESTART_LOG; do
    [[ -n "${!v:-}" ]] && ENVS+=" $v='${!v}'"
  done
  "$TMUX_BIN" run-shell -b "$ENVS '$SELF' '$NAME' >> '$LOG' 2>&1"
  echo "재시작 예약됨: $NAME (${REPLY_GRACE}초 뒤 pane 교체, 로그: $LOG)"
  exit 0
fi

# --- 2단계(tmux 서버 아래, pane 사망과 무관하게 진행) ---
log "=== $NAME 재시작 시작 ==="

# 기동 명령 = LaunchAgent plist에서 추출 (tmux new-session -s <NAME> 의 마지막 인자)
CMD=""
for p in "$HOME/Library/LaunchAgents"/*.plist; do
  CMD=$(/usr/bin/plutil -extract ProgramArguments json -o - "$p" 2>/dev/null \
    | /usr/bin/python3 -c "
import json,sys
try: a=json.load(sys.stdin)
except Exception: sys.exit()
if '-s' in a and a[a.index('-s')+1]=='$NAME' and 'new-session' in a: print(a[-1])
" 2>/dev/null)
  [[ -n "$CMD" ]] && break
done
if [[ -z "$CMD" ]]; then
  log "실패: 세션 '$NAME'의 LaunchAgent plist를 찾지 못함"
  exit 1
fi

# 작업폴더(cd 대상) → 이 봇의 discord MCP 로그 경로 (bot-up.sh와 같은 규칙)
WORKDIR=$(echo "$CMD" | grep -oE "cd [^;&']+" | head -1 | sed 's/^cd //; s/ *$//')
MCP_LOG_DIR="$HOME/Library/Caches/claude-cli-nodejs/${WORKDIR//[\/.]/-}/mcp-logs-plugin-discord-discord"

# 웹훅 (없으면 통지 생략) — folder-bot config → usage-coach 순
WEBHOOK="${BOT_RESTART_WEBHOOK:-}"
if [[ -z "$WEBHOOK" && -f "$HOME/.config/folder-bot/config.json" ]]; then
  WEBHOOK=$(sed -nE 's/.*"webhook_url" *: *"([^"]+)".*/\1/p' "$HOME/.config/folder-bot/config.json" | head -1)
fi
if [[ -z "$WEBHOOK" && -f "$HOME/.config/usage-coach/discord.json" ]]; then
  WEBHOOK=$(sed -nE 's/.*"webhook_url" *: *"([^"]+)".*/\1/p' "$HOME/.config/usage-coach/discord.json" | head -1)
fi
notify() {
  [[ -n "$WEBHOOK" ]] || return 0
  curl -s -m 15 -H 'Content-Type: application/json' \
    -d "{\"content\":\"♻️ $NAME 재시작 — $1\"}" "$WEBHOOK" >/dev/null || true
}

sleep "$REPLY_GRACE"

# 재기동 환경 보강: respawn된 pane은 tmux 서버 환경을 물려받는데, 서버를 띄운 launchd job에
# 따라 PATH가 빈약할 수 있다 — claude·bun·node 경로를 앞에 선다 (plist CMD가 PATH를 export하면 그쪽이 우선)
NODE_BIN=$(/bin/ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | tail -1)
SAFE_PATH="$HOME/.local/bin:$HOME/.bun/bin${NODE_BIN:+:$NODE_BIN}:/usr/local/bin:/usr/bin:/bin"

STAMP=$(mktemp "${TMPDIR:-/tmp}/bot-restart-stamp.XXXXXX")
if "$TMUX_BIN" has-session -t "$NAME" 2>/dev/null; then
  "$TMUX_BIN" respawn-pane -k -t "$NAME:0.0" "export PATH=\"$SAFE_PATH:\$PATH\"; $CMD"
else
  "$TMUX_BIN" new-session -d -s "$NAME" "export PATH=\"$SAFE_PATH:\$PATH\"; $CMD"
fi
log "pane 교체 완료 — 연결 판정 대기 (${CONNECT_TIMEOUT}초, $MCP_LOG_DIR)"

RESULT="⏱ ${CONNECT_TIMEOUT}초 내 연결 판정 없음 — pane 확인 필요"
deadline=$((SECONDS + CONNECT_TIMEOUT))
while (( SECONDS < deadline )); do
  sleep 3
  files=$(find "$MCP_LOG_DIR" -name '*.jsonl' -newer "$STAMP" 2>/dev/null || true)
  [[ -n "$files" ]] || continue
  line=$(grep -ho -e 'Successfully connected[^,"]*' -e 'Connection failed[^,"]*' $files 2>/dev/null | tail -1)
  if [[ "$line" == Successfully* ]]; then RESULT="✅ $line — '이어서하자'로 재정박"; break
  elif [[ -n "$line" ]]; then RESULT="❌ $line"; break; fi
done
rm -f "$STAMP"

log "판정: $RESULT"
notify "$RESULT"
log "=== $NAME 재시작 종료 ==="
