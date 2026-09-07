#!/usr/bin/env bash
# install-autostart.sh 리눅스 분기 오프라인 테스트 — HARNESS_OS=Linux DRY_RUN=1 (systemctl/launchctl 무접촉).
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# 안전장치: 실기기 LaunchAgent/systemd에 닿으면 즉시 실패
for c in launchctl systemctl loginctl; do printf '#!/bin/sh\necho "FAIL: %s 호출됨" >&2; exit 97\n' "$c" > "$TMP/bin/$c"; chmod +x "$TMP/bin/$c"; done
HOME="$TMP" HARNESS_OS=Linux DRY_RUN=1 PATH="$TMP/bin:$PATH" bash "$DIR/scripts/install-autostart.sh" > "$TMP/out.log" 2>&1 || { cat "$TMP/out.log"; echo "FAIL: exit"; exit 1; }
U="$TMP/.config/systemd/user"
[[ -f "$U/discord-multiagent-orchestrator.service" ]] || { cat "$TMP/out.log"; echo "FAIL: 유닛 없음"; exit 1; }
grep -q 'RemainAfterExit=yes' "$U/discord-multiagent-orchestrator.service" || { echo "FAIL: oneshot"; exit 1; }
grep -q 'KillMode=process' "$U/discord-multiagent-orchestrator.service" || { echo "FAIL: KillMode"; exit 1; }
[[ -f "$U/orchestrator.tmux-cmd" ]] || { echo "FAIL: tmux-cmd 사이드카 없음"; exit 1; }
grep -q 'bot-up.sh -n orchestrator' "$U/orchestrator.tmux-cmd" || { echo "FAIL: 사이드카 명령"; exit 1; }
grep -q '/bin/bash -lc' "$U/orchestrator.tmux-cmd" || { echo "FAIL: 리눅스는 bash -lc"; exit 1; }
[[ -x "$U/orchestrator.up.sh" ]] || { echo "FAIL: up.sh 없음/실행권한"; exit 1; }
grep -q 'orchestrator.up.sh' "$U/discord-multiagent-orchestrator.service" || { echo "FAIL: ExecStart→up.sh"; exit 1; }
[[ ! -d "$TMP/Library/LaunchAgents" ]] || { echo "FAIL: 리눅스에서 plist 생성"; exit 1; }
# macOS 경로도 DRY_RUN이면 launchctl 무접촉이어야 한다
HOME="$TMP" HARNESS_OS=Darwin DRY_RUN=1 PATH="$TMP/bin:$PATH" bash "$DIR/scripts/install-autostart.sh" > "$TMP/out2.log" 2>&1 || { cat "$TMP/out2.log"; echo "FAIL: darwin dry-run exit"; exit 1; }
[[ -f "$TMP/Library/LaunchAgents/com.discord-multiagent.orchestrator.plist" ]] || { echo "FAIL: darwin plist"; exit 1; }
echo "autostart-linux.test OK"
