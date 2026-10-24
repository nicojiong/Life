extends RefCounted
## 统一的视觉语言：绢纸底色、墨色文字、朱砂点缀。

const PAPER := Color(0.914, 0.882, 0.812)
const PAPER_DEEP := Color(0.878, 0.839, 0.765)
const INK := Color(0.165, 0.141, 0.114)
const FADED := Color(0.431, 0.384, 0.314)
const CINNABAR := Color(0.608, 0.227, 0.180)
const HAIR := Color(0.251, 0.211, 0.161, 0.26)


static func label(text: String, size: int, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap_label(text: String, size: int, color: Color = INK) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func rich(text: String = "") -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = false
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", 22)
	r.add_theme_font_size_override("bold_font_size", 22)
	r.add_theme_font_size_override("italics_font_size", 22)
	r.add_theme_color_override("default_color", INK)
	return r


static func choice(text: String) -> Button:
	var b := Button.new()
	b.text = "▸　" + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", CINNABAR)
	b.add_theme_color_override("font_pressed_color", CINNABAR)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.41, 0.35, 0.45))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0)
	normal.border_width_left = 2
	normal.border_color = Color(0.251, 0.211, 0.161, 0.18)
	normal.content_margin_left = 18
	normal.content_margin_right = 16
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	b.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.35, 0.28, 0.20, 0.055)
	hover.border_color = CINNABAR
	b.add_theme_stylebox_override("hover", hover)

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.35, 0.28, 0.20, 0.11)
	b.add_theme_stylebox_override("pressed", pressed)

	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", normal)
	return b


static func ink_button(text: String, w: int = 240) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 54)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", CINNABAR)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.251, 0.211, 0.161, 0.03)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.251, 0.211, 0.161, 0.32)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.608, 0.227, 0.180, 0.08)
	hover.border_color = CINNABAR
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func hair() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = HAIR
	sb.thickness = 1
	s.add_theme_stylebox_override("separator", sb)
	return s
