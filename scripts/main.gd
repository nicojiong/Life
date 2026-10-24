extends Control
## 入口：主题、背景、调试舞台与截图。

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const SAVE_PATH := "user://fusheng_save.json"

var screen: Control
var shot_path := ""
var shot_stage := "village"
var shot_frames := 4
var shot_wait_ms := 1200


func _ready() -> void:
	theme = _build_theme()
	get_window().title = "浮生"
	_build_bg()
	_parse_args()

	if _has_arg("--fresh"):
		# 只有显式声明测试环境才允许删档，防止误删真实存档
		if OS.get_environment("LIFE_ALLOW_SAVE_WIPE") == "1" and _isolated_user_dir():
			_clear_save()
		else:
			push_warning("--fresh 被拒绝：需要在隔离数据目录下并设置 LIFE_ALLOW_SAVE_WIPE=1")

	_show_stage(shot_stage)

	if shot_path != "":
		_capture_after(shot_frames)


# ---------------------------------------------------------------- 主题与背景

func _build_theme() -> Theme:
	var t := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"KaiTi", "STKaiti", "SimSun", "Songti SC",
		"Noto Serif CJK SC", "Microsoft YaHei", "SimHei",
	])
	f.allow_system_fallback = true
	t.default_font = f
	t.default_font_size = 20
	return t


func _build_bg() -> void:
	var cr := ColorRect.new()
	cr.color = UIKit.PAPER
	cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cr)

	var pb: Control = preload("res://scripts/ui/paper_bg.gd").new()
	add_child(pb)


# ---------------------------------------------------------------- 页面

func _swap(n: Control) -> void:
	if screen != null and is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = n
	add_child(n)


func show_village() -> Control:
	var s = preload("res://scripts/street/village_scene.gd").new()
	if _has_arg("--no-intro"):
		s.skip_intro = true
	_swap(s)
	return s


# ---------------------------------------------------------------- 调试舞台

