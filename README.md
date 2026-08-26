# Coding Agent 记忆插件（Claude Code / Codex / Cursor）

设计文档：`docs/agent-memory/design/coding-agent-memory-plugin.md`。

三个插件是同一套逻辑（`memory-hook` 二进制）的三种打包：

- 每轮问答结束（Stop hook，async）：按游标增量读本机 transcript →
  adapter 归一化 + 密钥预遮蔽 → 上传 `POST /v1/connectors/agent-sessions/events`；
- 会话开始（SessionStart hook）：`POST /v1/context/compile` →
  已确认规则 / 用户画像 / 项目相关记忆 / 待确认收件箱注入 additionalContext；
- 上传失败不推进游标（transcript 本身就是持久队列），指数退避后自动重试；
  服务端唯一约束保证重放幂等。

## 构建与安装

```bash
make plugins          # 构建并把 memory-hook 拷入 claude-code/bin/、codex/bin/ 与 cursor/bin/（MCP 走服务端 HTTP，无本机 MCP 进程）
make auth-login       # 登录一次（RFC 8628 设备授权）：终端给短码，浏览器里确认，凭据写入
                      # ~/.config/deep-memory/credentials.toml，hook / MCP / 剪贴板共用；
                      # 没有 memoryctl 的机器可用插件目录里的 `memory-hook login`
```

登录后 hook 不再需要在 `agent.toml` 里手填 `DM_API_KEY` / `DM_SPACE_ID`；这些变量只用于临时覆盖。
机制见 `docs/agent-memory/design/unified-device-login-design.md`。

MCP 只有一种传输：memoryd 的 **Streamable HTTP** `POST {MEMORYD_PUBLIC_URL}/mcp`，头 `Authorization: Bearer <PAT>`
（不暴露 confirm / reject，确认归交互身份）。Claude Code 插件的 `.mcp.json` 用 `headersHelper` 指向
`memory-hook mcp-headers`，每次连接时从 `credentials.toml` 读 PAT，不需要把 key 写进任何配置；
Codex / Cursor 的清单读环境变量 `DM_API_KEY`。服务端地址默认 `https://dm.exobrain.cc`，
本机开发用 `DM_MEMORYD_URL` 覆盖。最省事的接入方式是 Web 控制台侧栏「接入与密钥」→「复制一句话」，
Agent 自己 `memory-hook redeem <接入码>`。见 `docs/agent-memory/design/api-key-and-client-authorization.md`。

### Claude Code

从 GitHub marketplace 安装（推荐；二进制由启动器按版本从 Releases 下载、sha256 校验）：

```bash
claude plugin marketplace add outyua/deep-memory-plugin
claude plugin install deep-memory@deep-memory
# 在 Claude Code 里：/deep-memory:login <控制台「复制一句话」里的接入码>
```

本地开发从源码目录安装（`make plugins` 把 debug 二进制放进 `bin/memory-hook.local`，启动器优先用它）：

```bash
claude plugin marketplace add /path/to/deep-memory/plugins
claude plugin install deep-memory@deep-memory
```

发布新版本：`deploy/build-client.sh && deploy/publish-plugin.sh <version>`。

装完即生效（headless `-p` 会话也触发；Stop/SessionEnd 是 async hook，
进程脱离 CLI 存活，事件不出现在 stream-json 里但采集正常）。

### Codex

两边共用 `plugins/` 作为 marketplace 根目录，但清单文件分开：

- Claude Code 读 `.claude-plugin/marketplace.json`（只有 `deep-memory`）
- Codex 优先读 `.agents/plugins/marketplace.json`（只有 `deep-memory-codex`）

不要让 Codex 去装 Claude 那份清单。`plugin.json` 的 `name` 必须与 marketplace 条目名一致，故 Codex 包名为 `deep-memory-codex`：

```bash
codex plugin marketplace add /path/to/deep-memory/plugins
codex plugin add deep-memory-codex@deep-memory
```

装对后，Codex「市场」里这条的路径应是
`.../plugins/.agents/plugins/marketplace.json`，插件数是 1。
若仍显示 `.claude-plugin/marketplace.json` 或「2 个插件」，说明还在读 Claude 清单。

改过插件文件后必须升 `plugin.json` 的 `version` 再 `codex plugin add` 一次：
Codex 本地 marketplace 的缓存只在版本变化时刷新。

**必须一次信任**：Codex 的 hook 有 trusted_hash 门（`[hooks.state]`），
未信任的 hook 会被静默跳过——打开 `codex` 交互界面运行 `/hooks`，信任
`deep-memory-codex` 的三个 hook 后常态生效。已审核来源的自动化可用
`codex exec --dangerously-bypass-hook-trust` 单次绕过（不要作为常态）。

两份清单已经拆开，Codex 市场里不应再出现 Claude 包。若 `~/.codex/config.toml`
还留着 `deep-memory@deep-memory:hooks/hooks.json` 的 `[hooks.state]` 条目，
那是以前误装 Claude 包留下的信任记录，对当前 `deep-memory-codex` 无效，可删。

