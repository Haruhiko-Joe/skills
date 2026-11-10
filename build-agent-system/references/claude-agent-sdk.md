# Claude Agent SDK Reference

Claude Agent SDK is Claude Code packaged as a library: the agent loop, built-in tools, permissions, hooks, subagents, and sessions, driven from TypeScript or Python.

> Checked on 2026-11-10 against `@anthropic-ai/claude-agent-sdk` 0.3.319 and `claude-agent-sdk` (Python) 0.2.179 (Claude Code 2.1.319), using the Agent SDK docs at code.claude.com/docs/en/agent-sdk and the SDK CHANGELOGs. TypeScript 0.3.320 and 0.3.321 change no options, message types, hooks, or permission modes per the CHANGELOG.

---

## Installation

```bash
# TypeScript (Node 18.14+); zod 4 is used for tool and output schemas
npm install @anthropic-ai/claude-agent-sdk zod

# Python (3.10+)
pip install claude-agent-sdk
```

Both packages bundle a native Claude Code binary (TS: via npm optional dependencies, so `--omit=optional` drops it; Python: in the platform wheel). No separate Claude Code install is needed; `pathToClaudeCodeExecutable` (TS) / `cli_path` (Python) point to another binary.

Auth: `ANTHROPIC_API_KEY` (not read from `.env` automatically), or `CLAUDE_CODE_USE_BEDROCK=1` / `CLAUDE_CODE_USE_VERTEX=1` / `CLAUDE_CODE_USE_FOUNDRY=1` / `CLAUDE_CODE_USE_ANTHROPIC_AWS=1` with that provider's credentials. Products built on the SDK may not offer claude.ai login unless Anthropic approved it.

TS also exports `@anthropic-ai/claude-agent-sdk/core`: same `query()`, `startup()`, `prewarm()`, `tool()`, `createSdkMcpServer()` and session mutations, without the session listing/reading helpers, for apps that bundle the SDK. Import from the root or `/core` in one process, not both.

---

## Core API

### query()

Main entry point. Returns an async stream of messages (TS: a `Query` object that is also an `AsyncGenerator<SDKMessage>`).

**TypeScript:**
```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const message of query({
  prompt: "Analyze the architecture of this repository",
  options: {
    model: "claude-opus-5-5",
    effort: "high",
    systemPrompt: "You are a code analysis expert",
    cwd: "/path/to/repo",
    allowedTools: ["Read", "Glob", "Grep"],
    permissionMode: "dontAsk",
    maxTurns: 10,
  },
})) {
  if (message.type === "result") {
    if (message.subtype === "success") console.log(message.result);
    console.log("Session ID:", message.session_id, "Cost:", message.total_cost_usd);
  }
}
```

**Python:** messages are dataclasses; match with `isinstance`, not `.type`.
```python
from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage

async for message in query(
    prompt="Analyze the architecture of this repository",
    options=ClaudeAgentOptions(
        model="claude-opus-5-5",
        effort="high",
        system_prompt="You are a code analysis expert",
        cwd="/path/to/repo",
        allowed_tools=["Read", "Glob", "Grep"],
        permission_mode="dontAsk",
        max_turns=10,
    ),
):
    if isinstance(message, ResultMessage):
        print(message.subtype, message.result, message.session_id, message.total_cost_usd)
```

A one-shot `query()` **throws/raises after yielding an error result** (TS: an `Error`; Python: `ResultError`, a `ProcessError` subclass with `subtype`, `errors`, `terminal_reason`). Read the result message inside the loop, then catch.

Prompt forms:
- `string`: one-shot. The process exits after the turn (and after any background subagents it waits for).
- `AsyncIterable<SDKUserMessage>` (Python: async iterable of dicts): streaming input. The session stays open while the iterable is open, so you can push more user messages, use the `Query` control methods, and receive a separate `result` per turn (including turns started by finished background tasks).

### startup() / prewarm() (TypeScript)

`startup()` spawns the CLI and finishes the initialize handshake before you have a prompt:

```typescript
import { startup } from "@anthropic-ai/claude-agent-sdk";

const warm = await startup({ options: { cwd: "/repo", maxTurns: 3 } });
const q = warm.query("What files are here?");   // callable once per WarmQuery
for await (const message of q) { /* ... */ }
```

`prewarm()` (alpha) parks a spare process before the session's folder is known; `spare.claim({ prompt, options: { cwd, model, ... } })` binds it later. Use it for hosts that start many sessions.

### ClaudeSDKClient (Python)

Stateful multi-turn client: each `client.query()` continues the same session.

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions, AssistantMessage, TextBlock

async with ClaudeSDKClient(options=ClaudeAgentOptions(
    allowed_tools=["Read", "Edit", "Glob", "Grep"],
)) as client:
    await client.query("Analyze the auth module")
    async for message in client.receive_response():   # ends after the ResultMessage
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)

    await client.query("Now refactor it to use JWT")  # same session
    async for message in client.receive_response():
        ...

    # Control methods
    await client.interrupt()
    await client.set_model("claude-fable-5-2")
    await client.set_permission_mode("acceptEdits")
    await client.stop_task(task_id)                   # stop a background task
    await client.get_mcp_status()
    await client.get_context_usage()
    await client.rewind_files(user_message_id)        # needs enable_file_checkpointing=True
