extends VBoxContainer
signal changed
const Foveation=preload("res://graphics/foveation.gd")
var preferences:RefCounted
var choice=preload("res://scripts/frontend_choice.gd").new()
var notice:=Label.new()
var fixed_row:=VBoxContainer.new()
var gaze_row:=VBoxContainer.new()
var fixed_choice:Control
var gaze_choice:Control
var mirror_choice:Control
var foveation_status:=Label.new()
var capability_key:=""
var poll:=0.0
func setup(value:RefCounted)->void:
	preferences=value
	var label:=Label.new();label.text="Multisample anti-aliasing (MSAA)";add_child(label)
	choice.name="MSAA";choice.custom_minimum_size.y=44
	for option:String in ["Off","2×","4×","8×"]:choice.add_item(option)
	choice.select(preferences.msaa);add_child(choice)
	choice.item_selected.connect(func(index:int):
		preferences.set_msaa(index)
		notice.text="Applied and saved." if preferences.save_preferences()==OK else "Applied for this session; could not save the preference."
		changed.emit())
	var help:=Label.new();help.text="Smooths object edges in headset and desktop views. Higher levels use more GPU power. Changes apply immediately.";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(help)
	add_child(fixed_row);add_child(gaze_row)
	fixed_choice=add_choice(fixed_row,"Fixed foveation","FoveationLevel",["Off","Low","Medium","High"],preferences.foveation_level,func(index:int):preferences.foveation_level=index;save())
	gaze_choice=add_choice(gaze_row,"Eye-tracked foveation · sharp region","FoveaSize",["Off","Small","Medium","Large"],preferences.fovea_size,func(index:int):preferences.fovea_size=index;save())
	foveation_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(foveation_status)
	mirror_choice=add_choice(self,"Desktop mirror (VR)","DesktopMirror",["Third-person","Standard OpenXR · left eye"],preferences.desktop_mirror,func(index:int):preferences.desktop_mirror=index;save())
	var mirror_help:=Label.new();mirror_help.text="OpenXR shows the headset's left-eye view and stops the extra third-person render. Desktop play is unchanged.";mirror_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(mirror_help)
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(notice)
	refresh_foveation(XRServer.find_interface("OpenXR"))

func add_choice(parent:Control,title:String,node_name:String,options:Array,selected:int,callback:Callable)->Control:
	var label:=Label.new();label.text=title;parent.add_child(label)
	var control=preload("res://scripts/frontend_choice.gd").new();control.name=node_name;control.custom_minimum_size.y=44
	for option:String in options:control.add_item(option)
	control.select(selected);parent.add_child(control);control.item_selected.connect(callback)
	return control

func save()->void:
	notice.text="Applied and saved." if preferences.save_preferences()==OK else "Applied for this session; could not save the preference."
	changed.emit();refresh_foveation(XRServer.find_interface("OpenXR"))

func refresh_foveation(xr)->void:
	capability_key=Foveation.mode(xr)+str(xr.is_foveation_supported() if xr!=null and xr.is_initialized() else false)
	var gaze:bool=Foveation.mode(xr)=="gaze"
	if fixed_row.visible==gaze:
		fixed_choice.close_popup();gaze_choice.close_popup()
	fixed_row.visible=not gaze;gaze_row.visible=gaze
	foveation_status.text=Foveation.description(xr,preferences.foveation_level,preferences.fovea_size)

func _process(delta:float)->void:
	if preferences==null:return
	poll+=delta
	if poll<0.5:return
	poll=0.0
	var xr=XRServer.find_interface("OpenXR")
	var key:=Foveation.mode(xr)+str(xr.is_foveation_supported() if xr!=null and xr.is_initialized() else false)
	if key!=capability_key:refresh_foveation(xr)
