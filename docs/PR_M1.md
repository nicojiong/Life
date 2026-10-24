# PR：M0 收尾 + M1 可靠性底座（汇总）

> 本文件是 PR 描述草稿。分支 `agent/M1-ci-workflow` 是**一条连续提交链**，已包含此前
> 16 个开发分支的全部提交，无需逐个合并。

## 摘要

按 `docs/strategy` 的路线图完成 M0 全部 4 项，并推进 M1 的四个任务（存档、时钟、随机与日志、人物状态）。
所有改动都在 `agent/M1-ci-workflow` 一条链上，`main` 未被改动。

## 这轮修掉的四个已复现缺陷

| 缺陷 | 修复 | 断言 |
|---|---|---|
| 父亲在长行动中死亡后，收益记到被切回的孩子头上 | `_on_action` 记录 `acting_pov`，视角变化即中断不发奖 | `action_pov_change_no_reward` |
| 父母死亡被重复结算 | `_parent_death` 增加幂等守卫 | `parent_death_settled_once` |
| 真实事件仍用未保存的全局随机数 | 新增 `_pick_from()`，事件/城名挑选走 `sim_rng` | `events_use_saved_rng` |
| 未来版本存档被接受并降级覆盖 | `schema_version > 当前` 时拒绝加载并禁止写盘 | `save_rejects_future_version` |

## 其他改动

- **年关按户结算**：`_household_year_cost()` 汇总所有在世成员，与操控谁无关（断言 `household_year_cost`：1250 vs 340）。
- **稳定行动标识**：冷却键改为 `_action_key(act)`，优先 `id`，否则内容签名（断言 `action_key_stable`）。
- **CI 修复**：Linux 上 `user://` 是 `~/.local/share/godot`（小写）；日志先落盘 `verify-artifacts/` 再清理临时目录；新增 `-ExpectedAssertions`，缺 SUMMARY 或条数不符即失败。

## 测试证据

- 本地：`tools/verify.ps1` → `pass=50 fail=0`，exit 0，真实存档目录未被触碰。
- CI：GitHub Actions run 见 commit 状态页（当前 `46` 条断言）全部步骤 success；此前 `e893052` 的 run `40051930378` 也 success。
- 日志产物：`verify-artifacts`（run.log）。

历史失败（已在本次修掉）：
- run 40050519482 / 40050570193 → 退出码 2（Linux 路径大小写），且日志产物为空。

## 已知限制

- 时间边界队列仍未显式化（年关/生日/死亡靠代码先后顺序）。
- 随机已拆 birth/world/actor 三条可保存流；表现层与调试流按设计不入库。
- 黄金重放（固定 seed + 命令序列逐 tick 比对）未开始。
- 断言是单元级，未覆盖真人试玩的端到端复现。
- 只有 ubuntu-latest 的 CI；Windows/macOS 未配置。

## 后续任务

1. M1-01b：把年龄/健康/寿数收拢到 actor 表，`pov_state` 只留职业与 story。
2. M1-05：黄金重放 fixture。
3. M2/M3：WorldState / ActionService / EventScheduler 的分层，以及内容扩展。

## 合并方式

仓库现有授权下由维护者合并。本 PR 只做 push 与验证，不宣称已合并。

## 状态更新（2026-10-24 第三轮）

验证提交：`dd9e9fd`（跨进程续跑首个场景），CI 状态见该 commit 的 checks 页。

断言从 35 增至 **46**，本轮新增/修复：

| 项 | 断言 |
|---|---|
| 旧档三视角迁移不串人 | `old_save_pov_migration` |
| 赴任路径类型错误 | `take_post_assigns_county` |
| 死亡入口统一 | `death_unified` |
| 事件按真实月份到期 | `event_due_by_month` |
| 年关费用跨视角一致 | `household_cost_pov_consistent` |

**仍未完成**（不得据此标 M0/M1/M2 完成）：

- 跨进程续跑验收（三个独立进程）—— 下一任务
- 连续运行与「保存退出后重载续跑」的状态对比未做
- 借米因果链未做（现有因果链只有 3 跳样例）
- 数据文件没有字段/类型校验
- 只有 Linux CI；无真人试玩

唯一下一任务：**跨进程续跑验收**（A 跑 N 步存档退出 / B 新进程读档续跑 M 步 / C 一次跑 N+M 步，三进程比对）。
## 跨进程续跑（M1-05c）

三进程：A 跑 N 步存档退出 → B 新进程读档导出即刻状态再跑 M 步 → C 干净目录连续跑 N+M 步。
比较 A/B0（检查点 vs 加载）与 B1/C（终态），并做反向验证（删字段/改事实/改随机流必须报错）。

- 脚本：`tools/continuity.ps1`，入口 `--stage=continuity_a|b|c`（`main.gd` 只分发）
- CI：`continuity` 独立 job，与 `isolated-smoke` 分开报告，失败各自红
- 产物：四份快照、实际存档、三进程日志、`report.txt` 差异报告
- 首个场景（正常跨年）已通过：`dd9e9fd`

未完成：父母视角待办、死亡边界、非零 month_frac 保存点、产物级（改磁盘文件）反向验证。
