---
description: 用 deep-memory 控制台「接入与密钥」页给出的一次性接入码登录本机（写入 ~/.config/deep-memory/credentials.toml，hook 与 MCP 共用）
argument-hint: <接入码> [--server URL]
---

memory-hook redeem 的输出：

!`"$CLAUDE_PLUGIN_ROOT/bin/memory-hook" redeem $ARGUMENTS 2>&1`

根据上面的输出回复用户：显示「已登录」则说明登录成功，告诉用户下一次会话开始时会自动注入长期记忆、MCP 工具已可用；
否则原样转述错误，并提示接入码 10 分钟内有效、只能兑换一次，需要回控制台重新「复制一句话」。
