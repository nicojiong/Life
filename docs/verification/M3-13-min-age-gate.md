# M3-13 验证证据：年纪门槛必须在执行层生效

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：69 → **70**

## 1. 抓到的真 bug

`_on_action()` 里只检查了 `ended`、钱、`req.learning`、冷却——**没有检查 `min_age`**。

界面之所以没出问题，是因为 `_actions_for()` 在生成动作时按年龄过滤了。但这意味着：

- 任何绕过界面的路径（脚本、事件、以后加的快捷操作）都能让十岁小孩去应省试；
- 年纪门槛只是"看不见的按钮"，不是"做不了的事"。

## 2. 修法

在 `_on_action()` 的钱与 `req` 检查之前插入：

```gdscript
if act.has("min_age") and age < int(act["min_age"]):
    _toast("还不到年纪。", Color(0.62, 0.24, 0.18))
    return
```

现在门槛在**执行层**，UI 过滤只是体验优化。

## 3. 断言

```
[VERIFY] PASS min_age_gate blocked_at10=true allowed_at20=true
[VERIFY] SUMMARY pass=70 fail=0 failed=[]
```

两件事：

1. **10 岁时**调用"应省试"（`min_age: 16`）：钱没变、月索引没变、没有"进士"——被挡住；
2. **20 岁时**同一条动作：钱被扣 或 时间前进——真的执行了。

用 `_replay_snapshot()` / `_replay_restore()` 包住，不影响后面的断言。

## 4. 未覆盖

- 只验了 `min_age` 一条动作，没有遍历所有带 `min_age` 的面板动作（现在有 40+ 条带门槛的）。
- `max_age` 没有对应检查——目前代码里没有这个字段，但事件定义里有 `max_age`，两边语义还没统一。
- 没有验证"刚好等于 min_age 的那一年"是否允许（断言用的是 10 与 20，跨过了边界）。
