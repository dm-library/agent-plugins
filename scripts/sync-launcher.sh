#!/bin/sh
# 启动器只有一份事实来源：launcher/memory-hook。各宿主目录里的 bin/memory-hook 由本脚本生成
# （插件按目录安装，每个宿主目录必须自带一份，所以生成物也提交进仓库）。
# 用法：sh scripts/sync-launcher.sh          生成 / 更新三份副本
#       sh scripts/sync-launcher.sh --check  只检查副本是否与生成结果一致（CI 用），不一致时非 0 退出
set -eu
cd "$(dirname "$0")/.."
src=launcher/memory-hook
mode=${1:-write}

render() {
  # 首行 shebang 原样保留，紧接着标明这是生成文件，其余与源文件逐字相同
  head -n 1 "$src"
  echo "# 生成文件，请勿手改：源文件是 launcher/memory-hook，改完运行 sh scripts/sync-launcher.sh"
  tail -n +2 "$src"
}

stale=0
for host in claude-code codex cursor; do
  dst="$host/bin/memory-hook"
  if [ "$mode" = "--check" ]; then
    if ! render | cmp -s - "$dst"; then
      echo "FAIL: $dst 与 launcher/memory-hook 的生成结果不一致；运行 sh scripts/sync-launcher.sh" >&2
      stale=1
    fi
  else
    mkdir -p "$host/bin"
    render > "$dst.tmp" && mv "$dst.tmp" "$dst" && chmod +x "$dst"
  fi
done
exit "$stale"
