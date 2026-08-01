# folder-bot 플러그인 (1단계) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "업무=폴더" 세션을 전용 디스코드 채널 봇으로 만드는 Claude Code 플러그인 `folder-bot`을 만들고, 협업 폴더 시험 봇으로 전 흐름(추가→페어링→기동→재시작)을 검증한다.

**Architecture:** 마켓플레이스 플러그인(netwaif/loadout과 동형 구조) 안의 스킬 `configure-bot`이 결정적 엔진 `generator/botctl.py`를 호출한다. botctl은 `~/.config/folder-bot/bots.json`을 정본으로 plist·스크립트·CLAUDE.md 마커 블록·페어링 파일을 멱등 생성한다. 기동 직렬화(bot-up)와 원격 재시작(bot-restart)은 하네스 레포에서 검증된 스크립트를 동봉한다.

**Tech Stack:** Python 3 표준 라이브러리만(loadout generator 관례), bash, tmux, launchd(macOS), pytest(테스트).

## Global Constraints

- 스펙 정본: `docs/superpowers/specs/2026-08-01-folder-bots-design.md` (하네스 레포)
- 새 레포 위치: `~/VSCodeWorkspace/folder-bot` (github.com/netwaif/folder-bot — 푸시는 3단계, 이 계획에서는 로컬 git만)
- 설정 정본: `~/.config/folder-bot/bots.json` + `~/.config/folder-bot/config.json`(webhook_url 선택)
- CLAUDE.md 마커: `<!-- store:discord-bot:start -->` / `<!-- store:discord-bot:end -->` (loadout 호환 이름)
- plist 라벨: `com.folder-bot.<이름>`, ProgramArguments = `[tmux, new-session, -d, -s, <세션>, <CMD 한 줄>]` — **bot-restart.sh의 plist 파서가 이 모양을 전제**하므로 변경 금지
- `launchctl bootout` 실행 금지(부팅 시 그 job이 tmux 서버를 띄웠으면 프로세스 그룹째 죽음 — 2026-07-31 결정). 파일 생성/삭제 + `tmux kill-session`만 사용
- 비파괴: SESSION.md 생성·수정 금지. CLAUDE.md는 마커 블록 append/제거만
- botctl은 `HOME` 환경변수 기준 경로만 사용(테스트에서 HOME을 tmpdir로 돌림)
- 모든 파일 쓰기는 멱등(재실행 시 같은 결과), 비밀 파일(.env)은 0600
- 커밋 메시지 끝에 항상:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` + `Claude-Session: https://claude.ai/code/session_01R2LjTDbUkvwbhTDSTP5wtz`

## File Structure

```
~/VSCodeWorkspace/folder-bot/
├── .claude-plugin/marketplace.json          # 마켓플레이스 정의 (loadout과 동형)
├── .gitignore                               # __pycache__, .pytest_cache
├── LICENSE                                  # MIT
├── README.md                                # 설치·사용·수동 단계(포탈) 안내
├── plugins/folder-bot/
│   ├── .claude-plugin/plugin.json
│   └── skills/configure-bot/
│       ├── SKILL.md                         # AI 지침 — 흐름 지휘·포탈 가이드
│       ├── generator/botctl.py              # 결정적 엔진 (add/pair/start/stop/remove/list/doctor)
│       └── assets/
│           ├── bot-up.sh                    # 하네스 정본 사본 (기동 직렬화)
│           ├── bot-restart.sh               # 하네스 정본 + folder-bot 웹훅 소스 패치
│           └── directive-block.md           # CLAUDE.md 마커 블록 본문 (정적 텍스트)
└── tests/test_botctl.py                     # pytest — HOME 격리 단위 테스트
```

---

### Task 1: 레포 스캐폴드 + 플러그인 메타

**Files:**
- Create: `~/VSCodeWorkspace/folder-bot/.claude-plugin/marketplace.json`
- Create: `~/VSCodeWorkspace/folder-bot/plugins/folder-bot/.claude-plugin/plugin.json`
- Create: `~/VSCodeWorkspace/folder-bot/.gitignore`, `LICENSE`(MIT, Copyright (c) 2026 netwaif), `README.md`(제목+한 줄 소개만, 본문은 Task 8 이후)

**Interfaces:**
- Produces: 마켓플레이스 name `folder-bot`, 플러그인 name `folder-bot` version `0.1.0`, source `./plugins/folder-bot` — Task 9의 `/plugin marketplace add`가 이 구조를 소비

- [ ] **Step 1: 디렉토리·메타 파일 생성**

marketplace.json:

```json
{
  "name": "folder-bot",
  "description": "폴더 전용 디스코드 채널 봇 — 업무 폴더의 Claude 세션을 전용 채널 봇으로 만들고, 부팅 자동 기동과 디스코드 원격 재시작(컨텍스트 리사이클)까지 설치한다",
  "owner": { "name": "netwaif", "email": "netwaif@users.noreply.github.com" },
  "plugins": [
    {
      "name": "folder-bot",
      "description": "\"이 폴더를 디스코드 봇으로 만들어줘\" — 봇 추가/제거/점검을 한 스킬로. 결정적 엔진(botctl)이 bots.json 정본에서 plist·기동 직렬화·원격 재시작·CLAUDE.md 지침 블록을 멱등 설치. 수동은 디스코드 포탈 단계뿐(스킬이 단계별 안내).",
      "version": "0.1.0",
      "source": "./plugins/folder-bot",
      "author": { "name": "netwaif" }
    }
  ]
}
```

