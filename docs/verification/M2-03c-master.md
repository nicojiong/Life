# M2-03c 验证证据：拜师 / 介绍 / 拒绝链

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：54 → **55**
- 存档 schema：16 → **17**

## 1. 机制

| 项 | 设计 |
|---|---|
| 师傅 | 木匠陈师傅（稳定 id `chen`），关系存 `relations` |
| 条件 | 12–20 岁、未拜过、师傅在世、不是士人 |
| 送礼拜师 | 200 文，关系 +2 |
| 托人介绍 | 不花钱，但需要保人（`有人作保` 或 `借米还清`） |
| 判定 | 关系 ≥ 3 或有保人 → 成功：`craft +6`、`craft_rank≥1`、`story["拜师"]`、关系 +3 |
| 资源不足 | 200 文不够 → `insufficient`，状态不变 |
| 被拒 | 关系不足且无保人 → `refused`，关系 −1 |
| 师傅不在 | `master_available=false` → `unavailable`，不改变状态 |
| 主动不去 | `decline` → `refused` + `story["没拜成师"]` + 关系 −1 |

玩家入口：四月「拜师」场景（`cond: apprentice`），三个选项：备二百钱上门 / 托人介绍 / 算了不去。

## 2. 断言

```
[VERIFY] PASS master_chain short=true refused=true guarantee=true gone=true reload=true
[VERIFY] SUMMARY pass=55 fail=0 failed=[]
```

六段（干净起点：12 岁、无师、关系 0、无保人）：

1. 钱不够 → `insufficient`，钱与状态都不变；
2. 关系不足且无保人 → `refused`；
3. 有人作保 → **不花钱**也能拜师，手艺术提升、关系上升；
4. 师傅不在 → `unavailable`，状态不变；
5. 主动不去 → `refused` 且留痕；
6. 存读档 → `apprentice_state` 与 `master_available` 保持。

## 3. 与前面两条链的交叉

- 第 3 段的"保人"复用借米链的 `借米还清` / `有人作保` 标记——还过米的人更容易拜师，这是两条链的真实交叉。
- 卖嫁妆降母亲关系，不影响师傅关系；目前没有"母亲反对学手艺"的分支（留 M2-04）。

## 4. 未覆盖

- 师傅不会死亡或离开（要等 M3-01 NPC 生命周期）。
- 拜师后没有出师/自立门户的后续。
- 只有一位师傅，没有推荐到别家。
- 被拒后同一世不能再申请（`apprentice_state=refused` 锁死），没有"再试一次"。
