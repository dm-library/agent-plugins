#!/bin/sh
# 证明 Release 资产检查不是永远绿：夹具里资产齐全则通过，缺资产则失败。不访问网络。
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1" >&2; fail=1; }

assets='memory-hook-aarch64-apple-darwin
memory-hook-aarch64-apple-darwin.sha256
memory-hook-aarch64-unknown-linux-gnu
memory-hook-aarch64-unknown-linux-gnu.sha256
memory-hook-x86_64-apple-darwin
memory-hook-x86_64-apple-darwin.sha256
memory-hook-x86_64-unknown-linux-gnu
memory-hook-x86_64-unknown-linux-gnu.sha256'

printf '%s\n' "$assets" > "$tmp/complete"
printf '%s\n' "$assets" "memory-hook-extra" > "$tmp/superset"
printf '%s\n' "$assets" | sed '/memory-hook-x86_64-unknown-linux-gnu.sha256/d' > "$tmp/missing-sha"
printf '%s\n' 'memory-hook-x86_64-unknown-linux-gnu.sha256.extra' > "$tmp/prefix-only"
: > "$tmp/empty"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<EOF
#!/bin/sh
echo called >> "$tmp/curl-called"
exit 99
EOF
chmod +x "$tmp/bin/curl"

run() { # expect pass|fail, then args
  expect=$1
  shift
  if PATH="$tmp/bin:/usr/bin:/bin" sh "$root/scripts/check-release-assets.sh" "$@" >/dev/null 2>"$tmp/err"; then
    got=pass
  else
    got=fail
  fi
  if [ "$got" = "$expect" ]; then
    ok "$expect $(printf '%s ' "$@")"
  else
    bad "期望 $expect，实际 $got：$*"
    cat "$tmp/err" >&2 || true
  fi
}

run pass --assets-file "$tmp/complete" --version 0.4.0
run pass --assets-file "$tmp/superset" --version 0.0.0
run fail --assets-file "$tmp/missing-sha" --version 0.4.1
run fail --assets-file "$tmp/prefix-only" --version 0.4.0
run fail --assets-file "$tmp/empty" --version 0.4.0
run fail --assets-file "$tmp/does-not-exist" --version 0.4.0

if [ -e "$tmp/curl-called" ]; then
  bad "夹具模式访问了网络（调用了 curl）"
else
  ok "夹具模式没有调用 curl"
fi

[ "$fail" = 0 ] && echo "ok: scripts/test-release-assets.sh passed" || exit 1
