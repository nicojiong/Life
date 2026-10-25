# M4-01 修复证据：正常死亡接入档案事务

- 日期：2026-10-25
- 分支：`agent/m2-m3`
- 断言：仍 73 条，但 `death_archive_transaction` **替换了原来恒真的 `dup_ok`**

## 1. 审查发现的问题（确认成立）

`_ending()` 里只有 `_clear_save()`：

```gdscript
func _ending() -> void:
	if ended: return
	ended = true
	panel.visible = false
	_clear_save()        # ← 先清档
	...cutscene...
```

人生档案的写盘逻辑在之前几次文件回滚中**已经丢失**。结果：正常寿终/病死时，普通存档被删掉，档案却一份都没留下。

## 2. 修复：单一死亡事务

```gdscript
func _die_and_archive(cause: String) -> void:
	death_cause = cause
	if death_fact_fid == 0:
		death_fact_fid = _log_fact("death", cause, {...})   # 1) 致死事实
	last_archive = _build_life_archive()
	var wrote := _write_life_archive(last_archive)          # 2) 落盘
	life_archive_written = wrote
	if wrote:
		_clear_save()                                       # 3) 只有落盘成功才清档
```

`_ending()` 改为：`ended = true` → `_die_and_archive(death_cause)` → 播放死亡过场。不再有第二处 `_clear_save()`。

档案文件名也改成一生一档：

```
user://life_archive_<slot>_<出生年>_<种子>.json
```

## 3. 断言（替换恒真项）

```
[VERIFY] PASS death_archive_transaction written=true death_fact=true cleared_after=true no_dup=true restart=true distinct=true first_intact=true
```

七件，全部是真检查：

| 检查 | 含义 |
|---|---|
| `written` | 档案文件真的写出来了，`age`/`death_cause` 与死亡时一致 |
| `death_fact` | 事实日志里**恰好 1 条** `death` 事实，且 `death_fact_fid > 0` |
| `cleared_after` | 落盘之后普通存档确实被清掉 |
| `no_dup` | 再调一次死亡事务，档案内容逐字节不变（`JSON.stringify` 相等） |
| `restart` | 清空内存 `last_archive` 后仍能从磁盘读回同一份（姓名、章回数一致） |
| `distinct` | 换出生年/种子后档案落到**另一个文件** |
| `first_intact` | 旧的那份档案仍然完好（`age == 64`） |

原来的 `dup_ok=true` 已删除——那条断言什么都没验。

## 4. 未覆盖

- 只验证了 `_ending()` 这条路径；父母死亡（`_settle_actor_death` 的 `who != child` 分支）不写档案，因为那不是"玩家人生结束"，符合设计但没写断言。
- 没有验证"落盘失败时保留存档"这条分支（需要构造写盘失败）。
- 档案文件没有被旧档迁移逻辑清理，长期玩会积攒多份文件；没有做清理策略。