```

Use the client within one async context (it holds an anyio task group from `connect()` to `disconnect()`).

| Feature | `query()` | `ClaudeSDKClient` (Py) / streaming-input `query()` (TS) |
|---------|-----------|-------------------|
| Session | New per call (unless `resume`/`continue`) | One session across turns |
| Multi-turn | `resume: sessionId` | `client.query()` / push to the input iterable |
| Interrupt, set model/mode mid-run | No | Yes |
| Best for | Pipelines, one-off tasks | Interactive apps, long-lived sessions |

TS has no client class: use `query()` with an `AsyncIterable<SDKUserMessage>` prompt for the same behavior, or `continue: true` / `resume` across calls.

### Main Configuration Options

TS names shown; Python uses snake_case (`allowed_tools`, `permission_mode`, `max_budget_usd`, ...). Exceptions noted.

| Option | Type | Description |
|--------|------|-------------|
| `model` | `string` | Full ID (`claude-opus-5-5`) or alias (`fable`, `opus`, `sonnet`, `haiku`) |
| `fallbackModel` | `string` | Model(s) to try if the primary is overloaded/unavailable (both SDKs) |
| `effort` | `'low' \| 'medium' \| 'high' \| 'xhigh' \| 'max'` | Reasoning depth (see Thinking & Effort) |
| `thinking` | `ThinkingConfig` | `{type:'adaptive'}` etc. `maxThinkingTokens` is deprecated |
| `systemPrompt` | `string \| string[] \| {type:'custom',...} \| {type:'preset', preset:'claude_code', append?, excludeDynamicSections?}` | Custom prompt, or Claude Code's prompt with additions. Python: `str`, preset/custom dict, or `{"type":"file","path":...}` |
| `cwd` | `string` | Working directory (default: process cwd) |
| `additionalDirectories` | `string[]` | Extra accessible dirs. Python: `add_dirs` |
| `tools` | `string[] \| {type:'preset', preset:'claude_code'}` | **Which built-in tools exist.** `[]` removes all built-ins |
| `allowedTools` | `string[]` | **Pre-approved** tools/rules (`"Read"`, `"Bash(npm test *)"`, `"mcp__github__*"`). Does not restrict availability |
| `disallowedTools` | `string[]` | Bare name removes the tool; scoped rule (`"Bash(rm *)"`) denies matching calls in every mode |
| `permissionMode` | `PermissionMode` | See Permission Modes |
| `allowDangerouslySkipPermissions` | `boolean` | Required with `bypassPermissions` (TS) |
| `canUseTool` | callback | Runtime approval for calls nothing else decided |
| `permissionPrompts` | `'host' \| 'none'` | `'none'`: never call `canUseTool`, deny instead (TS) |
| `maxTurns` | `number` | Max model round-trips |
| `maxBudgetUsd` | `number` | Spend cap for this call, subagents included |
| `taskBudget` | `{ total: number }` | Model-visible token budget (alpha, `task-budgets` beta) |
| `outputFormat` | `{ type: 'json_schema', schema }` | Structured output |
| `mcpServers` | `Record<string, McpServerConfig>` | MCP servers. Python also accepts a config file path/JSON string |
| `strictMcpConfig` | `boolean` | Ignore `.mcp.json`, settings, and plugin MCP servers |
| `agents` | `Record<string, AgentDefinition>` | Programmatic subagents |
| `agent` | `string` | Run the main thread as a named agent (TS) |
| `hooks` | `Partial<Record<HookEvent, HookCallbackMatcher[]>>` | Callback hooks |
| `continue` | `boolean` | Continue the most recent session in `cwd`. Python: `continue_conversation` |
| `resume` | `string` | Resume a session by ID |
| `forkSession` | `boolean` | With `resume`: write to a new session ID |
| `sessionId` | `string` (UUID) | Use this ID for the new session (or for the fork) |
| `resumeSessionAt` | `string` | With `resume`: truncate history after this message UUID |
| `persistSession` | `boolean` | `false` = no transcript on disk (TS only) |
| `sessionStore` | `SessionStore` | Mirror transcripts to your storage so other hosts can resume (both SDKs) |
| `title` | `string` | Session title (TS) |
| `enableFileCheckpointing` | `boolean` | Track file edits for `rewindFiles()` |
| `settingSources` | `('user' \| 'project' \| 'local')[]` | Which settings files load. Omitted = all. `[]` = isolation. Needs `'project'` for CLAUDE.md |
| `settings` | `string \| Settings` | Extra flag-layer settings (TS also takes an object; Python a path or JSON string) |
| `skills` | `string[] \| 'all'` | Skills enabled for the main session (replaces putting `'Skill'` in `allowedTools`) |
| `plugins` | `{ type: 'local', path }[]` | Load plugins |
| `sandbox` | `SandboxSettings` | OS-level sandbox for Bash (filesystem/network/credentials) |
| `env` | `Record<string, string>` | TS: **replaces** the subprocess env (spread `process.env`). Python: merged over the inherited env |
| `includePartialMessages` | `boolean` | Emit `stream_event` deltas |
| `forwardSubagentText` | `boolean` | Forward subagent text/thinking, not just tool blocks |
| `agentProgressSummaries` | `boolean` | Periodic one-line subagent summaries on `task_progress` (TS) |
| `includeHookEvents` | `boolean` | Emit hook lifecycle system messages |
| `abortController` | `AbortController` | Cancel the query (TS) |
| `stderr` | `(data: string) => void` | CLI stderr callback |

---

## Thinking & Effort Configuration

Current models think adaptively and are steered with `effort`:

| Model | ID | Thinking | Effort |
|-------|----|----------|--------|
| Claude Fable 5.2 | `claude-fable-5-2` | Always on | `low`–`max`, API default `high` |
| Claude Opus 5.5 | `claude-opus-5-5` | Always on, cannot be disabled | `low`–`max`, API default `medium` |
| Claude Sonnet 5.5 (not used by this skill) | `claude-sonnet-5-5` | On by default, `disabled` not accepted | `low`–`max`, default `high` |
| Claude Haiku 5.5 (not used by this skill) | `claude-haiku-5-5` | On by default | `low`–`max`, API default `medium` |

```typescript
// Current models: omit `thinking` (or pass adaptive) and set effort explicitly
options: { model: "claude-opus-5-5", effort: "xhigh" }

// Show readable thinking summaries (default display is "omitted": empty thinking blocks)
options: { thinking: { type: "adaptive", display: "summarized" } }