func _show_stage(stage: String) -> void:
	match stage:
		"verify_smoke":
			var v = show_village()
			v.call_deferred("_run_verify_smoke")
		"village_night":
			var a = show_village()
			a.hour = 22.0
			a.shop_open = true
			a.shop_label = "绸庄"
			a.shop = {"kind": "silk", "stock": 40, "price": 1, "helper": false, "market": 1.05, "rival": 1}
			a.call_deferred("_rebuild")
		"village_winter":
			var b = show_village()
			b.month = 12
			b.hour = 14.0
		"village_dialog":
			var c = show_village()
			c.call_deferred("debug_dialog", "li_shen")
		"village_talk":
			var d = show_village()
			d.call_deferred("walk_to_npc", "li_shen")
		"village_marry":
			var e = show_village()
			e.age = 14
			e.call_deferred("_on_new_year")
			e.call_deferred("walk_to_npc", "meiren")
		"village_shop":
			var f = show_village()
			f.age = 24
			f.money = 30000
			f.shop_open = true
			f.shop_label = "绸庄"
			f.shop = {"kind": "silk", "stock": 40, "price": 1, "helper": false, "market": 1.05, "rival": 1}
			f.player = Vector2(2470.0, 1180.0)
			f.cam = Vector2(1830.0, 780.0)
			f.call_deferred("_rebuild")
			f.call_deferred("_open_panel", "shop")
		"village_pan":
			var k = show_village()
			k.cam = Vector2(1820.0, 900.0)
		"village_years":
			var m = show_village()
			m.money = 20000
			m.married = true
			m.spouse_name = "李氏"
			m.call_deferred("debug_years", 60)
		"village_exam":
			var n = show_village()
			n.call_deferred("debug_exam")
		"village_epitaph":
			var o = show_village()
			o.call_deferred("debug_epitaph", int(_arg_value("--tier", "0")))
		"village_craft":
			var q = show_village()
			q.call_deferred("debug_craft")
		"village_trade":
			var t = show_village()
			t.call_deferred("debug_trade")
		"village_med":
			var v = show_village()
			v.call_deferred("debug_med")
		"village_farm":
			var fa = show_village()
			fa.call_deferred("debug_farm")
		"village_mil":
			var mb = show_village()
			mb.call_deferred("debug_mil")
		"village_events":
			var ev = show_village()
			ev.call_deferred("debug_events")
		"village_warm":
			var wv = show_village()
			wv.call_deferred("debug_warm")
		"village_polish":
			var pl = show_village()
			pl.call_deferred("debug_polish")
		"village_child":
			var ch = show_village()
			ch.call_deferred("debug_child")
		"village_office":
			var of = show_village()
			of.call_deferred("debug_office")
		"village_switch":
			var sw = show_village()
			sw.call_deferred("debug_switch")
		"village_kid":
			var kd = show_village()
			kd.call_deferred("debug_child2")
		"village_corners":
			var cn = show_village()
			cn.cam = Vector2(0, 120)
			cn.player = Vector2(430, 380)
			cn.call_deferred("debug_corners")
		"village_playmate":
			var pm = show_village()
			pm.age = 4
			pm.player = Vector2(430.0, 660.0)
			pm.call_deferred("_open_dialog_by_id", "a_he")
		"village_mixed":
			var mx = show_village()
			mx.age = 40
			mx.craft_rank = 2
			mx.trade_rank = 1
			mx.farm_rank = 2
			mx.land = 6
			mx.med_rank = 2
			mx.medicine = 40.0
			mx.mil_rank = 1
			mx.merit = 1
			mx.busy = false
		"village_yamen":
			var ym = show_village()
			ym.story["进士"] = true
			ym.office_rank = 2
			ym.gov_merit = 15
			ym.county = "吴县"
			ym.money = 8000
			ym.age = 34
			ym.player = Vector2(2060.0, 820.0)
			ym.call_deferred("_open_panel", "yamen")
		"village_baby":
			var bb = show_village()
			bb.busy = false
			bb.age = 0
			bb.player = Vector2(330.0, 620.0)
			bb.call_deferred("_open_panel", "home")
		"village_child_year":
			var cy = show_village()
			cy.busy = false
			cy.age = 3
			cy.call_deferred("debug_child")
		"village_walk":
			var wk = show_village()
			wk.call_deferred("debug_walk")
		"village_pov":
			var pv = show_village()
			pv.call_deferred("debug_pov")
		"village_father":
			var ft = show_village()
			ft.call_deferred("debug_as_father")
		"village_mother":
			var mo = show_village()
			mo.call_deferred("debug_mother")
		"village_mom_panel":
			var mp = show_village()
			mp.call_deferred("debug_mom_panel")
		"village_scenes":
			var sc = show_village()
			sc.call_deferred("debug_scenes")
		"village_scene_panel":
			var sp = show_village()
			sp.call_deferred("debug_scene_panel")
		"village_festival":
			var fe = show_village()
			fe.call_deferred("debug_festival_memory")
		"village_infant":
			var inf = show_village()
			inf.cam = Vector2(0, 320)
			inf.busy = false
		"village_war_death":
			var wd = show_village()
			wd.death_cause = "战死"
			wd.mil_rank = 3
			wd.merit = 6
			wd.fame = 52.0
			wd.age = 34
			wd.call_deferred("_show_epitaph")
		"village_field":
			var fb = show_village()
			fb.farm_rank = 2
			fb.land = 10
			fb.money = 6000
			fb.player = Vector2(940.0, 780.0)
			fb.call_deferred("_open_panel", "field")
		"village_pharmacy":
			var w = show_village()
			w.med_rank = 1
			w.medicine = 40.0
			w.money = 3000
			w.player = Vector2(2020.0, 1010.0)
			w.call_deferred("_open_panel", "pharmacy")
		"village_market":
			var u = show_village()
			u.trade_rank = 1
			u.money = 25000
			u.shop_open = true
			u.shop_label = "绸庄"
			u.shop = {"kind": "silk", "stock": 40, "price": 1, "helper": false, "market": 1.05, "rival": 1}
			u.player = Vector2(1268.0, 566.0)
			u.call_deferred("_rebuild")
			u.call_deferred("_open_panel", "market")
		"village_smithy":
			var r = show_village()
			r.craft_rank = 1
			r.craft = 46.0
			r.money = 6000
			r.player = Vector2(392.0, 1050.0)
			r.call_deferred("_open_panel", "smithy")
		"village_shop_run":
			var g = show_village()
			g.age = 24
			g.money = 30000
			g.shop_open = true
			g.shop_label = "绸庄"
			g.shop = {"kind": "silk", "stock": 0, "price": 1, "helper": false, "market": 1.05, "rival": 1}
			g.call_deferred("debug_shop_run")
		"village_act":
			var h = show_village()
			h.call_deferred("debug_action", "school", 0)
		"village_save":
			var i = show_village()
			i.call_deferred("debug_save")
		"village_load":
			var j = show_village()
			j.call_deferred("debug_load")
		_:
			show_village()


# ---------------------------------------------------------------- 命令行

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var arg := str(a)
		if arg.begins_with("--shot="):
			shot_path = arg.substr(7)
		elif arg.begins_with("--stage="):
			shot_stage = arg.substr(8)
		elif arg.begins_with("--frames="):
			shot_frames = int(arg.substr(9))
		elif arg.begins_with("--wait="):
			shot_wait_ms = int(arg.substr(7))


func _has_arg(key: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if str(a) == key:
			return true
	return false


func _arg_value(key: String, fallback: String) -> String:
	var prefix := key + "="
	for a in OS.get_cmdline_user_args():
		var arg := str(a)
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback


func _clear_save() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	# 三个槽 + 旧版单文件，一并清掉
	for f in ["fusheng_save.json", "fusheng_save_1.json", "fusheng_save_2.json", "fusheng_save_3.json"]:
		if FileAccess.file_exists("user://" + f):
			dir.remove(f)


func _isolated_user_dir() -> bool:
	# tools/verify.ps1 会把项目复制到临时目录并把 config/name 改成 LifeVerify-<id>
	return OS.get_user_data_dir().find("LifeVerify") >= 0


func _capture_after(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
	var until := Time.get_ticks_msec() + shot_wait_ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot_path)
	print("[SHOT] %s -> %s (%dx%d)" % [shot_path, error_string(err), img.get_width(), img.get_height()])
	get_tree().quit()
