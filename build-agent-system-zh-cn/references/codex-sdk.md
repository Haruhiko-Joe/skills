# Codex SDK Reference

Codex SDK 是 OpenAI 推出的 SWE-agent SDK，支持 TypeScript 和 Python，用编程方式操控 Codex agent。

---

## 安装

```bash
# TypeScript
npm install @openai/codex-sdk

# Python
pip install codex-app-server
```

TypeScript 需要 Node.js 18+，Python 需要 3.10+。

---

## 核心 API（TypeScript）

### Codex 实例

```typescript
import { Codex } from "@openai/codex-sdk";

const codex = new Codex({
  config: {
    profile: "my-profile",                    // 引用 config.toml 中的 profile
    developer_instructions: myInstruction,     // System Prompt
  },
});

// 可选：控制 CLI 环境
const codex = new Codex({
  env: { PATH: "/usr/local/bin" },
  config: {
    show_raw_agent_reasoning: true,
    sandbox_workspace_write: { network_access: true },
  },
});
```

### Thread 管理

```typescript
// 创建新 thread
const thread = codex.startThread({
  workingDirectory: "/path/to/repo",
  skipGitRepoCheck: true,
});

// 恢复已有 thread
const thread = codex.resumeThread(threadId, {
  workingDirectory: "/path/to/repo",
});

// 在同一 Thread 上反复调用 run() 即可延续对话
const turn1 = await thread.run("诊断测试失败原因");
const turn2 = await thread.run("实施修复");
```

### 执行与输出

```typescript
// 普通文本输出
const turn = await thread.run(prompt);
console.log(turn.finalResponse);

// 结构化输出（SDK 保证解析成功）
const turn = await thread.run(prompt, { outputSchema: mySchema });
const data = JSON.parse(turn.finalResponse);

// 获取 thread ID 用于后续 resume
const threadId = thread.id;
```

### 流式输出

`runStreamed()` 提供中间进度——工具调用、流式响应、文件变更：

```typescript
const { events } = await thread.runStreamed("诊断测试失败原因");

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

### 图像输入

```typescript
const turn = await thread.run([
  { type: "text", text: "描述这些截图中的问题并给出修复建议" },
  { type: "local_image", path: "./screenshots/error-state.png" },
  { type: "local_image", path: "./screenshots/mobile-layout.jpg" },
]);
```

图像输入要点：
- 图像项格式为 `{ type: "local_image", path: "..." }`
- 可在一次 `run()` 中混合多段文本和多张图像
- `path` 支持相对路径或绝对路径
- URL 图像需先下载到本地文件

---

## 核心 API（Python）

### Codex 实例

```python
from codex_app_server import Codex, AsyncCodex

# 同步（使用 context manager 确保清理）
with Codex() as codex:
    thread = codex.thread_start(model="gpt-5.5")
    result = thread.run("诊断测试失败原因")
    print(result.final_response)

# 异步
async with AsyncCodex() as codex:
    thread = await codex.thread_start(model="gpt-5.5")
    result = await thread.run("实施修复")
    print(result.final_response)
```

### Thread 管理（Python）

```python
# 创建
thread = codex.thread_start(
    model="gpt-5.5",
    cwd="/path/to/repo",
    developer_instructions=my_instruction,
    approval_policy="never",
    sandbox="danger-full-access",
    config={"model_reasoning_effort": "high"},
)

# 恢复
thread = codex.thread_resume(thread_id,
    model="gpt-5.5",
    cwd="/path/to/repo",
)

# 分叉（从已有 thread 创建分支）
forked = codex.thread_fork(thread_id,
    cwd="/path/to/repo",
)

# 列出 thread
threads = codex.thread_list(limit=10, sort_key="last_modified")

# 归档/取消归档
codex.thread_archive(thread_id)
codex.thread_unarchive(thread_id)

# Thread 方法
thread.set_name("功能实现")
thread.compact()       # 压缩上下文
messages = thread.read(include_turns=True)
```

### 执行与输出（Python）

```python
from codex_app_server import RunResult, TurnHandle

