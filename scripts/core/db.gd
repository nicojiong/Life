extends Node
## 数据层：时代年号、出身、姓名，以及中文数字/纪年这些公用小工具。

var era: Dictionary = {}
var origins: Array = []
var names: Dictionary = {}
var events: Array = []
var loaded := false


func _ready() -> void:
	load_all()


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[DB] 缺少数据文件: " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[DB] 无法打开: " + path)
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_error("[DB] JSON 解析失败: " + path)
	return parsed


func load_all() -> void:
	era = _load_json("res://data/era/song.json")
	if era == null:
		era = {}
	origins = _load_json("res://data/origins.json")
	if origins == null:
		origins = []
	names = _load_json("res://data/names.json")
	if names == null:
		names = {}
	events = _load_json("res://data/events.json")
	if events == null:
		events = []
	print("[DB] 出身 %d 种，年号 %d 个，事件 %d 条" % [origins.size(), era.get("eras", []).size(), events.size()])
	loaded = true


func pick_origin(rng: RandomNumberGenerator) -> Dictionary:
	if origins.is_empty():
		return {}
	var total := 0.0
	for o in origins:
		total += float(o.get("weight", 10))
	var roll := rng.randf() * total
	for o in origins:
		roll -= float(o.get("weight", 10))
		if roll <= 0.0:
			return o
	return origins[origins.size() - 1]


func make_name(rng: RandomNumberGenerator, gender: String) -> Dictionary:
	var surnames: Array = names.get("surnames", ["陈"])
	var s: String = str(surnames[rng.randi_range(0, surnames.size() - 1)])
	var g := ""
	if gender == "女":
		var ff: Array = names.get("female_first", ["淑"])
		g = str(ff[rng.randi_range(0, ff.size() - 1)]) + "娘"
	else:
		var mf: Array = names.get("male_first", ["守"])
		var ms: Array = names.get("male_second", ["之"])
		g = str(mf[rng.randi_range(0, mf.size() - 1)]) + str(ms[rng.randi_range(0, ms.size() - 1)])
	return {"surname": s, "given": g, "full": s + g}


## 公历年份 → 年号纪年，例如 1043 → 庆历三年
func era_label(y: int) -> String:
	var eras: Array = era.get("eras", [])
	for e in eras:
		if y >= int(e[0]) and y <= int(e[1]):
			var idx := y - int(e[0]) + 1
			var num := "元" if idx == 1 else cn(idx)
			return str(e[2]) + num + "年"
	if y < 1038:
		return "景祐年间"
	return "建炎以后"


## 阿拉伯数字 → 汉字数字（0–999）
func cn(n: int) -> String:
	var d: Array = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if n <= 0:
		return "零"
	if n < 10:
		return str(d[n])
	if n == 10:
		return "十"
	if n < 20:
		return "十" + str(d[n % 10])
	if n < 100:
		var s: String = str(d[int(n / 10.0)]) + "十"
		if n % 10 != 0:
			s += str(d[n % 10])
		return s
	var h: String = str(d[int(n / 100.0)]) + "百"
	var rest: int = n % 100
	if rest == 0:
		return h
	if rest < 10:
		return h + "零" + str(d[rest])
	if rest < 20:
		return h + "一" + str(d[rest % 10])
	var t: String = h + str(d[int(rest / 10.0)]) + "十"
	if rest % 10 != 0:
		t += str(d[rest % 10])
	return t


func event_def(id: String) -> Dictionary:
	for e in events:
		if str((e as Dictionary).get("id", "")) == id:
			return e
	return {}