// Older models only (e.g. Haiku 4.5): fixed budget, or off
options: { thinking: { type: "enabled", budgetTokens: 20000 } }   // Python: {"type": "enabled", "budget_tokens": 20000}
options: { thinking: { type: "disabled" } }
```

- The Messages API rejects `{type: "disabled"}` and fixed budgets on Fable 5.2, Opus 5.5, and Sonnet 5.5. Don't send them for these models.
- Fable 5.2 ignores "think less" instructions at `medium` and above; lower `effort` instead. Most of its gain is present at `high`.
- `xhigh`/`high` suit long agentic coding; `low`/`medium` suit subagents doing narrow lookups. Set effort per subagent with `AgentDefinition.effort`.
- Change effort mid-session (TS, streaming input): `await q.applyFlagSettings({ effortLevel: "high" })`.
- Aliases (`opus`, `sonnet`, `haiku`, `fable`) resolve to whatever the bundled Claude Code maps them to; pin full IDs when reproducibility matters.

---

## Image Input

Send images through the streaming-input prompt; a string prompt cannot carry image attachments. Content blocks follow the Messages API `MessageParam` shape.

```typescript
import { query, type SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import fs from "node:fs";

const imageData = fs.readFileSync("/path/to/image.png").toString("base64");

async function* imagePrompt(): AsyncGenerator<SDKUserMessage> {
  yield {
    type: "user",
    message: {
      role: "user",
      content: [
        { type: "image", source: { type: "base64", media_type: "image/png", data: imageData } },
        { type: "text", text: "Describe the content in this image" },
      ],
    },
    parent_tool_use_id: null,
  };
}

for await (const msg of query({ prompt: imagePrompt(), options: { maxTurns: 1 } })) {
  if (msg.type === "result" && msg.subtype === "success") console.log(msg.result);
}
```

URL source: `{ type: "image", source: { type: "url", url: "https://example.com/photo.jpg" } }`.

Python: yield dicts of the same shape (`{"type": "user", "message": {...}, "parent_tool_use_id": None}`) from an async generator passed as `prompt`.

Formats: JPEG, PNG, GIF, WebP. Size and pixel limits are the Messages API's. Alternatively, put the image on disk and let Claude open it with the `Read` tool.

---

## Session Management

Sessions are JSONL transcripts under `~/.claude/projects/<encoded-cwd>/` (or `$CLAUDE_CONFIG_DIR/projects/`). They hold the conversation, not file state.

```typescript
// Session ID: on every message; read it from the result (or system/init)
let sessionId: string | undefined;
for await (const msg of query({ prompt: "..." })) {
  if (msg.type === "result") sessionId = msg.session_id;
}

// Resume a specific session
query({ prompt: "Continue the previous work", options: { resume: sessionId } });

// Continue the most recent session in cwd
query({ prompt: "Continue", options: { continue: true } });

// Fork: new session ID with a copy of the history; the original is untouched
query({ prompt: "Try a different approach", options: { resume: sessionId, forkSession: true } });

// Branch from an earlier point
query({ prompt: "...", options: { resume: sessionId, forkSession: true, resumeSessionAt: assistantMessageUuid } });

// Pre-assign the ID of a new session (useful for orchestrators)
query({ prompt: "...", options: { sessionId: crypto.randomUUID() } });
```

Resume looks the ID up beyond the current project directory, but only on the same machine. Across hosts, use a `sessionStore` adapter (resume from a matching `cwd`) or copy the `.jsonl` file.

### Session Utility Functions

**TypeScript** (all async):
```typescript
import {
  listSessions, getSessionInfo, getSessionMessages, renameSession, tagSession,
  forkSession, deleteSession, listSubagents, getSubagentMessages,
} from "@anthropic-ai/claude-agent-sdk";

const sessions = await listSessions({ dir: "/path/to/project", limit: 20 });
const info = await getSessionInfo(sessionId);                 // SDKSessionInfo | undefined
const messages = await getSessionMessages(sessionId, { limit: 50 });
await renameSession(sessionId, "Auth refactor");
await tagSession(sessionId, "needs-review");                  // null clears
const { sessionId: forkId } = await forkSession(sessionId, { upToMessageId, title: "Alt" });
await deleteSession(sessionId);
const agentIds = await listSubagents(sessionId);
const subMessages = await getSubagentMessages(sessionId, agentIds[0]);
```

**Python** (synchronous functions):
```python
from claude_agent_sdk import (
    list_sessions, get_session_info, get_session_messages, rename_session, tag_session,
    fork_session, delete_session, list_subagents, get_subagent_messages,
)

sessions = list_sessions(directory="/path/to/project", limit=20)
info = get_session_info(session_id)
messages = get_session_messages(session_id, limit=50)
rename_session(session_id, "Auth refactor")
tag_session(session_id, "needs-review")              # None clears
fork_id = fork_session(session_id, up_to_message_id=uuid, title="Alt").session_id
delete_session(session_id)
agent_ids = list_subagents(session_id)
sub_messages = get_subagent_messages(session_id, agent_ids[0])
```

`SDKSessionInfo` fields (TS camelCase / Python snake_case): `sessionId`, `summary`, `lastModified`, `fileSize`, `customTitle`, `firstPrompt`, `gitBranch`, `cwd`, `tag`, `createdAt`.

`sessionStore` mirrors transcripts to your backend (`append`/`load`/`listSessions`/`delete`); `InMemorySessionStore` is a reference implementation and `importSessionToStore()` (TS) / `import_session_to_store()` (Python) migrates local sessions.

---

## Query Object Methods (TypeScript)

`query()` returns a `Query`. Control methods need streaming input (an `AsyncIterable` prompt).

```typescript
const q = query({ prompt: inputStream, options: { ... } });

for await (const msg of q) { ... }

// Control
await q.interrupt();                        // stop the current turn
await q.setPermissionMode("acceptEdits");
await q.setModel("claude-fable-5-2");
await q.applyFlagSettings({ effortLevel: "high" });   // mid-session settings overlay
await q.streamInput(moreMessages);
await q.rewindFiles(userMessageId, { dryRun: true }); // needs enableFileCheckpointing

// Background tasks
await q.stopTask(taskId);                   // task_id from task_* messages
await q.backgroundTasks(toolUseId);         // move a foreground Bash/subagent to the background (omit the ID for all)

// Introspection
await q.initializationResult();
await q.supportedCommands();
await q.supportedModels();
await q.supportedAgents();
await q.mcpServerStatus();
await q.getContextUsage({ detail: "summary" });
await q.accountInfo();

// MCP / plugins
await q.reconnectMcpServer("github");
await q.toggleMcpServer("github", false);
await q.setMcpServers({ ... });             // replace dynamically added servers
await q.reloadPlugins();
await q.reloadSkills();

q.close();                                  // terminate the subprocess
```

---

## Structured Output

The agent can use tools as usual, then returns JSON validated against your schema (JSON Schema draft-07). On mismatch Claude Code re-prompts; after the retry limit the result subtype is `error_max_structured_output_retries`. The stream shows this as calls to an internal `StructuredOutput` tool.

**TypeScript (Zod 4):**
```typescript
import { z } from "zod";
import { query } from "@anthropic-ai/claude-agent-sdk";

const Review = z.object({
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
    outputFormat: { type: "json_schema", schema: z.toJSONSchema(Review, { target: "draft-7" }) },
  },
})) {
  if (msg.type === "result" && msg.subtype === "success" && msg.structured_output !== undefined) {
    const review = Review.parse(msg.structured_output);
  }
}
```

**Python (Pydantic):**
```python
from pydantic import BaseModel
from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage

