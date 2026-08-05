#!/usr/bin/env bash
# claude 봇 기동 직렬화 래퍼 — LaunchAgent의 tmux 세션 명령이 claude 대신 이 스크립트를 exec 한다.
#
# 문제: 봇 여러 개가 부팅 시 동시에 뜨면 discord 플러그인 MCP(start = "bun install && bun server.ts")가
#       같은 플러그인 캐시 디렉토리에서 bun install을 동시 실행 → bin 링크 EEXIST 경합 → 한쪽 MCP가
#       기동 실패하고 재시도가 없어 그 봇은 채널 미연결로 남는다 (2026-07-29 오케 / 2026-07-31 수다 클로드 실측).
# 해법: 전역 락을 잡은 채 claude를 기동하고, 이 봇의 discord MCP 연결 판정(성공/실패)이 로그에 나타날
#       때까지 락을 유지한다 — 봇들의 bun install 창이 구조적으로 겹치지 않는다.
#       macOS에는 flock(1)이 없어 mkdir 원자성으로 락을 구현한다.
#
# 사용: cd <봇 작업폴더> 후  exec bot-up.sh <claude 인자...>
#       (PATH·DISCORD_STATE_DIR 등 환경은 호출자(plist)가 설정)
set -uo pipefail

LOCK_DIR="${CLAUDE_BOT_LOCK:-$HOME/.claude/bot-boot.lock.d}"
STALE_SEC=600        # 락이 이보다 오래되면 잔존물로 보고 스틸
ACQUIRE_TIMEOUT=300  # 락 대기 상한 — 초과 시 직렬화 포기하고 그냥 기동
CONNECT_TIMEOUT=240  # MCP 연결 판정 대기 상한 — 초과 시 락 해제

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
[[ -z "$CLAUDE_BIN" && -x "$HOME/.local/bin/claude" ]] && CLAUDE_BIN="$HOME/.local/bin/claude"
if [[ -z "$CLAUDE_BIN" || ! -x "$CLAUDE_BIN" ]]; then
  echo "bot-up: claude를 찾을 수 없음 — PATH 또는 CLAUDE_BIN 확인" >&2
  exit 1
fi

log() { echo "[bot-up $(date '+%F %T')] $*"; }

# --- 락 획득 (mkdir 원자성 + 사망/노화 스틸) ---
acquired=0
deadline=$((SECONDS + ACQUIRE_TIMEOUT))
while (( SECONDS < deadline )); do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    acquired=1
    echo $$ > "$LOCK_DIR/pid"
    break
  fi
  holder=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
  if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
    log "락 보유자($holder) 사망 — 스틸"
    rm -rf "$LOCK_DIR"; continue
  fi
  mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
  if (( mtime > 0 && $(date +%s) - mtime > STALE_SEC )); then
    log "락이 ${STALE_SEC}초 이상 잔존 — 스틸"
    rm -rf "$LOCK_DIR"; continue
  fi
  sleep 2
done
(( acquired )) || log "락 대기 ${ACQUIRE_TIMEOUT}초 초과 — 직렬화 없이 기동"

# --- 플러그인 의존성 선워밍 (락 보유 중이면 콜드 install도 단독 수행됨) ---
PLUG_DIR=$(ls -td "$HOME/.claude/plugins/cache/claude-plugins-official/discord/"*/ 2>/dev/null | head -1)
if [[ -n "$PLUG_DIR" ]] && command -v bun >/dev/null 2>&1; then
  (cd "$PLUG_DIR" && bun install --no-summary >/dev/null 2>&1) || true
fi

# --- 연결 판정 감시자: 이 봇의 discord MCP 로그에 성공/실패가 찍히면 락 해제 ---
if (( acquired )); then
  MCP_LOG_DIR="$HOME/Library/Caches/claude-cli-nodejs/${PWD//[\/.]/-}/mcp-logs-plugin-discord-discord"
  STAMP=$(mktemp "${TMPDIR:-/tmp}/bot-up-stamp.XXXXXX")
  (
    watch_deadline=$((SECONDS + CONNECT_TIMEOUT))
    while (( SECONDS < watch_deadline )); do
      sleep 3
      files=$(find "$MCP_LOG_DIR" -name '*.jsonl' -newer "$STAMP" 2>/dev/null || true)
      [[ -n "$files" ]] || continue
      if grep -h -e 'Successfully connected' -e 'Connection failed' $files 2>/dev/null | grep -q .; then
        break
      fi
    done
    rm -f "$STAMP"
    rm -rf "$LOCK_DIR"
  ) >/dev/null 2>&1 &
  # ↑ fd 분리 — 감시자가 stdout 파이프를 붙들면 $(bot-up …) 형태의 호출이
  #   CONNECT_TIMEOUT 내내 블록된다 (2026-08-05 테스트 실측)
fi

# 무인 봇 권한 모드 — 프로덕션 실측(저자 '전역' permissions.defaultMode=auto)의
# 세션 한정 번역. 프로젝트 settings.local.json의 defaultMode는 user 스코프 전용이라
# 효력이 없다(2026-08-05 E2E 실측: 주입돼도 manual mode 유지). 세션 플래그는
# 봇에게만 적용돼 계정 전역을 오염하지 않는다. 호출자 지정이 있으면 존중.
if [[ " $* " != *" --permission-mode "* ]]; then
  set -- "$@" --permission-mode "${BOT_PERMISSION_MODE:-auto}"
fi

log "claude 기동: $CLAUDE_BIN $*"
exec "$CLAUDE_BIN" "$@"