plugin.json:

```json
{
  "name": "folder-bot",
  "version": "0.1.0",
  "description": "폴더 전용 디스코드 채널 봇 설치기. bots.json 정본으로 LaunchAgent·기동 직렬화(bot-up)·원격 재시작(bot-restart)·CLAUDE.md 지침 블록을 멱등 관리. 세션 이어가기(SESSION.md)와 짝을 이뤄 '세션 마감하고 재시작해' → '이어서하자' 컨텍스트 리사이클이 어느 폴더에서나 성립한다.",
  "author": { "name": "netwaif" }
}
```

- [ ] **Step 2: JSON 유효성 확인**

Run: `python3 -c "import json;[json.load(open(p)) for p in ['.claude-plugin/marketplace.json','plugins/folder-bot/.claude-plugin/plugin.json']];print('OK')"` (레포 루트에서)
Expected: `OK`

- [ ] **Step 3: git init + 첫 커밋**

```bash
cd ~/VSCodeWorkspace/folder-bot && git init && git add -A && git commit -m "chore: folder-bot 플러그인 스캐폴드"
```

---

### Task 2: botctl 설정 코어 (bots.json add/list/remove)

**Files:**
- Create: `plugins/folder-bot/skills/configure-bot/generator/botctl.py`
- Test: `tests/test_botctl.py`

**Interfaces:**
- Produces (이후 모든 태스크가 소비):
  - `CONFIG_DIR = Path(os.environ["HOME"]) / ".config/folder-bot"`
  - `load_bots() -> dict` / `save_bots(bots: dict) -> None` (bots.json, 들여쓰기 2, ensure_ascii=False)
  - `resolve_bot(name: str) -> dict` — 항목에 기본값 채워 반환: `engine="claude"`, `remote_control=session`, `state_dir=folder+"/.discord-state"`, `autostart=True`, `directive_block=True`, 경로는 `~` 확장(expanduser)
  - CLI: `botctl.py add --name N --folder F --session S [--remote-control R] [--no-remote-control] [--no-directive-block] [--no-autostart]` / `botctl.py list` / `botctl.py remove --name N [--keep-state]`
  - add는 **설정 기록 + 후속 설치 함수 호출**(후속 함수는 Task 3~5에서 채움 — 이 태스크에서는 `install_all(bot)`을 빈 스텁으로 두고 "다음 태스크에서 구현" 주석)

- [ ] **Step 1: 실패하는 테스트 작성** (`tests/test_botctl.py`)

```python
import json, os, subprocess, sys
from pathlib import Path

BOTCTL = Path(__file__).parent.parent / "plugins/folder-bot/skills/configure-bot/generator/botctl.py"

def run(env_home, *args):
    env = dict(os.environ, HOME=str(env_home))
    return subprocess.run([sys.executable, str(BOTCTL), *args],
                          capture_output=True, text=True, env=env)

def test_add_writes_bots_json(tmp_path):
    folder = tmp_path / "work" / "collab"; folder.mkdir(parents=True)
    r = run(tmp_path, "add", "--name", "collab", "--folder", str(folder),
            "--session", "collab-bot", "--no-autostart", "--no-directive-block")
    assert r.returncode == 0, r.stderr
    data = json.loads((tmp_path / ".config/folder-bot/bots.json").read_text())
    assert data["collab"]["session"] == "collab-bot"
    assert data["collab"]["folder"] == str(folder)

def test_add_is_idempotent(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    for _ in range(2):
        r = run(tmp_path, "add", "--name", "b", "--folder", str(folder),
                "--session", "b-bot", "--no-autostart", "--no-directive-block")
        assert r.returncode == 0
    data = json.loads((tmp_path / ".config/folder-bot/bots.json").read_text())
    assert list(data.keys()) == ["b"]

def test_remove_deletes_entry(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    run(tmp_path, "add", "--name", "b", "--folder", str(folder),
        "--session", "b-bot", "--no-autostart", "--no-directive-block")
    r = run(tmp_path, "remove", "--name", "b", "--keep-state")
    assert r.returncode == 0
    data = json.loads((tmp_path / ".config/folder-bot/bots.json").read_text())
    assert "b" not in data

def test_resolve_defaults(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    run(tmp_path, "add", "--name", "b", "--folder", str(folder),
        "--session", "b-bot", "--no-autostart", "--no-directive-block")
    r = run(tmp_path, "list")
    assert "b-bot" in r.stdout            # session
    assert ".discord-state" in r.stdout   # state_dir 기본값 표시
```

- [ ] **Step 2: 실패 확인**

Run: `cd ~/VSCodeWorkspace/folder-bot && python3 -m pytest tests/ -v`
Expected: FAIL (botctl.py 없음)

- [ ] **Step 3: botctl.py 최소 구현**

핵심 골격(전체를 이 모양으로 작성):