class Issue(BaseModel):
    severity: str
    description: str

class ReviewOutput(BaseModel):
    summary: str
    issues: list[Issue]
    passed: bool

async for msg in query(
    prompt="Review this code",
    options=ClaudeAgentOptions(
        output_format={"type": "json_schema", "schema": ReviewOutput.model_json_schema()}
    ),
):
    if isinstance(msg, ResultMessage) and msg.subtype == "success" and msg.structured_output:
        result = ReviewOutput.model_validate(msg.structured_output)
```

Treat `success` without `structured_output` as a failure too.

---

## Permission Modes

| Mode | Behavior |
|------|----------|
| `"default"` | No mode-based approvals. Calls that need approval and match no allow rule go to `canUseTool` (denied if there is none). `"manual"` is accepted as an alias at runtime but is not in the type |
| `"dontAsk"` | Anything that would prompt is denied. Only allow rules, hooks, and no-approval calls run. Best for headless agents |
| `"acceptEdits"` | Auto-approve file edits and filesystem commands (`mkdir`, `rm`, `mv`, `cp`, `sed`, ...) inside working directories |
| `"bypassPermissions"` | Approve everything except protected actions. TS requires `allowDangerouslySkipPermissions: true`. `allowedTools` does not limit it; use `disallowedTools` |
| `"plan"` | Explore and plan; edits go to `canUseTool` |
| `"auto"` | A model classifier approves/blocks each reviewed action; falls back to `canUseTool` when undecided. Availability depends on model and provider (both SDKs) |

Set the mode explicitly. When omitted, the starting mode comes from `permissions.defaultMode` in loaded settings, and the fallback has changed across Claude Code versions.

Evaluation order for each tool call: **hooks → deny rules → ask rules → permission mode → allow rules → `canUseTool`**. A hook `deny` and a deny rule win in every mode. Calls approved before step 6 never reach `canUseTool`, so put checks that must see every call in a `PreToolUse` hook.

Subagents inherit `plan`, `acceptEdits`, `auto`, and `bypassPermissions` from the main session. Under a `default`/`dontAsk` main session they use `AgentDefinition.permissionMode`, except that `bypassPermissions` is never applied there.

`canUseTool` (TS) returns `{ behavior: "allow", updatedInput?, updatedPermissions? }` or `{ behavior: "deny", message, interrupt? }`. Python: return `PermissionResultAllow(...)` / `PermissionResultDeny(...)`.

---

## Built-in Tools

| Tool | Purpose |
|------|---------|
| `Read` / `Write` / `Edit` | Read, create, edit files (also images, PDFs, notebooks via `Read`) |
| `Bash` | Shell commands; `run_in_background` for long commands |
| `Monitor` | Watch a background command's output and react to events |
| `Glob` / `Grep` | File search. Native builds may use Bash `find`/`grep` instead; list `Glob`/`Grep` in `tools` or `allowedTools` to get them |
| `WebSearch` / `WebFetch` | Web search and page fetch |
| `Agent` | Spawn a subagent (listed as `Task` in `system/init.tools`; older `tool_use` blocks also used `Task`) |
| `SendMessage` | Message a named running agent |
| `TaskStop` | Stop a background task |
| `Workflow` | Run a scripted multi-agent workflow (TS 0.3.149+) |
| `TaskCreate` / `TaskGet` / `TaskUpdate` / `TaskList` | Task tracking; replaced `TodoWrite` in SDK sessions |
| `AskUserQuestion` | Ask the user multiple-choice questions (answered via `canUseTool`) |
| `Skill` | Invoke a skill (enable with the `skills` option) |
| `ToolSearch` | Load deferred tool schemas (MCP tools are deferred by default) |
| `NotebookEdit` | Edit Jupyter notebooks |
| `EnterWorktree` / `ExitWorktree` | Work in a temporary git worktree |
| `CronCreate` / `CronList` / `CronDelete` / `ScheduleWakeup` | Session-scoped scheduled prompts |

The exact tool set of a session is `system/init.tools`. TS exports `BUILTIN_TOOL_NAMES` (alpha) for validating rules.

---

## Subagents

Define subagents with `agents`; Claude delegates through the `Agent` tool based on each `description` (or when the prompt names the agent). A built-in `general-purpose` agent is always available unless `CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS=1`. Agents in `.claude/agents/*.md` load too; programmatic ones win on name clashes.

```typescript
for await (const msg of query({
  prompt: "Comprehensively review this project's code quality",
  options: {
    allowedTools: ["Read", "Grep", "Glob", "Agent"],
    agents: {
      "security-reviewer": {
        description: "Security review expert. Use for vulnerability checks.",
        prompt: `You are a security review expert, focusing on:
- SQL injection, XSS, and other OWASP Top 10 vulnerabilities
- Sensitive information leaks
- Missing permission checks`,
        tools: ["Read", "Grep", "Glob"],
        model: "opus",
        effort: "high",
      },
      "perf-reviewer": {
        description: "Performance review expert. Use to find bottlenecks.",
        prompt: "You are a performance review expert...",
        tools: ["Read", "Grep", "Glob", "Bash"],
        model: "opus",
        maxTurns: 20,
        background: true,
      },
    },
  },
})) { ... }
```

Python: `agents={"name": AgentDefinition(description=..., prompt=..., tools=[...], model="opus")}`. Multi-word fields keep camelCase (`disallowedTools`, `maxTurns`, `mcpServers`, `permissionMode`, `initialPrompt`).

### AgentDefinition Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | `string` | Yes | When to use the agent (drives delegation) |
| `prompt` | `string` | Yes | The agent's system prompt |
| `tools` | `string[]` | No | Allowed tools; omitted = inherit available tools |
| `disallowedTools` | `string[]` | No | Removed tools; `mcp__server`, `mcp__*` patterns allowed |
| `model` | `string` | No | Alias (`fable`/`opus`/`sonnet`/`haiku`), `inherit`, or full ID |
| `effort` | level or `number` | No | Reasoning effort for this agent |
| `maxTurns` | `number` | No | Turn cap; output is marked partial and the agent can be resumed |
| `background` | `boolean` | No | Always run as a non-blocking background task |
| `permissionMode` | `PermissionMode` | No | Subject to the inheritance rules above |
| `skills` | `string[]` | No | Skills preloaded into the agent's context |
| `mcpServers` | `(string \| Record<string, config>)[]` | No | MCP servers by name or inline config |
| `memory` | `'user' \| 'project' \| 'local'` | No | Persistent agent-memory directory scope |
| `initialPrompt` | `string` | No | First turn when the agent is the main thread (`agent` option); ignored for subagents |
| `autoCompactWindow` | `number` | No | Lower auto-compact threshold for this subagent (TS only) |
| `omitClaudeMd` | `boolean` | No | Start without user/project/local CLAUDE.md (TS only) |

### Execution model

- **Background by default.** A spawned subagent normally runs in the background: the `Agent` tool returns `status: "async_launched"` and the report arrives in a later turn. Claude waits (blocking call, `status: "completed"`) when its next step needs the result. `background: true` forces background; asking in the prompt ("run X and wait for it") forces waiting. In one-shot `query()` the final `result` is held until background subagents finish.
- **Context.** A subagent starts fresh: its own system prompt plus the `Agent` call's prompt, project CLAUDE.md, and its tools. It does not see the parent's history. Only its final message returns to the parent.
- **Forks.** `subagent_type: "fork"` starts a subagent that copies the current conversation (same model and effort as the parent). On by default; disable with `disallowedTools: ["Agent(fork)"]`.
- **Resume.** A finished subagent's tool result contains `agentId: <id>`. Resume the parent session (`resume: sessionId`, same `agents`) and ask Claude to resume that agent ID. Named agents (`Agent` input `name`) are addressable with `SendMessage` while running.
- **Isolation.** The `Agent` tool accepts `isolation: "worktree"` to run the subagent in a temporary git worktree.
- **Limits.** Nesting depth `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (default 3), concurrency `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20), both via `env`. `maxBudgetUsd` covers subagent spend and stops background subagents at the cap.
- **Detect.** `tool_use` blocks named `Agent` (match `Task` too for old transcripts). Messages produced inside a subagent carry `parent_tool_use_id`; TS also adds `agent_id` (equals the subagent's `task_id`) and `subagent_type`.

### Background tasks

Background subagents, background Bash commands, monitors, and workflows are tracked as tasks and reported as `system` messages:

| Subtype | Meaning |
|---------|---------|
| `task_started` | `task_id`, `description`, `task_type`, `subagent_type`, `is_backgrounded`, `parent_task_id` |
| `task_progress` | Usage so far, `last_tool_name`, optional `summary` (`agentProgressSummaries`) |
| `task_updated` | `patch` with `status` (`running`/`completed`/`failed`/`killed`/...) |
| `task_notification` | Terminal: `status` `completed`/`failed`/`stopped`, `summary`, `output_file`, `usage` |
| `background_tasks_changed` | Full set of live background tasks (TS) |

Stop one with `q.stopTask(taskId)` / `client.stop_task(task_id)`. A terminal state can arrive only as `task_updated`, so clear tracked tasks on a terminal status from either message. In streaming-input sessions, a finished background task starts a new turn whose `result.origin` is `{ kind: "task-notification" }`.

### Workflows (TypeScript)

For runs that coordinate dozens to hundreds of agents, the `Workflow` tool executes an orchestration script (`agent()`, `parallel()`, `pipeline()`, `phase()`) outside the conversation context. Add `Workflow` to `allowedTools` to auto-approve runs.

---

## MCP Servers

```typescript
for await (const msg of query({
  prompt: "List recent GitHub issues",
  options: {
    mcpServers: {
      github: {
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-github"],
        env: { GITHUB_TOKEN: process.env.GITHUB_TOKEN ?? "" },
      },
    },
    allowedTools: ["mcp__github__*"],
  },
})) { ... }
```

Tool naming: `mcp__{server_name}__{tool_name}`. Allow-rule globs work only after a literal `mcp__<server>__` prefix.

| Type | Use Case | Configuration |
|------|----------|---------------|
| stdio (default) | Local process | `{ command, args?, env? }` |
| http | Remote server | `{ type: "http", url, headers? }` |
| sse | Remote SSE server | `{ type: "sse", url, headers? }` |
| sdk | In-process server | the object returned by `createSdkMcpServer()` / `create_sdk_mcp_server()` |

- Servers connect in the background; slow ones show `status: "pending"` in `system/init`. `alwaysLoad: true` on a server waits for it and keeps its tools out of tool search.
- MCP tools are deferred behind `ToolSearch` by default (only names are in context until loaded).
- Per-server `timeout` (ms) bounds each tool call.
- TS: `tools: [{ name, permission_policy: "always_ask" | "always_deny" }]` on a server config forces approval or denial for specific tools.
- Change servers mid-session with `q.setMcpServers()` / `toggleMcpServer()` / `reconnectMcpServer()`.

---

## Custom Tools

In-process MCP tools; they work with string prompts.

**TypeScript:**
```typescript
import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const getTemperature = tool(
  "get_temperature",
  "Get the current temperature at a location",
  {
    latitude: z.number().describe("Latitude"),
    longitude: z.number().describe("Longitude"),
  },
  async (args) => {
    const resp = await fetch(
      `https://api.open-meteo.com/v1/forecast?latitude=${args.latitude}&longitude=${args.longitude}&current=temperature_2m`
    );
    if (!resp.ok) {
      return { content: [{ type: "text", text: `API error: ${resp.status}` }], isError: true };
    }
    const data = await resp.json();
    return { content: [{ type: "text", text: `Temperature: ${data.current.temperature_2m}°C` }] };
  },
  { annotations: { readOnlyHint: true } },   // optional extras: annotations, alwaysLoad, searchHint
);

const weatherServer = createSdkMcpServer({ name: "weather", version: "1.0.0", tools: [getTemperature] });

for await (const msg of query({
  prompt: "What's the temperature in Tokyo?",
  options: {
    mcpServers: { weather: weatherServer },
    allowedTools: ["mcp__weather__get_temperature"],
  },
})) { ... }
```

**Python:**
```python
from typing import Annotated, Any
from claude_agent_sdk import tool, create_sdk_mcp_server, ClaudeAgentOptions

@tool("get_temperature", "Get current temperature at a location", {
    "latitude": Annotated[float, "Latitude"],
    "longitude": Annotated[float, "Longitude"],
})
async def get_temperature(args: dict[str, Any]) -> dict[str, Any]:
    temp = await fetch_temperature(args["latitude"], args["longitude"])
    return {"content": [{"type": "text", "text": f"Temperature: {temp}°C"}]}

@tool("get_humidity", "Get current humidity", {"latitude": float, "longitude": float})
async def get_humidity(args: dict[str, Any]) -> dict[str, Any]:
    humidity = await fetch_humidity(args["latitude"], args["longitude"])
    return {"content": [{"type": "text", "text": f"Humidity: {humidity}%"}]}

weather_server = create_sdk_mcp_server(name="weather", version="1.0.0",
                                       tools=[get_temperature, get_humidity])

options = ClaudeAgentOptions(
    mcp_servers={"weather": weather_server},
    allowed_tools=["mcp__weather__get_temperature", "mcp__weather__get_humidity"],
)
```

Python schema forms: a dict of name → Python type (all keys required; `Annotated[type, "description"]` adds descriptions), a `TypedDict` class, or a full JSON Schema dict (`{"type": "object", "properties": ..., "required": [...]}`) for enums, optional fields, and nesting. Return `"is_error": True` (Python) / `isError: true` (TS) for failures; uncaught exceptions are also returned to Claude as error results.

---

## Hooks (Event Hooks)

Callbacks at key execution points. Matching hooks for one event run in parallel; for permission decisions `deny` > `defer` > `ask` > `allow`.

| Hook | Python | Trigger |
|------|--------|---------|
| `PreToolUse` | Yes | Before a tool runs (allow/deny/ask/defer, rewrite input) |
| `PostToolUse` | Yes | After a tool succeeds (add context, replace output) |
| `PostToolUseFailure` | Yes | After a tool fails |
| `PostToolBatch` | No | After a batch of parallel tool calls resolves |
| `UserPromptSubmit` | Yes | A prompt is submitted (including self-started turns) |
| `UserPromptExpansion` | No | A typed command / MCP prompt expands |
| `Stop` / `StopFailure` | Yes / No | Turn ends normally / ends on an API error |
| `SubagentStart` / `SubagentStop` | Yes | Subagent starts / finishes |
| `PreCompact` / `PostCompact` | Yes / No | Around context compaction |
| `PermissionRequest` | Yes | A call needs a permission decision |
| `PermissionDenied` | No | Auto mode denied a call |
| `Notification` | Yes | Agent notifications (e.g. a permission prompt waiting) |
| `SessionStart` / `SessionEnd` / `Setup` | No | Session lifecycle |
| `TaskCreated` / `TaskCompleted` | No | `TaskCreate` task-list items (not background tasks) |
| `TeammateIdle` | No | A teammate agent becomes idle |
| `PreModelSwitch` / `PostModelSwitch` | No | Around a model change |
| `Elicitation` / `ElicitationResult` | No | MCP server requests user input |
| `ConfigChange`, `InstructionsLoaded`, `CwdChanged`, `FileChanged`, `DirectoryAdded`, `WorktreeCreate`, `WorktreeRemove`, `MessageDisplay` | No | Environment and display events |

Python-only sessions can still use the other events as shell-command hooks in settings files.

### Callback and output shape

- Signature: TS `(input: HookInput, toolUseID: string | undefined, { signal }) => Promise<HookJSONOutput>`; Python `async (input_data, tool_use_id, context) -> dict`.
- Matcher: `{ matcher?: string, hooks: [...], timeout?: seconds, onFailure?: "continue" | "block" }` (Python `HookMatcher(matcher=..., hooks=[...], timeout=..., on_failure=...)`). For tool events the matcher is a tool-name pattern such as `"Write|Edit"` or `"^mcp__"`.
- Return `{}` to proceed unchanged. Top-level fields: `continue` (Python `continue_`), `stopReason`, `suppressOutput`, `systemMessage` (shown to the user), `decision`, `reason`, `hookSpecificOutput`. Async (fire-and-forget): `{ async: true, asyncTimeout?: ms }` (Python `async_`).

```typescript
// hookSpecificOutput by event
{ hookEventName: "PreToolUse", permissionDecision?: "allow" | "deny" | "ask" | "defer",
  permissionDecisionReason?: string, updatedInput?: Record<string, unknown>, additionalContext?: string }
{ hookEventName: "PostToolUse", additionalContext?: string, updatedToolOutput?: unknown }
{ hookEventName: "UserPromptSubmit" | "SubagentStart" | "Stop" | "SubagentStop" | "PostToolBatch", additionalContext?: string }
{ hookEventName: "PermissionRequest",
  decision: { behavior: "allow", updatedInput?, updatedPermissions? } | { behavior: "deny", message?, interrupt? } }
```

`defer` ends the turn with `stop_reason: "tool_deferred"` (and `terminal_reason: "tool_deferred"`) and the call in `result.deferred_tool_use`, so a host can resume it later. `Stop`/`SubagentStop` `additionalContext` makes the agent keep working on that feedback.

### Example: Prevent modification of .env files

**TypeScript:**
```typescript
import { query, type HookCallback } from "@anthropic-ai/claude-agent-sdk";

const protectEnv: HookCallback = async (input) => {
  if (input.hook_event_name !== "PreToolUse") return {};
  const { file_path } = input.tool_input as { file_path?: string };
  if (file_path?.endsWith(".env")) {
    return {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Modification of .env files is not allowed",
      },
    };
  }
  return {};
};

for await (const msg of query({
  prompt: "...",
  options: { hooks: { PreToolUse: [{ matcher: "Write|Edit", hooks: [protectEnv] }] } },
})) { ... }
```

**Python:**
```python
from claude_agent_sdk import query, ClaudeAgentOptions, HookMatcher

async def protect_env(input_data, tool_use_id, context):
    file_path = input_data["tool_input"].get("file_path", "")
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
        hooks={"PreToolUse": [HookMatcher(matcher="Write|Edit", hooks=[protect_env])]}
    ),
):
    ...
```

Matchers only see tool names; a Bash command that writes `.env` bypasses this hook. Use the `sandbox` option or deny rules such as `Edit(//path/**)` for stronger guarantees.

---

## Message Types

**TypeScript** (`SDKMessage`, discriminated on `type`, then `subtype`):

| Type | Description |
|------|-------------|
| `system` / `init` | Session start: `session_id`, `model`, `tools`, `mcp_servers`, `permissionMode`, `agents`, `skills` |
| `assistant` | Model output; `message` is an API `Message` (text, thinking, tool_use blocks) |
| `user` | Tool results (`tool_result` blocks, `tool_use_result` structured output) and replayed prompts |
| `result` | End of a turn (one per turn) |
| `stream_event` | Partial deltas (`includePartialMessages`) |
| `system` / `task_started`, `task_progress`, `task_updated`, `task_notification`, `background_tasks_changed` | Background task lifecycle |
| `system` / `compact_boundary` | Context was compacted |
| `system` / `status`, `api_retry`, `permission_denied`, `informational`, `notification`, `session_state_changed` | Status, retries, denials, warnings |
| `system` / `hook_started`, `hook_progress`, `hook_response` | Hook lifecycle (`includeHookEvents`) |
| `tool_progress` | Heartbeat for long tool calls (incl. `Agent`) |
| `tool_use_summary`, `prompt_suggestion`, `rate_limit_event`, `auth_status`, `conversation_reset` | Other events |

Subagent messages carry `parent_tool_use_id` (and in TS `agent_id`, `subagent_type`).

**Python** classes: `SystemMessage` (`subtype`, `data`; subclasses `TaskStartedMessage`, `TaskProgressMessage`, `TaskUpdatedMessage`, `TaskNotificationMessage`, `HookEventMessage`, `MirrorErrorMessage`), `AssistantMessage` (`content` blocks: `TextBlock`, `ThinkingBlock`, `ToolUseBlock`, ...; `model`, `usage`), `UserMessage`, `ResultMessage`, `StreamEvent`, `RateLimitEvent`, `ConversationResetMessage`.

### Result Message Fields

| Field (TS / Python) | Type | Description |
|-------|------|-------------|
| `session_id` | `string` | Session identifier |
| `subtype` | `string` | See below |
| `is_error` | `boolean` | `true` on errors, and on `success` when the turn ended on an API error (`api_error_status` set) |
| `result` | `string` | Final text (success only) |
| `structured_output` | `unknown` | Validated output when `outputFormat` is set |
| `errors` | `string[]` | Error details (error subtypes) |
| `stop_reason` | `string \| null` | Model stop reason |
| `terminal_reason` | `string` | Why the loop ended: `completed`, `max_turns`, `budget_exhausted`, `aborted_streaming`/`aborted_tools` (interrupted), `tool_deferred`, `api_error`, ... |
| `duration_ms` / `duration_api_ms` | `number` | Wall time / API time |
| `num_turns` | `number` | Model round-trips |
| `total_cost_usd` | `number` | Estimated cost of this `query()` call, subagents included (cumulative in streaming sessions) |
| `usage` | `object` | Main loop only; prefer `modelUsage` |
| `modelUsage` / `model_usage` | `Record<string, ModelUsage>` | Per-model `inputTokens`, `outputTokens`, cache tokens, `costUSD`, incl. subagents |
| `permission_denials` | `array` | Denied tool calls |
| `deferred_tool_use` | `{ id, name, input }` | Call deferred by a `PreToolUse` hook |
| `origin` | `object` | What triggered the turn, e.g. `{ kind: "task-notification" }` |

### Result Subtypes

| Subtype | Meaning |
|---------|---------|
| `success` | Turn completed (check `is_error` and `structured_output`) |
| `error_during_execution` | Execution error, including startup failures |
| `error_max_turns` | Hit `maxTurns` |
| `error_max_budget_usd` | Hit `maxBudgetUsd` |
| `error_max_structured_output_retries` | No schema-valid output after retries |

There is no `interrupted` subtype; an interrupt shows up as `terminal_reason: "aborted_streaming"` or `"aborted_tools"`.

---

## Agent Class Template

State lives in sessions; run/continue maps to a new session vs. `resume`. Each call returns the session ID and schema-validated data.

```typescript
import {
  query,
  type EffortLevel,
  type PermissionMode,
  type SDKResultMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const MyOutput = z.object({
  summary: z.string(),
  passed: z.boolean(),
  issues: z.array(z.object({
    severity: z.enum(["high", "medium", "low"]),
    description: z.string(),
  })),
});
type MyOutput = z.infer<typeof MyOutput>;
const myOutputSchema = z.toJSONSchema(MyOutput, { target: "draft-7" });

export interface AgentStructuredResponse<T> {
  sessionId: string;
  data: T;
  costUsd: number;
}

export interface MyAgentOptions {
  model?: string;
  effort?: EffortLevel;
  systemPrompt?: string;
  tools?: string[];
  permissionMode?: PermissionMode;
  maxTurns?: number;
  maxBudgetUsd?: number;
}

export class MyAgent {
  private readonly model: string;
  private readonly effort: EffortLevel;
  private readonly systemPrompt?: string;
  private readonly tools: string[];
  private readonly permissionMode: PermissionMode;
  private readonly maxTurns: number;
  private readonly maxBudgetUsd?: number;

  constructor(options: MyAgentOptions = {}) {
    this.model = options.model ?? "claude-opus-5-5";
    this.effort = options.effort ?? "high";
    this.systemPrompt = options.systemPrompt;
    this.tools = options.tools ?? ["Read", "Glob", "Grep"];
    // dontAsk: listed tools run, anything that would need approval is denied (no human in the loop)
    this.permissionMode = options.permissionMode ?? "dontAsk";
    this.maxTurns = options.maxTurns ?? 30;
    this.maxBudgetUsd = options.maxBudgetUsd;
  }

  run(cwd: string, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    return this.execute(prompt, cwd);
  }

  // Pass the original cwd so relative paths and project settings match the first run
  continue(sessionId: string, prompt: string, cwd: string): Promise<AgentStructuredResponse<MyOutput>> {
    return this.execute(prompt, cwd, sessionId);
  }

  private async execute(prompt: string, cwd: string, sessionId?: string): Promise<AgentStructuredResponse<MyOutput>> {
    let result: SDKResultMessage | undefined;
    try {
      for await (const msg of query({
        prompt,
        options: {
          cwd,
          model: this.model,
          effort: this.effort,
          systemPrompt: this.systemPrompt,
          allowedTools: this.tools,
          permissionMode: this.permissionMode,
          maxTurns: this.maxTurns,
          maxBudgetUsd: this.maxBudgetUsd,
          outputFormat: { type: "json_schema", schema: myOutputSchema },
          resume: sessionId,
        },
      })) {
        if (msg.type === "result") result = msg;
      }
    } catch (error) {
      // query() throws after yielding an error result; report that result below instead
      if (!result) throw error;
    }

    if (!result) throw new Error("query() ended without a result message");
    if (result.subtype !== "success") {
      throw new Error(`Agent run ${result.session_id} failed: ${result.subtype} ${result.errors.join("; ")}`);
    }
    if (result.structured_output === undefined) {
      throw new Error(`Agent run ${result.session_id} ended without structured output`);
    }
    return {
      sessionId: result.session_id,
      data: MyOutput.parse(result.structured_output),
      costUsd: result.total_cost_usd,
    };
  }
}
```

Python follows the same shape: build `ClaudeAgentOptions(cwd=..., resume=session_id, output_format={...})`, keep the last `ResultMessage` from the loop, catch `ResultError`, then `MyOutput.model_validate(result.structured_output)`.

---

## Orchestration Notes

For orchestration pattern design and selection, see the "How to Build Agent System" section in SKILL.md.

Claude Agent SDK specifics:
- **Context passing**: serialize one agent's `structured_output` into the next agent's prompt; subagents likewise only see the prompt they are given.
- **Session resume and branching**: `resume` restores context; `forkSession: true` (optionally `resumeSessionAt`) or `forkSession()` / `fork_session()` branches without touching the original. Forks copy conversation, not files; give parallel writers separate worktrees.
- **Parallel execution (host-driven)**: run several `query()` calls concurrently (`Promise.all` / `asyncio.gather`), each with its own session and `cwd`.
- **Built-in subagents (model-driven)**: declare `agents`; Claude delegates via the `Agent` tool, runs subagents in the background by default, and can fork the current conversation (`subagent_type: "fork"`). Cap with depth/concurrency env vars and `maxBudgetUsd`.
- **Background work**: track `task_*` system messages, stop with `stopTask()`, push a running foreground task to the background with `backgroundTasks()` (TS). In streaming-input sessions each finished background task produces its own `result`.
- **Large fan-out**: the `Workflow` tool (TS) runs scripted multi-agent orchestration outside the conversation context.
- **Multi-turn control**: `ClaudeSDKClient` (Python) or streaming-input `query()` (TS) for interrupt, model/permission changes, and follow-up prompts in one live session.
- **Cost and limits**: read `total_cost_usd` / `modelUsage` from the last result; set `maxTurns` and `maxBudgetUsd` on every unattended agent.
