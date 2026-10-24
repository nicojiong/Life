extends Control
## 纸纹与界画边框。

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := get_rect()
	var outer := Rect2(Vector2(22, 18), r.size - Vector2(44, 36))
	draw_rect(outer, Color(0.25, 0.21, 0.16, 0.22), false, 1.0)
	var inner := Rect2(Vector2(28, 24), r.size - Vector2(56, 48))
	draw_rect(inner, Color(0.25, 0.21, 0.16, 0.09), false, 1.0)

	# 几处淡淡的墨点，模拟旧纸
	var seedv := 20261023
	for i in range(26):
		seedv = (seedv * 1103515245 + 12345) & 0x7fffffff
		var x := float(seedv % 10000) / 10000.0 * r.size.x
		seedv = (seedv * 1103515245 + 12345) & 0x7fffffff
		var y := float(seedv % 10000) / 10000.0 * r.size.y
		seedv = (seedv * 1103515245 + 12345) & 0x7fffffff
		var rad := 1.0 + float(seedv % 100) / 60.0
		draw_circle(Vector2(x, y), rad, Color(0.25, 0.21, 0.16, 0.045))
