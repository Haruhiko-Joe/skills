# Antigravity SDK Reference

Google Antigravity SDK (`google-antigravity`) drives Antigravity agents from Python: the agent loop, built-in file/shell/web tools, policies, hooks, subagents, workflows, and persisted conversations. Each `Agent` runs a bundled `localharness` binary as a subprocess and talks to it over a local WebSocket.

> Checked on 2026-11-10 against `google-antigravity` 0.1.23 (PyPI, wheels uploaded 2026-10-28; CHANGELOG entry 2026-10-26), the `main` branch of github.com/google-antigravity/antigravity-sdk-python (README, examples, `skills/google-antigravity-sdk/`, source), antigravity.google/docs/sdk, and the `agy` CLI 1.5.3. Package status: Alpha (`Development Status :: 3 - Alpha`). Python only.

| | Antigravity SDK (Python) |
|---|---|
| Runtime | `localharness` binary shipped in the platform wheel, one subprocess per `Agent` |
| Auth | `GEMINI_API_KEY` (or `api_key=`), or Vertex / Gemini Enterprise (`vertex=True`). No Antigravity app/CLI sign-in |
| Default model | `gemini-3.8-flash` (the Antigravity app and CLI default to Gemini 4 Argon; the SDK does not) |
| Start / resume conversation | Yes: `conversation_id` + the same `save_dir` |
| Fork conversation | No |
| Structured output | `response_schema=` (JSON Schema dict/str or Pydantic class), returned through the `finish` tool |
| Default permissions (`LocalAgentConfig`) | All default tools exposed, including file writes; `run_command` denied by policy; file tools contained to `workspaces` |
| Subagents | Model-driven (`invoke_subagent`): dynamic self-clones and static `SubagentConfig`s, nested depth configurable |
| Scripted multi-agent | `beta.workflows` + `agent.beta.run_workflow()` (beta): `agent`, `parallel`, `pipeline`, `call_tool` |
| Mid-turn control | `response.cancel()` only; no steering |
| Remote / cloud agents | Not exposed in the public SDK |

---

## Installation

```bash
pip install google-antigravity          # Python >= 3.10 (classifiers list 3.10–3.13)
export GEMINI_API_KEY="..."             # Gemini Developer API key (aistudio.google.com/app/api-keys)
```

- Install from PyPI. The runtime binary is only in the platform wheels (macOS arm64/x86_64, manylinux aarch64/x86_64, Windows amd64/arm64); cloning the repo is not enough.
- Vertex / Gemini Enterprise Agent Platform: `LocalAgentConfig(vertex=True, api_key=...)` (Express mode) or `LocalAgentConfig(vertex=True, project=..., location=...)` with ADC (`gcloud auth application-default login`). `GOOGLE_GENAI_USE_VERTEXAI=True` (or `GOOGLE_GENAI_USE_ENTERPRISE=True`), `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION` work instead of kwargs; explicit kwargs win.
- A missing key raises `types.AntigravityValidationError` when the agent starts, not when the config is built.
- Local models without a key: `LiteRTAgentConfig(model_path=...)` (Gemma 4 via `pip install google-antigravity litert-lm`, about 24 GB VRAM recommended) or `LocalOpenAIAgentConfig` (Ollama, LM Studio). Both use the lightweight preset (minimal tools, no subagents).

---

## Core API

Three layers: `Agent` (layer 1, what most code uses), `Conversation` / `ChatResponse` / `Step` (layer 2, reachable as `agent.conversation`), and `ConnectionStrategy` / `Connection` (layer 3, transport).

### Agent

```python
import asyncio
from google.antigravity import Agent, LocalAgentConfig

async def main() -> None:
    config = LocalAgentConfig(system_instructions="You are an expert assistant for codebase navigation.")
    async with Agent(config) as agent:              # spawns localharness, opens the conversation
        response = await agent.chat("What files are in the current directory?")
        print(await response.text())                # drains the turn
        print(agent.conversation_id)                # persist this to resume later

asyncio.run(main())
```

| Member | Notes |
|---|---|
| `Agent(config)` | Deep-copies the config (hooks, tools, triggers, policies keep identity) |
| `async with Agent(...)` | Starts the harness; raises `ValueError` if write tools or MCP servers are enabled with an empty `policies` list and no `pre_tool_call_decide` hook |
| `await agent.chat(prompt)` | Sends one user turn, returns a `ChatResponse` immediately. `prompt` is `str`, a media object, or a list of them. Empty/whitespace prompt raises `ValueError` |
| `agent.conversation_id` | Runtime-assigned ID; set after the first exchange, `None` before start |
| `agent.conversation` | Layer-2 `Conversation`: `history` (list of `Step`), `turn_count`, `last_response`, `total_usage`, `trajectory_usages`, `compaction_indices`, `send()`, `receive_steps()`, `cancel()`, `wait_for_idle()`, `wait_for_wakeup(timeout=300.0)`, `clear_history()` |
| `agent.sandbox_status` | `SandboxStatus(available, unavailable_reason)` when the harness reported one |
| `agent.beta.run_workflow(...)` | Beta, see Workflows |

Several `chat()` calls on one open `Agent` continue the same conversation. Closing the `async with` ends the harness process; the conversation survives on disk only if `save_dir` is one you keep.

### LocalAgentConfig

`LocalAgentConfig` is a Pydantic model with keyword-only arguments. **Unknown keyword arguments are silently ignored** (Pydantic default `extra="ignore"`); for example `LocalAgentConfig(endpoint=...)`, which appears in the official prioritized-inference example, has no effect in 0.1.23 because there is no `endpoint` field. Put endpoints inside `ModelTarget`.

