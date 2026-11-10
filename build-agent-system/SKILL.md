---
name: "build-agent-system"
description: "Guide for designing and building AI agent systems. TRIGGER broadly: whenever the user is doing any agent-related development — building, debugging, refactoring, or discussing agents, agentic architectures, tool-use patterns, multi-agent orchestration, agent workflows, autonomous pipelines, LLM-driven automation, or coding agent systems. Covers Codex SDK, Claude Agent SDK, Antigravity SDK, and general agent design patterns. Activate even if the user doesn't explicitly say 'agent' — infer from context (e.g., tool-calling loops, planning/execution patterns, autonomous task decomposition)."
---

# Build Agent System

This skill covers the complete methodology for building Agent Systems using **Codex SDK**, **Claude Agent SDK**, or **Antigravity SDK**.

For specific SDK usage, refer to the corresponding reference docs:
- **Codex SDK** (OpenAI): see `references/codex-sdk.md`
- **Claude Agent SDK** (Anthropic): see `references/claude-agent-sdk.md`
- **Antigravity SDK** (Google, Python): see `references/antigravity-sdk.md`

The references may lag behind the SDKs. Before relying on a specific option, check the official docs: the `claude-api` skill or [code.claude.com/docs](https://code.claude.com/docs) for the Claude Agent SDK, the `openai-docs` skill or [learn.chatgpt.com/docs](https://learn.chatgpt.com/docs) for the Codex SDK, and [antigravity.google/docs](https://antigravity.google/docs) or the [antigravity-sdk-python](https://github.com/google-antigravity/antigravity-sdk-python) repo for the Antigravity SDK.

---

## Core Concepts

A single Agent can be abstracted as: **input string → perform actions + modify data → return structured output**.

Complex Agent Systems are composed of multiple orchestrated Agents, each responsible for a different role. Building a system involves two steps:
1. Define each individual Agent
2. Orchestrate the Agents into a system

---

## How to Build a Single Agent

### Three Essentials of an Agent

Regardless of the SDK, defining an Agent requires configuring three things:

| Element | Description | Codex SDK | Claude Agent SDK | Antigravity SDK |
|---------|-------------|-----------|------------------|-----------------|
| **System Instruction** | Prompt defining the role, responsibilities, and task workflow | `developer_instructions` (config / thread options) | `systemPrompt` (TS) / `system_prompt` (Python) | `system_instructions` |
| **Output Schema** | Structured output format, guaranteed to parse at the SDK level | `outputSchema` (TS) / `output_schema` (Python), JSON Schema | `outputFormat: {type: "json_schema", schema}` (Zod via `z.toJSONSchema`, Pydantic via `model_json_schema()`) | `response_schema` (Pydantic class or JSON Schema), returned through the `finish` tool |
| **Profile / Config** | Runtime parameters such as model, permissions, and sandbox | Thread options / `thread_start` kwargs + `config` overrides (CLI profiles cannot be passed from the SDK) | `options` object | `LocalAgentConfig` (model, tools, policies, workspaces) |

### Agent Class Design Principles

Each Agent is encapsulated as a class with two core methods:
- **run**: Initial execution, creates a new session
- **continue**: Continues a conversation within the same session (for multi-turn interaction and feedback correction)

Key design points:
- **Session ID** restores state across calls — this is the foundation for multi-turn interaction and redo workflows
- **Working directory** scopes the Agent's filesystem access to a specific path
- **Structured output** is enforced via schema definitions at the SDK level, not through prompt-based constraints (which are unreliable)

For class templates and code examples, refer to the corresponding SDK reference docs.

---

## How to Write System Prompts

System Prompts determine the quality of Agent behavior.

### Management Approach

Define prompts in TypeScript files rather than raw `.md` files — this avoids extra IO and keeps prompts co-located with code:

```typescript
export const myAgentInstruction = `
# SYSTEM PROMPT for {Agent Name}
...
`.trim();
```

Organize all prompts in a dedicated directory:

```
src/devInstructions/
├── analyzer.ts
├── executor.ts
├── reviewer.ts
└── index.ts        # unified exports
```

### Prompt Template Structure

```markdown
# SYSTEM PROMPT for {Agent Name}

## ROLE DEFINITION
Briefly define the Agent's responsibilities and task boundaries. Clarify what the Agent "is" and "is not."

## Task Background
Provide overall task context: What problem is the Agent System solving? What are the other Agents responsible for?
Help the current Agent understand its position within the system to make better judgments.

## ABOUT THE TASK
Describe the specific task the Agent needs to complete:
- What needs to be delivered?
- How will the output be consumed downstream?
- What are the criteria for task completion?

## INPUT
Describe the format and meaning of the input, helping the Agent correctly understand what it receives.

## CONSTRAINTS
Caveats, boundaries, and domain-specific rules the Agent must respect.

## SOP
The standard operating procedure after the Agent receives its task, listed step by step.

## Output Example
If using structured output, describe the meaning of each field and provide a complete example.
```

### Writing Principles

- **Explain the why, not just the what**: An LLM that understands the reasoning behind a rule will handle edge cases far better than one following a rigid "MUST" directive
- **Provide context over commands**: Telling an Agent where it fits in the system is more effective than dictating "you must do X"
- **Show, don't tell**: A single concrete output example conveys more than three paragraphs of description
- **Draw clear boundaries**: In ROLE DEFINITION, state what the Agent is *not* responsible for — this prevents scope creep and overlapping work between Agents
- **State the completion condition**: Unattended Agents stop when they think they are done. Say what "done" means and which stops are acceptable (missing input, missing permission); otherwise a turn that ends with a progress report looks like a finished task

### Model-specific Notes

The template works for all three vendors; these points come from each vendor's current prompting guide.

**Claude (Opus 5.5, Fable 5.2)** — [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices), [Prompting Claude Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5), [Prompting Claude Fable 5.2](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-2):
- Separate instructions, context, and inputs with XML tags; put long documents at the top and the request at the end.
- Control depth with `effort`, not with "think carefully" lines. Do not ask the model to write its reasoning in the output; that can be refused as reasoning extraction. Ask for a short explanation or a summary of actions instead.
- An unattended run may end a turn with a progress report. Keep a checklist the Agent updates, and when items remain open, continue the session naming them; cap automatic continuations at two or three.
- Wrap untrusted text (emails, web pages, user-pasted content) in tagged blocks and tell the model that instructions inside are data.
- Fable 5.2 applies instructions as written. Cautions pile up in memory files, notes, and messages between Agents and make it hold back routine work, so delete the ones whose reason is gone, give each rule its scope, and name the steps that need no approval. "Think less" lines no longer work on it; lower `effort`.
- Fable 5.2 on a coding Agent: say who owns the code. Told nothing, it adds to the existing structure and reports nearby problems instead of fixing them; told the code base is its own, it restructures and makes unrequested changes, so review the diff.
- Fable 5.2 stops early more often at `low` and `medium` effort. For unattended Agents at those levels, add Anthropic's "Finishing work" paragraph from the guide above, and keep your own confirmation step for irreversible actions.

**OpenAI (GPT-6 family)** — [Using GPT-6](https://developers.openai.com/api/docs/guides/prompt-guidance), [Rethinking skills and prompts for GPT-6 Astra](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra):
- Define completion before it starts and tell it to keep working until the outcome is met. Do not require a review stop after the first implementation; it pulls the model toward stopping early.
- It tends to ask when input could change the result. In unattended Agents, grant permission for safe steps explicitly (run checks, fix failures caused by the change, rerun) and tell it to infer intent and scope.
- It follows skills and AGENTS.md closely. Audit them, and state that the task's instructions take precedence over skill guidance.
- It under-uses subagents; say when to use them. Drop itinerary-style steps and blanket "always test" rules that older prompts needed.

**Gemini (Gemini 4 Argon)** — [Prompt design strategies](https://aistudio.google.com/docs/prompting-strategies), [Developer's guide to Gemini 4 Argon](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/guides/gemini-4-argon):
- Put constraints, role, and output format first, then context and documents, then the specific task last ("Based on the information above, ..."). Static content first also helps implicit caching.
- Use one structure consistently (XML-style tags or Markdown headings). Write plainly; emphatic wording such as "CRITICAL" or capitals does not help.
- Output is terse by default; ask explicitly for detail. It does not follow numeric length targets, so describe the shape of the output instead. Include a few consistently formatted examples for tone and format.
- Control depth with the thinking level, not with requests to show reasoning. In agentic prompts, say where it may assume and where it must stop, and that on a non-transient error it should change approach rather than repeat the call.

### System Prompt Example

Here is a prompt example for a Writer Agent in a documentation generation system, demonstrating how to fill in each section:

```typescript
export const writerInstruction = `
# SYSTEM PROMPT for Writer

## ROLE DEFINITION
You are the Writer Agent in the autoDoc system, responsible for generating high-quality Markdown documentation for leaf nodes.
You are the final step in the documentation generation pipeline — your output is what end users see on the documentation site.

## Task Background
autoDoc is an automated documentation generation system. The entire system is completed through the collaboration of the following Agents:
- Scaffold: Top-level decomposition, generates the root graph
- Decomposer: Recursively expands subgraphs, decides which nodes terminate as document pages
- Checker: Validates the quality of Decomposer outputs
- Writer (you): Generates the final Markdown documentation for leaf nodes

## ABOUT THE TASK
After the Decomposer's output passes the Checker validation, all nodes with child.type = "page" are assigned to you.
You need to thoroughly read the code within the node's codeScope range and generate a well-structured, comprehensive Markdown document.

## INPUT
- Module name (name): The name of the current leaf node
- Module description (description): The Decomposer's description of the node's responsibilities
- Code scope (codeScope): List of file/directory paths to read
- Ancestor context (optional): Complete hierarchy information from the root graph to the current node

## CONSTRAINTS
1. Audience is new developers encountering the project for the first time
2. All content must be grounded in actual code — never fabricate
3. When referencing key code snippets, annotate with file path and line number

## SOP
1. Read code: Read all files in codeScope one by one
2. Analyze structure: Identify core components
3. Trace call chains: Understand data flow of key processes
4. Organize documentation: Structure by overview, key processes, function signatures, type definitions, etc.
5. Output result

## Output Example
{ "content": "# Module Name\\n\\n## Overview and Responsibilities\\n\\n..." }
`.trim();
```

---

## How to Build Agent System

After defining individual Agents, you need to orchestrate them into a system. Key design decisions:

| Decision Point | Description |
|----------------|-------------|
| **Task Assignment** | How to decompose and assign the overall task to each Agent |
| **Context Flow** | How Agents pass information (direct output / shared storage / message queue) |
| **Completion Criteria** | How to determine if the task meets the standard |
| **Redo Mechanism** | How to retry or rollback when the standard is not met |

### Orchestration Patterns

#### 1. Non-LLM Orchestration (Recommended for deterministic workflows)

Use code logic to control the execution order and conditional branching of Agents. Suitable for scenarios with clear, fixed-step workflows.

**Sequential Pipeline**

The output of one Agent serves as the input for the next:

```
[Analyzer] → analysis → [Executor] → result → [Reviewer] → review
```

Suitable for linear processing workflows. Call each Agent's `run` method in sequence, serializing the previous Agent's `data` as the next Agent's `prompt`.

**Fan-out / Fan-in**

Assign independent subtasks to multiple Agents in parallel, then aggregate the results:

```
           ┌→ [Worker 1] → result 1 ─┐
[Task] ────┼→ [Worker 2] → result 2 ──┼→ [Aggregator] → summary
           └→ [Worker 3] → result 3 ─┘
```

Use `Promise.all` (TS) or `asyncio.gather` (Python) for parallel execution, then have an Aggregator Agent consolidate the results.

**Loop with Checker**

After execution, a Checker Agent validates the result. If it fails, feedback is sent back to the Executor Agent for a redo. This is the core pattern for quality assurance:

```
[Executor] → result → [Checker] → passed? ─Yes→ done
                          │
                          No
                          │
                          └→ feedback → [Executor.continue] → result → [Checker] → ...
```

Key points:
- Use `continue` (not `run`) for retries — the Agent retains context about what went wrong and the Checker's feedback, leading to more targeted fixes.
- Always set `maxRetries` to prevent infinite loops. 3 retries is a reasonable default.

#### 2. LLM Orchestration (For dynamic decision workflows)

Use an Orchestrator Agent to decide which Agent to call and what parameters to pass. Suitable for scenarios where the workflow is uncertain and requires dynamic decision-making.

Orchestrator's structured output format:

```typescript
interface OrchestratorDecision {
  nextAgent: string;      // the next agent to call
  prompt: string;         // prompt to pass to that agent
  done: boolean;          // whether the entire task is complete
  finalResult?: string;   // final result when done=true
}
```

Execution loop: Orchestrator decides → Execute the selected Agent → Feed result back to the Orchestrator → Next decision, until `done=true`.

**Note**: all three SDKs also let the model itself spawn subagents, so an Orchestrator can be the SDK's own agent instead of your loop:
- Claude Agent SDK: subagents defined in the `agents` option (`AgentDefinition`), dispatched through the `Agent` tool.
- Codex: built-in multi-agent (`features.multi_agent`, on by default), with custom roles in `.codex/agents/*.toml` and limits under `[agents]`.
- Antigravity SDK: `SubagentConfig` entries or dynamic self-clones; nesting depth defaults to 1.

See each reference's Subagents section.

#### 3. Background Subagents (Claude Agent SDK)

Subagents launched through the `Agent` tool run in the background by default (`AgentDefinition.background: true` forces it). The tool returns at once with `status: "async_launched"`, the main agent keeps working, and the report arrives later as a task notification:

```
[Main Agent] ──────────────────────────────→ continues working
      │
      └── spawn ──→ [Background Agent] ──→ task_notification → next turn
```

- In a one-shot `query()`, the final result waits for background subagents. With streaming input, each finished background task starts a new turn whose result carries `origin.kind: "task-notification"`.
- Lifecycle arrives as `system` messages (`task_started`, `task_progress`, `task_notification`); stop one with `stopTask()` / `stop_task()`.
- `maxBudgetUsd` covers subagent spend. Nesting depth and concurrency are capped (defaults 3 and 20).
- For dozens to hundreds of agents, the `Workflow` tool (TS) runs a coordination script outside the conversation context.

Useful for a monitoring agent alongside the main one, parallel research, or long tasks that should not block the main flow.

#### 4. Forking (speculative execution)

Branch from the same state, try several approaches in parallel, then pick the best:

```
[Session A] ─── fork ──┬→ [Session B: approach 1] → result 1
                        └→ [Session C: approach 2] → result 2
                               ↓
                        [Pick best] → final result
```

- Claude Agent SDK: `forkSession: true` on resume, or `forkSession()` / `fork_session()`; `resumeSessionAt` forks from a specific message. Inside a session, the `fork` subagent type copies the current conversation.
- Codex: `thread_fork()` in the Python SDK; the TS SDK has no fork (the CLI has `codex exec fork`).
- Antigravity SDK: no conversation fork. Workflow agents can work on an isolated copy of the repo (`workspace="branch"`).

Run the branches with `Promise.all` / `asyncio.gather`; the original session stays untouched.

### Orchestration Pattern Selection Guide

| Scenario | Recommended Pattern | Reason |
|----------|-------------------|--------|
| Fixed workflow, clear steps | Sequential Pipeline | Simple, reliable, easy to debug |
| Many similar subtasks | Fan-out | Maximizes concurrency, reduces total time |
| Quality assurance needed | Loop with Checker | Checker provides automated feedback, reduces manual intervention |
| Dynamic workflow, real-time decisions needed | LLM Orchestration | Orchestrator can flexibly adjust strategy based on intermediate results |
| Long task + non-blocking side work | Background Subagents | Main agent continues while background agents handle secondary tasks |
| Need to explore multiple solutions | Forking | Try approaches in parallel without contaminating the base state |
| Complex systems | Combination | e.g., LLM orchestration + local loop checking + background agents |

---

## Suggested Project Structure

```
my-agent-system/
├── src/
│   ├── agents/                    # one file per Agent
│   │   ├── analyzer.ts
│   │   ├── executor.ts
│   │   ├── reviewer.ts
│   │   └── orchestrator.ts
│   ├── devInstructions/           # centralized System Prompt management
│   │   ├── analyzer.ts
│   │   ├── executor.ts
│   │   └── index.ts
│   ├── utils/
│   │   ├── schemas/               # Output Schema definitions
│   │   │   ├── schemas.ts
│   │   │   └── parsers.ts
│   │   └── response.ts           # AgentStructuredResponse type
│   └── workflows/                 # orchestration logic
│       ├── pipeline.ts
│       └── index.ts
├── package.json
└── tsconfig.json
```

---

## Practical Tips

### Error Handling and Retries

Agent calls can fail due to rate limits, network issues, or malformed output. Design for this:

- Wrap each Agent call in a try/catch. On transient errors (rate limits, timeouts), retry with exponential backoff.
- In a Loop with Checker pattern, cap retries via `maxRetries`. If the Checker rejects output 3 times, escalate rather than loop forever.
- When using `continue` for retries, the session preserves prior context — the Agent knows what failed. A fresh `run` loses that history, so only use it as a last resort.

### Cost and Token Management

Multi-agent systems multiply API costs. Keep this under control:

- Models are fixed per vendor: Claude Opus 5.5 or Fable 5.2, OpenAI `gpt-6-astra`, Google Gemini 4 Argon. Never use Sonnet, Haiku, Gemini Flash, or the other GPT-6 models, not even for checkers or fan-out workers; their quality is not good enough. Cut cost with lower effort instead.
- Lower effort before switching models: `effort` (Claude), `model_reasoning_effort` (Codex), and the thinking level (Antigravity) control depth and cost.
- Cap runaway loops: `maxTurns` / `max_turns` and `maxBudgetUsd` (Claude, which also covers subagent spend), `BudgetConfig` limits on model calls, tool calls, and tokens (Antigravity, reported through `stop_reason`). Codex has no turn cap in the SDK; bound it in your own loop.
- Track cost per Agent: `total_cost_usd` on the Claude result message, token `usage` on Codex turns, token usage on Antigravity responses (no USD). Log per-Agent totals to find the most expensive step.
- For fan-out patterns, estimate total cost as `cost_per_worker × number_of_workers` before scaling up.
- Codex Python SDK's `retry_on_overload()` wraps a call with backoff for overload errors; Antigravity has `RetryConfig`.

### Debugging and Observability

- Log every Agent invocation with its prompt (truncated), session/thread ID, model, duration, and cost.
- When an Agent produces unexpected output, check the transcript (the full message stream) rather than guessing. The intermediate tool calls and reasoning reveal where things went wrong.
- In multi-Agent systems, assign each Agent a name prefix in logs (e.g., `[Analyzer]`, `[Checker]`) so you can trace the flow.
- During development, preview behavior without side effects: `permissionMode: "plan"` or a low `maxTurns` (Claude), a `read-only` sandbox (Codex), or write tools disabled with the default policies, which deny the shell (Antigravity).

---

## SDK Selection Guide

All three are full agent runtimes. The choice depends on the model you want, the language, and which controls you need.

| Dimension | Codex SDK (OpenAI) | Claude Agent SDK (Anthropic) | Antigravity SDK (Google) |
|-----------|-------------------|------------------------------|--------------------------|
| **Language** | TypeScript + Python | TypeScript + Python | Python only (alpha) |
| **Execution Model** | Thread / turn | Session / query | `Agent` + conversation; one bundled local runtime process per `Agent` |
| **Auth / Billing** | ChatGPT sign-in or API key | Claude sign-in or API key | `GEMINI_API_KEY` or Vertex / Gemini Enterprise; not the Antigravity subscription (for that, call `agy -p`) |
| **Configuration** | Thread options + `config` overrides of config.toml keys | In-code `options` + `.claude/` settings | `LocalAgentConfig` |
| **Sub-Agents** | Built-in multi-agent, roles in `.codex/agents/*.toml` | `agents` option; background by default; `fork` subagent; `Workflow` tool (TS) | `SubagentConfig` or self-clones; beta workflows (`agent`, `parallel`, `pipeline`) |
| **Permission Control** | Sandbox mode + approval policy (Python default: `auto_review` reviewer) | `permissionMode` (6 modes) + `allowedTools` + hooks | Tool visibility (`enabled_tools`) + runtime policies (allow / deny / ask / auto); shell denied by default; optional OS sandbox |
| **Structured Output** | `outputSchema` / `output_schema` | `outputFormat` (json_schema) | `response_schema` via the `finish` tool |
| **Mid-execution Control** | Python: `steer()` / `interrupt()`; TS: abort only | `interrupt()`, `setModel()`, `rewindFiles()`, `stopTask()` | `cancel()` only |
| **Background / Long-running** | Goals exist in the CLI but not in the SDK; many concurrent turns per `AsyncCodex` | Background subagents and task notifications; cross-host resume via `sessionStore` | Triggers and schedules (stop when the process exits); resume from `save_dir` |
| **Session Branching** | Python `thread_fork()` | `forkSession` / `forkSession()` / `resumeSessionAt` | None (workflow agents can use a repo branch) |

## Model Selection Guide

| Dimension | Claude (Anthropic) | OpenAI | Google |
|-----------|-------------------|--------|--------|
| **Models to use** | Opus 5.5 (`claude-opus-5-5`) or Fable 5.2 (`claude-fable-5-2`) only | `gpt-6-astra` only | Gemini 4 Argon only |
| **Depth control** | `effort` (`low`–`max`), thinking always on. API default is `medium` on Opus 5.5 and `high` on Fable 5.2, so set it explicitly | `model_reasoning_effort` (`low`–`ultra`) | Thinking level |
| **Cost control** | Lower `effort`; Opus 5.5 as the default, Fable 5.2 for the hardest reasoning, planning, and long unattended runs | Lower effort | Lower thinking level |

Assign each Agent in the system to the model that fits its role:

| Agent role | Model | Why |
|---|---|---|
| Solves math or algorithm problems, writes proofs or complexity-critical code from a complete specification | `gpt-6-astra` (Codex SDK) | Rigorous, careful solutions when the problem is fully defined. Have an upstream Agent (or your code) produce the full statement first: inputs, constraints, objective, edge cases, what must be proved |
| Writes prose people will read: docs, reports, copy, Chinese text; rewrites and translates | Gemini 4 Argon (Antigravity SDK) | Natural, human-sounding writing |
| Implements and debugs in a real repository, reviews code, runs long unattended, or handles loosely specified work that needs judgment; reads charts and screenshots; builds frontend UI | Claude Opus 5.5 (Claude Agent SDK) | Strong at end-to-end agentic coding and review in large codebases, catches details that don't add up, reports plainly what it did and what remains |
| Orchestrator / Checker | Claude Fable 5.2 or Opus 5.5, or the allowed model of the SDK you use | Judgment over other Agents' output; a Checker should not be weaker than the Agent it checks. Anthropic reports good results with Fable 5.2 as planner and orchestrator for other models |
| High-volume, mechanical workers | The same models at low effort | Smaller models are not used; lowering effort is the cost lever |

Never assign an Agent, a subagent, or a Checker to any other model: not Claude Sonnet or Haiku, not Gemini Flash (the Antigravity SDK default, so always set `model` explicitly), and not the other GPT-6 models (`gpt-6.1-sol`, `gpt-6.1-terra`, `gpt-6-luna`). Pin subagent models too: `agents.default_subagent_model` (Codex), the `model` field of each `AgentDefinition` (Claude), `SubagentConfig.model` (Antigravity). All three SDKs set the model per Agent, so one system can mix vendors, for example Astra for the algorithm core, Claude for integration and review, Argon for the documentation.

After choosing an SDK, refer to the corresponding reference doc for specific API usage.
