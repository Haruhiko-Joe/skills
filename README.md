# Skills

一组用于扩展 Agent 能力的skills集合。

## 技能列表

### build-agent-system

设计和构建 AI Agent 系统的指南，支持 Codex SDK、Claude Agent SDK 和 Antigravity SDK。涵盖多 Agent 编排、Agent 工作流及自动化流水线。

- [build-agent-system](build-agent-system/)

### agy-delegation / claude-delegation / codex-delegation

让 Claude Code、Codex、Antigravity 三家互相委派任务。每个 skill 对应一个被调用方，直接调用它的 CLI（`agy -p`、`claude -p`、`codex exec`），装在另外两家里：

| 宿主 | 安装的 skill | 目录 |
|---|---|---|
| Claude Code | agy-delegation、codex-delegation | `~/.claude/skills/` |
| Antigravity | claude-delegation、codex-delegation | `~/.gemini/config/skills/` |
| Codex | claude-delegation、agy-delegation | `~/.codex/skills/` |

```bash
./install-delegation.sh          # 复制到三家的 skill 目录；改了 skill 后用 --force 重跑覆盖
```

防环：每个 skill 的命令模板先检查 `AGENT_BRIDGE_PARENT`，已设置就拒绝启动；启动被调用方时设置 `AGENT_BRIDGE_PARENT=1`，子进程和它的 shell 工具都会继承。所以被委派出去的 agent 只能自己做或用自家的原生 subagent，不能再跨家委派。模型固定：Claude 只用 Opus 5.5 或 Fable 5.2，OpenAI 只用 `gpt-6-astra`，Google 只用 Gemini 4 Carbon，它们自己开的 subagent 也一样。触发条件：只有你明确要求时才会委派，也就是你点名了某一家，或者直接说把任务委派出去。宿主模型不会因为自己判断某个任务适合另一家，就把它派出去；没有明确要求时它自己做。你要求委派但没有点名时，按下面的分工选：定义完整的数学和算法题交给 Codex；写给人读的文字交给 Antigravity，安全漏洞审计、开放式调研，以及对复杂架构或代码的第二意见也可以交给它；在真实仓库里改代码、调试、评审交给 Claude。宿主模型是被委派 agent 的用户：对方给出计划、提问或有操作被拒时，宿主在同一个会话里回复（批准、纠正、回答），该由你决定的事再来问你。任务正文的写法按三家官方提示词指南写在各自的 SKILL.md 里。

- [agy-delegation](agy-delegation/)：写作、润色、翻译、安全审计、开放式调研、第二意见，以及想用 Antigravity 额度跑的任务
- [claude-delegation](claude-delegation/)：代码实现、调试、评审、仓库分析
- [codex-delegation](codex-delegation/)：代码实现、调查、算法、评审

### rebuttal-writing

学术会议论文审稿回复（Rebuttal / Author Response，如 ICLR、NeurIPS、ICML、CVPR、ACL 等）的写作与核查指南。涵盖 `W -> Q` 严格排序、提炼审稿人真实质疑、数据表格自包含（假设审稿人不看修订稿）、多评判模型交叉核验加分歧全量人工核验、常见质疑回应模板、论文与 `pdfdiff` 一致性核查，以及 OpenReview 公式转义检查。

- [rebuttal-writing](rebuttal-writing/)
