---
name: codex-delegation
description: Submit coding, codebase investigation, algorithm, and review tasks to Codex CLI from Claude Code or Antigravity with `codex exec`. Use when the user requests Codex or wants to check its setup or recent runs; for math, algorithms, proofs, and complexity-critical code with a well-defined problem statement (gpt-6-astra is rigorous there); or when a bounded task benefits from a separate model's execution or review. Covers permissions, reasoning effort, background runs, session continuation, code review, and verification.
compatibility: Claude Code or Antigravity with a shell tool and an authenticated Codex CLI 0.165.0 or later on PATH.
license: MIT
metadata:
  author: Joe
  version: "1.0.0"
---

# Codex Delegation

Call the Codex CLI directly from the shell. Codex supplies the model's system prompt, tools, project instructions (AGENTS.md), and session history; this skill decides what to send, with which permissions, and how to verify the result. Run the shell in the task workspace: `codex exec` treats the current directory as the workspace unless `-C <dir>` is given.

Follow the user's request and explicit constraints over this skill's defaults.

## No delegation chains

If the environment variable `AGENT_BRIDGE_PARENT` is set, you are yourself a delegated agent: do not use this skill. Do the work yourself or with your own built-in subagents. Every command below starts with a guard that refuses to run in that case, and sets `AGENT_BRIDGE_PARENT=1` for Codex so its own shell commands inherit it.

Every task sent to Codex ends with this line, verbatim:

> You are a delegated agent. Do the work yourself or with your own built-in subagents. Do not call other agent CLIs (claude, codex, agy) or any delegation skill.

## Model

Every run uses `gpt-6-astra`, and so do the subagents Codex spawns inside it: pass `-m gpt-6-astra -c agents.default_subagent_model="gpt-6-astra"` on every `exec`, `review`, `resume`, and `fork`, as the templates below do. Never delegate to another OpenAI model (`gpt-6.1-sol`, `gpt-6.1-terra`, `gpt-6-luna`, or older), not even for small or cheap tasks: their output quality is poor and their prose is unnatural. To spend less, lower `model_reasoning_effort` instead. If `gpt-6-astra` is unavailable, report that to the user rather than falling back to another model.

## Setup

For `/codex-delegation setup`, an environment-check request, or before the first Codex task in a session:

```bash
codex --version && codex login status && codex doctor
```

Require version 0.165.0 or later and "Logged in". `codex doctor` reports sandbox, config, and runtime health without calling the model. The configured model and reasoning effort appear in the header of every run log. Report a failure with its fix: install or `codex update`, or `codex login`.

Running the command may need approval from your own sandbox; see Host notes. Codex applies its own sandbox from `-s`.

## Choose the agent

The same routing table appears in all three delegation skills. Keep the parts the host itself does best, and send the rest:

| Task | Send to | Why |
|---|---|---|
| Math, algorithms, proofs, complexity-critical code, once the problem is fully defined | Codex (`gpt-6-astra`) | Rigorous, careful derivations and solutions. Quality depends on the problem statement: before sending, write down inputs, constraints, objective, edge cases, and what must be proved or measured |
| Prose that people read: docs, articles, release notes, emails, UI copy, Chinese text; rewriting and translation | Antigravity (Gemini 4 Argon) | Natural, human-sounding writing. Also suits high-volume batches, since the subscription quota is generous |
| Multi-step changes in a real repository carried through to passing checks; debugging; code review; long unattended runs; loosely specified tasks that need judgment; charts, screenshots, and frontend UI | Claude (Opus 5.5 or Fable 5.2) | Strong at end-to-end agentic coding and review in large codebases, at catching details that don't add up, and at reporting plainly what it did and what is still open |

Split mixed tasks along these lines, for example: Codex designs and proves the algorithm, Claude integrates it into the codebase, Antigravity writes the user-facing docs. Do not send prose to Codex, and do not send under-specified math to anyone; define the problem first.

## Decide what to submit

Submit a bounded task whose result you can review. Best fits: math and algorithm problems, proofs, and complexity-critical code with a complete problem definition; also independent code review. Do not send prose for people to read; see the routing table above. Keep evolving requirements and decisions with the user. Handle the work locally when the handoff would cost more than the task itself.

Read-only tasks can run in parallel. Run one writing task per workspace at a time; `--worktree` runs a task in a managed Git worktree when parallel writes are needed. Never widen permissions to get past a failure without the user's authorization.

## Write the task

Include only what changes the result:

- Goal: the behavior or answer needed.
- Context: relevant paths, reproduction steps, prior decisions, useful evidence. Codex finds other files itself.
- Boundaries: authorized edits, interfaces to preserve, actions that need a new decision.
- Acceptance: the checks or evidence that establish completion.

For a math or algorithm task, the statement decides the quality of the answer. Before sending, write down all of these, and settle open ones with the user rather than leaving them to Codex:

- Inputs and their types, bounds, and guarantees (sorted, distinct, connected, and so on).
- The objective or the claim to prove, in exact terms; how ties and degenerate cases are handled.
- Requirements on the result: complexity, exact or approximate answer, numeric precision or modulus.
- What to hand back: the method, a proof or derivation of its correctness, the complexity, the code if wanted, and a check, such as agreement with a brute force on small random cases.

State the execution contract: complete the authorized work and its relevant verification, make reasonable assumptions for routine gaps, and report. If information or permission is missing, finish the independent parts and name the exact blocker; do not add an approval step for work the user already authorized. Ask for the conclusion first, then evidence: changes or findings, commands actually run with their outcomes, and open issues. Use the task's language. Tests should cover the change's actual risks, not restate the code. End with the no-chain line above.

Shape the prompt the way OpenAI's GPT-6 guides recommend:

- Define completion before it starts: the outcome and the check that proves it. Tell it to keep working until that outcome is met; do not ask it to stop for review after a first implementation, which pulls it toward an early stop.
- Grant permission for safe steps explicitly, for example: run the relevant tests, fix failures caused by the change, and rerun them without asking. It otherwise tends to stop and ask when input could change the result.
- Name paths and reproduction steps, and only the one or two boundaries that matter. Drop itinerary-style steps, blanket "read these docs first" rules, and generic "always add tests" rules; it tests on its own, so name the smallest relevant check instead.
- Your instructions take precedence over its skills and AGENTS.md; say so when they may conflict, and ask it to name any skill or file that made it pause or change course.
- It under-uses subagents. For broad parallel work, say when to use its own subagents.
- Ask for the report in short prose paragraphs, main point first, lists only for parallel items.

## Run a task

Always pass `-s` explicitly: the user's Codex config may default to a wider sandbox. Send the task through stdin with a quoted heredoc whose delimiter does not occur in the task; never interpolate task text into the command. Redirect stderr to a log file so the transcript stays out of the conversation; stdout carries only Codex's final message.

```bash
[ -z "$AGENT_BRIDGE_PARENT" ] || { echo "refused: nested cross-agent delegation"; exit 1; }
mkdir -p ~/.agent-bridge/logs/codex; LOG=~/.agent-bridge/logs/codex/$(date +%Y%m%d-%H%M%S)-$$.log
AGENT_BRIDGE_PARENT=1 codex exec -s read-only -m gpt-6-astra -c agents.default_subagent_model="gpt-6-astra" --skip-git-repo-check - <<'CODEX_TASK' 2>"$LOG"
Problem: given n closed intervals [l_i, r_i], find the size of the largest subset in which every two intervals share at least one point.
Input: 1 <= n <= 2*10^5; integers 0 <= l_i <= r_i <= 10^9; intervals may repeat; touching endpoints count as sharing a point.
Required: an O(n log n) algorithm, a proof that it is correct, and a Python function solve(intervals) -> int.
Done when: the function agrees with a brute force over all subsets on 1000 random cases with n <= 8. Run that check and report the command and its result. Do not write files; put the code in the final message.
Answer with the result first, then the proof, then the code, then the check.

You are a delegated agent. Do the work yourself or with your own built-in subagents. Do not call other agent CLIs (claude, codex, agy) or any delegation skill.
CODEX_TASK
echo "exit=$? log=$LOG"; grep -m1 'session id:' "$LOG"
```

Permissions, one per run:

| Flag | Effect |
|---|---|
| `-s read-only` | Default. Inspect only. |
| `-s workspace-write` | Edit files inside the workspace; `--add-dir <dir>` adds other writable directories. |
| `--approve-for-me` | Workspace-write plus automatic review of escalation requests such as network access or paths outside the workspace. Used instead of `-s`. |
| `-s danger-full-access` | No filesystem isolation. Only with explicit user authorization. |

Options:

- `-c model_reasoning_effort="<level>"`: `low`, `medium`, `high`, `xhigh`, `max`, or `ultra` (maximum reasoning plus Codex's automatic task delegation). Omit to keep the user's configured default. Use low for lookups and mechanical edits, medium for routine work, high for complex implementation or debugging, xhigh or max for hard proofs, hard algorithm design, and tightly coupled problems.
- `-c service_tier="priority"`: Fast mode at higher usage; `"default"` turns it off for one run. Omit to keep the user's setting.
- `-i <image>`: attach a screenshot or diagram (repeatable).
- `--ephemeral`: no persisted session, so no continuation.
- `--output-schema <file>`: constrain the final message to a JSON Schema when a later step parses it.
- `--json` with `-o <file>`: JSONL events on stdout and the final message in the file, for mechanical checks of commands and exit codes instead of the human transcript.

Progress of a running task: `tail -n 20 "$LOG"`. See Host notes for timeouts and background runs.

## Host notes

- Claude Code: set the Bash timeout to 600000 ms for foreground runs. For anything longer, run the same command with `run_in_background: true`; Claude Code notifies you when it exits, and TaskStop stops it when the user asks. Do not poll in a loop.
- Antigravity: the template must run outside the terminal sandbox, because it needs network access and writes under `~/.agent-bridge` and `~/.codex`. agy asks the user to approve the command each time. Allow rules cannot cover it: they do not match commands that redirect output to files. The user approves at the prompt, or runs agy with a tool permission setting that proceeds without asking. A headless `agy -p` host cannot ask at all and needs `--dangerously-skip-permissions`, which is the user's decision. For long runs, start the command in the background and check the log with `tail`.

## Review code

`codex exec review` runs Codex's built-in reviewer over a diff. A prompt is optional and scopes the review.

```bash
[ -z "$AGENT_BRIDGE_PARENT" ] || { echo "refused: nested cross-agent delegation"; exit 1; }
AGENT_BRIDGE_PARENT=1 codex exec review -m gpt-6-astra -c agents.default_subagent_model="gpt-6-astra" --uncommitted - <<'CODEX_TASK' 2>"$LOG"
Focus on concurrency and error handling in the payment module.
CODEX_TASK
```

Targets: `--uncommitted`, `--base <branch>`, or `--commit <sha>` (with optional `--title`). The review runs in the current directory.

## Continue a session

You are Codex's user for the session. A run is one turn of a conversation: when Codex asks a question, proposes an approach, or names a blocker, answer in the same session. Answer from what you know of the user's intent, and take decisions that are the user's (scope, a trade-off, a wider sandbox) to the user first.

The log header contains `session id: <uuid>`. Resume it so Codex keeps its context. `exec resume` has no `-s` or `-C`: set the sandbox with `-c` and run from the workspace.

```bash
[ -z "$AGENT_BRIDGE_PARENT" ] || { echo "refused: nested cross-agent delegation"; exit 1; }
AGENT_BRIDGE_PARENT=1 codex exec resume <session-id> -m gpt-6-astra -c agents.default_subagent_model="gpt-6-astra" --skip-git-repo-check -c sandbox_mode="workspace-write" - <<'CODEX_TASK' 2>"$LOG"
The acceptance check failed for the empty-input case. Fix it and rerun the relevant check.
CODEX_TASK
```

`codex exec fork <session-id> -m gpt-6-astra "<prompt>"` tries an alternative from the same starting point in a new session. Resumed sessions keep their earlier instructions; start a fresh task when that framing no longer fits.

## Verify

The log is the evidence: a header (model, sandbox, effort, session id), then one `exec` block per command with its working directory, result, and output, then the final message and tokens used. Compare Codex's claims with those blocks; `grep -n -A3 '^exec' "$LOG"` lists the commands. For write runs, inspect `git status` and `git diff`. For consequential changes, rerun the key acceptance check yourself or request an independent review in a fresh session.

A non-zero exit or an empty final message means the turn failed. Read the end of the log before retrying, and continue the session with targeted instructions rather than resubmitting a task that may already have changed files.

Recent runs: `ls -t ~/.agent-bridge/logs/codex | head`. Each file's header identifies the run.

## References

Checked against Codex CLI 0.167.0 on 2026-11-10: the model pin and the nesting guard by test runs; `exec review`, `fork`, `--worktree`, `--approve-for-me`, and `--output-schema` from `codex exec --help` only. CLI: [non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode), [config reference](https://learn.chatgpt.com/codex/config-file/config-reference), [changelog](https://learn.chatgpt.com/docs/changelog). Prompting: [Using GPT-6](https://developers.openai.com/api/docs/guides/prompt-guidance), [Rethinking skills and prompts for GPT-6 Astra](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra), [Codex prompting](https://learn.chatgpt.com/docs/prompting).
