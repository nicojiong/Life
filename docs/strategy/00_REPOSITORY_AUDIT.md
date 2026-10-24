# 00｜仓库现状与优先风险审计

> 用途：后续产品、架构、里程碑与 Agent 执行文档的现状依据。本文描述审计基线，不把规划中的功能视为已经实现。

## 1. 审计基线与证据边界

- 仓库：[nicojiong/Life](https://github.com/nicojiong/Life)。
- 基线：`main` 的 [2d035379f21abbc8d1d6f06d0328eb756751b993](https://github.com/nicojiong/Life/commit/2d035379f21abbc8d1d6f06d0328eb756751b993)，审阅日期为 2026-10-24。
- 方法：读取全部文本源码、配置、README 与 GDD，追踪出生、行动、时间、人物、事件、存档和死亡路径。未修改游戏代码或远程仓库。
- **本轮仅为静态审计，未运行 Godot、未实际游玩、未执行自动化测试。** 当前环境 PATH 未发现 `godot` 或 `godot4`，这不代表用户电脑没有安装。
- 项目配置声明 Godot 4.7；README 写有 4.7.2 的本机路径。它们是仓库声明，不能代替执行环境的 `--version` 核验。

下文行号均指上述固定 commit 的原始文件。核心文件 `scripts/street/village_scene.gd` 共 4631 行，同时承载模拟状态、规则、内容、界面、绘制、存档和调试，是渐进拆分的主要对象。

## 2. 能力分类：保留已有成果，识别真正缺口

| 分类 | 能力 | 源码实际表现 |
|---|---|---|
| 已实现 | 随机出生 | 从 10 种出身按权重抽取，读取钱、地点、属性和 flags；年龄从 0 开始。|
| 已实现 | 村庄交互 | 程序绘制村庄、A* 寻路、相机、小地图、地点行动、NPC 对话、昼夜季节和过场。|
| 已实现 | 多条职业路径 | 科举、官场、手艺、商业、医术、农业、军事和母亲妇业已有具体逻辑。|
| 已实现 | 父母视角与童年 | 可切换父母/孩子；14 条童年事件按年龄、父亲行当、母亲性情和贫穷条件筛选。|
| 部分实现 | 人物记忆 | 有单一 `att` 值影响台词、价格、选项，但关系不独立持久化。|
| 部分实现 | 有因果的事件 | 借米留下 flag，特定年龄催债；尚无通用债务、事件实例或延迟调度。|
| 部分实现 | 存档与完整一生 | 三槽存读、五档墓志已有，但存档遗漏状态，死亡边界和恢复路径存在风险。|
| 部分实现 | 随机身份 | 已随机家庭出身；主角姓名调用固定男性分支，出生年固定 1040–1044。|
| 未接入 | 可选时代 | DB 固定加载北宋文件；时代配置的起止年与历史 timeline 未进入模拟逻辑。|
| 未接入 | 通用自主世界 | NPC 主要在固定点附近随机走动，尚无独立欲望、职业计划和持续社会关系网。|
| 待验证 | 可运行、可通关、性能 | 必须在确认版本的 Godot 环境运行；源码和截图不能证明这些结论。|

主要证据：[出生与父母生成](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L962-L1053)、[出身权重](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/core/db.gd#L44-L69)、[行动与科举入口](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L2529-L2689)。README 末尾的“没有科举”已与实现不符，不能据此安排重建。

## 3. 十项优先发现

### A01｜P0：死亡不是可靠的结算终点

`_on_action()` 先通过 `_advance_months(m)` 跳时；跳时可能进入 `_ending()` 并清档，但返回后仍执行收益、特殊效果和 `_save_game()`。战死经 `_die_young()` 进入结局，也可能返回外层继续存档。`ended` 又未进入存档。

源码支持的风险是“行动中途死亡后仍发奖”和“清档后重写普通存档”；实际表现需运行复现。应统一行动结果 `completed / interrupted / actor_died / world_ended`，死亡后立即终止当前命令，再生成独立人生档案。

证据：[`_on_action` 2970–3006](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L2970-L3006)、[`_advance_months` 3420–3443](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L3420-L3443)、[`_die_young` / `_ending` 3675–3686](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L3675-L3686)。

### A02｜P0：存档不能完整恢复同一个世界

`_ready()` 先随机 `_init_identity()`，再 `_load_game()` 局部覆盖。`_state_dict()` 未完整保存 `father_trade`、`mother_temper`、当前 `women_rank`、`scenes_done`、`child_last`、`month_frac`、`time_scale`、NPC 状态、随机数状态等。

这使家庭属性可能来自新随机初始化；母亲当前职业可能丢失；节令与童年去重记录可能重置；模拟无法准确续接。应新增版本化 SaveEnvelope，区分游戏事实、人物状态和表现状态，提供迁移、校验、备份与原子写入。每个缺漏字段是否导致用户可见错误，要用专项往返用例确认。

证据：[`_ready` 272–278](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L272-L278)、[`_state_dict` / `_load_game` 301–411](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L301-L411)。

### A03｜P0：死亡父母与旧档补全使用同一种“缺失”状态

`_parent_death()` 从 `pov_state` 删除死亡父母；`_load_game()` 看到缺少父亲或母亲，会按兼容旧档的逻辑重新生成，未区分死亡与旧版本缺字段。应以稳定 actor ID 和 `alive/death_record` 表示死亡，禁止用删除人物实体表达死亡。旧档迁移按 `schema_version` 执行，不能每次读档补生。

证据：[`_load_game` 391–397](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L391-L397)、[`_parent_death` 2246–2254](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L2246-L2254)。

### A04｜P1：时间成本不一致，短行动可以即时刷值

地点行动只有 `months >= 6` 才推进月份；对话总推进 `months`；节令自行跳时；实时钟又独立推进。于是“歇三个月”可即时加健康，“看告示”可即时加学识，母亲“浆洗三个月”可即时加钱和手艺。`_strip_time()` 同时隐藏部分时间文案，让真实成本更难理解。

应选择唯一模拟时钟：长期收益必须消费时间或有限精力，查看与取消免费。地图走动可以保留表现时间，但不得与人生时间重复结算。长活动需要明确是否可中断及中途死亡如何处理。

证据：[`_on_action` 2987–2994](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L2987-L2994)、[对话推进 2212–2233](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L2212-L2233)、[浆洗与隐藏时间 1242–1254](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L1242-L1254)。

### A05｜P1：NPC 好感依附画面，重建与换视角会清零

对话修改 `npcs[i]["att"]`，但 `_spawn_npcs()` 每次重新创建 `att:0`。切视角、重建场景、读档都会经过重新生成。当前记忆不能支撑十年后仍记得玩家的行为。

应由 WorldState 持有关系和记忆，场景只按 actor ID 展示。关系至少区分信任、亲近、恩怨和债务；重要经历保存事件 ID，不能只留一个总分。

证据：[`_switch_pov` 1132–1152](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L1132-L1152)、[`_spawn_npcs` 1885–1976](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L1885-L1976)、[态度修改 2224–2227](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L2224-L2227)。

### A06｜P1：世界结算依赖当前控制谁

`_advance_months()` 给缓存人物年龄加一，但年关健康衰退、收入、事件、婚育里程碑主要操作当前视角的全局字段。婚姻、子女、父母存活数又由共享变量表示。非控制人物没有同等生命周期处理，另有主角 46 岁的固定丧亲剧情。

需要拆出 Actor、Household、World 三类状态，并让关键人物统一随时钟更新。主角一生模式默认只控制主角；父母引导由其资源、价值观和关系决定。保留父母视角时，观察行为不能改变世界规则。

证据：[视角字段 110–116](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L110-L116)、[年推进与年关 3427–3578](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L3427-L3578)。

### A07｜P1：延迟因果固定在年龄，临时人物无法可靠恢复

借米说“秋后还”，实际催债只在 22 岁触发；22 岁以后借款没有相同后续。“宽限三个月”只设置 flag，并未创建三个月到期任务。媒人和债主生成标记被保存，临时 NPC 本身未保存，读档可能留下“已经生成、人物不在”的状态。

应采用 `event_instance + due_at + bindings + cause_id + status`，到期时重新校验双方存活、地点、债务和关系。晚年借款也应按借款日计算后果。婚育可提供年龄窗口，但不能把某岁必生子当通用世界规则。

证据：[借米 2369–2371](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L2369-L2371)、[还款与延期 3075–3081](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L3075-L3081)、[固定生成 3482–3489](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L3482-L3489)。

### A08｜P1：时代与地域配置只部分消费

DB 固定读 `song.json`；出生年固定 1040–1044；时代 `timeline/start_year/end_year` 未用于世界推进。地点文字可为汴京或边地，但仍使用同一村庄与人物。现状不是“只差时代选择按钮”，而是缺少控制制度、职业、经济、事件、姓名和地点的 EraPack 边界。

先把北宋抽为完整配置包；第二时代用于验证通用引擎，不能只换显示文本。主角性别也应纳入出生身份和时代规则，避免扩展女性角色时沿用固定男性婚育文案。

证据：[DB 固定加载 30–40](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/core/db.gd#L30-L40)、[出生固定分支 962–983](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L962-L983)、[北宋配置](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/data/era/song.json)。

### A09｜P1：内容标识已有接线错误，必须先建立校验

商人家庭配置 flag 是“商贾”，出生逻辑检查“商人”，该出身的父亲行当会落入默认“农”。NPC `lao_seng` 连续定义两次。应使用稳定机器 ID，展示名称另存；导入时校验唯一 ID、引用、枚举、年龄约束、时代范围和数值边界。

证据：[商贾配置](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/data/origins.json#L35-L45)、[商人分支 989–998](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L989-L998)、[重复老僧 1915–1916](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L1915-L1916)。

### A10｜P2：结局和开发验证还不能衡量“独特人生”

墓志最高档依赖进士与声望，普通、独身人生容易得到“余无可书”。可以保留社会记载等级，同时增加个人愿望、亲密关系、实际影响和重要选择的独立叙述。结局必须引用真实事件，不凭空补写。

现有 debug 多为直接设状态、调用特殊效果并打印，缺少统一断言与失败退出码；截图证明某帧能显示，不能证明路线可达、存档正确或长期稳定。科举等调试会绕过正常行动前置条件，应另有从出生走正常接口的测试。

证据：[墓志评级 3766–3794](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L3766-L3794)、[科举调试 935–952](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/street/village_scene.gd#L935-L952)。

## 4. 首次 Agent 必须核对的十二条回归风险

以下是拟建立的验收用例，不代表本次已经运行通过。

| 编号 | 用例与通过条件 | 依据 |
|---|---|---|
| R01 | 重复短行动十次，产生收益就必须消耗约定时间/精力。| A04 |
| R02 | 界面显示的行动成本与实际时钟增量相符。| A04 |
| R03 | 活动跨越死亡时刻，不继续结算收益或特殊效果。| A01 |
| R04 | 死亡后不重建活人存档；人生档案可读且只写一次。| A01 |
| R05 | NPC 关系在切视角、重建场景和存读档后保持。| A05 |
| R06 | 同一存档的父亲职业、母亲性情保持不变。| A02 |
| R07 | 母亲升职后直接存档，读档保持当前妇业级别。| A02 |
| R08 | 已过节令和童年重复控制记录正确恢复。| A02 |
| R09 | 相同 seed、版本、选择序列产生相同模拟历史；存读档不改变后续抽取。| A02 |
| R10 | 父母死亡后存读档，不复活、不恢复活人对话。| A03 |
| R11 | 临时媒人/债主等待时存读档，事件与绑定人物都恢复。| A07 |
| R12 | 仅改变观察视角，世界人物年龄、收入和死亡事实不变。| A06 |

## 5. 调试与存档保护：先核实再运行

已有可复用入口包括 `village_save/load/years/exam/craft/trade/med/farm/mil/pov/father/mother/scenes/festival/epitaph`。它们可作为夹具素材，不能直接作为自动验收结论。`--shot=...` 在等待渲染后保存 PNG 并退出，也没有检查游戏规则。

**`--fresh` 的真实范围是四个文件：** `fusheng_save.json`、`fusheng_save_1.json`、`fusheng_save_2.json`、`fusheng_save_3.json`，位于该项目的 `user://` 下；不是只清当前档。见 [`main.gd` 清档与截图代码](https://github.com/nicojiong/Life/blob/2d035379f21abbc8d1d6f06d0328eb756751b993/scripts/main.gd#L318-L344)。测试必须使用隔离的用户数据目录或独立测试项目配置，并验证隔离生效，不能对真实玩家目录直接运行 `--fresh`。

首次运行应先确认：远程是否新增提交；现有 AGENTS/README 的有效规则；实际 Godot 版本；用户数据位置与备份；内容文件完整性；启动/解析结果；已有 debug 的副作用。记录真实命令、退出码、日志和 commit，未知结论继续标记待验证。

## 6. 优先修复出口与最小闭环

第一阶段出口：修正文档与标识问题；统一行动/时间/死亡边界；完整保存人物、关系、事件和 RNG；通过 R01–R12 中与已迁移功能对应的断言。不得用增加剧情数量替代这些条件。

随机数需要分流：出生、世界事件、人物决策分别持有可保存的模拟状态，画面游走与粒子使用独立随机源。这样调整绘制帧数或新增一段装饰动画，不会消耗决定下一次人生事件的随机序列。重放验收同时固定内容版本与规则版本，避免把版本变化误判为存档损坏。

第二阶段出口：在原村庄保留可玩界面，抽出 WorldState、Actor、Household、Clock、ActionService、EventScheduler、SaveService；采用逐条迁移和适配层，不一次重写所有表现代码。

第三阶段先证明一条长期因果：随机家庭出生 → 父母决策 → 儿童形成经验 → 选择读书/学艺/帮工 → 真实借款及到期 → NPC 依据记忆提供或拒绝担保 → 成年路径改变 → 老年记录可追溯原因。链条允许拒绝、失败、人物死亡和读档恢复。打通后再批量扩人物剧本、地图和第二时代。

后续规划引用本审计时，请使用 A01–A10 和 R01–R12 编号；新基线改变了结论时追加证据与状态，不静默把“待验证”改成“已修复”。