```python
#!/usr/bin/env python3
"""folder-bot 결정적 엔진 — bots.json 정본으로 봇을 멱등 설치·관리한다."""
import argparse, json, os, sys
from pathlib import Path

def home() -> Path: return Path(os.environ["HOME"])
def config_dir() -> Path: return home() / ".config/folder-bot"
def bots_path() -> Path: return config_dir() / "bots.json"

def load_bots() -> dict:
    if not bots_path().exists(): return {}
    return json.loads(bots_path().read_text())

def save_bots(bots: dict) -> None:
    config_dir().mkdir(parents=True, exist_ok=True)
    bots_path().write_text(json.dumps(bots, ensure_ascii=False, indent=2) + "\n")

def resolve_bot(name: str) -> dict:
    raw = load_bots().get(name)
    if raw is None: sys.exit(f"오류: 봇 '{name}' 없음 — botctl.py list 로 확인")
    b = dict(raw)
    b["name"] = name
    b.setdefault("engine", "claude")
    b.setdefault("remote_control", b["session"])
    b.setdefault("state_dir", str(Path(b["folder"]) / ".discord-state"))
    b.setdefault("autostart", True)
    b.setdefault("directive_block", True)
    for k in ("folder", "state_dir"): b[k] = str(Path(b[k]).expanduser())
    return b

def install_all(bot: dict) -> list[str]:
    """add 후 설치 일괄 수행 — Task 3~5에서 단계별로 채운다."""
    return []

def cmd_add(a) -> None:
    bots = load_bots()
    entry = {"engine": "claude", "folder": a.folder, "session": a.session}
    if a.no_remote_control: entry["remote_control"] = False
    elif a.remote_control: entry["remote_control"] = a.remote_control
    if a.no_directive_block: entry["directive_block"] = False
    if a.no_autostart: entry["autostart"] = False
    bots[a.name] = entry
    save_bots(bots)
    for line in install_all(resolve_bot(a.name)): print(line)
    print(f"등록됨: {a.name}")

def cmd_list(a) -> None:
    for name in load_bots():
        b = resolve_bot(name)
        print(f"{name}\t{b['engine']}\t{b['folder']}\t{b['session']}\t{b['state_dir']}")

def cmd_remove(a) -> None:
    bots = load_bots()
    if a.name in bots:
        del bots[a.name]; save_bots(bots)
    print(f"제거됨: {a.name}")   # plist·블록 제거는 Task 5·7에서 추가

def main() -> None:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    ap = sub.add_parser("add")
    ap.add_argument("--name", required=True); ap.add_argument("--folder", required=True)
    ap.add_argument("--session", required=True); ap.add_argument("--remote-control")
    ap.add_argument("--no-remote-control", action="store_true")
    ap.add_argument("--no-directive-block", action="store_true")
    ap.add_argument("--no-autostart", action="store_true")
    ap.set_defaults(fn=cmd_add)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    rp = sub.add_parser("remove")
    rp.add_argument("--name", required=True); rp.add_argument("--keep-state", action="store_true")
    rp.set_defaults(fn=cmd_remove)
    a = p.parse_args(); a.fn(a)

if __name__ == "__main__": main()
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m pytest tests/ -v`
Expected: 4 PASS

- [ ] **Step 5: 커밋**

```bash
git add -A && git commit -m "feat: botctl 설정 코어 — bots.json add/list/remove (HOME 격리 테스트)"
```

---

### Task 3: 스크립트 동봉 + ~/.local/bin 설치

**Files:**
- Create: `plugins/folder-bot/skills/configure-bot/assets/bot-up.sh` — `~/ai-folder/dev/discord-multiagent/scripts/bot-up.sh` **그대로 복사**
- Create: `plugins/folder-bot/skills/configure-bot/assets/bot-restart.sh` — 같은 곳에서 복사 후 **웹훅 소스 한 곳 패치**(아래)
- Modify: `generator/botctl.py` — `install_scripts()` 추가, `install_all`에서 호출
- Test: `tests/test_botctl.py` 추가

**Interfaces:**
- Consumes: Task 2의 `install_all(bot)`
- Produces: `install_scripts() -> list[str]` — assets의 두 스크립트를 `~/.local/bin/bot-up`, `~/.local/bin/bot-restart`로 복사(0755, 내용 같으면 건너뜀). `ASSETS = Path(__file__).parent.parent / "assets"`

- [ ] **Step 1: assets 복사 + bot-restart.sh 웹훅 패치**

복사 후 bot-restart.sh의 웹훅 결정부를 이렇게 교체(folder-bot config 우선, usage-coach 폴백 유지):

```bash
# 웹훅 (없으면 통지 생략) — folder-bot config → usage-coach 순
WEBHOOK="${BOT_RESTART_WEBHOOK:-}"
if [[ -z "$WEBHOOK" && -f "$HOME/.config/folder-bot/config.json" ]]; then
  WEBHOOK=$(sed -nE 's/.*"webhook_url" *: *"([^"]+)".*/\1/p' "$HOME/.config/folder-bot/config.json" | head -1)
fi
if [[ -z "$WEBHOOK" && -f "$HOME/.config/usage-coach/discord.json" ]]; then
  WEBHOOK=$(sed -nE 's/.*"webhook_url" *: *"([^"]+)".*/\1/p' "$HOME/.config/usage-coach/discord.json" | head -1)
fi
```

Run: `bash -n assets 두 파일` → Expected: 무출력(문법 OK)

- [ ] **Step 2: 실패하는 테스트 추가**

```python
def test_install_scripts_idempotent(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    r = run(tmp_path, "add", "--name", "b", "--folder", str(folder),
            "--session", "b-bot", "--no-autostart", "--no-directive-block")
    assert r.returncode == 0
    bin_dir = tmp_path / ".local/bin"
    assert (bin_dir / "bot-up").exists() and (bin_dir / "bot-restart").exists()
    assert os.access(bin_dir / "bot-up", os.X_OK)
    mtime = (bin_dir / "bot-up").stat().st_mtime
    run(tmp_path, "add", "--name", "b", "--folder", str(folder),
        "--session", "b-bot", "--no-autostart", "--no-directive-block")
    assert (bin_dir / "bot-up").stat().st_mtime == mtime  # 내용 동일 → 재쓰기 없음
```

