extends RefCounted

static func build() -> Theme:
	var result := preload("res://resources/fonts/ui_theme.tres").duplicate() as Theme
	result.default_font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	result.default_font_size = 22
	for type in ["Label", "Button", "ItemList", "LineEdit"]:
		result.set_color("font_color", type, Color("c9fbff"))
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_pressed_color", type, Color.WHITE)
	result.set_color("font_selected_color", "ItemList", Color.WHITE)
	result.set_stylebox("panel", "PanelContainer", box("071c29", "3ea8b9", 2, 18))
	result.set_stylebox("panel", "ItemList", box("06131e", "245363", 1, 8))
	result.set_stylebox("selected", "ItemList", box("164c60", "65deee", 2, 8))
	result.set_stylebox("selected_focus", "ItemList", box("164c60", "a4f4ff", 2, 8))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fill := "12394a" if state in ["hover", "pressed"] else "0a2636"
		result.set_stylebox(state, "Button", box(fill, "67dcea" if state in ["hover", "focus", "pressed"] else "2b6477", 2, 12))
	result.set_constant("v_separation", "ItemList", 16)
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 10)
	return result

static func box(fill: String, border: String, width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(width)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(margin)
	return style
