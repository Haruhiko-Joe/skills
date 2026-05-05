# Claude Agent SDK Reference

Claude Agent SDK is Anthropic's Agent development SDK, with first-class support for both TypeScript and Python.

---

## Installation

```bash
# TypeScript
npm install @anthropic-ai/claude-agent-sdk

# Python
pip install claude-agent-sdk
```

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

### startup() (TypeScript)

Pre-warms the CLI subprocess for faster first queries. Call once at application start:

```typescript
import { startup } from "@anthropic-ai/claude-agent-sdk";

const warm = await startup({ options: { maxTurns: 3 } });

// Subsequent queries start faster
for await (const message of warm.query("What files are here?")) {
  console.log(message);
}
```

### ClaudeSDKClient (Python)

For multi-turn conversations with automatic session management. The client tracks session state internally — each `query()` call continues the same session:

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions, AssistantMessage, TextBlock

async with ClaudeSDKClient(options=ClaudeAgentOptions(
    allowed_tools=["Read", "Edit", "Glob", "Grep"],
)) as client:
    # First query — captures session ID internally
    await client.query("Analyze the auth module")
    async for message in client.receive_response():
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)

    # Second query — automatically continues same session
    await client.query("Now refactor it to use JWT")
    async for message in client.receive_response():
        ...

    # Control methods
    await client.interrupt()                          # interrupt execution
    await client.set_model("sonnet")                  # switch model
    await client.set_permission_mode("acceptEdits")   # change permissions
    await client.rewind_files(user_message_id)        # revert file changes
```

Key difference from `query()`:

| Feature | `query()` | `ClaudeSDKClient` |
|---------|-----------|-------------------|
| Session | New each time | Reuses same session |
| Multi-turn | Via `resume` option | Automatic |
| Interrupts | Not supported | `await client.interrupt()` |
| Best for | One-off tasks, pipelines | Interactive apps, multi-turn |

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
| `maxBudgetUsd` | `number` | Maximum USD budget for a query |
| `outputFormat` | `object` | Structured output schema |
| `mcpServers` | `object` | MCP server configuration |
| `agents` | `object` | Sub-Agent definitions |
| `hooks` | `object` | Event hooks |
| `thinking` | `object` | Thinking config: `{ type: "adaptive" \| "enabled" \| "disabled" }` |
| `effort` | `string` | Reasoning depth: low / medium / high / xhigh / max |
| `continue` | `boolean` | Continue the most recent session |
| `resume` | `string` | Resume a specific session by session ID |
| `forkSession` | `boolean` | Fork from an existing session |
| `persistSession` | `boolean` | Persist session to disk (TS only, default true) |
| `enableFileCheckpointing` | `boolean` | Track and revert file changes |
| `sandbox` | `object` | Sandbox settings |
| `tools` | `array \| object` | Tool config, supports presets: `{ type: "preset", preset: "claude_code" }` |
| `settingSources` | `array` | Restrict which config sources load |
| `plugins` | `array` | Plugin configurations |
| `sessionStore` | `object` | Custom session storage backend |
| `fallbackModel` | `string` | Fallback model on failure (Python) |

---

## Thinking Configuration

Control the model's reasoning behavior:

```typescript
// Adaptive (default) — model decides when to think
options: { thinking: { type: "adaptive" } }

// Enabled with token budget
options: { thinking: { type: "enabled", budget_tokens: 20000 } }

// Disabled
options: { thinking: { type: "disabled" } }

// Effort level (alternative to manual thinking config)
options: { effort: "high" }  // low | medium | high | xhigh | max
```

Opus 4.7 requires SDK v0.2.111+ and uses `thinking: { type: "adaptive" }` (not the old `enabled` type).

---

## Image Input

`prompt` supports `AsyncIterable<SDKUserMessage>` for multimodal messages containing images:

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
        { type: "text", text: "Describe the content in this image" },
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

URL approach:
```typescript
content: [
  { type: "image", source: { type: "url", url: "https://example.com/photo.jpg" } },
  { type: "text", text: "Analyze this image" },
]
```

| Item | Limit |
|------|-------|
| Supported formats | JPEG, PNG, GIF, WebP |
| Max size per image | ≤ 5 MB |
| Pixel limit | 8000 × 8000 px |

---

## Session Management

```typescript
// Get session ID from result
let sessionId: string;
for await (const msg of query({ prompt: "..." })) {
  if (msg.type === "result") sessionId = msg.session_id;
}

// Resume a specific session
for await (const msg of query({
  prompt: "Continue the previous work",
  options: { resume: sessionId }
})) { ... }

// Continue the most recent session
for await (const msg of query({
  prompt: "Continue",
  options: { continue: true }
})) { ... }