- [ ] **Step 3: 실패 확인** — Run: `python3 -m pytest tests/ -v` → 새 테스트 FAIL

- [ ] **Step 4: install_scripts 구현**

```python
import shutil, stat
ASSETS = Path(__file__).resolve().parent.parent / "assets"

def install_scripts() -> list[str]:
    out = []
    bin_dir = home() / ".local/bin"; bin_dir.mkdir(parents=True, exist_ok=True)
    for src_name, dst_name in (("bot-up.sh", "bot-up"), ("bot-restart.sh", "bot-restart")):
        src, dst = ASSETS / src_name, bin_dir / dst_name
        if not (dst.exists() and dst.read_bytes() == src.read_bytes()):
            shutil.copyfile(src, dst)
            out.append(f"스크립트 설치: {dst}")
        dst.chmod(dst.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return out
```

`install_all`에서 `lines += install_scripts()` 호출.

- [ ] **Step 5: 통과 확인 + 커밋**

Run: `python3 -m pytest tests/ -v` → 전부 PASS

```bash
git add -A && git commit -m "feat: bot-up/bot-restart 동봉·~/.local/bin 멱등 설치 (+folder-bot 웹훅 소스)"
```

---

### Task 4: LaunchAgent plist 생성 (bot-restart 파서 호환)

**Files:**
- Modify: `generator/botctl.py` — `build_cmd(bot)`, `write_plist(bot)` 추가
- Test: `tests/test_botctl.py` 추가

**Interfaces:**
- Consumes: `resolve_bot`, `install_all`
- Produces:
  - `build_cmd(bot: dict) -> str` — `/bin/zsh -lc 'cd <folder>; export PATH="<현재 PATH의 & 이스케이프>"; export DISCORD_STATE_DIR=<state_dir>; exec <HOME>/.local/bin/bot-up -n <session> --remote-control <rc> --channels plugin:discord@claude-plugins-official'` (remote_control이 False면 `-n`·`--remote-control` 생략)
  - `write_plist(bot: dict) -> list[str]` — `~/Library/LaunchAgents/com.folder-bot.<name>.plist`, ProgramArguments = `[<tmux절대경로>, new-session, -d, -s, <session>, <CMD>]`, RunAtLoad true. autostart=False면 기존 plist 삭제만.
  - `find_tmux() -> str` — `shutil.which("tmux")` → `/opt/homebrew/bin/tmux` → `/usr/local/bin/tmux` 순, 없으면 exit "tmux 필요"

- [ ] **Step 1: 실패하는 테스트 추가** (bot-restart.sh 파서와 같은 로직으로 plist를 검증)

```python
import plistlib

def test_plist_shape_matches_bot_restart_parser(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    (tmp_path / "Library/LaunchAgents").mkdir(parents=True)
    r = run(tmp_path, "add", "--name", "b", "--folder", str(folder),
            "--session", "b-bot", "--no-directive-block")
    assert r.returncode == 0, r.stderr
    p = tmp_path / "Library/LaunchAgents/com.folder-bot.b.plist"
    a = plistlib.loads(p.read_bytes())["ProgramArguments"]
    # bot-restart.sh 파서 전제: '-s' 다음이 세션명, 마지막 인자가 CMD
    assert a[a.index("-s") + 1] == "b-bot" and "new-session" in a
    cmd = a[-1]
    assert f"cd {folder}" in cmd and "DISCORD_STATE_DIR=" in cmd
    assert "/.local/bin/bot-up" in cmd and "--channels plugin:discord@claude-plugins-official" in cmd
    assert "-n b-bot" in cmd and "--remote-control b-bot" in cmd

def test_no_autostart_removes_plist(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    (tmp_path / "Library/LaunchAgents").mkdir(parents=True)
    run(tmp_path, "add", "--name", "b", "--folder", str(folder), "--session", "b-bot",
        "--no-directive-block")
    run(tmp_path, "add", "--name", "b", "--folder", str(folder), "--session", "b-bot",
        "--no-directive-block", "--no-autostart")
    assert not (tmp_path / "Library/LaunchAgents/com.folder-bot.b.plist").exists()
```

- [ ] **Step 2: 실패 확인** — `python3 -m pytest tests/ -v` → 새 테스트 FAIL

- [ ] **Step 3: 구현**

```python
import plistlib, shutil as _shutil

def find_tmux() -> str:
    for c in (_shutil.which("tmux"), "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"):
        if c and Path(c).exists(): return c
    sys.exit("오류: tmux를 찾을 수 없음 — brew install tmux")

def build_cmd(bot: dict) -> str:
    path_esc = os.environ.get("PATH", "").replace("&", "&amp;")
    parts = [f"cd {bot['folder']}",
             f'export PATH="{path_esc}"',
             f"export DISCORD_STATE_DIR={bot['state_dir']}"]
    flags = ""
    if bot["remote_control"]:
        flags = f" -n {bot['session']} --remote-control {bot['remote_control']}"
    parts.append(f"exec {home()}/.local/bin/bot-up{flags}"
                 " --channels plugin:discord@claude-plugins-official")
    return "/bin/zsh -lc '" + "; ".join(parts) + "'"

def plist_path(bot: dict) -> Path:
    return home() / f"Library/LaunchAgents/com.folder-bot.{bot['name']}.plist"

def write_plist(bot: dict) -> list[str]:
    p = plist_path(bot)
    if not bot["autostart"]:
        if p.exists(): p.unlink(); return [f"plist 제거(autostart off): {p}"]
        return []
    p.parent.mkdir(parents=True, exist_ok=True)
    data = {"Label": f"com.folder-bot.{bot['name']}",
            "ProgramArguments": [find_tmux(), "new-session", "-d", "-s", bot["session"], build_cmd(bot)],
            "RunAtLoad": True}
    blob = plistlib.dumps(data)
    if not (p.exists() and p.read_bytes() == blob):
        p.write_bytes(blob); return [f"plist 생성: {p} (다음 부팅부터 자동 기동)"]
    return []
```

