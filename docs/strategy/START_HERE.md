# Life /《浮生》战略规划与 Agent 执行包

2026-10-24 · 规划 v1.0 · 目标仓库：https://github.com/nicojiong/Life

## 这份交付包含什么

这是一份基于实际仓库源码的整体规划和开发交接包：保留现有 Godot 北宋村庄原型，逐步形成“选择时代、随机出生、成长获得自主权、行动产生长期后果、NPC拥有自己的生活、走完独特一生”的个人世界。

代码审计基线：2d035379f21abbc8d1d6f06d0328eb756751b993。核对了仓库文本源文件与一张现有界面截图。本次没有运行 Godot，没有修改游戏功能，没有创建 GitHub 分支、提交、PR 或 push；未来开发任务全部为 todo。

## 阅读顺序

| 文件 | 用途 |
|---|---|
| [AGENT_START_PROMPT.md](AGENT_START_PROMPT.md) | 复制给开发 Agent 的启动指令，从 M0-01 开始 |
| [00_REPOSITORY_AUDIT.md](docs/strategy/00_REPOSITORY_AUDIT.md) | 当前实现、关键缺陷、源码证据和第一批回归 |
| [01_GAME_VISION_AND_RULES.md](docs/strategy/01_GAME_VISION_AND_RULES.md) | 整体游戏定位、年龄自主权、随机因果、人生终局、时代规划 |
| [02_SYSTEM_ARCHITECTURE.md](docs/strategy/02_SYSTEM_ARCHITECTURE.md) | 状态、统一时钟、事务、RNG、日志、存档、事件与时代协议 |
| [03_CHARACTER_AND_STORY_BIBLE.md](docs/strategy/03_CHARACTER_AND_STORY_BIBLE.md) | 人物元素、原创模板、故事元、跨年剧本与内容生产 |
| [04_ROADMAP_AND_BACKLOG.md](docs/strategy/04_ROADMAP_AND_BACKLOG.md) | M0–M7 共8个阶段、31张任务卡与可验收出口 |
| [05_AGENT_DELIVERY_RUNBOOK.md](docs/strategy/05_AGENT_DELIVERY_RUNBOOK.md) | 开发、测试、commit、push、PR、CI与中断恢复的具体动作 |
| [06_ACCEPTANCE_AND_TEST_PLAN.md](docs/strategy/06_ACCEPTANCE_AND_TEST_PLAN.md) | 25个行为场景、状态不变量、模拟与真实试玩的分工 |
| [07_REFERENCES_AND_DECISIONS.md](docs/strategy/07_REFERENCES_AND_DECISIONS.md) | 来源、事实边界、设计决策和待验证假设 |
| [backlog.json](backlog.json) | 可被 Agent 读取的任务依赖与验收数据 |
| [STATE.json](STATE.json) | 初始执行状态，避免把规划误认为已实现 |
| [AGENTS.md.template](templates/AGENTS.md.template) | 拟加入仓库的长期规则模板，使用前与已有规则合并 |
| [TASK_TEMPLATE.md](templates/TASK_TEMPLATE.md) | 小任务实施记录模板 |
| [ITERATION_REPORT_TEMPLATE.md](templates/ITERATION_REPORT_TEMPLATE.md) | 每轮证据和push记录模板 |

## 怎样交给 Agent

1. 解压整个包，保留内部相对目录。把包和目标仓库同时提供给具有代码读写、运行与GitHub权限的 Agent。
2. 发送 AGENT_START_PROMPT.md 中的完整指令。Agent先检查当前仓库与审计基线的差异，再执行 M0-01。
3. 在 M0-01 中，将策略文档合并到仓库 docs/strategy；backlog.json 和 STATE.json 可放到 docs/agent/ 并记录新位置；执行记录放 docs/tasks/。这属于规划导入，不得覆盖原有有效规则或用户未提交修改。
4. 如仓库已有 AGENTS.md，合并必要条款；没有时才用模板创建。模板不自动获得高于用户指令的权限。
5. 以后每次恢复先看 STATE.json、任务卡和远端分支，沿原任务继续。每个经过验收的小任务都commit、push并核验远端SHA；集成与发布遵循现有授权。

若Agent只有聊天能力，应把实现动作标成环境不可用，交付具体阻断信息；不能把建议文字当成已经完成的代码。持续后台执行需要实际运行器，不是粘贴一次提示词便永久自动运行。

## 关键设计决定

- 出生决定起点，不锁定终身职业；用户的自由选择是核心。
- 第一时代继续北宋，先证明完整人生；第二时代用于检验制度与内容是否真正解耦。
- 默认单机离线，玩家世界独立；运行时在线AI为可选扩展。
- 先修时间、存档、人物记忆和死亡边界，再增加大量事件。
- AI生成的内容须经过规则、引用、语义、模拟和审阅；正式游戏状态由模拟规则维护。
- 推送成功、CI成功、合并成功、发布成功分别记录，不能相互替代。

## 文件冲突的裁决

用户当前指令与仓库有效规则优先；本包是拟实施方案。任务ID、状态与依赖以 backlog.json 为机器清单，解释以路线图为准；工程字段和运行合约以架构文档为准；内容文档示例必须遵循工程合约。冲突先修文件并记录决策，不让多个Agent各造一套协议。

推荐每次里程碑验收后更新：有效产品规则、代码结构、任务状态、测试入口、存档版本、内容版本和下一阶段缺口。保留历史审计作为基线，不把旧事实悄悄改成新现状。
