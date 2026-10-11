extends PanelContainer
## Tenkeyless layout using the same holographic controls as the datapad.
## Layout reference: LushkinR, https://opengameart.org/content/keyboard (CC0).
signal dismissed
const Holo=preload("res://scripts/datapad_theme.gd")
var target_viewport:Viewport
var shifted:=false
var caps:=false
var control:=false
var alt:=false
var keys:Array[Dictionary]=[]
var last_target:Control
const UNIT:=58.0
const ROW:=56.0

func _ready()->void:
	theme=Holo.build();add_theme_stylebox_override("panel",Holo.frame(10,"wide"))
	custom_minimum_size=Vector2(1200,400)
	var layout:=Control.new();add_child(layout)
	var function_row:Array=[["Esc",KEY_ESCAPE,1]]
	for i in range(12):function_row.append(["F%d"%(i+1),KEY_F1+i,1])
	function_row.append(["Done",0,2])
	row(layout,function_row,0)
	row(layout,[["`","~",1],["1","!",1],["2","@",1],["3","#",1],["4","$",1],["5","%",1],["6","^",1],["7","&",1],["8","*",1],["9","(",1],["0",")",1],["-","_",1],["=","+",1],["Backspace",KEY_BACKSPACE,2]],1)
	row(layout,[["Tab",KEY_TAB,1.5],["q","Q",1],["w","W",1],["e","E",1],["r","R",1],["t","T",1],["y","Y",1],["u","U",1],["i","I",1],["o","O",1],["p","P",1],["[","{",1],["]","}",1],["\\","|",1.5]],2)
	row(layout,[["Caps",KEY_CAPSLOCK,1.75],["a","A",1],["s","S",1],["d","D",1],["f","F",1],["g","G",1],["h","H",1],["j","J",1],["k","K",1],["l","L",1],[";",":",1],["'","\"",1],["Enter",KEY_ENTER,2.25]],3)
	row(layout,[["Shift",KEY_SHIFT,2.25],["z","Z",1],["x","X",1],["c","C",1],["v","V",1],["b","B",1],["n","N",1],["m","M",1],[",","<",1],[".",">",1],["/","?",1],["Shift",KEY_SHIFT,2.75]],4)
	row(layout,[["Ctrl",KEY_CTRL,1.5],["Alt",KEY_ALT,1.5],["Space",KEY_SPACE,9],["Alt",KEY_ALT,1.5],["Ctrl",KEY_CTRL,1.5]],5)
	row(layout,[["Insert",KEY_INSERT,1],["Home",KEY_HOME,1],["PgUp",KEY_PAGEUP,1]],1,16)
	row(layout,[["Delete",KEY_DELETE,1],["End",KEY_END,1],["PgDn",KEY_PAGEDOWN,1]],2,16)
	row(layout,[["↑",KEY_UP,1]],4,17)
	row(layout,[["←",KEY_LEFT,1],["↓",KEY_DOWN,1],["→",KEY_RIGHT,1]],5,16)

func row(layout:Control,descriptors:Array,y:int,start:float=0)->void:
	var x:=start
	for descriptor in descriptors:
		var button:=Button.new();layout.add_child(button);button.focus_mode=Control.FOCUS_NONE
		button.position=Vector2(14+x*UNIT,12+y*ROW);button.size=Vector2(float(descriptor[2])*UNIT-5,ROW-5)
		for state in ["normal","hover","pressed","disabled","focus"]:
			var style:=button.get_theme_stylebox(state).duplicate() as StyleBox
			style.content_margin_left=4;style.content_margin_right=4;style.content_margin_top=4;style.content_margin_bottom=4
			button.add_theme_stylebox_override(state,style)
		button.add_theme_font_size_override("font_size",14 if str(descriptor[0]).length()>4 and float(descriptor[2])==1 else 18);button.text=str(descriptor[0])
		keys.append({"button":button,"plain":descriptor[0],"value":descriptor[1]})
		button.pressed.connect(func():press_key(descriptor[0],descriptor[1]))
		x+=float(descriptor[2])

func refresh_keys()->void:
	for key in keys:
		var label:=str(key.plain)
		if key.value is String:
			var capital:=shifted != caps if label.to_lower()!=label.to_upper() else shifted
			label=str(key.value) if capital else label
		key.button.text=label
		key.button.modulate=Holo.ACCENT if (key.plain=="Shift" and shifted) or (key.plain=="Caps" and caps) or (key.plain=="Ctrl" and control) or (key.plain=="Alt" and alt) else Color.WHITE

func press_key(label:String,value:Variant)->void:
	if label=="Done":dismissed.emit();return
	if value is int:
		match int(value):
			KEY_SHIFT:shifted=not shifted;refresh_keys();return
			KEY_CAPSLOCK:caps=not caps;refresh_keys();return
			KEY_CTRL:control=not control;refresh_keys();return
			KEY_ALT:alt=not alt;refresh_keys();return
	if not is_instance_valid(target_viewport):return
	var target:=target_viewport.gui_get_focus_owner()
	if not target is LineEdit and not target is TextEdit:return
	var event:=InputEventKey.new();event.pressed=true;event.shift_pressed=shifted;event.ctrl_pressed=control;event.alt_pressed=alt
	if value is String:
		var capital:=shifted != caps if label.to_lower()!=label.to_upper() else shifted
		var character:String=value if capital else label
		event.unicode=character.unicode_at(0);event.keycode=label.to_upper().unicode_at(0)
	else:
		event.keycode=int(value)
		if value==KEY_SPACE:event.unicode=32
	target_viewport.push_input(event,true)
	var release:=event.duplicate() as InputEventKey;release.pressed=false;target_viewport.push_input(release,true)
	shifted=false;control=false;alt=false;refresh_keys()

func reset_modifiers()->void:
	shifted=false;caps=false;control=false;alt=false;refresh_keys()
