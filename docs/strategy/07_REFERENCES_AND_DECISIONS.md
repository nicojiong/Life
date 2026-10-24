# 来源、决策与待验证假设

查阅日期：2026-10-24（Asia/Shanghai）。此文件帮助后续 Agent 区分用户目标、当前源码事实和新的设计建议。

## 1. 证据范围

仓库：https://github.com/nicojiong/Life  
审计提交：[2d035379f21abbc8d1d6f06d0328eb756751b993](https://github.com/nicojiong/Life/commit/2d035379f21abbc8d1d6f06d0328eb756751b993)

已读取该提交下16个文本文件，包括项目配置、全部GDScript源文件、数据与文档；还查看了docs/shots/village_warm.png的现有截图。源码审阅发现的问题列在00_REPOSITORY_AUDIT.md。截图是仓库已有资产，不能作为本轮运行成功的证据。当前分析环境PATH未发现Godot可执行文件，本轮没有启动游戏或执行项目测试。

没有修改游戏源码，没有创建远程分支、commit、PR或push。此次写入的是独立规划包；STATE.json明确记录这一点。

### 固定版本的一手源码

| 来源 | 用于核对什么 |
|---|---|
| [README](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/README.md) | 当前玩法描述、操作、运行说明与过时缺口 |
| [现有GDD](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/docs/GDD.md) | 原设计方向、童年和父母视角、时间规则矛盾 |
| [village_scene.gd](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd) | 4631行主场景中的出生、行动、人物、结算、存档、结局 |
| [main.gd](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/main.gd) | 启动、调试stage、截图与--fresh的清档范围 |
| [db.gd](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/core/db.gd) | 出身抽取、姓名、固定时代加载与年号 |
| [origins.json](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/data/origins.json) | 10种出身、权重、初始属性与商贾标识 |
| [song.json](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/data/era/song.json) | 年历、考试年份、尚未接入的历史时间线 |
| [project.godot](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/project.godot) | 引擎特性声明、自动加载、分辨率与渲染模式 |

## 2. 外部机制参考

| 一手来源 | 可以借鉴的思路 | 在本项目中的采用方式 |
|---|---|---|
| [Emily Short: Storylets: You Want Them](https://emshort.blog/2019/11/29/storylets-you-want-them/) | 用前置条件、内容和效果构成可组合叙事 | 建立故事元定义与实例，减少无限分支树 |
| [Failbetter: StoryNexus Developer Diary #2](https://www.failbettergames.com/news/storynexus-developer-diary-2-fewer-spreadsheets-less-swearing) | 基于状态的叙事片段，可依共同规则协作扩展 | 先统一条件/效果协议，再让多个写作Agent生产 |
| [Wildermyth 官方介绍](https://www.wildermyth.com/press/sheet.php?p=wildermyth) | 人物跨越生涯，选择、成长和记忆形成连续经历 | 把外观、关系与回望连接到实际发生过的生活 |
| [Generative Agents 原论文](https://arxiv.org/abs/2304.03442) | 观察、记忆、规划与反思对可信行为的作用 | NPC保留可检索记忆与目标；先用规则实现，在线模型另做成本验证 |

这些来源支持机制研究，不证明本项目可在任意规模、延迟或预算下运行。人设、剧情、数值和路线是本规划的原创建议；未直接复制这些作品的角色、对白或资产。

## 3. 工程参考

- [Godot 4.7 命令行](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)：核对headless、import、脚本与导出入口。可用命令仍需以实际安装版本核验。
- [Godot RandomNumberGenerator](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)：seed/state保存恢复与算法实现细节。确定性承诺限定在固定引擎/模拟/内容版本。
- [Godot 数据路径](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html)：user://与项目配置相关；worktree不能自动隔离玩家存档。
- [GitHub CLI 创建PR](https://cli.github.com/manual/gh_pr_create)：核对base/head/body-file参数。
- [GitHub CLI PR检查](https://cli.github.com/manual/gh_pr_checks)：核对检查状态与等待行为；无检查不等于通过。
- [Git worktree](https://git-scm.com/docs/git-worktree)：独立工作区与分支协作。

## 4. 决策登记

| 决策 | 来源/性质 | 理由与可修改边界 |
|---|---|---|
| 可选时代、随机出生、独特一生 | 用户明确目标 | 每个可玩时代必须包含真实制度和人生内容 |
| 自主权随成长增加 | 用户明确目标 | 0–6父母主导，6以后有部分表达，12以后逐步扩大 |
| 出身不锁定终身职业 | 对用户自由目标的实施解释 | 如用户以后要求宿命模式，作为独立模式，不覆盖默认自由人生 |
| 继续Godot与现有街景 | 技术建议 | 已有原型可复用；引擎更换需另有证据与迁移任务 |
| 默认单机离线个人世界 | 产品建议 | 优先实现可保存、可复现的一生；联机另立目标 |
| 保留父母代管为可选模式 | 产品建议 | 默认个人视角更符合“活自己的一生”，既有家庭玩法可继续复用 |
| 单一逻辑时间+命令事务 | 工程建议 | 修复零时间收益、视角影响结算和死后结算 |
| 字段统一snake_case | 工程合约建议 | 以02架构为准，人物与事件示例共用协议 |
| 12核心NPC、3路线、约40故事元 | 范围建议 | M3工作量起点；按可玩与覆盖调整，不视为硬性产量竞赛 |
| AI优先用于开发期生成 | 工程/成本建议 | 候选可校验，离线游戏可运行；运行时服务独立评估 |
| 第二时代先短切片再完整人生 | 验证策略建议 | 先验证制度解耦，再宣称时代可完整游玩 |
| 每部分验收后commit与push | 用户明确交付目标 | 远端SHA验证；分支、PR和集成状态分别记录 |
| 自动合并/公开发布/付费不预授权 | 交付边界 | 依已有用户授权与仓库规则，不让规划文件自行扩大权限 |

## 5. 后续需要用实际证据回答的问题

1. 目标用户更喜欢30–90分钟浓缩人生，还是更长的沉浸节奏？原型测试后决定，不由代码随意定死。
2. 固定年龄节点改成条件事件后，童年与晚年是否还有足够内容？按覆盖与试玩反馈补齐。
3. 现有引擎版本、系统字体和导出配置能否在目标Windows环境稳定运行？M0与M7分别核验。
4. 哪些历史细节必须严谨、哪些明确采用玩法抽象？时代包应建立来源和置信度字段。
5. 人物数量、日志规模与事件更新频率的成本如何？先测原型，再设上限和分层策略。
6. 当引擎或内容版本更新时，采用旧版本继续、迁移还是显式重开？存档兼容策略需随实际发布版本更新。

这些问题不阻止先完成M0与M1。它们应变成后续验证任务，而不是要求用户一次性回答全部设计细节。
