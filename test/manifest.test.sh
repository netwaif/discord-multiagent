#!/usr/bin/env bash
# 오버레이 manifest 정합성 — src 실존·스키마·마커 존재를 오프라인 검증
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
python3 - <<'EOF'
import json, pathlib, sys
mf = json.load(open("install/overlay-manifest.json"))
assert mf["schema_version"] == 1, "schema_version"
for item in mf["overlay"] + mf["seeds"]:
    assert pathlib.Path(item["src"]).exists(), f"src 없음: {item['src']}"
for item in mf["overlay"]:
    assert item["mode"] in ("644", "755"), item
text = pathlib.Path(mf["claude_block"]["src"]).read_text()
assert "<!-- discord-multiagent:start -->" in text and "<!-- discord-multiagent:end -->" in text
print("manifest OK")
EOF
