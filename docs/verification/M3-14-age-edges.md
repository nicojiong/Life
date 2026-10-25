# M3-14 验证证据：动作与事件共用同一套年龄判定（含边界）

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：70 → **71**

## 1. 之前的隐患

年龄判定有**两套**：

| 位置 | 写法 |
|---|---|
| `_on_action` | `if act.has("min_age") and age < int(...)` —— 只有下限 |
| `_event_ok` | `if age < min_age: return false` + `if age > max_age: return false` |

结果：动作没有上限概念（`max_age` 形同虚设），事件与动作的边界语义也可能不一致。

## 2. 修法

新增唯一判定：

```gdscript
func _age_ok(lo: int, hi: int) -> bool:
    if age < lo: return false
    if hi > 0 and age > hi: return false
    return true
```

- `_on_action`：`if act.has("min_age") and not _age_ok(min_age, act.get("max_age", 0))` → 挡住并提示"还不到年纪"；
- `_event_ok`：`if not _age_ok(ev.min_age, ev.max_age ?? 200)` → 挡住。

两边现在走同一函数，`hi <= 0` 表示无上限。

## 3. 断言

```
[VERIFY] PASS age_gate_edges below=true at_min=true at_max=true above=true event=true probes=4 probe_ok=true
[VERIFY] SUMMARY pass=71 fail=0 failed=[]
```

七件事：

1. 15 岁对 `min_age=16` → 挡住；
2. **16 岁正好等于门槛 → 允许**（边界算在内）；
3. 6 岁对 `max_age=6` → 允许；
4. 7 岁超出上限 → 挡住；
5. 事件侧同一条 helper：4 岁挡、5 岁放、7 岁放、8 岁挡；
6. 动作侧用四个合成动作（min_age = 12/15/16/18）验证：低于门槛钱不变；刚好到门槛钱 +10；
7. 探针数量 ≥3。

## 4. 未覆盖

- 仍用合成动作验证动作侧，**没有遍历真实面板里带 `min_age` 的条目**（它们在开科年/特定身份下才出现）。
- `max_age` 在动作侧目前没有任何真实动作使用，等于只验了 helper、没验玩法。
- 事件侧只用了一个合成事件，没有对 `data/events.json` 里 41 条逐条跑边界。
