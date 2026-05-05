# Skills

一组用于扩展 Agent 能力的skills集合。

> [English](README.en.md)

## 技能列表

### build-agent-system

设计和构建 AI Agent 系统的指南，支持 Codex SDK 和 Claude Agent SDK。涵盖多 Agent 编排、Agent 工作流及自动化流水线。

- [English](build-agent-system/)
- [中文](build-agent-system-zh-cn/)

### doc-drill

为 [autoDoc](https://github.com/YanboQiao/autoDoc) 生成的代码库文档提供渐进式浏览能力。帮助 Agent 按层级逐步深入文档树——顶层概览 → 模块关系图 → 叶子页面——每次只加载与当前任务相关的内容。

**核心思路**：autoDoc 生成树状结构的文档（JSON 图 + Markdown 叶子节点）。doc-drill 为 Agent 提供一个 4 步协议来高效遍历文档树：

1. **定位全局** — 浏览顶层模块列表
2. **锁定模块** — 深入相关模块
3. **聚焦细节** — 阅读具体的叶子页面
4. **关键词搜索** — 不确定位置时按关键词查找

包含 `scripts/browse.mjs`，一个 CLI 工具，每次调用返回文档树的对应层级。将 autoDoc 输出放入 `docs/{project}/` 即可使用。

## 使用方法

在 `settings.json` 中将技能目录添加到 Claude Code：

```json
{
  "permissions": {
    "additionalDirectories": [
      "/path/to/skills/build-agent-system",
      "/path/to/skills/doc-drill"
    ]
  }
}
```