// Fork a session (create a branch)
for await (const msg of query({
  prompt: "Try a different approach",
  options: { resume: sessionId, forkSession: true }
})) { ... }
```

### Session Utility Functions

**TypeScript:**
```typescript
import { listSessions, getSessionMessages, getSessionInfo, renameSession, tagSession } from "@anthropic-ai/claude-agent-sdk";

const sessions = await listSessions();
const messages = await getSessionMessages(sessionId);
const info = await getSessionInfo(sessionId);
await renameSession(sessionId, "Auth refactor");
await tagSession(sessionId, "needs-review");  // pass null to clear
```

**Python:**
```python
from claude_agent_sdk import list_sessions, get_session_messages, get_session_info, rename_session, tag_session

sessions = list_sessions(directory="/path/to/project", limit=10)
messages = get_session_messages(session_id)
info = get_session_info(session_id)
rename_session(session_id, "Auth refactor")
tag_session(session_id, "needs-review")
```

Session info fields: `session_id`, `summary`, `last_modified`, `custom_title`, `first_prompt`, `git_branch`, `cwd`, `tag`, `created_at`.

---

## Query Object Methods (TypeScript)

`query()` returns a Query object with control methods beyond iterating messages:

```typescript
const q = query({ prompt: "...", options: { ... } });

// Iterate messages
for await (const msg of q) { ... }

// Control methods
await q.interrupt();                        // interrupt current execution
await q.rewindFiles(userMessageId);         // revert file changes to a point
await q.setPermissionMode("plan");          // change permission mode mid-query
await q.setModel("sonnet");                 // switch model mid-query

// Introspection
const initResult = await q.initializationResult();
const commands = await q.supportedCommands();
const models = await q.supportedModels();
const agents = await q.supportedAgents();
const mcpStatus = await q.mcpServerStatus();

// MCP management
await q.reconnectMcpServer("github");
await q.toggleMcpServer("github", true);
await q.setMcpServers({ ... });

// Background task control
await q.stopTask(taskId);

// Cleanup
q.close();
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
    outputFormat: { type: "json_schema", schema: z.toJSONSchema(schema) }
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
| `"default"` | Unmatched tools require approval (needs `canUseTool` callback) |
| `"acceptEdits"` | Auto-approve file edits and common filesystem commands |
| `"bypassPermissions"` | Auto-approve all tools (use with caution) |
| `"plan"` | Plan only, no execution |
| `"dontAsk"` | Only allow tools in allowedTools, deny the rest |
| `"auto"` | Model classifier decides approval (TypeScript only) |

---

## Built-in Tools

| Tool | Purpose |
|------|---------|
| `Read` | Read files |
| `Write` | Create files |
| `Edit` | Edit existing files |
| `Bash` | Execute terminal commands |
| `Monitor` | Watch background scripts, react to output events |
| `Glob` | Search files by pattern |
| `Grep` | Search file contents |
| `WebSearch` | Web search |
| `WebFetch` | Fetch web page content |
| `Agent` | Invoke sub-Agent |
| `NotebookEdit` | Edit Jupyter notebooks |
| `AskUserQuestion` | Ask user clarifying questions with options |

---

## Subagents

Built-in subagent mechanism — define specialized sub-Agents through `agents` config, Claude decides when to invoke them:

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
        description: "Performance review expert, identifies performance bottlenecks",
        prompt: "You are a performance review expert...",
        tools: ["Read", "Grep", "Glob", "Bash"],
        model: "sonnet",
        maxTurns: 5,
        background: true,
      },
    }
  }
})) { ... }
```

### AgentDefinition Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | `string` | Yes | Describes the Agent's purpose (Claude uses this to decide when to invoke) |
| `prompt` | `string` | Yes | System Prompt |
| `tools` | `string[]` | No | Allowed tools; inherits all if unspecified |
| `disallowedTools` | `string[]` | No | Tools this agent cannot use |
| `model` | `string` | No | Model override: opus / sonnet / haiku |
| `maxTurns` | `number` | No | Maximum turns for this sub-agent |
| `background` | `boolean` | No | Run as background task (notifies via `TaskCompleted` hook) |
| `initialPrompt` | `string` | No | Auto-submitted first turn prompt |
| `memory` | `string` | No | Memory scope: "user" / "project" / "local" |
| `effort` | `string` | No | Effort level override |
| `permissionMode` | `string` | No | Permission mode override |
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
    allowedTools: ["mcp__github__*"],
  }
})) { ... }
```

Tool naming: `mcp__{server_name}__{tool_name}`

Transport types:
| Type | Use Case | Configuration |
|------|----------|---------------|
| stdio (default) | Local process | `{ command, args }` |
| http | Cloud API | `{ type: "http", url }` |
| sse | Streaming endpoint | `{ type: "sse", url }` |
| sdk | In-process server | `{ type: "sdk", name, instance }` |

