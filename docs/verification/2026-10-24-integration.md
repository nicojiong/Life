# 集成验收：四个已复现缺陷 + CI 修复

- 日期：2026-10-24
- 基线：`33a768b`（`agent/M1-ci-workflow`）
- 本次提交：`3986a9b`（缺陷修复）、`e893052`（CI 修复）
- 断言总数：**26 条，全部通过**

## 1. 四个已复现缺陷

### 1.1 父亲在长行动中死亡后，收益发给了孩子

**复现**：替父亲操控，执行一个 12 个月的长行动；父亲的年龄已到寿数，跳时中触发 `_parent_death` → 视角自动切回孩子 → 回到 `_on_action` 继续发奖，`+5000 文`记到孩子头上。

**修复**：`_on_action` 在扣钱前记录 `acting_pov`，跳时与特殊效果之后各检查一次 `if pov != acting_pov`，中断并返回，不发奖：

```
[ACTION] interrupted_by_pov_change father->child
[VERIFY] PASS action_pov_change_no_reward money=1000 pov=child
```

### 1.2 父母死亡被重复结算

**复现**：`_parent_death()` 没有幂等守卫。重复调用会再扣一次 `parents_alive`、再写一条 `death` 事实、再弹一次提示。

**修复**：函数入口检查 `parent_dead[who]`，已结算直接返回：

```
[DEATH] already_settled father
[VERIFY] PASS parent_death_settled_once alive=1
```

### 1.3 真实事件仍用未保存的全局随机数

**复现**：`_roll_event` 的事件池挑选、童年事件标记、赴任县名，仍用 `randi() % pool.size()`。这条全局流不存档、不可复现，且与画面随机混在一起。

**修复**：新增 `_pick_from(pool)`，内部只走 `sim_rng`；三处调用全部改道。现在全文件只剩启动种子一处 `randi()`：

```
[VERIFY] PASS events_use_saved_rng pick=c
```

### 1.4 未来版本存档被接受并降级保存

**复现**：读档只做 `schema_version < 2` 的旧档兼容，从不检查"存档比程序新"。更高版本的存档会被读进来，下一次保存时按当前版本写回，新字段被静默丢弃。

**修复**：读档时 `file_ver > SAVE_SCHEMA_VERSION` → 置 `save_future`、拒绝加载、`_save_game` 拒绝写盘：

```
[SAVE] future_version 7 > 6
[SAVE] refused_future_save
[VERIFY] PASS save_rejects_future_version kept=7.0
```

## 2. 长行动 / 冷却 / 人物切换

| 规则 | 现状 |
|---|---|
| 短行动不耗时、长行动（≥6 月）跳时 | 不变 |
| 冷却 = 声明月数，从结算之后起算 | 不变（长行动已用自己的时间付过账） |
| 冷却键 | 改为 `_action_key(act)`：优先 `id`，否则内容签名（标签+月数+效果） |
| 视角切换 | 行动中切视角即中断，不发奖 |

```
[VERIFY] PASS action_key_stable sig=sig:读书|m1|glearning id=id:study
```

## 3. 按户结算（M1-02 剩余项之一）

年关支出原先按**当前操控者**的年龄算：`300 + age*4`。换成父亲过日子，这一家的年关就按父亲的年龄收；换成孩子，又按孩子收。

现在 `_household_year_cost()` 汇总**所有在世成员**（已故不计），年关与操控谁无关：

```
[VERIFY] PASS household_year_cost paid=1250 single_actor_would_be=340
```

## 4. CI 修复

| 问题 | 修复 |
|---|---|
| Linux 上 `user://` 在 `~/.local/share/godot`（小写），脚本用 `Godot` 判定目录 → 误报"隔离失败"、退出码 2 | 按平台选 `godot` / `Godot` |
| 日志写在临时目录，`finally` 先删掉，`upload-artifact` 拿到空目录 | 先落盘到 `verify-artifacts/`，再清理 |
| 只校验 PASS/FAIL 计数，跑一半也可能"通过" | 新增 `-ExpectedAssertions`，缺 SUMMARY 或条数不符即失败 |

## 5. 真实 CI 结果

| 运行 | SHA | 结果 |
|---|---|---|
| 40050519482 | `e8cf720` | failure（退出码 2：Linux 路径大小写） |
| 40050570193 | `33a768b` | failure（同上，且日志产物为空） |
| 40051930378 | `e893052` | **success** |

成功运行的步骤：checkout → 安装 Godot 4.7.2 → `tools/verify.ps1` → 打印日志 → 上传 `verify-artifacts`（1207 B）。

## 6. 未覆盖

- 四个修复只做了单元级断言，没有做真人试玩的端到端复现。
- 时间边界队列仍未显式化（年关/生日/死亡仍靠代码先后顺序）。
- 未拆五类随机流，`sim_rng` 仍是单一流。
- 黄金重放（固定 seed + 命令序列逐 tick 比对）未开始。
