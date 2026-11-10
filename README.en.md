# Skills

A collection of skills for extending agent capabilities.

## Skills

### build-agent-system

Guide for designing and building AI agent systems using Codex SDK, Claude Agent SDK, or Antigravity SDK. Covers multi-agent orchestration, agent workflows, and automated pipelines.

- [build-agent-system](build-agent-system/)

### agy-delegation / claude-delegation / codex-delegation

Let Claude Code, Codex, and Antigravity delegate tasks to each other. Each skill targets one callee and calls its CLI directly (`agy -p`, `claude -p`, `codex exec`); install it in the other two hosts:

| Host | Skills | Directory |
|---|---|---|
| Claude Code | agy-delegation, codex-delegation | `~/.claude/skills/` |
| Antigravity | claude-delegation, codex-delegation | `~/.gemini/config/skills/` |
| Codex | claude-delegation, agy-delegation | `~/.codex/skills/` |

```bash
./install-delegation.sh          # copies into each host's skill directory; rerun with --force after editing a skill
```

No delegation chains: every run template first checks `AGENT_BRIDGE_PARENT` and refuses if it is set, and starts the callee with `AGENT_BRIDGE_PARENT=1`, which the callee's shell tools inherit. A delegated agent can only do the work itself or use its own built-in subagents. Models are fixed: Claude uses only Opus 5.5 or Fable 5.2, OpenAI only `gpt-6-astra`, Google only Gemini 4 Argon, and the same holds for the subagents they start. Routing: fully defined math and algorithm problems go to Codex, prose for people to read goes to Antigravity, and repository changes, debugging, and review go to Claude. The host model acts as the delegated agent's user: when the agent proposes a plan, asks a question, or has an action denied, the host replies in the same session (approves, corrects, answers) and brings decisions that are yours to you. Each SKILL.md shapes task prompts according to the vendor's official prompting guide.

- [agy-delegation](agy-delegation/): writing, editing, translation, second opinions, and tasks worth running on the Antigravity subscription
- [claude-delegation](claude-delegation/): implementation, debugging, review, repository analysis
- [codex-delegation](codex-delegation/): implementation, investigation, algorithms, review
