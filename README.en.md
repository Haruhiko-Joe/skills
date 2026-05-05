# Skills

A collection of skills for extending agent capabilities.

## Skills

### build-agent-system

Guide for designing and building AI agent systems using Codex SDK or Claude Agent SDK. Covers multi-agent orchestration, agent workflows, and automated pipelines.

- [English](build-agent-system/)
- [中文](build-agent-system-zh-cn/)

### doc-drill

Progressive disclosure browser for [autoDoc](https://github.com/YanboQiao/autoDoc)-generated codebase documentation. Helps agents navigate large codebases by drilling into hierarchical documentation layer by layer — top-level overview → module graph → leaf page — loading only what's relevant to the task.

**Core idea**: autoDoc generates tree-structured docs (JSON graphs + Markdown leaves). doc-drill teaches the agent a 4-step protocol to traverse this tree efficiently:

1. **Orient** — scan top-level modules
2. **Locate** — drill into the relevant module
3. **Focus** — read the specific leaf page
4. **Search** — keyword search when unsure where to look

Includes `scripts/browse.mjs`, a CLI tool that returns the right layer of documentation on each call. Place your autoDoc output in `docs/{project}/` to make it browsable.

## Usage

Add a skill directory to Claude Code via `settings.json`:

```json
{
  "permissions": {
    "additionalDirectories": [
      "/path/to/skills/build-agent-system",
      "/path/to/skills/doc-drill"
    ]
  }
}