`install_all`에 `lines += write_plist(bot)` 추가.

argparse 확장 규칙(T2 패턴 그대로, 이후 태스크 공통): 새 서브커맨드는 `sub.add_parser("<이름>")`에
해당 태스크 Interfaces의 플래그를 그대로 등록한다 — T6 `pair`: `--name/--token/--user-id/--channel-id/--force`,
T7 `start`: `--name/--dry-run`, `stop`: `--name`, `doctor`: `--name`(선택).

- [ ] **Step 4: 통과 확인 + 커밋**

```bash
python3 -m pytest tests/ -v   # 전부 PASS
git add -A && git commit -m "feat: LaunchAgent plist 멱등 생성 — bot-restart 파서 호환 모양 고정"
```

---

### Task 5: CLAUDE.md 지침 블록 (마커 append/제거, 비파괴)

**Files:**
- Create: `plugins/folder-bot/skills/configure-bot/assets/directive-block.md`
- Modify: `generator/botctl.py` — `install_block(folder)`, `remove_block(folder)`, remove 서브커맨드 연동
- Test: `tests/test_botctl.py` 추가

**Interfaces:**
- Consumes: `install_all`, `cmd_remove`
- Produces: `MARK_START = "<!-- store:discord-bot:start -->"`, `MARK_END = "<!-- store:discord-bot:end -->"`; `install_block(folder: Path) -> list[str]`(이미 있으면 no-op), `remove_block(folder: Path) -> list[str]`(마커 범위만 제거)

- [ ] **Step 1: directive-block.md 본문 작성** (마커 제외 본문 — 정적 텍스트, 폴더별 값 없음)

```markdown
## 디스코드 봇 (전용 채널)

이 폴더의 세션은 discord 플러그인으로 **전용 채널**에 연결된 봇으로 뜰 수 있다.
채널에서 온 메시지는 이 세션 소관이다 — reply 도구로 답하고, 긴 작업은 진행 상황을
중간에 편집·게시한다. 전송하지 않은 텍스트는 상대에게 보이지 않는다.

### 세션 재시작 (컨텍스트가 찼을 때)
디스코드에서 사용자가 재시작을 요청하면("세션 마감하고 재시작해" 류):
1. 이 폴더의 세션 마감 규율대로 기록을 갱신한다(SESSION.md가 있으면 그 규칙, 있는
   작업 기록 프로토콜이 따로 있으면 그쪽 정본).
2. reply로 짧게 답장: 재시작 들어감 + 성패는 웹훅 알림(설정된 경우) + 재기동 후
   "이어서하자"로 재정박.
3. `bot-restart $(tmux display-message -p '#S')` 실행 — 즉시 반환되고 몇 초 뒤
   이 세션이 교체된다(재시작 작업은 tmux 서버에 위탁되므로 완주한다).

### 주의
- 이 폴더에서 로컬 터미널 세션과 봇 세션을 병행하면 같은 SESSION.md를 공유한다 —
  **마감 주체는 한 세션만**. 양쪽에서 마감하면 늦게 쓴 쪽이 이긴다.
- 채널 밖(다른 채널·DM)의 지시는 처리하지 않는다.
```

- [ ] **Step 2: 실패하는 테스트 추가**

```python
def test_directive_block_nondestructive(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    original = "# 기존 내용\n\n소중한 규칙.\n"
    (folder / "CLAUDE.md").write_text(original)
    (folder / "SESSION.md").write_text("세션 기록\n")
    run(tmp_path, "add", "--name", "b", "--folder", str(folder),
        "--session", "b-bot", "--no-autostart")
    text = (folder / "CLAUDE.md").read_text()
    assert original in text and "<!-- store:discord-bot:start -->" in text
    assert (folder / "SESSION.md").read_text() == "세션 기록\n"  # SESSION.md 무접촉
    run(tmp_path, "add", "--name", "b", "--folder", str(folder),
        "--session", "b-bot", "--no-autostart")
    assert text == (folder / "CLAUDE.md").read_text()            # 멱등
    run(tmp_path, "remove", "--name", "b", "--keep-state")
    assert (folder / "CLAUDE.md").read_text() == original        # 블록 외 diff 0
```

- [ ] **Step 3: 실패 확인** — `python3 -m pytest tests/ -v` → FAIL

- [ ] **Step 4: 구현**

```python
MARK_START = "<!-- store:discord-bot:start -->"
MARK_END = "<!-- store:discord-bot:end -->"

def install_block(folder: Path) -> list[str]:
    md = folder / "CLAUDE.md"
    body = (ASSETS / "directive-block.md").read_text()
    cur = md.read_text() if md.exists() else ""
    if MARK_START in cur: return []
    block = f"\n{MARK_START}\n{body.rstrip()}\n{MARK_END}\n"
    md.write_text(cur + block)
    return [f"CLAUDE.md 지침 블록 설치: {md}"]

def remove_block(folder: Path) -> list[str]:
    md = folder / "CLAUDE.md"
    if not md.exists(): return []
    cur = md.read_text()
    if MARK_START not in cur or MARK_END not in cur: return []
    pre, rest = cur.split(MARK_START, 1)
    _, post = rest.split(MARK_END, 1)
    md.write_text(pre.rstrip("\n") + ("\n" if pre.strip() else "") + post.lstrip("\n"))
    return [f"CLAUDE.md 지침 블록 제거: {md}"]
```