| Field | Default | Purpose |
|---|---|---|
| `system_instructions` | `None` | `str` (appended section), `TemplatedSystemInstructions`, or `CustomSystemInstructions` |
| `model` / `models` | `None` | Model name or `ModelTarget`; `models` for explicit text + image targets |
| `api_key`, `vertex`, `project`, `location` | `None` | Endpoint shorthand |
| `capabilities` | `CapabilitiesConfig()` | Exposed built-in tools, subagents, `run_command` options (see Permissions) |
| `policies` | `policy.confirm_run_command()` | Runtime allow/deny/ask rules |
| `workspaces` | `[os.getcwd()]` | Directories the agent works in; file tools are contained to them |
| `save_dir` | new temp dir per `Agent` | Where conversations are stored. Set it to resume later |
| `app_data_dir` | `~/.gemini/antigravity` | Artifacts, scratch files, media (`brain/`). Must be absolute |
| `conversation_id`, `session_continuation_mode` | `None` | Resume / create semantics |
| `response_schema` | `None` | Structured output schema |
| `tools` | `[]` | Custom Python tools |
| `mcp_servers` | `[]` | `McpStdioServer` / `McpStreamableHttpServer` |
| `hooks` | `[]` | Lifecycle hooks |
| `triggers` | `[]` | Background tasks that push messages |
| `subagents` | `[]` | Static `SubagentConfig`s |
| `skills_paths` / `inline_skills` | `[]` | Skills (mutually exclusive) |
| `budget_config` | `None` | `BudgetConfig` caps on model calls, tool calls, tokens |
| `compaction_config` | `None` | `CompactionConfig(token_threshold=...)` |
| `retry_config` | `None` | `RetryConfig(api_retry=..., model_output_retry=...)` |
| `env` | `None` | Extra env vars for the harness and `run_command` |
| `debug_config` | `None` | `True` or `DebugConfig(...)` for DEBUG logging and server-side tracing |

Presets (return copies, keep fields you set explicitly):
- `.lightweight()`: minimal tools (`run_command`, `view_file`, `create_file`, `edit_file`), `AgentBehavior.MINIMAL`, subagents off, compaction at 65,536 tokens.
- `.eval(thinking_level=ThinkingLevel.HIGH)`: disables `generate_image` and subagents, enables daemons, `policies=[policy.allow_all()]`, `RetryConfig.benchmark()`, sets thinking on text models.

### ChatResponse and Streaming

`ChatResponse` wraps one turn. Every iterator is an independent cursor over a shared buffer, so you can stream thoughts and text in sequence, or concurrently with `asyncio.gather`, and still call `text()` afterwards.

```python
import sys

response = await agent.chat("Refactor utils.py and explain the change.")

async for thought in response.thoughts:      # str deltas of model reasoning
    sys.stdout.write(thought)
async for call in response.tool_calls:       # types.ToolCall: name, args, id, canonical_path, server_name
    print(f"[tool] {call.name} {call.args}")
async for token in response:                 # str deltas of the answer text
    sys.stdout.write(token)

final_text = await response.text()           # full answer text (buffer already drained)
```

| Member | Notes |
|---|---|
| `async for token in response` | Answer text deltas |
| `response.thoughts` / `response.tool_calls` / `response.chunks` | Thought deltas, `ToolCall` objects, or all chunks (`types.Thought`, `types.Text`, `types.ToolCall`) |
| `await response.text()` / `await response.resolve()` | Drain; aggregated text / list of chunks |
| `await response.structured_output()` | Drain; parsed payload of the most recent `finish` step in history, or `None` (see Structured Output for the stale-value caveat) |
| `response.usage_metadata` | `UsageMetadata` for this turn: `prompt_token_count`, `cached_content_token_count`, `candidates_token_count`, `thoughts_token_count`, `total_token_count`, `service_tier`. No USD cost |
| `response.stop_reason` | `StopReason.UNSPECIFIED` on normal completion; `MAX_MODEL_CALLS_EXCEEDED`, `MAX_TOOL_CALLS_EXCEEDED`, `MAX_INPUT_TOKENS_EXCEEDED`, `MAX_OUTPUT_TOKENS_EXCEEDED`, `MAX_TOTAL_TOKENS_EXCEEDED`, `QUOTA_EXHAUSTED` |
| `await response.cancel()` | Aborts the turn; readers get `types.AntigravityCancelledError` |

`agent.conversation.history` holds `Step` objects with `type` (`TEXT_RESPONSE`, `TOOL_CALL`, `SYSTEM_MESSAGE`, `COMPACTION`, `FINISH`, `THINKING`), `status`, `content`, `thinking`, `tool_calls`, `error`, `structured_output`, `depth` (0 = root), `parent_trajectory_id` (non-empty inside subagents), `trajectory_id`, `step_index`.

### Interactive Loop

`run_interactive_loop(config)` from `google.antigravity.utils.interactive` takes a **config** (not an `Agent`), sets `AgentBehavior.INTERACTIVE`, registers an ask-question hook, and upgrades the default `run_command` deny to a y/n prompt. For development only.

---

## Session Management

A conversation is stored under `save_dir` and identified by `conversation_id`. Without `save_dir` each `Agent` writes to a fresh temp directory, so nothing can be resumed.

```python
from google.antigravity import Agent, LocalAgentConfig, types

SAVE_DIR = "/abs/path/.agent-sessions"

async with Agent(LocalAgentConfig(save_dir=SAVE_DIR)) as agent:
    await (await agent.chat("Remember: my favorite color is blue.")).text()
    conversation_id = agent.conversation_id

async with Agent(LocalAgentConfig(
    save_dir=SAVE_DIR,                                   # must be the same directory
    conversation_id=conversation_id,
    session_continuation_mode=types.SessionContinuationMode.RESUME,
)) as agent:
    print(await (await agent.chat("What is my favorite color?")).text())
```

| `SessionContinuationMode` | Behavior |
|---|---|
| `RESUME` | Resume; fail if the conversation does not exist. Requires `conversation_id` |
| `CREATE_OR_RESUME` | Resume if present, otherwise create |
| `CREATE_ONLY` | Create; fail if it already exists |
| unset | The official persistence example passes only `conversation_id` + `save_dir` and resumes; the default mode is not documented |

