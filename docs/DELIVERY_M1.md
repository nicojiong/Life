# 交付报告：M0 + M1 前段

- 日期：2026-10-24
- 仓库：https://github.com/nicojiong/Life
- 依据：`docs/strategy/`（规划包）、`docs/agent/backlog.json`（31 张任务卡）
- `main` 未改动，仍在 `2d03537`

## 1. 一句话

按规划把 **M0 全部 4 项**做完，并推进了 **M1 的四个任务**（每个任务拆成可验收的小切片，共 13 个提交）。全部改动在 16 个 `agent/*` 分支上，**均未合并**，等待评审。

## 2. 分支与提交

| 任务 | 分支 | 远端 SHA | 结果 |
|---|---|---|---|
| M0-01 冻结基线 | `agent/M0-01-baseline` | `4c64fbe` | 规划导入、`docs/BASELINE.md`、改正过时结论 |
| M0-02 隔离验证 | `agent/M0-02-verify-entry` | `3d57967` | `tools/verify.ps1`、`--stage=verify_smoke`、`--fresh` 守卫 |
| M0-03 内容 ID | `agent/M0-03-content-ids` | `fffa81f` | 修商贾接线、删重复 NPC、3 条内容断言 |
| M0-04 死亡边界 | `agent/M0-04-death-boundary` | `b69eab7` | 死后不发奖、不重写存档、死亡只触发一次 |
| M1-04a 存档字段 | `agent/M1-04a-save-fields` | `1788fe8` | 补 7 个漏存字段 + schema 版本 |
| M1-04b 死亡与缺字段分离 | `agent/M1-04b-dead-parent` | `f019e8d` | 已故父母不因读档复活 |
| M1-04c 原子写入 | `agent/M1-04c-atomic-save` | `c0e11dd` | tmp→bak→main、损坏回退备份 |
| M1-04d 旧档迁移 | `agent/M1-04d-migration` | `2fa4a31` | v1 fixture、缺失字段按出身推导 |
| M1-02a 统一结算 | `agent/M1-02a-action-cooldown` | `76766e7` | 对话与地点共用冷却结算 |
| M1-02b 年关一次 | `agent/M1-02b-year-settles-once` | `1c0b47f` | 年关防重入水位 |
| M1-02c 各自老化 | `agent/M1-02c-actor-aging` | `2315660` | 不操控的家人也老化、也会死 |
| M1-03a 可复现随机 | `agent/M1-03a-sim-rng` | `91ab293` | sim_rng 独立流、种子入库 |
| M1-03b 事实日志 | `agent/M1-03b-fact-log` | `1bc41ac` | `facts` + cause，入库 |
| M1-03c 墓志引事实 | `agent/M1-03c-epitaph-facts` | `bf0846f` | 墓志写「一生所记：…」 |
| M1-01a 关系归世界 | `agent/M1-01a-relations` | `b9d58fa` | 关系不再随重建清零 |
| CI 工作流 | `agent/M1-ci-workflow` | `e8cf720` | 已提交，**未运行** |

分支是**堆叠**的：每个基于前一个的精确 SHA，PR 的 base 应依次指向前一条。

## 3. 验证证据

命令：

```powershell
pwsh -File tools/verify.ps1 -GodotPath <Godot console exe>
```

最新一次（`e8cf720`）输出：

```
[VERIFY] PASS isolated_user_dir C:/Users/.../LifeVerify-<id>
[VERIFY] PASS origins_count 10
[VERIFY] PASS newborn_state age=0 can_walk=false
[VERIFY] PASS save_roundtrip money=12345
[VERIFY] PASS parents_present
[VERIFY] PASS father_trade_mapping
[VERIFY] PASS merchant_origin_wired
[VERIFY] PASS npc_ids_unique count=14
[VERIFY] PASS save_roundtrip_full schema=6
[VERIFY] PASS dead_parent_stays_dead
[SAVE] corrupt_or_unreadable user://fusheng_save_1.json err=Expected key
[SAVE] recovered_from_backup
[VERIFY] PASS save_recovers_from_backup money=100
[VERIFY] PASS save_migrates_v1 upgraded_to=6.0
[VERIFY] PASS action_cooldown_blocks_spam money=800
[YEAR] settle_skipped year=1046 last=1046
[VERIFY] PASS new_year_settles_once deducted=854
[VERIFY] PASS actors_age_independently father_hp=39.2 self_hp=60.0
[VERIFY] PASS rng_reproducible seq=[56, 47, 41] resume=160
[VERIFY] PASS facts_have_causes kinds=["event", "exam"]
[VERIFY] PASS epitaph_uses_facts 一生所记：应试2次、逢变故1次。
[VERIFY] PASS relations_survive_rebuild rebuild=25 load=25
[ACTION] interrupted_before_reward 长活
[VERIFY] PASS death_blocks_reward money=1000
[VERIFY] SUMMARY pass=20 fail=0 failed=[]
[verify] PASS 真实存档目录未被触碰
exit=0
```