주의: remove 결과가 정확히 원문과 같도록 append 시 붙인 개행을 대칭으로 걷어낸다 —
위 테스트(`== original`)가 검증한다. `install_all`에서 `bot["directive_block"]`이면 호출.
`cmd_remove`는 **엔트리 삭제 전에 `resolve_bot(a.name)`으로 경로를 확보**한 뒤
bots.json에서 지우고, `remove_block(Path(bot["folder"]))` + plist 삭제
(`plist_path(bot)` 존재 시 unlink)를 수행한다(`--keep-state`면 state_dir은 남긴다 —
state 삭제는 어떤 경우에도 하지 않고 경로만 안내 출력).

- [ ] **Step 5: 통과 확인 + 커밋**

```bash
python3 -m pytest tests/ -v
git add -A && git commit -m "feat: CLAUDE.md 지침 블록 멱등 설치/제거 — 비파괴(diff 0) 보장"
```

---

### Task 6: pair (토큰·접근 파일 생성)

**Files:**
- Modify: `generator/botctl.py` — `pair` 서브커맨드
- Test: `tests/test_botctl.py` 추가

**Interfaces:**
- Consumes: `resolve_bot`
- Produces: CLI `botctl.py pair --name N --token T --user-id U --channel-id C` →
  `<state_dir>/.env`(`DISCORD_BOT_TOKEN=T`, 0600) + `<state_dir>/access.json`
  (실측 스키마: `{"dmPolicy":"allowlist","allowFrom":[U],"groups":{C:{"requireMention":false,"allowFrom":[U]}},"pending":{}}`) + `<state_dir>/inbox/` 디렉토리

- [ ] **Step 1: 실패하는 테스트 추가**

```python
def test_pair_writes_state(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    run(tmp_path, "add", "--name", "b", "--folder", str(folder),
        "--session", "b-bot", "--no-autostart", "--no-directive-block")
    r = run(tmp_path, "pair", "--name", "b", "--token", "tok123",
            "--user-id", "111", "--channel-id", "222")
    assert r.returncode == 0, r.stderr
    st = folder / ".discord-state"
    assert (st / ".env").read_text() == "DISCORD_BOT_TOKEN=tok123\n"
    assert oct((st / ".env").stat().st_mode)[-3:] == "600"
    acc = json.loads((st / "access.json").read_text())
    assert acc["dmPolicy"] == "allowlist" and acc["allowFrom"] == ["111"]
    assert acc["groups"]["222"] == {"requireMention": False, "allowFrom": ["111"]}
    assert (st / "inbox").is_dir()

def test_pair_refuses_overwrite(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    run(tmp_path, "add", "--name", "b", "--folder", str(folder),
        "--session", "b-bot", "--no-autostart", "--no-directive-block")
    run(tmp_path, "pair", "--name", "b", "--token", "tok1", "--user-id", "1", "--channel-id", "2")
    r = run(tmp_path, "pair", "--name", "b", "--token", "tok2", "--user-id", "1", "--channel-id", "2")
    assert r.returncode != 0            # 기존 페어링 보호 — --force 없이 덮지 않음
    assert "tok1" in (folder / ".discord-state/.env").read_text()
```

- [ ] **Step 2: 실패 확인** — `python3 -m pytest tests/ -v` → FAIL

- [ ] **Step 3: 구현** (`--force`로만 덮어쓰기 허용)

```python
def cmd_pair(a) -> None:
    bot = resolve_bot(a.name)
    st = Path(bot["state_dir"])
    env = st / ".env"
    if env.exists() and not a.force:
        sys.exit(f"오류: {env} 이미 존재 — 덮어쓰려면 --force")
    st.mkdir(parents=True, exist_ok=True); (st / "inbox").mkdir(exist_ok=True)
    env.write_text(f"DISCORD_BOT_TOKEN={a.token}\n"); env.chmod(0o600)
    access = {"dmPolicy": "allowlist", "allowFrom": [a.user_id],
              "groups": {a.channel_id: {"requireMention": False, "allowFrom": [a.user_id]}},
              "pending": {}}
    (st / "access.json").write_text(json.dumps(access, ensure_ascii=False, indent=2) + "\n")
    print(f"페어링 완료: {st}")
```

- [ ] **Step 4: 통과 확인 + 커밋**

```bash
python3 -m pytest tests/ -v
git add -A && git commit -m "feat: pair — 토큰(.env 0600)·access.json(allowlist)·inbox 생성, 기존 페어링 보호"
```

---

### Task 7: start/stop + doctor

**Files:**
- Modify: `generator/botctl.py` — `start`/`stop`/`doctor` 서브커맨드
- Test: `tests/test_botctl.py` 추가

