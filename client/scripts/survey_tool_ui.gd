extends Control
## Source map + authoritative Core3 resource catalog/grid. No local densities.
signal resource_selected(id: String)
signal resource_details_changed(resource: Dictionary)
signal tool_slot_requested
const MapControl = preload("res://scripts/datapad_map.gd")
const ThemeSource = preload("res://scripts/datapad_theme.gd")
const PIXELS := Vector2i(1050,680)
const MAX_SPOTS := 256
class SurveyMap extends MapControl:
	var spots: Array=[]
	var highest: Dictionary={}
	func load_service_references(_path: String = "") -> void:
		# A survey is a resource-density view, never a city/service map.
		source_services=[];native_services=[];service_points=[];landmarks=[];waypoints=[]
	func _gui_input(_event: InputEvent) -> void: pass # Range is server/tool/skill controlled.
	func _draw() -> void:
		super()
		var font:=get_theme_default_font()
		for sample: Dictionary in spots:
			var p:=world_to_screen(position_of(sample.get("position",{})))
			if not Rect2(Vector2.ZERO,size).has_point(p): continue
			var density:=clampf(float(sample.get("density",0)),0,1)
			draw_circle(p,4,Color(1-density,0.5+density*0.5,0.3,0.95))
			draw_string(font,p+Vector2(6,-5),"%d%%"%int(round(density*100)),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ddfbff"))
		if not highest.is_empty():
			var p:=world_to_screen(position_of(highest.get("position",{})))
			draw_arc(p,11,0,TAU,24,Color("ffed72"),2,true)
var map: SurveyMap
var resources: ItemList
var title: Label
var status: Label
var info: Label
var context: Dictionary={}
var result: Dictionary={}
var selected_resource_id := ""
var pending := false
var navigation_delay:=0.0
var catalog: Dictionary={}
var selected_ids: Array[String]=[]
var source_center:=Vector3.ZERO
var active := false
var configured_planet := ""

func configure() -> void:
	theme=ThemeSource.build(); size=Vector2(PIXELS); custom_minimum_size=size
	var panel:=Panel.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(panel)
	panel.add_theme_stylebox_override("panel",ThemeSource.frame(14,"wide"))
	title=Label.new(); add_child(title); title.position=Vector2(18,12); title.size=Vector2(780,40); title.text="RESOURCE SURVEY"
	var holster:=Button.new(); add_child(holster); holster.position=Vector2(865,10); holster.size=Vector2(165,42); holster.text="Tool slot"; holster.pressed.connect(func(): tool_slot_requested.emit())
	resources=ItemList.new(); add_child(resources); resources.position=Vector2(18,65); resources.size=Vector2(330,515); resources.item_selected.connect(select_index)
	map=SurveyMap.new(); add_child(map); map.position=Vector2(365,65); map.size=Vector2(665,515); map.mouse_filter=Control.MOUSE_FILTER_IGNORE; map.clip_contents=true
	info=Label.new(); add_child(info); info.position=Vector2(18,590); info.size=Vector2(1000,30); info.add_theme_font_size_override("font_size",18)
	status=Label.new(); add_child(status); status.position=Vector2(18,624); status.size=Vector2(1000,45); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.add_theme_font_size_override("font_size",17); status.text="Reading current planet resources…"
	var path:=ProjectSettings.globalize_path("res://../runtime/assets/datapad/catalog.json")
	if FileAccess.file_exists(path):
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary: catalog=value
	set_context({})

func set_context(value: Dictionary) -> void:
	var changed_tool:=str(context.get("tool_id",""))!=str(value.get("tool_id",""))
	context=value.duplicate(true); pending=false; selected_ids.clear(); resources.clear()
	if changed_tool: selected_resource_id="";result={};map.spots=[];map.highest={}
	for resource: Dictionary in context.get("resources",[]):
		selected_ids.append(str(resource.get("id","")))
		resources.add_item(str(resource.get("name","Resource"))+" · "+str(resource.get("type","")))
	var planet:=str(context.get("planet","tatooine"))
	title.text="RESOURCE SURVEY · "+planet.to_upper()
	var data: Dictionary=catalog.get("maps",{}).get(planet,{}).duplicate(true)
	data["landmarks"]=[]; data["icons"]={}
	if planet!=configured_planet:
		map.configure(data,ProjectSettings.globalize_path("res://../runtime/assets/datapad")); configured_planet=planet
	var range_m:=maxf(1,float(context.get("max_range_m",context.get("range_m",1))))
	map.zoom=minf(map.world_bounds.size.x,map.world_bounds.size.y)/range_m
	info.text=("Survey span %dm · skill %d · holding trigger surveys · point + stick selects"%[int(range_m),int(context.get("surveying_skill",0))]) if context.has("max_range_m") else "Waiting for authoritative tool and skill range…"
	if selected_resource_id in selected_ids:
		resources.select(selected_ids.find(selected_resource_id));resource_details_changed.emit(selected_resource())
	else:
		selected_resource_id=""
		if not selected_ids.is_empty(): select_index(0); resources.select(0)
		else: resource_details_changed.emit({})
	set_center(MapControl.position_of(context.get("center",source_center)))
	set_pending(false,"Select a resource with the other hand, then squeeze the holding trigger." if not selected_ids.is_empty() else "No server resources available for this tool and planet.")

func select_index(index: int) -> void:
	if pending or index<0 or index>=selected_ids.size(): return
	selected_resource_id=selected_ids[index]; resource_selected.emit(selected_resource_id);resource_details_changed.emit(selected_resource())
	map.spots=[]; map.highest={}; result={}; map.queue_redraw()

func selected_resource() -> Dictionary:
	for resource: Dictionary in context.get("resources",[]):
		if str(resource.get("id",""))==selected_resource_id: return resource.duplicate(true)
	return {}

func set_center(position: Vector3) -> void:
	source_center=position; map.set_player_position(position); map.center=Vector2(position.x,position.z); map.queue_redraw()

func set_result(value: Dictionary) -> void:
	result=value.duplicate(true)
	map.spots=result.get("spots",[]).slice(0,MAX_SPOTS)
	map.highest=result.get("highest",{}) if result.get("highest") is Dictionary else {}
	if result.has("center"): set_center(MapControl.position_of(result.center))
	var waypoint: Variant=result.get("waypoint")
	var message: String="%d authoritative survey samples"%map.spots.size()
	if not map.highest.is_empty(): message+=" · highest %d%%"%int(round(float(map.highest.get("density",0))*100))
	if waypoint is Dictionary and not waypoint.is_empty(): message+=" · waypoint created"
	set_pending(false,message); map.queue_redraw()

func set_pending(value: bool, message := "") -> void:
	pending=value; resources.mouse_filter=Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	if not message.is_empty(): status.text=message

func scroll(stick: Vector2, delta: float) -> void:
	if pending or absf(stick.y)<.25:navigation_delay=0;return
	navigation_delay-=delta
	if navigation_delay>0 or resources.item_count==0:return
	navigation_delay=.18
	var selected:=resources.get_selected_items()
	var index:=clampi(0 if selected.is_empty() else selected[0]+(-1 if stick.y>0 else 1),0,resources.item_count-1)
	resources.select(index);resources.ensure_current_is_visible();select_index(index)

func set_active(value: bool) -> void:
	if active==value: return
	active=value; visible=value
