# Codex SDK Reference

Codex SDK 是 OpenAI 推出的 swe-agent SDK，通过 TypeScript 调用 SDK 暴露的方法，用编程的方式操作 Codex。

如需查阅最新 API 文档，请使用 `OpenAI Docs` 技能获取官方文档。

---

## 安装

```bash
npm install @openai/codex-sdk
```

## 核心 API

### Codex 实例

```typescript
import { Codex, Thread, ThreadOptions } from "@openai/codex-sdk";

const codex = new Codex({
  config: {
    profile: "my-profile",                    // 引用 config.toml 中的 profile
    developer_instructions: myInstruction,     // System Prompt
  },
});
```

### Thread 管理

```typescript
// 创建新 thread
const threadOptions: ThreadOptions = {
  workingDirectory: "/path/to/repo",
  skipGitRepoCheck: true,      // 允许在非 git 仓库中运行
};
const thread = codex.startThread(threadOptions);

// 恢复已有 thread（用于 continue 场景）
const thread = codex.resumeThread(threadId, threadOptions);
```

### 执行与输出

```typescript
// 普通文本输出
const turn = await thread.run(prompt);
console.log(turn.finalResponse);   // 文本响应

// 结构化输出（SDK 保证 100% 解析成功）
const turn = await thread.run(prompt, { outputSchema: mySchema });
const data = JSON.parse(turn.finalResponse);

// 获取 thread ID（用于后续 resume）
const threadId = thread.id;
```

### 图像输入

当需要把图像一并交给 Codex 时，`thread.run()` 不再传单个字符串，而是传结构化输入数组。文本项会拼接成 prompt，图像项使用本地文件路径传入。

```typescript
const turn = await thread.run([
  { type: "text", text: "描述这两张截图中的问题，并给出修复建议" },
  { type: "local_image", path: "./screenshots/error-state.png" },
  { type: "local_image", path: "./screenshots/mobile-layout.jpg" },
]);

console.log(turn.finalResponse);
```

图像输入要点：
- 图像项格式为 `{ type: "local_image", path: "..." }`
- 可以在一次 `run()` 中混合传入多段文本和多张图像
- `path` 使用当前工作目录下的相对路径或绝对路径
- `runStreamed()` 的输入格式与 `run()` 相同

如果图像来源是 URL，先下载到本地文件，再按 `local_image` 方式传入。

## Profile 配置

在 `~/.codex/config.toml` 中定义配置档，example如下：

```toml
[profiles.reviewer]
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
approval_policy = "never"
sandbox_mode = "danger-full-access"
personality = "pragmatic"
service_tier = "fast"
```

| 字段 | 说明 |
|------|------|
| `model` | 使用的模型 |
| `model_reasoning_effort` | 推理强度：low / medium / high / xhigh |
| `approval_policy` | 工具调用审批策略：never / always / auto |
| `sandbox_mode` | 沙箱模式：sandbox / danger-full-access |
| `personality` | 人格风格 |
| `service_tier` | 服务层级：fast / default |

## Agent Class 模板

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

## 编排说明

编排模式的设计思想和选择指南请参见 SKILL.md 中的"多 Agent 编排"章节。

Codex SDK 编排要点：
- **Context 传递**：Agent 之间通过 `JSON.stringify(result.data)` 序列化输出，作为下一个 Agent 的 prompt 输入
- **会话恢复**：循环校验场景下使用 `codex.resumeThread(threadId)` 保持上下文，避免从零开始
- **并行执行**：使用 `Promise.all` 并行调用多个 Agent 实例，每个实例独立持有自己的 Thread
- **LLM 编排**：Orchestrator Agent 通过结构化输出（`{ nextAgent, prompt, done }`）驱动调度循环
