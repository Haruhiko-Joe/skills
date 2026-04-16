---
name: "build-agent-system-zh-cn"
description: "AI Agent 系统设计与构建指南。广泛触发：只要用户在进行任何 Agent 相关的开发工作——构建、调试、重构或讨论 Agent、Agentic 架构、工具调用模式、多 Agent 编排、Agent 工作流、自主流水线、LLM 驱动的自动化、编码 Agent 系统，均应激活。覆盖 Codex SDK、Claude Agent SDK 及通用 Agent 设计模式。即使用户未明确说'Agent'，也应从上下文推断并激活（如工具调用循环、规划/执行模式、自主任务分解）。"
---

# Build Agent System

本技能涵盖使用 **Codex SDK** 或 **Claude Agent SDK** 构建 Agent System 的完整方法论。

SDK 具体的 API 调用方式请查阅对应参考文档：
- **Codex SDK**（OpenAI）：阅读 `references/codex-sdk.md`
- **Claude Agent SDK**（Anthropic）：阅读 `references/claude-agent-sdk.md`

如需查阅 SDK 的最新官方文档，请使用 `OpenAI Docs` 或 `Anthropic Docs` 技能获取最新 API 参考。

---

## 核心概念

单个 Agent 可以抽象为：**输入字符串 → 执行操作 + 修改数据 → 返回结构化输出**。

复杂的 Agent System 由多个 Agent 编排而成，每个 Agent 承担不同职责。构建系统分两步：
1. 定义好每一个单独的 Agent
2. 将 Agent 编排为系统

---

## How to Build a Single Agent

### Agent 三要素

无论使用哪个 SDK，定义一个 Agent 都需要配置三样东西：

| 要素 | 说明 | Codex SDK | Claude Agent SDK |
|------|------|-----------|-----------------|
| **System Instruction** | 定义角色、职责和任务 workflow 的提示词 | `developer_instructions` | `systemPrompt` |
| **Output Schema** | 结构化输出格式，SDK 层面保证解析成功 | `outputSchema` (JSON Schema) | `outputFormat` (JSON Schema / Zod / Pydantic) |
| **Profile / Config** | 模型、权限、沙箱等运行参数 | `~/.codex/config.toml` profile | `options` 对象 |

### Agent Class 设计原则

每个 Agent 封装为一个 class，提供两个核心方法：
- **run**：首次执行，创建新会话
- **continue**：基于同一会话继续对话（用于多轮交互、反馈修正）

关键设计要点：
- **会话 ID**：跨调用恢复状态的基础，是多轮交互和 redo 流程的核心
- **工作目录**：限定 Agent 的文件系统操作范围
- **结构化输出**：通过 Schema 在 SDK 层面强制约束，而非依赖提示词约束（提示词约束不可靠）

具体的 class 模板和代码示例请查阅对应 SDK 的参考文档。

---

## 如何编写 System Prompt

System Prompt 决定了 Agent 的行为质量。

### 管理方式

使用 TypeScript 文件定义，而非直接用 `.md` 文件——避免额外 IO 开销，并让 prompt 与代码共存：

```typescript
export const myAgentInstruction = `
# SYSTEM PROMPT for {Agent Name}
...
`.trim();
```

在专门目录中统一管理所有 prompt：

```
src/devInstructions/
├── analyzer.ts
├── executor.ts
├── reviewer.ts
└── index.ts        # 统一导出
```

### Prompt 模板结构

```markdown
# SYSTEM PROMPT for {Agent Name}

## ROLE DEFINITION
简要定义 Agent 的职责和任务边界。明确该 Agent "是什么"和"不是什么"。

## Task Background
提供整体任务背景：整个 Agent System 在解决什么问题？其他 Agent 各自负责什么？
帮助当前 Agent 理解自己在系统中的位置，做出更合理的判断。

## ABOUT THE TASK
具体描述该 Agent 需要完成的任务：
- 需要交付什么？
- 输出会如何被下游消费？
- 任务完成的判定标准是什么？

## INPUT
描述输入的格式和含义，帮助 Agent 正确理解收到的内容。

## CONSTRAINTS
注意事项、约束边界、业务场景下的特殊规则。

## SOP
该 Agent 收到任务后的标准执行流程，按步骤列出。

## Output Example
如果使用结构化输出，描述每个字段的含义并给出完整示例。
```

