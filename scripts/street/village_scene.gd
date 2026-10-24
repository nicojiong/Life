extends Control
## 平铺村庄（大图版）：俯视 3/4 视角，镜头跟随，A* 寻路。
## 点地面走过去，点屋顶走到门口进屋做事。

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const CutsceneScript := preload("res://scripts/street/cutscene.gd")

const W := 1280.0
const H := 800.0
const WORLD_W := 3200.0
const WORLD_H := 1900.0
const CELL := 40.0
const RIVER_Y := 1530.0
const HOURS_PER_SEC := 0.03     # 一天约 13 分钟，一个时辰约 66 秒
## 真实节奏：一年 = 7 天现实时间（一年 604800 秒，一个月 50400 秒）
const SECONDS_PER_YEAR := 604800.0
## 流速档位：1× 真实节奏 / 60× / 600× / 3600×
const TIME_SCALES := [1.0, 60.0, 600.0, 3600.0]
var time_scale := 1.0
const MM_W := 236.0
const MM_H := 140.0
const MM_MARGIN := 24.0

const C_GRASS := Color(0.808, 0.792, 0.671)
const C_PATH := Color(0.788, 0.722, 0.576)
const C_WATER := Color(0.502, 0.616, 0.624)
const C_BODY := Color(0.271, 0.224, 0.180)
const C_ROOF := Color(0.165, 0.137, 0.110)
const C_ROOF2 := Color(0.216, 0.180, 0.145)
const C_DOOR := Color(0.416, 0.278, 0.169)
const C_WIN := Color(0.929, 0.678, 0.353)
const C_LANTERN := Color(0.741, 0.259, 0.176)
const C_INK := Color(0.145, 0.118, 0.094)
const C_SIL := Color(0.125, 0.098, 0.078)
const C_PAPER := Color(0.965, 0.937, 0.878)

var name_text := ""
var place := "苏州吴县"
var year := 1044
var month := 3
var age := 6
var money := 4000
var learning := 4.0
var craft := 4.0
var fame := 1.0
var health := 72.0
var lifespan := 70

var shop_open := false
var shop_label := ""
var shop_level := 1
var shop := {"kind": "", "stock": 0, "price": 1, "helper": false, "market": 1.0, "rival": 1}

var buildings: Array = []
var props: Array = []
var npcs: Array = []

var player := Vector2(1250.0, 900.0)
var cam := Vector2(610.0, 500.0)
var path: Array = []
var path_i := 0
var facing := 1.0
var moving := false
var walk_phase := 0.0
var pending_building := ""
var pending_npc := ""
var hover_npc := ""
var dragging := false
var drag_from := Vector2.ZERO
var drag_cam := Vector2.ZERO
var story := {}
var origin_flags: Array = []
var craft_rank := 0
var apprentice_hired := 0
var workshop_open := false
var trade_rank := 0
var guild_open := false
var medicine := 0.0
var med_rank := 0
var med_book := false
var land := 0
var farm_rank := 0
var mil_rank := 0
var merit := 0
var death_cause := ""
var slot := 1
var birth_year := 1044
var father_name := ""
var mother_name := ""
var skip_intro := false
var office_rank := 0
var gov_merit := 0
var scandal := 0
var county := ""
var father_trade := "农"
var mother_temper := "和"
var child_last := ""
var can_walk := true
var pov := "child"
var pov_state := {}
var child_pos := Vector2(330, 620)
var pov_btns: Array = []
var speed_btn: Button = null
var women_rank := 0
var month_frac := 0.0

## 存档格式版本：字段增删时递增，读档据此做迁移
const SAVE_SCHEMA_VERSION := 6
var save_schema_seen := 0
## A03：父母是否已故（保留人物记录，不用删除表示死亡）
var parent_dead := {"father": false, "mother": false}
var parent_death_year := {"father": 0, "mother": 0}
var recovered_from_backup := false
## M1-02：每个行动的世界时间冷却（键 = 行动标签，值 = 可再次执行的月份序号）
var action_cooldown := {}
## M1-02b：年关结算水位，保证一年只结算一次
var last_settled_year := 0

## M1-03：模拟专用随机流（与画面/游走的随机分开），可存可复现
var sim_rng := RandomNumberGenerator.new()
var sim_seed := 0


func _init_sim_rng(s: int) -> void:
	sim_seed = s
	sim_rng.seed = s


func _rnd() -> float:
	return sim_rng.randf()


func _rndi(a: int, b: int) -> int:
	return sim_rng.randi_range(a, b)


func _rndf(a: float, b: float) -> float:
	return sim_rng.randf_range(a, b)


## M1-03b：事实日志。每条记"什么时候、什么类型、由什么引起"，供墓志与调试追溯
var facts: Array = []
const FACT_CAP := 240
## M1-01a：人物关系（id → attitude），由世界持有，不随场景重建消失
var relations: Dictionary = {}
## 测试时关掉年度随机事件，避免随机扣血/扣钱干扰断言
var events_enabled := true


func _log_fact(kind: String, cause: String, data: Dictionary = {}) -> void:
	facts.append({"t": _month_index(), "kind": kind, "cause": cause, "data": data})
	if facts.size() > FACT_CAP:
		facts = facts.slice(facts.size() - FACT_CAP)

var _re_time := RegEx.new()

## 切换视角时要保存/恢复的字段（钱是全家共用的，不在其中）
const POV_FIELDS := [
	"age", "health", "learning", "craft", "fame", "lifespan",
	"craft_rank", "trade_rank", "med_rank", "farm_rank", "mil_rank",
	"office_rank", "gov_merit", "scandal", "county",
	"land", "workshop_open", "guild_open", "apprentice_hired", "med_book",
	"medicine", "merit", "can_walk", "women_rank",
]

## 四种体格：高壮 / 中等 / 矮胖 / 瘦高
const BUILDS := [
	{"h": 34.5, "sh": 17.5, "gw": 11.5, "leg": 12.5, "hr": 6.9},
	{"h": 31.0, "sh": 15.0, "gw": 9.5, "leg": 11.5, "hr": 6.5},
	{"h": 28.5, "sh": 15.5, "gw": 12.5, "leg": 10.0, "hr": 6.7},
	{"h": 33.5, "sh": 13.0, "gw": 8.0, "leg": 12.5, "hr": 6.2},
]
var player_build: Dictionary = BUILDS[1]
var married := false
var spouse_name := ""
var children := 0
var parents_alive := 2
var busy := false
var hover_id := ""
var toasts: Array = []
var t := 0.0
var hour := 8.0
var step_sound_t := 0.0
var milestones := {}
var ended := false

const SAVE_DIR := "user://"

## 随机事件池：每年 32% 概率触发一条，按年龄与身份筛选
const EVENTS := [
	{"id": "drought", "min_age": 8},
	{"id": "flood", "min_age": 8},
	{"id": "levy", "min_age": 12},
	{"id": "thieves", "min_age": 12},
	{"id": "plague", "min_age": 10},
	{"id": "suit", "min_age": 16},
	{"id": "wedding", "min_age": 10},
	{"id": "harvest", "min_age": 16, "cond": "farm"},
	{"id": "reward", "min_age": 20, "cond": "famous"},
	{"id": "school", "min_age": 25, "cond": "parent"},
	{"id": "rash", "min_age": 1, "max_age": 6},
	{"id": "riverfall", "min_age": 2, "max_age": 7},
	{"id": "find_coin", "min_age": 3, "max_age": 8},
	{"id": "quarrel", "min_age": 3, "max_age": 9},
]

## 各地点允许去的最小年龄；太小的时候只能在家
## 0-6 岁：不由玩家选，由父母带着过。每年抽一条。
const CHILD_EVENTS := [
	{"id": "market_trip", "min_age": 2},
	{"id": "lullaby", "min_age": 1},
	{"id": "needle", "min_age": 3, "mother": "和"},
	{"id": "scold", "min_age": 2, "mother": "严"},
	{"id": "sick_mother", "min_age": 2, "mother": "病"},
	{"id": "pawn_ring", "min_age": 2, "cond": "poor"},
	{"id": "drunk_cry", "min_age": 4, "father": "农"},
	{"id": "wood", "min_age": 3, "father": "匠"},
	{"id": "abacus", "min_age": 4, "father": "商"},
	{"id": "drill_play", "min_age": 4, "father": "兵"},
	{"id": "letters", "min_age": 4, "father": "吏"},
	{"id": "fever", "min_age": 1},
	{"id": "bully", "min_age": 4},
	{"id": "grandma", "min_age": 3},
]

## 一年里的节令：到月就出现，过了它时间往下跳一段
const YEAR_SCENES := [
	{"m": 1, "id": "yuandan", "name": "元日"},
	{"m": 3, "id": "qingming", "name": "清明"},
	{"m": 5, "id": "duanwu", "name": "端午"},
	{"m": 7, "id": "zhongyuan", "name": "中元"},
	{"m": 8, "id": "zhongqiu", "name": "中秋"},
	{"m": 11, "id": "dongzhi", "name": "冬至"},
]
var scenes_done := {}

## 每个节令的选项：不是确认框，是一次小选择
const SCENE_OPTS := {
	"yuandan": [
		{"id": "visit", "label": "挨家去拜年", "gain": {"fame": 3},
			"text": "你从东头走到西头，磕了十几个头，兜里塞满了炒豆。"},
		{"id": "fire", "label": "守着家里的火盆", "gain": {"health": 2},
			"text": "一家人围着火盆坐到半夜，谁也没说话，炭噼啪响。",
			"poor": "火盆里的炭是去年剩下的，一家人围得比往年更近。"},
		{"id": "street", "label": "上街看放炮", "gain": {"fame": 1, "health": 1},
			"text": "爆竹炸得震耳朵，孩子们满地捡没响的。"},
	],
	"qingming": [
		{"id": "grave", "label": "去坟上添土", "gain": {"fame": 3},
			"text": "你把新土一捧一捧添上去，压了三张纸。"},
		{"id": "walk", "label": "带家里人踏青", "gain": {"health": 2, "fame": 1},
			"text": "河边柳条刚绿，孩子在草地上跑得满脸是土。"},
		{"id": "copy", "label": "在家抄一天经", "gain": {"learning": 2},
			"text": "抄到「慎终追远」，笔尖停了一会儿。"},
	],
	"duanwu": [
		{"id": "boat", "label": "去看赛舟", "gain": {"fame": 2, "health": 1},
			"text": "两船撞在一起，落水的人爬上来还在笑。"},
		{"id": "zongzi", "label": "在家包粽子", "gain": {"health": 2},
			"text": "母亲包的个儿大，你包的全漏了米。",
			"poor": "家里没有糯米，母亲用豆子包了几个，说也是一样的。"},
		{"id": "give", "label": "给邻家送一串", "gain": {"fame": 3},
			"text": "邻家回了一把艾草，说驱邪。"},
	],
	"zhongyuan": [
		{"id": "burn", "label": "在路口烧纸", "gain": {"fame": 2},
			"text": "风把纸灰吹得很高，你仰头看了很久。"},
		{"id": "temple", "label": "去庙里听经", "gain": {"learning": 1, "fame": 1},
			"text": "老僧念到半夜，你打了两个盹。"},
		{"id": "sleep", "label": "早早关门睡了", "gain": {"health": 1},
			"text": "这一夜你睡得沉，什么也没梦见。"},
	],
	"zhongqiu": [
		{"id": "moon", "label": "在院里赏月", "gain": {"health": 1, "fame": 1},
			"text": "月饼切四份，一人一块。月亮很圆，云跑得很快。",
			"poor": "没有月饼。母亲把一块糖敲成四份，一人一点。"},
		{"id": "wine", "label": "去邻家喝酒", "gain": {"fame": 2, "health": -1},
			"text": "喝到后半夜，说了许多不该说的话。"},
		{"id": "alone", "label": "一个人坐一会儿", "gain": {"health": 1},
			"text": "你想起一些不在场的人，没跟谁说。"},
	],
	"dongzhi": [
		{"id": "pot", "label": "一家人吃锅子", "gain": {"health": 2},
			"text": "锅里冒白气，窗上的纸被熏得发黄。"},
		{"id": "shrine", "label": "去祠堂祭祖", "gain": {"fame": 3},
			"text": "族里的老人念了名单，念到你父亲时停了停。"},
		{"id": "poor", "label": "给穷人送一碗", "cost": 200, "gain": {"fame": 4},
			"text": "那人接了碗，手抖了一下，没抬头。"},
	],
}

const SCENE_FLAVOR := {
	"yuandan": "爆竹从天没亮响到日头出来。",
	"qingming": "柳条刚绿，坟头的草还没长起来。",
	"duanwu": "门口插了艾，河上有鼓声。",
	"zhongyuan": "街口有人在烧纸，风一阵一阵。",
	"zhongqiu": "月亮升得早，院里凉了。",
	"dongzhi": "开始落雪了，屋檐下挂着冰棱。",
}

const MIN_AGE := {
	"home": 0, "field": 6, "school": 6, "market": 8, "academy": 12, "temple": 6,
	"yamen": 14, "teahouse": 10, "pharmacy": 8, "shrine": 6, "smithy": 8,
	"tavern": 12, "pawnshop": 12, "washe": 8, "mulberry": 6, "dye": 10,
	"inn": 10, "drill": 16, "dock": 10, "lot": 16, "shop": 0,
	"grave": 6, "garden": 6, "thresh": 8,
}

var grid_w := 0
var grid_h := 0
var blocked := PackedByteArray()

var panel: PanelContainer
var panel_title: Label
var panel_sub: Label
var panel_actions: VBoxContainer
var panel_hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 模拟随机流先于身份生成初始化：同种子得到同一份出身与一生
	var boot := int(Time.get_ticks_usec()) ^ randi()
	_init_sim_rng(boot)
	_init_identity()
	var resumed := _load_game()
	_rebuild()
	_build_panel()
	_build_pov_bar()
	Sfx.volume_changed.connect(_on_volume_changed)
	cam = (player - Vector2(W * 0.5, H * 0.5)).clamp(Vector2.ZERO, Vector2(WORLD_W - W, WORLD_H - H))
	set_process(true)
	queue_redraw()
	if resumed:
		_toast("接着上次活：%s，%s岁。" % [DB.era_label(year), DB.cn(age)], Color(0.30, 0.26, 0.21))
		if shop_open:
			_toast("铺子还在，存货 %d。" % int(shop.get("stock", 0)), Color(0.48, 0.32, 0.16))
	else:
		_toast("右键拖动画面，点地就走，点屋进屋，点人有话说。", Color(0.30, 0.26, 0.21))
		if not skip_intro:
			_play_cutscene("生", [
				"%s，你生在%s。" % [DB.era_label(year), place],
				"父亲%s，是个%s的。母亲%s，性子%s。" % [
					father_name, _father_trade_word(), mother_name, mother_temper],
				"有人在说话，你听不懂，只觉得声音很近。",
			], false)


# ---------------------------------------------------------------- 存档

func _state_dict() -> Dictionary:
	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"name": name_text, "place": place, "year": year, "month": month, "age": age,
		"money": money, "learning": learning, "craft": craft, "fame": fame,
		"health": health, "lifespan": lifespan,
		"shop_open": shop_open, "shop_label": shop_label, "shop_level": shop_level,
		"shop": shop, "story": story, "married": married, "spouse": spouse_name,
		"children": children, "parents_alive": parents_alive,
		"craft_rank": craft_rank, "apprentice_hired": apprentice_hired,
		"workshop_open": workshop_open, "origin_flags": origin_flags,
		"trade_rank": trade_rank, "guild_open": guild_open,
		"medicine": medicine, "med_rank": med_rank, "med_book": med_book,
		"land": land, "farm_rank": farm_rank,
		"mil_rank": mil_rank, "merit": merit, "death_cause": death_cause,
		"pov": pov, "pov_state": pov_state, "child_pos_x": child_pos.x, "child_pos_y": child_pos.y,
		"can_walk": can_walk,
		"office_rank": office_rank, "gov_merit": gov_merit, "scandal": scandal, "county": county,
		"milestones": milestones,
		# A02：此前遗漏、读档后会被重新随机或重置的状态
		"father_trade": father_trade, "mother_temper": mother_temper,
		"women_rank": women_rank, "scenes_done": scenes_done, "child_last": child_last,
		"time_scale": time_scale, "slot": slot,
		"parent_dead": parent_dead, "parent_death_year": parent_death_year,
		"action_cooldown": action_cooldown, "last_settled_year": last_settled_year,
		"facts": facts, "relations": relations,
		# RNG 的 64 位 seed/state 用十进制字符串，避免 JSON 精度丢失
		"sim_seed": str(sim_seed), "sim_state": str(sim_rng.state),
		"px": player.x, "py": player.y, "hour": hour,
		"birth_year": birth_year, "father_name": father_name, "mother_name": mother_name,
	}


func _save_file() -> String:
	return "user://fusheng_save_%d.json" % slot


func _save_game() -> void:
	# A01：人生已经结束后不再写普通存档，否则会覆盖死亡时清掉的档
	if ended:
		print("[SAVE] refused_after_end")
		return
	# 原子写入：先写 .tmp → 旧的挪成 .bak → .tmp 顶上去；中途断电最多丢一次写入
	var main := _save_file()
	var tmp := main + ".tmp"
	var bak := main + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		print("[SAVE] open_tmp_failed ", tmp)
		return
	f.store_string(JSON.stringify(_state_dict()))
	f.close()
	var abs_main := ProjectSettings.globalize_path(main)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_bak := ProjectSettings.globalize_path(bak)
	if FileAccess.file_exists(main):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(abs_bak)
		DirAccess.rename_absolute(abs_main, abs_bak)
	var err := DirAccess.rename_absolute(abs_tmp, abs_main)
	if err != OK:
		print("[SAVE] promote_failed err=", err)


func _read_save_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	# 用 JSON 实例解析：损坏时返回错误码而不是往 stderr 打引擎 ERROR
	var j := JSON.new()
	if j.parse(txt) != OK:
		print("[SAVE] corrupt_or_unreadable ", path, " err=", j.get_error_message())
		return {}
	if j.data is Dictionary:
		return j.data
	return {}


func _load_game() -> bool:
	recovered_from_backup = false
	var d := _read_save_dict(_save_file())
	if d.is_empty():
		d = _read_save_dict(_save_file() + ".bak")
		if not d.is_empty():
			recovered_from_backup = true
			print("[SAVE] recovered_from_backup")
	if d.is_empty():
		return false
	name_text = str(d.get("name", name_text))
	place = str(d.get("place", place))
	year = int(d.get("year", year))
	month = int(d.get("month", month))
	age = int(d.get("age", age))
	money = int(d.get("money", money))
	learning = float(d.get("learning", learning))
	craft = float(d.get("craft", craft))
	fame = float(d.get("fame", fame))
	health = float(d.get("health", health))
	lifespan = int(d.get("lifespan", lifespan))
	shop_open = bool(d.get("shop_open", false))
	shop_label = str(d.get("shop_label", shop_label))
	shop_level = int(d.get("shop_level", shop_level))
	if d.get("shop") is Dictionary:
		shop = d["shop"]
	if d.get("story") is Dictionary:
		story = d["story"]
	married = bool(d.get("married", false))
	spouse_name = str(d.get("spouse", spouse_name))
	children = int(d.get("children", children))
	parents_alive = int(d.get("parents_alive", parents_alive))
	craft_rank = int(d.get("craft_rank", craft_rank))
	apprentice_hired = int(d.get("apprentice_hired", apprentice_hired))
	workshop_open = bool(d.get("workshop_open", workshop_open))
	trade_rank = int(d.get("trade_rank", trade_rank))
	guild_open = bool(d.get("guild_open", guild_open))
	medicine = float(d.get("medicine", medicine))
	med_rank = int(d.get("med_rank", med_rank))
	med_book = bool(d.get("med_book", med_book))
	land = int(d.get("land", land))
	farm_rank = int(d.get("farm_rank", farm_rank))
	mil_rank = int(d.get("mil_rank", mil_rank))
	merit = int(d.get("merit", merit))
	death_cause = str(d.get("death_cause", death_cause))
	can_walk = bool(d.get("can_walk", can_walk))
	pov = str(d.get("pov", pov))
	child_pos = Vector2(float(d.get("child_pos_x", child_pos.x)), float(d.get("child_pos_y", child_pos.y)))
	if d.get("pov_state") is Dictionary:
		var ps: Dictionary = d["pov_state"]
		pov_state = {}
		for k in ps.keys():
			if ps[k] is Dictionary:
				pov_state[str(k)] = ps[k]
	# 老存档（schema < 2）没有父母数据时补上，不然门口会少两个人；
	# 新存档不补：缺人物只可能意味着已故，按死亡记录处理，不能复活。
	if int(d.get("schema_version", 1)) < 2:
		var rr := RandomNumberGenerator.new()
		rr.randomize()
		if not pov_state.has("father"):
			pov_state["father"] = _make_parent("father", rr)
		if not pov_state.has("mother"):
			pov_state["mother"] = _make_parent("mother", rr)
	office_rank = int(d.get("office_rank", office_rank))
	gov_merit = int(d.get("gov_merit", gov_merit))
	scandal = int(d.get("scandal", scandal))
	county = str(d.get("county", county))
	if d.get("origin_flags") is Array:
		origin_flags = d["origin_flags"]
	if d.get("milestones") is Dictionary:
		milestones = d["milestones"]
	player = Vector2(float(d.get("px", player.x)), float(d.get("py", player.y)))
	hour = float(d.get("hour", hour))
	birth_year = int(d.get("birth_year", birth_year))
	father_name = str(d.get("father_name", father_name))
	mother_name = str(d.get("mother_name", mother_name))
	# A02：这些字段以前不存，读档后会变回新随机值或被重置
	# 旧档没有 father_trade 时按 origin_flags 推导，而不是沿用内存里的随机值
	if d.has("father_trade"):
		father_trade = str(d["father_trade"])
	else:
		father_trade = _father_trade_for(origin_flags)
	mother_temper = str(d.get("mother_temper", "和"))
	women_rank = int(d.get("women_rank", women_rank))
	if d.get("scenes_done") is Dictionary:
		scenes_done = d["scenes_done"]
	child_last = str(d.get("child_last", child_last))
	time_scale = float(d.get("time_scale", time_scale))
	if d.get("parent_dead") is Dictionary:
		var pd: Dictionary = d["parent_dead"]
		for k in pd.keys():
			parent_dead[str(k)] = bool(pd[k])
	if d.get("parent_death_year") is Dictionary:
		var py: Dictionary = d["parent_death_year"]
		for k in py.keys():
			parent_death_year[str(k)] = int(py[k])
	if d.get("action_cooldown") is Dictionary:
		action_cooldown = d["action_cooldown"]
	last_settled_year = int(d.get("last_settled_year", last_settled_year))
	if d.get("facts") is Array:
		facts = d["facts"]
	if d.get("relations") is Dictionary:
		relations = d["relations"]
	if d.has("sim_seed") and d.has("sim_state"):
		sim_seed = int(str(d["sim_seed"]))
		sim_rng.seed = sim_seed
		sim_rng.state = int(str(d["sim_state"]))
	save_schema_seen = int(d.get("schema_version", 1))
	return true


func debug_save() -> void:
	money = 43210
	age = 37
	story["debug"] = true
	_save_game()
	print("[SAVE] 写入 money=", money, " age=", age, " name=", name_text)


func debug_load() -> void:
	print("[SAVE] 读回 money=", money, " age=", age, " name=", name_text, " story=", story)


func debug_years(n: int) -> void:
	var work := {"label": "做工", "months": 6, "cost": 0, "gain": {"money": 1500}}
	for i in range(n):
		# 模拟“活着就得干活”：一年两份工
		_on_action(work)
		_on_action(work)
		if not alive_check():
			break
	print("[YEARS] age=", age, " money=", money, " married=", married,
		" children=", children, " parents=", parents_alive, " story=", story)


func alive_check() -> bool:
	return age < lifespan and health > 0.0


func debug_corners() -> void:
	busy = false
	for id in ["grave", "garden", "thresh"]:
		var b := _by_id(id)
		print("[CORNER] ", id, " 存在=", not b.is_empty(),
			" 动作=", _actions_for(id).size(), " 最小年龄=", MIN_AGE.get(id, 0))
	print("[CORNER] 地点总数=", buildings.size())
	print("[CORNER] 坟地祭父母出现=", _has_parent_grave_option())
	parents_alive = 0
	print("[CORNER] 父母故后 祭父母出现=", _has_parent_grave_option())


func _has_parent_grave_option() -> bool:
	for a in _actions_for("grave"):
		if str(a.get("label", "")).begins_with("祭父母"):
			return true
	return false


func debug_child2() -> void:
	busy = false
	age = 4
	print("[KID] 玩伴=", _find_npc("a_he").get("name", "?"), "/", _find_npc("shi_tou").get("name", "?"))
	print("[KID] 阿禾台词=", _dialog_line(_find_npc("a_he")))
	print("[KID] 阿禾选项=", _dialog_choices("a_he").size(), " 石头选项=", _dialog_choices("shi_tou").size())
	var seen := {}
	for i in range(400):
		for e in EVENTS:
			if _event_ok(e):
				seen[str(e["id"])] = true
	print("[KID] 四岁可达事件=", seen.size(), " ", seen.keys())
	_apply_event("riverfall")
	print("[KID] 落水后 body=", health, " 标记=", story.has("落水"))
	age = 20
	print("[KID] 二十岁阿禾台词=", _dialog_line(_find_npc("a_he")), " 选项=", _dialog_choices("a_he").size())


func debug_switch() -> void:
	busy = false
	money = 20000
	# 匠人改学医
	craft = 45.0
	craft_rank = 2
	_apply_special("med_apprentice")
	print("[SW] 匠人转医 → 匠=", craft_rank, " 医=", med_rank, " 医术=", medicine, "（含懂火候 +6）")
	# 商人改从军
	trade_rank = 2
	_apply_special("enlist")
	print("[SW] 商人从军 → 商=", trade_rank, " 军=", mil_rank)
	# 军官转官场
	story["进士"] = true
	mil_rank = 2
	_apply_special("take_post")
	print("[SW] 军官赴任 → 官=", _office_name(), " 政绩=", gov_merit, "（军功 +2）")
	# 摆摊真的能进行商
	trade_rank = 0
	_apply_special("stall")
	print("[SW] 摆摊之后 → 商=", trade_rank, " 行商可跑商=", trade_rank >= 1)


func debug_office() -> void:
	busy = false
	story["进士"] = true
	money = 20000
	fame = 40.0
	print("[GOV] 初始 官=", _office_name(), " 衙门选项=", _actions_for("yamen").size())
	_apply_special("take_post")
	print("[GOV] 赴任 官=", _office_name(), " 任所=", county, " 俸=", _salary())
	for i in range(4):
		_apply_special("judge_fair")
	print("[GOV] 四次断案 政绩=", gov_merit, " 声望=", fame)
	_apply_special("promote")
	print("[GOV] 升迁 官=", _office_name(), " 俸=", _salary())
	for i in range(8):
		_apply_special("judge_fair")
	print("[GOV] 八案后 政绩=", gov_merit, " 需要=", _promote_need())
	_apply_special("promote")
	print("[GOV] 再升 官=", _office_name(), " 俸=", _salary(), " 墓志=", _tier_name())
	for i in range(3):
		_apply_special("judge_bribe")
	print("[GOV] 三次受贿 贪名=", scandal, " 钱=", money)
	scandal = 3
	_on_new_year()
	print("[GOV] 被劾后 官=", _office_name(), " 贬谪次数=", story.get("贬谪", 0), " 墓志=", _tier_name())


func _child_event_ok(ev: Dictionary) -> bool:
	if age < int(ev.get("min_age", 0)):
		return false
	if ev.has("father") and str(ev["father"]) != father_trade:
		return false
	if ev.has("mother") and str(ev["mother"]) != mother_temper:
		return false
	if str(ev.get("cond", "")) == "poor":
		return money < 600
	return true


func _child_year() -> void:
	var pool: Array = []
	for e in CHILD_EVENTS:
		if _child_event_ok(e) and str(e["id"]) != child_last:
			pool.append(e)
	if pool.is_empty():
		for e in CHILD_EVENTS:
			if _child_event_ok(e):
				pool.append(e)
	if pool.is_empty():
		return
	var ev: Dictionary = pool[randi() % pool.size()]
	child_last = str(ev["id"])
	_apply_child_event(child_last)