- `conversation_id` must be at least 32 characters of `[a-zA-Z0-9-]` (a `str(uuid.uuid4())` qualifies). Passing your own ID with `CREATE_ONLY` should let you fix the ID before the first turn; the enum documents this, but no official example shows it.
- On resume the previous steps are loaded into `agent.conversation.history`.
- No fork/branch API, no session listing or deletion API, no mid-turn steering. The CLI's conversation store (`agy --conversation`) is separate from SDK `save_dir`s.

---

## System Instructions

```python
from google.antigravity import LocalAgentConfig, types

# 1. Plain string: appended as a section to the default Antigravity system prompt
LocalAgentConfig(system_instructions="You are a strict code reviewer.")

# 2. Templated (recommended): replace the identity, append titled sections, keep the default scaffolding
LocalAgentConfig(system_instructions=types.TemplatedSystemInstructions(
    identity="You are an expert Code Quality Reviewer.",
    sections=[types.SystemInstructionSection(title="review_criteria", content="- Focus on readability.")],
))

# 3. Custom: replaces ALL default instructions (tool usage, safety, workspace paths); you supply everything
LocalAgentConfig(system_instructions=types.CustomSystemInstructions(
    text="...", title="SecurityPolicy",   # title optional (0.1.23): renders under <SecurityPolicy> instead of <System>
))
```

`SystemInstructionSection.title` defaults to `"user_system_instructions"`. `CustomSystemInstructions` drops the default description of workspaces, skills, and tool protocols; the official persona example rebuilds them by hand.

---

## Structured Output

Set `response_schema` to a Pydantic model class, a JSON Schema dict, or a JSON string. The SDK converts it to JSON Schema and attaches it to the built-in `finish` tool; the model ends the turn by calling `finish` with a matching payload.

```python
import pydantic
from google.antigravity import Agent, LocalAgentConfig

class ActionItem(pydantic.BaseModel):
    assignee: str
    task: str
    deadline: str

class MeetingSummary(pydantic.BaseModel):
    action_items: list[ActionItem]

async with Agent(LocalAgentConfig(response_schema=MeetingSummary)) as agent:
    response = await agent.chat("Summarize the meeting notes in notes.txt.")
    data = await response.structured_output()          # dict parsed from JSON, or None
    summary = MeetingSummary.model_validate(data) if data is not None else None
```

- `structured_output()` returns a plain `dict` (the official example indexes it with `.get`). Validate it yourself with `model_validate`.
- It reads the **most recent `finish` step in the whole history**, so a turn that ends without calling `finish` returns the previous turn's payload. Check that a new root-level `FINISH` step appeared in this turn (see the template).
- Keep `BuiltinTools.FINISH` in `enabled_tools` when you restrict tools; it is in `BuiltinTools.read_only()` and the defaults.
- Nested models (`$defs`/`$ref`) work in the official example. Which JSON Schema keywords the backend enforces is not documented. Malformed outputs are retried per `RetryConfig(model_output_retry=ModelOutputRetryConfig(max_retries=...))`; what happens after retries run out is not documented.
- Workflow agents take a per-call `schema=` dict instead (see Workflows).

---

## Model and Thinking Configuration

```python
from google.antigravity import (
    GeminiAPIEndpoint, GeminiModelOptions, LocalAgentConfig, ModelTarget, ServiceTier, ThinkingLevel,
)

config = LocalAgentConfig(
    model=ModelTarget(
        name="gemini-4-argon",
        endpoint=GeminiAPIEndpoint(                    # api_key falls back to GEMINI_API_KEY
            options=GeminiModelOptions(
                thinking_level=ThinkingLevel.HIGH,
                service_tier=ServiceTier.STANDARD,     # PRIORITY / FLEX also exist
                max_output_tokens=100_000,             # per-step output cap (0.1.22+)
            ),
        ),
    ),
)
# Shorthand when no options are needed: LocalAgentConfig(model="gemini-4-argon")
```

- SDK default text model: `gemini-3.8-flash`. This skill uses Gemini 4 Argon only, so always set the model explicitly, for the Agent and every `SubagentConfig`; default image model: `gemini-3.1-flash-lite-image` (`DEFAULT_MODEL`, `DEFAULT_IMAGE_GENERATION_MODEL` in `google.antigravity.models`). An explicit text model keeps the default image model unless `models=` lists an IMAGE target.
- Gemini 4 Argon: the Gemini API model page lists model code `gemini-4-argon` (stable, 1,048,576-token context, thinking low/medium/high). The SDK repo does not mention Argon and its own guide says not to guess model IDs, so verify the ID against your key before relying on it. The `agy models` IDs (`gemini-4-argon-high`, `gemini-3.8-flash-medium`, ...) are CLI aliases with effort baked in, not Gemini API IDs.
- `ThinkingLevel`: `MINIMAL`, `LOW`, `MEDIUM`, `HIGH`, `EXTRA_HIGH`. Supported levels depend on the model (Argon: low/medium/high per the Gemini API page). There is no per-turn model or thinking switch on `Agent.chat`; build a new `Agent` to change them.
- Vertex: `endpoint=VertexEndpoint(project=..., location=..., options=GeminiModelOptions(...))` (`project`/`location` and `api_key` are mutually exclusive).
- `SubagentConfig.model` takes a name only; subagents run against the agent-level endpoint.
- `capabilities.agent_behavior`: `AUTONOMOUS` (default; finishes without asking), `INTERACTIVE` (asks questions, planning; needed for `ask_question`), `MINIMAL` (trimmed prompt for small models).

---

## Tools, Capabilities, and Permissions