### 编写原则

- **解释 why，而非堆砌 MUST**：LLM 理解了背后的原因，在边界情况下能做出远比僵硬规则更好的判断
- **提供上下文而非仅指令**：告诉 Agent 它在系统中的位置，比命令"你必须做 X"更有效
- **用示例代替长篇描述**：一个具体的输出示例，胜过三段文字说明
- **明确边界**：在 ROLE DEFINITION 中说清楚"不负责什么"，防止 Agent 越界和多个 Agent 之间职责重叠

### System Prompt 示例

以下是一个文档生成系统中 Writer Agent 的 prompt 示例，展示了各模块的填写方式：

```typescript
export const writerInstruction = `
# SYSTEM PROMPT for Writer

## ROLE DEFINITION
你是 autoDoc 系统中的 Writer Agent，负责为叶子节点生成高质量的 Markdown 文档。
你是整个文档生成流水线的最后一环——你的输出就是最终用户在文档站中看到的内容。

## Task Background
autoDoc 是一个自动文档生成系统，整个系统由以下 Agent 协作完成：
- Scaffold：顶层拆解，生成根图
- Decomposer：递归展开子图，决定哪些节点终止为文档页
- Checker：校验 Decomposer 产物的质量
- Writer（你）：为叶子节点生成最终的 Markdown 文档

## ABOUT THE TASK
当 Decomposer 的产物通过 Checker 校验后，所有 child.type = "page" 的节点分配给你。
你需要深入阅读该节点 codeScope 范围内的代码，生成一份结构完整、内容翔实的 Markdown 文档。

## INPUT
- 模块名称（name）：当前叶子节点的名称
- 模块描述（description）：Decomposer 对该节点的职责描述
- 代码范围（codeScope）：需要阅读的文件/目录路径列表
- 祖先上下文（ancestor context）（可选）：从根图到当前节点的完整层级信息

## CONSTRAINTS
1. 面向新人：读者是第一次接触项目的开发者
2. 代码驱动：所有内容必须基于实际读取到的代码，不要编造
3. 引用关键代码片段时，标注文件路径和行号

## SOP
1. 阅读代码：逐一阅读 codeScope 中的所有文件
2. 梳理结构：识别核心组件
3. 追踪调用链：理解关键流程的数据流向
4. 组织文档：按照概述、关键流程、函数签名、类型定义等章节组织
5. 输出结果

## Output Example
{ "content": "# 模块名称\\n\\n## 概述与职责\\n\\n..." }
`.trim();
```

---

## How to Build Agent System

定义好单个 Agent 后，需要将它们编排为系统。核心设计决策：

| 决策点 | 说明 |
|--------|------|
| **任务分配** | 如何将总任务拆解并分配给各 Agent |
| **Context 流转** | Agent 之间如何传递信息（直接传输出 / 共享存储 / 消息队列） |
| **完成判定** | 如何判断任务是否达标 |
| **Redo 机制** | 不达标时如何重试或回退 |

### 编排模式

#### 1. 非 LLM 编排（推荐用于确定性流程）

用代码逻辑控制 Agent 的执行顺序和条件判断。适合流程明确、步骤固定的场景。

**顺序流水线（Pipeline）**

前一个 Agent 的输出作为后一个 Agent 的输入：

```
[Analyzer] → analysis → [Executor] → result → [Reviewer] → review
```

适用于线性处理流程。实现时依次调用各 Agent 的 `run` 方法，将上一个的 `data` 序列化后作为下一个的 `prompt`。

**并行扇出 + 汇聚（Fan-out / Fan-in）**

将独立子任务并行分配给多个 Agent，收集结果后汇总：

```
           ┌→ [Worker 1] → result 1 ─┐
[Task] ────┼→ [Worker 2] → result 2 ──┼→ [Aggregator] → summary
           └→ [Worker 3] → result 3 ─┘
```

使用 `Promise.all`（TS）或 `asyncio.gather`（Python）并行执行，然后由汇聚 Agent 整合结果。

**循环校验（Loop with Checker）**

执行后由 Checker Agent 校验，不通过则将反馈送回执行 Agent 重做。这是实现质量保证的核心模式：

