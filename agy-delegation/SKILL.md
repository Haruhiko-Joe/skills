---
name: agy-delegation
description: Submit writing, editing, translation, repository investigation, and coding tasks to the Antigravity CLI (`agy`, Gemini 4 Argon by default) from Claude Code or Codex with `agy -p`. Use when the user asks for Antigravity, agy, Gemini, or Argon; wants natural, human-sounding prose (Chinese or English copy, docs, emails, polishing); wants a second model's opinion; or has a bounded task worth offloading to the Antigravity subscription. Covers permissions, model and effort, long runs, conversation continuation, and verification.
compatibility: Claude Code or Codex with a shell tool, jq, and an authenticated Antigravity CLI (agy) 1.5.3 or later on PATH.
license: MIT
metadata:
  author: Joe
  version: "1.0.0"
---

# Antigravity Delegation

Call the Antigravity CLI directly from the shell. agy supplies its own system prompt, tools, subagents, and rules (GEMINI.md / AGENTS.md); this skill decides what to send, with which permissions, and how to verify the result. Run the shell in the task workspace: agy treats the current directory as the workspace, and `--add-dir <dir>` adds more.

Follow the user's request and explicit constraints over this skill's defaults.

## No delegation chains

If the environment variable `AGENT_BRIDGE_PARENT` is set, you are yourself a delegated agent: do not use this skill. Do the work yourself or with your own built-in subagents. The run template below enforces this and refuses to start.

Every task sent to agy ends with this line, verbatim:

> You are a delegated agent. Do the work yourself or with your own built-in subagents. Do not call other agent CLIs (claude, codex, agy) or any delegation skill.

## Model

Every run uses Gemini 4 Argon. The templates pass `--model gemini-4-argon --effort high`; pass both, because `--model` without `--effort` drops to the model's default thinking level instead of the user's configured one. Never Gemini Flash.

agy's subagents can run on other model tiers: custom agents may declare `flash`, and the model behind the built-in `research` subagent is not documented. Only the `self` subagent type is a clone of the calling agent. No setting restricts this, so every task carries the line "Use only Gemini 4 Argon: if you start subagents, use the `self` type only." The Verify section shows how to list the subagents a run started. If Argon is unavailable, report that to the user rather than falling back.

## Setup

For `/agy-delegation setup`, an environment-check request, or before the first agy task in a session:

```bash
agy --version && agy models && agy -p "/quota"
```

Require version 1.5.3 or later and a model list (proves sign-in). `/quota` in print mode answers without starting a turn or spending quota. Report a failure with its fix: `agy update`, or run `agy` once interactively to sign in.

## Choose the agent

The same routing table appears in all three delegation skills. Keep the parts the host itself does best, and send the rest:

| Task | Send to | Why |
|---|---|---|
| Math, algorithms, proofs, complexity-critical code, once the problem is fully defined | Codex (`gpt-6-astra`) | Rigorous, careful derivations and solutions. Quality depends on the problem statement: before sending, write down inputs, constraints, objective, edge cases, and what must be proved or measured |
| Prose that people read: docs, articles, release notes, emails, UI copy, Chinese text; rewriting and translation | Antigravity (Gemini 4 Argon) | Natural, human-sounding writing. Also suits high-volume batches, since the subscription quota is generous |
| Multi-step changes in a real repository carried through to passing checks; debugging; code review; long unattended runs; loosely specified tasks that need judgment; charts, screenshots, and frontend UI | Claude (Opus 5.5 or Fable 5.2) | Strong at end-to-end agentic coding and review in large codebases, at catching details that don't add up, and at reporting plainly what it did and what is still open |

Split mixed tasks along these lines, for example: Codex designs and proves the algorithm, Claude integrates it into the codebase, Antigravity writes the user-facing docs. Do not send prose to Codex, and do not send under-specified math to anyone; define the problem first.

## Decide what to submit

Good fits: prose that should read naturally (articles, docs, release notes, emails, UI copy, Chinese writing), rewriting or translating text, a second opinion on wording or a design, and high-volume batches. For rigorous math or algorithms, or multi-step repository work, see the routing table above. Keep evolving requirements and decisions with the user. Handle the work locally when the handoff would cost more than the task.

Read-only tasks can run in parallel. Run one writing task per workspace at a time.

## Write the task

Include only what changes the result:

- Goal: the text, behavior, or answer needed. For writing: audience, purpose, tone, language, and what to avoid.
- Context: relevant paths, source material, prior decisions. agy reads other files itself.
- Boundaries: authorized edits, interfaces to preserve, actions that need a new decision.
- Acceptance: the checks or evidence that establish completion.

State the execution contract: complete the authorized work and its relevant verification, make reasonable assumptions for routine gaps, and report. If information or permission is missing, finish the independent parts and name the exact blocker. Ask for the conclusion first, then evidence. For a writing task, ask for the finished text itself in the final message, not a description of it. Use the task's language. End with the no-chain line above.

Shape the prompt the way Google's Gemini guides recommend for Gemini 4 Argon:

- Order: constraints and output format first, then context and source material, then the specific task last, introduced with a bridge such as "Based on the material above, ...". Static material first also helps implicit caching.
- Pick one structure and keep it: XML-style tags (`<constraints>`, `<context>`, `<task>`) or Markdown headings, not both.
- Plain, direct wording. Drop emphasis such as capitals, "CRITICAL", or persuasion; define any term that could be read two ways; say what to do, and also what not to do when a default is likely.
- Output is terse by default. Ask explicitly for a detailed or conversational answer when that is wanted.
- Argon does not reliably follow numeric length targets. Describe the shape instead (one paragraph, three short sections, a five-row table) and check the result.
- For tone or format, include one to three short examples of the target voice in identical formatting; vary them so it does not copy one.
- Do not ask it to show its reasoning steps in the reply; it thinks internally. Use `--effort` for depth: `low` for summaries and extraction, `medium` for routine edits, `high` (the template default) for writing that has to read well and for multi-file engineering or design.
- For multi-step work, let it run the whole plan, and state where it may assume and where it must stop. Tell it that on a non-transient error it should change approach instead of repeating the same call.

## Run a task

Pass the task through a quoted heredoc into a variable and attach it with `-p=`; never interpolate other text into the command. stdout is a stream of JSON events written to the log; the last line is the result.

```bash
[ -z "$AGENT_BRIDGE_PARENT" ] || { echo "refused: nested cross-agent delegation"; exit 1; }
mkdir -p ~/.agent-bridge/logs/agy; LOG=~/.agent-bridge/logs/agy/$(date +%Y%m%d-%H%M%S)-$$.jsonl
TASK=$(cat <<'AGY_TASK'
<constraints>
Investigate only; do not change any files. Answer in English prose, conclusion first, then evidence with file:line citations, then open questions.
</constraints>
<context>
Authentication lives under src/auth. Users report sessions expiring early after the last release.
</context>
<task>
Based on the context above, explain how session expiry is computed and checked, starting at src/auth and following its callers.
</task>

Use only Gemini 4 Argon: if you start subagents, use the `self` type only.
You are a delegated agent. Do the work yourself or with your own built-in subagents. Do not call other agent CLIs (claude, codex, agy) or any delegation skill.
AGY_TASK
)
AGENT_BRIDGE_PARENT=1 agy --model gemini-4-argon --effort high --output-format stream-json --mode accept-edits --sandbox \
  --settings '{"toolPermission":"proceed-in-sandbox"}' -p="$TASK" >"$LOG" 2>"$LOG.err"
echo "exit=$? log=$LOG"
tail -n 1 "$LOG" | jq -r '.result | "conversation: \(.conversation_id)  finished: \(.finished_reason // "complete")  denied: \([.denied_actions[]?.action] | join(","))\n\n\(.response)"'
cat "$LOG.err"
```

Modes, one per run:

| Mode | Flags | Use |
|---|---|---|
| Work (default) | `--mode accept-edits --sandbox --settings '{"toolPermission":"proceed-in-sandbox"}'` | agy reads, edits workspace files, and runs commands inside the terminal sandbox. When nothing may change, say so in the task. agy follows that, so no stricter mode is needed. |
| Plan first | `--mode plan --sandbox --settings '{"toolPermission":"proceed-in-sandbox"}'` | agy investigates, writes a plan to `~/.gemini/antigravity-cli/brain/<conversation-id>/implementation_plan.md` instead of changing files, and asks for approval. Use it when you want to see the approach first; then answer in the same conversation (see Work with agy). |
| Full access | `--dangerously-skip-permissions` | No prompts; only the system denylist and the user's own deny rules apply. Only with explicit user authorization. |