Two independent layers:
- **Capabilities** (`CapabilitiesConfig.enabled_tools` / `disabled_tools`, mutually exclusive) decide which built-in tools the model sees at all.
- **Policies** (`policies=[...]`) decide at call time whether a visible tool call runs. A denied tool stays in context and the model gets a denial message.

### Built-in Tools

| `BuiltinTools` | Tool name | Default |
|---|---|---|
| `VIEW_FILE` | `view_file` | on |
| `CREATE_FILE` / `EDIT_FILE` | `create_file` / `edit_file` | on |
| `RUN_COMMAND` | `run_command` | on, but denied by the default policy |
| `INVOKE_SUBAGENT` / `RUN_WORKFLOW` | `invoke_subagent` / `run_workflow` | on |
| `SEARCH_WEB` / `READ_URL_CONTENT` | `search_web` / `read_url_content` | on |
| `GENERATE_IMAGE` | `generate_image` | on |
| `SCHEDULE` | `schedule` (one-shot timer or cron) | on |
| `FINISH` | `finish` (ends turn, carries structured output) | on |
| `ASK_QUESTION` | `ask_question` | off (needs `AgentBehavior.INTERACTIVE`) |
| `LIST_DIR` / `SEARCH_DIR` / `FIND_FILE` | `list_directory` / `search_directory` / `find_file` | off (legacy; opt in via `enabled_tools`) |

Helper lists: `BuiltinTools.read_only()` = `VIEW_FILE`, `READ_URL_CONTENT`, `SCHEDULE`, `FINISH`; `.deprecated()` = the three legacy search tools; `.nondestructive()`, `.minimal()`, `.file_tools()`, `.default()`, `.all_tools()`, `.none()`.

### Default Behavior (0.1.23 source)

The README, the docs site, and the CLI's bundled SDK pointer say the agent is "read-only by default; pass `capabilities=CapabilitiesConfig()` to enable write tools". That describes the abstract `AgentConfig` default. **`LocalAgentConfig` overrides it**: its default `capabilities=CapabilitiesConfig()` exposes every default tool, including `create_file` and `edit_file`, and its default policy `confirm_run_command()` denies only `run_command`. Always set `capabilities` explicitly.

```python
from google.antigravity import BuiltinTools, CapabilitiesConfig, LocalAgentConfig, types
from google.antigravity.hooks import policy

# Read-only reviewer: only these tools are visible
read_only = LocalAgentConfig(
    workspaces=["/repo"],
    capabilities=CapabilitiesConfig(enabled_tools=[
        BuiltinTools.VIEW_FILE, BuiltinTools.LIST_DIR, BuiltinTools.SEARCH_DIR,
        BuiltinTools.FIND_FILE, BuiltinTools.FINISH,
    ]),
)

# Autonomous writer: shell allowed, shell sandboxed, file tools kept inside workspaces
writer = LocalAgentConfig(
    workspaces=["/repo"],
    capabilities=CapabilitiesConfig(
        run_command_config=types.RunCommandConfig(enable_sandbox=True, timeout_seconds=900),
    ),
    policies=[policy.workspace_only(["/repo"]), policy.allow_all()],
)
```

### Policies

`from google.antigravity.hooks import policy` (also re-exported as `google.antigravity.policy`).

| Builder | Effect |
|---|---|
| `policy.allow(tool, *, when=None)` | Approve |
| `policy.deny(tool, *, when=None, reason="")` | Reject; `reason` goes to the model |
| `policy.ask_user(tool, *, handler, when=None)` | Call `handler(tool_call[, reason]) -> bool` (sync or async) |
| `policy.allow_all()` / `policy.deny_all()` | `allow("*")` / `deny("*")` |
| `policy.confirm_run_command(handler=None)` | Deny (or ask on) `run_command`, allow the rest. The `LocalAgentConfig` default |
| `policy.safe_defaults(handler)` | Allow read-only tools, ask for everything else |
| `policy.workspace_only(workspaces)` | Keep `view_file`/`create_file`/`edit_file` inside the configured `workspaces` (the argument itself is ignored; containment uses `config.workspaces`) |
| `policy.auto(handler=None, model=None)` | Model-based safety assessment of risky calls (shell, URL fetch); flagged calls are denied or sent to `handler` |

- `tool` is a built-in name, a custom tool name, `"*"`, `"server/tool"`, `"server/*"`, or an MCP server config (`policy.allow(server_cfg, ["tool1"])`).
- `when` receives the argument dict (or a Pydantic model if annotated). If it raises, the policy matches (fail closed). The shell command argument is `args["CommandLine"]`.
- Precedence: specific deny > specific ask > specific allow > `server/*` deny > ask > allow > `*` deny > ask > allow; first match wins within a level.
- Workspace containment is on by default when workspaces are set. **`allow_all()` without `workspace_only(...)` turns it off**, letting file tools touch any path. Containment covers file tools, not `run_command`.
- Policies apply to tool calls made inside subagents too.
- Passing `policies=[]` with write tools or MCP servers enabled makes `async with Agent(...)` raise `ValueError`.

### OS Sandbox for `run_command`

`RunCommandConfig(enable_sandbox=True)` runs shell commands inside the OS sandbox ("exebox"), which blocks writes outside the workspace. If the sandbox is unavailable the command still runs unsandboxed and the SDK logs a warning; check `agent.sandbox_status.available` when it matters. Other `RunCommandConfig` fields: `timeout_seconds` (default 10 minutes), `enable_daemons` (lets `run_command(IsDaemon=True)` start background servers without blocking the turn).

The working directory `run_command` starts in is not documented. The harness process inherits the Python process's cwd; state paths in the prompt or system instructions.

### Custom Tools

Plain Python functions (sync or async). The function name is the tool name, the docstring is the description, type hints become the schema. A parameter annotated `ToolContext` is injected and hidden from the model.

