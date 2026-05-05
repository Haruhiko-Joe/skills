# Claude Agent SDK Reference

Claude Agent SDK 是 Anthropic 推出的 Agent 开发 SDK，支持 TypeScript 和 Python。

---

## 安装

```bash
# TypeScript
npm install @anthropic-ai/claude-agent-sdk

# Python
pip install claude-agent-sdk
```

---

## 核心 API

### query()

主入口函数，返回异步消息流：

**TypeScript：**
```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const message of query({
  prompt: "分析这个仓库的架构",
  options: {
    model: "opus",
    systemPrompt: "你是一个代码分析专家",
    cwd: "/path/to/repo",
    permissionMode: "bypassPermissions",
    allowedTools: ["Read", "Glob", "Grep"],
    maxTurns: 10,
  }
})) {
  if (message.type === "result") {
    console.log(message.result);
    console.log("Session ID:", message.session_id);
    console.log("Cost:", message.total_cost_usd);
  }
}
```

**Python：**
```python
from claude_agent_sdk import query, ClaudeAgentOptions

async for message in query(
    prompt="分析这个仓库的架构",
    options=ClaudeAgentOptions(
        model="opus",
        system_prompt="你是一个代码分析专家",
        cwd="/path/to/repo",
        permission_mode="bypassPermissions",
        allowed_tools=["Read", "Glob", "Grep"],
        max_turns=10,
    )
):
    if message.type == "result":
        print(message.result)
```

### startup()（TypeScript）

预热 CLI 子进程，加速首次查询。在应用启动时调用一次：

```typescript
import { startup } from "@anthropic-ai/claude-agent-sdk";

const warm = await startup({ options: { maxTurns: 3 } });

// 后续查询启动更快
for await (const message of warm.query("这里有哪些文件？")) {
  console.log(message);
}
```

### ClaudeSDKClient（Python）

用于多轮对话的自动会话管理客户端。内部自动追踪会话状态，每次 `query()` 调用自动延续同一会话：

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions, AssistantMessage, TextBlock

async with ClaudeSDKClient(options=ClaudeAgentOptions(
    allowed_tools=["Read", "Edit", "Glob", "Grep"],
)) as client:
    # 第一次查询——内部自动捕获 session ID
    await client.query("分析 auth 模块")
    async for message in client.receive_response():
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)

    # 第二次查询——自动延续同一会话
    await client.query("现在重构为 JWT 方式")
    async for message in client.receive_response():
        ...

    # 控制方法
    await client.interrupt()                          # 中断执行
    await client.set_model("sonnet")                  # 切换模型
    await client.set_permission_mode("acceptEdits")   # 更改权限
    await client.rewind_files(user_message_id)        # 回退文件修改
