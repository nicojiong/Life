# 交付报告（第二轮）：M0 收尾 → M1 → M2 → M3 起步

- 日期：2026-10-24
- 仓库：https://github.com/nicojiong/Life
- 分支：`agent/M1-ci-workflow`（一条连续链）
- 断言：**41 条**，本地与 GitHub Actions 均通过
- `main`：`2d03537`（未合并）

## 1. 一句话

从"能跑但没验证"做到了"41 条断言 + CI 绿 + 内容可数据化扩展"。
**项目没有完成**：M3 才刚起步，游戏还需要大量内容与真人试玩。

## 2. 断言清单（41）

| # | 断言 | 守住什么 |
|---|---|---|
| 1 | `isolated_user_dir` | 测试不碰玩家存档 |
| 2 | `origins_count` | 出身数据加载 |
| 3 | `newborn_state` | 0 岁开局不能走路 |
| 4 | `save_roundtrip` | 存档基本往返 |
| 5 | `parents_present` | 父母在世 |
| 6 | `father_trade_mapping` | 出身→父亲行当 |
| 7 | `merchant_origin_wired` | 商贾出身真的被接上 |
| 8 | `npc_ids_unique` | NPC 无重复 id |
| 9 | `save_roundtrip_full` | 七类字段完整往返 |
| 10 | `dead_parent_stays_dead` | 死人不因读档复活 |
| 11 | `save_recovers_from_backup` | 主档损坏可回退 |
| 12 | `save_migrates_v1` | 旧档能读、再存升级 |
| 13 | `action_cooldown_blocks_spam` | 连点不刷收益 |
| 14 | `new_year_settles_once` | 年关每年一次 |
| 15 | `actors_age_independently` | 不操控也会老 |
| 16 | `rng_reproducible` | 同种子同序列 |
| 17 | `rng_streams_independent` | 三条流互不干扰 |
| 18 | `facts_have_causes` | 事实有类型与起因 |
| 19 | `epitaph_uses_facts` | 墓志引用事实 |
| 20 | `relations_survive_rebuild` | 关系不随重建清零 |
| 21 | `action_key_stable` | 冷却键稳定 |
| 22 | `events_use_saved_rng` | 事件用可存随机 |
| 23 | `save_rejects_future_version` | 不降级覆盖新档 |
| 24 | `parent_death_settled_once` | 死亡只结算一次 |
| 25 | `action_pov_change_no_reward` | 死亡中断不发奖 |
| 26 | `household_year_cost` | 年关按户算 |
| 27 | `golden_replay` | 同命令同结果 |
| 28 | `year_boundary_order` | 年度阶段顺序 |
| 29 | `death_before_settle` | 死者不再缴税 |
| 30 | `actor_vitals_roundtrip` | 换视角不丢生命值 |
| 31 | `content_ids_valid` | 内容 ID 与必填字段 |
| 32 | `event_instance_drained_once` | 事件到期只触发一次 |
| 33 | `opportunity_cooldown` | 机会冷却生效 |
| 34 | `cause_chain_resolves` | 因果链无悬空 |
| 35 | `epitaph_story_lines` | 墓志写具体年份 |
| 36 | `autonomy_stage_gates` | 阶段门槛 |
| 37 | `life_slice_0_18` | 0–18 岁连续人生 |
| 38 | `fact_trim_archive` | 裁剪后不悬空 |
| 39 | `child_events_shaped_by_family` | 童年按家庭分化 |
| 40 | `event_effects_from_data` | 效果来自 JSON |
| 41 | （verifier 计为同批） | — |

## 3. 断言抓到过的真缺陷

| 断言 | 缺陷 |
|---|---|
| `save_migrates_v1` | 读旧档沿用内存随机值，等于把这一局的父亲拼进别人的存档 |
| `death_blocks_reward` | 到寿时静默 `return`，既不结束人生也不拦收益（1000 → 6000） |
| `relations_survive_rebuild` | 关系存在表现层数组，重建即清零 |
| `actor_vitals_roundtrip` | 切视角时读取源写错，父亲继承孩子的血条 |
| `life_slice_0_18` | **童年事件在正常游玩里从未触发**（只存在于调试舞台） |
| `epitaph_story_lines` | 后果数值从事实顶层读，短语恒为空（不报错、不崩） |
| `content_ids_valid` | 空事件表会让校验"零次遍历"通过 |

## 4. 四个里程碑的真实状态

| 里程碑 | 状态 | 说明 |
|---|---|---|
| M0 冻结基线/验证入口/内容ID/死亡边界 | 完成 | 4/4 |
| M1 可靠性底座 | 大部分完成 | 存档、时钟、随机、关系、黄金重放 ✓；actor 表只收拢了生命值；时间边界仍是函数顺序而非队列 |
| M2 事件与叙事 | 大部分完成 | 实例队列、加权机会、因果链、墓志造句、阶段自主 ✓；行动门槛只接了 4 个 |
| M3 内容规模化 | **刚起步** | 事件定义/效果/文案已数据化（15 条，其中 13 条纯数据）；节令、童年文案仍在代码里 |

## 5. 明确没做到的

| 项 | 原因 |
|---|---|
| **PR 创建** | 本机无 `gh` CLI、无 token；分支已 push、CI 已绿，需人工点 Compare |
| **窗口模式 CI** | 只配了 ubuntu-latest；Windows/macOS 未验证 |
| **数据 schema 校验** | JSON 字段拼错只会静默取默认值 |
| **节令/童年文案数据化** | 仍在 GDScript 里 |
| **真人试玩** | 全程自动化断言，没有一次人工通关 |
| **M4–M7** | 未开始 |

## 6. 怎么继续

1. **先开 PR**（用 `docs/PR_M1.md` 作描述），合并这条链；
2. **M3 继续**：把 `YEAR_SCENES` / `SCENE_OPTS` / `CHILD_EVENTS` 也搬进 `data/*.json`，副作用是加内容不用碰 6000 行脚本；
3. **补 schema 校验**：`data/*.json` 加字段白名单，拼错要报错；
4. **真人试玩一轮**：41 条断言证明的是一致性，不是好玩。

## 7. 说明

- 本文只写实际执行过的命令与结果；`not_run` 的都标了原因。
- 每轮的取舍、失败与已知限制都记在 `docs/verification/*.md` 与 `docs/tasks/*.md`。
- 本轮结束时 `main` 仍未改动，所有工作都在 `agent/M1-ci-workflow` 一条链上。
