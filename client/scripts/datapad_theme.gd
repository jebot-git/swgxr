extends RefCounted
## Empty CC0 Wenrexa frames only. Original SWG item models remain the UI imagery.
const INK := Color("c9fbff")
const MUTED := Color("91bdcc")
const ACCENT := Color("67dcea")
const SURFACE := Color("071c29")
const PANEL_SQUARE = preload("res://resources/ui/wenrexa_hologram/panel_square.png")
const PANEL_TALL = preload("res://resources/ui/wenrexa_hologram/panel_tall.png")
const PANEL_WIDE = preload("res://resources/ui/wenrexa_hologram/panel_wide.png")
const BUTTON_NORMAL = preload("res://resources/ui/wenrexa_hologram/button_normal.png")
const BUTTON_HOVER = preload("res://resources/ui/wenrexa_hologram/button_hover.png")
const BUTTON_PRESSED = preload("res://resources/ui/wenrexa_hologram/button_pressed.png")
const BUTTON_DISABLED = preload("res://resources/ui/wenrexa_hologram/button_disabled.png")

static func frame(margin:int=20,shape:String="square")->StyleBoxTexture:
	var style:=StyleBoxTexture.new()
	style.texture=PANEL_TALL if shape=="tall" else PANEL_WIDE if shape=="wide" else PANEL_SQUARE
	style.set_texture_margin_all(24)
	style.set_content_margin_all(margin)
	style.modulate_color=Color(.72,.78,1.12,1)
	return style

static func button(state:String="normal",margin:int=12)->StyleBoxTexture:
	var style:=StyleBoxTexture.new()
	style.texture=BUTTON_HOVER if state in ["hover","focus"] else BUTTON_PRESSED if state=="pressed" else BUTTON_DISABLED if state=="disabled" else BUTTON_NORMAL
	style.set_texture_margin_all(12)
	style.texture_margin_top=10;style.texture_margin_bottom=10
	style.set_content_margin_all(margin)
	style.modulate_color=Color(.72,.78,1.12,1)
	return style

static func cell(selected:bool=false,margin:int=8)->StyleBoxFlat:
	return box("12394a" if selected else "092532","67dcea" if selected else "2b6477",2 if selected else 1,margin)

static func slider_handle(highlight:bool=false,disabled:bool=false)->Texture2D:
	# A square-cornered extended grip, generated from primitives (no pack icons).
	var image:=Image.create_empty(28,44,false,Image.FORMAT_RGBA8)
	image.fill(Color("547684") if disabled else INK if highlight else ACCENT)
	image.fill_rect(Rect2i(2,2,24,40),Color("092532"))
	for y in [15,21,27]:image.fill_rect(Rect2i(8,y,12,2),MUTED if disabled else ACCENT)
	return ImageTexture.create_from_image(image)

static func build() -> Theme:
	var result := preload("res://resources/fonts/ui_theme.tres").duplicate() as Theme
	result.default_font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	result.default_font_size = 22
	for type in ["Label", "Button", "ItemList", "LineEdit"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_pressed_color", type, Color.WHITE)
	result.set_color("font_disabled_color","Button",Color("547684"))
	result.set_color("font_selected_color", "ItemList", INK)
	for type in ["PanelContainer","Panel"]:result.set_stylebox("panel",type,frame())
	result.set_stylebox("panel", "ItemList", frame(16,"tall"))
	result.set_stylebox("selected", "ItemList", cell(true))
	result.set_stylebox("selected_focus", "ItemList", cell(true))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		result.set_stylebox(state, "Button", button(state))
	result.set_icon("grabber","HSlider",slider_handle())
	result.set_icon("grabber_highlight","HSlider",slider_handle(true))
	result.set_icon("grabber_disabled","HSlider",slider_handle(false,true))
	result.set_stylebox("slider","HSlider",box("0a2939","2b6477",1,4))
	result.set_stylebox("grabber_area","HSlider",box("3ea8b9","67dcea",0,4))
	result.set_stylebox("grabber_area_highlight","HSlider",box("67dcea","67dcea",0,4))
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