func _apply_child_event(id: String) -> void:
	var warm := Color(0.30, 0.42, 0.22)
	var cold := Color(0.62, 0.24, 0.18)
	match id:
		"market_trip":
			learning = minf(100.0, learning + 1.0)
			fame = minf(100.0, fame + 1.0)
			_toast("父亲把你架在脖子上赶集。你看见那么多人的头，一直看到睡着。", warm)
		"lullaby":
			health = minf(100.0, health + 1.0)
			_toast("夜里睡不着，母亲哼了一支不成调的歌。你听着听着就沉下去了。", warm)
		"needle":
			craft = minf(100.0, craft + 1.0)
			_toast("母亲握着你的手教针脚，你扎了三回，她没松开。", warm)
		"scold":
			fame = minf(100.0, fame + 1.0)
			health = maxf(0.0, health - 1.0)
			_toast("你打碎了碗。母亲罚你跪了半个时辰，跪完又给你留了饭。", cold)
		"sick_mother":
			money = maxi(0, money - 200)
			health = maxf(0.0, health - 1.0)
			_toast("母亲病了半年，咳得厉害。你自己学会了自己穿衣裳。", cold)
		"pawn_ring":
			money += 800
			story["当镯"] = true
			_toast("家里揭不开锅。母亲把陪嫁的银镯子当了，回来时手是空的。", cold)
		"drunk_cry":
			fame = minf(100.0, fame + 1.0)
			_toast("父亲喝多了，抱着你哭，反复说他对不起这个家。你不知该怎么应。", cold)
		"wood":
			craft = minf(100.0, craft + 2.0)
			_toast("父亲把一块边角料塞给你，教你削一把木剑。削了三天，像根柴。", warm)
		"abacus":
			learning = minf(100.0, learning + 2.0)
			_toast("父亲抱你上柜台，教你拨算盘珠子。你只会听响。", warm)
		"drill_play":
			health = minf(100.0, health + 2.0)
			_toast("父亲教你扎马步，你站不到十个数就倒了，他在旁边笑。", warm)
		"letters":
			learning = minf(100.0, learning + 3.0)
			_toast("父亲在灯下写字，握着你的手描了一个「人」字。那是你认得的第一字。", warm)
		"fever":
			health = maxf(0.0, health - 2.0)
			story["病过"] = true
			_toast("你发高热，母亲用凉水给你擦了一夜。天亮时她眼里全是血丝。", cold)
		"bully":
			fame = maxf(0.0, fame - 1.0)
			_toast("邻家孩子抢了你的东西，你哭着回家。父亲说：下回自己抢回来。", cold)
		"grandma":
			health = minf(100.0, health + 1.0)
			money += 100
			_toast("外婆来了，带一包糖。她走的时候你抱着她的腿不放。", warm)


func debug_festival_memory() -> void:
	busy = false
	age = 7
	money = 80
	_pick_scene_option("zhongqiu", "moon")
	print("[FEST] 童年穷困 标记=", story.keys())
	age = 30
	money = 5000
	_pick_scene_option("dongzhi", "poor")
	print("[FEST] 冬至施粥 标记=", story.keys())
	var ep := _epitaph()
	for l in ep:
		print("[FEST] 墓志> ", l)


func debug_scene_panel() -> void:
	busy = false
	age = 20
	month = 8
	scenes_done.clear()
	player = Vector2(330, 620)
	cam = (player - Vector2(W * 0.5, H * 0.5)).clamp(Vector2.ZERO, Vector2(WORLD_W - W, WORLD_H - H))
	var sc := _due_scene()
	print("[SCENE] 弹出节令=", sc.get("name", "无"), " 选项数=", SCENE_OPTS.get(str(sc.get("id", "")), []).size())
	_do_scene(sc)
	# 模拟玩家点了第一项
	var opts: Array = SCENE_OPTS.get(str(sc.get("id", "")), [])
	if not opts.is_empty():
		_on_action({"label": "", "months": 0,
			"special": "scene_pick:%s:%s" % [str(sc["id"]), str((opts[0] as Dictionary)["id"])]})
	print("[SCENE] 选完 月=", month, " 已过=", scenes_done.size(), " 忙=", busy)
	var nxt := _due_scene()
	print("[SCENE] 下个节令=", nxt.get("name", "无"))


func _run_verify_smoke() -> void:
	# 行为断言入口：失败必须以非零退出码结束，供 tools/verify.ps1 判定
	busy = false
	var fails: Array = []
	var oks := 0

	if OS.get_user_data_dir().find("LifeVerify") >= 0:
		oks += 1
		print("[VERIFY] PASS isolated_user_dir ", OS.get_user_data_dir())
	else:
		fails.append("isolated_user_dir")
		print("[VERIFY] FAIL isolated_user_dir ", OS.get_user_data_dir())

	if DB.origins.size() == 10:
		oks += 1
		print("[VERIFY] PASS origins_count 10")
	else:
		fails.append("origins_count")
		print("[VERIFY] FAIL origins_count ", DB.origins.size())

	if age == 0 and not can_walk:
		oks += 1
		print("[VERIFY] PASS newborn_state age=0 can_walk=false")
	else:
		fails.append("newborn_state")
		print("[VERIFY] FAIL newborn_state age=", age, " can_walk=", can_walk)

	var money_before := money
	money = 12345
	_save_game()
	money = 1
	var loaded := _load_game()
	if loaded and money == 12345:
		oks += 1
		print("[VERIFY] PASS save_roundtrip money=12345")
	else:
		fails.append("save_roundtrip")
		print("[VERIFY] FAIL save_roundtrip loaded=", loaded, " money=", money)
	money = money_before

	if pov_state.has("father") and pov_state.has("mother"):
		oks += 1
		print("[VERIFY] PASS parents_present")
	else:
		fails.append("parents_present")
		print("[VERIFY] FAIL parents_present ", pov_state.keys())

	# A09：出身 flag → 父亲行当 的接线
	if _father_trade_for(["商贾"]) == "商" and _father_trade_for(["匠人"]) == "匠" \
			and _father_trade_for(["军户"]) == "兵" and _father_trade_for(["士人"]) == "吏" \
			and _father_trade_for(["农家"]) == "农":
		oks += 1
		print("[VERIFY] PASS father_trade_mapping")
	else:
		fails.append("father_trade_mapping")
		print("[VERIFY] FAIL father_trade_mapping")

	# A09：数据里真实存在「商贾」出身，且能被映射成商人
	var merchant_found := false
	var merchant_ok := false
	for o in DB.origins:
		var of: Array = o.get("flags", [])
		if of.has("商贾"):
			merchant_found = true
			merchant_ok = _father_trade_for(of) == "商"
	if merchant_found and merchant_ok:
		oks += 1
		print("[VERIFY] PASS merchant_origin_wired")
	else:
		fails.append("merchant_origin_wired")
		print("[VERIFY] FAIL merchant_origin_wired found=", merchant_found, " ok=", merchant_ok)

	# 内容 ID 唯一：NPC 不允许重复 id
	var seen_ids := {}
	var dup_id := ""
	for n in npcs:
		var nid := str(n.get("id", ""))
		if nid == "":
			continue
		if seen_ids.has(nid):
			dup_id = nid
		seen_ids[nid] = true
	if dup_id == "":
		oks += 1
		print("[VERIFY] PASS npc_ids_unique count=", seen_ids.size())
	else:
		fails.append("npc_ids_unique")
		print("[VERIFY] FAIL npc_ids_unique duplicate=", dup_id)

	# A02：完整存档往返（父亲行当/母亲性情/妇业/节令/流速/童年去重）
	var keep := {
		"ft": father_trade, "mt": mother_temper, "wr": women_rank,
		"cl": child_last, "ts": time_scale,
		"sd": (scenes_done as Dictionary).duplicate(true),
	}
	father_trade = "匠"
	mother_temper = "严"
	women_rank = 3
	child_last = "wood"
	time_scale = 600.0
	scenes_done = {"1046_qingming": true}
	_save_game()
	father_trade = "农"
	mother_temper = "和"
	women_rank = 0
	child_last = ""
	time_scale = 1.0
	scenes_done = {}
	save_schema_seen = 0
	var ok_full := _load_game()
	if ok_full and father_trade == "匠" and mother_temper == "严" and women_rank == 3 \
			and child_last == "wood" and is_equal_approx(time_scale, 600.0) \
			and scenes_done.has("1046_qingming") and save_schema_seen == SAVE_SCHEMA_VERSION:
		oks += 1
		print("[VERIFY] PASS save_roundtrip_full schema=", save_schema_seen)
	else:
		fails.append("save_roundtrip_full")
		print("[VERIFY] FAIL save_roundtrip_full ", father_trade, "/", mother_temper, "/",
			women_rank, "/", child_last, "/", time_scale, "/", scenes_done, "/", save_schema_seen)
	father_trade = str(keep["ft"])
	mother_temper = str(keep["mt"])
	women_rank = int(keep["wr"])
	child_last = str(keep["cl"])
	time_scale = float(keep["ts"])
	scenes_done = (keep["sd"] as Dictionary).duplicate(true)

	# A03：已故父母不能因为读档被复活
	parent_dead["father"] = true
	parent_death_year["father"] = 1050
	_save_game()
	parent_dead["father"] = false
	parent_death_year["father"] = 0
	var ok_dead := _load_game()
	var pov_before := pov
	_switch_pov("father")
	if ok_dead and bool(parent_dead["father"]) and int(parent_death_year["father"]) == 1050 \
			and pov == "child" and pov_state.has("father"):
		oks += 1
		print("[VERIFY] PASS dead_parent_stays_dead")
	else:
		fails.append("dead_parent_stays_dead")
		print("[VERIFY] FAIL dead_parent_stays_dead ok=", ok_dead, " dead=", parent_dead,
			" pov=", pov, " has=", pov_state.has("father"))
	parent_dead["father"] = false
	parent_death_year["father"] = 0
	pov = pov_before

	# A02：写入中断/损坏可回退备份
	money = 100
	_save_game()
	money = 200
	_save_game()
	var main_abs := ProjectSettings.globalize_path(_save_file())
	var broken := FileAccess.open(_save_file(), FileAccess.WRITE)
	if broken != null:
		broken.store_string("{ this is not json")
		broken.close()
	money = 0
	var ok_backup := _load_game()
	if ok_backup and recovered_from_backup and money == 100:
		oks += 1
		print("[VERIFY] PASS save_recovers_from_backup money=", money)
	else:
		fails.append("save_recovers_from_backup")
		print("[VERIFY] FAIL save_recovers_from_backup ok=", ok_backup,
			" recovered=", recovered_from_backup, " money=", money)
	recovered_from_backup = false

	recovered_from_backup = false

	# 旧档迁移：schema_version=1（无新字段）能读、有明确默认、再存即升级
	var fx := FileAccess.open("res://tests/fixtures/save_v1.json", FileAccess.READ)
	if fx != null:
		var legacy_text := fx.get_as_text()
		fx.close()
		var w := FileAccess.open(_save_file(), FileAccess.WRITE)
		if w != null:
			w.store_string(legacy_text)
			w.close()
		var ok_v1 := _load_game()
		var v1_defaults: bool = father_trade == "农" and women_rank == 0 \
			and is_equal_approx(time_scale, 1.0) and save_schema_seen == 1 \
			and name_text == "李守拙" and money == 3456 and mother_temper == "和"
		# 迁移应体现在下一次保存
		_save_game()
		var reread := _read_save_dict(_save_file())
		var upgraded: bool = int(reread.get("schema_version", 0)) == SAVE_SCHEMA_VERSION
		if ok_v1 and v1_defaults and upgraded:
			oks += 1
			print("[VERIFY] PASS save_migrates_v1 upgraded_to=", reread.get("schema_version", 0))
		else:
			fails.append("save_migrates_v1")
			print("[VERIFY] FAIL save_migrates_v1 ok=", ok_v1, " defaults=", v1_defaults,
				" upgraded=", upgraded, " ft=", father_trade, " wr=", women_rank,
				" ts=", time_scale, " schema=", save_schema_seen)
	else:
		fails.append("save_migrates_v1")
		print("[VERIFY] FAIL save_migrates_v1 fixture_missing")
	save_schema_seen = SAVE_SCHEMA_VERSION

	# M1-02：同一件事不能靠连点反复刷收益（冷却 = 声明的 months）
	action_cooldown = {}
	money = 500
	var keep_age2 := age
	age = 5  # 避开年关结算，只观察收益是否重复
	var spam := {"label": "测试短活", "months": 1, "gain": {"money": 300}}
	_on_action(spam)
	var after_first := money
	_on_action(spam)
	var after_second := money
	age = keep_age2
	if after_first == 800 and after_second == 800:
		oks += 1
		print("[VERIFY] PASS action_cooldown_blocks_spam money=", after_second)
	else:
		fails.append("action_cooldown_blocks_spam")
		print("[VERIFY] FAIL action_cooldown_blocks_spam first=", after_first, " second=", after_second)
	action_cooldown = {}

	# M1-02b：年关每年只结算一次（防重入）
	var keep_money2 := money
	var keep_age3 := age
	var keep_settled := last_settled_year
	age = 30
	money = 10000
	last_settled_year = year - 1
	_on_new_year()
	var once := money
	_on_new_year()
	if once < 10000 and money == once:
		oks += 1
		print("[VERIFY] PASS new_year_settles_once deducted=", 10000 - once)
	else:
		fails.append("new_year_settles_once")
		print("[VERIFY] FAIL new_year_settles_once once=", once, " twice=", money)
	money = keep_money2
	age = keep_age3
	last_settled_year = keep_settled

	# M1-02c：不操控父母时，他们的老化与死亡照样发生
	var keep_father: Dictionary = (pov_state.get("father", {}) as Dictionary).duplicate(true)
	var keep_settled2 := last_settled_year
	var keep_hp2 := health
	var f_state: Dictionary = pov_state.get("father", {})
	f_state["age"] = 55
	f_state["health"] = 40.0
	f_state["lifespan"] = 90
	pov_state["father"] = f_state
	health = 60.0
	last_settled_year = year - 1
	var keep_money3 := money
	var keep_events := events_enabled
	events_enabled = false  # 年度随机事件会扣血扣钱，先关掉只看老化
	money = 50000  # 保证年关付得起，不触发"欠年"扣血
	_on_new_year()
	events_enabled = keep_events
	var father_hp := float((pov_state.get("father", {}) as Dictionary).get("health", 0.0))
	if is_equal_approx(father_hp, 39.2) and is_equal_approx(health, 60.0):
		oks += 1
		print("[VERIFY] PASS actors_age_independently father_hp=", father_hp, " self_hp=", health)
	else:
		fails.append("actors_age_independently")
		print("[VERIFY] FAIL actors_age_independently father_hp=", father_hp, " self_hp=", health)
	pov_state["father"] = keep_father
	last_settled_year = keep_settled2
	health = keep_hp2
	money = keep_money3

	# M1-03：同种子得到同一串抽取；存读档后抽取接着走
	_init_sim_rng(12345)
	var seq_a: Array = []
	for i in range(6):
		seq_a.append(_rndi(0, 99))
	_init_sim_rng(12345)
	var seq_b: Array = []
	for i in range(6):
		seq_b.append(_rndi(0, 99))
	_init_sim_rng(777)
	_rndi(0, 99)
	_save_game()
	var expected_next := _rndi(0, 999)
	_init_sim_rng(1)
	var ok_rng_load := _load_game()
	var actual_next := _rndi(0, 999)
	if seq_a == seq_b and ok_rng_load and actual_next == expected_next:
		oks += 1
		print("[VERIFY] PASS rng_reproducible seq=", seq_a.slice(0, 3), " resume=", actual_next)
	else:
		fails.append("rng_reproducible")
		print("[VERIFY] FAIL rng_reproducible same=", seq_a == seq_b,
			" loaded=", ok_rng_load, " expected=", expected_next, " actual=", actual_next)
	_init_sim_rng(4242)

	# M1-03b：事实日志每条都要有类型与起因，时间不回退
	facts = []
	_apply_event("drought")
	_log_fact("exam", "test_cause", {"note": "x"})
	var ok_facts := facts.size() >= 2
	var last_t := -1
	for f in facts:
		var fd: Dictionary = f
		if str(fd.get("kind", "")) == "" or str(fd.get("cause", "")) == "":
			ok_facts = false
		if int(fd.get("t", 0)) < last_t:
			ok_facts = false
		last_t = int(fd.get("t", 0))
	var kinds: Array = []
	for f in facts:
		kinds.append(str((f as Dictionary).get("kind", "")))
	if ok_facts and kinds.has("event"):
		oks += 1
		print("[VERIFY] PASS facts_have_causes kinds=", kinds)
	else:
		fails.append("facts_have_causes")
		print("[VERIFY] FAIL facts_have_causes ok=", ok_facts, " kinds=", kinds)
	facts = []

	# M1-03c：墓志引用事实日志
	facts = []
	var no_trace := _facts_trace() == ""
	_log_fact("exam", "jieshi_pass", {"year": year})
	_log_fact("exam", "jieshi_fail", {"year": year})
	_log_fact("event", "year_end", {"id": "drought"})
	var with_trace := _facts_trace()
	var in_epitaph := false
	for line in _epitaph():
		if str(line).begins_with("一生所记"):
			in_epitaph = true
	if no_trace and with_trace.find("应试2次") >= 0 and in_epitaph:
		oks += 1
		print("[VERIFY] PASS epitaph_uses_facts ", with_trace)
	else:
		fails.append("epitaph_uses_facts")
		print("[VERIFY] FAIL epitaph_uses_facts empty_ok=", no_trace,
			" trace=", with_trace, " in_epitaph=", in_epitaph)
	facts = []

	# M1-01a：关系不随场景重建与存读档丢失
	relations = {}
	_set_att("li_shen", 25)
	_spawn_npcs()
	var att_after_rebuild := _get_att("li_shen")
	_save_game()
	relations = {}
	_load_game()
	var att_after_load := _get_att("li_shen")
	if att_after_rebuild == 25 and att_after_load == 25:
		oks += 1
		print("[VERIFY] PASS relations_survive_rebuild rebuild=", att_after_rebuild,
			" load=", att_after_load)
	else:
		fails.append("relations_survive_rebuild")
		print("[VERIFY] FAIL relations_survive_rebuild rebuild=", att_after_rebuild,
			" load=", att_after_load)
	relations = {}

	# A01：跨寿终的行动不得继续发奖（放最后，因为它会结束人生）
	var keep_money := money
	var keep_age := age
	money = 1000
	age = 40
	lifespan = 40
	_on_action({"label": "长活", "months": 12, "gain": {"money": 5000}})
	if ended and money == 1000:
		oks += 1
		print("[VERIFY] PASS death_blocks_reward money=", money)
	else:
		fails.append("death_blocks_reward")
		print("[VERIFY] FAIL death_blocks_reward ended=", ended, " money=", money)
	money = keep_money
	age = keep_age

	print("[VERIFY] SUMMARY pass=", oks, " fail=", fails.size(), " failed=", fails)
	get_tree().quit(0 if fails.is_empty() else 1)


func debug_scenes() -> void:
	busy = false
	scenes_done.clear()
	year = 1045
	month = 1
	for i in range(8):
		var sc := _due_scene()
		if sc.is_empty():
			print("[SCENE] 本月无节令 month=", month)
			break
		var m0 := month
		_do_scene(sc)
		print("[SCENE] ", sc["name"], " 月=", m0, " → ", month, "（年=", year, "）")
	print("[SCENE] 一年过完：年=", year, " 月=", month, " 已过节令=", scenes_done.size())


func debug_mom_panel() -> void:
	_switch_pov("mother")
	women_rank = 2
	craft = 52.0
	money = 4000
	player = Vector2(372, 600)
	cam = (player - Vector2(W * 0.5, H * 0.5)).clamp(Vector2.ZERO, Vector2(WORLD_W - W, WORLD_H - H))
	_open_panel("home")


func debug_mother() -> void:
	busy = false
	_switch_pov("mother")
	print("[MOM] 视角=", pov, " 年龄=", age, " 技艺=", craft, " 妇业=", _women_name())
	print("[MOM] 家选项=", _actions_for("home").size())
	_apply_special("w_start")
	print("[MOM] 接浆洗 → 妇业=", _women_name(), " 钱=", money)
	craft = 46.0
	_apply_special("w_journey")
	print("[MOM] 出师 → 妇业=", _women_name(), " 声望=", fame)
	print("[MOM] 绣娘期家选项=", _actions_for("home").size())
	craft = 72.0
	money = 9000
	fame = 30.0
	_apply_special("w_shop")
	print("[MOM] 开绣坊 → 妇业=", _women_name(), " 钱=", money)
	craft = 90.0
	fame = 60.0
	_apply_special("w_guild")
	print("[MOM] 掌行 → 妇业=", _women_name(), " 声望=", fame)
	_apply_special("w_midwife")
	print("[MOM] 接生一次 声望=", fame)
	_switch_pov("child")
	print("[MOM] 切回孩子 视角=", pov, " 母亲档位=", _mother_rank())


func debug_as_father() -> void:
	_switch_pov("father")
	player = Vector2(1268, 566)
	cam = (player - Vector2(W * 0.5, H * 0.5)).clamp(Vector2.ZERO, Vector2(WORLD_W - W, WORLD_H - H))
	_open_panel("market")


func debug_pov() -> void:
	busy = false
	print("[POV] 出生 视角=", pov, " 孩子=", age, "岁 能走=", can_walk)
	var f: Dictionary = pov_state["father"]
	print("[POV] 父亲=", f.get("age"), "岁 行当=", father_trade, " 匠级=", f.get("craft_rank"),
		" 技艺=", f.get("craft"), " 寿=", f.get("lifespan"))
	_switch_pov("father")
	print("[POV] 切到父亲 视角=", pov, " 年龄=", age, " 技艺=", craft, " 能去校场=", age >= int(MIN_AGE["drill"]))
	_on_action({"label": "做工", "months": 6, "gain": {"money": 1200}})
	_on_action({"label": "做工", "months": 6, "gain": {"money": 1200}})
	print("[POV] 父亲干一年 钱=", money, " 孩子年龄(存档)=", (pov_state.get("child", {}) as Dictionary).get("age"))
	_switch_pov("child")
	print("[POV] 切回孩子 年龄=", age, " 钱=", money, " 能走=", can_walk)
	print("[POV] 父亲年龄(存档)=", (pov_state.get("father", {}) as Dictionary).get("age"))


func debug_walk() -> void:
	busy = false
	print("[WALK] 出生 can_walk=", can_walk, " 年龄=", age, " 提示=", _hint())
	var before := player
	_start_walk(Vector2(1200, 900))
	print("[WALK] 婴儿点地面 → moving=", moving, " 位移=", player.distance_to(before))
	for i in range(2):
		_on_action({"label": "过一年", "months": 12, "special": "child_year"})
	print("[WALK] 两年后 年龄=", age, " can_walk=", can_walk)
	_start_walk(Vector2(1200, 900))
	print("[WALK] 会走后点地面 → moving=", moving, " 路径点=", path.size())


func debug_child() -> void:
	busy = false
	print("[CHILD] 父=%s（%s）母=%s（%s）年龄=%d" % [father_name, father_trade, mother_name, mother_temper, age])
	print("[CHILD] 家选项=", _actions_for("home").size(), "（低龄只应有一项）")
	print("[CHILD] 提示=", _hint())
	var seen := {}
	for y in range(6):
		_child_year()
		seen[child_last] = true
	print("[CHILD] 六次引导 事件=", seen.keys())
	print("[CHILD] 属性 学=", learning, " 技=", craft, " 身=", health, " 钱=", money)
	print("[CHILD] 父母台词 父=", _dialog_line(_find_npc("father")))
	print("[CHILD] 父母台词 母=", _dialog_line(_find_npc("mother")))
	print("[CHILD] 父选项=", _dialog_choices("father").size(), " 母选项=", _dialog_choices("mother").size())
	print("[CHILD] 墓志印记 当镯=", story.has("当镯"), " 病过=", story.has("病过"))


func debug_polish() -> void:
	money = 7777
	slot = 1
	_save_game()
	money = 111
	slot = 2
	_save_game()
	print("[SLOT] 档1=", FileAccess.file_exists("user://fusheng_save_1.json"),
		" 档2=", FileAccess.file_exists("user://fusheng_save_2.json"))
	money = 0
	slot = 1
	_load_game()
	print("[SLOT] 读档1 钱=", money)
	slot = 2
	_load_game()
	print("[SLOT] 读档2 钱=", money)
	print("[HINT] age=", age, " → ", _hint())
	Sfx.set_master(-12.0)
	print("[VOL] 设 -12 后=", Sfx.master_db)
	Sfx.set_master(0.0)
	print("[VOL] 复位=", Sfx.master_db)


func debug_warm() -> void:
	_set_att("li_shen", 22)
	_freeze_npc("li_shen")
	_open_dialog_by_id("li_shen")


func debug_events() -> void:
	age = 35
	children = 2
	farm_rank = 2
	fame = 50.0
	var seen := {}
	for i in range(500):
		var pool: Array = []
		for e in EVENTS:
			if _event_ok(e):
				pool.append(e)
		if not pool.is_empty():
			seen[str(pool[randi() % pool.size()]["id"])] = true
	print("[EVT] 可达事件种类=", seen.size(), " ", seen.keys())
	_set_att("zhang_tu", 0)
	print("[MEM] 张屠户 态度 0 → 肉价 ", _meat_price())
	_set_att("zhang_tu", 40)
	print("[MEM] 张屠户 态度 40 → 肉价 ", _meat_price())
	_set_att("zhang_tu", -40)
	print("[MEM] 张屠户 态度 -40 → 肉价 ", _meat_price())
	_set_att("li_shen", 20)
	print("[MEM] 李婶 态度 20 → ", _dialog_line(_find_npc("li_shen")))
	_set_att("li_shen", -20)
	print("[MEM] 李婶 态度 -20 → ", _dialog_line(_find_npc("li_shen")))
	var m0 := money
	_apply_event("drought")
	print("[EVT] 旱灾 ", m0, "→", money, " 身体=", health)


func debug_mil() -> void:
	money = 10000
	health = 85.0
	print("[MIL] 初始 rank=", mil_rank, " 校场选项=", _actions_for("drill").size())
	_apply_special("enlist")
	print("[MIL] 应募后 rank=", mil_rank, " 钱=", money, " 选项=", _actions_for("drill").size())
	merit = 2
	_apply_special("promote_nco")
	print("[MIL] 升厢军 rank=", mil_rank, " 墓志=", _tier_name())
	merit = 5
	fame = 45.0
	_apply_special("promote_officer")
	print("[MIL] 授军官 rank=", mil_rank, " 葬志=", _tier_name())
	var rounds := 0
	for i in range(20):
		if ended:
			break
		rounds += 1
		_apply_special("patrol")
	print("[MIL] 巡边 ", rounds, " 次 战死=", ended, " 死因=", death_cause)


func debug_farm() -> void:
	money = 150000
	print("[FARM] 初始 rank=", farm_rank, " 田=", land, " 选项=", _actions_for("field").size())
	_apply_special("farm_rent")
	print("[FARM] 租田后 rank=", farm_rank, " 钱=", money)
	for i in range(6):
		_on_action({"label": "买田", "months": 3, "cost": _land_price(), "special": "farm_buy"})
	print("[FARM] 六亩后 rank=", farm_rank, " 田=", land, " 钱=", money)
	for i in range(14):
		_on_action({"label": "买田", "months": 3, "cost": _land_price(), "special": "farm_buy"})
	print("[FARM] 二十亩后 rank=", farm_rank, " 田=", land, " 钱=", money)
	for i in range(20):
		_on_action({"label": "买田", "months": 3, "cost": _land_price(), "special": "farm_buy"})
	print("[FARM] 四十亩后 rank=", farm_rank, " 田=", land, " 钱=", money, " 墓志=", _tier_name())
	var before := money
	_apply_special("farm_collect")
	print("[FARM] 收一年租 ", before, "→", money)


func debug_med() -> void:
	money = 20000
	fame = 20.0
	print("[MED] 初始 rank=", med_rank, " 药铺选项=", _actions_for("pharmacy").size())
	_apply_special("med_apprentice")
	medicine = 36.0
	print("[MED] 拜师后 rank=", med_rank, " 医术=", medicine, " 选项=", _actions_for("pharmacy").size())
	_apply_special("med_journeyman")
	medicine = 62.0
	fame = 35.0
	_apply_special("med_clinic")
	print("[MED] 坐堂 rank=", med_rank, " 声望=", fame)
	medicine = 88.0
	fame = 60.0
	_apply_special("med_book")
	print("[MED] 著书 rank=", med_rank, " 著书=", med_book, " 墓志=", _tier_name())
	var m0 := money
	var f0 := fame
	for i in range(6):
		_apply_special("med_visit")
	print("[MED] 六次出诊 钱 ", m0, "→", money, " 声望 ", f0, "→", fame)