```

与 `query()` 的关键区别：

| 特性 | `query()` | `ClaudeSDKClient` |
|------|-----------|-------------------|
| 会话 | 每次新建 | 复用同一会话 |
| 多轮对话 | 需通过 `resume` 选项 | 自动管理 |
| 中断 | 不支持 | `await client.interrupt()` |
| 适用场景 | 一次性任务、流水线 | 交互式应用、多轮对话 |

### 主要配置项

| 选项 | 类型 | 说明 |
|------|------|------|
| `prompt` | `string \| AsyncIterable<SDKUserMessage>` | 任务描述，支持文本或多模态消息流 |
| `model` | `string` | 模型：opus / sonnet / haiku |
| `systemPrompt` | `string` | 系统提示词 |
| `cwd` | `string` | 工作目录 |
| `allowedTools` | `string[]` | 允许使用的工具 |
| `disallowedTools` | `string[]` | 禁止使用的工具 |
| `permissionMode` | `string` | 权限模式 |
| `maxTurns` | `number` | 最大迭代次数 |
| `maxBudgetUsd` | `number` | 最大 USD 预算 |
| `outputFormat` | `object` | 结构化输出 schema |
| `mcpServers` | `object` | MCP 服务器配置 |
| `agents` | `object` | 子 Agent 定义 |
| `hooks` | `object` | 事件钩子 |
| `thinking` | `object` | 思考配置：`{ type: "adaptive" \| "enabled" \| "disabled" }` |
| `effort` | `string` | 推理深度：low / medium / high / xhigh / max |
| `continue` | `boolean` | 继续最近的会话 |
| `resume` | `string` | 通过 session ID 恢复指定会话 |
| `forkSession` | `boolean` | 从已有会话分叉 |
| `persistSession` | `boolean` | 持久化会话到磁盘（仅 TS，默认 true） |
| `enableFileCheckpointing` | `boolean` | 追踪并回退文件修改 |
| `sandbox` | `object` | 沙箱设置 |
| `tools` | `array \| object` | 工具配置，支持预设：`{ type: "preset", preset: "claude_code" }` |
| `settingSources` | `array` | 限制加载的配置源 |
| `plugins` | `array` | 插件配置 |
| `sessionStore` | `object` | 自定义会话存储后端 |
| `fallbackModel` | `string` | 失败时的备选模型（Python） |

---

## 思考配置

控制模型的推理行为：

```typescript
// 自适应（默认）——模型自行决定何时思考
options: { thinking: { type: "adaptive" } }

// 启用并设置 token 预算
options: { thinking: { type: "enabled", budget_tokens: 20000 } }

// 禁用
options: { thinking: { type: "disabled" } }

// effort 级别（替代手动思考配置）
options: { effort: "high" }  // low | medium | high | xhigh | max
```

Opus 4.7 需要 SDK v0.2.111+，使用 `thinking: { type: "adaptive" }`（不再使用旧的 `enabled` 类型）。

---

## 图像输入

`prompt` 支持 `AsyncIterable<SDKUserMessage>` 传入包含图像的多模态消息：

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";
import type { SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import fs from "fs";

const imageData = fs.readFileSync("/path/to/image.png").toString("base64");

async function* imagePrompt(): AsyncGenerator<SDKUserMessage> {
  yield {
    type: "user",
    message: {
      role: "user",
      content: [
        {
          type: "image",
          source: { type: "base64", media_type: "image/png", data: imageData },
        },
        { type: "text", text: "请描述这张图片中的内容" },
      ],
    },
    parent_tool_use_id: null,
  };
}

for await (const msg of query({
  prompt: imagePrompt(),
  options: { model: "sonnet", maxTurns: 1 },
})) {
  if (msg.type === "result") console.log(msg.result);
}
```

URL 方式：
```typescript
content: [
  { type: "image", source: { type: "url", url: "https://example.com/photo.jpg" } },
  { type: "text", text: "分析这张图片" },
]
```

| 项目 | 限制 |
|------|------|
| 支持格式 | JPEG、PNG、GIF、WebP |
| 单张大小 | ≤ 5 MB |
| 像素上限 | 8000 × 8000 px |

---

## 会话管理

```typescript
// 获取 session ID
let sessionId: string;
for await (const msg of query({ prompt: "..." })) {
  if (msg.type === "result") sessionId = msg.session_id;
}

// 恢复指定会话
for await (const msg of query({
  prompt: "继续之前的工作",
  options: { resume: sessionId }
})) { ... }

// 继续最近的会话
for await (const msg of query({
  prompt: "继续",
  options: { continue: true }
})) { ... }

// 分叉会话（创建分支）
for await (const msg of query({
  prompt: "尝试另一种方案",
  options: { resume: sessionId, forkSession: true }
})) { ... }
```

### 会话工具函数

**TypeScript：**
```typescript
import { listSessions, getSessionMessages, getSessionInfo, renameSession, tagSession } from "@anthropic-ai/claude-agent-sdk";

const sessions = await listSessions();
const messages = await getSessionMessages(sessionId);
const info = await getSessionInfo(sessionId);
await renameSession(sessionId, "Auth 重构");
await tagSession(sessionId, "needs-review");  // 传 null 清除标签
```

