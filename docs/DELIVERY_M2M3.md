# M2–M3 候选版交付总览（最终版）

- 分支：`agent/m2-m3`（领先 `main` 90+ 提交）
- 断言：**73 条全过**（`tools/verify.ps1`）
- CI：`isolated-smoke` + `continuity` 双绿（最近确认 `8d5ccb3`、`2136256`）
- 存档 schema：21；事件：41 条；节令场景：12 个；事实记录上限：320

## 一、按任务逐项对照

| 任务 | 交付 | 证据 |
|---|---|---|
| M2-01 事件 schema 与坏数据校验 | 白名单校验 + 精确报错 | `M2-01a-schema.md`、断言 `content_schema_validation` |
| M2-02 到期队列与机会调度 | 互斥/过期/取消/改期 + 冷却 | `M2-02a-queue.md`、`queue_policies` |
| M2-03 三条因果链 | 借米（借→还/拖/赖）、家庭牺牲（当嫁妆/抓药/硬扛）、拜师（交情/保人/被拒/师父离世） | `M2-03a/b/c`、`debt_chain`、`family_sacrifice`、`master_chain` |
| M2-04 分阶段自主权 | 婴幼/少年/成年；可拒绝家里安排 | `M2-04a`、`autonomy_stages` |
| M2-05 0–18 岁闭环 | 12 个节令场景 + 开蒙 + 童年事件 | `M2-05a`、`life_slice_0_18`、`m2_choice_divergence` |
| M3-01 12 名核心 NPC 独立生活 | 各自目标、逐年行动、记忆（独立 `npc_log`） | `M3-01a/b`、`npc_independent_life facts=0->36` |
| M3-02 三条可走完一生路线 | 求学 / 手艺营生 / 留乡照护 | `M3-02a/b`、`m3_routes_walkable study=76 degree=true` |
| M3-03 按状态发生的家庭变化 | 提亲看家境、可拒绝、子女按婚育、父母只按健康与寿数 | `M3-03a`、`family_by_state` |
| M3-04 可追溯人生档案 | 章回带 `fid`、评价单列、落盘、结局页展示 | `M3-04a`、`M3-04b`、`life_archive`、`archive_on_screen` |
| M3-05 约 40 个受校验片段 | 41 条，覆盖幼/少/成/晚 | `M3-05a`、`story_fragments count=41` |

## 二、超出原任务的修复（都是被数据逼出来的）

| 修复 | 起因 |
|---|---|
| 重放快照补齐家庭/债务/学徒/节令字段 | 黄金重放在 Linux 变红 |
| 事实裁剪优先丢噪音 | 档案只剩 2 条章回，早年人生被删 |
| 日常劳动进档案（做木工/种田/读书） | 手艺人一生在档案里只剩"遇上旱" |
| 识字上限统一 200、技能统一 100 | 读书过 100 白读 |
| `_on_action` 执行层校验 `min_age` | 十岁小孩能应省试 |
| 动作与事件共用 `_age_ok` | 两套年龄判定 |
| 童年也抽事件、种田涨农技 | 11 条幼年片段永远抽不到 |
| 求学路线收入模型 | 76 年一次没中举，原因不是考不上而是没钱去考 |

## 三、验证入口

```powershell
tools\verify.ps1            # 73 条断言，退出码 0/1/2
tools\continuity.ps1        # 4 场景 × 3 进程快照零差异 + 磁盘变异可捕获
tools\playtest_check.ps1    # 试玩构建能否启动（PASS boot_ok events_line=[DB] … 41 条）
```

## 四、必须写明的未达成项

1. **候选 PR 未创建**：本机无 `gh`、无 `GITHUB_TOKEN`，`agent/m2-m3` 没有任何 PR。需要人工点：
   `https://github.com/nicojiong/Life/compare/main...agent/m2-m3?expand=1`，正文用 `docs/PR_M2M3.md`。
2. **真人试玩未做**：`playtest_check.ps1` 只证明能启动、无脚本错误，不证明好玩。`human_play=pending_user_acceptance`。
3. **内容可达性只有 41%**（17/41）：9 条完整人生只碰到 17 条事件。两次尝试都失败并已回滚——婚育扩覆盖 41%→39%，幼年抽选率提到 85% 后覆盖数**一条没变**（说明瓶颈不在抽选率，真因尚未定位）。门槛 ≥40% 是现状下限，不是合格线。
4. 提亲对象固定"周氏"、无离婚/丧偶/再娶；子女只是计数；名望 100 后无内容。
5. 进士与做官链未验证；科举概率与家境/师承/地域无关。
6. 结局页无滚动/分页，章回超 6 条被截断，且未做渲染级截图验证。

## 五、结论

M2-01…M3-05 的**机制与断言**已全部落地并在本地与 CI 上通过；**内容体验层**仍有明确短板（可达性 41%、真人试玩缺失）。因此本分支状态为 `ready_for_user_acceptance`，`integrated_sha` 保持 `null`，不合并 `main`、不发布 Release。
