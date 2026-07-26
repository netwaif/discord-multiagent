#!/usr/bin/env bash
# 오케스트레이터 세션 부팅 자동 기동 — LaunchAgent 설치 (멱등)
# 동형 패턴: com.soonho.claude-discord.plist / codex-discord tui-up.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMUX_BIN=$(command -v tmux)
[[ -n "$TMUX_BIN" ]] || { echo "tmux 경로 탐지 실패" >&2; exit 1; }
LABEL=com.discord-multiagent.orchestrator
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# 설치 시점의 완전한 PATH를 굽는다 — launchd·비대화 로그인 셸에는 bun(.zshrc 전용) 등이 없어
# claude가 spawn하는 MCP 서버(discord=bun, codex 등)가 죽는다 (2026-07-24 실측)
PATH_ESC="${PATH//&/&amp;}"
CMD="/bin/zsh -lc 'cd $DIR; export PATH=\"$PATH_ESC\"; export DISCORD_STATE_DIR=$DIR/.discord-state; exec claude --channels plugin:discord@claude-plugins-official'"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$TMUX_BIN</string><string>new-session</string><string>-d</string>
    <string>-s</string><string>orchestrator</string><string>$CMD</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "설치 완료: $PLIST"
