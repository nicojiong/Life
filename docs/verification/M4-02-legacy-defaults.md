# M4-02 修复证据：旧档缺字段不得继承脏内存

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：73 → **74**（新增 `legacy_defaults`）

## 1. 问题（审查意见第 2 条，确认成立）

`_load_game()` 里大量这样写：

```gdscript
debt_units = int(d.get("debt_units", debt_units))
apprentice_state = str(d.get("apprentice_state", apprentice_state))
married = bool(d.get("married", false))
children = int(d.get("children", children))
```

缺字段时取的是**当前内存里的值**。于是 schema14 之类的旧档，如果上一个局还留着债务、NPC 记忆、师徒状态、婚事、嫁妆，加载后这些"上一局的残留"就被当成这一局的状态。

## 2. 修复

把所有这类兜底改成**显式默认值**：

| 字段组 | 缺失时的默认 |
|---|---|
| 债务 | `debt_units/due/deferrals/due_sid = 0`、`debt_state = "none"` |
| NPC | `npc_state = {}`、`npc_log = []`、`npc_seq = 0`（之后由 `_npc_ensure()` 重建 12 人） |
| 学徒 | `apprentice_state = "none"`、`master_available = true` |
| 婚事 | `married = false`、`spouse_name = ""`、`children = 0`、`marriage_* = false/0` |
| 物品 | `heirlooms = {HEIRLOOM_HAIRPIN: 1}` |
| 卧病 | `family_ill_pending = false`、`ill_who = ""` |

## 3. 断言

```
[VERIFY] PASS legacy_defaults dirty={ "npc_dirties": 12, "npc_log": 0, "npc_seq": 0, "apprentice": "none", "master": true, "heirloom": 1, "debt": "0/0/none/0/0", "married": false, "spouse": "", "children": 0, "m_pending": false, "m_refused": false, "m_wait": 0, "ill": false, "ill_who": "" } clean_same=true
```

做法：

1. 用 `_state_dict()` 造一份 **schema=14** 的旧档，删掉 19 个新字段；
2. **脏内存**加载：先把债务设 5、NPC 记忆设成脏值、学徒设 `refused`、`married=true`、嫁妆清空，再 `_load_game()`；
3. **干净内存**加载：把同样的字段复位到默认，再 `_load_game()`；
4. 两次结果 `JSON.stringify` **完全相等**（`clean_same=true`），且各项都等于默认值。

`npc_dirties: 12` 不是继承，而是 `_npc_ensure()` 在空状态上重建了 12 名 NPC 的初始状态。

## 4. 未覆盖

- 只覆盖上面 19 个字段；`story`、`milestones`、`scenes_done`、`opp_last`、`event_instances` 等仍是旧写法（多数用 `is Dictionary/Array` 判空，风险较低），没有逐一验证。
- 没有覆盖 schema 14 缺少 `month_frac`、`npc_log` 之外更早版本（如 v1 夹具）的组合情况。
- 没有验证"旧档里字段类型错误"（比如 `debt_units` 是字符串）时的行为。
