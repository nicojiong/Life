# 内容校验：事件/节令/出身的 ID 与必填字段

- 日期：2026-10-24
- 任务：M2-01 的前置（内容定义协议的第一块）
- 断言：`content_ids_valid`，总数 31 → **32**

## 1. 为什么先做这个

M2 要加大量事件、节令选项与出身。这些内容现在都是 GDScript 里的常量表：

- `EVENTS`（14 条年度事件）
- `CHILD_EVENTS`（童年事件）
- `YEAR_SCENES`（6 个节令）+ `SCENE_OPTS`（每个节令的选项）
- `data/origins.json`（10 种出身）

表一长，最容易犯的错是**重复 id** 和**新增出身没有对应行当**。两种错都不会崩溃，只会静默地让某条内容永远抽不到、或让某个出身的父亲变成默认农夫——正是 M0-03 修过的那类 bug。

## 2. 校验内容

| 对象 | 检查 |
|---|---|
| `EVENTS` / `CHILD_EVENTS` | id 非空、不重复；`min_age`/`max_age` 在 0–100 且 max ≥ min |
| `YEAR_SCENES` | id 不重复；每个节令在 `SCENE_OPTS` 里有定义、至少 2 个选项 |
| `SCENE_OPTS` | 选项 id 非空、同一节令内不重复 |
| `origins` | flags 非空；至少含一个职业 flag；能映射到已知行当；weight > 0 |

返回的是问题列表而不是布尔值——断言失败时直接打印 `dup_event:drought` 这样的可定位信息，而不是一句"内容有问题"。

## 3. 断言

```
[VERIFY] PASS content_ids_valid events=14 scenes=6
[VERIFY] SUMMARY pass=32 fail=0 failed=[]
```

## 4. 这条断言不是摆设

写完先做了一次**注入验证**：临时在 `EVENTS` 里加一条重复的 `drought`，重跑：

```
[VERIFY] FAIL content_ids_valid ["dup_event:drought"]
```

确认它会红之后再把注入撤掉。一条永远不会红的校验等于没有校验。

## 5. 未覆盖

- 只做结构校验，不检查"事件 id 是否真的有对应的 `_apply_event` 分支"（需要反射或显式注册表，留给 M2-01 的事件定义协议）。
- 不检查文案里引用的 `story` flag 是否存在。
- 不检查数值平衡（例如某事件扣钱是否超过初期收入）。
- 校验在运行时跑，不在构建期；内容写错仍然能启动，只是断言会红。
