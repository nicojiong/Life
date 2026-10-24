# M2-03b 验证证据：家庭牺牲 / 珍贵物品链

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：53 → **54**
- 存档 schema：15 → **16**

## 1. 机制

| 项 | 设计 |
|---|---|
| 触发 | 年边界检查：在世家长健康 < 40 → `family_ill_pending = true`，记 `illness_started` |
| 选择 | 二月「卧病」场景（`cond: ill`）：当银簪 / 抓药 / 硬扛 |
| 卖嫁妆 | 银簪只能卖一次，+400 文，母亲关系 −2，`story["卖了银簪"]` |
| 抓药 | 300 文；钱不够返回 `insufficient` 并记 `medicine_unaffordable`，不改状态 |
| 硬扛 | 病人 −8 健康，`story["硬扛过病"]` |
| 失效 | 卧病者死亡后场景不再出现（`_scene_ok` 检查 `_actor_is_dead`） |

选择后清 `family_ill_pending`，同一年不会重复触发。

## 2. 断言

```
[VERIFY] PASS family_sacrifice started=true treat=true heirloom=true endure=true reload=true
[VERIFY] SUMMARY pass=54 fail=0 failed=[]
```

五段（自带干净起点：父母在世、有银簪、母亲 30 血）：

1. **触发**：`_maybe_start_family_illness()` 选中母亲；
2. **资源不足**：钱 100、药 300 → `insufficient`，钱不变；
3. **卖嫁妆只能一次**：第一次成功 +400，第二次返回 false，银簪计数为 0；
4. **抓药有效**：钱 400 → 扣 300，母亲回血；
5. **存读档**：嫁妆数量、卧病标记、卧病者三项都保持。

## 3. 未覆盖

- 只有一件嫁妆（银簪），没有多件可卖。
- 卧病只按"健康 < 40"触发，没有按季节/疫病/年龄加权。
- 卖嫁妆只降母亲关系，没有后续"母亲记恨/临终提起"的长回响（留 M3-04）。
- 场景选项没有禁用态（钱不够仍可点，点了才失败）。
