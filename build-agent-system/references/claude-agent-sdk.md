# Claude Agent SDK Reference

Claude Agent SDK (formerly Claude Code SDK) is Anthropic's Agent development SDK, with first-class support for both TypeScript and Python.

For the latest API documentation, use the `Anthropic Docs` skill to fetch official references.

---

## Installation

```bash
# TypeScript
npm install @anthropic-ai/claude-agent-sdk

# Python
pip install claude-agent-sdk
```

Environment variable: `ANTHROPIC_API_KEY=your-api-key`

Alternative Providers:
- Amazon Bedrock: `CLAUDE_CODE_USE_BEDROCK=1` + AWS credentials
- Google Vertex AI: `CLAUDE_CODE_USE_VERTEX=1` + GCP credentials

---

## Core API

### query()

Main entry function, returns an async message stream:

**TypeScript:**
```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const message of query({
  prompt: "Analyze the architecture of this repository",
  options: {
    model: "opus",
    systemPrompt: "You are a code analysis expert",
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

**Python:**
```python
from claude_agent_sdk import query, ClaudeAgentOptions

async for message in query(
    prompt="Analyze the architecture of this repository",
    options=ClaudeAgentOptions(
        model="opus",
        system_prompt="You are a code analysis expert",
        cwd="/path/to/repo",
        permission_mode="bypassPermissions",
        allowed_tools=["Read", "Glob", "Grep"],
        max_turns=10,
    )
):
    if message.type == "result":
        print(message.result)
```

### Main Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `prompt` | `string \| AsyncIterable<SDKUserMessage>` | Task description, supports text or multimodal message stream |
| `model` | `string` | Model: opus / sonnet / haiku |
| `systemPrompt` | `string` | System prompt |
| `cwd` | `string` | Working directory |
| `allowedTools` | `string[]` | Tools allowed to use |
| `disallowedTools` | `string[]` | Tools not allowed to use |
| `permissionMode` | `string` | Permission mode |
| `maxTurns` | `number` | Maximum number of iterations |
| `outputFormat` | `object` | Structured output schema |
| `mcpServers` | `object` | MCP server configuration |
| `agents` | `object` | Sub-Agent definitions |
| `hooks` | `object` | Event hooks |
| `continue` | `boolean` | Continue the most recent session |
| `resume` | `string` | Resume a specific session by session ID |
| `forkSession` | `boolean` | Fork from an existing session |

---

## Image Input

In addition to strings, `prompt` also supports `AsyncIterable<SDKUserMessage>`, allowing multimodal messages containing images.

### SDKUserMessage Structure

```typescript
type SDKUserMessage = {
  type: "user";
  message: MessageParam;          // { role: "user", content: string | ContentBlockParam[] }
  parent_tool_use_id: string | null;
};
```

`message.content` array can mix `ImageBlockParam` and `TextBlockParam`:

```typescript
// Image content block
interface ImageBlockParam {
  type: "image";
  source: Base64ImageSource | URLImageSource;
}

interface Base64ImageSource {
  type: "base64";
  media_type: "image/jpeg" | "image/png" | "image/gif" | "image/webp";
  data: string;  // base64 encoded
}

interface URLImageSource {
  type: "url";
  url: string;
}
```

### Example

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
          text: "Describe the content in this image",
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

The URL approach is more concise — reference online images directly:

```typescript
content: [
  {
    type: "image",
    source: { type: "url", url: "https://example.com/photo.jpg" },
  },
  { type: "text", text: "Analyze this image" },
]
```

### Format and Limits

| Item | Limit |
|------|-------|
| Supported formats | JPEG, PNG, GIF, WebP |
| Max size per image | ≤ 5 MB |
| Pixel limit | 8000 × 8000 px |
| Recommended size | Longest side ≤ 1568 px, total pixels ≤ 1.15 million |

---

## Session Management

```typescript
// Get session ID
let sessionId: string;
for await (const msg of query({ prompt: "..." })) {
  if (msg.type === "result") sessionId = msg.session_id;
}

// Resume a specific session (continue scenario)
for await (const msg of query({
  prompt: "Continue the previous work",
  options: { resume: sessionId }
})) { ... }

// Continue the most recent session
for await (const msg of query({
  prompt: "Continue",
  options: { continue: true }
})) { ... }

// Fork a session (create a branch from a point)
for await (const msg of query({
  prompt: "Try a different approach",
  options: { resume: sessionId, forkSession: true }
})) { ... }
```

---

## Structured Output

**TypeScript (Zod):**
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
  prompt: "Review this code",
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

**Python (Pydantic):**
```python
from pydantic import BaseModel

class ReviewOutput(BaseModel):
    summary: str
    issues: list[dict]
    passed: bool

