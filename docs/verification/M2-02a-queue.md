# M2-02a 验证证据：到期队列策略

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：51 → **52**

## 1. 新增的队列能力

| 能力 | 实现 | 行为 |
|---|---|---|
| 互斥组 | `_enqueue_event(..., group, expire)` | 同组已有未结算事件时，新事件不入队，记 `event_rejected/mutex` |
| 有效期 | 实例字段 `expire` | 到期时若 `now > expire`，记 `event_expired`，**不执行效果** |
| 显式取消 | `_cancel_event(sid, reason)` | 标记已结算、记 `event_cancelled`，不执行效果 |
| 主体死亡/失效 | 已有 `_apply_event_for` 的 cancel/transfer | 保持 |
| 无候选人物 | `target == ""` | 记 `cancelled_unknown_target` |

所有"没发生"的路径都不写 `event` 事实，因此不会进墓志、不会计入变故。

## 2. 断言

```
[VERIFY] PASS queue_policies mutex=true expire=true cancel=true
[VERIFY] SUMMARY pass=52 fail=0 failed=[]
```

三段各自独立验证：

1. **互斥**：同组第二条入队返回 0，队列仍是 1 条；
2. **过期**：到期时间已越过有效窗口 → 到期那一刻判过期，钱不变、`event` 事实 0 条、`event_expired` 1 条；
3. **取消**：`_cancel_event` 返回真，取消后推进时间不产生任何效果，`event_cancelled` 1 条、`event` 0 条。

## 3. 断言抓到的真 bug

`_cancel_event` 第一次写成了：

```gdscript
if ...:
    continue
    d["fired"] = true      # 永远执行不到
    return true
return false
```

函数永远返回 false。断言里 `cancelled=false` 直接把它抓出来——这是"只验证两边相等"发现不了的。

## 4. 未覆盖

- 互斥组只在同一队列内生效，没有跨"世界事件"与"个人事件"的组。
- 过期只按"月"判断，没有按天/小时。
- 取消没有面向玩家的提示，只有事实日志。
- 定义层（events.json）还没有 `group/expire` 字段；目前由调用方传入。
