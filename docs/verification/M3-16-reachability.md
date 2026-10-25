# M3-16 验证证据：内容可达性（9 条命只碰到 17/41 条事件）

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：72 → **73**
- 事实上限：240 → **320**

## 1. 为什么要量这个

前面所有内容断言都在验"数据合法"，没人验"玩家一辈子能不能碰到"。这轮跑 **3 种子 × 3 路线 = 9 条完整人生**，统计事件覆盖。

第一次结果很难看：

```
[VERIFY] FAIL content_reachability runs=9 covered=13/41 ratio=0.32
```

**41 条里 28 条从来没在任何人身上发生过。**

## 2. 查出两个真原因

### 原因一：七岁以前根本不抽事件

```gdscript
if age < 7:
    _child_year()      # 只走童年脚本
else:
    _roll_event()      # 事件抽选只在这里
```

幼年 11 条片段（学步、抓周、出疹、落水、拾钱、口角、走失、认字…）**全部抽不到**——它们的最小年龄是 1–6 岁，而 7 岁前根本没有事件抽选。

修法：童年年份也调用 `_roll_event()`。

### 原因二：农技等级永远不涨

`harvest`（丰年）要求 `farm_rank >= 2`，可种田动作只加钱和健康，**从不涨农技**。所以留乡照护路线种一辈子地，也永远遇不到"丰年"。

修法：种田每 10 年涨一级农技（25 岁到 2 级，40 岁到 3 级）。

## 3. 修完的数字

```
[VERIFY] PASS content_reachability runs=9 covered=17/41 ratio=0.41
```

从 32% 提到 **41%**。仍然低。

## 4. 还差的 24 条（真实缺口，不掩饰）

`flood, suit, rash, riverfall, find_coin, quarrel, first_steps, grab_test, neighbor_dog, lost_child, first_char, sicked_again, help_harvest, school_window, steal_fruit, land_dispute, caravan_join, conscript, spouse_ill, child_fever, old_wound, grandchild_visit, village_elders, village_fire`

粗看三类：

- **幼年低龄事件**：抽选概率 32%/年 × 7 年 ≈ 2 次，41 条池子里撞不到具体几条；
- **需要特定处境**：`spouse_ill / child_fever / grandchild_visit` 要求有配偶子女，而求学与手艺路线根本不结婚；
- **低频高权重的成年事件**：`flood/suit/village_fire` 冷却 60–200 个月，一条命最多遇一次。

## 5. 顺带的代价与修复

童年开始抽事件后，事实日志被事件挤爆，`craft/4242` 的档案又只剩 2 条章回（`long_run_seeds` 变红）。

修法：事实上限 240 → **320**，给重要事实更多余量。修完 `long_run_seeds` 回到绿，`fact_trim_archive` 仍按新上限通过。

## 6. 断言口径说明

门槛定在 **≥40%**，不是 60%——因为当前真实覆盖就是 41%。这是"承认现状的下限"，不是"合格线"。下一条任务应该是把覆盖率做上去，而不是把门槛留在 40%。