---

## Custom Tools

**TypeScript:**
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
    return { content: [{ type: "text", text: `Temperature: ${data.current.temperature_2m}°C` }] };
  }
);

const server = createSdkMcpServer({
  name: "weather",
  version: "1.0.0",
  tools: [getTemperature],
});

// Use as in-process MCP server
for await (const msg of query({
  prompt: "What's the temperature in Tokyo?",
  options: { mcpServers: { weather: { type: "sdk", name: "weather", instance: server } } }
})) { ... }
```

**Python:**
```python
from claude_agent_sdk import tool, create_sdk_mcp_server, ClaudeAgentOptions

@tool("get_temperature", "Get current temperature at a location", {
    "latitude": {"type": "number", "description": "Latitude"},
    "longitude": {"type": "number", "description": "Longitude"},
})
async def get_temperature(args):
    # fetch temperature...
    return {"content": [{"type": "text", "text": f"Temperature: {temp}°C"}]}

@tool("get_humidity", "Get current humidity", {"latitude": float, "longitude": float})
async def get_humidity(args):
    return {"content": [{"type": "text", "text": f"Humidity: {humidity}%"}]}

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

## Hooks (Event Hooks)

Insert custom logic at key execution points:

| Hook | Trigger Timing |
|------|----------------|
| `PreToolUse` | Before tool execution (can intercept/modify/deny) |
| `PostToolUse` | After successful tool execution |
| `PostToolUseFailure` | After tool execution fails |
| `PostToolBatch` | After a batch of tool calls completes |
| `Notification` | On notification events |
| `UserPromptSubmit` | When user submits a prompt |
| `SessionStart` | When a session starts |
| `SessionEnd` | When a session ends |
| `Stop` | When execution stops |
| `SubagentStart` | When a sub-Agent starts |
| `SubagentStop` | When a sub-Agent completes |
| `PreCompact` | Before context compaction |
| `PermissionRequest` | When a permission decision is needed |
| `TaskCompleted` | When a background task completes |
| `TeammateIdle` | When a teammate agent becomes idle |

### PreToolUse Hook Output

```typescript
type PreToolUseOutput = {
  permissionDecision?: "allow" | "deny" | "ask" | "defer";
  permissionDecisionReason?: string;
  updatedInput?: Record<string, unknown>;   // modify tool input
  additionalContext?: string;               // inject context
};
```

### Example: Prevent modification of .env files

**TypeScript:**
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

**Python:**
```python
from claude_agent_sdk import query, ClaudeAgentOptions, HookMatcher

async def protect_env(input_data, tool_use_id, context):
    file_path = input_data.get("tool_input", {}).get("file_path", "")
    if file_path.endswith(".env"):
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "Modification of .env files is not allowed",
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

## Message Types

The message stream returned by `query()` contains:

| Type | Description |
|------|-------------|
| `system` (subtype: `init`) | Session initialization |
| `assistant` | Claude's reasoning and tool calls |
| `tool_result` | Tool execution results |
| `result` | Final result |
| `rate_limit` | Rate limit events |
| `task_started` | Background task started |
| `task_progress` | Background task progress |
| `task_notification` | Background task completed/failed |

### Result Message Fields

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | `string` | Session identifier |
| `subtype` | `string` | Result subtype |
| `result` | `string` | Text result |
| `structured_output` | `object` | Parsed structured output (if outputFormat used) |
| `duration_ms` | `number` | Total execution time |
| `num_turns` | `number` | Number of turns taken |
| `total_cost_usd` | `number` | Total cost in USD |
| `usage` | `object` | Token usage: `{ input_tokens, output_tokens, cache_*_input_tokens }` |
| `modelUsage` | `object` | Per-model usage breakdown |
| `deferred_tool_use` | `object` | Deferred tool calls |
| `permission_denials` | `array` | Permission denials that occurred |

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

Claude Agent SDK manages state through sessions. The run/continue pattern is implemented via session IDs:

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

## Orchestration Notes

For orchestration pattern design and selection guide, refer to the "How to Build Agent System" section in SKILL.md.

Claude Agent SDK orchestration key points:
- **Context passing**: Serialize output and pass to the next Agent's prompt
- **Session resume**: Use `options.resume = sessionId` to restore context; `forkSession` for branching
- **Parallel execution**: Multiple `query()` calls run in parallel, each holding an independent session
- **Built-in subagent**: Declare sub-Agents through `agents` config — Claude decides when to invoke them, no manual Orchestrator loop needed
- **Background subagents**: Set `background: true` in AgentDefinition for concurrent execution; monitor via `TaskCompleted` hook
- **Multi-turn client**: Use `ClaudeSDKClient` (Python) for interactive multi-turn workflows with interrupt/steer capability
