# Codex SDK Reference

Codex SDK is OpenAI's SWE-agent SDK. It provides TypeScript methods for programmatic control of Codex agents.

For the latest API documentation, use the `OpenAI Docs` skill to fetch official references.

---

## Installation

```bash
npm install @openai/codex-sdk
```

## Core API

### Codex Instance

```typescript
import { Codex, Thread, ThreadOptions } from "@openai/codex-sdk";

const codex = new Codex({
  config: {
    profile: "my-profile",                    // references a profile in config.toml
    developer_instructions: myInstruction,     // System Prompt
  },
});
```

### Thread Management

```typescript
// Create a new thread
const threadOptions: ThreadOptions = {
  workingDirectory: "/path/to/repo",
  skipGitRepoCheck: true,      // allow running in non-git repositories
};
const thread = codex.startThread(threadOptions);

// Resume an existing thread (for continue scenarios)
const thread = codex.resumeThread(threadId, threadOptions);
```

### Execution and Output

```typescript
// Plain text output
const turn = await thread.run(prompt);
console.log(turn.finalResponse);   // text response

// Structured output (SDK guarantees 100% parse success)
const turn = await thread.run(prompt, { outputSchema: mySchema });
const data = JSON.parse(turn.finalResponse);

// Get thread ID (for subsequent resume)
const threadId = thread.id;
```

### Image Input

When passing images to Codex, `thread.run()` takes a structured input array instead of a single string. Text items are concatenated into the prompt, and image items use local file paths.

```typescript
const turn = await thread.run([
  { type: "text", text: "Describe the issues in these two screenshots and suggest fixes" },
  { type: "local_image", path: "./screenshots/error-state.png" },
  { type: "local_image", path: "./screenshots/mobile-layout.jpg" },
]);

console.log(turn.finalResponse);
```

Image input key points:
- Image items use the format `{ type: "local_image", path: "..." }`
- You can mix multiple text segments and multiple images in a single `run()` call
- `path` uses a relative path from the current working directory or an absolute path
- `runStreamed()` uses the same input format as `run()`

If the image source is a URL, download it to a local file first, then pass it as `local_image`.

## Profile Configuration

Define configuration profiles in `~/.codex/config.toml`, example:

```toml
[profiles.reviewer]
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
approval_policy = "never"
sandbox_mode = "danger-full-access"
personality = "pragmatic"
service_tier = "fast"
```

| Field | Description |
|-------|-------------|
| `model` | Model to use |
| `model_reasoning_effort` | Reasoning effort: low / medium / high / xhigh |
| `approval_policy` | Tool call approval policy: never / always / auto |
| `sandbox_mode` | Sandbox mode: sandbox / danger-full-access |
| `personality` | Personality style |
| `service_tier` | Service tier: fast / default |

## Agent Class Template

```typescript
import { Codex, Thread, ThreadOptions } from "@openai/codex-sdk";

interface AgentStructuredResponse<T> {
  threadId: string;
  rawText: string;
  data: T;
}

interface MyAgentOptions {
  profile?: string;
  developerInstructions?: string;
}

export class MyAgent {
  private codex: Codex | null = null;
  private thread: Thread | null = null;
  private threadId: string | null = null;
  private threadOptions: ThreadOptions | undefined;
  private readonly profile: string;
  private readonly developerInstructions: string;

  constructor(options: MyAgentOptions = {}) {
    this.profile = options.profile ?? "default";
    this.developerInstructions = options.developerInstructions ?? "";
  }

  async run(path: string, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    this.codex = new Codex({
      config: {
        profile: this.profile,
        developer_instructions: this.developerInstructions,
      },
    });
    this.threadOptions = {
      workingDirectory: path,
      skipGitRepoCheck: true,
    };
    this.thread = this.codex.startThread(this.threadOptions);
    return this.execute(prompt);
  }

  async continue(threadId: string, prompt: string): Promise<AgentStructuredResponse<MyOutput>> {
    if (!this.codex) {
      this.codex = new Codex({
        config: {
          profile: this.profile,
          developer_instructions: this.developerInstructions,
        },
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

## Orchestration Notes

For orchestration pattern design philosophy and selection guide, refer to the "How to Build Agent System" section in SKILL.md.

Codex SDK orchestration key points:
- **Context passing**: Pass serialized output between Agents via `JSON.stringify(result.data)` as the next Agent's prompt input
- **Session resume**: In loop-with-checker scenarios, use `codex.resumeThread(threadId)` to maintain context, avoiding a fresh start
- **Parallel execution**: Use `Promise.all` to invoke multiple Agent instances in parallel, each holding its own independent Thread
- **LLM orchestration**: The Orchestrator Agent drives the scheduling loop via structured output (`{ nextAgent, prompt, done }`)
