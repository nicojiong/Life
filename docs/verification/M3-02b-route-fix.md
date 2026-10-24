# M3-02b 验证证据：路线隔离修复

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：仍 59（`m3_routes_walkable` 由"绕过"变为"真过"）

## 1. 上一轮的错误与真实原因

上一轮我报告 care 路线"跑进了 craft 分支"。真实原因**不是分支串线**，而是两件事：

1. `_continuity_start()` **没有重置玩家进度** —— `craft_rank / married / story / learning` 等从上一条路线带进下一条。所以 care 跑完还带着 craft 的 `匠户` 与 `craft_rank=1`。
2. `_route_step()` 靠 `_month_index() % 6 == 0` 触发，实际几乎打不中——每次运行只有 1–2 次行动，其余成长来自节令场景。所以"读书 710"其实是节令给的，不是路线行动。

## 2. 修法

- `_continuity_start()` 显式重置：`story / married / spouse / children / learning / craft / fame / 五种 rank / office / gov_merit / scandal / county / land / 工坊与行会 / 学徒 / 医术 / merit / milestones / 拜师状态 / child_pref / 嫁妆 / 卧病 / 债务`。
- `_route_run()` 改为**按年龄变化每年触发一次** `_route_step`，并把 `steps` 计入结果，断言可核对"确实每年行动"。
- 求学路线改为走 `_on_action` 的应解试动作（不再是裸 `_apply_special`），并先抄书挣钱。

## 3. 修复后的三条路线

```
[VERIFY] PASS m3_routes_walkable study=76/109.0 craft=64/2 care=62/true
```

| 路线 | 年龄 | 关键证据 | steps |
|---|---|---|---|
| 求学 | 76 | 识字 109 | 76 |
| 手艺营生 | 64 | `craft_rank=2`、`匠户`、存款 15119 | 64 |
| 留乡照护 | 62 | `married=true`、子女 2、`务农` | 63 |

三条路线互不污染：care 不再带 `匠户`，craft 不再有识字，study 没有职业等级。

## 4. 仍未验证（诚实）

- 求学路线**没有中举**：识字只有 109，解试需要 25 且要过随机判定，但资金与年份窗口经常不满足，76 年一次都没考上。`study_mark` 用的是"识字 ≥100"，不是功名。
- 每年只做一次路线行动，其余时间被节令与年关消耗；这不是完整生活模拟。
- 只跑了三个固定种子。
