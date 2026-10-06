extends RefCounted
## Front-end controls share the datapad palette and compact face.
const DatapadTheme = preload("res://scripts/datapad_theme.gd")
const INK := DatapadTheme.INK
const MUTED := DatapadTheme.MUTED
const ACCENT := DatapadTheme.ACCENT

static func build() -> Theme:
	var result := DatapadTheme.build()
	result.default_font_size = 22
	result.set_color("font_disabled_color", "Button", Color("547684"))
	result.set_stylebox("disabled", "Button", DatapadTheme.button("disabled"))
	for type in ["OptionButton", "LineEdit", "TextEdit", "PopupMenu", "TabBar"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_selected_color", type, Color.WHITE)
		result.set_color("font_disabled_color", type, Color("547684"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		result.set_stylebox(state, "OptionButton", result.get_stylebox(state, "Button"))
	for type in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type, DatapadTheme.box("071c29", "2b6477", 1, 12))
		result.set_stylebox("read_only", type, DatapadTheme.box("092532", "2b6477", 1, 12))
		var focus := DatapadTheme.box("071c29", "67dcea", 2, 12)
		focus.draw_center = false
		result.set_stylebox("focus", type, focus)
		result.set_color("caret_color", type, ACCENT)
		result.set_color("selection_color", type, Color("23574f"))
		result.set_color("font_placeholder_color", type, MUTED)
	result.set_stylebox("panel", "PopupMenu", DatapadTheme.frame(16))
	result.set_stylebox("hover", "PopupMenu", DatapadTheme.box("12394a", "67dcea", 1, 8))
	result.set_constant("v_separation", "PopupMenu", 16)
	result.set_stylebox("panel", "TabContainer", DatapadTheme.frame(20))
	for type in ["TabContainer", "TabBar"]:
		for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
			result.set_stylebox(state, type, DatapadTheme.button("pressed" if state=="tab_selected" else "hover" if state=="tab_hovered" else "disabled" if state=="tab_disabled" else "normal"))
		result.set_color("font_unselected_color", type, MUTED)
		result.set_color("font_selected_color", type, INK)
		result.set_font_size("font_size", type, 20)
	result.set_stylebox("slider", "HSlider", DatapadTheme.box("0a2939", "2b6477", 1, 4))
	result.set_stylebox("grabber_area", "HSlider", DatapadTheme.box("3ea8b9", "67dcea", 0, 4))
	result.set_stylebox("grabber_area_highlight", "HSlider", DatapadTheme.box("67dcea", "67dcea", 0, 4))
	for type in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", type, DatapadTheme.box("071c29", "163e37", 0, 7))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type, DatapadTheme.box("3ea8b9", "67dcea", 0, 7))
	result.set_stylebox("separator", "HSeparator", DatapadTheme.box("2b6477", "2b6477", 0, 1))
	return result