```python
from google.antigravity import Agent, LocalAgentConfig, ToolContext

def record_fruit(sku: str, count: int, ctx: ToolContext) -> str:
    """Records the count of fruits by SKU."""
    counts = dict(ctx.get_state("fruit_counts", {}))
    counts[sku] = counts.get(sku, 0) + count
    ctx.set_state("fruit_counts", counts)     # session-scoped state; ctx.conversation_id also available
    return f"Total for {sku}: {counts[sku]}"

config = LocalAgentConfig(tools=[record_fruit])
```

- The default policy allows custom tools; under `deny_all()` add `policy.allow("record_fruit")`.
- Tools may return media (`types.Image.from_file(...)`) or a list mixing text and media.
- A custom tool with a built-in's name overrides the built-in.
- Raised exceptions reach the model as tool errors; shape the message with an `on_tool_error` hook.

---

## MCP Servers

```python
from google.antigravity import LocalAgentConfig, types
from google.antigravity.hooks import policy

calc = types.McpStdioServer(name="calc", command="python", args=["mcp_server.py"], env={"MODE": "safe"})
remote = types.McpStreamableHttpServer(name="docs", url="https://example.com/mcp", headers={"Authorization": "Bearer ..."})

config = LocalAgentConfig(
    mcp_servers=[calc, remote],
    policies=[policy.deny_all(), policy.allow(calc, ["multiply"]), policy.allow(remote)],
)
```

- `name` must match `^[a-zA-Z0-9_-]+$`. Common fields: `timeout_seconds`, `enabled_tools` / `disabled_tools` (hide tools from the model), `force_all_tools_eager` (load all tool schemas up front instead of through tool search).
- HTTP fields: `headers`, `timeout` (30 s), `sse_read_timeout` (300 s), `terminate_on_close`.
- MCP outputs larger than `CapabilitiesConfig.mcp_max_output_bytes` (default 4096 bytes) are written to a file instead of inlined.
- Whether the SDK also loads MCP servers from the CLI/IDE configuration under `~/.gemini` is not documented; declare them in code.

---

## Skills

```python
from google.antigravity import InlineSkill, LocalAgentConfig

LocalAgentConfig(skills_paths=["/abs/path/skills/my-skill"])          # directories with SKILL.md
LocalAgentConfig(inline_skills=[InlineSkill(
    name="custom-math",
    description="Guidance for custom math operations.",
    content="# Custom Math\nUse `add(a, b)` for addition.",
)])
```

`skills_paths` and `inline_skills` cannot be combined. The official example passes a single skill folder. Subagents inherit parent skills unless `skills_config` says otherwise (`SubagentInheritSkillsConfig(skill_names=[...])`, `SubagentNoneSkillsConfig()`, `SubagentOverrideSkillsConfig(skills_paths=..., inline_skills=...)`).

---

## Hooks

Register decorated functions (or `hooks.*Hook` subclasses with `async def run(self, context, data)`) in `hooks=[...]`.

```python
from google.antigravity import LocalAgentConfig, types
from google.antigravity.hooks import hooks

@hooks.pre_tool_call_decide
async def guard(data: types.ToolCall) -> types.HookResult:
    if data.name == "run_command" and "rm -rf" in data.args.get("CommandLine", ""):
        return types.HookResult(allow=False, message="Destructive command blocked.")
    return types.HookResult(allow=True)           # modified_args={...} rewrites arguments

@hooks.on_tool_error
async def on_error(data: Exception) -> str | None:
    return f"[Tool failed: {data}. Try another approach.]"   # None keeps the default message

@hooks.stop
async def keep_going(data: types.StopArgs) -> types.StopHookResult:
    if data.continuation_count == 0 and "TODO" in data.response_text:
        return types.StopHookResult(decision=types.StopDecision.CONTINUE, reason="Resolve the remaining TODOs.")
    return types.StopHookResult(decision=types.StopDecision.ALLOW_STOP)

config = LocalAgentConfig(hooks=[guard, on_error, keep_going])
```

| Decorator / class | Kind | Data |
|---|---|---|
| `on_session_start` / `on_session_end` | inspect | none |
| `pre_turn` / `PreTurnHook` | decide | prompt; return `HookResult` |
| `post_turn` / `PostTurnHook` | inspect | final response text |
| `pre_tool_call_decide` / `PreToolCallDecideHook` | decide | `ToolCall`; return `HookResult(allow, message, modified_args)` |
| `post_tool_call` / `PostToolCallHook` | inspect | `ToolResult` |
| `on_tool_error` / `OnToolErrorHook` | transform | exception (a `RuntimeError` carrying the message for harness tools); return replacement text or `None` |
| `on_interaction` / `OnInteractionHook` | transform | `AskQuestionInteractionSpec`; return `QuestionHookResult` |
| `on_compaction` / `OnCompactionHook` | inspect | compaction `Step` |
| `stop` / `StopHook` | transform | `StopArgs`; return `StopHookResult` (`CONTINUE` needs a non-empty `reason`) |

Subagent runs appear as `invoke_subagent` tool calls; parent hooks also fire for every tool call inside subagents. Hook state (`HookContext`) and tool state (`ToolContext`) are separate stores.

---

## Subagents

Subagents are model-driven: the root agent calls `invoke_subagent`, the subagent runs in its own context window, and its final response comes back as the tool result.

```python
from google.antigravity import LocalAgentConfig, types

fact_checker = types.SubagentConfig(
    name="fact_checker",
    description="Reads specific files and verifies factual claims.",
    system_instructions="Verify each claim against the files. Report evidence.",
    capabilities=types.SubagentCapabilities(
        enabled_tools=[types.BuiltinTools.VIEW_FILE, types.BuiltinTools.FIND_FILE],
    ),
)
lead = types.SubagentConfig(
    name="lead_researcher",
    description="Researches a topic and delegates fact-checking.",
    capabilities=types.SubagentCapabilities(
        enabled_tools=[types.BuiltinTools.VIEW_FILE, types.BuiltinTools.INVOKE_SUBAGENT],
        allowed_subagents=["fact_checker"],
    ),
    model="gemini-4-argon",
)
config = LocalAgentConfig(
    subagents=[lead, fact_checker],
    capabilities=types.CapabilitiesConfig(max_subagent_depth=3, allowed_subagents=["lead_researcher"]),
)
```