# 简单执行——返回 RunResult
result: RunResult = thread.run("打个招呼")
print(result.final_response)   # str | None
print(result.items)            # 已执行的操作列表
print(result.usage)            # ThreadTokenUsage | None

# 带选项执行
result = thread.run(prompt,
    approval_policy="never",
    cwd="/path/to/repo",
    effort="xhigh",               # low | medium | high | xhigh
    model="gpt-5.5",
    output_schema=my_schema,      # 结构化输出的 JSON Schema
    personality="pragmatic",
    sandbox_policy="danger-full-access",
    service_tier="fast",          # fast | default
    summary="简要任务描述",
)

# 多轮：在同一 thread 上反复调用 run()
first = thread.run("总结代码")
second = thread.run("现在重构它")
```

### Turn 级别控制（Python）

用于流式输出、中途转向和中断：

```python
from codex_app_server import TurnHandle, AsyncTurnHandle

# 获取 TurnHandle 进行细粒度控制
turn: TurnHandle = thread.turn(prompt)

# 流式接收事件
for event in turn.stream():
    print(event)

# 或等待完整结果
result = turn.run()

# 中途转向（注入指导而不重启）
turn.steer("专注于 auth 模块")

# 中断执行
turn.interrupt()
```

注意：`stream()` 和 `run()` 每个 turn 只能用其中一个。

### 图像输入（Python）

```python
from codex_app_server import TextInput, ImageInput, LocalImageInput

# 本地图像
result = thread.run([
    TextInput("描述这张截图中的问题"),
    LocalImageInput("./screenshots/error.png"),
])

# URL 图像
result = thread.run([
    TextInput("分析这张架构图"),
    ImageInput("https://example.com/architecture.png"),
])
```

其他输入类型：`SkillInput(name, path)`、`MentionInput(name, path)`。

---

## Profile 配置

在 `~/.codex/config.toml` 中定义配置档：

```toml
[profiles.reviewer]
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
approval_policy = "never"
sandbox_mode = "danger-full-access"
personality = "pragmatic"
service_tier = "fast"
```

| 字段 | 说明 |
|------|------|
| `model` | 使用的模型（推荐 gpt-5.5 用于复杂任务） |
| `model_reasoning_effort` | 推理强度：low / medium / high / xhigh |
| `approval_policy` | 工具调用审批策略：never / always / auto |
| `sandbox_mode` | 沙箱模式：sandbox / danger-full-access |
| `personality` | 人格风格 |
| `service_tier` | 服务层级：fast / default |

---

## 重试工具（Python）

```python
from codex_app_server import retry_on_overload, is_retryable_error

# 自动重试，带指数退避 + 抖动
@retry_on_overload(max_retries=3)
def run_with_retry(thread, prompt):
    return thread.run(prompt)

# 手动检查
try:
    result = thread.run(prompt)
except Exception as e:
    if is_retryable_error(e):
        await asyncio.sleep(1)
        result = thread.run(prompt)
```

---

## Agent Class 模板（TypeScript）

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

## Agent Class 模板（Python）

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

## 编排说明

编排模式的设计思想和选择指南请参见 SKILL.md 中的"多 Agent 编排"章节。

Codex SDK 编排要点：
- **Context 传递**：Agent 之间通过 `JSON.stringify(result.data)` 序列化输出，作为下一个 Agent 的 prompt
- **会话恢复**：使用 `resumeThread(threadId)`（TS）或 `thread_resume(thread_id)`（Python）保持上下文
- **Thread 分叉**：使用 `thread_fork()` 进行推测性执行——从同一状态尝试多种方案，选择最优结果
- **并行执行**：使用 `Promise.all`（TS）或 `asyncio.gather`（Python）并行运行多个 Agent，各自独立持有 Thread
- **Turn 转向**：使用 `TurnHandle.steer()`（Python）在执行中途修正方向，无需重启
- **LLM 编排**：Orchestrator Agent 通过结构化输出（`{ nextAgent, prompt, done }`）驱动调度循环