func debug_trade() -> void:
	money = 60000
	fame = 30.0
	print("[TRADE] 初始 rank=", trade_rank, " 市集选项=", _actions_for("market").size())
	_apply_special("stall")
	print("[TRADE] 摆摊后 钱=", money, " 声望=", fame)
	_apply_special("caravan")
	print("[TRADE] 跑商后 钱=", money)
	trade_rank = 1
	shop_open = true
	shop_label = "绸庄"
	shop["kind"] = "silk"
	shop_level = 1
	_apply_special("sedentary")
	print("[TRADE] 坐贾 rank=", trade_rank, " 铺级=", shop_level, " 声望=", fame)
	fame = 45.0
	_apply_special("guild")
	print("[TRADE] 行会 rank=", trade_rank, " 行会=", guild_open, " 声望=", fame)
	_apply_special("set_price")
	print("[TRADE] 议价后 行情=", shop.get("market", 1.0), " 墓志=", _tier_name())


func debug_craft() -> void:
	craft = 20.0
	money = 20000
	print("[CRAFT] 初始 rank=", craft_rank, " 选项=", _actions_for("smithy").size())
	_apply_special("apprentice")
	print("[CRAFT] 拜师后 rank=", craft_rank, " 技艺=", craft, " 选项=", _actions_for("smithy").size())
	craft = 45.0
	_apply_special("journeyman")
	print("[CRAFT] 出师后 rank=", craft_rank, " 声望=", fame)
	craft = 60.0
	_apply_special("take_apprentice")
	craft = 70.0
	_apply_special("workshop")
	print("[CRAFT] 作坊 rank=", craft_rank, " 徒弟=", apprentice_hired,
		" 作坊=", workshop_open, " 墓志=", _tier_name())


func debug_epitaph(tier: int) -> void:
	story = {}
	money = 12000
	married = true
	spouse_name = "李氏"
	children = 2
	age = 63
	fame = 40.0
	if tier == 0:
		story["进士"] = true
		fame = 80.0
	elif tier == 1:
		story["进士"] = true
		fame = 50.0
	elif tier == 2:
		story["举人"] = true
		fame = 48.0
	elif tier == 4:
		married = false
		children = 0
		fame = 5.0
	_show_epitaph()


func debug_exam() -> void:
	learning = 70.0
	story["读书"] = true
	money = 20000
	year = 1057
	age = 22
	print("[EXAM] 开科=", _is_exam_year(), " 书院选项=", _actions_for("academy").size())
	for i in range(8):
		_apply_special("jieshi")
		if story.has("举人"):
			break
	print("[EXAM] 举人=", story.has("举人"), " 声望=", fame)
	for i in range(8):
		_apply_special("shengshi")
		if story.has("进士"):
			break
	print("[EXAM] 进士=", story.has("进士"), " 声望=", fame, " 钱=", money)
	print("[EXAM] 墓志档位=", _tier_name())


func _clear_save() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var base := _save_file().get_file()
	for f in [base, base + ".bak", base + ".tmp"]:
		if FileAccess.file_exists("user://" + f):
			dir.remove(f)


func _init_identity() -> void:
	var r := RandomNumberGenerator.new()
	if sim_seed != 0:
		r.seed = sim_seed
	else:
		r.randomize()
	var o: Dictionary = DB.pick_origin(r)
	var nm: Dictionary = DB.make_name(r, "男")
	name_text = str(nm["full"])
	place = str(o["place"])
	money = int(o["money"])
	origin_flags = []
	for f in o.get("flags", []):
		origin_flags.append(str(f))
	var at: Dictionary = o["attrs"]
	learning = float(at["learning"])
	craft = float(at["craft"])
	fame = float(at["fame"])
	health = float(at["health"])
	year = r.randi_range(1040, 1044)
	birth_year = year
	age = 0
	can_walk = false
	month = r.randi_range(1, 12)
	lifespan = 56 + r.randi_range(0, 22)
	var fathers: Array = DB.names.get("father", ["九"])
	var mothers: Array = DB.names.get("mother_surname", ["王"])
	father_name = str(nm["surname"]) + str(fathers[r.randi_range(0, fathers.size() - 1)])
	mother_name = str(mothers[r.randi_range(0, mothers.size() - 1)]) + "氏"
	# 父亲的行当、母亲的性情——决定童年被怎么带大
	father_trade = _father_trade_for(origin_flags)
	var temps := ["和", "严", "病"]
	mother_temper = str(temps[r.randi_range(0, temps.size() - 1)])
	pov_state["father"] = _make_parent("father", r)
	pov_state["mother"] = _make_parent("mother", r)
	child_pos = player
	# 体格：兵的壮、吏的瘦、农与匠的厚实
	if origin_flags.has("军户"):
		player_build = BUILDS[0]
	elif origin_flags.has("读书") or origin_flags.has("士人"):
		player_build = BUILDS[3]
	elif origin_flags.has("匠人"):
		player_build = BUILDS[2]
	else:
		player_build = BUILDS[1]


func _make_parent(who: String, r: RandomNumberGenerator) -> Dictionary:
	var st := {
		"age": 28, "health": 70.0, "learning": 10.0, "craft": 10.0, "fame": 5.0,
		"lifespan": 62,
		"craft_rank": 0, "trade_rank": 0, "med_rank": 0, "farm_rank": 0, "mil_rank": 0,
		"office_rank": 0, "gov_merit": 0, "scandal": 0, "county": "",
		"land": 0, "workshop_open": false, "guild_open": false,
		"apprentice_hired": 0, "med_book": false, "medicine": 0.0, "merit": 0,
		"can_walk": true, "story": {}, "women_rank": 0,
	}
	if who == "father":
		st["age"] = r.randi_range(25, 34)
		st["lifespan"] = int(st["age"]) + r.randi_range(20, 34)
		match father_trade:
			"匠":
				st["craft"] = 52.0
				st["craft_rank"] = 2
				st["fame"] = 10.0
			"商":
				st["learning"] = 26.0
				st["trade_rank"] = 1
				st["fame"] = 14.0
			"兵":
				st["health"] = 84.0
				st["mil_rank"] = 1
				st["fame"] = 8.0
			"吏":
				st["learning"] = 48.0
				st["fame"] = 18.0
			_:
				st["craft"] = 28.0
				st["farm_rank"] = 1
				st["health"] = 66.0
	else:
		st["age"] = r.randi_range(22, 30)
		st["lifespan"] = int(st["age"]) + r.randi_range(24, 38)
		st["craft"] = 34.0
		st["health"] = 60.0
	return st


func _is_craft_family() -> bool:
	return origin_flags.has("匠人")


func _rank_name() -> String:
	return str(["白身", "学徒", "匠人", "都料匠"][craft_rank])


func _trade_name() -> String:
	return str(["白身", "行商", "坐贾", "行会头目"][trade_rank])


func _med_name() -> String:
	return str(["白身", "学徒", "郎中", "坐堂", "名医"][med_rank])


func _farm_name() -> String:
	return str(["白身", "佃农", "自耕农", "小地主", "田主"][farm_rank])


func _land_price() -> int:
	return 2000 + farm_rank * 400


func _mil_name() -> String:
	return str(["白身", "乡兵", "厢军", "军官"][mil_rank])


func _leave_old_line(keep: String) -> void:
	# 改行：除了正在入的这条线，其余已入行的职业各降一级（田产是资产，不降）
	var lost: Array = []
	if keep != "craft" and craft_rank > 0:
		craft_rank -= 1
		lost.append("手艺")
	if keep != "trade" and trade_rank > 0:
		trade_rank -= 1
		lost.append("生意")
	if keep != "med" and med_rank > 0:
		med_rank -= 1
		lost.append("医术")
	if keep != "mil" and mil_rank > 0:
		mil_rank -= 1
		lost.append("军职")
	if lost.is_empty():
		return
	var s := ""
	for i in range(lost.size()):
		if i > 0:
			s += "、"
		s += str(lost[i])
	_toast("久不操持，%s都荒了。" % s, Color(0.48, 0.32, 0.16))


func _father_trade_word() -> String:
	return str({"农": "种田", "匠": "做手艺", "商": "跑买卖", "兵": "当兵", "吏": "在衙门抄写"}.get(father_trade, "种田"))


func _capture_pov() -> Dictionary:
	var d := {}
	for k in POV_FIELDS:
		d[k] = get(k)
	d["story"] = (story as Dictionary).duplicate(true)
	return d


func _apply_pov(d: Dictionary) -> void:
	for k in POV_FIELDS:
		if d.has(k):
			set(k, d[k])
	story = (d.get("story", {}) as Dictionary).duplicate(true)


func _pov_npc_id() -> String:
	return "" if pov == "child" else pov


func _switch_pov(who: String) -> void:
	if who == pov or ended:
		return
	if who != "child" and (not pov_state.has(who) or bool(parent_dead.get(who, false))):
		return
	var from_pos := player
	pov_state[pov] = _capture_pov()
	var target: Dictionary = pov_state.get(who, {})
	if who == "child":
		pov_state["father"] = pov_state.get("father", {})
	pov = who
	if not target.is_empty():
		_apply_pov(target)
	if who == "child":
		player = child_pos
	else:
		player = from_pos
	child_pos = player if who == "child" else child_pos
	busy = false
	panel.visible = false
	_spawn_npcs()
	_center_on_player()
	_refresh_pov_bar()
	var label := "你自己"
	match who:
		"father":
			label = "父亲" + father_name
		"mother":
			label = "母亲" + mother_name
	_toast("你现在是%s，%s岁。" % [label, DB.cn(age)], Color(0.48, 0.32, 0.16))
	Sfx.play("bell")


func _build_pov_bar() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(18.0, H - 114.0)
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for who in ["father", "mother", "child"]:
		var b := UIKit.ink_button("　", 88)
		b.custom_minimum_size = Vector2(88, 32)
		b.add_theme_font_size_override("font_size", 15)
		b.tooltip_text = "切换视角"
		b.pressed.connect(_switch_pov.bind(str(who)))
		row.add_child(b)
		pov_btns.append(b)
	# 流速按钮：点一下在 1× / 60× / 600× / 3600× 之间轮换
	speed_btn = UIKit.ink_button("流速 1×", 116)
	speed_btn.position = Vector2(18.0, H - 152.0)
	speed_btn.custom_minimum_size = Vector2(116, 30)
	speed_btn.add_theme_font_size_override("font_size", 14)
	speed_btn.tooltip_text = "点击切换时间流速（1 年 7 天 / 2.8 小时 / 17 分钟 / 2.8 分钟）"
	speed_btn.pressed.connect(_cycle_speed)
	add_child(speed_btn)
	_refresh_pov_bar()


func _refresh_pov_bar() -> void:
	if pov_btns.is_empty():
		return
	var ids := ["father", "mother", "child"]
	for i in range(pov_btns.size()):
		var who := str(ids[i])
		var b: Button = pov_btns[i]
		var alive := who == "child" or not bool(parent_dead.get(who, false))
		b.visible = alive
		if not alive:
			continue
		var label := "父亲"
		if who == "mother":
			label = "母亲"
		elif who == "child":
			label = "自己"
		b.text = label + ("·当前" if pov == who else "")
		b.disabled = (pov == who)


func _women_name() -> String:
	return str(["白身", "帮工", "绣娘", "绣坊主", "行首"][women_rank])


func _mother_rank() -> int:
	if pov == "mother":
		return women_rank
	return int((pov_state.get("mother", {}) as Dictionary).get("women_rank", 0))


func _mother_home_actions() -> Array:
	var a: Array = []
	if women_rank == 0:
		a.append({"label": "接第一份浆洗（三个月）", "months": 3, "special": "w_start"})
	if women_rank == 1 and craft >= 45.0:
		a.append({"label": "出师，做绣娘（三个月）", "months": 3, "special": "w_journey"})
	if women_rank >= 1:
		a.append({"label": "接绣活（半年）", "months": 6, "cost": 0,
			"gain": {"money": 1200, "craft": 3},
			"flavor": "半年绣了十二方帕子，指尖全是针眼。"})
		a.append({"label": "在门口摆个茶摊（半年）", "months": 6, "cost": 0,
			"gain": {"money": 900, "fame": 2},
			"flavor": "过路的脚夫坐满了三条凳，一天能卖四十碗。"})
	if women_rank >= 2:
		a.append({"label": "帮人接生（一个月，有风险）", "months": 1, "special": "w_midwife"})
	if women_rank == 2 and craft >= 70.0 and money >= 6000:
		a.append({"label": "开一间绣坊（六贯，一年）", "months": 12, "cost": 6000,
			"special": "w_shop"})
	if women_rank >= 3:
		a.append({"label": "绣坊收徒（三个月）", "months": 3, "cost": 0,
			"gain": {"fame": 4, "craft": 1}, "flavor": "收了两个丫头，先教穿针。"})
	if women_rank == 3 and craft >= 88.0 and fame >= 50.0:
		a.append({"label": "掌女红行（一年）", "months": 12, "special": "w_guild"})
	a.append({"label": "浆洗缝补（三个月）", "months": 3, "cost": 0,
		"gain": {"money": 350, "craft": 1}, "flavor": "手泡在冷水里，冬天裂了口子。"})
	return a


func _strip_time(s: String) -> String:
	# 动作不再消耗时间，标签里的"（三个月）"就没意义了，去掉
	if _re_time.get_pattern() == "":
		_re_time.compile("（(?:一个月|三个月|半年|一年|一季)")
	var out := _re_time.sub(s, "（", true)
	out = out.replace("（）", "")
	out = out.replace("（，", "（")
	return out


func _set_time_scale(s: float) -> void:
	time_scale = s
	_refresh_speed_btn()
	var per_year := SECONDS_PER_YEAR / time_scale
	var txt := ""
	if per_year >= 86400.0:
		txt = "%.1f 天" % (per_year / 86400.0)
	elif per_year >= 3600.0:
		txt = "%.1f 小时" % (per_year / 3600.0)
	else:
		txt = "%.0f 分钟" % (per_year / 60.0)
	_toast("流速 %.0f×　—　一年约 %s" % [time_scale, txt], Color(0.48, 0.32, 0.16))
	Sfx.play("click")


func _cycle_speed() -> void:
	var i := TIME_SCALES.find(time_scale)
	if i < 0:
		i = -1
	_set_time_scale(float(TIME_SCALES[(i + 1) % TIME_SCALES.size()]))


func _refresh_speed_btn() -> void:
	if speed_btn == null:
		return
	speed_btn.text = "流速 %.0f×" % time_scale


func _due_scene() -> Dictionary:
	if ended or busy:
		return {}
	for s in YEAR_SCENES:
		var key := "%d_%s" % [year, str(s["id"])]
		var m := int(s["m"])
		if month >= m and month <= m + 2 and not scenes_done.has(key):
			return s
	return {}


func _scene_months_to_next() -> int:
	# 到下个还没过的节令还有几个月（同月的算 0，先把同月的过完）
	for s in YEAR_SCENES:
		var m := int(s["m"])
		var key := "%d_%s" % [year, str(s["id"])]
		if scenes_done.has(key):
			continue
		if m >= month:
			return m - month
	return 13 - month


func _do_scene(s: Dictionary) -> void:
	# 打开节令的选择面板，选完才推进时间
	var sid := str(s["id"])
	panel_title.text = str(s["name"])
	panel_sub.text = str(SCENE_FLAVOR.get(sid, ""))
	for c in panel_actions.get_children():
		panel_actions.remove_child(c)
		c.queue_free()
	for o in SCENE_OPTS.get(sid, []):
		var opt: Dictionary = o
		var b := UIKit.choice(str(opt["label"]))
		if int(opt.get("cost", 0)) > money:
			b.disabled = true
			b.text += "　—　钱不够"
		var act := {"label": str(opt["label"]), "months": 0,
			"special": "scene_pick:%s:%s" % [sid, str(opt["id"])]}
		b.pressed.connect(_on_action.bind(act))
		panel_actions.add_child(b)
	panel.visible = true
	busy = true
	Sfx.play("open")
	_fit_panel()
	queue_redraw()


func _pick_scene_option(sid: String, oid: String) -> void:
	for o in SCENE_OPTS.get(sid, []):
		var opt: Dictionary = o
		if str(opt["id"]) != oid:
			continue
		var cost := int(opt.get("cost", 0))
		if cost > money:
			_toast("钱不够。", Color(0.62, 0.24, 0.18))
			return
		money -= cost
		_apply_gain(opt.get("gain", {}))
		scenes_done["%d_%s" % [year, sid]] = true
		var line := str(opt["text"])
		# 童年 + 家里紧 → 换一句更苦的，并留下墓志印记
		if age < 12 and money < 250 and opt.has("poor"):
			line = str(opt["poor"])
			story["穷" + sid] = true
		elif age < 12:
			story["童年节令"] = int(story.get("童年节令", 0)) + 1
		if sid == "dongzhi" and oid == "poor":
			story["施舍"] = true
		_toast(line, Color(0.30, 0.42, 0.22))
		var jump := _scene_months_to_next()
		if jump > 0:
			_advance_months(jump)
		Sfx.play("ok")
		_save_game()
		return


func _office_name() -> String:
	return str(["待选", "主簿", "县令", "通判"][office_rank])


func _promote_need() -> int:
	return [0, 6, 14, 99][office_rank]


func _salary() -> int:
	return [2400, 2400, 4800, 8400][office_rank]


func _rebuild() -> void:
	buildings = [
		{"id": "home", "name": "家", "pos": Vector2(320, 500), "w": 176, "h": 104, "kind": "house"},
		{"id": "school", "name": "私塾", "pos": Vector2(660, 420), "w": 166, "h": 98, "kind": "house"},
		{"id": "field", "name": "田", "pos": Vector2(940, 650), "w": 210, "h": 136, "kind": "field"},
		{"id": "market", "name": "市集", "pos": Vector2(1268, 452), "w": 196, "h": 110, "kind": "house"},
		{"id": "temple", "name": "寺庙", "pos": Vector2(1596, 800), "w": 176, "h": 110, "kind": "temple"},
		{"id": "academy", "name": "书院", "pos": Vector2(1866, 450), "w": 184, "h": 110, "kind": "house"},
		{"id": "yamen", "name": "衙门", "pos": Vector2(2196, 640), "w": 196, "h": 114, "kind": "house"},
		{"id": "teahouse", "name": "茶肆", "pos": Vector2(1660, 1010), "w": 168, "h": 100, "kind": "house"},
		{"id": "pharmacy", "name": "药铺", "pos": Vector2(2020, 880), "w": 162, "h": 98, "kind": "house"},
		{"id": "shrine", "name": "祠堂", "pos": Vector2(900, 1090), "w": 172, "h": 102, "kind": "house"},
		{"id": "smithy", "name": "铁匠铺", "pos": Vector2(392, 894), "w": 156, "h": 96, "kind": "house"},
		{"id": "tavern", "name": "酒肆", "pos": Vector2(1012, 306), "w": 170, "h": 100, "kind": "house"},
		{"id": "pawnshop", "name": "当铺", "pos": Vector2(1424, 1186), "w": 160, "h": 98, "kind": "house"},
		{"id": "washe", "name": "瓦舍", "pos": Vector2(2008, 1160), "w": 184, "h": 106, "kind": "house"},
		{"id": "mulberry", "name": "桑园", "pos": Vector2(520, 1300), "w": 200, "h": 130, "kind": "field"},
		{"id": "dye", "name": "染坊", "pos": Vector2(2740, 764), "w": 168, "h": 100, "kind": "house"},
		{"id": "inn", "name": "客栈", "pos": Vector2(2648, 1336), "w": 180, "h": 104, "kind": "house"},
		{"id": "drill", "name": "校场", "pos": Vector2(1080, 1390), "w": 190, "h": 108, "kind": "house"},
		{"id": "grave", "name": "坟地", "pos": Vector2(430, 300), "w": 200, "h": 120, "kind": "grave"},
		{"id": "garden", "name": "菜园", "pos": Vector2(2940, 430), "w": 180, "h": 120, "kind": "garden"},
		{"id": "thresh", "name": "打谷场", "pos": Vector2(300, 1450), "w": 220, "h": 140, "kind": "thresh"},
		{"id": "dock", "name": "码头", "pos": Vector2(1600, 1430), "w": 176, "h": 100, "kind": "dock"},
	]
	if shop_open:
		buildings.append({"id": "shop", "name": shop_label, "pos": Vector2(2470, 1020), "w": 186, "h": 104, "kind": "shop"})
	elif age >= 16:
		buildings.append({"id": "lot", "name": "空地", "pos": Vector2(2470, 1020), "w": 172, "h": 96, "kind": "lot"})

	props = [
		{"kind": "tree", "pos": Vector2(120, 300), "r": 44.0},
		{"kind": "tree", "pos": Vector2(540, 300), "r": 38.0},
		{"kind": "tree", "pos": Vector2(860, 300), "r": 40.0},
		{"kind": "tree", "pos": Vector2(1120, 260), "r": 36.0},
		{"kind": "tree", "pos": Vector2(1440, 300), "r": 42.0},
		{"kind": "tree", "pos": Vector2(2060, 320), "r": 38.0},
		{"kind": "tree", "pos": Vector2(2560, 380), "r": 44.0},
		{"kind": "tree", "pos": Vector2(2860, 700), "r": 46.0},
		{"kind": "tree", "pos": Vector2(300, 1100), "r": 42.0},
		{"kind": "tree", "pos": Vector2(760, 1180), "r": 38.0},
		{"kind": "tree", "pos": Vector2(1180, 1240), "r": 42.0},
		{"kind": "tree", "pos": Vector2(2180, 1300), "r": 44.0},
		{"kind": "tree", "pos": Vector2(2800, 1260), "r": 40.0},
		{"kind": "well", "pos": Vector2(1250, 700), "r": 28.0},
		{"kind": "well", "pos": Vector2(2150, 950), "r": 26.0},
		{"kind": "stall", "pos": Vector2(1180, 560), "r": 34.0},
		{"kind": "stall", "pos": Vector2(1360, 560), "r": 34.0},
		{"kind": "stall", "pos": Vector2(1120, 900), "r": 32.0},
		{"kind": "rock", "pos": Vector2(700, 980), "r": 18.0},
		{"kind": "rock", "pos": Vector2(1980, 1080), "r": 20.0},
		{"kind": "hay", "pos": Vector2(1080, 840), "r": 22.0},
		{"kind": "hay", "pos": Vector2(1140, 900), "r": 20.0},
		{"kind": "hay", "pos": Vector2(640, 880), "r": 21.0},
		{"kind": "cart", "pos": Vector2(1520, 700), "r": 26.0},
		{"kind": "cart", "pos": Vector2(2320, 900), "r": 24.0},
		{"kind": "fence", "pos": Vector2(420, 700), "r": 60.0},
		{"kind": "fence", "pos": Vector2(1000, 980), "r": 70.0},
		{"kind": "fence", "pos": Vector2(1820, 1180), "r": 64.0},
		{"kind": "fence", "pos": Vector2(2560, 1220), "r": 56.0},
		{"kind": "tree", "pos": Vector2(210, 620), "r": 36.0},
		{"kind": "tree", "pos": Vector2(210, 980), "r": 34.0},
		{"kind": "tree", "pos": Vector2(880, 1120), "r": 32.0},
		{"kind": "tree", "pos": Vector2(1300, 980), "r": 36.0},
		{"kind": "tree", "pos": Vector2(1560, 320), "r": 34.0},
		{"kind": "tree", "pos": Vector2(2380, 420), "r": 38.0},
		{"kind": "tree", "pos": Vector2(2720, 980), "r": 36.0},
		{"kind": "tree", "pos": Vector2(3040, 1180), "r": 42.0},
		{"kind": "hay", "pos": Vector2(456, 1180), "r": 20.0},
		{"kind": "hay", "pos": Vector2(620, 1420), "r": 22.0},
		{"kind": "hay", "pos": Vector2(1180, 1420), "r": 20.0},
		{"kind": "cart", "pos": Vector2(316, 1080), "r": 24.0},
		{"kind": "cart", "pos": Vector2(1712, 1300), "r": 26.0},
		{"kind": "stall", "pos": Vector2(1480, 640), "r": 30.0},
		{"kind": "stall", "pos": Vector2(2130, 520), "r": 28.0},
		{"kind": "well", "pos": Vector2(760, 900), "r": 24.0},
		{"kind": "well", "pos": Vector2(1880, 1240), "r": 24.0},
		{"kind": "rock", "pos": Vector2(1120, 1160), "r": 18.0},
		{"kind": "rock", "pos": Vector2(2660, 700), "r": 20.0},
		{"kind": "fence", "pos": Vector2(640, 1160), "r": 54.0},
		{"kind": "fence", "pos": Vector2(1480, 960), "r": 64.0},
		{"kind": "fence", "pos": Vector2(2260, 1260), "r": 58.0},
		{"kind": "fence", "pos": Vector2(940, 1260), "r": 50.0},
		{"kind": "tree", "pos": Vector2(2880, 980), "r": 40.0},
		{"kind": "tree", "pos": Vector2(3000, 1240), "r": 36.0},
		{"kind": "tree", "pos": Vector2(2400, 1080), "r": 34.0},
		{"kind": "tree", "pos": Vector2(2560, 760), "r": 32.0},
		{"kind": "hay", "pos": Vector2(2820, 1180), "r": 20.0},
		{"kind": "cart", "pos": Vector2(2760, 900), "r": 24.0},
		{"kind": "fence", "pos": Vector2(2960, 760), "r": 56.0},
		{"kind": "stall", "pos": Vector2(2600, 1180), "r": 28.0},
		{"kind": "tree", "pos": Vector2(1460, 1180), "r": 36.0},
		{"kind": "tree", "pos": Vector2(2380, 1180), "r": 34.0},
		{"kind": "tree", "pos": Vector2(560, 1320), "r": 40.0},
		{"kind": "tree", "pos": Vector2(1980, 1240), "r": 38.0},
	]
	_spawn_npcs()
	_build_grid()


# ---------------------------------------------------------------- 网格与寻路

func _build_grid() -> void:
	grid_w = int(WORLD_W / CELL)
	grid_h = int(WORLD_H / CELL)
	blocked.resize(grid_w * grid_h)
	blocked.fill(0)
	for b in buildings:
		_block_rect(_footprint(b).grow(12.0))
	for p in props:
		var pr: Dictionary = p
		if str(pr["kind"]) == "stall":
			continue
		var pos: Vector2 = pr["pos"]
		_block_rect(Rect2(pos.x - 18.0, pos.y - 14.0, 36.0, 28.0))
	# 河
	var ry := int(RIVER_Y / CELL)
	for gy in range(ry, grid_h):
		for gx in range(grid_w):
			blocked[gy * grid_w + gx] = 1
	# 码头栈桥开口
	var dock_cx := int(1600.0 / CELL)
	for gx in range(dock_cx - 4, dock_cx + 5):
		for gy in range(ry - 1, ry + 2):
			if gx >= 0 and gx < grid_w and gy >= 0 and gy < grid_h:
				blocked[gy * grid_w + gx] = 0


func _block_rect(r: Rect2) -> void:
	var x0 := int(floor(r.position.x / CELL))
	var x1 := int(floor((r.position.x + r.size.x) / CELL))
	var y0 := int(floor(r.position.y / CELL))
	var y1 := int(floor((r.position.y + r.size.y) / CELL))
	for gy in range(maxi(0, y0), mini(grid_h - 1, y1) + 1):
		for gx in range(maxi(0, x0), mini(grid_w - 1, x1) + 1):
			blocked[gy * grid_w + gx] = 1


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, grid_w - 1), clampi(int(p.y / CELL), 0, grid_h - 1))