async for msg in query(
    prompt="Review this code",
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

## Permission Modes

| Mode | Behavior |
|------|----------|
| `"default"` | Unmatched tools require approval |
| `"acceptEdits"` | Auto-approve file edit operations |
| `"bypassPermissions"` | Auto-approve all tools (use with caution) |
| `"plan"` | Plan only, no execution |
| `"dontAsk"` | Only allow tools in allowedTools, reject the rest |

---

## Built-in Tools

| Tool | Purpose |
|------|---------|
| `Read` | Read files |
| `Write` | Create files |
| `Edit` | Edit existing files |
| `Bash` | Execute terminal commands |
| `Glob` | Search files by pattern |
| `Grep` | Search file contents |
| `WebSearch` | Web search |
| `WebFetch` | Fetch web page content |
| `Agent` | Invoke sub-Agent |
| `NotebookEdit` | Edit Jupyter notebooks |

---

## Subagents

Claude Agent SDK has a built-in subagent mechanism. Define specialized sub-Agents through the `agents` configuration, and Claude will decide when to invoke them on its own.

```typescript
for await (const msg of query({
  prompt: "Comprehensively review this project's code quality",
  options: {
    allowedTools: ["Read", "Grep", "Glob", "Agent"],
    agents: {
      "security-reviewer": {
        description: "Security review expert, checks for security vulnerabilities in code",
        prompt: `You are a security review expert, focusing on:
- SQL injection, XSS, and other OWASP Top 10 vulnerabilities
- Sensitive information leaks
- Missing permission checks`,
        tools: ["Read", "Grep", "Glob"],
        model: "opus",
      },
      "perf-reviewer": {
        description: "Performance review expert, identifies performance bottlenecks and optimization opportunities",
        prompt: "You are a performance review expert...",
        tools: ["Read", "Grep", "Glob", "Bash"],
        model: "sonnet",
      },
    }
  }
})) { ... }
```

### AgentDefinition Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | `string` | Yes | Describes the Agent's purpose (Claude uses this to decide whether to invoke it) |
| `prompt` | `string` | Yes | System Prompt |
| `tools` | `string[]` | No | Allowed tools; inherits all if unspecified |
| `model` | `string` | No | Model override: opus / sonnet / haiku / inherit |
| `skills` | `string[]` | No | Available skills |
| `mcpServers` | `array` | No | Available MCP servers |

---

## MCP Servers

Connect to external systems via MCP (Model Context Protocol):

```typescript
for await (const msg of query({
  prompt: "List recent GitHub issues",
  options: {
    mcpServers: {
      github: {
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-github"],
        env: { GITHUB_TOKEN: process.env.GITHUB_TOKEN },
      }
    },
    allowedTools: ["mcp__github__*"],  // wildcard authorization
  }
})) { ... }
```

Tool naming convention: `mcp__{server_name}__{tool_name}`

Transport types:
| Type | Use Case | Configuration |
|------|----------|---------------|
| stdio (default) | Local process | `{ command, args }` |
| http | Cloud API | `{ type: "http", url }` |
| sse | Streaming endpoint | `{ type: "sse", url }` |

---

## Custom Tools

```typescript
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const getTemperature = tool(
  "get_temperature",
  "Get the current temperature at a specified location",
  {
    latitude: z.number().describe("Latitude"),
    longitude: z.number().describe("Longitude"),
  },
  async (args) => {
    const resp = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${args.latitude}&longitude=${args.longitude}&current=temperature_2m`);
    const data = await resp.json();
    return {
      content: [{ type: "text", text: `Temperature: ${data.current.temperature_2m}°C` }],
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

## Hooks (Event Hooks)

Insert custom logic at key execution points:

| Hook | Trigger Timing |
|------|----------------|
| `PreToolUse` | Before tool execution (can intercept/modify) |
| `PostToolUse` | After tool execution |
| `Stop` | When execution stops |
| `SubagentStart` | When a sub-Agent starts |
| `SubagentStop` | When a sub-Agent completes |

Example: Prevent modification of .env files:

```typescript
const protectEnv = async (input, toolUseID, { signal }) => {
  const filePath = input.tool_input?.file_path as string;
  if (filePath?.endsWith(".env")) {
    return {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Modification of .env files is not allowed",
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

## Message Types

The message stream returned by `query()` contains the following types:

| Type | Description |
|------|-------------|
| `system` (subtype: `init`) | Session initialization, includes MCP connection status |
| `assistant` | Claude's reasoning and tool calls |
| `tool_result` | Tool execution results |
| `result` | Final result |

### Result Subtypes

| Subtype | Meaning |
|---------|---------|
| `success` | Task completed |
| `error_during_execution` | Execution error |
| `error_max_turns` | Reached iteration limit |
| `error_max_budget_usd` | Reached budget limit |
| `error_max_structured_output_retries` | Structured output parse failure |
| `error_interrupted` | Cancelled by user or intercepted by hook |

---

## Agent Class Template

Unlike Codex SDK's Thread model, Claude Agent SDK manages state through sessions. The run/continue pattern is implemented via session IDs:

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

## Orchestration Notes

For orchestration pattern design philosophy and selection guide, refer to the "How to Build Agent System" section in SKILL.md.

Claude Agent SDK orchestration key points:
- **Context passing**: Same as Codex — serialize output and pass it to the next Agent's prompt
- **Session resume**: Use `options.resume = sessionId` to restore session context; supports `forkSession` for branching
- **Parallel execution**: Multiple `query()` calls can run in parallel, each holding an independent session
- **Built-in subagent**: Unique to Claude Agent SDK — declare sub-Agents through the `agents` configuration, and Claude decides when to invoke them, no need to manually write an Orchestrator loop. Ideal for dynamic decision scenarios