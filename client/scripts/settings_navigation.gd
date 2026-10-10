extends VBoxContainer
## Settings pages share the established canvas dropdown and controller scrolling.
var pages:Dictionary={}
var buttons:Dictionary={}
var home:=VBoxContainer.new()
var heading:=Label.new()
var back:=Button.new()
var current:=""
func _ready()->void:
	name="SettingsNavigation";add_theme_constant_override("separation",14)
	var header:=HBoxContainer.new();add_child(header)
	back.text="‹ Settings";back.custom_minimum_size.y=44;header.add_child(back);back.pressed.connect(show_page.bind(""))
	heading.text="SETTINGS";heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
	home.size_flags_vertical=Control.SIZE_EXPAND_FILL;home.add_theme_constant_override("separation",14);add_child(home)
	show_page("")
func add_page(title:String)->VBoxContainer:
	var button:=Button.new();button.name=title+"Settings";button.text=title;button.custom_minimum_size.y=52;home.add_child(button);buttons[title]=button
	button.pressed.connect(show_page.bind(title))
	var scroll:=preload("res://scripts/frontend_scroll.gd").new();scroll.name=title+"Page";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;add_child(scroll)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",14);scroll.add_child(content)
	pages[title]=scroll;scroll.hide();return content
func show_page(title:String)->void:
	if not title.is_empty() and not pages.has(title):return
	preload("res://scripts/frontend_choice.gd").close_all(get_viewport())
	var previous:=current;current=title;home.visible=title.is_empty();back.visible=not title.is_empty();heading.text="SETTINGS" if title.is_empty() else title.to_upper()
	for key:String in pages:pages[key].visible=key==title
	if not title.is_empty():back.grab_focus()
	elif buttons.has(previous):buttons[previous].grab_focus()
