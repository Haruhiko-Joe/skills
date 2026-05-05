---
name: "build-agent-system"
description: "Guide for designing and building AI agent systems. TRIGGER broadly: whenever the user is doing any agent-related development — building, debugging, refactoring, or discussing agents, agentic architectures, tool-use patterns, multi-agent orchestration, agent workflows, autonomous pipelines, LLM-driven automation, or coding agent systems. Covers Codex SDK, Claude Agent SDK, and general agent design patterns. Activate even if the user doesn't explicitly say 'agent' — infer from context (e.g., tool-calling loops, planning/execution patterns, autonomous task decomposition)."
---

# Build Agent System

This skill covers the complete methodology for building Agent Systems using **Codex SDK** or **Claude Agent SDK**.

For specific SDK usage, refer to the corresponding reference docs:
- **Codex SDK** (OpenAI): see `references/codex-sdk.md`
- **Claude Agent SDK** (Anthropic): see `references/claude-agent-sdk.md`

For the latest official documentation, use the `OpenAI Docs` or `Anthropic Docs` skills to fetch up-to-date API references.

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

| Element | Description | Codex SDK | Claude Agent SDK |
|---------|-------------|-----------|-----------------|
| **System Instruction** | Prompt defining the role, responsibilities, and task workflow | `developer_instructions` | `systemPrompt` |
| **Output Schema** | Structured output format, guaranteed to parse at the SDK level | `outputSchema` (JSON Schema) | `outputFormat` (JSON Schema / Zod / Pydantic) |
| **Profile / Config** | Runtime parameters such as model, permissions, and sandbox | `~/.codex/config.toml` profile | `options` object |

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

**Note**: Claude Agent SDK has a built-in subagent mechanism that allows you to define sub-Agents directly through the `agents` configuration, and Claude will decide when to invoke them on its own. See the Subagents section in `references/claude-agent-sdk.md`.

### Orchestration Pattern Selection Guide

| Scenario | Recommended Pattern | Reason |
|----------|-------------------|--------|
| Fixed workflow, clear steps | Sequential Pipeline | Simple, reliable, easy to debug |
| Many similar subtasks | Fan-out | Maximizes concurrency, reduces total time |
| Quality assurance needed | Loop with Checker | Checker provides automated feedback, reduces manual intervention |
| Dynamic workflow, real-time decisions needed | LLM Orchestration | Orchestrator can flexibly adjust strategy based on intermediate results |
| Complex systems | Combination | e.g., LLM orchestration + local loop checking |

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

- Use the cheapest model that meets quality requirements per Agent. Not every Agent needs `opus` — Checkers and simple classifiers often work fine on `haiku` or `sonnet`.
- Set `maxTurns` to prevent runaway loops. A reasonable default is 10–30 for most tasks.
- Track cumulative cost via `total_cost_usd` (Claude Agent SDK) or token counts. Log per-Agent costs to identify the most expensive step.
- For fan-out patterns, estimate total cost as `cost_per_worker × number_of_workers` before scaling up.

### Debugging and Observability

- Log every Agent invocation with its prompt (truncated), session/thread ID, model, duration, and cost.
- When an Agent produces unexpected output, check the transcript (the full message stream) rather than guessing. The intermediate tool calls and reasoning reveal where things went wrong.
- In multi-Agent systems, assign each Agent a name prefix in logs (e.g., `[Analyzer]`, `[Checker]`) so you can trace the flow.
- During development, run Agents with `maxTurns: 1` or `permissionMode: "plan"` to preview their behavior without executing side effects.

---

## SDK Selection Guide

| Dimension | Codex SDK (OpenAI) | Claude Agent SDK (Anthropic) |
|-----------|-------------------|---------------------------|
| **Language Support** | TypeScript | TypeScript + Python |
| **Execution Model** | Thread/Turn model | Session/Query model |
| **Configuration** | TOML profile file | In-code options object |
| **Sub-Agents** | Manual orchestration required | Built-in subagent mechanism |
| **Tool System** | Sandboxed file operations | Rich built-in tools + MCP protocol |
| **Permission Control** | `approval_policy` | `permissionMode` + hooks |
| **Structured Output** | `outputSchema` | `outputFormat` (supports Zod/Pydantic) |

## Model Selection Guide

| Dimension | Claude (Anthropic) | OpenAI |
|-----------|-------------------|--------|
| **Text Work** | Excels — output is natural, fluent, and doesn't feel AI-generated | Average |
| **Frontend Development** | Strong design aesthetics, high-quality generated UI code | Average |
| **Hard Math / Algorithms** | Average | Excels — can AC Codeforces 3000+ extremely hard algorithm problems |

Selection advice:
- For copywriting, documentation, frontend pages, and other text/design-oriented tasks, prefer Claude
- For competition-level algorithm problems and complex mathematical reasoning, prefer OpenAI

After choosing an SDK based on your project needs, refer to the corresponding reference docs for specific API usage.