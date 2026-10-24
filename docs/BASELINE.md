# 基线快照（M0-01）

> 本文件由 Agent 在 M0-01 任务中实测填写。只记录**实际执行过**的检查与其退出码；未执行的项目明确标为 `not_run`，不写入推测结论。

- 记录时间：2026-10-24（Asia/Shanghai）
- 仓库：https://github.com/nicojiong/Life
- 任务：M0-01「冻结现状与修正文档」
- 分支：`agent/M0-01-baseline`

## 1. 代码基线

| 项 | 实测值 |
|---|---|
| HEAD（开始工作前） | `2d035379f21abbc8d1d6f06d0328eb756751b993` |
| 规划审计基线 | `2d035379f21abbc8d1d6f06d0328eb756751b993` |
| 是否发生漂移 | 否，两者一致 |
| 已跟踪文件数 | 79 |
| `scripts/street/village_scene.gd` | 4597 行 |
| `scripts/main.gd` | 339 行 |
| `docs/GDD.md` | 326 行 |
| `README.md` | 104 行 |

## 2. 执行环境

| 项 | 实测值 |
|---|---|
| 操作系统 | Windows（PowerShell 7） |
| 引擎 | `Godot_v4.7.2-stable_win64_console.exe` |
| `--version` 输出 | `4.7.2.stable.official.ed1daf0bf` |
| 引擎路径 | `D:\Developer\Godot\4.7.2-stable\`（本机路径，非仓库承诺） |
| 项目路径 | `D:\code\agentProject\maker-onething-dsh` |

`project.godot` 声明 `config/features` 为 4.7，与实测版本一致；README 中的本机路径仅作运行示例。

## 3. 已执行的检查

| 检查 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| 引擎版本 | `Godot_v4.7.2-stable_win64_console.exe --version` | `4.7.2.stable.official.ed1daf0bf` | 0 |
| 编辑器导入 / 资源扫描 | `--headless --path . --import` | 完成：扫描 63 个资源、注册 7 个全局类、无 parse error、stderr 为空 | 0 |
| 源码结构核对 | 行数统计、目录清单 | 见上表 | — |

导入日志要点：`first_scan_filesystem DONE`、`update_scripts_classes DONE`、`reimport DONE`、`loading_editor_layout DONE`；stderr 无输出。

导入同时生成了 7 个 `*.gd.uid` 文件（Godot 4.4+ 为脚本分配的稳定 UID），属项目文件，本次一并入库，避免后续反复出现未跟踪文件。

## 4. 未执行的检查（及原因）

| 检查 | 状态 | 原因 / 何时补 |
|---|---|---|
| 实际启动游戏 | `not_run` | 普通启动会读写 `user://` 真实存档；在 M0-02 建立隔离数据目录之前不执行 |
| 现有 `--stage=*` 调试舞台 | `not_run` | 同上；且 `--fresh` 会删除 4 个存档文件，未隔离前禁止运行 |
| 截图 `--shot=` | `not_run` | 依赖真实启动；且截图只证明某帧渲染，不是行为断言 |
| R01–R12 回归用例 | `not_run` | 验证入口 `tools/verify.ps1` 尚不存在，属 M0-02 产物 |
| 性能 / 可通关性 | `not_run` | 需先有隔离启动与自动断言 |
| CI | `not_run` | 仓库尚未配置 CI |

以上均为真实状态，不代表通过或失败。

## 5. 本次修正的文档矛盾

静态阅读发现的过时结论，已在同一任务内改正：

| 位置 | 原文（过时） | 处置 |
|---|---|---|
| `README.md` §已知缺口 | 「12 处地点」「**没有科举**」「钱没有去处」 | 三条均已不符合实现：地点为 22 处；科举、官场、六条职业线已实现；钱已可通过田产、绣坊、行会消耗。改为指向真实缺口并引用审计编号 |
| `docs/GDD.md` §7 | 「目前评价只有一档…**分级评价还没做**」 | 已实现五档墓志（国史有传 / 府志留名 / 县志一行 / 族谱一句 / 无名）。改为描述现状 |
| `docs/GDD.md` §9 | 「科举只有考没有做官」「NPC 无记忆」 | 均已实现（衙门赴任/断案/升迁/弹劾；NPC 态度影响台词、价格、选项）。改为审计中的真实 P0/P1 问题 |

新旧设计不再同时生效：规划文档统一位于 `docs/strategy/`，任务与状态位于 `docs/agent/`，执行记录位于 `docs/tasks/`。

## 6. 规划包导入位置

| 规划包原文件 | 仓库位置 |
|---|---|
| `AGENT_START_PROMPT.md`、`START_HERE.md`、`docs/strategy/00–07` | `docs/strategy/` |
| `Life_Game_Strategy_20261024.md`（合并版全文） | `docs/strategy/FULL_STRATEGY.md` |
| `backlog.json`、`STATE.json` | `docs/agent/` |
| `templates/TASK_TEMPLATE.md`、`ITERATION_REPORT_TEMPLATE.md` | `docs/tasks/` |
| `templates/AGENTS.md.template` | 仓库根 `AGENTS.md`（此前不存在，按模板创建） |

导入后删除了解压包副本与两份顶层副本文件，仓库内只保留上述规范位置，避免同一文档多处生效。

## 7. 下一步

M0-02：建立隔离的验证入口 —— `tools/verify.ps1` + 独立用户数据目录 + 带退出码的最小断言，替换「截图 + print」作为验收手段。
