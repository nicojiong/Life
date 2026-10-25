# M3-10 验证证据：开馆授徒进书院面板

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：66 → **67**

## 1. 改了什么

上一轮"开馆授徒"只活在自动演练脚本里，玩家在书院面板点不到——这是"测试有、游戏没有"的典型。

本轮把它加进 `_actions_for("academy")`：

```gdscript
if learning >= 120.0:
    acts.append({"label": "开馆授徒（一年，识字一百二）", "months": 12, "cost": 0,
        "gain": {"money": 1500, "learning": 2, "fame": 3}, "req": {"learning": 120.0},
        "flavor": "你在自家堂屋摆了几张矮桌，收了六个蒙童。"})
```

## 2. 断言

```
[VERIFY] PASS academy_teaching_option low_hidden=true high_offered=true money_ok=true
[VERIFY] SUMMARY pass=67 fail=0 failed=[]
```

三件事：

1. 识字 60 时，面板里**没有**"开馆授徒"（不能提前享受）；
2. 识字 130 时，面板里**有**这条；
3. 这条的 `gain.money ≥ 1000`，不是空壳选项。

## 3. 本轮踩的坑（记录，避免重犯）

把这段插进 `match id:` 分支时连续崩了四次：

1. 插到 `return acts` **之后** → 语句不可达，且 `"temple":` 变成非法 match 分支；
2. 用 `-join $nl` 拼块，PowerShell 5.1 下换行没生效，整段挤成一行；
3. 缩进少一层（`acts.append` 落在 `if` 外面）；
4. 块尾没补换行 → `return acts` 和 `"temple":` 连在同一行。

最后用"定位 `\t\t\treturn acts` 行号 → 按索引插入 → 读回缩进核对 → 跑 verify"这套流程才成。教训：**改 GDScript 结构必须按行号 + 回读缩进，不能靠字符串替换**。

## 4. 未覆盖

- 断言只检查面板返回的动作列表，**没有模拟点击**，也没验证 12 个月的时间推进与冷却。
- 面板里仍缺"开馆"带来的后续（学生、束脩波动、被人请去讲学）。
- 名望 100 之后依然没有新内容。