**Interfaces:**
- Consumes: `resolve_bot`, `build_cmd`, `find_tmux`, `plist_path`, `MARK_START`
- Produces:
  - `start --name N [--dry-run]` — `tmux has-session -t <session>` 확인 후 없으면 `tmux new-session -d -s <session> <build_cmd(bot)>`. `--dry-run`은 실행할 명령만 출력(테스트용)
  - `stop --name N` — `tmux kill-session -t <session>` (launchctl bootout 금지 — Global Constraints)
  - `doctor [--name N]` — 읽기 전용: 봇마다 bots.json ↔ plist 존재·내용 일치 ↔ CLAUDE.md 블록 유무(directive_block 설정과 대조) ↔ state_dir 페어링 유무 ↔ tmux 세션 생존을 `[OK]/[WARN]/[FAIL]`로 보고, FAIL 있으면 exit 1

- [ ] **Step 1: 실패하는 테스트 추가**

```python
def test_start_dry_run_prints_command(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    run(tmp_path, "add", "--name", "b", "--folder", str(folder),
        "--session", "b-bot", "--no-autostart", "--no-directive-block")
    r = run(tmp_path, "start", "--name", "b", "--dry-run")
    assert r.returncode == 0
    assert "new-session" in r.stdout and "b-bot" in r.stdout and "bot-up" in r.stdout

def test_doctor_reports_missing_pairing(tmp_path):
    folder = tmp_path / "w"; folder.mkdir()
    (tmp_path / "Library/LaunchAgents").mkdir(parents=True)
    run(tmp_path, "add", "--name", "b", "--folder", str(folder), "--session", "b-bot",
        "--no-directive-block")
    r = run(tmp_path, "doctor")
    assert "페어링" in r.stdout and "[WARN]" in r.stdout   # .env 없음 → WARN
```

- [ ] **Step 2: 실패 확인** — `python3 -m pytest tests/ -v` → FAIL

- [ ] **Step 3: 구현**

```python
import subprocess

def cmd_start(a) -> None:
    bot = resolve_bot(a.name); tmux = find_tmux(); cmd = build_cmd(bot)
    argv = [tmux, "new-session", "-d", "-s", bot["session"], cmd]
    if a.dry_run: print(" ".join(argv)); return
    if subprocess.run([tmux, "has-session", "-t", bot["session"]],
                      capture_output=True).returncode == 0:
        print(f"이미 실행 중: {bot['session']}"); return
    subprocess.run(argv, check=True)
    print(f"기동: {bot['session']} — 연결 판정은 MCP 로그(bot-up이 감시)")

def cmd_stop(a) -> None:
    bot = resolve_bot(a.name)
    subprocess.run([find_tmux(), "kill-session", "-t", bot["session"]], capture_output=True)
    print(f"중지: {bot['session']}")

def cmd_doctor(a) -> None:
    fails = 0
    names = [a.name] if a.name else list(load_bots())
    for name in names:
        b = resolve_bot(name)
        def rep(level, msg):
            nonlocal fails
            if level == "FAIL": fails += 1
            print(f"[{level}] {name}: {msg}")
        p = plist_path(b)
        if b["autostart"] and not p.exists(): rep("FAIL", f"plist 없음: {p}")
        env = Path(b["state_dir"]) / ".env"
        if not env.exists(): rep("WARN", f"페어링 안 됨(.env 없음): {env}")
        md = Path(b["folder"]) / "CLAUDE.md"
        has_block = md.exists() and MARK_START in md.read_text()
        if b["directive_block"] and not has_block: rep("WARN", "CLAUDE.md 지침 블록 없음")
        alive = subprocess.run([find_tmux(), "has-session", "-t", b["session"]],
                               capture_output=True).returncode == 0
        rep("OK" if alive else "WARN", f"tmux 세션 {'생존' if alive else '없음'}: {b['session']}")
    sys.exit(1 if fails else 0)
```

- [ ] **Step 4: 통과 확인 + 커밋**

```bash
python3 -m pytest tests/ -v
git add -A && git commit -m "feat: start/stop/doctor — bootout 없는 기동·중지, 읽기 전용 진단"
```

---

### Task 8: SKILL.md (AI 지침 — 흐름 지휘 + 포탈 가이드)

**Files:**
- Create: `plugins/folder-bot/skills/configure-bot/SKILL.md`
- Modify: `README.md` — 설치·사용·수동 단계 본문

**Interfaces:**
- Consumes: botctl CLI 전체(Task 2~7의 서브커맨드·플래그 정확히 그 이름으로)
- Produces: 스킬 트리거 문구(“이 폴더를 디스코드 봇으로 만들어줘”, “폴더 봇 추가/제거/점검”, “/configure-bot”)

- [ ] **Step 1: SKILL.md 작성** — frontmatter(name: configure-bot, description: 트리거 포함) + 본문에 다음을 그대로 반영:

1. **전제 점검**: macOS인지(`uname`), discord 공식 플러그인 설치돼 있는지(`~/.claude/plugins/cache/claude-plugins-official/discord/` 존재), tmux 있는지. 미비하면 설치 방법 안내 후 중단.
2. **질문(한 번에)**: 봇 이름(영문 소문자) / 폴더(기본 = 현재 폴더) / tmux 세션명(기본 = `<이름>-bot`) / 리모트 컨트롤(기본 = 켬).
3. `python3 "<이 스킬 폴더>/generator/botctl.py" add --name … --folder … --session …` 실행, 출력 그대로 보여주기.
4. **포탈 수동 단계 안내** (순서대로, 사용자가 끝냈다고 할 때까지 대기):
   - https://discord.com/developers/applications → New Application → Bot 탭에서 토큰 발급(Reset Token)
   - Privileged Gateway Intents에서 **MESSAGE CONTENT INTENT** 켜기
   - OAuth2 → URL Generator: scope `bot`, 권한 View Channels/Send Messages/Read Message History/Embed Links/Attach Files → 생성된 URL로 서버에 초대
   - 서버에 전용 텍스트 채널 생성 → 채널 ID 복사(개발자 모드) + 본인 사용자 ID 복사
