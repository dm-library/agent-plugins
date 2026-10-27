# Deep Memory Coding Agent Plugins

Deep Memory 是面向开发者的跨工具个人记忆系统。本仓库为 **Claude Code**、**Codex** 和 **Cursor** 提供官方插件支持，使不同 Coding Agent 能够无缝共享和演进长期项目记忆、用户决策与工作情景。

- **仓库地址**：[https://github.com/dm-library/agent-plugins](https://github.com/dm-library/agent-plugins)

---


## 核心特性

- **会话增量自动采集（Stop Hook）**：每轮问答结束时自动按游标增量读取本机 transcript，经过敏感凭据预脱敏后异步上传入库。服务端唯一约束保证重放幂等。
- **记忆与画像智能注入（SessionStart Hook）**：会话启动时根据当前工作目录自动检索相关记忆、已确认规则与用户画像，注入 Agent 上下文。
- **Streamable HTTP MCP**：直连 Deep Memory 服务端 MCP 端点（`POST /mcp`），在对话中随时检索项目决策或沉淀新记忆。
- **零依赖极简分发**：插件内嵌轻量启动器，按当前系统架构（macOS arm64/x86_64, Linux x86_64/aarch64）自动从 GitHub Releases 下载校验对应版本的二进制，无需配置本地编译环境。

---

## 快速安装

### 1. Claude Code

从官方市场安装：

```bash
# 添加插件市场
claude plugin marketplace add dm-library/agent-plugins

# 安装插件
claude plugin install deep-memory@deep-memory
```

**登录授权**：在 Claude Code 会话中运行斜杠命令：
```
/deep-memory:login <控制台「工具」里生成的接入码>
```
也可在终端直接执行：
```bash
~/.local/share/deep-memory/bin/<version>/memory-hook redeem <接入码>
```

> **MCP 配置**：Claude Code 插件的 `.mcp.json` 内置 `headersHelper`，自动从本机凭据读取 PAT 发起请求，无需在配置文件中明文保存 API Key。

---

### 2. Codex

Codex 优先读取 `.agents/plugins/marketplace.json` 清单：

```bash
# 添加插件市场
codex plugin marketplace add dm-library/agent-plugins

# 安装 Codex 专用插件
codex plugin add deep-memory-codex@deep-memory
```

**信任 Hook**：
Codex 的安全机制要求对插件 Hook 进行一次信任确认。安装后在 `codex` 交互界面中运行 `/hooks`，确认信任 `deep-memory-codex` 的相关 Hook 即可常态生效。

> **Codex 注意事项**：Codex 的 `SessionEnd` hook 规范为同步执行且超时上限为 3 秒。插件已适配 3 秒超时限制，未完成的增量会在下一次会话中自动重传，数据不丢失。

> **MCP 配置**：Codex 插件的 `.mcp.json` 用 `http_headers_helper` 调用 `memory-hook mcp-headers --url <插件内置地址>`，与 Claude Code 一样从本机凭据读取 PAT，不需要导出 `DM_API_KEY`。`mcp-headers` 会核对这个地址与登录凭据所属的服务端是否一致，不一致就拒绝输出凭据（自托管用户见下文「自托管服务端」）。需要支持 `http_headers_helper` 的 Codex 版本（0.159 能加载这份配置）；不认识这个字段的旧版本请在 `~/.codex/config.toml` 里自行注册：`[mcp_servers.deep-memory] url = "https://dm.exobrain.cc/mcp"`、`bearer_token_env_var = "DM_API_KEY"`（同时设置 `DM_SPACE_ID`，见下）。

---

### 3. Cursor

Cursor 2.5+ 支持本地与团队插件目录加载：

```bash
# 克隆仓库并软链接到 Cursor 本地插件目录
git clone https://github.com/dm-library/agent-plugins.git
mkdir -p ~/.cursor/plugins/local
ln -sfn "$(pwd)/agent-plugins/cursor" ~/.cursor/plugins/local/deep-memory
```

然后在 Cursor 中按 `Cmd+Shift+P`（macOS）或 `Ctrl+Shift+P`（Linux/Windows）执行 **Developer: Reload Window**。打开 Cursor 设置中的 **Customize** 即可看到 Deep Memory hooks 与 MCP 工具。

> **MCP 配置**：Cursor 的 `mcp.json` 只能从环境变量取值（`${env:NAME}`），没有动态凭据接口，所以插件内置 MCP 条目的 Bearer Token 来自环境变量 `DM_API_KEY`——请把它设成登录得到的同一个 PAT（`~/.config/deep-memory/credentials.toml` 里的 `api_key`），并同时设置 `DM_SPACE_ID`。Hooks 不受影响，仍然读登录凭据。
>
> ⚠️ 这个内置条目固定连 `https://dm.exobrain.cc/mcp`。**连自托管服务端时不要设置 `DM_API_KEY`**，否则自托管实例的 PAT 会被发到托管域名；请改用 `memory-hook mcp-config cursor` 生成的本机配置（见「自托管服务端」）。

---

## 认证与登录

推荐用**一键接入码**：在 Web 控制台「工具」→「连接新工具」里生成接入码，在 Agent 对话中运行 `/deep-memory:login <接入码>`（或终端执行 `memory-hook redeem <接入码>`）。系统会换取长期凭据并写入 `~/.config/deep-memory/credentials.toml`（PAT、space、登录时的服务端地址）。

凭据由谁读取：

| 组件 | PAT 来源 |
|---|---|
| Hooks（三个宿主）、`memory-hook watch` / `clipboard` | `DM_API_KEY` 环境变量 > `credentials.toml` > `agent.toml` 的 `api_key` |
| Claude Code MCP | `memory-hook mcp-headers`（`headersHelper`），取值同上 |
| Codex MCP | `memory-hook mcp-headers`（`http_headers_helper`），取值同上 |
| Cursor MCP（插件内置条目） | 只读环境变量 `DM_API_KEY` |
| 自托管：`memory-hook mcp-stdio` | 登录凭据，只发往登录时的服务端 |

> `DM_API_KEY` 一旦设置就会压过登录凭据（`memory-hook status` 会提示）。只有 Cursor 的内置 MCP 条目需要它；设置时请与登录得到的 PAT 保持一致，重新登录后记得同步更新。
>
> **设置 `DM_API_KEY` 时必须同时设置 `DM_SPACE_ID`。** 服务端没有默认 space：只有 key 没有 space 时，请求会被拒绝（`SCOPE_NOT_SPECIFIED`），记忆注入与会话采集都不会生效。从 v0.4.1 起 hooks 会对这种配置给出明确警告（Claude Code / Codex 显示在会话开始的系统消息里，Cursor 附在注入上下文里，另写一行到 stderr），`memory-hook status` 也会提示。space id 可在控制台「工具」或 `credentials.toml` 的 `space_id` 查到。

**凭据只发给它所属的服务端**（v0.4.1）：
- 登录凭据绑定 `memory-hook login` 时的服务端地址。`DM_MEMORYD_URL` 指向别的地址时，hooks 不会把登录凭据发过去（视同未登录并给出警告）。
- `memory-hook mcp-headers` 先核对宿主要连的 MCP 地址（`--url`，或 Claude Code 注入的 `CLAUDE_CODE_MCP_SERVER_URL`），与凭据所属服务端不是同一个 origin（scheme + 主机 + 端口）就拒绝输出，以非 0 退出。

没有登录凭据时，Hooks 不会向公网服务端发送任何内容（只有服务端地址是本机回环地址时才允许免凭据）。

---

## 配置参考

配置优先级：**环境变量** > `~/.config/deep-memory/credentials.toml`（登录写入）> `~/.config/deep-memory/agent.toml`（手写）> **默认值**。

| 环境变量 | 配置文件键 | 默认值 | 说明 |
|---|---|---|---|
| `DM_MEMORYD_URL` | `base_url` | `https://dm.exobrain.cc` | Deep Memory 服务端地址（兼容旧名 `MEMORYD_URL`） |
| `DM_API_KEY` | `api_key` | 无 | 随请求携带的 Bearer Token |
| `DM_SPACE_ID` | `space_id` | 登录时选定 | 采集写入与注入读取的 space。**设置了 `DM_API_KEY` 就必须同时设置它**（服务端没有默认 space） |
| `DM_CONTEXT_BUDGET` | `context_budget` | `1500` | SessionStart 注入的 token 预算上限 |
| `DM_EXCLUDE_DIRS` | `exclude` | 空 | 逗号分隔的目录路径前缀，命中时跳过采集与注入（Hooks 与 `memory-hook watch` 都生效） |
| `DM_STATE_DIR` | `state_dir` | `~/.local/state/deep-memory` | 本机游标、缓存与重试退避状态目录 |
| `DM_HOOK_BUDGET_MS` | `hook_budget_ms` | 由宿主超时换算 | 单次上传 Hook 的时间预算；缺省取 `hooks.json` 里该 Hook 的 `timeout`（经 `--timeout` 传入）减去进程启停余量 |

### 服务端地址：Hooks 与 MCP 要连同一台

不做任何配置时，Hooks 与三个宿主的 MCP 都连 `https://dm.exobrain.cc`。

连自建或本机服务端时，两者的取值方式不同，需要分别指过去：

- **Hooks**：按上面的优先级取 `base_url`——`memory-hook login --server <URL>` 会把地址写进 `credentials.toml`，之后自动生效。
- **MCP**：宿主的 MCP 配置读不到 `credentials.toml` / `agent.toml`。
  - Claude Code：插件的 MCP 地址是 `${DM_MEMORYD_URL:-https://dm.exobrain.cc}/mcp`，设置环境变量 `DM_MEMORYD_URL`（例如写进 `~/.claude/settings.json` 的 `env`）即可；同一个变量对 Hooks 也是最高优先级。
  - Codex / Cursor：插件配置不支持在地址里展开环境变量，内置条目固定连托管地址。运行下面的命令，按登录结果生成本机 MCP 配置（stdio 方式，经 `memory-hook mcp-stdio` 转发到 `<你的地址>/mcp`，凭据直接取自登录结果，不需要 `DM_API_KEY`），并在宿主里停用插件内置的 `deep-memory` MCP 条目：

    ```bash
    memory-hook mcp-config codex    # 输出追加到 ~/.codex/config.toml 的片段
    memory-hook mcp-config cursor   # 输出合并进 ~/.cursor/mcp.json 的片段
    ```

  内置条目即使没停用也不会拿到自托管凭据：`mcp-headers` 会拒绝把它发往托管地址（Codex 会显示该 MCP 连接失败）。Cursor 的内置条目读的是 `DM_API_KEY`，所以自托管用户**不要设置 `DM_API_KEY`**。

`memory-hook status` 会在 Hooks 连接的不是默认地址时提示这一点。

---

## 开源协议

本项目采用 [MIT License](https://opensource.org/licenses/MIT) 开源。
