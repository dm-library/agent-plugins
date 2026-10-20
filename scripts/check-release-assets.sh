#!/bin/sh
# 插件 VERSION 必须在启动器实际下载的 Release 里有对应的 memory-hook 资产。
# 启动器默认从 dm-library/agent-plugins 下载（见 launcher/memory-hook 的 DM_PLUGIN_REPO）。
# 四个平台的二进制和各自的 sha256 都要在，且资产大小不能为 0。缺任何一个，本脚本以非 0 退出。
#
# 夹具（不访问网络）：
#   sh scripts/check-release-assets.sh --assets-file <文件> [--version <版本>]
# 文件一行一个资产名。有全部必需资产则通过，少了则失败。
#
# 实况：
#   sh scripts/check-release-assets.sh [--version <版本>] [--repo owner/name]
# 默认版本读 claude-code/bin/VERSION，默认仓库是 ${DM_PLUGIN_REPO:-dm-library/agent-plugins}。
set -eu
cd "$(dirname "$0")/.."

assets_file=
version=
repo=${DM_PLUGIN_REPO:-dm-library/agent-plugins}

while [ $# -gt 0 ]; do
  case "$1" in
    --assets-file)
      assets_file=$2
      shift 2
      ;;
    --version)
      version=$2
      shift 2
      ;;
    --repo)
      repo=$2
      shift 2
      ;;
    *)
      echo "FAIL: 未知参数 $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$version" ]; then
  version=$(tr -d '[:space:]' < claude-code/bin/VERSION)
fi
if [ -z "$version" ]; then
  echo "FAIL: VERSION 为空" >&2
  exit 1
fi

required='memory-hook-aarch64-apple-darwin
memory-hook-aarch64-apple-darwin.sha256
memory-hook-aarch64-unknown-linux-gnu
memory-hook-aarch64-unknown-linux-gnu.sha256
memory-hook-x86_64-apple-darwin
memory-hook-x86_64-apple-darwin.sha256
memory-hook-x86_64-unknown-linux-gnu
memory-hook-x86_64-unknown-linux-gnu.sha256'

list=
body=
cleanup() {
  [ -z "$list" ] || rm -f "$list"
  [ -z "$body" ] || rm -f "$body"
}
trap cleanup EXIT

if [ -n "$assets_file" ]; then
  if [ ! -f "$assets_file" ]; then
    echo "FAIL: 资产夹具不存在：$assets_file" >&2
    exit 1
  fi
  names=$assets_file
else
  body=$(mktemp)
  list=$(mktemp)
  names=$list
  set -- curl -sS -L --retry 2 --output "$body" --write-out '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    set -- "$@" -H "Authorization: Bearer ${GITHUB_TOKEN}"
  elif [ -n "${GH_TOKEN:-}" ]; then
    set -- "$@" -H "Authorization: Bearer ${GH_TOKEN}"
  fi
  set -- "$@" "https://api.github.com/repos/$repo/releases/tags/v$version"
  code=$("$@") || code=${code:-000}
  code=$(printf '%s' "$code" | tr -cd '0-9')
  [ -n "$code" ] || code=000
  python3 - "$code" "$body" "$version" "$repo" "$names" <<'PY'
import json, sys
code, path, version, repo, dest = sys.argv[1:]
raw = open(path, encoding="utf-8").read()
try:
    data = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError:
    data = {}
assets = data.get("assets") if isinstance(data, dict) else None
tag = data.get("tag_name") if isinstance(data, dict) else None
if code != "200" or not isinstance(assets, list) or tag != "v" + version:
    message = data.get("message") if isinstance(data, dict) else ""
    extra = f"（{message}）" if message else ""
    print(
        f"FAIL: {repo} 没有 Release v{version}，或列不出资产（HTTP {code}）{extra}",
        file=sys.stderr,
    )
    sys.exit(1)
with open(dest, "w", encoding="utf-8") as out:
    for asset in assets:
        name = asset.get("name") or ""
        size = asset.get("size") or 0
        if name and int(size) > 0:
            print(name, file=out)
PY
fi

missing=0
for name in $required; do
  if ! grep -F -x -q "$name" "$names"; then
    echo "FAIL: Release v$version 缺少资产 $name" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "FAIL: $repo 的 Release v$version 与插件 VERSION 对不上" >&2
  exit 1
fi

echo "ok: $repo v$version 含有全部 memory-hook 资产"