- Dynamic subagents: with no `subagents=` the model can still spawn clones of itself ("self") when `enable_subagents=True` (default) and `invoke_subagent` is enabled.
- `SubagentConfig` fields: `name`, `description`, `system_instructions` (strings/templated are appended to the subagent defaults; `CustomSystemInstructions` replaces them), `capabilities: SubagentCapabilities` (`agent_behavior`, `enabled_tools`/`disabled_tools`, `allowed_subagents`, `run_command_config`; **`None` means read-only tools**), `tools`, `model` (name only), `skills_config`.
- `max_subagent_depth` defaults to 1 (flat delegation). Unknown names in `allowed_subagents` fail validation.
- The docs say custom tools given to a subagent must also be listed in the parent's `tools`; the parent can then call them too.
- Whether the model runs several subagents concurrently, and whether subagents can run in the background, is not documented. Use workflows `parallel` or host-side `asyncio.gather` when you need guaranteed concurrency.

---

## Workflows (beta)

Scripted multi-agent orchestration that runs inside the harness through the `run_workflow` tool. The decorated function is never executed in your Python process: its source is extracted, validated (no `print()`, no top-level `return`/`yield`), and sent to the harness.

```python
from google.antigravity import Agent, LocalAgentConfig, beta, types
from google.antigravity.hooks import policy

workflows = beta.workflows

@workflows.define
async def audit_files():
    """Audit files in parallel, then synthesize."""
    workflows.phase("Audit")
    findings = await workflows.parallel(
        workflows.args["paths"],
        lambda p: workflows.agent(f"Audit {p} in one sentence.", schema={"type": "string"},
                                  role=f"Audit {p}", type_name="file_auditor"),
    )
    workflows.phase("Synthesize")
    lead = workflows.agent("You are the lead security reviewer.", role="Lead")     # multi-turn handle
    summary = await lead("Summarize:\n" + "\n".join(findings),
                         schema={"type": "object", "properties": {"summary": {"type": "string"}},
                                 "required": ["summary"]})
    workflows.log(summary["summary"])

auditor = types.SubagentConfig(name="file_auditor", description="Audits one file.",
                               capabilities=types.SubagentCapabilities(enabled_tools=[types.BuiltinTools.VIEW_FILE]))
config = LocalAgentConfig(
    workspaces=["/repo"],
    subagents=[auditor],
    capabilities=types.CapabilitiesConfig(enabled_tools=[types.BuiltinTools.RUN_WORKFLOW, types.BuiltinTools.VIEW_FILE]),
    policies=[policy.allow_all()],
)
async with Agent(config) as agent:
    result = await agent.beta.run_workflow(audit_files, args={"paths": ["/repo/auth.py", "/repo/db.py"]})
    print(result.output)            # workflow log and results; also result.response_text, result.script_path
```

| Primitive | Meaning |
|---|---|
| `phase(name)`, `log(*values)` | Progress structure and output lines |
| `agent(prompt, schema=None, role=None, type_name="self", workspace="inherit")` | Spawn an agent; await it for one turn, or keep the handle and `await handle(prompt, schema=...)` for multi-turn. `type_name` picks a `SubagentConfig` |
| `workspace=` | `"inherit"` (parent workspace), `"branch"` (isolated VCS copy such as a git worktree, removed at the end), `"share"` (separate working tree sharing repo storage) |
| `parallel(items, fn)` / `pipeline(items, fn)` | Concurrent / sequential map over items |
| `call_tool(name, **args)` | Call a tool directly; failures raise `ToolError` inside the script |
| `args` | The dict passed as `run_workflow(..., args=...)` (JSON-serializable) |

- `agent.beta.run_workflow(workflow=None, script_path=None, description="", args=None)` takes exactly one of a `@workflows.define` function or a `.py` script path (scripts use the primitives as bare names). Requires `enable_subagents=True` and `run_workflow` enabled, else `ValueError`.
- The root model is prompted to call `run_workflow`; if it does not, or the step errors, `types.ToolExecutionError` is raised. Returns `WorkflowResult` (a `ChatResponse` subclass) with `output`, `response_text`, `script_path`, `script`, `description`.
- The model can also write and run inline workflow scripts on its own during `agent.chat()` when `run_workflow` is enabled.
- Tool names inside `call_tool` follow the harness's naming (the official example uses `call_tool("read_file", Path=...)`); the full list is not documented.

---

## Triggers and Long-Running Sessions

Triggers are async background tasks that live as long as the `Agent` session and push messages into it.

```python
from google.antigravity import LocalAgentConfig
from google.antigravity.triggers import every, on_file_change

async def check_status(ctx):
    await ctx.send("Check the deployment status.")

async def on_change(ctx, changes):
    for change in changes:
        await ctx.send(f"{change.kind.value}: {change.path}")

config = LocalAgentConfig(triggers=[every(60, check_status), on_file_change("/repo/config.yaml", on_change)])
```

- `every(interval_seconds, callback)` first fires after one interval. `on_file_change(path, callback)` imports `watchfiles` lazily, so install it separately.
- Custom triggers: `@trigger` on `async def fn(ctx: TriggerContext)` (from `google.antigravity.triggers`).
- The `schedule` tool lets the model set its own one-shot timers or cron jobs; `agent.conversation.wait_for_wakeup(timeout=300.0)` blocks until the agent wakes.
- Nothing runs detached: when the Python process exits, the harness and its triggers stop. The conversation can be resumed later from `save_dir`.

---