```
[Executor] → result → [Checker] → passed? ─Yes→ done
                          │
                          No
                          │
                          └→ feedback → [Executor.continue] → result → [Checker] → ...
```

关键点：
- 重试时使用 `continue` 而非 `run`——Agent 保留了之前出错的上下文和 Checker 的反馈，修复更有针对性。
- 务必设置 `maxRetries` 防止无限循环，3 次重试是合理的默认值。

#### 2. LLM 编排（适用于动态决策流程）

用一个 Orchestrator Agent 来决定调用哪个 Agent、传递什么参数。适合任务流程不确定、需要动态决策的场景。

Orchestrator 的结构化输出格式：

```typescript
interface OrchestratorDecision {
  nextAgent: string;      // 下一个要调用的 agent
  prompt: string;         // 传给该 agent 的 prompt
  done: boolean;          // 是否完成整个任务
  finalResult?: string;   // done=true 时的最终结果
}
```

执行循环：Orchestrator 决策 → 执行选定的 Agent → 将结果反馈给 Orchestrator → 下一轮决策，直到 `done=true`。

**注意**：Claude Agent SDK 内置了 subagent 机制，可以直接通过 `agents` 配置定义子 Agent，由 Claude 自行决定何时调用。详见 `references/claude-agent-sdk.md` 的 Subagents 章节。

### 编排模式选择指南

| 场景 | 推荐模式 | 原因 |
|------|----------|------|
| 流程固定，步骤明确 | 顺序流水线 | 简单可靠，易调试 |
| 大量同类子任务 | 并行扇出 | 充分利用并发，缩短总耗时 |
| 需要质量保证 | 循环校验 | Checker 提供自动化反馈，减少人工介入 |
| 流程动态、需临场判断 | LLM 编排 | Orchestrator 可根据中间结果灵活调整策略 |
| 复杂系统 | 组合使用 | 例如 LLM 编排 + 局部循环校验 |

---

## 项目结构建议

```
my-agent-system/
├── src/
│   ├── agents/                    # 每个 Agent 一个文件
│   │   ├── analyzer.ts
│   │   ├── executor.ts
│   │   ├── reviewer.ts
│   │   └── orchestrator.ts
│   ├── devInstructions/           # System Prompt 统一管理
│   │   ├── analyzer.ts
│   │   ├── executor.ts
│   │   └── index.ts
│   ├── utils/
│   │   ├── schemas/               # Output Schema 定义
│   │   │   ├── schemas.ts
│   │   │   └── parsers.ts
│   │   └── response.ts           # AgentStructuredResponse 类型
│   └── workflows/                 # 编排逻辑
│       ├── pipeline.ts
│       └── index.ts
├── package.json
└── tsconfig.json
```

## SDK 选择指南

| 维度 | Codex SDK (OpenAI) | Claude Agent SDK (Anthropic) |
|------|-------------------|---------------------------|
| **语言支持** | TypeScript | TypeScript + Python |
| **运行模型** | Thread/Turn 模型 | Session/Query 模型 |
| **配置方式** | TOML profile 文件 | 代码内 options 对象 |
| **子 Agent** | 需手动编排 | 内置 subagent 机制 |
| **工具系统** | 沙箱内文件操作 | 丰富的内置工具 + MCP 协议 |
| **权限控制** | `approval_policy` | `permissionMode` + hooks |
| **结构化输出** | `outputSchema` | `outputFormat` (支持 Zod/Pydantic) |

## 模型选择指南

| 维度 | Claude (Anthropic) | OpenAI |
|------|-------------------|--------|
| **文字工作** | 擅长，输出自然流畅，没有浓重的 AI 感 | 一般 |
| **前端开发** | 设计风格好，生成的 UI 代码质量高 | 一般 |
| **高难度数学 / 算法** | 一般 | 擅长，能 AC Codeforces 3000+ 的极难算法题和奥赛等级的数学题 |

选择建议：
- 文案生成、文档撰写、前端页面等偏文字和设计的任务，优先使用 Claude
- 竞赛级算法题、复杂数学推理等硬核计算任务，优先使用 OpenAI

根据项目需求选择 SDK 后，查阅对应的参考文档获取具体 API 用法。