# Claude Agent SDK Reference

Claude Agent SDK（原 Claude Code SDK）是 Anthropic 推出的 Agent 开发 SDK，支持 TypeScript 和 Python。

如需查阅最新 API 文档，请使用对应技能获取官方文档。

---

## 安装

```bash
# TypeScript
npm install @anthropic-ai/claude-agent-sdk

# Python
pip install claude-agent-sdk
```

环境变量：`ANTHROPIC_API_KEY=your-api-key`

替代 Provider：
- Amazon Bedrock：`CLAUDE_CODE_USE_BEDROCK=1` + AWS 凭证
- Google Vertex AI：`CLAUDE_CODE_USE_VERTEX=1` + GCP 凭证

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
| `outputFormat` | `object` | 结构化输出 schema |
| `mcpServers` | `object` | MCP 服务器配置 |
| `agents` | `object` | 子 Agent 定义 |
| `hooks` | `object` | 事件钩子 |
| `continue` | `boolean` | 继续最近的会话 |
| `resume` | `string` | 通过 session ID 恢复指定会话 |
| `forkSession` | `boolean` | 从已有会话分叉 |

---

## 图像输入

`prompt` 除了接受字符串，还支持 `AsyncIterable<SDKUserMessage>`，可传入包含图像的多模态消息。

### SDKUserMessage 结构

```typescript
type SDKUserMessage = {
  type: "user";
  message: MessageParam;          // { role: "user", content: string | ContentBlockParam[] }
  parent_tool_use_id: string | null;
};
```

`message.content` 数组中可混合 `ImageBlockParam` 和 `TextBlockParam`：

```typescript
// 图像内容块
interface ImageBlockParam {
  type: "image";
  source: Base64ImageSource | URLImageSource;
}

interface Base64ImageSource {
  type: "base64";
  media_type: "image/jpeg" | "image/png" | "image/gif" | "image/webp";
  data: string;  // base64 编码
}

interface URLImageSource {
  type: "url";
  url: string;
}
```

### 示例

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
          source: {
            type: "base64",
            media_type: "image/png",
            data: imageData,
          },
        },
        {
          type: "text",
          text: "请描述这张图片中的内容",
        },
      ],
    },
    parent_tool_use_id: null,
  };
}

for await (const msg of query({
  prompt: imagePrompt(),
  options: { model: "sonnet", maxTurns: 1 },
})) {
  if (msg.type === "result") {
    console.log(msg.result);
  }
}
```

URL 方式更简洁，直接引用在线图片：

```typescript
content: [
  {
    type: "image",
    source: { type: "url", url: "https://example.com/photo.jpg" },
  },
  { type: "text", text: "分析这张图片" },
]
```

### 格式与限制

| 项目 | 限制 |
|------|------|
| 支持格式 | JPEG、PNG、GIF、WebP |
| 单张大小 | ≤ 5 MB |
| 像素上限 | 8000 × 8000 px |
| 建议尺寸 | 最长边 ≤ 1568 px，总像素 ≤ 1.15 百万 |

---

## 会话管理

```typescript
// 获取 session ID
let sessionId: string;
for await (const msg of query({ prompt: "..." })) {
  if (msg.type === "result") sessionId = msg.session_id;
}

// 恢复指定会话（continue 场景）
for await (const msg of query({
  prompt: "继续之前的工作",
  options: { resume: sessionId }
})) { ... }

// 继续最近的会话
for await (const msg of query({
  prompt: "继续",
  options: { continue: true }
})) { ... }

// 分叉会话（从某个点创建分支）
for await (const msg of query({
  prompt: "尝试另一种方案",
  options: { resume: sessionId, forkSession: true }
})) { ... }
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
    outputFormat: {
      type: "json_schema",
      schema: z.toJSONSchema(schema),
    }
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
| `"default"` | 未匹配的工具需要审批 |
| `"acceptEdits"` | 自动批准文件编辑操作 |
| `"bypassPermissions"` | 自动批准所有工具（谨慎使用） |
| `"plan"` | 仅规划不执行 |
| `"dontAsk"` | 仅允许 allowedTools 中的工具，其余拒绝 |

---

## 内置工具

| 工具 | 用途 |
|------|------|
| `Read` | 读取文件 |
| `Write` | 创建文件 |
| `Edit` | 编辑现有文件 |
| `Bash` | 执行终端命令 |
| `Glob` | 按模式搜索文件 |
| `Grep` | 搜索文件内容 |
| `WebSearch` | 网络搜索 |
| `WebFetch` | 获取网页内容 |
| `Agent` | 调用子 Agent |
| `NotebookEdit` | 编辑 Jupyter 笔记本 |

---

## Subagents（子 Agent）

Claude Agent SDK 内置了子 Agent 机制，通过 `agents` 配置定义专门的子 Agent，由 Claude 自行决定何时调用。

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
        description: "性能审查专家，识别性能瓶颈和优化机会",
        prompt: "你是性能审查专家...",
        tools: ["Read", "Grep", "Glob", "Bash"],
        model: "sonnet",
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
| `model` | `string` | 否 | 模型覆盖：opus / sonnet / haiku / inherit |
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
    allowedTools: ["mcp__github__*"],  // 通配符授权
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

---

## 自定义工具

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
    return {
      content: [{ type: "text", text: `温度：${data.current.temperature_2m}°C` }],
    };
  }
);

const server = createSdkMcpServer({
  name: "weather",
  version: "1.0.0",
  tools: [getTemperature],
});
```

---

## Hooks（事件钩子）

在关键执行节点插入自定义逻辑：

| Hook | 触发时机 |
|------|---------|
| `PreToolUse` | 工具执行前（可拦截/修改） |
| `PostToolUse` | 工具执行后 |
| `Stop` | 执行停止时 |
| `SubagentStart` | 子 Agent 启动 |
| `SubagentStop` | 子 Agent 完成 |

示例：禁止修改 .env 文件：

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

---

## 消息类型

`query()` 返回的消息流包含以下类型：

| 类型 | 说明 |
|------|------|
| `system` (subtype: `init`) | 会话初始化，包含 MCP 连接状态 |
| `assistant` | Claude 的推理和工具调用 |
| `tool_result` | 工具执行结果 |
| `result` | 最终结果 |

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

基于 Claude Agent SDK 的 Agent 封装与 Codex SDK 的 Thread 模型不同，这里通过 session 管理实现 run/continue：

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";
import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";

interface AgentStructuredResponse<T> {
  sessionId: string;
  data: T;
  cost?: number;
}

interface MyAgentOptions {
  model?: string;
  systemPrompt?: string;
  tools?: string[];
  permissionMode?: string;
}

export class MyAgent {
  private readonly model: string;
  private readonly systemPrompt: string;
  private readonly tools: string[];
  private readonly permissionMode: string;

  constructor(options: MyAgentOptions = {}) {
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

  private async execute(
    prompt: string,
    cwd?: string,
    sessionId?: string,
  ): Promise<AgentStructuredResponse<MyOutput>> {
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

## 编排说明

编排模式的设计思想和选择指南请参见 SKILL.md 中的"多 Agent 编排"章节。

Claude Agent SDK 编排要点：
- **Context 传递**：与 Codex 相同，通过序列化输出传递给下一个 Agent 的 prompt
- **会话恢复**：使用 `options.resume = sessionId` 恢复会话上下文；支持 `forkSession` 创建分支
- **并行执行**：多个 `query()` 调用可并行运行，各自持有独立 session
- **内置 subagent**：Claude Agent SDK 独有——通过 `agents` 配置声明子 Agent，Claude 自行决定何时调用，无需手动编写 Orchestrator 循环。适合动态决策场景