func _is_blocked(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= grid_w or c.y >= grid_h:
		return true
	return blocked[c.y * grid_w + c.x] == 1


func _idx(c: Vector2i) -> int:
	return c.y * grid_w + c.x


func _nearest_open(c: Vector2i) -> Vector2i:
	if not _is_blocked(c):
		return c
	for radius in range(1, 12):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var n := Vector2i(c.x + dx, c.y + dy)
				if not _is_blocked(n):
					return n
	return c


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + 0.414 * float(mini(dx, dy))


func _find_path(from: Vector2, to: Vector2) -> Array:
	var start := _nearest_open(_cell_of(from))
	var goal := _nearest_open(_cell_of(to))
	var open: Array = [start]
	var came: Dictionary = {}
	var gscore: Dictionary = {}
	var fscore: Dictionary = {}
	gscore[_idx(start)] = 0.0
	fscore[_idx(start)] = _heuristic(start, goal)
	var closed: Dictionary = {}

	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if float(fscore.get(_idx(open[i]), 1e9)) < float(fscore.get(_idx(open[best]), 1e9)):
				best = i
		var cur: Vector2i = open[best]
		if cur == goal:
			return _reconstruct(came, cur, to)
		open.remove_at(best)
		closed[_idx(cur)] = true

		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nb := Vector2i(cur.x + dx, cur.y + dy)
				if _is_blocked(nb) or closed.has(_idx(nb)):
					continue
				var step := 1.414 if (dx != 0 and dy != 0) else 1.0
				var tentative := float(gscore.get(_idx(cur), 1e9)) + step
				if tentative < float(gscore.get(_idx(nb), 1e9)):
					came[_idx(nb)] = cur
					gscore[_idx(nb)] = tentative
					fscore[_idx(nb)] = tentative + _heuristic(nb, goal)
					if not open.has(nb):
						open.append(nb)
	return []


func _reconstruct(came: Dictionary, cur: Vector2i, final_point: Vector2) -> Array:
	var cells: Array = [cur]
	var guard := 0
	while came.has(_idx(cur)) and guard < 4000:
		guard += 1
		cur = came[_idx(cur)]
		cells.append(cur)
	cells.reverse()
	var out: Array = []
	for i in range(1, cells.size()):
		var c: Vector2i = cells[i]
		out.append(Vector2((float(c.x) + 0.5) * CELL, (float(c.y) + 0.5) * CELL))
	out.append(final_point)
	return out


# ---------------------------------------------------------------- 输入

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				dragging = true
				drag_from = mb.position
				drag_cam = cam
				mouse_default_cursor_shape = Control.CURSOR_DRAG
			else:
				dragging = false
				mouse_default_cursor_shape = Control.CURSOR_ARROW
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _mm_rect().has_point(mb.position):
				_cam_to_minimap(mb.position)
				return
			if busy or ended:
				return
			var world_pos := mb.position + cam
			Sfx.play("click")
			if not can_walk:
				var b0 := _building_at(world_pos)
				if not b0.is_empty() and str(b0["id"]) == "home":
					_open_panel("home")
				else:
					_toast("你还不会走，母亲抱着你。", Color(0.48, 0.32, 0.16))
				return
			var b := _building_at(world_pos)
			if not b.is_empty():
				pending_npc = ""
				pending_building = str(b["id"])
				_start_walk(_door_of(b))
				return
			var npc := _npc_at(world_pos)
			if not npc.is_empty():
				pending_building = ""
				pending_npc = str(npc["id"])
				_freeze_npc(str(npc["id"]))
				_start_walk((npc["pos"] as Vector2) + Vector2(0, 42))
				return
			pending_building = ""
			pending_npc = ""
			_start_walk(world_pos)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging:
			cam = (drag_cam - (mm.position - drag_from)).clamp(Vector2.ZERO, Vector2(WORLD_W - W, WORLD_H - H))
			queue_redraw()
			return
		var wp := mm.position + cam
		var b := _building_at(wp)
		var id := "" if b.is_empty() else str(b["id"])
		var npc := _npc_at(wp)
		var nid := "" if npc.is_empty() else str(npc["id"])
		if id != hover_id or nid != hover_npc:
			hover_id = id
			hover_npc = nid
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (id != "" or nid != "") else Control.CURSOR_ARROW
			queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	match k:
		KEY_F, KEY_HOME:
			_center_on_player()
		KEY_A, KEY_LEFT:
			_pan_by(Vector2(-140, 0))
		KEY_D, KEY_RIGHT:
			_pan_by(Vector2(140, 0))
		KEY_W, KEY_UP:
			_pan_by(Vector2(0, -140))
		KEY_S, KEY_DOWN:
			_pan_by(Vector2(0, 140))
		KEY_BRACKETLEFT:
			_switch_slot(-1)
		KEY_BRACKETRIGHT:
			_switch_slot(1)
		KEY_1:
			_set_time_scale(1.0)
		KEY_2:
			_set_time_scale(60.0)
		KEY_3:
			_set_time_scale(600.0)
		KEY_4:
			_set_time_scale(3600.0)
		KEY_F5:
			_save_game()
			_toast("已存到第 %d 档。" % slot, Color(0.30, 0.26, 0.21))
		KEY_F9:
			if _load_game():
				_rebuild()
				_center_on_player()
				_toast("读到第 %d 档。" % slot, Color(0.30, 0.26, 0.21))
			else:
				_toast("第 %d 档是空的。" % slot, Color(0.62, 0.24, 0.18))


func _switch_slot(delta: int) -> void:
	_save_game()
	slot = ((slot - 1 + delta + 3) % 3) + 1
	if _load_game():
		_rebuild()
		_center_on_player()
		_toast("读到第 %d 档。" % slot, Color(0.30, 0.26, 0.21))
	else:
		_save_game()
		_toast("第 %d 档是空的，这一世已存进去。" % slot, Color(0.30, 0.26, 0.21))


func _pan_by(d: Vector2) -> void:
	cam = (cam + d).clamp(Vector2.ZERO, Vector2(WORLD_W - W, WORLD_H - H))
	queue_redraw()


func _center_on_player() -> void:
	cam = (player - Vector2(W * 0.5, H * 0.5)).clamp(Vector2.ZERO, Vector2(WORLD_W - W, WORLD_H - H))
	queue_redraw()


func _mm_rect() -> Rect2:
	return Rect2(W - MM_W - MM_MARGIN, 74.0, MM_W, MM_H)


func _cam_to_minimap(p: Vector2) -> void:
	var r := _mm_rect()
	var fx := clampf((p.x - r.position.x) / r.size.x, 0.0, 1.0)
	var fy := clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)
	var target := Vector2(fx * WORLD_W, fy * WORLD_H) - Vector2(W * 0.5, H * 0.5)
	cam = target.clamp(Vector2.ZERO, Vector2(WORLD_W - W, WORLD_H - H))
	queue_redraw()


func _npc_at(p: Vector2) -> Dictionary:
	for nv in npcs:
		var n: Dictionary = nv
		if not bool(n.get("named", false)):
			continue
		var pos: Vector2 = n["pos"]
		if absf(p.x - pos.x) < 24.0 and p.y > pos.y - 56.0 and p.y < pos.y + 12.0:
			return n
	return {}


func _find_npc(id: String) -> Dictionary:
	for n in npcs:
		if str(n.get("id", "")) == id:
			return n
	return {}


func _freeze_npc(id: String) -> void:
	for i in range(npcs.size()):
		var n: Dictionary = npcs[i]
		if str(n.get("id", "")) == id:
			n["wait"] = 9999.0
			npcs[i] = n


func _unfreeze_npc(id: String) -> void:
	for i in range(npcs.size()):
		var n: Dictionary = npcs[i]
		if str(n.get("id", "")) == id:
			n["wait"] = 0.0
			npcs[i] = n


func _start_walk(dest: Vector2) -> void:
	if not can_walk:
		return
	var d := Vector2(clampf(dest.x, 40.0, WORLD_W - 40.0), clampf(dest.y, 120.0, RIVER_Y - 12.0))
	path = _find_path(player, d)
	path_i = 0
	if path.is_empty():
		path = [d]
	moving = true


func walk_to(p: Vector2) -> void:
	pending_building = ""
	pending_npc = ""
	_start_walk(p)


func _building_at(p: Vector2) -> Dictionary:
	for b in buildings:
		if _footprint(b).has_point(p):
			return b
	return {}


func _footprint(b: Dictionary) -> Rect2:
	var pos: Vector2 = b["pos"]
	var w := float(b["w"])
	var h := float(b["h"])
	return Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h + 18.0)


func _door_of(b: Dictionary) -> Vector2:
	var pos: Vector2 = b["pos"]
	return Vector2(pos.x, pos.y + float(b["h"]) * 0.5 + 30.0)


func _by_id(id: String) -> Dictionary:
	for b in buildings:
		if str(b["id"]) == id:
			return b
	return {}


# ---------------------------------------------------------------- 更新

func _process(delta: float) -> void:
	t += delta
	hour = fmod(hour + delta * HOURS_PER_SEC, 24.0)
	# 时间自己往前走，不用玩家点；1× 时一年要七天，按流速加速
	if not ended and not busy:
		month_frac += delta * time_scale * 12.0 / SECONDS_PER_YEAR
		while month_frac >= 1.0:
			month_frac -= 1.0
			_advance_months(1)
	if not can_walk:
		var mom := _find_npc("mother")
		if not mom.is_empty():
			player = (mom["pos"] as Vector2) + Vector2(16, -6)
	_update_player(delta)
	_update_npcs(delta)
	if not toasts.is_empty():
		var keep: Array = []
		for item in toasts:
			var d: Dictionary = item
			d["life"] = float(d["life"]) - delta
			if float(d["life"]) > 0.0:
				keep.append(d)
		toasts = keep
	queue_redraw()


func _update_player(delta: float) -> void:
	if not moving:
		return
	if path_i >= path.size():
		_finish_walk()
		return
	var wp: Vector2 = path[path_i]
	var to := wp - player
	var dist := to.length()
	var step := 200.0 * delta
	if dist <= step:
		player = wp
		path_i += 1
		if path_i >= path.size():
			_finish_walk()
		return
	player += (to / dist) * step
	if absf(to.x) > 2.0:
		facing = signf(to.x)
	walk_phase += delta * 11.0
	step_sound_t -= delta
	if step_sound_t <= 0.0:
		step_sound_t = 0.46
		Sfx.play("step")


func _finish_walk() -> void:
	moving = false
	path.clear()
	path_i = 0
	if pending_npc != "":
		var nid := pending_npc
		pending_npc = ""
		_open_dialog_by_id(nid)
		return
	if pending_building != "":
		var id := pending_building
		pending_building = ""
		_open_panel(id)


func _father_trade_for(flags: Array) -> String:
	# 出身 flag → 父亲行当。数据里用的是「商贾」，历史代码曾写「商人」，两者都接受。
	if flags.has("匠人"):
		return "匠"
	if flags.has("商贾") or flags.has("商人"):
		return "商"
	if flags.has("军户"):
		return "兵"
	if flags.has("读书") or flags.has("士人"):
		return "吏"
	return "农"


func _spawn_npcs() -> void:
	npcs = []
	var r := RandomNumberGenerator.new()
	r.randomize()
	var father_line := "父亲蹲在门槛上修农具，头也不抬。"
	match father_trade:
		"匠":
			father_line = "父亲在院里刨木头，刨花卷成花，落了一地。"
		"商":
			father_line = "父亲在灯下算账，算盘珠子打得噼啪响。"
		"兵":
			father_line = "父亲在磨刀，一边磨一边看门外。"
		"吏":
			father_line = "父亲在灯下抄文书，笔尖沙沙响。"
	var mother_line := "母亲在灶下忙，看见你就笑。"
	match mother_temper:
		"严":
			mother_line = "母亲在院里晾衣，看见你就问：活干完了吗。"
		"病":
			mother_line = "母亲靠在床头，咳了两声，还是想起身给你做饭。"
	var cast := [
		{"id": "li_shen", "name": "李婶", "kind": 0, "home": Vector2(400, 648), "line": "她蹲在门口择菜，抬头看了你一眼。",
			"warm": "她把手在围裙上擦了擦，笑着招呼你进屋坐。",
			"cold": "她看见你，低下头继续择菜，当作没看见。"},
		{"id": "wang_xiucai", "name": "王秀才", "kind": 0, "home": Vector2(722, 546), "line": "他抱着一摞旧书，袖口磨破了。",
			"warm": "他把书往旁边挪了挪，给你腾出一个位置。",
			"cold": "他侧过身，把书抱得更紧了些。"},
		{"id": "zhang_tu", "name": "张屠户", "kind": 4, "home": Vector2(1224, 572), "line": "案板上还挂着半扇肉，他手上的刀没停。",
			"warm": "他切下一小块肉推过来：拿去，不算钱。",
			"cold": "他把刀往案板上一拍：今天不赊账。"},
		{"id": "lao_seng", "name": "老僧", "kind": 3, "home": Vector2(1644, 912), "line": "他扫地，扫得很慢，一下一下。"},
		{"id": "huo_lang", "name": "货郎", "kind": 1, "home": Vector2(1004, 852), "line": "担子两头挂着针线、糖人、小鼓。"},
		{"id": "li_zheng", "name": "里正", "kind": 4, "home": Vector2(1258, 862), "line": "他背着手站在井边，看谁家烟囱没冒烟。"},
		{"id": "wen_po", "name": "稳婆", "kind": 0, "home": Vector2(472, 754), "line": "她坐在门槛上搓麻绳，手很稳。"},
		{"id": "you_yi", "name": "游医", "kind": 3, "home": Vector2(1706, 1108), "line": "他摊开一块布，上面摆着二十几个纸包。"},
		{"id": "chuan_fu", "name": "船夫", "kind": 1, "home": Vector2(1656, 1372), "line": "他蹲在船头补网，头也不抬。"},
		{"id": "lao_shu", "name": "老塾师", "kind": 0, "home": Vector2(748, 492), "line": "他捧着书在槐树下打瞌睡，书翻在同一页。"},
		{"id": "mother", "name": mother_name, "kind": 0, "home": Vector2(372, 588), "line": mother_line,
			"warm": "母亲把手在围裙上擦了擦，蹲下来替你理衣领。",
			"cold": "母亲没抬头，只说了一句：饭在锅里。"},
		{"id": "father", "name": father_name, "kind": 4, "home": Vector2(296, 626), "line": father_line},
		{"id": "a_he", "name": "阿禾", "kind": 0, "home": Vector2(438, 636),
			"line": "她已经长成大姑娘了，见了你低头就走。",
			"line_child": "她蹲在地上用树枝画画，画的是两个小人。"},
		{"id": "shi_tou", "name": "石头", "kind": 4, "home": Vector2(246, 700),
			"line": "他跟着他爹学木匠去了，手上的茧比你还厚。",
			"line_child": "他鼻子上挂着两条虫，手里攥着一只蚂蚱。"},
	]
	for c in cast:
		var cc: Dictionary = c
		if str(cc["id"]) == pov:
			continue
		if str(cc["id"]) in ["father", "mother"] and bool(parent_dead.get(str(cc["id"]), false)):
			continue
		var home: Vector2 = cc["home"]
		var entry := {
			"id": str(cc["id"]), "name": str(cc["name"]), "named": true,
			"line": str(cc["line"]), "home": home,
			"pos": home, "target": home,
			"dir": 1.0, "speed": r.randf_range(14.0, 22.0),
			"kind": int(cc["kind"]), "phase": r.randf() * 6.28,
			"wait": r.randf_range(0.0, 2.0), "att": _get_att(str(cc["id"])),
			"build": BUILDS[absi(int(hash(str(cc["id"])))) % 4],
		}
		if cc.has("warm"):
			entry["warm"] = str(cc["warm"])
		if cc.has("cold"):
			entry["cold"] = str(cc["cold"])
		if cc.has("line_child"):
			entry["line_child"] = str(cc["line_child"])
		npcs.append(entry)
	if pov != "child":
		var kid_age := int((pov_state.get("child", {}) as Dictionary).get("age", 0))
		var kp := child_pos
		npcs.append({
			"id": "child", "name": name_text, "named": true,
			"line": "你的孩子，%s岁，正在院里玩。" % DB.cn(kid_age),
			"home": kp, "pos": kp, "target": kp, "dir": 1.0,
			"speed": 12.0, "kind": 0, "phase": r.randf() * 6.28,
			"wait": 0.0, "att": 0, "build": BUILDS[1],
		})
	var walker_kinds := [0, 1, 2, 3, 0, 1, 2, 4]
	for i in range(walker_kinds.size()):
		var p := Vector2(r.randf_range(500.0, 2700.0), r.randf_range(340.0, 1380.0))
		npcs.append({
			"id": "", "name": "", "named": false, "line": "", "home": p,
			"pos": p, "target": p, "dir": 1.0, "speed": r.randf_range(30.0, 54.0),
			"kind": int(walker_kinds[i % 4]), "phase": r.randf() * 6.28,
			"wait": r.randf_range(0.0, 2.5), "att": 0,
			"build": BUILDS[r.randi_range(0, 3)],
		})


func _spawn_special(id: String, npc_name: String, pos: Vector2, line: String) -> void:
	for n in npcs:
		if str(n.get("id", "")) == id:
			return
	npcs.append({
		"id": id, "name": npc_name, "named": true, "line": line,
		"home": pos, "pos": pos, "target": pos, "dir": 1.0,
		"speed": 0.0, "kind": 0, "phase": 0.0, "wait": 0.0, "att": _get_att(id),
	})


func _update_npcs(delta: float) -> void:
	for i in range(npcs.size()):
		var n: Dictionary = npcs[i]
		var pos: Vector2 = n["pos"]
		var tgt: Vector2 = n["target"]
		if float(n["wait"]) > 100.0:
			continue
		if float(n["wait"]) > 0.0:
			n["wait"] = float(n["wait"]) - delta
			npcs[i] = n
			continue
		var to := tgt - pos
		if to.length() < 8.0:
			var r := RandomNumberGenerator.new()
			r.randomize()
			if bool(n.get("named", false)):
				var home: Vector2 = n.get("home", pos)
				n["target"] = home + Vector2(r.randf_range(-150.0, 150.0), r.randf_range(-90.0, 90.0))
				n["wait"] = r.randf_range(2.0, 6.0)
			else:
				n["target"] = Vector2(r.randf_range(240.0, 2920.0), r.randf_range(300.0, 1440.0))
				n["wait"] = r.randf_range(1.0, 3.5)
			n["dir"] = 1.0 if r.randf() < 0.5 else -1.0
			npcs[i] = n
			continue
		var dirv := to.normalized()
		pos += dirv * float(n["speed"]) * delta
		if absf(dirv.x) > 0.05:
			n["dir"] = signf(dirv.x)
		n["pos"] = pos
		n["phase"] = float(n["phase"]) + delta * 8.0
		npcs[i] = n


# ---------------------------------------------------------------- 面板

func _build_panel() -> void:
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.965, 0.937, 0.878, 0.98)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.32, 0.26, 0.20, 0.45)
	sb.shadow_color = Color(0.15, 0.12, 0.09, 0.18)
	sb.shadow_size = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(700, 0)
	panel.position = Vector2(W * 0.5 - 350.0, 430.0)
	panel.visible = false
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	panel_title = UIKit.label("", 27, C_INK)
	head.add_child(panel_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close_btn := UIKit.ink_button("离 开", 100)
	close_btn.custom_minimum_size = Vector2(100, 36)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_close_panel)
	head.add_child(close_btn)

	panel_sub = UIKit.wrap_label("", 16, Color(0.42, 0.37, 0.30))
	panel_sub.custom_minimum_size = Vector2(640, 0)
	vb.add_child(panel_sub)
	vb.add_child(UIKit.hair())

	panel_actions = VBoxContainer.new()
	panel_actions.add_theme_constant_override("separation", 2)
	vb.add_child(panel_actions)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	vb.add_child(gap)
	panel_hint = UIKit.label("时间自己走（可在左下角调流速）　·　做事不花时间　·　过年过节会跳过一段", 14,
		Color(0.50, 0.45, 0.37))
	vb.add_child(panel_hint)


func _close_panel() -> void:
	panel.visible = false
	busy = false
	queue_redraw()


func _open_panel(id: String) -> void:
	var b := _by_id(id)
	if b.is_empty():
		return
	panel_title.text = str(b["name"])
	panel_sub.text = _panel_subtitle(id)
	for c in panel_actions.get_children():
		panel_actions.remove_child(c)
		c.queue_free()

	var need := int(MIN_AGE.get(id, 0))
	if age < need:
		var too_young := UIKit.choice("（等你长到%s岁再来）" % DB.cn(need))
		too_young.disabled = true
		panel_actions.add_child(too_young)
		panel.visible = true
		busy = true
		Sfx.play("open")
		_fit_panel()
		queue_redraw()
		return

	for a in _actions_for(id):
		var act: Dictionary = a
		var btn := UIKit.choice(_strip_time(str(act["label"])))
		if int(act.get("cost", 0)) > money:
			btn.disabled = true
			btn.text += "　—　钱不够"
		btn.pressed.connect(_on_action.bind(act))
		panel_actions.add_child(btn)

	panel.visible = true
	busy = true
	Sfx.play("open")
	_fit_panel()
	queue_redraw()


func _fit_panel() -> void:
	await get_tree().process_frame
	if panel == null or not panel.visible:
		return
	var max_y := H - 24.0 - panel.size.y
	panel.position.y = clampf(minf(430.0, max_y), 76.0, 700.0)


func debug_action(id: String, idx: int) -> void:
	_open_panel(id)
	var acts: Array = _actions_for(id)
	if idx >= 0 and idx < acts.size():
		_on_action(acts[idx])


func debug_dialog(id: String) -> void:
	_freeze_npc(id)
	_open_dialog_by_id(id)


func walk_to_npc(id: String) -> void:
	var n := _find_npc(id)
	if n.is_empty():
		return
	pending_building = ""
	pending_npc = id
	_freeze_npc(id)
	_start_walk((n["pos"] as Vector2) + Vector2(0, 42))


func debug_pick(id: String, idx: int) -> void:
	var chs: Array = _dialog_choices(id)
	if idx < chs.size():
		_on_dialog_choice(chs[idx], id)
	print("[DIALOG] id=", id, " married=", married, " money=", money, " story=", story, " age=", age)


func debug_shop_run() -> void:
	print("[SHOP] 初始 money=", money, " stock=", shop.get("stock", 0), " 定价=", _price_word())
	_on_action(_actions_for("shop")[0])
	print("[SHOP] 进货后 money=", money, " stock=", shop.get("stock", 0))
	shop["price"] = 0
	shop["helper"] = true
	_on_action(_actions_for("shop")[2])
	print("[SHOP] 营业后 money=", money, " stock=", shop.get("stock", 0),
		" 行情=", shop.get("market", 1.0), " age=", age)
	shop["price"] = 2
	_on_action(_actions_for("shop")[0])
	_on_action(_actions_for("shop")[2])
	print("[SHOP] 贵卖后 money=", money, " stock=", shop.get("stock", 0))


func _open_dialog_by_id(id: String) -> void:
	var n := _find_npc(id)
	if n.is_empty():
		return
	panel_title.text = str(n.get("name", ""))
	panel_sub.text = _dialog_line(n)
	for c in panel_actions.get_children():
		panel_actions.remove_child(c)
		c.queue_free()
	var shown := 0
	for a in _dialog_choices(id):
		var ch: Dictionary = a
		if ch.has("once") and story.has(str(ch["once"])):
			continue
		var btn := UIKit.choice(_strip_time(str(ch["label"])))
		if int(ch.get("cost", 0)) > money:
			btn.disabled = true
			btn.text += "　—　钱不够"
		btn.pressed.connect(_on_dialog_choice.bind(ch, id))
		panel_actions.add_child(btn)
		shown += 1
	if shown == 0:
		var btn2 := UIKit.choice("（没什么可说的了）")
		btn2.disabled = true
		panel_actions.add_child(btn2)
	panel.visible = true
	busy = true
	Sfx.play("open")
	_fit_panel()
	queue_redraw()


func _on_dialog_choice(ch: Dictionary, id: String) -> void:
	var cost := int(ch.get("cost", 0))
	if cost > money:
		_toast("钱不够。", Color(0.62, 0.24, 0.18))
		return
	# M1-02：对话与地点行动共用同一套冷却结算，且都不再推进月份
	if not _cooldown_ready(str(ch.get("label", ""))):
		return
	money -= cost
	if ch.has("once"):
		story[str(ch["once"])] = true
	if ch.has("flag"):
		story[str(ch["flag"])] = true
	if ch.has("gain"):
		_apply_gain(ch["gain"])
	if ch.has("att"):
		_set_att(id, _get_att(id) + int(ch["att"]))
	if ch.has("special"):
		_apply_special(str(ch["special"]))
	panel.visible = false
	busy = false
	_unfreeze_npc(id)
	_cooldown_commit(str(ch.get("label", "")), int(ch.get("months", 1)))
	# M1-02：对话不再额外推进月份，时间由世界钟与节令推进
	if ch.has("result"):
		_toast(str(ch["result"]), Color(0.30, 0.26, 0.21))
	Sfx.play("ok")
	_save_game()
	queue_redraw()
	if age >= lifespan or health <= 0.0:
		if pov == "child":
			_ending()
		else:
			_parent_death()


func _parent_death() -> void:
	var who := pov
	var nm := father_name if who == "father" else mother_name
	var p_age := age
	var kid_age := int((pov_state.get("child", {}) as Dictionary).get("age", 0))
	parents_alive = maxi(0, parents_alive - 1)
	# A03：用 alive/death_record 表示死亡，不再靠删除人物实体
	parent_dead[who] = true
	parent_death_year[who] = year
	_log_fact("death", "old_age", {"who": who, "age": p_age})
	_switch_pov("child")
	_spawn_npcs()
	_refresh_pov_bar()
	var lines: Array = [
		"%s年，%s走了，年%s。" % [DB.era_label(year), nm, DB.cn(p_age)],
	]
	if kid_age < 8:
		lines.append("你还不懂死是什么，只觉得屋里忽然很静。")
	else:
		lines.append("你在灵前站了很久，忽然想起他教你做的第一件事。")
	lines.append("从此这个家，要你自己撑了。")
	_play_cutscene("%s · 卒" % nm, lines, false)


func _pov_name() -> String:
	match pov:
		"father":
			return father_name
		"mother":
			return mother_name
	return name_text


func _dialog_line(n: Dictionary) -> String:
	var a := int(n.get("att", 0))
	if age < 12 and n.has("line_child"):
		return str(n["line_child"])
	if a >= 15 and n.has("warm"):
		return str(n["warm"])
	if a <= -15 and n.has("cold"):
		return str(n["cold"])
	return str(n.get("line", ""))


func _set_att(id: String, v: int) -> void:
	# M1-01a：关系存在 WorldState（relations），场景里的 NPC 只是显示
	relations[id] = v
	for i in range(npcs.size()):
		if str(npcs[i].get("id", "")) == id:
			npcs[i]["att"] = v


func _get_att(id: String) -> int:
	return int(relations.get(id, 0))


func _meat_price() -> int:
	return int(round(80.0 * clampf(1.0 - float(_get_att("zhang_tu")) / 250.0, 0.65, 1.35)))


