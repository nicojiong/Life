extends Control
## 过场演出：黑场、月轮、逐字浮现的字幕。点击推进。

signal finished

const C_INK := Color(0.075, 0.059, 0.047)
const C_PAPER := Color(0.925, 0.878, 0.792)
const C_FADED := Color(0.706, 0.639, 0.522)

var _title := ""
var _lines: Array = []
var _revealed := 0
var _chars := 0.0
var _t := 0.0
var _closing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	set_process(true)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.45)


func play(title: String, lines: Array) -> void:
	_title = title
	_lines = lines
	_revealed = 1 if lines.size() > 0 else 0
	_chars = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _revealed > 0 and _revealed <= _lines.size():
		var cur := str(_lines[_revealed - 1])
		_chars = minf(float(cur.length()), _chars + delta * 26.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _advance() -> void:
	if _revealed < _lines.size():
		_revealed += 1
		_chars = 0.0
	else:
		_closing = true
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.4)
		tw.finished.connect(func():
			finished.emit()
			queue_free()
		)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), C_INK)

	# 月轮
	draw_circle(Vector2(w * 0.5, h * 0.30), 100.0, Color(0.95, 0.90, 0.80, 0.028))
	draw_arc(Vector2(w * 0.5, h * 0.30), 92.0, 0.0, TAU, 72,
		Color(0.86, 0.79, 0.65, 0.16), 1.2)

	var font := get_theme_default_font()
	if font == null:
		return

	# 标题
	draw_string(font, Vector2(0, h * 0.235), _title,
		HORIZONTAL_ALIGNMENT_CENTER, w, 40, C_PAPER)

	# 分隔线
	var lw := 90.0
	draw_line(Vector2(w * 0.5 - lw, h * 0.255), Vector2(w * 0.5 + lw, h * 0.255),
		Color(0.70, 0.62, 0.50, 0.35), 1.0)

	# 已显示的行
	var y := h * 0.40
	var last_index := _revealed - 1
	for i in range(_revealed):
		var full := str(_lines[i])
		var shown := full
		if i == last_index:
			shown = full.substr(0, int(_chars))
		var alpha := 1.0 if i < last_index else 0.92
		draw_string(font, Vector2(0, y), shown,
			HORIZONTAL_ALIGNMENT_CENTER, w, 25, Color(C_PAPER.r, C_PAPER.g, C_PAPER.b, alpha))
		y += 46.0

	# 提示
	if _revealed >= _lines.size():
		var blink := 0.45 + 0.25 * sin(_t * 2.4)
		draw_string(font, Vector2(0, h - 90), "点 击 继 续",
			HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(C_FADED.r, C_FADED.g, C_FADED.b, blink))
