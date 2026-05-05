# Codex SDK Reference

Codex SDK is OpenAI's SWE-agent SDK. It provides programmatic control of Codex agents in both TypeScript and Python.

---

## Installation

```bash
# TypeScript
npm install @openai/codex-sdk

# Python
pip install codex-app-server
```

TypeScript requires Node.js 18+. Python requires Python 3.10+.

---

## Core API (TypeScript)

### Codex Instance

```typescript
import { Codex } from "@openai/codex-sdk";

const codex = new Codex({
  config: {
    profile: "my-profile",                    // references a profile in config.toml
    developer_instructions: myInstruction,     // System Prompt
  },
});

// Optional: control CLI environment
const codex = new Codex({
  env: { PATH: "/usr/local/bin" },
  config: {
    show_raw_agent_reasoning: true,
    sandbox_workspace_write: { network_access: true },
  },
});
```

### Thread Management

```typescript
// Create a new thread
const thread = codex.startThread({
  workingDirectory: "/path/to/repo",
  skipGitRepoCheck: true,
});

// Resume an existing thread
const thread = codex.resumeThread(threadId, {
  workingDirectory: "/path/to/repo",
});

// Call run() repeatedly on the same Thread to continue the conversation
const turn1 = await thread.run("Diagnose the test failure");
const turn2 = await thread.run("Implement the fix");
```

### Execution and Output

```typescript
// Plain text output
const turn = await thread.run(prompt);
console.log(turn.finalResponse);

// Structured output (SDK guarantees parse success)
const turn = await thread.run(prompt, { outputSchema: mySchema });
const data = JSON.parse(turn.finalResponse);

// Get thread ID for subsequent resume
const threadId = thread.id;
```

### Streaming

`runStreamed()` provides intermediate progress — tool calls, streaming responses, file changes:

```typescript
const { events } = await thread.runStreamed("Diagnose the test failure");

for await (const event of events) {
  switch (event.type) {
    case "item.completed":
      console.log("item", event.item);
      break;
    case "turn.completed":
      console.log("usage", event.usage);
      break;
  }
}
```

### Image Input

```typescript
const turn = await thread.run([
  { type: "text", text: "Describe these screenshots and suggest fixes" },
  { type: "local_image", path: "./screenshots/error-state.png" },
  { type: "local_image", path: "./screenshots/mobile-layout.jpg" },
]);
```

Image input key points:
- Image items use `{ type: "local_image", path: "..." }`
- Mix multiple text segments and images in a single `run()` call
- `path` supports relative or absolute paths
- For URL images, download to local file first

---

## Core API (Python)

### Codex Instance

```python
from codex_app_server import Codex, AsyncCodex

# Synchronous (use context manager for cleanup)
with Codex() as codex:
    thread = codex.thread_start(model="gpt-5.5")
    result = thread.run("Diagnose the test failure")
    print(result.final_response)

# Asynchronous
async with AsyncCodex() as codex:
    thread = await codex.thread_start(model="gpt-5.5")
    result = await thread.run("Implement the fix")
    print(result.final_response)
```

### Thread Management (Python)

```python
# Create
thread = codex.thread_start(
    model="gpt-5.5",
    cwd="/path/to/repo",
    developer_instructions=my_instruction,
    approval_policy="never",
    sandbox="danger-full-access",
    config={"model_reasoning_effort": "high"},
)

# Resume
thread = codex.thread_resume(thread_id,
    model="gpt-5.5",
    cwd="/path/to/repo",
)

# Fork (branch from existing thread)
forked = codex.thread_fork(thread_id,
    cwd="/path/to/repo",
)

# List threads
threads = codex.thread_list(limit=10, sort_key="last_modified")

# Archive/unarchive
codex.thread_archive(thread_id)
codex.thread_unarchive(thread_id)

# Thread methods
thread.set_name("Feature Implementation")
thread.compact()       # compact context
messages = thread.read(include_turns=True)
```

### Execution and Output (Python)

```python
from codex_app_server import RunResult, TurnHandle

# Simple run — returns RunResult
result: RunResult = thread.run("Say hello")
print(result.final_response)   # str | None
print(result.items)            # list of actions taken
print(result.usage)            # ThreadTokenUsage | None

# Run with options
result = thread.run(prompt,
    approval_policy="never",
    cwd="/path/to/repo",
    effort="xhigh",               # low | medium | high | xhigh
    model="gpt-5.5",
    output_schema=my_schema,      # JSON Schema for structured output
    personality="pragmatic",
    sandbox_policy="danger-full-access",
    service_tier="fast",          # fast | default
    summary="Brief task description",
)

# Multi-turn: call run() repeatedly on same thread
first = thread.run("Summarize the code")
second = thread.run("Now refactor it")
```

### Turn-Level Control (Python)

For streaming, mid-turn steering, and interrupt:

```python
from codex_app_server import TurnHandle, AsyncTurnHandle

# Get a TurnHandle for fine-grained control
turn: TurnHandle = thread.turn(prompt)

# Stream events as they happen
for event in turn.stream():
    print(event)

# Or await full completion
result = turn.run()

# Mid-turn steering (inject guidance without restarting)
turn.steer("Focus on the auth module specifically")

# Interrupt execution
turn.interrupt()
```

Note: `stream()` and `run()` are mutually exclusive per turn — use one or the other.

### Image Input (Python)

```python
from codex_app_server import TextInput, ImageInput, LocalImageInput

# Local images
result = thread.run([
    TextInput("Describe what's wrong in this screenshot"),
    LocalImageInput("./screenshots/error.png"),
])

# URL images
result = thread.run([
    TextInput("Analyze this diagram"),
    ImageInput("https://example.com/architecture.png"),
])
```

