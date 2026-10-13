#!/bin/sh
# 插件仓库的静态检查：JSON 合法、启动器副本是 launcher/ 的生成结果、版本号一致、
# MCP 配置不会把凭据交给未核对的地址。
# 用法：sh scripts/check.sh   （需要 python3）
set -eu
cd "$(dirname "$0")/.."
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

for f in $(git ls-files '*.json'); do
  python3 -m json.tool "$f" >/dev/null 2>&1 || err "$f 不是合法 JSON"
done

sh -n launcher/memory-hook || err "launcher/memory-hook 语法错误"
sh scripts/sync-launcher.sh --check || err "启动器副本没有从 launcher/memory-hook 重新生成"

v=$(cat claude-code/bin/VERSION)
for f in codex/bin/VERSION cursor/bin/VERSION; do
  [ "$(cat "$f")" = "$v" ] || err "$f 版本 $(cat "$f") != $v"
done
for f in claude-code/.claude-plugin/plugin.json codex/.codex-plugin/plugin.json cursor/.cursor-plugin/plugin.json; do
  pv=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$f")
  [ "$pv" = "$v" ] || err "$f 版本 $pv != $v"
done

python3 - <<'PY' || fail=1
import json, re, sys
ok = True
def bad(msg):
    global ok
    print("FAIL:", msg, file=sys.stderr); ok = False

codex = json.load(open("codex/.mcp.json"))["mcpServers"]["deep-memory"]
if f"mcp-headers --url {codex['url']}" not in codex["http_headers_helper"]:
    bad("codex: http_headers_helper 必须把 url 交给 mcp-headers --url 核对")

claude = json.load(open("claude-code/.mcp.json"))["mcpServers"]["deep-memory"]
if "mcp-headers" not in claude.get("headersHelper", ""):
    bad("claude-code: 必须用 headersHelper（mcp-headers 按 CLAUDE_CODE_MCP_SERVER_URL 核对）")

for path in ["claude-code/.mcp.json", "codex/.mcp.json", "cursor/mcp.json"]:
    text = open(path).read()
    if re.search(r"dm_pat_[A-Za-z0-9]", text):
        bad(f"{path}: 不得包含明文 PAT")
sys.exit(0 if ok else 1)
PY

[ "$fail" = 0 ] && echo "ok: plugin checks passed" || exit 1
