# M2-01a 验证证据：事件内容 schema 校验

- 日期：2026-10-25
- 分支：`agent/m2-m3`（候选集成线）
- 基线：`6ef8033`
- 断言：50 → **51**

## 1. 做了什么

新增 `scripts/core/content_schema.gd`：

```
validate_events(events, source) -> [{code, path, message}]
```

- **必填**：`id / name / min_age / weight / cooldown`
- **类型**：id/name/cond/text 字符串，min_age/max_age/weight/cooldown 整数，effects 对象
- **取值范围**：0 ≤ min_age ≤ 120，max_age ≥ min_age，weight ≥ 1，cooldown ≥ 0
- **唯一性**：id 不得重复
- **未知字段**：顶层出现清单外的键直接报错（不再静默忽略）
- **条件白名单**：`"" / farm / famous / parent`——加新条件必须同时实现 `_event_ok` 分支
- **效果白名单**：`money / health / fame / story`，类型逐个检查

错误路径精确到 `data/events.json[3].effects.cash` 这一级，不再"取默认值继续跑"。

`DB` 加载后立即校验，结果存 `DB.event_errors`，非空时 `push_warning` 打印全部错误。

## 2. 断言

```
[VERIFY] PASS content_schema_validation codes=7 precise=true
[VERIFY] SUMMARY pass=51 fail=0 failed=[]
```

两件事同时验证：

1. **线上数据干净**：`DB.event_errors` 为空；
2. **坏数据能被抓**：手工构造 9 条事件，覆盖 7 类错误
   （`missing_field` / `duplicate_id` / `bad_age_range` / `unknown_condition` / `unknown_effect` / `bad_type` / `unknown_field`），
   并断言路径精确到 `data/events.json[1].id`（缺 id）与 `[3].id`（重复 id）。

这条断言不是"数一数有几条错误"，而是**逐类核对错误码与路径**——放宽任何一类都会红。

## 3. 尚未覆盖

- 条件只校验"名字已实现"，没有校验"条件与人物角色是否匹配"（例如 `parent` 只能作用于有子女者）。
- 效果只校验键与类型，没有校验"数值范围是否合理"（例如 `health: -500`）。
- `CHILD_EVENTS`、`YEAR_SCENES`、`origins.json` 仍在代码/其他文件里，尚未纳入同一校验器。
- 事件定义与运行实例的字段级分离只做了一半：实例已有 `target/policy/due`，但定义里还没有"持续时间/互斥组"等调度字段（M2-02 补）。
