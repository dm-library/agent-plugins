#!/bin/sh
# 检查脚本自己的回归测试：在临时副本里制造漂移，确认 check.sh 会失败、同步后恢复通过。
# 用法：sh scripts/test.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$root" ls-files -z | (cd "$root" && xargs -0 tar cf -) | (cd "$tmp" && tar xf -)
git -C "$tmp" init -q && git -C "$tmp" add -A
fail=0
expect() { # expect <pass|fail> <说明>
  if sh "$tmp/scripts/check.sh" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$1" ]; then echo "ok: $2"; else echo "FAIL: $2（期望 $1，实际 $got）" >&2; fail=1; fi
}

expect pass "干净的仓库通过检查"

echo "# 手改了一份副本" >> "$tmp/codex/bin/memory-hook"
expect fail "手改生成的副本会被发现"
sh "$tmp/scripts/sync-launcher.sh"
expect pass "重新生成后恢复通过"

echo "# 启动器改了，但忘了同步" >> "$tmp/launcher/memory-hook"
expect fail "改了启动器却没重新生成会被发现"
sh "$tmp/scripts/sync-launcher.sh"
expect pass "同步后通过"

[ "$fail" = 0 ] && echo "ok: scripts/test.sh passed" || exit 1
