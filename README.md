# Deep Memory Coding Agent Plugins

Deep Memory 是面向开发者的跨工具个人记忆系统。本仓库为 **Claude Code**、**Codex** 和 **Cursor** 提供官方插件支持，使不同 Coding Agent 能够无缝共享和演进长期项目记忆、用户决策与工作情景。

- **仓库地址**：[https://github.com/dm-library/agent-plugins](https://github.com/dm-library/agent-plugins)
- **服务端项目**：[https://github.com/dm-library/memory](https://github.com/dm-library/memory)

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
/deep-memory:login <控制台「接入与密钥」中复制的接入码>
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

---

## 认证与登录

Deep Memory 支持多种凭据提供方式：

1. **一键接入码（推荐）**：
   在 Web 控制台侧栏「接入与密钥」中点击「复制一句话」，在 Agent 对话中运行 `/deep-memory:login <接入码>`，系统将自动换取长期凭据并安全存储至 `~/.config/deep-memory/credentials.toml`。
2. **环境变量覆盖**：
   在环境或终端中导出 `DM_API_KEY` 与 `DM_MEMORYD_URL`。

---

## 配置参考

配置优先级：**环境变量** > `~/.config/deep-memory/agent.toml` > **默认值**。

| 环境变量 | agent.toml 键 | 默认值 | 说明 |
|---|---|---|---|
| `DM_MEMORYD_URL` | `base_url` | `https://dm.exobrain.cc` | Deep Memory 服务端地址 |
| `DM_API_KEY` | `api_key` | 无 | 随请求携带的 Bearer Token（用于无凭据文件时的直接认证） |
| `DM_CONTEXT_BUDGET` | `context_budget` | `1500` | SessionStart 注入的 token 预算上限 |
| `DM_EXCLUDE_DIRS` | `exclude` | 空 | 逗号分隔的目录路径前缀，命中时跳过采集与注入 |
| `DM_STATE_DIR` | `state_dir` | `~/.local/state/deep-memory` | 本机游标、缓存与重试退避状态目录 |

---

## 本地开发与调试

若需要调试本地构建的 `memory-hook` 二进制：

- **方式一（环境变量）**：设置 `export DM_HOOK_BIN=/path/to/target/debug/memory-hook`。
- **方式二（本地覆盖）**：将编译生成的 `memory-hook` 复制为对应插件目录下的 `bin/memory-hook.local`（已在 `.gitignore` 中排除），启动器将优先执行该本地文件。

---

## 开源协议

本项目采用 [MIT License](https://opensource.org/licenses/MIT) 开源。
