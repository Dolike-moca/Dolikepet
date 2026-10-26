extends RefCounted
## Theme scoped to the settings window, never to the pet or other overlays.
const TEXT := Color("ecebf1")
const MUTED := Color("a19dab")
const ACCENT := Color("ab91ef")

static func box(color: Color, radius: int = 7, padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 0 if padding == 0 else 7
	style.content_margin_bottom = 0 if padding == 0 else 7
	return style

static func make() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	result.default_font = font
	result.default_font_size = 14
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", MUTED)
	result.set_stylebox("panel", "PanelContainer", box(Color("141318"), 0, 0))
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, box(Color("25232b")))
		result.set_stylebox("hover", type, box(Color("34303e")))
		result.set_stylebox("pressed", type, box(Color("47365e")))
		result.set_stylebox("disabled", type, box(Color("1f1d25")))
		var focus := box(Color.TRANSPARENT)
		focus.set_border_width_all(1)
		focus.border_color = ACCENT
		result.set_stylebox("focus", type, focus)
	result.set_stylebox("normal", "LineEdit", box(Color("25232b")))
	result.set_color("font_color", "LineEdit", TEXT)
	result.set_color("caret_color", "LineEdit", ACCENT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		result.set_stylebox(state, "CheckButton", box(Color.TRANSPARENT, 0, 0))
	var slider_track := box(Color("302c38"), 3, 0)
	slider_track.content_margin_top = 3
	slider_track.content_margin_bottom = 3
	result.set_stylebox("slider", "HSlider", slider_track)
	var slider_fill := slider_track.duplicate()
	slider_fill.bg_color = ACCENT
	result.set_stylebox("grabber_area", "HSlider", slider_fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	result.set_stylebox("background", "ProgressBar", box(Color("2c2934"), 4, 0))
	result.set_stylebox("fill", "ProgressBar", box(ACCENT, 4, 0))
	var line := StyleBoxLine.new()
	line.color = Color("2b2832")
	line.thickness = 1
	result.set_stylebox("separator", "HSeparator", line)
	for on in [false, true]:
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="36" height="22"><rect x="1" y="1" width="34" height="20" rx="10" fill="%s"/><circle cx="%d" cy="11" r="7" fill="#f5f2fc"/></svg>' % ["#9370d8" if on else "#49454f", 25 if on else 11]
		var image := Image.new()
		image.load_svg_from_string(svg)
		var texture := ImageTexture.create_from_image(image)
		for suffix in ["", "_mirrored"]:
			result.set_icon(("checked" if on else "unchecked") + suffix, "CheckButton", texture)
	return result
