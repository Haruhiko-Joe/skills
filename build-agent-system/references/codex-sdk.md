# Codex SDK Reference

Codex SDK is OpenAI's SDK for driving local Codex coding agents from code, in TypeScript and Python.

> Checked on 2026-11-10 against `@openai/codex-sdk` 0.167.0 (npm), `openai-codex` 0.167.0 (PyPI), and Codex CLI 0.167.0.

The two SDKs are built differently, and that decides what each can do:

| | TypeScript `@openai/codex-sdk` | Python `openai-codex` |
|---|---|---|
| Transport | Spawns `codex exec` per turn and reads its JSONL events | Keeps one long-lived `codex app-server` process (JSON-RPC over stdio) |
| Bundled CLI | `@openai/codex` (npm dependency) | `openai-codex-cli-bin` (pinned to the same version) |
| Start / resume thread | Yes | Yes |
| Fork thread | No | `thread_fork()` |
| Mid-turn steer / interrupt | Cancel only, via `AbortSignal` | `TurnHandle.steer()` / `.interrupt()` |
| Streaming | `runStreamed()` (exec JSONL events) | `TurnHandle.stream()` (app-server notifications) |
| Untrusted input from other agents | Plain prompt text only | `ExternalMessage` |
| Thread list / archive / read / compact | No | Yes |

---

## Installation

```bash
# TypeScript (Node.js 18+, server-side only)
npm install @openai/codex-sdk

# Python (3.10+)
pip install openai-codex
```

Both SDKs reuse the existing Codex login (`~/.codex`). For API-key auth, set `CODEX_API_KEY` (TS: or pass `apiKey`; Python: `codex.login_api_key("sk-...")`).

---

## Core API (TypeScript)

### Codex Instance

```typescript
import { Codex } from "@openai/codex-sdk";

const codex = new Codex({
  config: {
    developer_instructions: myInstruction,       // extra developer (system-level) instructions
    sandbox_workspace_write: { network_access: true },
  },
});
```

`CodexOptions`:

| Option | Meaning |
|---|---|
| `config` | JSON object, flattened to dotted paths and passed as repeated `--config key=value` |
| `configOverrides` | Raw TOML `key=value` strings, applied after `config` (they win over `config`) |
| `env` | Full environment for the CLI process; when set, `process.env` is **not** inherited |
| `apiKey` | Sets `CODEX_API_KEY` for the CLI |
| `baseUrl` | Passed as `--config openai_base_url=...` |
| `codexPathOverride` | Path to a specific `codex` binary |

SDK-managed settings and thread options are applied last and override both `config` and `configOverrides`.