Always pass a mode: the user's agy settings may default to a different one. The sandbox has no network access and cannot reach paths outside the workspace. A headless run cannot stop to ask: when an action needs approval, the turn usually ends at once with an empty `response`, the action is listed under `denied_actions`, and `$LOG.err` names the allow rule that would permit it.

Options:

- `--model gemini-4-argon` with `--effort <level>`: `low`, `medium`, or `high` (template default). The `gemini-4-argon-low/medium/high` slugs from `agy models` are the same model with the level fixed. No other models.
- `--add-dir <dir>`: add another directory to the workspace (repeatable).
- `--json-schema <schema-or-file>`: constrain the final response when a later step parses it.
- `--print-timeout <duration>`: hard limit such as `30m`; on expiry the run exits 3 with `finished_reason: print_timeout` and a partial response.

Progress of a running task: `tail -n 5 "$LOG" | jq -c '.step_update | {step_type, tool_name, state}'`. See Host notes for timeouts and background runs.

## Host notes

- Claude Code: set the Bash timeout to 600000 ms for foreground runs. For anything longer, run the same command with `run_in_background: true`; Claude Code notifies you when it exits, and TaskStop stops it when the user asks. Do not poll in a loop.
- Codex: the command needs network access and writes outside the workspace (`~/.agent-bridge`, `~/.gemini`). If your sandbox blocks it, request escalated permission for this command instead of working around the sandbox. Give the command a long timeout (30 minutes or more), or run it in a background terminal and check the log with `tail`.

## Work with agy

You are the delegated agent's user. A headless run is one turn of a conversation: read the result, then reply in the same conversation. Do not restrict agy in advance to avoid these exchanges; have them.

- It proposes a plan (plan mode, or it chose to check first). Read the plan file, compare it with what the user asked for, then approve it by resuming in work mode, or send corrections and let it revise.
- It asks a question. Answer from what you know of the user's intent. If the answer is the user's to give (scope, a trade-off, anything irreversible), ask the user and relay the answer.
- An action was denied and the turn ended. If the user's authorization covers it, resume with the rule from `$LOG.err` added to the settings, for example `--settings '{"toolPermission":"proceed-in-sandbox","permissions":{"allow":["command(npm test)"]}}'`. If not, ask the user.
- It stopped with work left. Resume and name the open items.

```bash
AGENT_BRIDGE_PARENT=1 agy --model gemini-4-argon --effort high --output-format stream-json --conversation <conversation-id> \
  --mode accept-edits --sandbox --settings '{"toolPermission":"proceed-in-sandbox"}' -p="$TASK" >"$LOG" 2>"$LOG.err"
```

The result line carries `conversation_id`. Put the reply in `TASK` the same way as a first task, for example "Approved. Implement the plan and run the test." After two or three rounds without progress, stop and report to the user.

## Verify

The log is the evidence: an `init` event, one `step_update` event per step (tool calls carry `tool_info` with name, parameters, output, or error), and a final `result` event with `response`, `usage`, `denied_actions`, and `finished_reason`. Compare agy's claims with the tool steps: `jq -c 'select(.step_update.tool_info) | .step_update.tool_info | {name, parameters, error}' "$LOG"`. List the subagents it started with `jq -c 'select(.step_update.subagent_info) | .step_update.subagent_info.subagents[] | {type_name, role}' "$LOG"`; every `type_name` should be `self`. For write runs, inspect `git status` and `git diff`. For consequential changes, rerun the key acceptance check yourself.

Failure signs: exit code 3 with an `AGY_ERROR: {...}` line in `$LOG.err` (model or agent failure; the JSON says whether it is retryable), exit code 2 (bad flags), a `finished_reason`, or an empty `response` with `denied_actions`. Read `$LOG.err` and the last steps before retrying, and resume the conversation with targeted instructions rather than resubmitting a task that may already have changed files.

Recent runs: `ls -t ~/.agent-bridge/logs/agy | head`.

## References

Checked on 2026-11-10 against agy 1.5.3: `agy --help`, `agy changelog`, test runs of work mode and of plan mode followed by an approval through `--conversation`, [CLI reference](https://antigravity.google/docs/cli/reference), [settings](https://antigravity.google/docs/settings?tab=cli), [permissions](https://antigravity.google/docs/permissions?tab=cli), [subagents](https://antigravity.google/docs/subagents/). Prompting: [Prompt design strategies](https://aistudio.google.com/docs/prompting-strategies), [Developer's guide to Gemini 4 Argon](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/guides/gemini-4-argon).