func _dialog_choices(id: String) -> Array:
	match id:
		"a_he":
			if age < 12:
				return [
					{"label": "一起去河边（三个月）", "months": 3, "gain": {"health": 1, "fame": 1}, "att": 4,
						"flag": "河边",
						"result": "你们在浅水里摸鱼。她摸到一条，看了半天，又放了。"},
					{"label": "看她画画（一个月）", "months": 1, "gain": {"learning": 1}, "att": 2,
						"result": "她画得很好，就是不肯给你看。"},
				]
			return [
				{"label": "打个招呼（一个月）", "months": 1, "gain": {"fame": 1}, "att": 2,
					"result": "她低着头应了一声，走得很快。"},
			]
		"shi_tou":
			if age < 12:
				return [
					{"label": "掏鸟窝（三个月）", "months": 3, "gain": {"craft": 1, "health": -1}, "att": 3,
						"result": "窝里没有蛋，只有几根草。你从树上滑下来，蹭破了手。"},
					{"label": "斗草（一个月）", "months": 1, "gain": {"fame": 1}, "att": 2,
						"result": "他的草茎断了，不服气，说明天再来。"},
				]
			return [
				{"label": "问他木匠活（三个月）", "months": 3, "gain": {"craft": 1}, "att": 2,
					"result": "他把刨花卷起来给你看，说这叫「花」。"},
			]
		"child":
			return [
				{"label": "换回来，做你自己", "months": 0, "special": "pov_child",
					"result": "你回到自己的身体里，好像刚睡醒。"},
			]
		"mother":
			var macts: Array = []
			if pov == "child":
				macts.append({"label": "接过母亲的日子（切换视角）", "months": 0, "special": "pov_mother"})
			if age < 6:
				macts.append({"label": "要她抱一抱", "months": 0, "once": "抱%d" % age,
					"gain": {"health": 1}, "att": 3,
					"result": "她把你抱起来，身上有一股皂角味。"})
			else:
				macts.append({"label": "陪她说说话（三个月）", "months": 3, "gain": {"health": 1, "fame": 1}, "att": 3,
					"result": "她讲起你小时候的事，讲着讲着自己笑了。"})
				macts.append({"label": "给她添件衣裳（三个月，四百文）", "months": 3, "cost": 400,
					"gain": {"fame": 2}, "att": 5,
					"result": "她嘴上说浪费，第二天就穿上了。"})
			return macts
		"father":
			var facts: Array = []
			if pov == "child":
				facts.append({"label": "接过父亲的日子（切换视角）", "months": 0, "special": "pov_father"})
			if age < 6:
				facts.append({"label": "看他做活", "months": 0, "once": "看%d" % age,
					"gain": {"craft": 1}, "att": 2,
					"result": "他不说话，你能看一下午。"})
			else:
				facts.append({"label": "跟他下地（半年）", "months": 6, "gain": {"health": 2, "craft": 1}, "att": 3,
					"result": "他教你分辨稗子和稻，说错一次敲一下你的手。"})
				facts.append({"label": "问他外头的事（一个月）", "months": 1, "gain": {"learning": 1}, "att": 1,
					"result": "他说县里在修桥，说北边又不太平。"})
			return facts
		"li_shen":
			var laacts: Array = [
				{"label": "讨碗水喝（一个月）", "months": 1, "gain": {"health": 1}, "att": 2,
					"result": "她舀了一瓢，还塞给你半个饼。"},
				{"label": "帮她把水缸挑满（一个月）", "months": 1, "gain": {"fame": 2, "health": -1}, "att": 5,
					"result": "她逢人就说：那孩子实诚。"},
				{"label": "借二斗米（一次）", "once": "borrow_li", "months": 1,
					"gain": {"money": 600}, "att": -3, "flag": "欠李婶",
					"result": "她说：秋后还啊。你点了头。"},
			]
			if _get_att("li_shen") >= 15 and not story.has("li_gift"):
				laacts.append({"label": "她塞给你一篮鸡蛋（一次）", "once": "li_gift", "months": 1,
					"gain": {"money": 300, "health": 2}, "att": 2,
					"result": "她说：自家鸡下的，拿着。你别推。"})
			return laacts
		"wang_xiucai":
			return [
				{"label": "借一本《孟子》（三个月）", "once": "borrow_book", "months": 3,
					"gain": {"learning": 3}, "att": 3, "flag": "借书",
					"result": "他把书递过来，又叮嘱了三遍别弄脏。"},
				{"label": "帮他抄两天书（两个月）", "months": 2,
					"gain": {"money": 300, "learning": 1}, "att": 2,
					"result": "他嫌你的字丑，还是给了钱。"},
				{"label": "问他考了几回", "months": 1, "att": 1,
					"result": "他笑了笑：六回。然后又笑了笑。"},
			]
		"zhang_tu":
			var meat_price := _meat_price()
			return [
				{"label": "买半斤肉（一个月，%d 文）" % meat_price, "months": 1, "cost": meat_price,
					"gain": {"health": 3}, "result": "他手起刀落，肉切得方方正正。"},
				{"label": "赊一斤（一次）", "once": "credit_meat", "months": 1,
					"gain": {"health": 2}, "flag": "欠肉钱", "result": "他抹了把刀：记着啊。"},
				{"label": "听他说行情（一个月）", "months": 1, "gain": {"learning": 1, "fame": 1},
					"result": "他说今年猪贵，米贱，盐要涨。"},
			]
		"lao_seng":
			return [
				{"label": "问他因果", "months": 1, "gain": {"health": 1},
					"result": "他说：你今日问，便是因。"},
				{"label": "帮他扫一夜地（一个月）", "months": 1,
					"gain": {"fame": 3, "health": -1}, "att": 5,
					"result": "天亮时他递给你一碗粥，什么都没说。"},
			]
		"huo_lang":
			return [
				{"label": "买一只糖人（二十文）", "months": 1, "cost": 20,
					"gain": {"fame": 1}, "result": "糖人是个骑马的将军，你舍不得吃。"},
				{"label": "听他说外头的事（一个月）", "months": 1,
					"gain": {"learning": 2, "fame": 2},
					"result": "他说汴京的夜市能开到三更，说的时候眼睛发亮。"},
			]
		"li_zheng":
			return [
				{"label": "交今年的丁钱（一季，四百文）", "months": 3, "cost": 400,
					"gain": {"fame": 3}, "flag": "交丁",
					"result": "他在簿子上打了个勾，说：你家还算明白。"},
				{"label": "替他说合一桩邻里纠纷（一个月）", "months": 1,
					"gain": {"fame": 5}, "result": "两家各让一步，他送你出门时说：会办事。"},
				{"label": "打听村里的风声（一个月）", "months": 1,
					"gain": {"learning": 1, "fame": 1},
					"result": "他说西头要修桥，说上头要来人查账。"},
			]
		"wen_po":
			return [
				{"label": "问她生养的事（一个月）", "months": 1, "gain": {"health": 2},
					"result": "她说：女人生孩子是过鬼门关，男人要在外头守着。"},
				{"label": "请她去照看产妇（三个月，五百文）", "months": 3, "cost": 500,
					"gain": {"fame": 4}, "result": "她接了钱，揣进袖子里，说：放心。"},
			]
		"you_yi":
			return [
				{"label": "抓一副药（一个月，三百文）", "months": 1, "cost": 300,
					"gain": {"health": 6}, "result": "药很苦，他多给了你两颗蜜枣。"},
				{"label": "跟他认药（半年）", "months": 6, "gain": {"craft": 3, "learning": 1},
					"result": "你记住了甘草、陈皮、半夏，还有两味有毒的。"},
				{"label": "听他讲疫病（一个月）", "months": 1, "gain": {"learning": 2},
					"result": "他说：病不是天上掉下来的，是水里来的。"},
			]
		"chuan_fu":
			return [
				{"label": "搭船去下游（一个月，五十文）", "months": 1, "cost": 50,
					"gain": {"learning": 1, "fame": 2}, "result": "下游有个镇子，比村里热闹十倍。"},
				{"label": "听他说水路的消息（一个月）", "months": 1, "gain": {"fame": 2},
					"result": "他说上游涨水，说有一船盐翻了，说衙门在查。"},
			]
		"lao_shu":
			return [
				{"label": "求他讲一章（一个月，一百文）", "months": 1, "cost": 100,
					"gain": {"learning": 4}, "result": "他讲《孟子》，讲到「民为贵」时停了停。"},
				{"label": "替他抄书（三个月）", "months": 3, "gain": {"money": 400, "learning": 2},
					"result": "他挑出你三个错字，用朱笔圈了。"},
			]
		"meiren":
			return [
				{"label": "应下这门亲事（三贯聘礼）", "months": 3, "cost": 3000,
					"gain": {"fame": 4}, "special": "marry", "att": 3,
					"result": "她笑得合不拢嘴：这才是懂事的孩子。"},
				{"label": "再等两年", "months": 1,
					"result": "她撇了撇嘴：错过了可别怨我。"},
			]
		"zhaizhu":
			return [
				{"label": "还清三贯", "months": 1, "cost": 3000,
					"special": "pay_debt", "result": "他把账划了，说：以后别再借了。"},
				{"label": "赖账", "months": 1, "special": "refuse_debt",
					"gain": {"fame": -6}, "result": "他在街上骂了半个时辰，全村都听见了。"},
				{"label": "求他宽限三个月", "months": 1, "special": "delay_debt",
					"result": "他哼了一声：三个月后利滚利。"},
			]
	return []


func _panel_subtitle(id: String) -> String:
	match id:
		"home":
			return "屋三间，灶上一口锅。母亲在院里晒东西。"
		"school":
			return "周先生坐馆授徒，一年束脩一千二百文，管一顿午饭。"
		"market":
			return "街面上人来人往，行市一日三变。"
		"field":
			return "田里的活计最实在，也最磨人。"
		"academy":
			return "山长是有出身的人，进门先要递帖子。"
		"temple":
			return "香火不断。殿前的石阶被跪得发亮。"
		"yamen":
			return "门房坐着个打瞌睡的差役，鼓在一边，没人敲。"
		"teahouse":
			return "几张旧桌子，一壶粗茶三文。南来北往的话都在这儿过一遍。"
		"pharmacy":
			return "药柜从地一直顶到梁，抽屉上写着名字，有些字你不认得。"
		"shrine":
			return "族里供着十几块牌位。族谱压在供桌下的木匣里。"
		"smithy":
			return "炉火烧了一整天，铁腥味顺着街飘出很远。"
		"tavern":
			return "酒旗挑在门口，里头总有人在划拳，输了的罚一碗。"
		"pawnshop":
			return "柜台高得看不到里头，掌柜坐在后头，眼睛比你高一个头。"
		"washe":
			return "勾栏里正演着傀儡戏，外头围了三层人，孩子骑在大人肩上。"
		"mulberry":
			return "桑树成行，叶子被摘得只剩顶上几片。"
		"dye":
			return "院子里挂满刚染好的布，蓝的、赭的、黑的，风一吹都在动。"
		"inn":
			return "门口拴着两头驴，堂里坐满了赶路的人。"
		"drill":
			return "校场上立着十几个草人，边上有杆旗，风大的时候呼啦作响。"
		"grave":
			return "几十个土堆，有的立了碑，有的只有一个记号。柏树长得很高。"
		"garden":
			return "四畦菜，两畦是青菜，两畦是萝卜。篱笆上爬着豆角。"
		"thresh":
			return "场院压得平平的，边上堆着草垛，石碾子还在。"
		"dock":
			return "船靠了岸，脚夫扛着包上上下下，河风腥得很。"
		"lot":
			return "村口有一块空地，原先是个塌了的茶棚。牙人说，盘下来不难。"
		"shop":
			return _shop_summary()
	return ""


func _actions_for(id: String) -> Array:
	match id:
		"home":
			var hacts: Array = []
			var sc := _due_scene()
			if not sc.is_empty():
				hacts.append({"label": "过%s（跳过一段时日）" % str(sc["name"]), "months": 0,
					"special": "scene"})
			if age < 6 and pov == "child":
				hacts.append({"label": "跟着父母过日子（一年）", "months": 12, "cost": 0,
					"special": "child_year"})
				return hacts
			if pov == "mother":
				for a in _mother_home_actions():
					hacts.append(a)
				return hacts
			hacts.append({"label": "歇一阵子", "months": 3, "cost": 0,
				"gain": {"health": 3}, "flavor": "你在院里晒了三个月太阳，什么都没做。"})
			hacts.append({"label": "陪家人说说话", "months": 3, "cost": 0,
				"gain": {"fame": 1, "health": 1}, "flavor": "母亲说了许多你小时候的事，你都记不得。"})
			return hacts
		"school":
			return [
				{"label": "读一年书（束脩一千二百文）", "months": 12, "cost": 1200,
					"gain": {"learning": 9}, "flag": "读书", "flavor": "一年下来，《论语》能背一半了。"},
				{"label": "替书铺抄书（半年）", "months": 6, "cost": 0,
					"gain": {"learning": 2, "money": 800}, "req": {"learning": 10.0},
					"flavor": "抄书换钱，字也练了。"},
			]
		"field":
			var facts: Array = []
			if farm_rank == 0:
				facts.append({"label": "跟东家租田来种（一年，押租八百）", "months": 12,
					"cost": 800, "special": "farm_rent"})
			if farm_rank >= 1:
				facts.append({"label": "佃种（一年）", "months": 12, "cost": 0,
					"gain": {"money": 2800, "health": -9},
					"flavor": "一年到头，交了租，剩下的刚够吃。"})
			if farm_rank >= 2:
				facts.append({"label": "耕种自家的田（一年）", "months": 12, "cost": 0,
					"special": "farm_till"})
			if farm_rank >= 3:
				facts.append({"label": "收租（一年）", "months": 12, "cost": 0,
					"special": "farm_collect"})
			if farm_rank >= 4:
				facts.append({"label": "修一条水渠（一年，六贯）", "months": 12, "cost": 6000,
					"gain": {"fame": 12},
					"flavor": "渠成那天，下游十几户人家来给你磕头。"})
			if farm_rank >= 1:
				facts.append({"label": "买一亩田（%d 文）" % _land_price(), "months": 3,
					"cost": _land_price(), "special": "farm_buy"})
			facts.append({"label": "给东家帮工（半年）", "months": 6, "cost": 0,
				"gain": {"money": 1700, "health": -3}, "flavor": "腰酸了半年，工钱结得还算爽快。"})
			return facts
		"market":
			var macts: Array = []
			if trade_rank == 0:
				macts.append({"label": "摆个小摊（一个月，本钱两百文）", "months": 1, "cost": 200,
					"special": "stall"})
			if trade_rank >= 1:
				macts.append({"label": "跟商队跑一趟（一年，本钱一贯）", "months": 12, "cost": 1000,
					"special": "caravan"})
			if trade_rank == 1 and shop_open and money >= 20000:
				macts.append({"label": "正式坐贾（半年，有声望的门面）", "months": 6,
					"special": "sedentary"})
			if trade_rank == 2 and money >= 50000 and fame >= 40.0:
				macts.append({"label": "入行会（一季，十贯）", "months": 3, "cost": 10000,
					"special": "guild"})
			if trade_rank >= 3:
				macts.append({"label": "议一年的行价（一个月）", "months": 1, "special": "set_price"})
			macts.append({"label": "在铺子里做工（半年）", "months": 6, "cost": 0,
				"gain": {"money": 1500, "craft": 1}, "flavor": "掌柜说你手脚还算麻利。"})
			macts.append({"label": "打听消息（一个月）", "months": 1, "cost": 100,
				"gain": {"fame": 2}, "flavor": "你在茶棚里坐了一个月，听了一肚子话。"})
			return macts
		"academy":
			var acts: Array = []
			var exam_year := _is_exam_year()
			var can_jie := exam_year and not story.has("举人") and not story.has("进士") and learning >= 25.0 and age >= 15 and age <= 42
			var can_sheng := exam_year and story.has("举人") and not story.has("进士") and learning >= 42.0 and age >= 18 and age <= 45
			if can_jie:
				acts.append({"label": "应解试（今年开科，八百文）", "months": 3, "cost": 800,
					"special": "jieshi"})
			elif can_sheng:
				acts.append({"label": "应省试（进京，一年，三千文）", "months": 12, "cost": 3000,
					"special": "shengshi"})
			acts.append({"label": "在书院读经（一年，两千文）", "months": 12, "cost": 2000,
				"gain": {"learning": 13, "fame": 2}, "flag": "读书",
				"flavor": "山长讲《春秋》，一堂课下来，你手心出汗。"})
			if story.has("举人") and not story.has("进士"):
				acts.append({"label": "温书备考（一年，八百文）", "months": 12, "cost": 800,
					"gain": {"learning": 7}, "flavor": "把旧卷子翻了三遍，页脚都卷了。"})
			acts.append({"label": "替山长校书（半年）", "months": 6, "cost": 0,
				"gain": {"learning": 5, "craft": 1}, "req": {"learning": 25.0},
				"flavor": "校出三处错字，山长看了你一眼。"})
			acts.append({"label": "拜一位先生（三个月，三千文）", "months": 3, "cost": 3000,
				"gain": {"learning": 4, "fame": 6}, "flag": "读书",
				"flavor": "你递了帖子，磕了头。先生说：往后每月来两回。"})
			return acts
		"temple":
			return [
				{"label": "上香（一个月，一百文）", "months": 1, "cost": 100,
					"gain": {"health": 2, "fame": 1}, "flavor": "香灰落在手背上，有一点烫。"},
				{"label": "施粥（三个月，一千文）", "months": 3, "cost": 1000,
					"gain": {"fame": 7}, "flavor": "粥棚前排了三十几个人，有孩子，也有老人。"},
				{"label": "替庙里抄经（半年）", "months": 6, "cost": 0,
					"gain": {"learning": 3, "fame": 3}, "flavor": "抄到「一切有为法」，窗外下了雪。"},
			]
		"yamen":
			var yacts: Array = []
			if story.has("进士") and office_rank == 0:
				yacts.append({"label": "赴任（半年）", "months": 6, "special": "take_post"})
			if office_rank >= 1:
				yacts.append({"label": "秉公断案（半年）", "months": 6, "special": "judge_fair"})
				yacts.append({"label": "收一笔贿（半年）", "months": 6, "special": "judge_bribe"})
				yacts.append({"label": "下乡劝农（半年）", "months": 6,
					"gain": {"fame": 2, "health": -3}, "special": "gov_farm"})
			if office_rank >= 1 and office_rank < 3 and gov_merit >= _promote_need():
				yacts.append({"label": "考绩升迁（三个月）", "months": 3, "special": "promote"})
			if office_rank >= 1 and not story.has("致仕"):
				yacts.append({"label": "告老还乡（三个月）", "months": 3, "special": "retire"})
			yacts.append({"label": "看衙门口贴的告示（一个月）", "months": 1, "cost": 0,
				"gain": {"learning": 1}, "flavor": "告示上的字你都认得，可有些话绕得很。"})
			yacts.append({"label": "递一张状子（一个月，五百文）", "months": 1, "cost": 500,
				"gain": {"fame": 2}, "flavor": "状子递进去，石沉大海。门房说：等着。"})
			yacts.append({"label": "在衙门应差（半年）", "months": 6, "cost": 0,
				"gain": {"money": 1200, "fame": 3}, "flavor": "抄了半年的文书，认得了几个书吏的脸。"})
			return yacts
		"teahouse":
			return [
				{"label": "喝一壶茶（一个月，五十文）", "months": 1, "cost": 50,
					"gain": {"health": 2, "fame": 1}, "flavor": "茶博士续了三回水，你听了一下午的闲话。"},
				{"label": "听人说书（一个月，三十文）", "months": 1, "cost": 30,
					"gain": {"fame": 2}, "flavor": "说的是一段杨家将，说到一半，说书的收钱去了。"},
			]
		"pharmacy":
			var pacts: Array = []
			if med_rank == 0:
				pacts.append({"label": "拜师学医（三个月，六百文）", "months": 3, "cost": 600,
					"special": "med_apprentice"})
			if med_rank >= 1:
				pacts.append({"label": "在药铺帮工（半年）", "months": 6, "cost": 0,
					"gain": {"money": 1000, "medicine": 2},
					"flavor": "你认得了三十几味药，记住了两味有毒。"})
				pacts.append({"label": "跟着师父认药（半年）", "months": 6, "cost": 0,
					"gain": {"medicine": 5, "learning": 1},
					"flavor": "师父把药柜拉开一格一格讲，讲到「附子」时停了停。"})
			if med_rank == 1 and medicine >= 35.0:
				pacts.append({"label": "出师，自立门户（三个月）", "months": 3, "special": "med_journeyman"})
			if med_rank >= 2:
				pacts.append({"label": "出诊（半年，有风险）", "months": 6, "special": "med_visit"})
			if med_rank == 2 and medicine >= 60.0 and fame >= 30.0:
				pacts.append({"label": "在药铺坐堂（三个月）", "months": 3, "special": "med_clinic"})
			if med_rank >= 3:
				pacts.append({"label": "坐堂问诊（一年）", "months": 12, "cost": 0,
					"gain": {"money": 4200, "fame": 6, "medicine": 1},
					"flavor": "一年下来，门口排的队比药铺的本行还长。"})
			if med_rank == 3 and medicine >= 85.0 and fame >= 55.0:
				pacts.append({"label": "著一部方书（一年）", "months": 12, "special": "med_book"})
			pacts.append({"label": "抓一副药（一个月，三百文）", "months": 1, "cost": 300,
				"gain": {"health": 6}, "flavor": "药很苦，掌柜多送了你两颗蜜枣。"})
			return pacts
		"shrine":
			return [
				{"label": "祭祖（一个月，两百文）", "months": 1, "cost": 200,
					"gain": {"fame": 3, "health": 1}, "flavor": "香点着了，族里的老人念了你的名字。"},
				{"label": "替族里抄族谱（半年）", "months": 6, "cost": 0,
					"gain": {"learning": 2, "fame": 4}, "flavor": "你看见了自己父亲的名字，写在祖父下面。"},
			]
		"grave":
			var gacts: Array = [
				{"label": "扫墓（一个月，一百文）", "months": 1, "cost": 100,
					"gain": {"fame": 2, "health": 1}, "flavor": "你把坟头的草拔了，压了三张纸。"},
				{"label": "在坟地坐一会儿（一个月）", "months": 1, "cost": 0,
					"gain": {"health": 1}, "flavor": "柏树上有鸟叫，你想起一些记不清的事。"},
			]
			if parents_alive <= 0:
				gacts.append({"label": "祭父母（三个月，三百文）", "months": 3, "cost": 300,
					"gain": {"fame": 4, "health": 2}, "flag": "祭过",
					"flavor": "你摆了酒，说了很多话。走的时候没有回头。"})
			return gacts
		"garden":
			return [
				{"label": "种一畦菜（半年）", "months": 6, "cost": 0,
					"gain": {"money": 400, "health": 1}, "flavor": "萝卜长得不好，青菜倒是旺。"},
				{"label": "挑菜去市集卖（三个月）", "months": 3, "cost": 0,
					"gain": {"money": 600, "health": -2}, "flavor": "两筐菜卖了一整天，剩了半筐。"},
			]
		"thresh":
			return [
				{"label": "帮人打谷（半年）", "months": 6, "cost": 0,
					"gain": {"money": 1200, "health": -4}, "flavor": "连枷抡了半年，胳膊抬不起来。"},
				{"label": "晒粮（三个月）", "months": 3, "cost": 0,
					"gain": {"money": 700, "health": -1}, "flavor": "你守着场院，赶了两回麻雀。"},
			]
		"drill":
			var dacts: Array = []
			if mil_rank == 0:
				dacts.append({"label": "应募从军（三个月）", "months": 3, "special": "enlist"})
			if mil_rank == 1:
				dacts.append({"label": "操练（半年）", "months": 6, "gain": {"money": 500, "health": 2},
					"flavor": "半年下来，能拉开一石弓了。"})
				dacts.append({"label": "随军出征（一年，会死人）", "months": 12, "special": "expedition"})
			if mil_rank == 1 and merit >= 2 and health >= 55.0:
				dacts.append({"label": "升作厢军（三个月）", "months": 3, "special": "promote_nco"})
			if mil_rank == 2:
				dacts.append({"label": "随大军出征（一年，会死人）", "months": 12, "special": "expedition2"})
			if mil_rank == 2 and merit >= 5 and fame >= 40.0:
				dacts.append({"label": "授军官（三个月）", "months": 3, "special": "promote_officer"})
			if mil_rank >= 3:
				dacts.append({"label": "带兵巡边（一年，有风险）", "months": 12, "special": "patrol"})
			dacts.append({"label": "在校场看人操练（一个月）", "months": 1,
				"gain": {"fame": 1}, "flavor": "草人被扎得全是窟窿，边上的老卒说：打仗不是这么打的。"})
			return dacts
		"dock":
			return [
				{"label": "在码头上扛包（半年）", "months": 6, "cost": 0,
					"gain": {"money": 1600, "health": -5}, "flavor": "一天扛八十包，晚上手抖得端不住碗。"},
				{"label": "搭船出去闯一年", "months": 12, "cost": 800,
					"gain": {"money": 4200, "fame": 3, "health": -4}, "flavor": "船到杭州，你看见了两层楼的酒肆。"},
				{"label": "在船头听人说话（一个月）", "months": 1, "cost": 0,
					"gain": {"fame": 1, "learning": 1}, "flavor": "南来北往的口音，你学了两句。"},
			]
		"smithy":
			var sacts: Array = []
			if craft_rank == 0:
				var fee := 600
				if _is_craft_family():
					fee = 300
				elif story.has("读书"):
					fee = 1200
				sacts.append({"label": "拜师学手艺（三个月，%d 文）" % fee, "months": 3,
					"cost": fee, "special": "apprentice",
					"flavor": "师父先让你看了三个月火，什么也没教。"})
			if craft_rank == 1:
				sacts.append({"label": "在铺里帮工（半年）", "months": 6,
					"gain": {"money": 1000, "craft": 2, "health": -3},
					"flavor": "半年下来，两条胳膊粗了一圈。"})
			if craft_rank == 1 and craft >= 40.0:
				sacts.append({"label": "出师（三个月）", "months": 3, "special": "journeyman"})
			if craft_rank >= 2:
				sacts.append({"label": "接一单营造（半年）", "months": 6,
					"gain": {"money": 2600, "craft": 2, "health": -5},
					"flavor": "给邻村盖祠堂，梁架上了那天，主家请你坐上席。"})
			if craft_rank == 2 and craft >= 55.0 and apprentice_hired < 2:
				sacts.append({"label": "收一个徒弟（三个月）", "months": 3, "special": "take_apprentice"})
			if craft_rank == 2 and craft >= 68.0 and money >= 8000:
				sacts.append({"label": "盘一间作坊（八贯，一年）", "months": 12,
					"cost": 8000, "special": "workshop"})
			if craft_rank >= 3:
				sacts.append({"label": "接官府的营造（一年）", "months": 12,
					"gain": {"money": 6000, "fame": 6, "health": -6},
					"flavor": "修的是学宫，监工的是通判。他挑不出错，脸色不太好看。"})
			sacts.append({"label": "打一把柴刀（一年，八百文）", "months": 12, "cost": 800,
				"gain": {"craft": 4, "fame": 2, "health": -2}, "flavor": "刀口淬了三回水，师父点头说：能用。"})
			return sacts
		"tavern":
			return [
				{"label": "喝一碗酒（一个月，六十文）", "months": 1, "cost": 60,
					"gain": {"health": 1, "fame": 2}, "flavor": "酒很烈，下肚像吞了一小团火。"},
				{"label": "听人划拳吹牛（一个月）", "months": 1, "cost": 0,
					"gain": {"fame": 1, "learning": 1}, "flavor": "有人说他见过海船，有人说他打过西夏。"},
				{"label": "替酒肆送一趟货（两个月）", "months": 2, "cost": 0,
					"gain": {"money": 500, "health": -2}, "flavor": "两坛酒挑到邻村，回来时肩膀磨红了。"},
			]
		"pawnshop":
			return [
				{"label": "典一件旧衣（一个月）", "months": 1, "cost": 0,
					"gain": {"money": 800, "fame": -2}, "flavor": "掌柜把衣裳抖开看了看，给了个不高不低的价。"},
				{"label": "把东西赎回来（三个月，一千文）", "months": 3, "cost": 1000,
					"gain": {"fame": 2}, "flavor": "衣裳上多了股霉味，但到底是自己的。"},
			]
		"washe":
			return [
				{"label": "听一曲（一个月，一百文）", "months": 1, "cost": 100,
					"gain": {"fame": 3, "health": 1}, "flavor": "唱的是《雨霖铃》，唱到一半有人叫好，有人抹眼泪。"},
				{"label": "看傀儡戏（一个月，五十文）", "months": 1, "cost": 50,
					"gain": {"fame": 2}, "flavor": "木头人打了三十个回合，最後还是好人赢了。"},
			]
		"mulberry":
			return [
				{"label": "采桑叶（半年）", "months": 6, "cost": 0,
					"gain": {"money": 900, "health": -2}, "flavor": "叶子要挑嫩的采，手指被汁水染成青色。"},
				{"label": "养一季蚕（一年）", "months": 12, "cost": 0,
					"gain": {"money": 1700, "craft": 2, "health": -3}, "flavor": "蚕上山那几天，你夜里要起来两回。"},
			]
		"dye":
			return [
				{"label": "在染坊帮工（半年）", "months": 6, "cost": 0,
					"gain": {"money": 1300, "craft": 2, "health": -2}, "flavor": "手上染的色，三个月都没洗掉。"},
				{"label": "染一匹自家的布（一年，六百文）", "months": 12, "cost": 600,
					"gain": {"craft": 4, "fame": 2}, "flavor": "蓝草要浸七遍，你守了七个通夜。"},
			]
		"inn":
			return [
				{"label": "在客栈帮工（半年）", "months": 6, "cost": 0,
					"gain": {"money": 1200, "fame": 1}, "flavor": "端了半年的盘子，认得了十几种口音。"},
				{"label": "听客人说话（一个月）", "months": 1, "cost": 0,
					"gain": {"learning": 2, "fame": 1}, "flavor": "有人说北边在打仗，有人说京城米价又涨了。"},
			]
		"lot":
			return [
				{"label": "盘一间包子铺（八贯）", "months": 3, "cost": 8000,
					"special": "open_bao", "flavor": "蒸笼一起，半个村子都闻得见。"},
				{"label": "盘一间绸庄（十八贯）", "months": 4, "cost": 18000,
					"special": "open_silk", "flavor": "绸庄的门面要体面，光是柜台就换了三回。"},
				{"label": "盘一间首饰铺（三十贯）", "months": 5, "cost": 30000,
					"special": "open_jewel", "flavor": "首饰铺赚的是富户的钱，赔的也是。"},
			]
		"shop":
			var g: Dictionary = _goods()
			var bulk := int(g.get("bulk", 0))
			var unit := str(g.get("unit", ""))
			var buy_cost := int(float(bulk) * float(g.get("cost", 4)) * float(shop.get("market", 1.0)))
			var helper_on := bool(shop.get("helper", false))
			var helper_label := "辞退伙计（月钱一百五十文）" if helper_on else "雇一个伙计（月钱一百五十文）"
			return [
				{"label": "进货 %d %s（%d 文）" % [bulk, unit, buy_cost], "months": 1,
					"cost": buy_cost, "special": "buy_stock"},
				{"label": "调价（现为%s）" % _price_word(), "months": 1, "special": "cycle_price"},
				{"label": "开门做半年生意", "months": 6, "special": "run_shop"},
				{"label": helper_label, "months": 1, "special": "toggle_helper"},
				{"label": "重装门面（一年，八贯）", "months": 12, "cost": 8000,
					"special": "expand", "flavor": "新招牌挂上去那天，街坊都来看。"},
			]
	return []