There is no profile option. `config: { profile: "x" }` now fails with "legacy `profile` config is no longer supported" (see [Configuration](#configuration-codexconfigtoml)).

### Thread Management

```typescript
const thread = codex.startThread({
  model: "gpt-6-astra",
  workingDirectory: "/path/to/repo",
  skipGitRepoCheck: true,
  sandboxMode: "workspace-write",
  approvalPolicy: "never",
  modelReasoningEffort: "high",
});

// Call run() repeatedly on the same Thread to continue the conversation
const turn1 = await thread.run("Diagnose the test failure");
const turn2 = await thread.run("Implement the fix");

// thread.id is null until the first turn starts; persist it for later resume
const threadId = thread.id;

// Resume (threads are stored in ~/.codex/sessions). Thread options are not
// persisted with the thread: pass workingDirectory etc. again.
const resumed = codex.resumeThread(threadId!, { workingDirectory: "/path/to/repo" });
```

`ThreadOptions`:

| Option | Values |
|---|---|
| `model` | Model ID, e.g. `gpt-6-astra` |
| `workingDirectory` | Passed as `--cd` |
| `additionalDirectories` | Extra writable dirs (`--add-dir`) |
| `skipGitRepoCheck` | Codex refuses non-Git directories unless `true` |
| `sandboxMode` | `"read-only"` \| `"workspace-write"` \| `"danger-full-access"` |
| `approvalPolicy` | `"never"` for unattended runs, or `"on-request"`. The type still lists `"on-failure"` and `"untrusted"`, but the docs mark them deprecated and unsupported |
| `modelReasoningEffort` | An effort the model advertises (see `model_reasoning_effort` below) |
| `networkAccessEnabled` | Sets `sandbox_workspace_write.network_access` |
| `webSearchMode` | `"disabled"` \| `"cached"` \| `"live"` (`webSearchEnabled: boolean` is the older shorthand) |
| `threadSource` | Label for threads your integration creates, e.g. `"ci"` (only applied on new threads) |

### Execution and Output

```typescript
const turn = await thread.run(prompt);
turn.finalResponse;   // string: text of the last agent_message item
turn.items;           // ThreadItem[]: completed items
turn.usage;           // Usage | null: input/cached/cache-write/output/reasoning tokens

// Structured output: outputSchema is a JSON Schema object, written to a temp file
// and passed as --output-schema. finalResponse is then a JSON string.
const turn = await thread.run(prompt, { outputSchema: mySchema });
const data = JSON.parse(turn.finalResponse) as MyOutput;

// Cancel a turn (kills the CLI process)
const controller = new AbortController();
const pending = thread.run(prompt, { signal: controller.signal });
controller.abort();
```

`run()` throws `Error(message)` when the turn emits `turn.failed`. Use strict-mode schemas: every property listed in `required`, and `additionalProperties: false`. A Zod schema works via `zodToJsonSchema(schema, { target: "openAi" })`.

### Streaming

`runStreamed()` returns an async generator of events as they arrive:

```typescript
const { events } = await thread.runStreamed("Diagnose the test failure");

for await (const event of events) {
  switch (event.type) {
    case "item.started":
    case "item.updated":
    case "item.completed":
      console.log(event.type, event.item.type, event.item);
      break;
    case "turn.completed":
      console.log("usage", event.usage);
      break;
    case "turn.failed":
      console.error(event.error.message);
      break;
  }
}
```

Event types (`ThreadEvent`): `thread.started` (carries `thread_id`), `turn.started`, `turn.completed` (`usage`), `turn.failed` (`error`), `item.started`, `item.updated`, `item.completed`, `error` (fatal stream error).

Item types (`ThreadItem`): `agent_message` (`text`), `reasoning` (`text`), `command_execution` (`command`, `aggregated_output`, `exit_code?`, `status`), `file_change` (`changes[{path, kind}]`, `status`), `mcp_tool_call` (`server`, `tool`, `arguments`, `result?`, `error?`, `status`), `web_search` (`query`), `todo_list` (`items[{text, completed}]`), `error` (`message`). Subagent activity is not surfaced as a TS item type.

### Image Input

```typescript
const turn = await thread.run([
  { type: "text", text: "Describe these screenshots and suggest fixes" },
  { type: "local_image", path: "./screenshots/error-state.png" },
  { type: "local_image", path: "./screenshots/mobile-layout.jpg" },
]);
```

- Only `text` and `local_image` entries exist; text entries are joined with blank lines, images go to `--image`.
- `path` may be relative or absolute. Download URL images to a local file first.

---

## Core API (Python)

### Codex Instance

```python
from openai_codex import Codex, AsyncCodex, CodexConfig, Sandbox

# Synchronous: starts app-server and initializes in __init__
with Codex() as codex:
    thread = codex.thread_start(model="gpt-6-astra", sandbox=Sandbox.workspace_write)
    result = thread.run("Diagnose the test failure")
    print(result.final_response)

# Asynchronous: initializes on context entry (or first awaited call)
async with AsyncCodex() as codex:
    thread = await codex.thread_start(model="gpt-6-astra")
    result = await thread.run("Implement the fix")
    print(result.final_response)
```

`CodexConfig` (process-level settings):

```python
CodexConfig(
    codex_bin=None,               # use a specific local codex binary instead of the bundled one
    config_overrides=('model_reasoning_effort="high"',),  # raw --config key=value strings
    cwd=None,                     # working directory of the app-server process
    env=None,                     # merged on top of os.environ
    launch_args_override=None,    # full argv replacement (advanced)
)
```

Other client methods: `models(include_hidden=False)`, `account()`, `logout()`, `login_api_key(key)`, `login_chatgpt()`, `login_chatgpt_device_code()`.

### Thread Management (Python)

```python
from openai_codex import ApprovalMode, Sandbox

thread = codex.thread_start(
    model="gpt-6-astra",
    cwd="/path/to/repo",
    developer_instructions=my_instruction,
    approval_mode=ApprovalMode.auto_review,
    sandbox=Sandbox.workspace_write,
    config={"model_reasoning_effort": "high"},   # any config.toml keys
    ephemeral=False,              # True: not persisted, cannot be resumed later
)
thread.id                         # available immediately

thread = codex.thread_resume(thread_id, cwd="/path/to/repo")
forked = codex.thread_fork(thread_id, cwd="/path/to/repo")   # new thread id, copied history

threads = codex.thread_list(limit=10)          # ThreadListResponse; filters: archived, cursor,
                                               # cwd, model_providers, sort_key, source_kinds
codex.thread_archive(thread_id)
codex.thread_unarchive(thread_id)

thread.set_name("Feature Implementation")
thread.compact()                               # compact context
history = thread.read(include_turns=True)      # ThreadReadResponse
```

Keyword arguments on `thread_start` / `thread_resume` / `thread_fork`: `model`, `model_provider`, `cwd`, `developer_instructions`, `base_instructions` (replaces built-in instructions), `config` (dict of config.toml keys), `approval_mode`, `sandbox`, `service_tier` (resume/fork), `ephemeral` (start/fork), `include_turns` (resume/fork: only controls whether history is returned, not model context), `personality` (deprecated: `friendly`/`pragmatic` no longer change style).

- `ApprovalMode.auto_review` (default for `thread_start`): approval requests go to the automatic reviewer instead of a human, so unattended runs do not block.
- `ApprovalMode.deny_all`: approval policy `never`; escalations are refused.
- `Sandbox.read_only` | `Sandbox.workspace_write` | `Sandbox.full_access`. Omitted means the configured default. These are enums; plain strings raise `ValueError`.

### Execution and Output (Python)

```python
from openai_codex import ApprovalMode, Sandbox, TurnResult
from openai_codex.types import ReasoningEffort, ReasoningSummary, TurnStatus

result: TurnResult = thread.run("Say hello")
result.final_response   # str | None (last final-answer agent message)
result.items            # list[ThreadItem]
result.usage            # ThreadTokenUsage | None
result.status           # TurnStatus, e.g. TurnStatus.failed
result.error            # TurnError | None
result.id, result.duration_ms

result = thread.run(
    prompt,
    output_schema=my_schema,                         # JSON Schema dict; final_response is JSON text
    effort=ReasoningEffort.high,                     # none|minimal|low|medium|high|xhigh|max|ultra
    summary=ReasoningSummary.model_validate("concise"),  # auto|concise|detailed|none
    model="gpt-6-astra",
    cwd="/path/to/repo",
    sandbox=Sandbox.read_only,                       # applies to this and later turns
    approval_mode=ApprovalMode.deny_all,
    service_tier="fast",                             # thread default from now on
    turn_service_tier="default",                     # this turn only
    source="review_ui",                              # label only, grants nothing
)
```

In 0.167.0 a failed turn raises `RuntimeError(error.message)` from `run()`; also check `result.status` / `result.error`, as the official examples do. RPC failures raise `CodexError` subclasses (`JsonRpcError`, `InvalidParamsError`, `ServerBusyError`, `TransportClosedError`, ...). Pick an effort the model supports: `codex.models()` lists each model's `supported_reasoning_efforts`.

### Turn-Level Control (Python)

`thread.turn(...)` takes the same arguments as `run()` and returns a `TurnHandle`:

```python
turn = thread.turn(prompt)

turn.steer("Focus on the auth module specifically")   # add user input to the running turn
turn.interrupt()                                     # stop it; status becomes interrupted

for event in turn.stream():          # Notification(method, payload), only for this turn
    if event.method == "item/agentMessage/delta":
        print(event.payload.delta, end="")
    elif event.method == "item/completed":
        item = event.payload.item.root      # e.g. item.type == "agentMessage"
    elif event.method == "turn/completed":
        print(event.payload.turn.status)

result = turn.run()                  # alternative to stream(): collect into TurnResult
```

- Consume a handle with either `stream()` or `run()`, not both.
- One `Codex` / `AsyncCodex` instance can run and stream several turns at once (events are routed by turn ID), so parallel agents can share one client.
- Async: `await thread.turn(...)`, `await turn.steer(...)`, `async for event in turn.stream()`.
- A handle only sees events from when it was created; use `thread.read(include_turns=True)` for earlier history.
- Items use camelCase type names (`agentMessage`, `commandExecution`, `fileChange`, `functionCallOutput`, ...). Payloads are typed pydantic models; unknown events arrive as `UnknownNotification` with raw `.params`.

### Input Types (Python)

```python
from openai_codex import TextInput, LocalImageInput, ImageInput, SkillInput, MentionInput, ExternalMessage

result = thread.run([
    TextInput("Describe what's wrong in this screenshot"),
    LocalImageInput("./screenshots/error.png"),
    ImageInput("data:image/png;base64,..."),   # data URLs only; http(s) URLs are deprecated
])

# Output from another agent, tool, or webhook: tool-level authority, below user and
# developer instructions; it never counts as user approval. Must be the whole input.
result = thread.run(ExternalMessage(
    tool_name="reviewer_agent",
    namespace="pipeline",
    content=json.dumps(review),
))
```

A plain `str` is shorthand for `TextInput`. `SkillInput(name, path)` invokes a skill, `MentionInput(name, path)` mentions a file or resource. `ExternalMessage` passed to `thread.turn()` while a turn is running joins that turn.

---

## Configuration (`~/.codex/config.toml`)

Both SDKs read the same config layers: `~/.codex/config.toml`, then a profile file if selected, then the trusted project's `.codex/config.toml`, then CLI/SDK overrides.

```toml
model = "gpt-6-astra"
model_reasoning_effort = "high"
model_reasoning_summary = "concise"
approval_policy = "never"
approvals_reviewer = "user"            # or "auto_review"
sandbox_mode = "workspace-write"
service_tier = "fast"
web_search = "cached"
developer_instructions = "Prefer small, reviewed diffs."

[sandbox_workspace_write]
network_access = true
writable_roots = ["/tmp/build"]
```

| Key | Values |
|---|---|
| `model` | Always `gpt-6-astra`, for every agent and subagent, checkers and fan-out workers included. The other GPT-6 models (`gpt-6.1-sol`, `gpt-6.1-terra`, `gpt-6-luna`) write noticeably worse, unnatural prose; do not use them. Set it explicitly rather than relying on the account default |
| `model_reasoning_effort` | `low` / `medium` / `high` / `xhigh` / `max` / `ultra`, as advertised by the model. `ultra` uses subagents (set `default_subagent_model` so they also run on Astra). Lower effort, not a smaller model, is the way to cut cost |
| `model_reasoning_summary` | `auto` / `concise` / `detailed` / `none` |
| `approval_policy` | `on-request` / `never` / `{ granular = { ... } }`. `on-failure` is deprecated, `untrusted` unsupported |
| `approvals_reviewer` | `user` (default) / `auto_review` |
| `sandbox_mode` | `read-only` / `workspace-write` / `danger-full-access` |
| `default_permissions` | Permission profile (`:read-only`, `:workspace`, `:danger-full-access`, or a named `[permissions.<name>]` table). Beta; do not combine with `sandbox_mode` |
| `service_tier` | `fast` (sent as `priority`) or another tier the model advertises |
| `web_search` | `disabled` / `cached` (default) / `indexed` / `live` |
| `developer_instructions` | Extra developer instructions for every session |
| `model_instructions_file` | Replaces the built-in instructions |
| `personality` | Deprecated |

**Profiles (CLI only).** Since Codex 0.134.0 a profile is a separate file `~/.codex/<name>.config.toml` with top-level keys, selected with `codex --profile <name>` / `codex exec --profile <name>`. `[profiles.<name>]` tables and the top-level `profile = "..."` key are no longer read, and setting `profile` makes config loading fail. Neither SDK passes `--profile` (`codex app-server` rejects it), so in SDK code put the per-agent settings in `ThreadOptions` / `config` (TS) or `thread_start(...)` kwargs / `config` (Python).

### Multi-Agent, MCP, Hooks, Skills

These are configured in config.toml (or passed through the SDK `config` object) and run inside the Codex session the SDK drives.

```toml
# Built-in subagents: the agent can spawn child threads (spawn_agent, wait, send_input, ...)
[features]
multi_agent = true          # default on
goals = true                # persisted /goal + automatic continuation, default on
hooks = true

[agents]
enabled = true
max_concurrent_threads_per_session = 4     # excludes the primary thread
default_subagent_model = "gpt-6-astra"   # never a smaller GPT-6 model
default_subagent_reasoning_effort = "high"

# MCP servers
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp"]

[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"

# Hooks (same schema as hooks.json)
[[hooks.PreToolUse]]
matcher = "^Bash$"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "python3 .codex/hooks/pre_tool_use_policy.py"
timeout = 30
```

- **Subagents.** Built-in roles: `default`, `worker`, `explorer`. Custom roles are standalone TOML files in `~/.codex/agents/` or `.codex/agents/` with required `name`, `description`, `developer_instructions` and optional `model`, `model_reasoning_effort`, `model_reasoning_summary`, `model_verbosity`, `skills.*`, `features.*`. Subagents inherit the parent's sandbox and approval settings. They are triggered by the prompt, AGENTS.md, or skills ("spawn one agent per module"). `agents.max_concurrent_threads_per_session` is the only documented limit.
- **MCP.** Per server: `command`/`args`/`env`/`cwd` (stdio) or `url` (streamable HTTP), `bearer_token_env_var`, `enabled_tools`, `disabled_tools`, `startup_timeout_sec` (10), `tool_timeout_sec` (60), `required` (fail startup if it can't start).
- **Hooks.** Events: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreModelRequest`, `PostModelRequest`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, `Stop`, `Interrupt`. Handler types `command` and `mcp_tool`. Exit code 2 blocks (reason on stderr); `Stop`/`SubagentStop` returning `decision: "block"` keeps the agent working. Non-managed hooks only run after they are trusted (`/hooks` in the CLI); project hooks also need a trusted project.
- **Skills.** Directories with `SKILL.md` (`name`, `description` frontmatter) in `.agents/skills` (from cwd up to the repo root) or `~/.agents/skills`. Python can invoke one explicitly with `SkillInput`. Toggle with `[[skills.config]]` entries (`name`/`path` + `enabled`).
- **Plugins.** `plugins."<plugin>@<marketplace>".enabled = true|false`; installed with `codex plugin`.
- **Goals.** Started with `/goal` in interactive sessions; budget cap via `goals.max_goal_token_budget`. Neither SDK's public API (0.167.0) has goal methods, so an SDK orchestrator cannot set or read goals directly.

---

## Retry Utilities (Python)

`retry_on_overload` is a plain function, not a decorator. It retries only errors where `is_retryable_error(exc)` is true (server overload, `ServerBusyError`), with exponential backoff and jitter. It is synchronous (`time.sleep`), so write your own loop for async code.

```python
from openai_codex import retry_on_overload, is_retryable_error, ServerBusyError

result = retry_on_overload(
    lambda: thread.run(prompt),
    max_attempts=3,
    initial_delay_s=0.25,
    max_delay_s=2.0,
)

# Async equivalent
for attempt in range(3):
    try:
        result = await thread.run(prompt)
        break
    except Exception as exc:
        if attempt == 2 or not is_retryable_error(exc):
            raise
        await asyncio.sleep(0.25 * 2**attempt)
```

Do not retry `InvalidParamsError` or `MethodNotFoundError`: fix the input or the runtime version.

---

## Agent Class Template (TypeScript)

```typescript
import { Codex, type ModelReasoningEffort, type Thread, type ThreadOptions } from "@openai/codex-sdk";

const myOutputSchema = {
  type: "object",
  properties: {
    summary: { type: "string" },
    status: { type: "string", enum: ["ok", "action_required"] },
  },
  required: ["summary", "status"],
  additionalProperties: false,
} as const;

interface MyOutput {
  summary: string;
  status: "ok" | "action_required";
}

interface AgentStructuredResponse<T> {
  threadId: string;
  rawText: string;
  data: T;
}

interface MyAgentOptions {
  model?: string;
  reasoningEffort?: ModelReasoningEffort;
  developerInstructions?: string;
}

export class MyAgent {
  private readonly codex: Codex;
  private readonly baseThreadOptions: ThreadOptions;
  private thread: Thread | null = null;

  constructor(options: MyAgentOptions = {}) {
    this.codex = new Codex(
      options.developerInstructions
        ? { config: { developer_instructions: options.developerInstructions } }
        : {},
    );
    this.baseThreadOptions = {
      model: options.model ?? "gpt-6-astra",
      modelReasoningEffort: options.reasoningEffort ?? "high",
      sandboxMode: "workspace-write",
      approvalPolicy: "never",
      skipGitRepoCheck: true,
    };
  }

  async run(path: string, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    this.thread = this.codex.startThread({ ...this.baseThreadOptions, workingDirectory: path });
    return this.execute(this.thread, prompt);
  }

  // Thread options are not stored with the thread, so the working directory is passed again.
  async continue(threadId: string, path: string, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    if (!this.thread || this.thread.id !== threadId) {
      this.thread = this.codex.resumeThread(threadId, { ...this.baseThreadOptions, workingDirectory: path });
    }
    return this.execute(this.thread, prompt);
  }

  private async execute(thread: Thread, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    const turn = await thread.run(prompt, { outputSchema: myOutputSchema });
    if (!thread.id) throw new Error("Codex did not report a thread id");
    const data = JSON.parse(turn.finalResponse) as MyOutput;
    return { threadId: thread.id, rawText: turn.finalResponse, data };
  }
}
```

## Agent Class Template (Python)

```python
import json
from dataclasses import dataclass
from typing import Any, Generic, TypeVar

from openai_codex import AsyncCodex, AsyncThread, Sandbox, TurnResult
from openai_codex.types import ReasoningEffort

T = TypeVar("T")

MY_OUTPUT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "status": {"type": "string", "enum": ["ok", "action_required"]},
    },
    "required": ["summary", "status"],
    "additionalProperties": False,
}


@dataclass
class AgentStructuredResponse(Generic[T]):
    thread_id: str
    raw_text: str
    data: T


class MyAgent:
    """Use as `async with MyAgent() as agent:` so the app-server process is closed."""

    def __init__(
        self,
        model: str = "gpt-6-astra",
        effort: ReasoningEffort = ReasoningEffort.high,
        developer_instructions: str | None = None,
    ) -> None:
        self.model = model
        self.effort = effort
        self.developer_instructions = developer_instructions
        self.codex = AsyncCodex()
        self.thread: AsyncThread | None = None

    async def __aenter__(self) -> "MyAgent":
        await self.codex.__aenter__()
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.codex.close()

    async def run(self, path: str, prompt: str) -> AgentStructuredResponse[dict[str, Any]]:
        self.thread = await self.codex.thread_start(
            model=self.model,
            cwd=path,
            developer_instructions=self.developer_instructions,
            sandbox=Sandbox.workspace_write,
        )
        return await self._execute(self.thread, prompt)

    async def continue_(self, thread_id: str, path: str, prompt: str) -> AgentStructuredResponse[dict[str, Any]]:
        if self.thread is None or self.thread.id != thread_id:
            self.thread = await self.codex.thread_resume(thread_id, model=self.model, cwd=path)
        return await self._execute(self.thread, prompt)

    async def _execute(self, thread: AsyncThread, prompt: str) -> AgentStructuredResponse[dict[str, Any]]:
        result: TurnResult = await thread.run(prompt, output_schema=MY_OUTPUT_SCHEMA, effort=self.effort)
        if result.final_response is None:
            raise RuntimeError(f"turn {result.id} ended without a final response")
        return AgentStructuredResponse(
            thread_id=thread.id,
            raw_text=result.final_response,
            data=json.loads(result.final_response),
        )
```

---

## Orchestration Notes

For orchestration pattern design and selection guide, refer to the "How to Build Agent System" section in SKILL.md.

Codex SDK orchestration key points:
- **Context passing**: Serialize one agent's output (`JSON.stringify(result.data)` / `json.dumps(...)`) into the next agent's prompt. In Python, wrap it in `ExternalMessage` so another agent's output cannot act as user instructions or approval.
- **Session resume**: `resumeThread(threadId, options)` (TS) or `thread_resume(thread_id, ...)` (Python) keeps context across loop-with-checker iterations. Persist the thread ID; in TS also re-pass thread options.
- **Thread forking**: Python `thread_fork()` branches from an existing thread for speculative attempts; pick the best branch and archive the rest. The TS SDK has no fork (the CLI has `codex exec fork`).
- **Parallel execution**: `Promise.all` (TS, one CLI process per running turn) or `asyncio.gather` (Python; one `AsyncCodex` can run many threads' turns concurrently). Give parallel writers separate working directories or worktrees.
- **Built-in subagents**: A single Codex thread can fan out to its own child agents (`[agents]` config, custom roles in `.codex/agents/`, effort `ultra`). Use this for in-session read-heavy fan-out; use separate SDK threads when your code needs to own scheduling, schemas, and per-agent results.
- **Turn steering**: Python `TurnHandle.steer()` corrects course mid-turn; `interrupt()` stops it. TS can only abort via `AbortSignal`.
- **Unattended runs**: Use `approvalPolicy: "never"` (TS) or the default `ApprovalMode.auto_review` (Python) with an explicit sandbox; nobody is there to answer approval prompts.
- **LLM orchestration**: The Orchestrator Agent drives scheduling via structured output (`{ nextAgent, prompt, done }`).