**Python：**
```python
from claude_agent_sdk import list_sessions, get_session_messages, get_session_info, rename_session, tag_session

sessions = list_sessions(directory="/path/to/project", limit=10)
messages = get_session_messages(session_id)
info = get_session_info(session_id)
rename_session(session_id, "Auth 重构")
tag_session(session_id, "needs-review")
```

会话信息字段：`session_id`、`summary`、`last_modified`、`custom_title`、`first_prompt`、`git_branch`、`cwd`、`tag`、`created_at`。

---

## Query 对象方法（TypeScript）

`query()` 返回的 Query 对象除了消息迭代外，还提供控制方法：

```typescript
const q = query({ prompt: "...", options: { ... } });

// 迭代消息
for await (const msg of q) { ... }

// 控制方法
await q.interrupt();                        // 中断当前执行
await q.rewindFiles(userMessageId);         // 回退文件修改到某个点
await q.setPermissionMode("plan");          // 执行中途切换权限模式
await q.setModel("sonnet");                 // 执行中途切换模型

// 内省方法
const initResult = await q.initializationResult();
const commands = await q.supportedCommands();
const models = await q.supportedModels();
const agents = await q.supportedAgents();
const mcpStatus = await q.mcpServerStatus();

// MCP 管理
await q.reconnectMcpServer("github");
await q.toggleMcpServer("github", true);
await q.setMcpServers({ ... });

// 后台任务控制
await q.stopTask(taskId);

// 清理
q.close();
```

---

## 结构化输出

**TypeScript（Zod）：**
```typescript
import { z } from "zod";

const schema = z.object({
  summary: z.string(),
  issues: z.array(z.object({
    severity: z.enum(["high", "medium", "low"]),
    description: z.string(),
  })),
  passed: z.boolean(),
});

for await (const msg of query({
  prompt: "审查这段代码",
  options: {
    outputFormat: { type: "json_schema", schema: z.toJSONSchema(schema) }
  }
})) {
  if (msg.type === "result" && msg.structured_output) {
    const validated = schema.safeParse(msg.structured_output);
    if (validated.success) console.log(validated.data);
  }
}
```

**Python（Pydantic）：**
```python
from pydantic import BaseModel

class ReviewOutput(BaseModel):
    summary: str
    issues: list[dict]
    passed: bool

async for msg in query(
    prompt="审查这段代码",
    options=ClaudeAgentOptions(
        output_format={
            "type": "json_schema",
            "schema": ReviewOutput.model_json_schema()
        }
    )
):
    if msg.type == "result" and msg.structured_output:
        result = ReviewOutput.model_validate(msg.structured_output)
```

---

## 权限模式

| 模式 | 行为 |
|------|------|
| `"default"` | 未匹配的工具需要审批（需 `canUseTool` 回调） |
| `"acceptEdits"` | 自动批准文件编辑和常见文件系统命令 |
| `"bypassPermissions"` | 自动批准所有工具（谨慎使用） |
| `"plan"` | 仅规划不执行 |
| `"dontAsk"` | 仅允许 allowedTools 中的工具，其余拒绝 |
| `"auto"` | 模型分类器决定审批（仅 TypeScript） |

---

## 内置工具

| 工具 | 用途 |
|------|------|
| `Read` | 读取文件 |
| `Write` | 创建文件 |
| `Edit` | 编辑现有文件 |
| `Bash` | 执行终端命令 |
| `Monitor` | 监控后台脚本，响应输出事件 |
| `Glob` | 按模式搜索文件 |
| `Grep` | 搜索文件内容 |
| `WebSearch` | 网络搜索 |
| `WebFetch` | 获取网页内容 |
| `Agent` | 调用子 Agent |
| `NotebookEdit` | 编辑 Jupyter 笔记本 |
| `AskUserQuestion` | 向用户提出澄清问题（可附选项） |