func _is_exam_year() -> bool:
	var ys: Array = DB.era.get("exam_years", [])
	for y in ys:
		if int(y) == year:
			return true
	return false


func _goods() -> Dictionary:
	match str(shop.get("kind", "")):
		"bao":
			return {"unit": "个", "cost": 4.0, "price": 10.0, "demand": 60.0, "bulk": 200}
		"silk":
			return {"unit": "匹", "cost": 120.0, "price": 260.0, "demand": 12.0, "bulk": 40}
		"jewel":
			return {"unit": "件", "cost": 400.0, "price": 900.0, "demand": 5.0, "bulk": 12}
	return {}


func _price_word() -> String:
	return str(["贱卖", "平价", "贵卖"][int(shop.get("price", 1))])


func _hint() -> String:
	if busy or ended:
		return ""
	if age < 8:
		if not can_walk:
			return "你还不会走，母亲抱着你——点家，跟着父母过一年"
		if age < 6:
			return "你还小，只能跟着父母过日子"
		return "去私塾读几年书，或者到田里帮工"
	if age < 14 and learning < 20.0:
		return "学识还浅，私塾可以再读两年"
	if age >= 14 and not married and not story.has("meiren_spawned"):
		return "该说亲了——媒人迟早会来"
	if age >= 16 and not shop_open and not story.has("lot_hint"):
		return "村口有空地，可以盘一间铺子"
	if _is_exam_year() and story.has("读书") and not story.has("进士"):
		return "今年开科，书院可以应考"
	if money < 400:
		return "家里快断粮了，去市集或码头找点活"
	var sc := _due_scene()
	if not sc.is_empty():
		return "「%s」到了——回家过节，时间会往前跳过一段" % str(sc["name"])
	return ""


func _on_volume_changed(db: float) -> void:
	var label := "静音"
	if db > Sfx.VOLUME_MIN + 0.1:
		label = "%d dB" % int(db)
	_toast("音量 " + label, Color(0.30, 0.26, 0.21))


func _shop_hud() -> String:
	var g: Dictionary = _goods()
	if g.is_empty():
		return shop_label
	return "%s　存货 %d%s　%s　行情 %.2f　同行%s　伙计%s" % [
		shop_label, int(shop.get("stock", 0)), str(g.get("unit", "")), _price_word(),
		float(shop.get("market", 1.0)),
		str(["贱卖", "平价", "贵卖"][int(shop.get("rival", 1))]),
		"有" if bool(shop.get("helper", false)) else "无",
	]


func _shop_summary() -> String:
	var g: Dictionary = _goods()
	if g.is_empty():
		return "「%s」的幌子挂在门口。" % shop_label
	return "存货 %d%s　·　定价%s　·　行情 %.2f　·　同行%s　·　伙计%s" % [
		int(shop.get("stock", 0)), str(g.get("unit", "")), _price_word(),
		float(shop.get("market", 1.0)),
		str(["贱卖", "平价", "贵卖"][int(shop.get("rival", 1))]),
		"有" if bool(shop.get("helper", false)) else "无",
	]


func _run_shop(months: int) -> void:
	var g: Dictionary = _goods()
	if g.is_empty():
		return
	var unit := str(g.get("unit", ""))
	var base_price := float(g.get("price", 10.0))
	var demand := float(g.get("demand", 60.0))
	var tier := int(shop.get("price", 1))
	var price_mult: float = [0.80, 1.00, 1.40][tier]
	var price_demand: float = [1.35, 1.00, 0.62][tier]
	var comp := 1.0
	if tier > int(shop.get("rival", 1)):
		comp = 0.72
	elif tier < int(shop.get("rival", 1)):
		comp = 1.18
	var cap := demand * price_demand * (1.0 + float(shop_level - 1) * 0.18)
	if bool(shop.get("helper", false)):
		cap *= 1.6
	var potential := cap * float(months) * comp
	var sold := int(minf(float(shop.get("stock", 0)), potential))
	shop["stock"] = int(shop.get("stock", 0)) - sold
	var revenue := int(float(sold) * base_price * price_mult * float(shop.get("market", 1.0)))
	var wage := 0
	if bool(shop.get("helper", false)):
		wage = 150 * months
	var profit := revenue - wage
	money = maxi(0, money + profit)
	if sold <= 0:
		_toast("铺子里没货，空站了%d个月，还倒贴工钱 %d 文。" % [months, wage], Color(0.62, 0.24, 0.18))
	else:
		_toast("卖出 %d %s，进账 %d 文，扣工钱净赚 %d 文。" % [sold, unit, revenue, profit],
			Color(0.30, 0.42, 0.22) if profit >= 0 else Color(0.62, 0.24, 0.18))


func _month_index() -> int:
	return year * 12 + month


func _cooldown_ready(label: String) -> bool:
	# 同一件事在冷却期内不能再做（冷却从"这次做完之后"开始算）
	if label == "":
		return true
	var now := _month_index()
	var ready_at := int(action_cooldown.get(label, 0))
	if ready_at > now:
		_toast("这事刚做过，再过 %d 个月。" % (ready_at - now), Color(0.62, 0.24, 0.18))
		return false
	return true


func _cooldown_commit(label: String, months: int) -> void:
	if label == "":
		return
	action_cooldown[label] = _month_index() + maxi(1, months)


func _on_action(act: Dictionary) -> void:
	if ended:
		return
	var cost := int(act.get("cost", 0))
	if cost > money:
		_toast("钱不够。", Color(0.62, 0.24, 0.18))
		return
	if act.has("req"):
		var req: Dictionary = act["req"]
		for k in req.keys():
			if k == "learning" and learning < float(req[k]):
				_toast("还做不了这个。", Color(0.62, 0.24, 0.18))
				return

	# M1-02：冷却检查必须在扣钱、关面板之前
	if not _cooldown_ready(str(act.get("label", ""))):
		return

	money -= cost
	panel.visible = false
	busy = false
	# 平常做事不花时间，时间自己走；只有"大事"（半年以上的活）才跳过一段
	var m := int(act.get("months", 1))
	if m >= 6:
		_advance_months(m)
		# A01：跳过的时间可能已经把人跳死了，死亡优先于本次行动的收益
		if ended:
			print("[ACTION] interrupted_before_reward ", str(act.get("label", "")))
			return
	if act.has("gain"):
		_apply_gain(act["gain"])
	if act.has("special"):
		_apply_special(str(act["special"]))
		# 战死等特殊效果会在这里结束人生，后续不再发奖、不再写普通存档
		if ended:
			print("[ACTION] interrupted_after_special ", str(act.get("label", "")))
			return
	if act.has("flag"):
		story[str(act["flag"])] = true
	# M1-02：结算完成后才开始计时，长期行动已用自己的 months 付过账
	_cooldown_commit(str(act.get("label", "")), int(act.get("months", 1)))
	if act.has("flavor"):
		_toast(str(act["flavor"]), Color(0.30, 0.26, 0.21))
	var got_money := false
	if act.has("gain") and act["gain"] is Dictionary and (act["gain"] as Dictionary).has("money"):
		got_money = int((act["gain"] as Dictionary)["money"]) > 0
	Sfx.play("coin" if got_money else "ok")
	_save_game()
	queue_redraw()
	if age >= lifespan or health <= 0.0:
		_ending()


func _apply_gain(g: Dictionary) -> void:
	for k in g.keys():
		var v := float(g[k])
		match str(k):
			"money":
				money = maxi(0, money + int(v))
			"learning":
				learning = clampf(learning + v, 0.0, 100.0)
			"craft":
				craft = clampf(craft + v, 0.0, 100.0)
			"medicine":
				medicine = clampf(medicine + v, 0.0, 100.0)
			"fame":
				fame = clampf(fame + v, 0.0, 100.0)
			"health":
				health = clampf(health + v, 0.0, 100.0)


func _apply_special(s: String) -> void:
	if s.begins_with("open_"):
		shop_open = true
		shop_level = 1
		match s:
			"open_bao":
				shop_label = "包子铺"
				shop["kind"] = "bao"
			"open_silk":
				shop_label = "绸庄"
				shop["kind"] = "silk"
			"open_jewel":
				shop_label = "首饰铺"
				shop["kind"] = "jewel"
		shop["stock"] = 0
		shop["price"] = 1
		shop["helper"] = false
		shop["market"] = 1.0
		shop["rival"] = 1
		_rebuild()
		_play_cutscene("开 张", [
			"你盘下了村口那间塌了半边的棚子。",
			"木匠修了七天，母亲剪了红纸贴上。",
			"开张那日，来了三桌人，你忙到二更。",
		], false)
	elif s == "expand":
		shop_level += 1
	elif s == "buy_stock":
		var g: Dictionary = _goods()
		var bulk := int(g.get("bulk", 0))
		shop["stock"] = int(shop.get("stock", 0)) + bulk
		_toast("进了 %d %s，码在后屋。" % [bulk, str(g.get("unit", ""))], Color(0.30, 0.26, 0.21))
	elif s == "cycle_price":
		shop["price"] = (int(shop.get("price", 1)) + 1) % 3
		_toast("你把价钱改成了%s。" % _price_word(), Color(0.30, 0.26, 0.21))
	elif s == "toggle_helper":
		shop["helper"] = not bool(shop.get("helper", false))
		if bool(shop["helper"]):
			_toast("邻村的后生留下了，管饭，月钱一百五十文。", Color(0.30, 0.26, 0.21))
		else:
			_toast("伙计收拾包袱走了。", Color(0.30, 0.26, 0.21))
	elif s == "run_shop":
		_run_shop(6)
	elif s == "marry":
		married = true
		spouse_name = "李氏"
		story["married"] = true
		story["meiren_done"] = true
		_log_fact("marriage", "meiren", {"spouse": spouse_name})
	elif s == "pay_debt":
		story.erase("欠李婶")
		story["清账"] = true
	elif s == "refuse_debt":
		story["赖账"] = true
	elif s == "delay_debt":
		story["利滚利"] = true
	elif s == "apprentice":
		craft_rank = 1
		craft = minf(100.0, craft + 6.0)
		fame = minf(100.0, fame + 2.0)
		story["匠户"] = true
		_leave_old_line("craft")
		_toast("你磕了头，端了拜师茶。师父说：先学三年看火。", Color(0.30, 0.26, 0.21))
	elif s == "journeyman":
		craft_rank = 2
		fame = minf(100.0, fame + 8.0)
		_play_cutscene("出 师", [
			"师父把一套凿子推到你面前，说：拿去吧。",
			"「以后接活，报我的名字也行，报你自己的也行。」",
			"你走出门，忽然觉得街比从前宽。",
		], false)
	elif s == "take_apprentice":
		apprentice_hired += 1
		fame = minf(100.0, fame + 6.0)
		_toast("收了个徒弟，管饭，不给工钱。", Color(0.30, 0.26, 0.21))
	elif s == "workshop":
		workshop_open = true
		craft_rank = 3
		fame = minf(100.0, fame + 10.0)
		_rebuild()
		_play_cutscene("开 作 坊", [
			"你在村口盘下两间铺面，挂了「营造」的幌子。",
			"来道贺的人坐了六桌，里正也来了。",
			"从此你不再自己抡锤，只看图样、算料、骂人。",
		], false)
	elif s == "child_year":
		_child_year()
	elif s == "pov_father":
		_switch_pov("father")
	elif s == "pov_mother":
		_switch_pov("mother")
	elif s == "pov_child":
		_switch_pov("child")
	elif s == "scene":
		var sc := _due_scene()
		if not sc.is_empty():
			_do_scene(sc)
	elif s.begins_with("scene_pick:"):
		var parts := s.split(":")
		if parts.size() >= 3:
			_pick_scene_option(parts[1], parts[2])
	elif s == "w_start":
		women_rank = 1
		money += 300
		craft = minf(100.0, craft + 2.0)
		_toast("接下了第一份浆洗。手在冷水里泡了三个月，指节都肿了。", Color(0.30, 0.26, 0.21))
	elif s == "w_journey":
		women_rank = 2
		fame = minf(100.0, fame + 5.0)
		_play_cutscene("绣 娘", [
			"你绣的一方帕子被布庄的掌柜看中了。",
			"他说：往后有多少，我收多少。",
			"你回家把针线盒擦了一遍，坐在灯下绣到三更。",
		], false)
	elif s == "w_midwife":
		if _rnd() < 0.85:
			fame = minf(100.0, fame + 5.0)
			_toast("母子平安。主家给你包了红纸，还提了一篮鸡蛋。", Color(0.30, 0.42, 0.22))
		else:
			fame = maxf(0.0, fame - 6.0)
			_toast("孩子没保住。你在门外站了很久，从此不太敢接生。", Color(0.62, 0.24, 0.18))
	elif s == "w_shop":
		women_rank = 3
		fame = minf(100.0, fame + 10.0)
		_play_cutscene("绣 坊", [
			"你在巷口租了两间屋，摆了六张绣架。",
			"姑娘们低头穿针，屋里只有线过布的声音。",
			"从此你不再自己绣整天，只看花样、算工钱。",
		], false)
	elif s == "w_guild":
		women_rank = 4
		fame = minf(100.0, fame + 12.0)
		_play_cutscene("行 首", [
			"女红行的老人们推你坐了首座。",
			"从今往后，县里绣活的价钱由你们几家议定。",
			"你摸了摸袖口那方旧帕子——那是你绣的第一件。",
		], false)
	elif s == "stall":
		var earn := 300 + _rndi(0, 600)
		money += earn
		fame = minf(100.0, fame + 1.0)
		if trade_rank == 0:
			trade_rank = 1
			_leave_old_line("trade")
			_toast("摊子摆住了。一个月赚 %d 文，从今往后你算个行商。" % earn, Color(0.30, 0.26, 0.21))
		else:
			_toast("一个月下来赚了 %d 文，被差役撵了两回。" % earn, Color(0.30, 0.26, 0.21))
	elif s == "caravan":
		if _rnd() < 0.6:
			var gain := _rndi(2000, 3600)
			money += gain
			_toast("这趟货卖得顺，赚了 %d 文。" % gain, Color(0.30, 0.42, 0.22))
		else:
			var loss := _rndi(400, 1000)
			money = maxi(0, money - loss)
			_toast("路上连日下雨，货烂了一半，亏了 %d 文。" % loss, Color(0.62, 0.24, 0.18))
	elif s == "sedentary":
		trade_rank = 2
		shop_level += 1
		fame = minf(100.0, fame + 10.0)
		_play_cutscene("坐 贾", [
			"你把铺面的招牌换成了漆的。",
			"从此不再挑担子跑路，只在柜台后头等人上门。",
			"同行说：他这回是打算长期做下去了。",
		], false)
	elif s == "guild":
		trade_rank = 3
		guild_open = true
		fame = minf(100.0, fame + 20.0)
		_play_cutscene("入 行 会", [
			"行会的老先生把一本册子推到你面前。",
			"「签了名，行价就由不得你一个人定了。」",
			"你签了。从今往后，你也是定行价的人之一。",
		], false)
	elif s == "set_price":
		shop["market"] = clampf(float(shop.get("market", 1.0)) + 0.10, 0.70, 1.40)
		fame = minf(100.0, fame + 2.0)
		_toast("你和几家同行议定了今年的价，行情涨了一成。", Color(0.30, 0.26, 0.21))
	elif s == "med_apprentice":
		med_rank = 1
		var bonus := 0.0
		if craft >= 40.0:
			bonus = 6.0
		medicine = minf(100.0, medicine + 6.0 + bonus)
		fame = minf(100.0, fame + 2.0)
		_leave_old_line("med")
		if bonus > 0.0:
			_toast("你懂火候，也认得几味药性，师父多教了你一手。", Color(0.30, 0.26, 0.21))
		else:
			_toast("你给师父磕了头。他说：先背三年汤头歌。", Color(0.30, 0.26, 0.21))
	elif s == "med_journeyman":
		med_rank = 2
		fame = minf(100.0, fame + 8.0)
		_play_cutscene("出 师", [
			"师父把药箱递给你，说：开方子之前，先看人。",
			"「治不好的，别硬治。说一句我治不了，不丢人。」",
			"你背着箱子出门，觉得箱子比想的沉。",
		], false)
	elif s == "med_visit":
		if _rnd() < 0.75:
			money += 2200
			fame = minf(100.0, fame + 4.0)
			_toast("这一趟治好了，主家塞给你两贯钱，还提了一篮鸡蛋。", Color(0.30, 0.42, 0.22))
		else:
			money = maxi(0, money - 600)
			fame = maxf(0.0, fame - 7.0)
			_toast("病人没救回来。家属在门口骂了半日，你一分钱没收。", Color(0.62, 0.24, 0.18))
	elif s == "med_clinic":
		med_rank = 3
		fame = minf(100.0, fame + 10.0)
		_play_cutscene("坐 堂", [
			"药铺给你留了一张桌子，桌上一方砚、一管笔。",
			"第一位病人是个咳了半年的老人。",
			"你搭上脉，忽然想起师父说的那句：先看人。",
		], false)
	elif s == "med_book":
		med_rank = 4
		med_book = true
		fame = minf(100.0, fame + 18.0)
		learning = minf(100.0, learning + 5.0)
		_play_cutscene("著 书", [
			"你把三十年看过的方子抄了一遍，删去一半。",
			"书成那日，弟子们抄了七份，分送州县。",
			"有人开始叫你「先生」，不叫名字了。",
		], false)
	elif s == "farm_rent":
		farm_rank = 1
		money += 2200
		health = maxf(0.0, health - 6.0)
		_leave_old_line("farm")
		_toast("押了八百文，租下东家八亩薄田。头一年，交完租只剩个饱。", Color(0.30, 0.26, 0.21))
	elif s == "farm_till":
		var income := 900 + land * 170
		money += income
		health = maxf(0.0, health - 8.0)
		_toast("自家%d亩田，一年收成折钱 %d 文。" % [land, income], Color(0.30, 0.42, 0.22))
	elif s == "farm_collect":
		var rent := land * (150 if farm_rank == 3 else 190)
		money += rent
		fame = minf(100.0, fame + 2.0)
		_toast("%d亩田的租子收上来，共 %d 文。" % [land, rent], Color(0.30, 0.42, 0.22))
	elif s == "farm_buy":
		land += 1
		if farm_rank == 1 and land >= 6:
			farm_rank = 2
			_play_cutscene("自 耕", [
				"第六亩田的契纸按了手印。",
				"从今往后，种的是自己的地，交的是官府的税。",
				"你在田埂上坐了很久，觉得土是热的。",
			], false)
		elif farm_rank == 2 and land >= 20:
			farm_rank = 3
			_play_cutscene("小 地 主", [
				"二十亩田，自己种不过来，雇了三户佃农。",
				"秋后收租，你坐在场院上，看人一担一担挑谷。",
			], false)
		elif farm_rank == 3 and land >= 40:
			farm_rank = 4
			_play_cutscene("田 主", [
				"四十亩田，连成一片，从村口一直铺到河边。",
				"县里修志，把你列进了「乡贤」一栏。",
			], false)
		else:
			_toast("买了第 %d 亩田，契纸压在箱底。" % land, Color(0.30, 0.26, 0.21))
	elif s == "enlist":
		if health < 45.0:
			_toast("你身子太弱，募兵的一眼就看出来了。", Color(0.62, 0.24, 0.18))
			return
		mil_rank = 1
		health = maxf(0.0, health - 2.0)
		money += 500
		_leave_old_line("mil")
		_toast("你报了名，领一口刀、两斗米。名册上不写名字，写「某乡某人」。", Color(0.30, 0.26, 0.21))
	elif s == "expedition":
		if _rnd() < 0.10:
			death_cause = "战死"
			_die_young()
			return
		merit += 1
		money += 3200
		health = maxf(0.0, health - 6.0)
		_toast("这一仗打完了，你在死人堆里坐了很久。战功记了一次。", Color(0.30, 0.26, 0.21))
	elif s == "expedition2":
		if _rnd() < 0.08:
			death_cause = "战死"
			_die_young()
			return
		merit += 1
		money += 4500
		health = maxf(0.0, health - 8.0)
		_toast("大军推进三十里，你跟着走完全程。战功记了一次。", Color(0.30, 0.26, 0.21))
	elif s == "promote_nco":
		mil_rank = 2
		fame = minf(100.0, fame + 6.0)
		_play_cutscene("升 厢 军", [
			"教头把你的名字从乡兵册上划掉，写到另一本上。",
			"「从今天起，你吃军粮，不种田了。」",
		], false)
	elif s == "promote_officer":
		mil_rank = 3
		fame = minf(100.0, fame + 15.0)
		_play_cutscene("授 军 官", [
			"授官的文书下来那天，营里杀了三头猪。",
			"你穿上新甲走到校场，看底下的人跟你从前一样站着。",
		], false)
	elif s == "patrol":
		if _rnd() < 0.12:
			death_cause = "战死"
			_die_young()
			return
		money += 6000
		fame = minf(100.0, fame + 8.0)
		_toast("巡边一年，遇了一小股马贼，斩了七级。", Color(0.30, 0.42, 0.22))
	elif s == "take_post":
		office_rank = 1
		var names := ["吴县", "长洲", "常熟", "昆山", "嘉定", "华亭"]
		county = str(names[randi() % names.size()])
		var bonus_note := ""
		if mil_rank >= 2:
			gov_merit += 2
			bonus_note = "你有军功在身，上官对你客气三分。"
		elif trade_rank >= 2:
			gov_merit += 2
			bonus_note = "你懂钱谷，一上任就查出库里亏空。"
		_play_cutscene("赴 任", [
			"吏部给你注了%s主簿。" % county,
			"上任那天，县衙的门槛比你家的高很多。",
			bonus_note if bonus_note != "" else "案上堆着没批完的状子，最上面一张写着「田界」。",
		], false)
	elif s == "judge_fair":
		if _rnd() < 0.60:
			gov_merit += 2
			fame = minf(100.0, fame + 3.0)
			_toast("判得公，两造都服。县里传你是个明白官。", Color(0.30, 0.42, 0.22))
		else:
			gov_merit += 1
			fame = maxf(0.0, fame - 2.0)
			money = maxi(0, money - 500)
			_toast("你判得不合豪强的心意，夜里有人往门上泼了粪。", Color(0.62, 0.24, 0.18))
	elif s == "judge_bribe":
		money += 3000
		gov_merit -= 1
		fame = maxf(0.0, fame - 3.0)
		scandal += 1
		_toast("银子收了，案子改了。你夜里睡得不太安稳。", Color(0.48, 0.32, 0.16))
	elif s == "gov_farm":
		gov_merit += 1
		_toast("下乡劝农，在田埂上走了半个月，鞋底磨穿了。", Color(0.30, 0.26, 0.21))
	elif s == "promote":
		if gov_merit < _promote_need():
			_toast("考绩还差 %d 分，再干两年。" % (_promote_need() - gov_merit), Color(0.62, 0.24, 0.18))
			return
		office_rank = mini(3, office_rank + 1)
		gov_merit = 0
		fame = minf(100.0, fame + 10.0)
		_play_cutscene("升 迁", [
			"考绩上上，你由%s升%s。" % [str(["", "主簿", "县令", "通判"][office_rank - 1]), _office_name()],
			"接印那天，旧同僚来道贺，脸上笑着，话说得很客气。",
		], false)
	elif s == "retire":
		story["致仕"] = true
		fame = minf(100.0, fame + 5.0)
		_toast("你递了告老的状子。回乡那天，只有两个老吏送到城外。", Color(0.30, 0.26, 0.21))
	elif s == "jieshi":
		var p := clampf(0.10 + learning * 0.010, 0.05, 0.90)
		if _rnd() < p:
			story["举人"] = true
			fame = minf(100.0, fame + 18.0)
			_log_fact("exam", "jieshi_pass", {"year": year})
			_play_cutscene("解 试", [
				"榜贴在州学墙上，人挤得水泄不通。",
				"你从最后一行往前看，看见了自己的名字。",
				"有人拍你的肩，你才发现自己在发抖。",
			], false)
		else:
			fame = maxf(0.0, fame - 1.0)
			_log_fact("exam", "jieshi_fail", {"year": year})
			_toast("解试落第。你在贡院外站到人都散了。", Color(0.62, 0.24, 0.18))
	elif s == "shengshi":
		var p2 := clampf(-0.08 + learning * 0.008, 0.04, 0.85)
		if _rnd() < p2:
			story["进士"] = true
			fame = minf(100.0, fame + 30.0)
			money += 4000
			_play_cutscene("登 第", [
				"殿试唱名，你名列三甲。",
				"骑马游街那天，你看见人群里有个像父亲的身影。",
				"回乡时，县里给你家送了匾。",
			], false)
		else:
			fame = maxf(0.0, fame - 2.0)
			_log_fact("exam", "shengshi_fail", {"year": year})
			_toast("省试落第。盘缠花光了，你在京城住了半年才凑够路费。", Color(0.62, 0.24, 0.18))


# ---------------------------------------------------------------- 时间

func _trigger_actor_end() -> void:
	# A01：人生结束只触发一次；当前控制谁，就结束谁的人生
	if ended:
		return
	if pov == "child":
		_ending()
	else:
		_parent_death()


func _advance_months(n: int) -> void:
	for i in range(n):
		# 已经到寿或已垮掉的人，不再推进时间，也不留下未结算的收益
		if age >= lifespan or health <= 0.0:
			_trigger_actor_end()
			return
		month += 1
		if shop_open:
			shop["market"] = clampf(float(shop.get("market", 1.0)) + _rndf(-0.045, 0.045), 0.70, 1.40)
			if _rnd() < 0.10:
				shop["rival"] = _rndi(0, 2)
		if month > 12:
			month = 1
			year += 1
			age += 1
			# 所有人一起长一岁——你替父亲过日子的时候，孩子也在长大
			for k in pov_state.keys():
				var st: Dictionary = pov_state[k]
				st["age"] = int(st.get("age", age)) + 1
			_on_new_year()
			if age >= lifespan or health <= 0.0:
				_trigger_actor_end()
				return


func _decay_health(age_v: int, hp: float) -> float:
	# 48 岁后每年掉一点，60 岁后掉得更快
	var h := hp
	if age_v > 48:
		h -= 0.8
	if age_v > 60:
		h -= 1.4
	return maxf(0.0, h)