Additional input types: `SkillInput(name, path)`, `MentionInput(name, path)`.

---

## Profile Configuration

Define configuration profiles in `~/.codex/config.toml`:

```toml
[profiles.reviewer]
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
approval_policy = "never"
sandbox_mode = "danger-full-access"
personality = "pragmatic"
service_tier = "fast"
```

| Field | Description |
|-------|-------------|
| `model` | Model to use (gpt-5.5 recommended for complex tasks) |
| `model_reasoning_effort` | Reasoning effort: low / medium / high / xhigh |
| `approval_policy` | Tool call approval: never / always / auto |
| `sandbox_mode` | Sandbox mode: sandbox / danger-full-access |
| `personality` | Personality style |
| `service_tier` | Service tier: fast / default |

---

## Retry Utilities (Python)

```python
from codex_app_server import retry_on_overload, is_retryable_error

# Automatic retry with exponential backoff + jitter
@retry_on_overload(max_retries=3)
def run_with_retry(thread, prompt):
    return thread.run(prompt)

# Manual check
try:
    result = thread.run(prompt)
except Exception as e:
    if is_retryable_error(e):
        await asyncio.sleep(1)
        result = thread.run(prompt)
```

---

## Agent Class Template (TypeScript)

```typescript
import { Codex, Thread, ThreadOptions } from "@openai/codex-sdk";

interface AgentStructuredResponse<T> {
  threadId: string;
  rawText: string;
  data: T;
}

export class MyAgent {
  private codex: Codex | null = null;
  private thread: Thread | null = null;
  private threadId: string | null = null;
  private threadOptions: ThreadOptions | undefined;
  private readonly profile: string;
  private readonly developerInstructions: string;

  constructor(options: { profile?: string; developerInstructions?: string } = {}) {
    this.profile = options.profile ?? "default";
    this.developerInstructions = options.developerInstructions ?? "";
  }

  async run(path: string, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    this.codex = new Codex({
      config: { profile: this.profile, developer_instructions: this.developerInstructions },
    });
    this.threadOptions = { workingDirectory: path, skipGitRepoCheck: true };
    this.thread = this.codex.startThread(this.threadOptions);
    return this.execute(prompt);
  }

  async continue(threadId: string, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    if (!this.codex) {
      this.codex = new Codex({
        config: { profile: this.profile, developer_instructions: this.developerInstructions },
      });
    }
    if (!this.thread || this.threadId !== threadId) {
      this.thread = this.codex.resumeThread(threadId, this.threadOptions);
      this.threadId = threadId;
    }
    return this.execute(prompt);
  }

  private async execute(prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    if (!this.thread) throw new Error("No active thread");
    const turn = await this.thread.run(prompt, { outputSchema: myOutputSchema });
    this.threadId = this.thread.id;
    const data = JSON.parse(turn.finalResponse) as MyOutput;
    return { threadId: this.threadId, rawText: turn.finalResponse, data };
  }
}
```

## Agent Class Template (Python)

```python
import json
from dataclasses import dataclass
from typing import TypeVar, Generic
from codex_app_server import AsyncCodex, AsyncThread, RunResult

T = TypeVar("T")

@dataclass
class AgentStructuredResponse(Generic[T]):
    thread_id: str
    raw_text: str
    data: T

class MyAgent:
    def __init__(self, model: str = "gpt-5.5", developer_instructions: str = ""):
        self.model = model
        self.developer_instructions = developer_instructions
        self.codex: AsyncCodex | None = None
        self.thread: AsyncThread | None = None

    async def run(self, path: str, prompt: str) -> AgentStructuredResponse:
        async with AsyncCodex() as codex:
            self.codex = codex
            self.thread = await codex.thread_start(
                model=self.model,
                cwd=path,
                developer_instructions=self.developer_instructions,
            )
            return await self._execute(prompt)

    async def continue_(self, thread_id: str, prompt: str) -> AgentStructuredResponse:
        if not self.codex:
            self.codex = AsyncCodex()
            await self.codex.__aenter__()
        self.thread = await self.codex.thread_resume(thread_id)
        return await self._execute(prompt)

    async def _execute(self, prompt: str) -> AgentStructuredResponse:
        if not self.thread:
            raise RuntimeError("No active thread")
        result: RunResult = await self.thread.run(prompt, output_schema=my_output_schema)
        data = json.loads(result.final_response)
        return AgentStructuredResponse(
            thread_id=self.thread.id,
            raw_text=result.final_response,
            data=data,
        )
```

---

## Orchestration Notes

For orchestration pattern design and selection guide, refer to the "How to Build Agent System" section in SKILL.md.

Codex SDK orchestration key points:
- **Context passing**: Pass serialized output between Agents via `JSON.stringify(result.data)` as the next Agent's prompt
- **Session resume**: Use `resumeThread(threadId)` (TS) or `thread_resume(thread_id)` (Python) to maintain context in loop-with-checker scenarios
- **Thread forking**: Use `thread_fork()` for speculative execution — try multiple approaches from the same state, pick the best result
- **Parallel execution**: Use `Promise.all` (TS) or `asyncio.gather` (Python) to run multiple Agents in parallel, each with its own Thread
- **Turn steering**: Use `TurnHandle.steer()` (Python) for mid-execution course correction without restarting
- **LLM orchestration**: The Orchestrator Agent drives scheduling via structured output (`{ nextAgent, prompt, done }`)
