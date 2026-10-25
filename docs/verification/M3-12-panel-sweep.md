# M3-12 验证证据：面板动作全量抽查（40 条，无一"文案摆设"）

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：68 → **69**

## 1. 从一条推广到一批

上一轮只点了"开馆授徒"一条。这轮把检查推广成扫描：

- 覆盖 23 个面板 id（home / field / school / market / academy / temple / yamen / teahouse / pharmacy / shrine / smithy / tavern / pawnshop / washe / mulberry / dye / inn / drill / dock / lot / grave / garden / thresh）
- 逐条取动作，最多测 **40 条**
- 每条都真的调 `_on_action(act)`

## 2. "有响应"怎么判

以下四者**任一**成立即算有响应：

| 判据 | 含义 |
|---|---|
| 月索引变化 | 时间真的走了 |
| 钱/识字/手艺/名望变化 | 收益真的结算 |
| 进入冷却 | 该动作被记账，不能连点 |

三者全否 → 记为 `dead`（摆设动作）。

## 3. 断言

```
[VERIFY] PASS panel_actions_respond tested=40 dead=0
[VERIFY] SUMMARY pass=69 fail=0 failed=[]
```

## 4. 隔离手法

每条动作执行前 `_replay_restore(pa_snap)` 回到同一分支点，再单独设好 `age=30 / money=99999 / learning=200 / action_cooldown={}`：

- 避免前一条动作的收益污染后一条；
- 避免"因为没钱/识字不够所以没反应"被误判成摆设；
- 全部跑完再整体还原，不影响后面的长跑与档案断言。

## 5. 没测到的部分（重要）

- **跳过所有 `special` 动作**：应解试、省试、升迁、告老、收贿等都在这些分支里，本轮**一条都没验**。
- 跳过没有 `gain` 的纯叙事动作。
- 仍是直接调用 `_on_action`，**没有经过真实按钮点击与面板重建**；禁用态、文案、刷新都没验。
- 只设了 `learning` 门槛，没有按 `min_age` 逐条构造对应年龄段，个别动作可能是在"不该能做的年纪"被点成功的。

所以这条断言能挡住"文案摆设"，但挡不住"条件错位的动作"。
