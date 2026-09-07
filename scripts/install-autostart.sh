#!/usr/bin/env bash
# 오케스트레이터 세션 부팅 자동 기동 — LaunchAgent 설치 (멱등)
# 동형 패턴: com.soonho.claude-discord.plist / codex-discord tui-up.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMUX_BIN=$(command -v tmux)
[[ -n "$TMUX_BIN" ]] || { echo "tmux 경로 탐지 실패" >&2; exit 1; }
# OS 분기: macOS=launchd, Linux=systemd 사용자 유닛. HARNESS_OS는 테스트 override, DRY_RUN=1이면 파일만.
OS_NAME="${HARNESS_OS:-$(uname -s)}"
case "$OS_NAME" in Darwin|Linux) ;; *) echo "지원하지 않는 OS: $OS_NAME" >&2; exit 1 ;; esac
LABEL=com.discord-multiagent.orchestrator
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# 설치 시점의 완전한 PATH를 굽는다 — launchd·비대화 로그인 셸에는 bun(.zshrc 전용) 등이 없어
# claude가 spawn하는 MCP 서버(discord=bun, codex 등)가 죽는다 (2026-07-24 실측)
PATH_ESC="${PATH//&/&amp;}"
# -n(세션 표시명)·--remote-control(폰 원격 접속)로 세션 구분·원격 진입을 기동 시 자동 활성화
# claude 직접 exec가 아니라 bot-up.sh 경유 — 봇 여러 개가 동시 부팅할 때 discord 플러그인의
# bun install 경합(EEXIST → MCP 연결 실패)을 전역 락으로 직렬화한다 (2026-07-29·07-31 실측)
SHELL_BIN=/bin/zsh; [[ "$OS_NAME" == Linux ]] && SHELL_BIN=/bin/bash   # 리눅스는 zsh가 없을 수 있다
CMD="$SHELL_BIN -lc 'cd $DIR; export PATH=\"$PATH_ESC\"; export DISCORD_STATE_DIR=$DIR/.discord-state; exec $DIR/scripts/bot-up.sh -n orchestrator --remote-control orchestrator --channels plugin:discord@claude-plugins-official'"

if [[ "$OS_NAME" == Linux ]]; then
  # systemd 사용자 유닛(oneshot+RemainAfterExit) — tmux 세션을 띄우고 빠진다. KillMode=process라 stop 때
  # 공유 tmux 서버(다른 봇 세션)를 죽이지 않는다. 세션 명령 원문은 <세션>.tmux-cmd 사이드카에 두고
  # (bot-restart.sh가 plist 대신 읽음), 유닛은 quoting 문제 없이 up.sh만 부른다.
  UNIT_DIR="$HOME/.config/systemd/user"; UNIT=discord-multiagent-orchestrator
  mkdir -p "$UNIT_DIR"
  printf '%s\n' "$CMD" > "$UNIT_DIR/orchestrator.tmux-cmd"
  cat > "$UNIT_DIR/orchestrator.up.sh" <<EOF
#!/bin/bash
exec "$TMUX_BIN" new-session -d -s orchestrator "\$(cat "$UNIT_DIR/orchestrator.tmux-cmd")"
EOF
  chmod 0755 "$UNIT_DIR/orchestrator.up.sh"
  cat > "$UNIT_DIR/$UNIT.service" <<EOF
[Unit]
Description=discord-multiagent 오케스트레이터 (tmux 세션 orchestrator)
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
KillMode=process
ExecStart=/bin/bash $UNIT_DIR/orchestrator.up.sh
ExecStop=$TMUX_BIN kill-session -t orchestrator

[Install]
WantedBy=default.target
EOF
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable --now "$UNIT.service"
    loginctl enable-linger "$USER" 2>/dev/null || true
  fi
  echo "설치 완료: $UNIT_DIR/$UNIT.service (VPS: 부팅 자동 기동 / WSL2: 우분투가 켜져 있는 동안)"
  exit 0
fi

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
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
fi
echo "설치 완료: $PLIST"