**Codex 的 SessionEnd 约束**：SessionEnd hook 超时上限 3s、不支持 async
（进程退出前同步执行），配置超出会打 "clamping timeout to 3s" /
"running async hook synchronously" 加载警告。故 Codex 版 `hooks/hooks.json` 的
SessionEnd 写 `timeout: 3` 且不加 `async`。被 3s 截断没有数据丢失：
游标不推进，残余增量下次会话重传；服务端对无 session_end 事件的会话
按静默阈值兜底生成 episode。

### Cursor

Cursor 插件格式与 Claude / Codex **不同源**（官方文档：https://cursor.com/docs/plugins 、https://cursor.com/docs/reference/plugins 、https://cursor.com/docs/hooks）：

- 清单在 `.cursor-plugin/plugin.json`（不是 `.claude-plugin`）
- hook 事件名是 camelCase：`sessionStart` / `stop` / `sessionEnd`
- `hooks.json` 是 `{ version, hooks: { event: [{ command, timeout }] } }`，没有 Claude 那种 `matcher` + 嵌套 `hooks` 数组
- SessionStart 注入 stdout 是 `{ "additional_context": "..." }`，不是 `hookSpecificOutput`
- stdin 常见字段是 `conversation_id`、`workspace_roots`、`transcript_path`（可空）；没有 `cwd`
- 会话 JSONL 在 `~/.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>.jsonl`
- 默认发现 `hooks/hooks.json` 与根目录 `mcp.json`
- 命令里的插件根变量是 `${CURSOR_PLUGIN_ROOT}`

本地安装（Cursor 2.5+ 从 `~/.cursor/plugins/local` 加载）：

```bash
make plugins
mkdir -p ~/.cursor/plugins/local
ln -sfn "$(pwd)/plugins/cursor" ~/.cursor/plugins/local/deep-memory
```

然后 **Developer: Reload Window**（或完全退出再开 Cursor）。打开 **Customize**，应能看到 Deep Memory 的 hooks 与 `deep-memory` MCP。

改过插件文件后同样要升 `plugin.json` 的 `version` 再 Reload：Cursor 按版本识别更新。

Cloud Agent 不跑 `sessionStart` / `sessionEnd`（官方：cloud 没有 IDE 会话边界，且早期回合可能只读）。`stop` 会跑，采集仍可按轮次上传；会话开始注入只在本机 Agent 窗口生效。

多插件仓库清单在 `plugins/.cursor-plugin/marketplace.json`（只含 Cursor 包）。团队市场可把 `plugins/` 当仓库根导入。不要把 Claude / Codex 的 `hooks.json` 交给 Cursor 加载——`${CLAUDE_PLUGIN_ROOT}` 不会被展开。

### Codex hooks 为什么必须放在 `hooks/hooks.json`

Codex 插件默认只发现 `hooks/hooks.json`（`codex-rs/core-plugins/src/loader.rs`
的 `DEFAULT_HOOKS_CONFIG_FILE`）。根目录 `hooks.json` **不会**被扫描；
`plugin.json` 也没写 `hooks` 字段时，加载结果是空列表且不打警告。

这和用户级 / 项目级 `~/.codex/hooks.json`、`.codex/hooks.json` 不是同一条路径。
设计文档早期写成「`hooks.json` 或 `hooks/hooks.json` 都行」，那是错的。

Claude Code 包本身放的就是 `hooks/hooks.json`，所以误装 `deep-memory@deep-memory`
时 Codex **反而能发现 hook**（`${CLAUDE_PLUGIN_ROOT}` 也会被展开成插件根）。
按文档改装 `deep-memory-codex` 之后 hook 消失，看起来像 Claude 包干扰，
实际是 Codex 包路径不符合默认发现规则。

当前 Codex 包：

- hook 文件：`plugins/codex/hooks/hooks.json`
- 命令：`${PLUGIN_ROOT}/bin/memory-hook`（不依赖 `~/.local/bin`）
- `plugin.json` 显式声明 `"hooks": "./hooks/hooks.json"`

## 配置

优先级：进程环境 > `~/.config/deep-memory/agent.toml` > 默认值。
（memory-hook 刻意不加载 cwd 的 `.env`——hook 运行在用户项目目录。）

| 环境变量 | agent.toml 键 | 默认 | 说明 |
|---|---|---|---|
| `MEMORYD_URL` | `base_url` | `http://127.0.0.1:7460` | 服务端地址；远端部署改 HTTPS 地址 |
| `DM_API_KEY` | `api_key` | 无 | 随请求发 `Authorization: Bearer`（服务端多用户开放后生效） |
| `DM_CONTEXT_BUDGET` | `context_budget` | `1500` | SessionStart 注入的 token 预算 |
| `DM_EXCLUDE_DIRS` | `exclude` | 空 | 逗号分隔的 cwd 前缀，命中则采集与注入都跳过 |
| `DM_STATE_DIR` | `state_dir` | `~/.local/state/deep-memory` | 游标 / 缓存 / 退避状态；`clipboard/` 队列也在其下 |

## 与 `memory-hook watch` 的关系

`memory-hook watch`（轮询授权的会话目录，`DM_WATCH_CLAUDE_DIR` / `DM_WATCH_CODEX_DIR` / `DM_WATCH_CURSOR_DIR`）
与 hook 子命令共用游标目录与上传路径，可并存：source_event 唯一约束使两路采集互相幂等。
本机长期建议只开一路。静默会话 → work_episode 由 memory-worker 兜底生成。
# agent-plugins