## Budgets, Compaction, Retries, Usage

```python
from google.antigravity import LocalAgentConfig, types

config = LocalAgentConfig(
    budget_config=types.BudgetConfig(
        max_model_calls=40, max_tool_calls=80, max_total_tokens=2_000_000,
        scope=types.BudgetScope.FORWARD_LOOKING,    # LIFETIME (default) also counts usage before a resume
    ),
    compaction_config=types.CompactionConfig(token_threshold=200_000),
    retry_config=types.RetryConfig(
        api_retry=types.ModelAPIRetryConfig(max_retries=8, initial_sleep_duration_ms=1000),
        model_output_retry=types.ModelOutputRetryConfig(max_retries=3),
    ),
)
```

- A budget hit ends the turn with a non-`UNSPECIFIED` `response.stop_reason`; no exception is raised.
- Other `BudgetConfig` fields: `max_input_tokens` (net of cached), `max_output_tokens` (candidates + thoughts).
- Tool output truncation: `CapabilitiesConfig(tool_output_truncation_config=ToolOutputTruncationConfig(max_tokens=...))` or an int.
- Usage: `response.usage_metadata` (turn), `agent.conversation.total_usage` (session), `agent.conversation.trajectory_usages` (per trajectory, including subagents). Token counts only; no cost field. OpenTelemetry helpers live in `google.antigravity.utils.otel`.

---

## Image and File Input

```python
from google.antigravity import Image, Document, from_file

response = await agent.chat([
    "Compare the chart with the spec and list three risks:",
    Image.from_file("chart.png", description="Q3 latency chart"),
    from_file("spec.pdf"),                                   # picks Image/Document/Audio/Video by MIME type
    Image(data=png_bytes, mime_type="image/png"),
])
```

Supported MIME types: images `png`, `jpeg`, `webp`, `bmp`; documents `pdf`, `json`, `plain`, `csv`, `html`, `css`, `javascript`, `rtf`, `xml`; plus common audio (`wav`, `mp3`, `aac`, `ogg`, `flac`, ...) and video (`mp4`, `webm`, `quicktime`, ...). `from_bytes(data, mime_type)` is the in-memory equivalent. Unsupported types raise `ValueError`. Image generation output goes through the `generate_image` tool and is saved under `app_data_dir`.

---

## Error Handling and Cancellation

| Where | Error |
|---|---|
| Building the config | `pydantic.ValidationError` for bad values (short `conversation_id`, `RESUME` without ID, `skills_paths` + `inline_skills`, unknown `allowed_subagents`). Unknown kwargs are ignored, not rejected |
| `async with Agent(...)` | `ValueError` (write tools/MCP with empty `policies`); `types.AntigravityValidationError` (missing API key, bad endpoint); `types.AntigravityConnectionError` (harness or WebSocket failure) |
| `agent.chat()` | `ValueError` for an empty prompt; `RuntimeError` if the session was not started |
| Draining the response | `types.AntigravityExecutionError` (terminal trajectory error such as a failed model call); `types.AntigravityConnectionError`; `types.AntigravityCancelledError` after `response.cancel()` (subclass of `asyncio.CancelledError`) |
| `agent.beta.run_workflow()` | `types.ToolExecutionError` (`tool_name`, `call_id`, `step_id`), `beta.workflows.WorkflowError`, `FileNotFoundError` |
| Budget / quota | No exception; check `response.stop_reason` |

Tool failures do not raise in your code; the model sees them and continues. Catch `types.AntigravityCancelledError` before `asyncio.CancelledError` to tell a `response.cancel()` from a cancelled task.

---

## Agent Class Template (Python)

One `Agent` (harness process) per call; the conversation lives in `save_dir`. `run` starts a conversation, `continue_` resumes it with `RESUME` so a missing conversation fails instead of starting over. Each call returns the conversation ID and schema-validated data.

