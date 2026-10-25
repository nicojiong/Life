# M4-03 修复证据：借米延期重排期 / 切视角结算

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：74 → **75**（新增 `debt_defer_rearm`）

## 1. 两个已确认的缺陷

### 缺陷一：延期取消了旧事件，却没有重新排期

```gdscript
func _defer_debt() -> String:
	debt_deferrals += 1
	_cancel_event(debt_due_sid, "debt_deferred")   # ← 取消了
	debt_due = maxi(_month_index() + 1, debt_due + 3)
	# ← 没有 _enqueue_event
```

结果：宽限一次之后，这笔债**永远不会再到期**，既不会被还，也不会赖账——借米链在延期那一步断掉。

### 缺陷二：非当前视角的到期债务被"消费"但不结算

借米到期事件固定投给 `child`（`_enqueue_event(..., "child", ...)`）。当玩家切到父亲视角时：

- `_apply_event_for("child", "debt_due", ...)` → `_apply_event_to_actor("child", ...)`
- `who != pov` → `_apply_event_to_inactive("child", "debt_due")`
- 该函数只处理 `plague` / `harvest` 两个特例，**没有 `debt_due` 分支**，于是走到 `_apply_event_effects(def)`，而 `debt_due` 没有数据定义 → 什么都不做
- 但实例已被标记 `fired = true` → 这笔债**静默消失**

## 2. 修复

```gdscript
# _defer_debt 里
debt_due = maxi(_month_index() + 1, debt_due + 3)
debt_due_sid = _enqueue_event("debt_due", "debt", debt_due, 0, "child", "cancel", "debt", debt_due)

# _apply_event_to_inactive 开头
if id == "debt_due":
	_debt_settle_due()
	_check_actor_deaths()
	return
```

债务是家庭级的，不吃视角这一套：谁在看画面，到期都要结算。

## 3. 断言

```
[VERIFY] PASS debt_defer_rearm sid=1->2 due=12491->12494 settled=true fact=true pov_settled=true
```

五件事，全部走正常月推进（`_advance_months`）：

| 检查 | 含义 |
|---|---|
| `sid=1->2` | 延期后确实生成**新的**事件实例，不是复用旧的 |
| `due 12491->12494` | 新到期日 = 旧到期 + 3 个月（从原到期日顺延，不是从现在重算） |
| `settled=true` | 推进到新到期日后，`debt_state` 不再是 `borrowed` |
| `fact=true` | 事实日志里出现 `debt / repaid` 或 `debt / defaulted` |
| `pov_settled=true` | **切到父亲视角**后推进到到期日，债务同样被结算 |

## 4. 未覆盖

- 只验了一次延期；两次延期（`debt_deferrals == 2` 后拒绝）没验新的排期行为。
- 视角测试只用了 father，没有测 mother。
- 债务结算后没有验证"还款金额与关系变化"是否与直接还清一致。