---

## Subagents（子 Agent）

内置子 Agent 机制——通过 `agents` 配置定义专门的子 Agent，Claude 自行决定何时调用：

```typescript
for await (const msg of query({
  prompt: "全面审查这个项目的代码质量",
  options: {
    allowedTools: ["Read", "Grep", "Glob", "Agent"],
    agents: {
      "security-reviewer": {
        description: "安全审查专家，检查代码中的安全漏洞",
        prompt: `你是安全审查专家，专注于：
- SQL 注入、XSS 等 OWASP Top 10 漏洞
- 敏感信息泄露
- 权限校验缺失`,
        tools: ["Read", "Grep", "Glob"],
        model: "opus",
      },
      "perf-reviewer": {
        description: "性能审查专家，识别性能瓶颈",
        prompt: "你是性能审查专家...",
        tools: ["Read", "Grep", "Glob", "Bash"],
        model: "sonnet",
        maxTurns: 5,
        background: true,
      },
    }
  }
})) { ... }
```

### AgentDefinition 字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `description` | `string` | 是 | 描述该 Agent 的用途（Claude 据此决定是否调用） |
| `prompt` | `string` | 是 | System Prompt |
| `tools` | `string[]` | 否 | 允许使用的工具，未指定则继承全部 |
| `disallowedTools` | `string[]` | 否 | 禁止使用的工具 |
| `model` | `string` | 否 | 模型覆盖：opus / sonnet / haiku |
| `maxTurns` | `number` | 否 | 子 Agent 最大轮数 |
| `background` | `boolean` | 否 | 作为后台任务运行（通过 `TaskCompleted` hook 通知） |
| `initialPrompt` | `string` | 否 | 自动提交的首轮 prompt |
| `memory` | `string` | 否 | 记忆范围："user" / "project" / "local" |
| `effort` | `string` | 否 | effort 级别覆盖 |
| `permissionMode` | `string` | 否 | 权限模式覆盖 |
| `skills` | `string[]` | 否 | 可使用的 skill |
| `mcpServers` | `array` | 否 | 可使用的 MCP 服务器 |

---

## MCP 服务器

通过 MCP（Model Context Protocol）连接外部系统：

```typescript
for await (const msg of query({
  prompt: "列出最近的 GitHub issues",
  options: {
    mcpServers: {
      github: {
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-github"],
        env: { GITHUB_TOKEN: process.env.GITHUB_TOKEN },
      }
    },
    allowedTools: ["mcp__github__*"],
  }
})) { ... }
```

工具命名规则：`mcp__{server_name}__{tool_name}`

传输类型：
| 类型 | 场景 | 配置 |
|------|------|------|
| stdio（默认） | 本地进程 | `{ command, args }` |
| http | 云端 API | `{ type: "http", url }` |
| sse | 流式端点 | `{ type: "sse", url }` |
| sdk | 进程内服务器 | `{ type: "sdk", name, instance }` |

---

## 自定义工具

**TypeScript：**
```typescript
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const getTemperature = tool(
  "get_temperature",
  "获取指定位置的当前温度",
  {
    latitude: z.number().describe("纬度"),
    longitude: z.number().describe("经度"),
  },
  async (args) => {
    const resp = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${args.latitude}&longitude=${args.longitude}&current=temperature_2m`);
    const data = await resp.json();
    return { content: [{ type: "text", text: `温度：${data.current.temperature_2m}°C` }] };
  }
);

const server = createSdkMcpServer({
  name: "weather",
  version: "1.0.0",
  tools: [getTemperature],
});

// 作为进程内 MCP 服务器使用
for await (const msg of query({
  prompt: "东京现在的温度是多少？",
  options: { mcpServers: { weather: { type: "sdk", name: "weather", instance: server } } }
})) { ... }
```

**Python：**
```python
from claude_agent_sdk import tool, create_sdk_mcp_server, ClaudeAgentOptions