5. **페어링**: 토큰·사용자 ID·채널 ID를 받아 `botctl.py pair --name … --token … --user-id … --channel-id …`. 토큰은 화면에 다시 출력하지 않는다.
6. **기동·판정**: `botctl.py start --name …` 후 그 봇 MCP 로그
   (`~/Library/Caches/claude-cli-nodejs/<폴더 경로의 / 와 . 을 - 로 바꾼 이름>/mcp-logs-plugin-discord-discord/` 최신 jsonl)에서 `Successfully connected` / `Connection failed` 판정을 확인해 결과 보고. 실패면 원인 후보(토큰 오입력·인텐트 미설정·초대 안 됨) 안내.
7. **마무리 안내**: 채널에서 인사 한 번 → 컨텍스트 차면 "세션 마감하고 재시작해" → 웹훅 알림(선택: `~/.config/folder-bot/config.json`의 `webhook_url`) → "이어서하자". 제거는 `botctl.py remove --name …`(state 보존은 `--keep-state`), 점검은 `botctl.py doctor`.
8. **비파괴 원칙 명시**: SESSION.md는 절대 만들거나 고치지 않는다. CLAUDE.md는 마커 블록만.

- [ ] **Step 2: README.md 본문** — 위 흐름의 사용자 관점 요약(플러그인 설치 명령, 스킬 한 번 실행, 수동 단계 목록, 재시작 사용법, macOS만 검증 명시).

- [ ] **Step 3: 정합성 검사**

Run: `grep -o 'botctl.py [a-z]*' plugins/folder-bot/skills/configure-bot/SKILL.md | sort -u`
Expected: add/doctor/pair/remove/start 만 등장(오타·없는 서브커맨드 없음)

- [ ] **Step 4: 커밋**

```bash
git add -A && git commit -m "docs: configure-bot SKILL.md(흐름 지휘·포탈 가이드) + README"
```

---

### Task 9: 로컬 마켓플레이스 설치 + 협업 폴더 시험 봇 E2E

**Files:**
- Modify: 없음(검증 태스크) — 발견된 결함은 해당 태스크 파일로 돌아가 수정

**Interfaces:**
- Consumes: 플러그인 전체, `~/ai-folder/collab` 폴더(실존 — 기존 CLAUDE.md·SESSION.md 보존 검증 대상)

- [ ] **Step 1: 로컬 마켓플레이스 등록** — `claude /plugin marketplace add ~/VSCodeWorkspace/folder-bot` 상당(대화형이면 사용자 안내). 설치 확인: 스킬 목록에 `folder-bot:configure-bot`.
- [ ] **Step 2: 사전 백업** — `cp ~/ai-folder/collab/CLAUDE.md ~/ai-folder/collab/SESSION.md <scratchpad>/collab-bak/` (실존 파일만).
- [ ] **Step 3: 사용자 게이트(AskUserQuestion)** — 시험 봇용 디스코드 봇 계정·토큰·전용 채널 준비를 요청(포탈 단계는 SKILL.md 가이드 그대로). 사용자가 폰만 있는 상황이면 이 태스크를 보류하고 나머지를 먼저 마친다.
- [ ] **Step 4: E2E 실행** — collab 폴더에서 configure-bot 흐름 전체: add → pair → start → MCP 로그 `Successfully connected` 확인 → 채널에서 인사 왕복.
- [ ] **Step 5: 재시작 흐름 검증** — 채널에서 "세션 마감하고 재시작해" → `~/.claude/logs/bot-restart.log` 판정 ✅ + (웹훅 설정 시) 알림 도착 → "이어서하자" 재정박 확인.
- [ ] **Step 6: 비파괴 검증** — `diff` 백업 대비 CLAUDE.md는 마커 블록 추가분만, SESSION.md는 diff 0.
- [ ] **Step 7: doctor 무결** — `botctl.py doctor` exit 0.
- [ ] **Step 8: 결과 요약 커밋** (플러그인 레포에 결함 수정이 있었으면 함께)

```bash
git add -A && git commit -m "test: 협업 폴더 시험 봇 E2E 통과 (연결·재시작·비파괴)"
```

---

### Task 10: 하네스 정본 동기화 (bot-restart 웹훅 소스)

**Files:**
- Modify: `~/ai-folder/dev/discord-multiagent/scripts/bot-restart.sh` — Task 3에서 assets 사본에 넣은 folder-bot config 웹훅 소스 블록을 정본에도 동일 적용

**Interfaces:**
- Consumes: Task 3의 웹훅 결정부 코드(동일 텍스트)

- [ ] **Step 1: 정본 패치** — Task 3 Step 1의 웹훅 결정부로 교체(assets 사본과 diff 0이 되게, 단 정본은 `.sh` 이름 유지)
- [ ] **Step 2: 검증** — `bash -n` + `diff <(tail -n +2 정본) <(tail -n +2 사본)` 로 본문 일치 확인(셔뱅 제외 동일)
- [ ] **Step 3: 하네스 레포 커밋** (푸시는 사용자 릴리즈 결정 후)

```bash
cd ~/ai-folder/dev/discord-multiagent && git add scripts/bot-restart.sh && git commit -m "feat: bot-restart 웹훅 소스에 ~/.config/folder-bot/config.json 추가 (플러그인 동봉본과 동기화)"
```
