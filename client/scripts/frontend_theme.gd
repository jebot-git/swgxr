extends RefCounted
## Front-end controls share the datapad palette and compact face.
const DatapadTheme = preload("res://scripts/datapad_theme.gd")
const INK := Color("c9fbff")
const MUTED := Color("91bdcc")
const ACCENT := Color("67dcea")

static func build() -> Theme:
	var result := DatapadTheme.build()
	result.default_font_size = 22
	result.set_color("font_disabled_color", "Button", Color("547684"))
	result.set_stylebox("disabled", "Button", DatapadTheme.box("091c28", "203e4c", 1, 12))
	for type in ["OptionButton", "LineEdit", "TextEdit", "PopupMenu", "TabBar"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_selected_color", type, Color.WHITE)
		result.set_color("font_disabled_color", type, Color("547684"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		result.set_stylebox(state, "OptionButton", result.get_stylebox(state, "Button"))
	for type in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type, DatapadTheme.box("061722", "2b6477", 1, 12))
		result.set_stylebox("read_only", type, DatapadTheme.box("081c28", "245363", 1, 12))
		var focus := DatapadTheme.box("061722", "67dcea", 2, 12)
		focus.draw_center = false
		result.set_stylebox("focus", type, focus)
		result.set_color("caret_color", type, ACCENT)
		result.set_color("selection_color", type, Color("23627b"))
		result.set_color("font_placeholder_color", type, MUTED)
	result.set_stylebox("panel", "PopupMenu", DatapadTheme.box("071c29", "67dcea", 2, 12))
	result.set_stylebox("hover", "PopupMenu", DatapadTheme.box("164c60", "67dcea", 1, 8))
	result.set_constant("v_separation", "PopupMenu", 16)
	result.set_stylebox("panel", "TabContainer", DatapadTheme.box("071c29", "245363", 1, 18))
	for type in ["TabContainer", "TabBar"]:
		for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
			result.set_stylebox(state, type, DatapadTheme.box("164c60" if state == "tab_selected" else "0a2636", "67dcea" if state == "tab_selected" else "2b6477", 1, 12))
		result.set_color("font_unselected_color", type, MUTED)
		result.set_color("font_selected_color", type, INK)
		result.set_font_size("font_size", type, 20)
	result.set_stylebox("slider", "HSlider", DatapadTheme.box("164051", "2b6477", 1, 4))
	result.set_stylebox("grabber_area", "HSlider", DatapadTheme.box("3ea8b9", "67dcea", 0, 4))
	result.set_stylebox("grabber_area_highlight", "HSlider", DatapadTheme.box("67dcea", "67dcea", 0, 4))
	for type in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", type, DatapadTheme.box("061722", "163b4b", 0, 7))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type, DatapadTheme.box("3ea8b9", "67dcea", 0, 7))
	result.set_stylebox("separator", "HSeparator", DatapadTheme.box("245363", "245363", 0, 1))
	return result