@tool("get_temperature", "获取指定位置的当前温度", {
    "latitude": {"type": "number", "description": "纬度"},
    "longitude": {"type": "number", "description": "经度"},
})
async def get_temperature(args):
    # 获取温度...
    return {"content": [{"type": "text", "text": f"温度：{temp}°C"}]}

@tool("get_humidity", "获取当前湿度", {"latitude": float, "longitude": float})
async def get_humidity(args):
    return {"content": [{"type": "text", "text": f"湿度：{humidity}%"}]}

weather_server = create_sdk_mcp_server(
    name="weather",
    version="1.0.0",
    tools=[get_temperature, get_humidity],
)

options = ClaudeAgentOptions(
    mcp_servers={"weather": weather_server},
    allowed_tools=["mcp__weather__get_temperature", "mcp__weather__get_humidity"],
)
```

---

## Hooks（事件钩子）

在关键执行节点插入自定义逻辑：

| Hook | 触发时机 |
|------|---------|
| `PreToolUse` | 工具执行前（可拦截/修改/拒绝） |
| `PostToolUse` | 工具成功执行后 |
| `PostToolUseFailure` | 工具执行失败后 |
| `PostToolBatch` | 一批工具调用完成后 |
| `Notification` | 通知事件 |
| `UserPromptSubmit` | 用户提交 prompt 时 |
| `SessionStart` | 会话开始时 |
| `SessionEnd` | 会话结束时 |
| `Stop` | 执行停止时 |
| `SubagentStart` | 子 Agent 启动时 |
| `SubagentStop` | 子 Agent 完成时 |
| `PreCompact` | 上下文压缩前 |
| `PermissionRequest` | 需要权限决策时 |
| `TaskCompleted` | 后台任务完成时 |
| `TeammateIdle` | 协作 Agent 空闲时 |

### PreToolUse Hook 输出

```typescript
type PreToolUseOutput = {
  permissionDecision?: "allow" | "deny" | "ask" | "defer";
  permissionDecisionReason?: string;
  updatedInput?: Record<string, unknown>;   // 修改工具输入
  additionalContext?: string;               // 注入上下文
};
```

### 示例：禁止修改 .env 文件

**TypeScript：**
```typescript
const protectEnv = async (input, toolUseID, { signal }) => {
  const filePath = input.tool_input?.file_path as string;
  if (filePath?.endsWith(".env")) {
    return {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "不允许修改 .env 文件",
      }
    };
  }
  return {};
};

for await (const msg of query({
  prompt: "...",
  options: {
    hooks: {
      PreToolUse: [{ matcher: "Write|Edit", hooks: [protectEnv] }],
    }
  }
})) { ... }
```

**Python：**
```python
from claude_agent_sdk import query, ClaudeAgentOptions, HookMatcher

async def protect_env(input_data, tool_use_id, context):
    file_path = input_data.get("tool_input", {}).get("file_path", "")
    if file_path.endswith(".env"):
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "不允许修改 .env 文件",
            }
        }
    return {}

async for msg in query(
    prompt="...",
    options=ClaudeAgentOptions(
        hooks={
            "PreToolUse": [HookMatcher(matcher="Write|Edit", hooks=[protect_env])]
        }
    )
):
    ...