func _on_new_year() -> void:
	# M1-02b：年关每年只结算一次，防重入（过场、嵌套推进、重复调用）
	if last_settled_year >= year:
		print("[YEAR] settle_skipped year=", year, " last=", last_settled_year)
		return
	last_settled_year = year
	scenes_done.clear()
	# M1-02c：每个活着的人各自老化扣血，不因当前操控谁而改变
	health = _decay_health(age, health)
	for k in pov_state.keys():
		var st: Dictionary = pov_state[k]
		var st_age := int(st.get("age", 0))
		var st_hp := _decay_health(st_age, float(st.get("health", 100.0)))
		st["health"] = st_hp
		var st_life := int(st.get("lifespan", 100))
		var kid := str(k)
		if kid in ["father", "mother"] and not bool(parent_dead.get(kid, false)) \
				and (st_age >= st_life or st_hp <= 0.0):
			parent_dead[kid] = true
			parent_death_year[kid] = year
			parents_alive = maxi(0, parents_alive - 1)
			_toast("%s也走了，就在这一年。" % (father_name if kid == "father" else mother_name),
				Color(0.62, 0.24, 0.18))
			_spawn_npcs()
	if health <= 0.0:
		lifespan = age
	if age == 1 and not milestones.has("zhuazhou"):
		milestones["zhuazhou"] = true
		_play_cutscene("周 岁", [
			"桌上摆了七样东西：笔、算盘、小弓、葱、铜钱、胭脂、一块木头的官印。",
			"母亲把你放在桌子中间，屋里的人都屏住气。",
			"你爬过去，先摸了摸笔，最后抓住的是别的——没人看清。",
		], false)
	if age == 2 and not can_walk:
		can_walk = true
		milestones["walk"] = true
		_play_cutscene("学 步", [
			"母亲把你放在地上，退开三步，张开手。",
			"你扶着墙走了两步，扑进她怀里。",
			"父亲在门口看着，没说话，把手里的活放下了。",
		], false)
	if age == 3 and not milestones.has("toddle"):
		milestones["toddle"] = true
		_toast("你会说整句话了。母亲高兴得直抹眼睛。", Color(0.30, 0.42, 0.22))
	if age == 6 and not milestones.has("school_age"):
		milestones["school_age"] = true
		_play_cutscene("六 岁", [
			"父亲把你的手翻过来看了看，说：该开蒙了。",
			"母亲连夜缝了个布袋子，装了两支笔。",
			"从今往后，你可以自己走出这个院子了。",
		], false)
	if age == 16 and not shop_open:
		_rebuild()
		_toast("村口那块空地，牙人说可以盘。", Color(0.48, 0.32, 0.16))
	if age == 14 and not married and not story.has("meiren_spawned"):
		story["meiren_spawned"] = true
		_spawn_special("meiren", "媒人", Vector2(560, 704), "她打量了你一圈，说：年纪到了，该说个人家了。")
		_toast("村里来了个媒人，在井边站着。", Color(0.48, 0.32, 0.16))
	if age == 22 and story.has("欠李婶") and not story.has("zhaizhu_spawned"):
		story["zhaizhu_spawned"] = true
		_spawn_special("zhaizhu", "债主", Vector2(500, 726), "他把账本摊开：连本带利，三贯。")
		_toast("有人上门讨账。", Color(0.62, 0.24, 0.18))
	if age == 18 and not milestones.has("adult"):
		milestones["adult"] = true
		_play_cutscene("及 冠", [
			"十八岁这年，母亲把你的旧衣裳拆了，重做了一件。",
			"父亲把刀递给你，又收了回去——那是他当兵时留下的。",
			"从此以后，这个家要你自己撑了。",
		], false)
	# 年关：吃穿用度与赋税
	if age >= 8:
		var cost := 300 + age * 4
		if married:
			cost += 200
		cost += children * 180
		cost += land * 18
		if shop_open and bool(shop.get("helper", false)):
			cost += 1800
		if money >= cost:
			money -= cost
			_toast("年关：吃穿用度、赋税共 %d 文。" % cost, Color(0.42, 0.34, 0.22))
		else:
			var short := cost - money
			money = 0
			fame = maxf(0.0, fame - 2.0)
			health = maxf(0.0, health - 1.0)
			story["欠年"] = int(story.get("欠年", 0)) + 1
			_toast("年关难过，短了 %d 文。典了件旧衣，债又添一笔。" % short, Color(0.62, 0.24, 0.18))
	# 俸禄
	if story.has("进士") and not story.has("致仕"):
		money += _salary()
	# 御史弹劾
	if scandal >= 3 and office_rank > 0:
		scandal = 0
		office_rank = maxi(0, office_rank - 1)
		fame = maxf(0.0, fame - 15.0)
		money = maxi(0, money - 2000)
		story["贬谪"] = int(story.get("贬谪", 0)) + 1
		_toast("御史弹劾你贪墨，降一级，追赃两千文。", Color(0.62, 0.24, 0.18))
	# 作坊与徒弟的进项
	if workshop_open:
		money += 1500
	if apprentice_hired > 0:
		money += 200 * apprentice_hired
	if guild_open:
		money += 3000
	if med_rank >= 4:
		money += 2000
	if _mother_rank() >= 3:
		money += 1200
	if _mother_rank() >= 4:
		money += 1300
	# 开科之年
	if _is_exam_year() and not story.has("进士"):
		if story.has("举人"):
			_toast("今年开科，可赴京应省试。", Color(0.48, 0.32, 0.16))
		elif story.has("读书") and learning >= 25.0:
			_toast("今年开科，书院可以应解试。", Color(0.48, 0.32, 0.16))
	_roll_event()
	# 生子
	if age == 30 and married and children == 0 and not milestones.has("child1"):
		milestones["child1"] = true
		children += 1
		money = maxi(0, money - 800)
		_play_cutscene("得 子", [
			"妻子临盆那夜，你在院里走到天亮。",
			"稳婆出来说：是个儿子。",
			"你抱他时手在抖，像抱一件借来的东西。",
		], false)
	elif age == 34 and married and children == 1 and not milestones.has("child2"):
		milestones["child2"] = true
		children += 1
		_toast("又添了一个孩子，屋里更挤了。", Color(0.42, 0.34, 0.22))
	# 丧亲
	if age == 46 and parents_alive > 0 and not milestones.has("orphan"):
		milestones["orphan"] = true
		parents_alive = 0
		health = maxf(0.0, health - 2.0)
		_play_cutscene("丧 亲", [
			"母亲是冬天走的，走的时候你在外头。",
			"回来时，灵堂已经摆好了。",
			"父亲坐在门槛上，一句话也不说。",
		], false)
	# 抱孙
	if age == 62 and children > 0 and not milestones.has("grandchild"):
		milestones["grandchild"] = true
		fame = minf(100.0, fame + 5.0)
		_play_cutscene("抱 孙", [
			"孙子满月，家里摆了四桌。",
			"有人把孩子递到你怀里，你忽然想起自己也有过这么小的时候。",
		], false)
	_save_game()


# ---------------------------------------------------------------- 结局

func _event_ok(ev: Dictionary) -> bool:
	if age < int(ev.get("min_age", 0)):
		return false
	if age > int(ev.get("max_age", 200)):
		return false
	match str(ev.get("cond", "")):
		"farm":
			return farm_rank >= 2
		"famous":
			return story.has("进士") or fame >= 45.0
		"parent":
			return children > 0
	return true


func _roll_event() -> void:
	if not events_enabled:
		return
	if _rnd() > 0.32:
		return
	var pool: Array = []
	for e in EVENTS:
		if _event_ok(e):
			pool.append(e)
	if pool.is_empty():
		return
	var ev: Dictionary = pool[randi() % pool.size()]
	_apply_event(str(ev["id"]))


func _apply_event(id: String) -> void:
	_log_fact("event", "year_end", {"id": id})
	var bad := Color(0.62, 0.24, 0.18)
	var good := Color(0.30, 0.42, 0.22)
	match id:
		"drought":
			money = maxi(0, money - 700)
			health = maxf(0.0, health - 3.0)
			_toast("春旱，河断了流。粮价涨了三成，家里先紧着吃。", bad)
		"flood":
			money = maxi(0, money - 900)
			_toast("夏水暴涨，冲了低处的田。修堤又摊了一笔钱。", bad)
		"levy":
			money = maxi(0, money - 500)
			fame = maxf(0.0, fame - 1.0)
			_toast("官府加派杂税，里正挨家收钱。", bad)
		"thieves":
			money = maxi(0, money - 600)
			health = maxf(0.0, health - 2.0)
			_toast("夜里进了贼，翻走了箱底的现钱。", bad)
		"plague":
			if med_rank >= 3:
				health = maxf(0.0, health - 2.0)
				_toast("疫气进了村。你懂医，早早闭门煮药，只病了一场小的。", good)
			else:
				health = maxf(0.0, health - 7.0)
				_toast("疫气进了村，你躺了两个月，差点没起来。", bad)
		"suit":
			money = maxi(0, money - 800)
			fame = maxf(0.0, fame - 2.0)
			_toast("被人告了一状，赔钱不说，还落了个不是。", bad)
		"wedding":
			money = maxi(0, money - 300)
			fame = minf(100.0, fame + 3.0)
			_toast("邻家嫁女，随了三百文的礼。席上吃了两碗。", good)
		"harvest":
			var gain := maxi(300, land * 60)
			money += gain
			_toast("今年风调雨顺，田里多收了 %d 文。" % gain, good)
		"reward":
			money += 1200
			fame = minf(100.0, fame + 8.0)
			_toast("县里旌表善行，赏了一千二百文。", good)
		"school":
			money = maxi(0, money - 500)
			fame = minf(100.0, fame + 2.0)
			_toast("孩子到了开蒙的年纪，束脩又是一笔。", bad)
		"rash":
			health = maxf(0.0, health - 3.0)
			story["出疹子"] = true
			_toast("你出了一身疹子，母亲守了三夜，用凉水给你擦身。", bad)
		"riverfall":
			health = maxf(0.0, health - 2.0)
			fame = minf(100.0, fame + 1.0)
			story["落水"] = true
			_toast("你掉进河里，被撑船的捞了上来。母亲抱着你哭了很久。", bad)
		"find_coin":
			money += 50
			_toast("你在墙根下捡到一枚铜钱，攥了一天，最后还是交给了母亲。", good)
		"quarrel":
			fame = maxf(0.0, fame - 1.0)
			_toast("邻家孩子抢了你的糖，你俩在泥地里滚成一团。", bad)


func _die_young() -> void:
	health = 0.0
	lifespan = age
	_ending()


func _ending() -> void:
	if ended:
		return
	ended = true
	panel.visible = false
	_clear_save()
	var lines: Array = []
	if death_cause == "战死":
		lines = [
			"%s，战事未平。" % DB.era_label(year),
			"年%s岁。你死在阵上，尸首没能找回来。" % _cn(age),
			"同乡捎回一件带血的衣服，母亲认了三天。",
		]
	else:
		lines = [
			"%s，你死在自家的床上。" % DB.era_label(year),
			"年%s岁。窗外有风，吹动了没关严的窗纸。" % _cn(age),
			"案上还压着去年没算完的账。",
		]
	_play_cutscene("%s · 卒" % name_text, lines, true)


func _play_cutscene(title: String, lines: Array, then_epitaph: bool) -> void:
	busy = true
	Sfx.play("bell")
	var cs: Control = CutsceneScript.new()
	add_child(cs)
	cs.play(title, lines)
	cs.finished.connect(func(): busy = false)
	if then_epitaph:
		cs.finished.connect(_show_epitaph)


func _show_epitaph() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.075, 0.059, 0.047)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(760, 0)
	center.add_child(col)

	var head := UIKit.label("【%s】" % _tier_name(), 30, Color(0.75, 0.30, 0.24))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	var line := Color(0.925, 0.878, 0.792)
	for s in _epitaph():
		var l := UIKit.wrap_label(str(s), 21, line)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(760, 0)
		col.add_child(l)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	col.add_child(spacer)

	var verdict := UIKit.wrap_label(_verdict(), 19, Color(0.72, 0.66, 0.55))
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict.custom_minimum_size = Vector2(760, 0)
	col.add_child(verdict)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 16)
	col.add_child(spacer2)

	var btn := UIKit.ink_button("再 活 一 世", 240)
	btn.add_theme_color_override("font_color", line)
	btn.pressed.connect(func():
		_clear_save()
		get_tree().reload_current_scene()
	)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(btn)
	col.add_child(row)


func _tier() -> int:
	if story.has("进士") and fame >= 68.0:
		return 0
	if story.has("进士") or fame >= 62.0:
		return 1
	if story.has("举人") or fame >= 45.0 or craft_rank >= 3 or trade_rank >= 3 or med_rank >= 4 or farm_rank >= 4 or mil_rank >= 3:
		return 2
	if children > 0 or married or craft_rank >= 2 or trade_rank >= 2 or med_rank >= 3 or farm_rank >= 3 or mil_rank >= 1:
		return 3
	return 4


func _tier_name() -> String:
	return str(["国史有传", "府志留名", "县志一行", "族谱一句", "无名"][_tier()])


func _verdict() -> String:
	match _tier():
		0:
			return "史臣曰：起于乡里，终至通显。其行事有足称者，故书之。"
		1:
			return "府志载其名，谓其「居乡有守，临事不苟」。"
		2:
			return "%s，%s人。此一行而已。" % [name_text, place]
		3:
			return "族谱记：公讳%s，配%s，子%d人。余无可书。" % [
				given_text(), spouse_name if married else "某氏", children]
		_:
			return "无人记得他的名字。风从麦田上过，一年又一年。"


func given_text() -> String:
	return name_text.substr(1) if name_text.length() > 1 else name_text


func _facts_trace() -> String:
	# M1-03c：墓志必须引用真实发生过的事，而不是只拼终值
	if facts.is_empty():
		return ""
	var counts := {}
	for f in facts:
		var k := str((f as Dictionary).get("kind", ""))
		counts[k] = int(counts.get(k, 0)) + 1
	var parts: Array = []
	if counts.has("exam"):
		parts.append("应试%d次" % int(counts["exam"]))
	if counts.has("event"):
		parts.append("逢变故%d次" % int(counts["event"]))
	if counts.has("marriage"):
		parts.append("成家一次")
	if counts.has("death"):
		parts.append("送亲%d人" % int(counts["death"]))
	if parts.is_empty():
		return ""
	var s := ""
	for i in range(parts.size()):
		if i > 0:
			s += "、"
		s += str(parts[i])
	return "一生所记：" + s + "。"


func _epitaph() -> Array:
	var lines: Array = []
	var tier := _tier()
	lines.append("%s，%s人。%s生。" % [name_text, place, DB.era_label(year - age)])
	if story.has("进士"):
		lines.append("登进士第，历官州县。俸禄所入，家道渐丰。")
		if office_rank >= 3:
			lines.append("历主簿、县令，终通判%s。" % county)
		elif office_rank == 2:
			lines.append("历主簿，终%s县令。" % county)
		elif office_rank == 1:
			lines.append("为%s主簿。" % county)
		if int(story.get("贬谪", 0)) > 0:
			lines.append("中岁以赃去官，士论少之。")
	elif story.has("举人"):
		lines.append("举于乡，屡试春官不第。")
	elif shop_open:
		lines.append("以%s为业，营生二十余年。" % shop_label)
	elif med_rank >= 4:
		lines.append("以医术名于州里，著方书一卷，活人无算。")
	elif mil_rank >= 3:
		lines.append("以军功授官，戍边十余年，身被数创。")
	elif mil_rank == 2:
		lines.append("隶厢军，转战南北，未得一言以归。")
	elif med_rank >= 3:
		lines.append("以医名于乡里，坐堂三十年。")
	elif farm_rank >= 4:
		lines.append("有田四十亩，岁收租百余石，为一乡之望。")
	elif farm_rank == 3:
		lines.append("有田二十亩，衣食粗足，里中称其能。")
	elif farm_rank == 2:
		lines.append("躬耕自给，未尝贷于人。")
	elif craft_rank >= 3:
		lines.append("以营造名于州里，曾主修学宫。徒众十余人。")
	elif craft_rank == 2:
		lines.append("以手艺名于乡里。")
	elif trade_rank >= 3:
		lines.append("以商起家，为行会之首，乡里缓急多倚之。")
	elif trade_rank == 2:
		lines.append("以坐贾起家，家道渐丰。")
	elif story.has("读书"):
		lines.append("少读书，终老于乡，以教授蒙童自给。")
	else:
		lines.append("终身为佣工，未尝有一间自己的铺面。")
	if married:
		lines.append("娶%s，相守至老。" % spouse_name)
	else:
		lines.append("终身未娶。")
	if children > 0:
		lines.append("子%d人。" % children)
	else:
		lines.append("无子。")
	var trace := _facts_trace()
	if trace != "":
		lines.append(trace)
	if int(story.get("欠年", 0)) >= 3:
		lines.append("晚年家道中落，靠乡邻接济度日。")
	if story.has("赖账"):
		lines.append("乡里传他赖债不还，子孙为之掩口。")
	elif story.has("清账"):
		lines.append("欠人的钱，到底还清了。")
	if story.has("河边"):
		lines.append("幼时与邻女阿禾戏于河上，捉鱼为乐，是其一生最闲的几年。")
	if story.has("穷yuandan"):
		lines.append("少时元日无新衣，母亲把旧袄翻过来缝了一遍。")
	if story.has("穷zhongqiu"):
		lines.append("少时中秋无饼，一块糖敲成四份，他分到最小的一点。")
	if int(story.get("童年节令", 0)) >= 4:
		lines.append("少时最盼过年，爆竹一响就往外跑。")
	if story.has("施舍"):
		lines.append("岁寒施粥，里中称其厚。")
	if _mother_rank() >= 3:
		lines.append("母%s，以女红起家，开绣坊于巷口。" % mother_name)
	elif _mother_rank() == 2:
		lines.append("母%s，善绣，乡里称之。" % mother_name)
	if story.has("落水"):
		lines.append("幼时曾没于水，赖人救起。")
	if death_cause == "战死":
		lines.append("殁于王事，年%s。" % _cn(age))
	else:
		lines.append("卒年%s，遗钱%s。" % [_cn(age), _money_text()])
	if tier >= 3:
		lines.append("里中无人为立传。")
	return lines


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	draw_set_transform(-cam, 0.0, Vector2.ONE)
	_draw_ground()

	var drawables: Array = []
	for pr in props:
		var p: Dictionary = pr
		drawables.append({"y": (p["pos"] as Vector2).y, "kind": "prop", "ref": p})
	for b in buildings:
		var bb: Dictionary = b
		drawables.append({"y": (bb["pos"] as Vector2).y + float(bb["h"]) * 0.5, "kind": "building", "ref": bb})
	for n in npcs:
		var nn: Dictionary = n
		drawables.append({"y": (nn["pos"] as Vector2).y, "kind": "npc", "ref": nn})
	drawables.append({"y": player.y, "kind": "player", "ref": null})

	drawables.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))

	for d in drawables:
		var kind := str(d["kind"])
		if kind == "prop":
			_draw_prop(d["ref"])
		elif kind == "building":
			_draw_building(d["ref"])
		elif kind == "npc":
			_draw_npc(d["ref"])
		else:
			_draw_player()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var tint := _ambient_tint()
	if tint.a > 0.008:
		draw_rect(Rect2(0, 0, W, H), tint)

	if _season() == 3:
		for i in range(80):
			var sx := fmod(float(i) * 137.0 + t * 22.0 + sin(t * 0.7 + float(i)) * 20.0, W)
			var sy := fmod(float(i) * 91.0 + t * 38.0, H)
			draw_circle(Vector2(sx, sy), 1.9, Color(1.0, 1.0, 1.0, 0.55))
	elif _season() == 0:
		for i in range(14):
			var sx := fmod(float(i) * 191.0 + t * 12.0, W)
			var sy := 120.0 + fmod(float(i) * 73.0 + t * 9.0, H - 220.0)
			draw_circle(Vector2(sx, sy), 2.2, Color(1.0, 0.98, 0.92, 0.30))

	if panel != null and panel.visible:
		draw_rect(Rect2(0, 0, W, H), Color(0.09, 0.07, 0.05, 0.18))
	_draw_hud()
	_draw_minimap()
	_draw_toasts()


func _season() -> int:
	if month >= 2 and month <= 4:
		return 0
	if month >= 5 and month <= 7:
		return 1
	if month >= 8 and month <= 10:
		return 2
	return 3


func _ambient_tint() -> Color:
	var c := Color(0, 0, 0, 0)
	match _season():
		0:
			c = Color(0.36, 0.56, 0.40, 0.05)
		1:
			c = Color(0.95, 0.74, 0.34, 0.05)
		2:
			c = Color(0.86, 0.54, 0.20, 0.11)
		3:
			c = Color(0.52, 0.62, 0.86, 0.18)
	var h := hour
	var night := 0.0
	if h < 5.0 or h >= 21.0:
		night = 0.52
	elif h < 7.0:
		night = lerpf(0.52, 0.0, (h - 5.0) / 2.0)
	elif h >= 17.5:
		night = lerpf(0.0, 0.52, (h - 17.5) / 3.5)
	if night > 0.01:
		c = c.blend(Color(0.07, 0.09, 0.20, night))
	return c


func _draw_ground() -> void:
	draw_rect(Rect2(0, 0, WORLD_W, WORLD_H), C_GRASS)

	var seedv := 2411
	for i in range(520):
		seedv = (seedv * 1103515245 + 12345) & 0x7fffffff
		var x := float(seedv % 10000) / 10000.0 * WORLD_W
		seedv = (seedv * 1103515245 + 12345) & 0x7fffffff
		var y := float(seedv % 10000) / 10000.0 * WORLD_H
		draw_line(Vector2(x, y), Vector2(x - 2.0, y - 5.0), Color(0.55, 0.54, 0.40, 0.20), 1.4)
		draw_line(Vector2(x, y), Vector2(x + 2.0, y - 4.0), Color(0.55, 0.54, 0.40, 0.20), 1.4)

	# 主路
	draw_rect(Rect2(0, 760, WORLD_W, 62), C_PATH)
	draw_rect(Rect2(1218, 180, 64, 1350), C_PATH)
	draw_circle(Vector2(1250, 790), 150.0, C_PATH)
	# 支路
	var branches := [
		[Vector2(320, 570), Vector2(320, 760)],
		[Vector2(660, 490), Vector2(660, 760)],
		[Vector2(940, 740), Vector2(940, 790)],
		[Vector2(1596, 870), Vector2(1596, 790)],
		[Vector2(1866, 520), Vector2(1866, 760)],
		[Vector2(2196, 710), Vector2(2196, 760)],
		[Vector2(2470, 1090), Vector2(2470, 760)],
		[Vector2(1600, 1490), Vector2(1600, 1350)],
		[Vector2(392, 972), Vector2(392, 800)],
		[Vector2(1012, 386), Vector2(1012, 760)],
		[Vector2(1424, 1265), Vector2(1424, 822)],
		[Vector2(2008, 1243), Vector2(2008, 822)],
		[Vector2(520, 1360), Vector2(520, 822)],
		[Vector2(1080, 1450), Vector2(1080, 822)],
		[Vector2(430, 372), Vector2(430, 448)],
		[Vector2(2940, 492), Vector2(2940, 700)],
		[Vector2(300, 1520), Vector2(300, 1240)],
	]
	for br in branches:
		draw_line(br[0] as Vector2, br[1] as Vector2, C_PATH, 36.0)

	# 河
	draw_rect(Rect2(0, RIVER_Y, WORLD_W, WORLD_H - RIVER_Y), C_WATER)
	draw_rect(Rect2(0, RIVER_Y - 14, WORLD_W, 14), Color(0.702, 0.639, 0.510))
	for i in range(24):
		var wy := RIVER_Y + 22.0 + float(i) * 15.0
		var off := sin(t * 0.7 + float(i) * 0.5) * 12.0
		draw_line(Vector2(off, wy), Vector2(off + 160.0, wy), Color(1, 1, 1, 0.12), 1.6)

	# 村界
	for i in range(200):
		var fx := float(i) * 16.0
		draw_line(Vector2(fx, 140.0), Vector2(fx, 156.0), Color(0.40, 0.33, 0.23, 0.35), 2.0)


func _draw_building(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var w := float(b["w"])
	var h := float(b["h"])
	var kind := str(b["kind"])

	if hover_id == str(b["id"]):
		draw_rect(Rect2(pos.x - w * 0.5 - 6.0, pos.y - h * 0.5 - 6.0, w + 12.0, h + 24.0),
			Color(1.0, 0.85, 0.5, 0.14))

	if kind == "field":
		_draw_field_plot(pos, w, h)
		_draw_plot_label(str(b["name"]), pos, w, h)
		return
	if kind == "grave":
		_draw_grave_plot(pos, w, h)
		_draw_plot_label(str(b["name"]), pos, w, h)
		return
	if kind == "garden":
		_draw_garden_plot(pos, w, h)
		_draw_plot_label(str(b["name"]), pos, w, h)
		return
	if kind == "thresh":
		_draw_thresh_plot(pos, w, h)
		_draw_plot_label(str(b["name"]), pos, w, h)
		return
	if kind == "dock":
		_draw_dock_plot(pos, w, h)
		return
	if kind == "lot":
		_draw_lot_plot(pos, w, h)
		return

	draw_set_transform(-cam + pos + Vector2(0, h * 0.5 - 2.0), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, w * 0.52, Color(0.25, 0.22, 0.16, 0.16))
	draw_set_transform(-cam, 0.0, Vector2.ONE)

	var is_shop := kind == "shop"
	var is_temple := kind == "temple"
	var wall_top := pos.y - h * 0.18
	var wall_bottom := pos.y + h * 0.5

	var id := str(b["id"])
	var jit := float(absi(int(hash(id))) % 1000) / 1000.0
	var wall_col := C_BODY.lerp(Color(0.33, 0.27, 0.21), jit * 0.45)
	var roof_col := C_ROOF.lerp(Color(0.25, 0.21, 0.17), jit * 0.5)

	draw_rect(Rect2(pos.x - w * 0.5, wall_top, w, wall_bottom - wall_top), wall_col)
	for i in range(4):
		var px := pos.x - w * 0.5 + 8.0 + float(i) * (w - 16.0) / 3.0
		draw_line(Vector2(px, wall_top), Vector2(px, wall_bottom), Color(0, 0, 0, 0.26), 2.5)

	var roof_top := pos.y - h * 0.5 - 16.0
	var roof_h := h * 0.62
	var roof_left := pos.x - w * 0.5 - 16.0
	var roof_w := w + 32.0
	var roof_poly := PackedVector2Array([
		Vector2(roof_left + 6.0, roof_top),
		Vector2(roof_left + roof_w - 6.0, roof_top),
		Vector2(roof_left + roof_w, roof_top + roof_h),
		Vector2(roof_left, roof_top + roof_h),
	])
	draw_colored_polygon(roof_poly, roof_col if not is_temple else Color(0.196, 0.157, 0.129))
	draw_rect(Rect2(roof_left + 2.0, roof_top - 3.0, roof_w - 4.0, 7.0), C_ROOF2)
	var ridge := 8
	for i in range(ridge):
		var rx := roof_left + 10.0 + float(i) * (roof_w - 20.0) / float(ridge - 1)
		draw_line(Vector2(rx, roof_top + 4.0), Vector2(rx, roof_top + roof_h - 2.0),
			Color(0, 0, 0, 0.14), 1.4)
	draw_rect(Rect2(roof_left - 2.0, roof_top + roof_h - 7.0, roof_w + 4.0, 8.0),
		Color(0.098, 0.082, 0.067))

	var door_w := 46.0
	var door_top := wall_bottom - 52.0
	draw_rect(Rect2(pos.x - door_w * 0.5, door_top, door_w, 52.0), C_DOOR)
	draw_rect(Rect2(pos.x - door_w * 0.5, door_top, door_w, 52.0), Color(0, 0, 0, 0.3), false, 2.0)
	draw_rect(Rect2(pos.x - 13.0, door_top + 16.0, 26.0, 22.0), Color(0.95, 0.72, 0.38, 0.5))

	if is_shop:
		draw_rect(Rect2(pos.x - w * 0.5 + 12.0, door_top - 28.0, w - 24.0, 24.0), C_WIN)
		for i in range(4):
			var gx := pos.x - w * 0.5 + 12.0 + float(i) * (w - 24.0) / 4.0
			draw_line(Vector2(gx, door_top - 28.0), Vector2(gx, door_top - 4.0), Color(0.18, 0.13, 0.09, 0.6), 2.0)
	else:
		for sxf in [-1.0, 1.0]:
			var sx := float(sxf)
			var wx: float = pos.x + sx * (w * 0.5 - 34.0)
			draw_rect(Rect2(wx - 14.0, door_top + 4.0, 28.0, 22.0), C_WIN)
			draw_rect(Rect2(wx - 14.0, door_top + 4.0, 28.0, 22.0), Color(0.2, 0.15, 0.1, 0.5), false, 1.5)

	for sxl in [-1.0, 1.0]:
		draw_circle(Vector2(pos.x + float(sxl) * (w * 0.5 - 10.0), wall_top + 12.0), 6.0, C_LANTERN)

	var f := get_theme_default_font()
	if f != null:
		var label := str(b["name"])
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var bw := tw + 22.0
		draw_rect(Rect2(pos.x - bw * 0.5, wall_top + 2.0, bw, 24.0), Color(0.88, 0.82, 0.70))
		draw_rect(Rect2(pos.x - bw * 0.5, wall_top + 2.0, bw, 24.0), Color(0.25, 0.19, 0.14, 0.6), false, 1.2)
		draw_string(f, Vector2(pos.x - bw * 0.5, wall_top + 20.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, bw, 15, Color(0.22, 0.15, 0.09))

	if is_temple:
		draw_circle(Vector2(pos.x, roof_top - 6.0), 5.0, Color(0.831, 0.706, 0.443))
		draw_line(Vector2(pos.x, roof_top - 2.0), Vector2(pos.x, roof_top + 6.0),
			Color(0.831, 0.706, 0.443), 3.0)

	# 商幌：铺子门口挂一面竖幌
	var banner_char := {
		"market": "市", "tavern": "酒", "teahouse": "茶", "inn": "栈",
		"dye": "染", "pharmacy": "药", "smithy": "铁", "pawnshop": "当",
	}
	if banner_char.has(id):
		var bx := pos.x + w * 0.5 - 2.0
		draw_line(Vector2(bx, wall_top + 4.0), Vector2(bx, wall_top + 60.0),
			Color(0.33, 0.26, 0.18), 2.0)
		draw_rect(Rect2(bx, wall_top + 8.0, 16.0, 46.0), Color(0.706, 0.302, 0.243))
		draw_rect(Rect2(bx, wall_top + 8.0, 16.0, 46.0), Color(0.20, 0.15, 0.10, 0.5), false, 1.0)
		if f != null:
			draw_string(f, Vector2(bx, wall_top + 36.0), str(banner_char[id]),
				HORIZONTAL_ALIGNMENT_CENTER, 16.0, 14, Color(0.96, 0.90, 0.78))

	# 衙门门前石狮
	if id == "yamen":
		for sxl2 in [-1.0, 1.0]:
			var lx := pos.x + float(sxl2) * (w * 0.5 + 20.0)
			draw_circle(Vector2(lx, wall_bottom - 4.0), 9.0, Color(0.42, 0.39, 0.34))
			draw_circle(Vector2(lx, wall_bottom - 13.0), 6.0, Color(0.47, 0.44, 0.38))

	# 学塾门前一块碑
	if id == "school" or id == "academy":
		draw_rect(Rect2(pos.x - w * 0.5 - 22.0, wall_bottom - 30.0, 14.0, 30.0),
			Color(0.55, 0.53, 0.47))
		draw_rect(Rect2(pos.x - w * 0.5 - 24.0, wall_bottom - 8.0, 18.0, 8.0),
			Color(0.45, 0.43, 0.38))


func _draw_plot_label(nm: String, pos: Vector2, w: float, h: float) -> void:
	var f := get_theme_default_font()
	if f == null or nm == "":
		return
	var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var bx := pos.x - tw * 0.5 - 9.0
	var by := pos.y + h * 0.5 - 26.0
	draw_rect(Rect2(bx, by, tw + 18.0, 21.0), Color(0.88, 0.82, 0.70, 0.88))
	draw_rect(Rect2(bx, by, tw + 18.0, 21.0), Color(0.25, 0.19, 0.14, 0.5), false, 1.0)
	draw_string(f, Vector2(bx + 9.0, by + 16.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(0.24, 0.18, 0.12))


func _draw_grave_plot(pos: Vector2, w: float, h: float) -> void:
	draw_rect(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h), Color(0.44, 0.47, 0.34))
	for i in range(6):
		var gx := pos.x - w * 0.32 + float(i % 3) * (w * 0.32)
		var gy := pos.y - h * 0.20 + float(i / 3) * (h * 0.40)
		draw_circle(Vector2(gx, gy + 8.0), 15.0, Color(0.37, 0.41, 0.30))
		draw_rect(Rect2(gx - 9.0, gy - 8.0, 18.0, 16.0), Color(0.60, 0.58, 0.52))
		draw_rect(Rect2(gx - 9.0, gy - 8.0, 18.0, 16.0), Color(0.18, 0.16, 0.12, 0.35), false, 1.0)
	if hover_id != "":
		pass


func _draw_garden_plot(pos: Vector2, w: float, h: float) -> void:
	draw_rect(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h), Color(0.43, 0.46, 0.27))
	for i in range(4):
		var ry := pos.y - h * 0.34 + float(i) * (h * 0.23)
		draw_line(Vector2(pos.x - w * 0.44, ry), Vector2(pos.x + w * 0.44, ry),
			Color(0.29, 0.25, 0.16, 0.55), 8.0)
		for j in range(5):
			var cx := pos.x - w * 0.36 + float(j) * (w * 0.18)
			draw_circle(Vector2(cx, ry - 5.0), 5.0, Color(0.52, 0.68, 0.30))


func _draw_thresh_plot(pos: Vector2, w: float, h: float) -> void:
	draw_rect(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h), Color(0.58, 0.50, 0.35))
	draw_set_transform(-cam + pos + Vector2(0, 6), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, w * 0.34, Color(0.52, 0.45, 0.31))
	draw_set_transform(-cam, 0.0, Vector2.ONE)
	for i in range(3):
		var hx := pos.x - w * 0.26 + float(i) * (w * 0.26)
		draw_circle(Vector2(hx, pos.y + h * 0.16), 13.0, Color(0.72, 0.62, 0.34))