```python
import os
from dataclasses import dataclass
from typing import Generic, Literal, TypeVar

import pydantic
from google.antigravity import (
    Agent,
    BuiltinTools,
    CapabilitiesConfig,
    GeminiAPIEndpoint,
    GeminiModelOptions,
    LocalAgentConfig,
    ModelTarget,
    ThinkingLevel,
    types,
)
from google.antigravity.hooks import policy


class Issue(pydantic.BaseModel):
    severity: Literal["high", "medium", "low"]
    description: str


class ReviewOutput(pydantic.BaseModel):
    summary: str
    passed: bool
    issues: list[Issue]


T = TypeVar("T", bound=pydantic.BaseModel)


@dataclass
class AgentStructuredResponse(Generic[T]):
    session_id: str
    raw_text: str
    data: T
    usage: types.UsageMetadata | None


# finish carries the structured output, so it must stay enabled
READ_ONLY_TOOLS = [
    BuiltinTools.VIEW_FILE,
    BuiltinTools.LIST_DIR,
    BuiltinTools.SEARCH_DIR,
    BuiltinTools.FIND_FILE,
    BuiltinTools.FINISH,
]


def _last_root_finish(history: list[types.Step]) -> types.Step | None:
    for step in reversed(history):
        if step.type == types.StepType.FINISH and step.depth == 0 and not step.parent_trajectory_id:
            return step
    return None


class MyAgent:
    def __init__(
        self,
        save_dir: str,
        model: str = "gemini-4-argon",
        thinking_level: ThinkingLevel = ThinkingLevel.HIGH,
        system_instructions: str | None = None,
        allow_writes: bool = False,
        budget: types.BudgetConfig | None = None,
    ) -> None:
        self.save_dir = os.path.abspath(save_dir)
        self.model = model
        self.thinking_level = thinking_level
        self.system_instructions = system_instructions
        self.allow_writes = allow_writes
        # FORWARD_LOOKING: each run/continue gets its own budget instead of sharing a lifetime cap
        self.budget = budget or types.BudgetConfig(max_model_calls=60, scope=types.BudgetScope.FORWARD_LOOKING)

    async def run(self, cwd: str, prompt: str) -> AgentStructuredResponse[ReviewOutput]:
        return await self._execute(cwd, prompt)

    # Use the same cwd as the first run; save_dir is fixed per instance
    async def continue_(self, session_id: str, cwd: str, prompt: str) -> AgentStructuredResponse[ReviewOutput]:
        return await self._execute(cwd, prompt, session_id)

    def _config(self, cwd: str, session_id: str | None) -> LocalAgentConfig:
        if self.allow_writes:
            capabilities = CapabilitiesConfig(
                run_command_config=types.RunCommandConfig(enable_sandbox=True),
            )
            # allow_all() alone disables workspace containment; workspace_only keeps file tools in cwd
            policies = [policy.workspace_only([cwd]), policy.allow_all()]
        else:
            capabilities = CapabilitiesConfig(enabled_tools=READ_ONLY_TOOLS)
            policies = None  # keep the default confirm_run_command()
        return LocalAgentConfig(
            model=ModelTarget(
                name=self.model,
                endpoint=GeminiAPIEndpoint(options=GeminiModelOptions(thinking_level=self.thinking_level)),
            ),
            system_instructions=self.system_instructions,
            workspaces=[cwd],
            save_dir=self.save_dir,
            capabilities=capabilities,
            policies=policies,
            response_schema=ReviewOutput,
            budget_config=self.budget,
            conversation_id=session_id,
            session_continuation_mode=types.SessionContinuationMode.RESUME if session_id else None,
        )

    async def _execute(
        self, cwd: str, prompt: str, session_id: str | None = None
    ) -> AgentStructuredResponse[ReviewOutput]:
        cwd = os.path.abspath(cwd)
        async with Agent(self._config(cwd, session_id)) as agent:
            previous_finish = _last_root_finish(agent.conversation.history)
            response = await agent.chat(prompt)
            raw_text = await response.text()  # raises AntigravityExecutionError on fatal turn errors

            conversation_id = agent.conversation_id
            if not conversation_id:
                raise RuntimeError("runtime did not assign a conversation_id")
            if response.stop_reason != types.StopReason.UNSPECIFIED:
                raise RuntimeError(f"turn in {conversation_id} stopped early: {response.stop_reason.value}")

            # structured_output() would return an older turn's payload if this turn never called finish
            finish = _last_root_finish(agent.conversation.history)
            if finish is None or finish is previous_finish or finish.structured_output is None:
                raise RuntimeError(f"turn in {conversation_id} ended without structured output")

            return AgentStructuredResponse(
                session_id=conversation_id,
                raw_text=raw_text,
                data=ReviewOutput.model_validate(finish.structured_output),
                usage=response.usage_metadata,
            )
```

Usage:

```python
reviewer = MyAgent(save_dir=".agent-sessions/reviewer", system_instructions="You review Python code for bugs.")
first = await reviewer.run("/repo", "Review src/auth.py.")
again = await reviewer.continue_(first.session_id, "/repo", "The token check was fixed. Review again.")
```

For several turns inside one process, keep one `Agent` open and call `agent.chat()` repeatedly instead of reopening it; reopening costs a harness start per call.

---

## Orchestration Notes

For orchestration pattern design and selection, see the "How to Build Agent System" section in SKILL.md.

Antigravity SDK specifics:
- **Context passing**: serialize one agent's validated output into the next agent's prompt. There is no typed "external message" input; mark another agent's output as data in the prompt text.
- **Session resume**: persist `conversation_id` and reuse the same `save_dir`; use `SessionContinuationMode.RESUME` so a lost session fails loudly. Budgets default to `BudgetScope.LIFETIME`, which counts usage from before the resume.
- **Forking**: not supported for conversations. For speculative attempts start separate conversations; for isolated file changes use workflow agents with `workspace="branch"` or give each host-side agent its own git worktree as `workspaces`.
- **Parallel execution (host-driven)**: open several `Agent`s and run their turns with `asyncio.gather` (official `deep_dives/round_based_chat.py`). Each `Agent` is its own harness subprocess and conversation. Parallel writers need separate `workspaces`.
- **Built-in subagents (model-driven)**: `invoke_subagent` with static `SubagentConfig`s or dynamic self-clones; nesting via `max_subagent_depth` (default 1) and `allowed_subagents`. Results come back as the tool result; parent policies and hooks cover subagent tool calls. Concurrency and background execution of subagents are not documented.
- **Workflows (beta)**: `@beta.workflows.define` + `agent.beta.run_workflow()` for scripted fan-out with per-agent JSON schemas, `parallel`/`pipeline`, multi-turn workflow agents, and isolated workspaces. Runs inside the harness; use it when the fan-out shape is known in advance.
- **Background and long-running work**: triggers (`every`, `on_file_change`, `@trigger`) and the `schedule` tool keep a live session working; `RunCommandConfig(enable_daemons=True)` for servers. All of it stops with the Python process; nothing runs detached.
- **Permissions for unattended runs**: set `capabilities` explicitly (the `LocalAgentConfig` default exposes write tools). Read-only: `enabled_tools=[...]`. Writers: `[policy.workspace_only(...), policy.allow_all()]` plus `RunCommandConfig(enable_sandbox=True)`. Avoid `ask_user` policies and `ask_question` when no human is present; keep `AgentBehavior.AUTONOMOUS`.
- **Limits**: set `BudgetConfig` on every unattended agent and check `response.stop_reason`; usage is in tokens only.
- **CLI alternative**: `agy -p` (CLI 1.5.3) runs the same agent with Antigravity sign-in, Gemini 4 Argon by default, `--json-schema`, `--conversation <id>`, `--model`, `--effort`, `--output-format json`. Use it when you want the subscription and CLI settings rather than an API key; see the repo's `agy-delegation` skill.
