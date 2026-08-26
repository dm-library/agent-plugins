---
description: 查看本机 deep-memory 登录状态（服务端、账号、space、PAT 是否仍有效）
---

memory-hook status 的输出：

!`"$CLAUDE_PLUGIN_ROOT/bin/memory-hook" status 2>&1`

把上面的状态用一两句话转述给用户；若显示失效或未登录，提示用 /deep-memory:login <接入码> 重新登录。