func _draw_field_plot(pos: Vector2, w: float, h: float) -> void:
	draw_rect(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h), Color(0.541, 0.451, 0.286))
	for i in range(7):
		var ry := pos.y - h * 0.5 + 8.0 + float(i) * (h - 16.0) / 7.0
		draw_line(Vector2(pos.x - w * 0.5 + 6.0, ry), Vector2(pos.x + w * 0.5 - 6.0, ry),
			Color(0.408, 0.333, 0.208, 0.5), 5.0)
		for j in range(11):
			var cx := pos.x - w * 0.5 + 12.0 + float(j) * (w - 24.0) / 11.0
			var sway := sin(t * 1.6 + float(j) + float(i)) * 2.0
			draw_line(Vector2(cx, ry), Vector2(cx + sway, ry - 14.0), Color(0.302, 0.408, 0.216), 2.0)
	draw_rect(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h), Color(0.36, 0.29, 0.18, 0.30), false, 2.0)


func _draw_dock_plot(pos: Vector2, w: float, h: float) -> void:
	draw_rect(Rect2(pos.x - w * 0.5, pos.y - 22.0, w, 48.0), Color(0.376, 0.318, 0.235))
	for i in range(8):
		var px := pos.x - w * 0.5 + 8.0 + float(i) * (w - 16.0) / 8.0
		draw_line(Vector2(px, pos.y + 6.0), Vector2(px, pos.y + 26.0), Color(0.298, 0.247, 0.180), 3.0)
	var bx := pos.x - 34.0
	var by := pos.y + 40.0
	var hull := PackedVector2Array([
		Vector2(bx, by), Vector2(bx + 80.0, by), Vector2(bx + 68.0, by + 18.0), Vector2(bx + 12.0, by + 18.0),
	])
	draw_colored_polygon(hull, Color(0.259, 0.204, 0.145))
	draw_line(Vector2(bx + 38.0, by), Vector2(bx + 38.0, by - 44.0), Color(0.298, 0.247, 0.180), 3.0)
	var sail := PackedVector2Array([
		Vector2(bx + 40.0, by - 42.0), Vector2(bx + 66.0, by - 24.0), Vector2(bx + 40.0, by - 6.0),
	])
	draw_colored_polygon(sail, Color(0.792, 0.741, 0.612, 0.9))
	draw_rect(Rect2(pos.x + 24.0, pos.y - 8.0, 28.0, 28.0), Color(0.478, 0.376, 0.243))
	var f := get_theme_default_font()
	if f != null:
		draw_rect(Rect2(pos.x - 30.0, pos.y - 74.0, 60.0, 26.0), Color(0.800, 0.741, 0.612))
		draw_string(f, Vector2(pos.x - 30.0, pos.y - 55.0), "码头",
			HORIZONTAL_ALIGNMENT_CENTER, 60.0, 16, Color(0.26, 0.19, 0.11))


func _draw_lot_plot(pos: Vector2, w: float, h: float) -> void:
	draw_rect(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h), Color(0.663, 0.608, 0.478, 0.55))
	draw_rect(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h), Color(0.40, 0.33, 0.22, 0.35), false, 2.0)
	for i in range(6):
		var gx := pos.x - 56.0 + float(i) * 24.0
		draw_line(Vector2(gx, pos.y + 24.0), Vector2(gx + 2.0, pos.y + 8.0), Color(0.35, 0.36, 0.22, 0.7), 2.0)
	draw_line(Vector2(pos.x + 38.0, pos.y + 24.0), Vector2(pos.x + 38.0, pos.y - 34.0), Color(0.40, 0.31, 0.20), 3.0)
	draw_rect(Rect2(pos.x + 16.0, pos.y - 66.0, 44.0, 32.0), Color(0.78, 0.70, 0.55))
	draw_rect(Rect2(pos.x + 16.0, pos.y - 66.0, 44.0, 32.0), Color(0.30, 0.23, 0.16, 0.6), false, 1.5)
	var f := get_theme_default_font()
	if f != null:
		draw_string(f, Vector2(pos.x + 16.0, pos.y - 42.0), "招",
			HORIZONTAL_ALIGNMENT_CENTER, 44.0, 18, Color(0.35, 0.22, 0.14))


func _draw_prop(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var r := float(p["r"])
	match str(p["kind"]):
		"tree":
			draw_set_transform(-cam + pos + Vector2(0, 6.0), 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, r * 0.9, Color(0.22, 0.22, 0.14, 0.18))
			draw_set_transform(-cam, 0.0, Vector2.ONE)
			draw_rect(Rect2(pos.x - 6.0, pos.y - 28.0, 12.0, 32.0), Color(0.286, 0.216, 0.157))
			draw_circle(pos + Vector2(0, -34.0), r * 0.66, Color(0.278, 0.337, 0.220))
			draw_circle(pos + Vector2(-r * 0.35, -20.0), r * 0.46, Color(0.239, 0.298, 0.192))
			draw_circle(pos + Vector2(r * 0.36, -22.0), r * 0.44, Color(0.302, 0.365, 0.235))
		"well":
			draw_circle(pos, r, Color(0.478, 0.427, 0.353))
			draw_circle(pos, r * 0.72, Color(0.157, 0.137, 0.114))
			draw_line(Vector2(pos.x - r - 8.0, pos.y - r * 0.6), Vector2(pos.x + r + 8.0, pos.y - r * 0.6),
				Color(0.353, 0.306, 0.243), 5.0)
		"stall":
			draw_rect(Rect2(pos.x - r, pos.y - 6.0, r * 2.0, 18.0), Color(0.478, 0.376, 0.243))
			draw_rect(Rect2(pos.x - r - 6.0, pos.y - 30.0, r * 2.0 + 12.0, 12.0), Color(0.706, 0.361, 0.259))
			for i in range(3):
				draw_circle(Vector2(pos.x - r + 6.0 + float(i) * 14.0, pos.y - 14.0), 4.0,
					Color(0.85, 0.72, 0.45))
		"rock":
			draw_circle(pos, r, Color(0.541, 0.514, 0.443))
			draw_circle(pos + Vector2(-r * 0.3, -r * 0.3), r * 0.5, Color(0.612, 0.588, 0.518))
		"hay":
			draw_circle(pos, r, Color(0.741, 0.635, 0.361))
			draw_circle(pos + Vector2(-r * 0.3, -r * 0.2), r * 0.62, Color(0.800, 0.706, 0.443))
			draw_line(Vector2(pos.x - r, pos.y + 2.0), Vector2(pos.x + r, pos.y + 2.0),
				Color(0.478, 0.400, 0.243), 2.0)
		"cart":
			draw_rect(Rect2(pos.x - r, pos.y - 10.0, r * 2.0, 18.0), Color(0.478, 0.376, 0.243))
			draw_circle(Vector2(pos.x - r * 0.7, pos.y + 10.0), 7.0, Color(0.259, 0.212, 0.161))
			draw_circle(Vector2(pos.x + r * 0.7, pos.y + 10.0), 7.0, Color(0.259, 0.212, 0.161))
			draw_line(Vector2(pos.x + r, pos.y - 2.0), Vector2(pos.x + r + 22.0, pos.y - 16.0),
				Color(0.353, 0.278, 0.192), 3.0)
		"fence":
			for i in range(7):
				var fx := pos.x - r + float(i) * (r * 2.0) / 6.0
				draw_line(Vector2(fx, pos.y), Vector2(fx, pos.y - 22.0), Color(0.400, 0.318, 0.212), 3.0)
			draw_line(Vector2(pos.x - r, pos.y - 16.0), Vector2(pos.x + r, pos.y - 16.0),
				Color(0.400, 0.318, 0.212), 2.5)


func _draw_figure(px: float, py: float, col: Color, b: Dictionary, kind: int,
		moving: bool, phase: float, face: float) -> void:
	var h := float(b.get("h", 31.0))
	var sh := float(b.get("sh", 15.0))
	var gw := float(b.get("gw", 9.5))
	var leg := float(b.get("leg", 11.5))
	var hr := float(b.get("hr", 6.5))
	if kind == 2:
		h *= 0.64
		sh *= 0.72
		gw *= 0.72
		leg *= 0.60
		hr *= 0.86
	var sw := sin(phase) * 3.2 if moving else 0.0
	var bob := absf(sin(phase)) * 1.1 if moving else 0.0

	draw_set_transform(-cam + Vector2(px, py + 2.0), 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, sh * 0.82, Color(0.15, 0.13, 0.09, 0.20))
	draw_set_transform(-cam, 0.0, Vector2.ONE)

	var hip := py - leg * 0.80
	var neck := py - h + hr * 1.5 + bob
	var limb := maxf(2.4, sh * 0.19)
	# 女性长裙盖到脚踝
	var hem := py - 4.0 if kind == 0 else hip + 3.0

	# 腿与脚
	draw_line(Vector2(px - sh * 0.22, hip), Vector2(px - sh * 0.22 - sw, py - 1.5), col, limb)
	draw_line(Vector2(px + sh * 0.22, hip), Vector2(px + sh * 0.22 + sw, py - 1.5), col, limb)
	draw_line(Vector2(px - sh * 0.22 - sw, py - 1.5), Vector2(px - sh * 0.22 - sw + face * 3.0, py - 1.5), col.darkened(0.25), 3.2)
	draw_line(Vector2(px + sh * 0.22 + sw, py - 1.5), Vector2(px + sh * 0.22 + sw + face * 3.0, py - 1.5), col.darkened(0.25), 3.2)

	# 袍身
	draw_colored_polygon(PackedVector2Array([
		Vector2(px - sh * 0.52, neck),
		Vector2(px + sh * 0.52, neck),
		Vector2(px + gw * 0.86, hem),
		Vector2(px - gw * 0.86, hem),
	]), col)
	# 肩线
	draw_line(Vector2(px - sh * 0.52, neck + 1.0), Vector2(px + sh * 0.52, neck + 1.0),
		col.darkened(0.28), 2.0)
	# 衣襟
	draw_line(Vector2(px - sh * 0.14, neck + 1.5), Vector2(px + sh * 0.08, hip - 1.0),
		col.lightened(0.30), 2.0)
	# 腰带
	draw_line(Vector2(px - gw * 0.76, hip - 0.5), Vector2(px + gw * 0.76, hip - 0.5),
		col.darkened(0.45), 3.0)

	# 手臂（比袍身暗，露在两侧）
	draw_line(Vector2(px - sh * 0.50, neck + 3.5), Vector2(px - sh * 0.60 - sw * 0.5, hip + 0.5),
		col.darkened(0.20), limb)
	draw_line(Vector2(px + sh * 0.50, neck + 3.5), Vector2(px + sh * 0.60 + sw * 0.5, hip + 0.5),
		col.darkened(0.20), limb)
	# 手
	draw_circle(Vector2(px - sh * 0.60 - sw * 0.5, hip + 0.5), limb * 0.42, col.darkened(0.35))
	draw_circle(Vector2(px + sh * 0.60 + sw * 0.5, hip + 0.5), limb * 0.42, col.darkened(0.35))

	# 脖子与头
	draw_rect(Rect2(px - hr * 0.34, neck - hr * 0.95, hr * 0.68, hr * 1.3), col)
	draw_circle(Vector2(px + face * 0.7, neck - hr * 1.15), hr, col)

	# 发式 / 头巾
	if kind == 3:
		pass
	elif kind == 0:
		draw_circle(Vector2(px + face * 0.7, neck - hr * 1.80), hr * 0.52, col.darkened(0.22))
		draw_circle(Vector2(px + face * 0.7 - hr * 0.55, neck - hr * 1.15), hr * 0.55, col.darkened(0.12))
		draw_circle(Vector2(px + face * 0.7 + hr * 0.55, neck - hr * 1.15), hr * 0.55, col.darkened(0.12))
	elif kind == 1:
		draw_rect(Rect2(px - hr * 1.02, neck - hr * 1.78, hr * 2.04, hr * 0.62), col.darkened(0.26))
	else:
		draw_rect(Rect2(px - hr * 0.98, neck - hr * 1.86, hr * 1.96, hr * 0.58), col.darkened(0.30))
		draw_line(Vector2(px - hr * 1.1, neck - hr * 1.52), Vector2(px + hr * 1.1, neck - hr * 1.52),
			col.darkened(0.30), 1.4)


func _draw_npc(n: Dictionary) -> void:
	var pos: Vector2 = n["pos"]
	if pos.x < cam.x - 80.0 or pos.x > cam.x + W + 80.0 or pos.y < cam.y - 80.0 or pos.y > cam.y + H + 80.0:
		return
	var kind := int(n["kind"])
	var tone := float(absi(int(hash(str(n.get("id", ""))))) % 100) / 100.0
	var col := Color(0.180, 0.145, 0.114, 0.95)
	if kind == 3:
		col = Color(0.353, 0.286, 0.212, 0.95)
	elif kind == 4:
		col = Color(0.263, 0.220, 0.169, 0.95)
	elif kind == 2:
		col = Color(0.243, 0.196, 0.153, 0.95)
	col = col.lerp(Color(0.30, 0.24, 0.18), tone * 0.35)

	var b: Dictionary = n.get("build", BUILDS[1])
	var target: Vector2 = n.get("target", pos)
	var moving := pos.distance_to(target) > 1.0
	_draw_figure(pos.x, pos.y, col, b, kind, moving, float(n["phase"]), float(n.get("dir", 1.0)))
	var hgt := float(b.get("h", 31.0))
	if kind == 2:
		hgt *= 0.64

	if kind == 1:
		draw_line(Vector2(pos.x - 13.0, pos.y - hgt + 4.0), Vector2(pos.x + 13.0, pos.y - hgt + 4.0),
			Color(0.35, 0.27, 0.18), 2.0)
		draw_circle(Vector2(pos.x - 13.0, pos.y - hgt + 10.0), 5.0, Color(0.45, 0.36, 0.24))
		draw_circle(Vector2(pos.x + 13.0, pos.y - hgt + 10.0), 5.0, Color(0.45, 0.36, 0.24))
	elif kind == 3:
		var hat := PackedVector2Array([
			Vector2(pos.x - 10.0, pos.y - hgt - 3.0), Vector2(pos.x + 10.0, pos.y - hgt - 3.0),
			Vector2(pos.x, pos.y - hgt - 11.0),
		])
		draw_colored_polygon(hat, Color(0.478, 0.400, 0.286))

	if bool(n.get("named", false)):
		var f := get_theme_default_font()
		if f != null:
			var nm := str(n.get("name", ""))
			var is_hover := hover_npc == str(n.get("id", ""))
			var bw2 := 96.0
			var bx2 := pos.x - bw2 * 0.5
			var by2 := pos.y - hgt - 30.0
			if is_hover:
				draw_rect(Rect2(bx2 - 6.0, by2 - 17.0, bw2 + 12.0, 26.0), Color(0.965, 0.937, 0.878, 0.96))
				draw_rect(Rect2(bx2 - 6.0, by2 - 17.0, bw2 + 12.0, 26.0), Color(0.741, 0.259, 0.176, 0.65), false, 1.2)
			draw_string(f, Vector2(bx2, by2), nm, HORIZONTAL_ALIGNMENT_CENTER, bw2, 15,
				Color(0.24, 0.16, 0.10) if is_hover else Color(0.28, 0.23, 0.17, 0.70))


func _draw_player() -> void:
	var x := player.x
	var y := player.y
	if not can_walk:
		# 婴儿：襁褓里的一小团，被母亲抱着
		draw_circle(Vector2(x, y - 4.0), 7.0, C_SIL)
		draw_rect(Rect2(x - 6.0, y - 2.0, 12.0, 9.0), C_SIL)
		draw_circle(Vector2(x, y - 9.0), 4.0, C_SIL)
		return
	var bob := sin(walk_phase) * 1.6 if moving else 0.0
	var leg := sin(walk_phase) * 4.0 if moving else 0.0

	_draw_figure(x, y, C_SIL, player_build, 4, moving, walk_phase, facing)

	if moving and path_i < path.size():
		var dest: Vector2 = path[path.size() - 1]
		var a := 0.35 + 0.2 * sin(t * 8.0)
		draw_circle(dest, 6.0, Color(0.741, 0.259, 0.176, a))
		draw_circle(dest, 11.0, Color(0.741, 0.259, 0.176, a * 0.4))
		# 路径点
		for i in range(path_i, path.size()):
			draw_circle(path[i] as Vector2, 2.0, Color(0.741, 0.259, 0.176, 0.18))


func _draw_hud() -> void:
	var f := get_theme_default_font()
	if f == null:
		return

	draw_rect(Rect2(0, 0, W, 62), Color(0.965, 0.937, 0.878, 0.92))
	draw_line(Vector2(0, 62), Vector2(W, 62), Color(0.30, 0.24, 0.18, 0.25), 1.0)
	draw_string(f, Vector2(30, 40), DB.era_label(year) + " · " + _month_name() + "　" + _shichen()
		+ "　·　档" + str(slot) + "　·　流速 %.0f×" % time_scale,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_INK)
	draw_string(f, Vector2(0, 40), _pov_name() + "　" + _cn(age) + "岁",
		HORIZONTAL_ALIGNMENT_CENTER, W, 22, C_INK)
	draw_string(f, Vector2(W - 330, 40), "家资 " + _money_text(),
		HORIZONTAL_ALIGNMENT_CENTER, 300, 21, C_INK)

	draw_rect(Rect2(0, H - 54, W, 54), Color(0.965, 0.937, 0.878, 0.94))
	draw_line(Vector2(0, H - 54), Vector2(W, H - 54), Color(0.30, 0.24, 0.18, 0.22), 1.0)
	var status := "学识 %s　　技艺 %s　　声望 %s　　身体 %s" % [
		_word(learning), _word(craft), _word(fame), _word(health)
	]
	if craft_rank > 0:
		status += "　　" + _rank_name()
	if trade_rank > 0:
		status += "　　" + _trade_name()
	if med_rank > 0:
		status += "　　医术" + _word(medicine)
	if land > 0:
		status += "　　田 %d 亩" % land
	if mil_rank > 0:
		status += "　　" + _mil_name()
		if merit > 0:
			status += "（功 %d）" % merit
	if office_rank > 0:
		status += "　　" + _office_name()
		if gov_merit > 0:
			status += "（绩 %d）" % gov_merit
	if women_rank > 0 and pov == "mother":
		status += "　　" + _women_name()
	draw_string(f, Vector2(30, H - 20), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.30, 0.26, 0.20))

	if shop_open and (panel == null or not panel.visible):
		draw_string(f, Vector2(W - 620, H - 20), _shop_hud(),
			HORIZONTAL_ALIGNMENT_CENTER, 600, 16, Color(0.45, 0.30, 0.14))

	var hint := _hint()
	if hint != "":
		draw_string(f, Vector2(0, H - 66), "·　" + hint + "　·",
			HORIZONTAL_ALIGNMENT_CENTER, W, 15, Color(0.38, 0.30, 0.20, 0.80))

	# 人不在视野里时，边缘给方向
	var sp := player - cam
	if sp.x < 0.0 or sp.x > W or sp.y < 62.0 or sp.y > H:
		var ex := clampf(sp.x, 56.0, W - 56.0)
		var ey := clampf(sp.y, 96.0, H - 96.0)
		draw_circle(Vector2(ex, ey), 9.0, Color(0.741, 0.259, 0.176, 0.55))
		draw_circle(Vector2(ex, ey), 15.0, Color(0.741, 0.259, 0.176, 0.18))
		draw_string(f, Vector2(ex - 90.0, ey - 18.0), "你在这儿",
			HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, Color(0.35, 0.22, 0.14, 0.85))


func _draw_minimap() -> void:
	var r := _mm_rect()
	var mw := r.size.x
	var mh := r.size.y
	var mx := r.position.x
	var my := r.position.y
	draw_rect(r, Color(0.965, 0.937, 0.878, 0.88))
	draw_rect(r, Color(0.30, 0.24, 0.18, 0.35), false, 1.2)

	var sx := mw / WORLD_W
	var sy := mh / WORLD_H

	# 河
	draw_rect(Rect2(mx, my + RIVER_Y * sy, mw, (WORLD_H - RIVER_Y) * sy),
		Color(0.502, 0.616, 0.624, 0.85))
	# 路
	draw_rect(Rect2(mx, my + 760.0 * sy, mw, 62.0 * sy), Color(0.788, 0.722, 0.576, 0.9))
	draw_rect(Rect2(mx + 1218.0 * sx, my + 180.0 * sy, 64.0 * sx, 1350.0 * sy), Color(0.788, 0.722, 0.576, 0.9))

	for b in buildings:
		var bp: Vector2 = b["pos"]
		var bx := mx + bp.x * sx
		var by := my + bp.y * sy
		var col := Color(0.30, 0.24, 0.18)
		if str(b["kind"]) == "shop":
			col = Color(0.741, 0.259, 0.176)
		elif str(b["kind"]) == "field":
			col = Color(0.480, 0.500, 0.260)
		draw_rect(Rect2(bx - 3.0, by - 3.0, 6.0, 6.0), col)

	# 视野框
	draw_rect(Rect2(mx + cam.x * sx, my + cam.y * sy, W * sx, H * sy),
		Color(0.35, 0.28, 0.20, 0.45), false, 1.2)
	# 玩家
	draw_circle(Vector2(mx + player.x * sx, my + player.y * sy), 4.0, Color(0.741, 0.259, 0.176))


func _draw_toasts() -> void:
	var f := get_theme_default_font()
	if f == null:
		return
	var idx := 0
	for item in toasts:
		var d: Dictionary = item
		var life := float(d["life"])
		var a := clampf(life / 1.2, 0.0, 1.0)
		var c: Color = d["color"]
		var text := str(d["text"])
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var bw := tw + 52.0
		var bx := (W - bw) * 0.5
		var by := 80.0 + float(idx) * 46.0 - (3.0 - life) * 4.0
		draw_rect(Rect2(bx, by, bw, 40.0), Color(0.965, 0.937, 0.878, 0.96 * a))
		draw_rect(Rect2(bx, by, bw, 40.0), Color(0.30, 0.24, 0.18, 0.28 * a), false, 1.0)
		draw_string(f, Vector2(bx, by + 27.0), text, HORIZONTAL_ALIGNMENT_CENTER, bw, 19,
			Color(c.r, c.g, c.b, a))
		idx += 1


func _toast(text: String, color: Color) -> void:
	toasts.append({"text": text, "color": color, "life": 3.0})
	if toasts.size() > 3:
		toasts.pop_front()
	queue_redraw()


# ---------------------------------------------------------------- 文本

func _cn(n: int) -> String:
	return DB.cn(n)


func _month_name() -> String:
	if month == 1:
		return "正月"
	if month == 11:
		return "十一月"
	if month == 12:
		return "腊月"
	return _cn(month) + "月"


func _shichen() -> String:
	var names := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
	var idx := int(floor(fmod(hour + 1.0, 24.0) / 2.0)) % 12
	return names[idx] + "时"


func _money_text() -> String:
	if money >= 1000:
		var g := int(money / 1000.0)
		var m := (money % 1000) / 100
		if m == 0:
			return "%d贯" % g
		return "%d贯%d陌" % [g, m]
	return "%d文" % money


func _word(v: float) -> String:
	if v >= 85.0:
		return "极"
	elif v >= 70.0:
		return "甚"
	elif v >= 55.0:
		return "颇"
	elif v >= 40.0:
		return "寻常"
	elif v >= 25.0:
		return "略"
	elif v >= 12.0:
		return "薄"
	return "无"
