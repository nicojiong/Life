# 候选 PR：M2–M3（事件系统 / 三条因果链 / NPC 独立生活 / 三路线 / 家庭变化 / 人生档案）

- 分支：`agent/m2-m3`
- 基线：`main`（**不合并**，等待人工验收）
- `integrated_sha`：`null`（尚未合并，不填）
- 状态：`ready_for_user_acceptance`，其中真人体验项保持 `pending_user_acceptance`

## 一、这个 PR 做了什么

把《浮生》从"能出生、能长大"推到"能过完一生、留下可查的档案"：

1. **事件系统**：schema 校验 + 坏数据定位；到期队列与机会调度（互斥/过期/取消/改期）。
2. **三条完整因果链**：借米（借→还/拖/赖）、家庭牺牲（卧病→当嫁妆/抓药/硬扛）、拜师（交情/保人/被拒/师父离世）。
3. **分阶段自主权**：婴幼不可动、少年受限、成年自主；可拒绝家里安排。
4. **0–18 岁可玩闭环**：12 个节令场景 + 开蒙选择 + 童年事件。
5. **12 名核心 NPC 独立生活**：各自目标、逐年行动、记住玩家（独立 `npc_log`，不挤占玩家事实）。
6. **三条可走完一生的人生路线**：求学 / 手艺营生 / 留乡照护。
7. **按人物状态发生的家庭变化**：提亲看家境与意愿、可拒绝、子女按婚育与健康、父母只按健康与寿数死亡。
8. **可追溯人生档案**：死亡时生成，章回带 `fid`，评价单独标注 `is_evaluation`。
9. **41 条受校验故事片段**：覆盖幼/少/成/晚四个年龄带。

## 二、验证

```
tools\verify.ps1        -> 63 条断言全过
tools\continuity.ps1    -> 4 场景 × 3 进程快照零差异 + 磁盘产物变异可捕获
tools\playtest_check.ps1 -> PASS boot_ok events_line=[DB] 出身 10 种，年号 20 个，事件 41 条
```

CI 对每个提交都跑 `isolated-smoke` 与 `continuity`，最近一次为双绿。

证据文件（每条断言对应一份）：

| 主题 | 文档 |
|---|---|
| 事件 schema | `docs/verification/M2-01a-schema.md` |
| 到期队列 | `docs/verification/M2-02a-queue.md` |
| 借米链 | `docs/verification/M2-03a-debt.md` |
| 家庭牺牲链 | `docs/verification/M2-03b-family.md` |
| 拜师链 | `docs/verification/M2-03c-master.md` |
| 分阶段自主权 | `docs/verification/M2-04a-autonomy.md` |
| 0–18 切片 | `docs/verification/M2-05a-slice.md` |
| NPC 独立生活 | `docs/verification/M3-01a-npc.md`、`M3-01b-npc12.md` |
| 三条路线 | `docs/verification/M3-02a-routes.md`、`M3-02b-route-fix.md` |
| 家庭变化 | `docs/verification/M3-03a-family-state.md` |
| 人生档案 | `docs/verification/M3-04a-archive.md` |
| 故事片段 | `docs/verification/M3-05a-fragments.md` |
| 多种子长跑 | `docs/verification/M3-05b-longrun.md` |

## 三、两个"早年选择影响后来"的例子

1. **开蒙读书 vs 帮工**：同种子 4242，12 岁识字 51 vs 3，18 岁存款 2114 vs 3814（`m2_choice_divergence`）。
2. **借米还清 vs 赖账**：还清才有保人，二十岁拜师才有 `guarantee=true`（`master_chain`）。

## 四、试玩入口

- `play.bat`：正常玩，存档在 `%APPDATA%\Godot\app_userdata\浮生`
- `playtest.bat`：隔离试玩，存档在 `...\LifePlaytest`，不碰原存档
- 详细说明见 `docs/PLAYTEST_M2M3.md`

## 五、已知不足（请在验收时一并看）

1. ~~求学路线一次都没中举~~ → 已修：收入模型调整后自动演练 `degree=true`；`study_mark` 现要求"举人/进士"。进士与做官链仍未验证。
2. 提亲对象固定"周氏"，不看关系；没有离婚/丧偶/再娶。
3. 子女只是计数，没有独立成长线。
4. ~~结局界面不展示档案~~ → 已接上：结局页显示「一生章回」「后人评」，最多 6 条章回。
5. 长跑只有 2 个种子，无混合策略（中途改行）。
6. `_archive_line` 的文案是一句短语，未按贫/富/官/匠分叉。
7. 真人试玩**尚未进行**——`playtest_check.ps1` 只证明能启动、无脚本错误。

## 六、验收清单

- [x] 事件 schema 与坏数据校验
- [x] 到期队列与机会调度
- [x] 三条因果链（借米/家庭牺牲/拜师）
- [x] 分阶段自主权
- [x] 0–18 岁可玩闭环
- [x] 12 名核心 NPC 独立生活
- [x] 三条可走完一生的人生路线
- [x] 按人物状态发生的家庭变化
- [x] 可追溯人生档案
- [x] 41 条受校验故事片段
- [x] 每个提交都有对应 CI 结果
- [x] Windows 试玩入口（`playtest.bat` + `playtest_check.ps1`）
- [ ] **真人试玩**（`pending_user_acceptance`）
- [ ] 合并到 `main`（本轮不做，`integrated_sha` 保持 `null`）
- [ ] 发布 Release（本轮不做）
