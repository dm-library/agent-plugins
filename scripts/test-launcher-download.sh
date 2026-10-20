#!/bin/sh
# 启动器下载失败必须报错并以非 0 退出。覆盖 hook 子命令（旧实现会静默 exit 0）
# 以及 404、非 2xx、空正文、校验失败。成功路径要真的 exec 下载到的文件。
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1" >&2; fail=1; }

work=$tmp/plugin
mkdir -p "$work/bin" "$tmp/data" "$tmp/home"
cp "$root/launcher/memory-hook" "$work/memory-hook"
printf '%s\n' '0.4.1' > "$work/VERSION"
chmod +x "$work/memory-hook"
printf '%s\n' '#!/bin/sh' 'echo "ran $*"' > "$tmp/body"

cat > "$work/bin/curl" <<'EOF'
#!/bin/sh
out=
url=
while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      out=$2
      shift 2
      ;;
    --write-out|--retry)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done
mode=${DM_FAKE_CURL_MODE:-404}
case "$url" in
  *.sha256) kind=sha ;;
  *) kind=bin ;;
esac
: > "${out:-/dev/null}"
if [ "$kind" = sha ]; then
  case "$mode" in
    ok)
      cat "$DM_FAKE_SHA_FILE" > "$out"
      printf '%s' 200
      ;;
    badsha)
      printf '%s\n' '0000000000000000000000000000000000000000000000000000000000000000' > "$out"
      printf '%s' 200
      ;;
    *)
      printf '%s' 404
      ;;
  esac
  exit 0
fi
case "$mode" in
  404) printf '%s' 404 ;;
  500) printf '%s' 500 ;;
  empty) printf '%s' 200 ;;
  ok|badsha|sha404)
    cp "$DM_FAKE_BODY" "$out"
    printf '%s' 200
    ;;
  *)
    echo "fake curl: unknown mode $mode" >&2
    printf '%s' 500
    ;;
esac
EOF

cat > "$work/bin/gh" <<'EOF'
#!/bin/sh
if [ "${DM_FAKE_GH_MODE:-fail}" != ok ]; then
  echo "fake gh: fail" >&2
  exit 1
fi
pattern=
output=
while [ $# -gt 0 ]; do
  case "$1" in
    --pattern)
      pattern=$2
      shift 2
      ;;
    --output)
      output=$2
      shift 2
      ;;
    --repo)
      shift 2
      ;;
    --clobber)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
case "$pattern" in
  *.sha256)
    if [ "$output" = - ]; then
      cat "$DM_FAKE_SHA_FILE"
    else
      cp "$DM_FAKE_SHA_FILE" "$output"
    fi
    ;;
  *)
    cp "$DM_FAKE_BODY" "$output"
    ;;
esac
EOF
chmod +x "$work/bin/curl" "$work/bin/gh"

sha=$(sha256sum "$tmp/body" | awk '{print $1}')
printf '%s\n' "$sha" > "$tmp/sha"
export DM_FAKE_BODY="$tmp/body" DM_FAKE_SHA_FILE="$tmp/sha"
export XDG_DATA_HOME="$tmp/data" HOME="$tmp/home"
export DM_PLUGIN_REPO=fixture.invalid/not-a-repo
export PATH="$work/bin:/usr/bin:/bin"
cached=$XDG_DATA_HOME/deep-memory/bin/0.4.1/memory-hook

run() { # mode ghmode args...
  mode=$1
  ghmode=$2
  shift 2
  DM_FAKE_CURL_MODE=$mode DM_FAKE_GH_MODE=$ghmode \
    "$work/memory-hook" "$@" >"$tmp/out" 2>"$tmp/err" && rc=0 || rc=$?
}

expect_fail() { # label mode command needle
  label=$1
  mode=$2
  cmd=$3
  needle=$4
  rm -rf "$XDG_DATA_HOME"
  run "$mode" fail "$cmd" --agent cursor
  if [ "$rc" -eq 0 ]; then
    bad "$label 以 0 退出（静默空跑）"
    return
  fi
  if ! grep -F -q "$needle" "$tmp/err"; then
    bad "$label 的报错里没有「$needle」"
    cat "$tmp/err" >&2 || true
    return
  fi
  if [ -x "$cached" ]; then
    bad "$label 失败后仍留下了可执行缓存"
    return
  fi
  ok "$label"
}

expect_fail "session-start HTTP 404" 404 session-start "HTTP 404"
expect_fail "stop HTTP 500" 500 stop "HTTP 500"
expect_fail "session-end 空正文" empty session-end "响应正文为空"
expect_fail "status 校验失败" badsha status "下载校验失败"
expect_fail "session-start 缺少 sha256" sha404 session-start "下载校验失败"

rm -rf "$XDG_DATA_HOME"
run ok fail session-start --agent cursor
if [ "$rc" -ne 0 ]; then
  bad "资产和校验都正确时 session-start 仍失败"
  cat "$tmp/err" >&2 || true
elif [ "$(cat "$tmp/out")" != "ran session-start --agent cursor" ]; then
  bad "成功下载后没有 exec 二进制，输出为：$(cat "$tmp/out")"
elif [ ! -x "$cached" ]; then
  bad "成功下载后没有留下可执行缓存"
else
  ok "session-start 下载成功并执行"
fi

run 404 fail session-start --agent cursor
if [ "$rc" -ne 0 ] || [ "$(cat "$tmp/out")" != "ran session-start --agent cursor" ]; then
  bad "缓存命中后不应再次因为 404 失败"
else
  ok "已缓存的二进制不再下载"
fi

rm -rf "$XDG_DATA_HOME"
run 404 ok stop --agent cursor
if [ "$rc" -ne 0 ] || [ "$(cat "$tmp/out")" != "ran stop --agent cursor" ]; then
  bad "curl 404 时 gh 回退没有装上二进制"
  echo "rc=$rc" >&2
  cat "$tmp/err" >&2 || true
else
  ok "curl 404 时 gh 回退可以完成安装"
fi

[ "$fail" = 0 ] && echo "ok: scripts/test-launcher-download.sh passed" || exit 1
