# Discord MultiAgent v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (인라인). v1 계획(2026-07-24-discord-multiagent-v1.md)의 Global Constraints 승계.

**Goal:** v1 실사용에서 확인된 보강 3건 — 오케 log 태그 규율, 부팅 자동 기동, 수다 채널 컨텍스트 큐.

**범위 외:** B안(스레드 멘션 위임)·배포 팩징은 다음 덩어리.

---

### Task 1: 오케 log 태그 규율 보강

**Files:**
- Modify: `CLAUDE.md` (Discord 블록 내 미러 규칙 아래 1줄)

- [ ] **Step 1:** 미러 규칙 섹션 끝에 추가:

```markdown
- log.md 태그는 정본 6종(`DECISION|WORKER_CALL|VERIFICATION|ERROR|APPROVAL|COMPLETE`)만
  사용한다 — 태스크 생성·라우팅·승인 대기 등은 전부 `[DECISION]`으로 기록 (임의 태그 금지)
```

- [ ] **Step 2:** 마커 무결성 grep (start/end 각 1) 후 커밋 `docs: log 태그 정본 6종 강제 (INV3)`
- [ ] **Step 3:** 오케 세션 재시작은 Task 2의 plist 검증과 겸한다 (kill 후 자동 기동 확인)

### Task 2: 부팅 자동 기동

**Files:**
- Create: `scripts/install-autostart.sh`
- 생성물: `~/Library/LaunchAgents/com.discord-multiagent.orchestrator.plist` (미추적)

**Interfaces:** com.soonho.claude-discord.plist와 동형 — tmux new-session 원라이너, RunAtLoad만(KeepAlive 없음, 인터랙티브). 멱등성 = tmux 동명 세션 생성 거부.

- [ ] **Step 1:** `scripts/install-autostart.sh` 작성 (tmux·claude 절대경로 탐지, plist 생성, bootout→bootstrap 멱등):

```bash
#!/usr/bin/env bash
# 오케스트레이터 세션 부팅 자동 기동 — LaunchAgent 설치 (멱등)
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMUX_BIN=$(command -v tmux) CLAUDE_BIN=$(command -v claude)
LABEL=com.discord-multiagent.orchestrator
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CMD="cd $DIR && export DISCORD_STATE_DIR=$DIR/.discord-state && exec $CLAUDE_BIN --channels plugin:discord@claude-plugins-official"
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
```

- [ ] **Step 2:** 기존 orchestrator tmux 세션 kill → `bash scripts/install-autostart.sh` 실행 → bootstrap의 RunAtLoad로 세션이 새로 뜨는지 `tmux capture-pane`으로 확인 (Task 1 규칙도 이 재시작으로 반영)
- [ ] **Step 3:** 커밋 `feat: 부팅 자동 기동 (install-autostart.sh)`

### Task 3: 수다 채널 컨텍스트 큐 (codex-discord)

**Files:**
- Modify: `~/ai-folder/dev/codex-discord/src/index.mjs` (헤드리스 공유 채널 분기)

**Interfaces:** 공유 채널(NAME_TRIGGER_CHANNELS)의 의미론을 v1의 단순 게이트에서 `classifyMessage`(TUI와 동일, 기존 테스트 커버)로 교체 + 채널별 `ContextQueue`(기존 클래스). 전용 채널 경로 불변.

- [ ] **Step 1:** index.mjs 헤드리스 진입부를 다음으로 교체 — 공유 채널이면 classify: ignore→무시 / context→큐 적재(텍스트만, 첨부 다운로드 없음) / trigger→큐 drain을 프롬프트로, 실패 시 restore:

```js
  // ===== 기존 headless 경로 =====
  let sharedCtx = null; // 공유 채널: TUI와 동일 의미론 + 채널별 컨텍스트 큐
  if (NAME_TRIGGER_CHANNELS.has(message.channelId)) {
    const verdict = classifyMessage({
      isMe: message.author.id === client.user.id,
      isBot: message.author.bot,
      allowed: ALLOWED.has(message.author.id),
      mentionsMe: message.mentions.users.has(client.user.id),
      mentionsOthers: message.mentions.users.size > 0 && !message.mentions.users.has(client.user.id),
      content: message.content ?? '',
      triggerName: TRIGGER_NAME,
    });
    if (verdict === 'ignore') return;
    const speaker = message.member?.displayName ?? message.author.username;
    let queue = sharedQueues.get(message.channelId);
    if (!queue) { queue = new ContextQueue(); sharedQueues.set(message.channelId, queue); }
    if (verdict === 'context') { queue.push(speaker, message.cleanContent ?? ''); return; }
    sharedCtx = { queue, speaker };
  } else if (message.author.bot) return;
  if (!ALLOWED.has(message.author.id)) return;
  if (!sharedCtx && message.mentions.users.size > 0 && !message.mentions.users.has(client.user.id)) return;
```

큐 선언(상단): `const sharedQueues = new Map();` — enqueue 콜백 안에서:

```js
      let prompt = await withAttachments(message, basePrompt);
      let block = null;
      if (sharedCtx) { block = sharedCtx.queue.drain(sharedCtx.speaker, prompt); prompt = block; }
```

catch에서 `if (sharedCtx && block !== null) sharedCtx.queue.restore(block);`

- [ ] **Step 2:** v1의 단순 게이트 블록(`공유 채널에서는 호명…`) 제거 (classifyMessage가 대체)
- [ ] **Step 3:** `node --test` 51개 전부 PASS + `node --check src/index.mjs`
- [ ] **Step 4:** 제미나이 데몬 재시작 → [사용자] 수다 스모크: 호명 없이 잡담 2줄 → `제미나이 방금 무슨 얘기 했는지 요약해봐` → 잡담 내용이 요약에 반영되면 통과
- [ ] **Step 5:** 커밋 `feat: 공유 채널 컨텍스트 큐 — 헤드리스도 대화를 따라 듣는다`

### 마감

- [ ] SESSION.md 갱신(양 레포) + discord-multiagent 커밋