**20 条断言全过，且运行前后真实存档目录未被触碰。**

## 4. 断言抓到过的真缺陷

| 断言 | 抓到的缺陷 |
|---|---|
| `save_migrates_v1` | 读旧档时 `d.get("father_trade", father_trade)` 沿用了内存里的随机值——等于把这一局的父亲拼进别人的存档 |
| `death_blocks_reward` | `_advance_months` 在 `age >= lifespan` 时静默 `return`，既不结束人生也不拦收益，钱从 1000 变 6000 |
| `action_cooldown_blocks_spam` | 长行动的自身推进刚好抵消冷却，短行动才是真缺口（模型写错） |
| `actors_age_independently` | 首次失败暴露的是断言没隔离随机事件（瘟疫 −7 血），不是代码问题 |

## 5. 各项任务的真实状态

| 任务 | 状态 | 已完成 | 未完成 |
|---|---|---|---|
| M0-01 | implemented | 基线、导入、文档修正 | 待合并 |
| M0-02 | implemented | 隔离入口、断言舞台、退出码 | CI 未真实运行 |
| M0-03 | implemented | 接线修复、ID 校验 | 数据层全量校验（依赖 M2） |
| M0-04 | implemented | 死亡边界 | 独立人生档案 |
| M1-01 | in_progress | 关系归世界持有 | Actor/Household 结构、财产所有权 |
| M1-02 | in_progress | 统一结算、冷却、年关一次、各自老化 | 按户结算、显式时间边界队列 |
| M1-03 | in_progress | 可复现流、事实日志、墓志引事实 | 五类流、cause_ids 链、黄金重放 |
| M1-04 | in_progress | 字段、版本、原子写、备份、迁移、RNG | NPC 关系、事件队列 |
| M1-05 | 未开始 | — | 黄金重放 fixture、生命周期边界报告 |

## 6. 仍然阻塞

| 项 | 原因 | 需要什么 |
|---|---|---|
| PR 创建 | 本机无 `gh` CLI、无 API token | 网页点 Compare & pull request，或给一个 `repo` 权限 PAT |
| CI 真实运行 | 无 runner、无 token | 推送后到 Actions 页面看首次结果；引擎下载 URL 可能需要按实际资产名修正 |
| 合并 main | 规程要求合并需单独授权 | 逐条评审 16 个分支 |

## 7. 如果要继续，建议顺序

1. **先合并 M0 四条**——它们互相独立、风险最低，且修正了文档与死亡边界。
2. **M1-01b**：把年龄/健康/寿数收拢到 actor 表，`pov_state` 只留职业与 story。这是 M1-02 剩余项（按户结算、边界队列）的前置。
3. **M1-05**：黄金重放——固定 seed + 固定命令序列，逐 tick 比对状态摘要。有了它，后面所有"改规则"才有回归保险。
4. **M2+**：等底座稳定后再拆 `WorldState / ActionService / EventScheduler`，不要边跑边换引擎。

## 8. 说明

- 本报告只写实际执行过的命令与结果；`not_run` 的项目都标注了原因。
- 每个分支的 `docs/tasks/*.md` 与 `docs/verification/*.md` 记录了当轮的取舍、失败与已知限制，可逐条复核。
- 游戏本身仍可在本地运行（`play.bat`），行为与 `main` 相比有上述改动，但**尚未经过真人试玩**——自动化断言证明的是一致性，不是"好不好玩"。


---

## 第二轮：修复与集成验收（2026-10-24 追加）

基线 `33a768b` 之后，本轮补了四个已复现缺陷、一处按户结算、以及 CI 本身的两个问题。

| 项 | 结果 |
|---|---|
| 父亲死亡后收益发给孩子 | 已修复，断言 `action_pov_change_no_reward` |
| 父亲死亡重复结算 | 已修复，断言 `parent_death_settled_once` |
| 真实事件用未保存的全局随机数 | 已修复（`_pick_from`），断言 `events_use_saved_rng` |
| 未来版本存档被降级覆盖 | 已修复，断言 `save_rejects_future_version` |
| 年关按户结算 | 已实现，断言 `household_year_cost`（1250 vs 单人口径 340） |
| 冷却使用稳定行动标识 | 已实现，断言 `action_key_stable` |
| CI Linux 路径大小写 / 日志产物 / 完整性校验 | 已修复，GitHub Actions run 40051930378 success |

断言总数从 20 增到 **26**，本地与 CI 均通过。

PR：**未创建**。本机无 `gh` CLI、无 `GITHUB_TOKEN`，无法调用 GitHub API 建 PR。
汇总分支为 `agent/M1-ci-workflow`（一条连续链，含此前 16 个分支的全部提交），
可在 https://github.com/nicojiong/Life/compare/main...agent/M1-ci-workflow?expand=1 一键开 PR。

下一步：M1-03 五类随机流、M1-05 黄金重放，然后 M2/M3。

详细证据见 `docs/verification/2026-10-24-integration.md` 与 `docs/verification/CI.md`。