```

---

## 消息类型

`query()` 返回的消息流包含：

| 类型 | 说明 |
|------|------|
| `system` (subtype: `init`) | 会话初始化 |
| `assistant` | Claude 的推理和工具调用 |
| `tool_result` | 工具执行结果 |
| `result` | 最终结果 |
| `rate_limit` | 速率限制事件 |
| `task_started` | 后台任务已启动 |
| `task_progress` | 后台任务进度 |
| `task_notification` | 后台任务完成/失败 |

### Result 消息字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `session_id` | `string` | 会话标识 |
| `subtype` | `string` | 结果子类型 |
| `result` | `string` | 文本结果 |
| `structured_output` | `object` | 解析后的结构化输出（如使用了 outputFormat） |
| `duration_ms` | `number` | 总执行时间 |
| `num_turns` | `number` | 使用的轮数 |
| `total_cost_usd` | `number` | 总费用（USD） |
| `usage` | `object` | Token 用量：`{ input_tokens, output_tokens, cache_*_input_tokens }` |
| `modelUsage` | `object` | 按模型分拆的用量 |
| `deferred_tool_use` | `object` | 延迟的工具调用 |
| `permission_denials` | `array` | 发生的权限拒绝 |

### Result 子类型

| subtype | 含义 |
|---------|------|
| `success` | 任务完成 |
| `error_during_execution` | 执行异常 |
| `error_max_turns` | 达到迭代上限 |
| `error_max_budget_usd` | 达到预算上限 |
| `error_max_structured_output_retries` | 结构化输出解析失败 |
| `error_interrupted` | 被用户取消或 hook 拦截 |

---

## Agent Class 模板

Claude Agent SDK 通过 session 管理状态。run/continue 模式通过 session ID 实现：

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

interface AgentStructuredResponse<T> {
  sessionId: string;
  data: T;
  cost?: number;
}

export class MyAgent {
  private readonly model: string;
  private readonly systemPrompt: string;
  private readonly tools: string[];
  private readonly permissionMode: string;

  constructor(options: { model?: string; systemPrompt?: string; tools?: string[]; permissionMode?: string } = {}) {
    this.model = options.model ?? "opus";
    this.systemPrompt = options.systemPrompt ?? "";
    this.tools = options.tools ?? ["Read", "Glob", "Grep"];
    this.permissionMode = options.permissionMode ?? "bypassPermissions";
  }

  async run(cwd: string, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    return this.execute(prompt, cwd);
  }

  async continue(sessionId: string, prompt: string, cwd?: string): Promise<AgentStructuredResponse<MyOutput>> {
    return this.execute(prompt, cwd, sessionId);
  }

  private async execute(prompt: string, cwd?: string, sessionId?: string): Promise<AgentStructuredResponse<MyOutput>> {
    const options: Record<string, unknown> = {
      model: this.model,
      systemPrompt: this.systemPrompt,
      allowedTools: this.tools,
      permissionMode: this.permissionMode,
      outputFormat: { type: "json_schema", schema: myOutputSchema },
    };
    if (cwd) options.cwd = cwd;
    if (sessionId) options.resume = sessionId;

    let result: AgentStructuredResponse<MyOutput> | undefined;

    for await (const msg of query({ prompt, options })) {
      if (msg.type === "result") {
        result = {
          sessionId: msg.session_id,
          data: msg.structured_output as MyOutput,
          cost: msg.total_cost_usd,
        };
      }
    }

    if (!result) throw new Error("No result received");
    return result;
  }
}
```

---

## 编排说明

编排模式的设计思想和选择指南请参见 SKILL.md 中的"多 Agent 编排"章节。

Claude Agent SDK 编排要点：
- **Context 传递**：序列化输出传递给下一个 Agent 的 prompt
- **会话恢复**：使用 `options.resume = sessionId` 恢复上下文；`forkSession` 创建分支
- **并行执行**：多个 `query()` 调用可并行运行，各自持有独立 session
- **内置 subagent**：通过 `agents` 配置声明子 Agent——Claude 自行决定何时调用，无需手动编写 Orchestrator 循环
- **后台子 Agent**：在 AgentDefinition 中设置 `background: true` 实现并发执行；通过 `TaskCompleted` hook 监控
- **多轮客户端**：使用 `ClaudeSDKClient`（Python）进行交互式多轮工作流，支持中断/转向能力
