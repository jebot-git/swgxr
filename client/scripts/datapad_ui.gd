extends PanelContainer

signal ship_action_requested(entry: Dictionary)
signal hyperspace_requested(destination: String)
signal hyperspace_abort_requested
var navigation_controls: VBoxContainer
var projection_button: Button
signal forget_skill_requested(skill_id: String)
signal call_vehicle_requested(entry: Dictionary)
signal recall_vehicle_requested(entry: Dictionary)
signal droid_action_requested(entry: Dictionary)
signal entry_selected(entry: Dictionary)
signal new_waypoint_requested(position: Vector3, label: String)
signal delete_entry_requested(entry: Dictionary)
signal cancel_mission_requested(entry: Dictionary)
signal map_expansion_requested(expanded: bool)
signal close_requested
const MapControl = preload("res://space/sector_map.gd")
const DatapadTheme = preload("res://scripts/datapad_theme.gd")
var planet:="tatooine"
var manifest: Dictionary = {}
var catalog_directory := ""
var entries: Array = []
var filtered_entries: Array = []
var mission_parcels: Array = []
var bounty_missions:Array=[]
var space_missions:Array=[]
var harvesting_deeds:Array=[]
var factory_blueprints:Array=[]
var vendors: Array = []
var owned_missions: Dictionary = {}
var parcel_assets=preload("res://scripts/inventory_assets.gd").new()
var parcel_previews:Dictionary={}
var category := "waypoints"
var expanded := false
var player_position := Vector3.ZERO
var detail_panel: PanelContainer
var detail_title: Label
var detail_type: Label
var detail_description: RichTextLabel
var detail_preview: TextureRect
var detail_attributes: Label
var list: ItemList
var map: Control
var content: VBoxContainer
var list_status: Label
var connection_status: Label
var close_button: Button
var coordinates: Label
var waypoint_button: Button
var map_toggle: Button
var expand_button: Button
var category_buttons: Dictionary = {}
var map_filters: HFlowContainer
var filter_buttons: Dictionary={}
var map_tools: HBoxContainer
var map_visible := false
var ready_built := false
var selected_entry: Dictionary = {}
var navigation_anchor:=Vector2.INF
var cancel_mission_button: Button
var delete_button: Button
var vehicle_button: Button
var busy := false
var ships: Array = []
var professions: Control
var forget_button: Button
var selected_skill_detail: Dictionary = {}

var vehicle_assets=preload("res://scripts/inventory_assets.gd").new()
var vehicle_previews: Dictionary={}
var vehicle_details: Dictionary={}
func vehicle_icon(entry: Dictionary) -> Texture2D:
	var template:=str(entry.get("template",""))
	if not template.begins_with("object/mobile/vehicle/"): return null
	if vehicle_previews.has(template):return vehicle_previews[template].get_texture()
	if vehicle_previews.size()>=16:return null
	if vehicle_assets.directory.is_empty():vehicle_assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/vehicles/catalog.json"))
	var model: MeshInstance3D=vehicle_assets.instance(template,1.5)
	if model==null:return null
	var viewport:=SubViewport.new();viewport.size=Vector2i(256,192);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.gui_disable_input=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;add_child(viewport)
	var pivot:=Node3D.new();viewport.add_child(pivot);pivot.rotation=Vector3(.25,.65,0);pivot.add_child(model)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.55;camera.position.z=3;camera.current=true
	vehicle_previews[template]=viewport
	return viewport.get_texture()

func parcel_icon(entry:Dictionary)->Texture2D:
	var template:=str(entry.get("template",""))
	if template.is_empty():return null
	if parcel_previews.has(template):return parcel_previews[template].get_texture()
	if parcel_previews.size()>=8:return null
	if parcel_assets.directory.is_empty():parcel_assets.configure()
	var model:MeshInstance3D=parcel_assets.instance(template,1.2)
	if model==null:return null
	var viewport:=SubViewport.new();viewport.size=Vector2i(256,192);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.gui_disable_input=true;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;add_child(viewport)
	var pivot:=Node3D.new();viewport.add_child(pivot);pivot.rotation=Vector3(.7,.35,0);pivot.add_child(model)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.4;camera.position.z=3;camera.current=true
	parcel_previews[template]=viewport
	return viewport.get_texture()

func set_mission_parcels(values:Array)->void:
	if values==mission_parcels:return
	mission_parcels=values.duplicate(true)
	set_entries(entries.filter(func(entry):return not entry.get("reference_only",false) and entry.get("type","")!="mission_parcel"))

func set_space_missions(values:Array)->void:
	if values==space_missions:return
	space_missions=values.duplicate(true);set_entries(entries)

func set_bounty_missions(values:Array)->void:
	if values==bounty_missions:return
	bounty_missions=values.duplicate(true)
	set_entries(entries)

func set_harvesting_deeds(values:Array)->void:
	if values==harvesting_deeds:return
	harvesting_deeds=values.duplicate(true)
	set_entries(entries)

func set_ships(values:Array)->void:
	if values == ships: return
	ships = values.duplicate(true)
	set_entries(entries)

func set_vendors(values:Array)->void:
	if values==vendors:return
	vendors=values.duplicate(true)
	set_entries(entries.filter(func(entry):return not entry.get("reference_only",false)))

func draggable_entry_at(pixel:Vector2)->Dictionary:
	if busy or not list.visible or not list.get_global_rect().has_point(pixel):return {}
	var index:=list.get_item_at_position(pixel-list.global_position,true)
	if index<0 or index>=filtered_entries.size():return {}
	var entry:Dictionary=filtered_entries[index]
	return entry.duplicate(true) if entry.get("type","") in ["mission_parcel","vendor","harvesting_deed","factory_deed","manufacturing_blueprint"] else {}

func _ready() -> void:
	build_ui()

func build_ui() -> void:
	if ready_built: return
	ready_built = true
	theme = DatapadTheme.build()
	add_theme_stylebox_override("panel",DatapadTheme.frame(28,"wide"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := make_label("DATAPAD",28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	connection_status = make_label("Awaiting character data",16)
	connection_status.modulate = Color("91bdcc")
	connection_status.clip_text = true
	connection_status.custom_minimum_size.x = 240
	header.add_child(connection_status)
	close_button=make_button("Close")
	close_button.pressed.connect(func():close_requested.emit())
	header.add_child(close_button)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for descriptor in [["waypoints","Waypoints"],["data","Data"],["vehicles","Vehicles"],["ships","Ships"],["pets","Pets"],["vendors","Vendors"],["poi","POI"],["schematics","Schematics"],["skills","Skills"]]:
		var button := make_button(descriptor[1])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",18)
		var id: String = descriptor[0]
		button.pressed.connect(func(): select_category(id))
		tabs.add_child(button)
		category_buttons[id] = button
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	list_status = make_label("No waypoints",20)
	content.add_child(list_status)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 170
	list.item_selected.connect(select_entry)
	content.add_child(list)
	professions = preload("res://scripts/profession_trees.gd").new()
	professions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	professions.visible = false
	professions.skill_selected.connect(show_skill_detail)
	content.add_child(professions)
	map = MapControl.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.visible = false
	map.cursor_selected.connect(func(_position: Vector3): update_coordinates())
	content.add_child(map)
	map.custom_minimum_size.y=224 # Frame, filters and action rows must fit the 625 px wrist viewport.
	map_filters=HFlowContainer.new();map_filters.visible=false;content.add_child(map_filters)
	for descriptor in [["city","Cities"],["poi","POI"],["bazaar","Bazaar"],["mission","Missions"],["bank","Bank"],["crafting","Crafting"],["travel","Travel"],["trainer","Trainers"]]:
		var button:=make_button(descriptor[1]);button.toggle_mode=true;button.button_pressed=true
		button.add_theme_font_size_override("font_size",16);button.custom_minimum_size.y=32
		button.toggled.connect(func(enabled):map.set_filter(str(descriptor[0]),enabled))
		filter_buttons[str(descriptor[0])]=button;map_filters.add_child(button)
	map_tools = HBoxContainer.new()
	map_tools.visible = false
	content.add_child(map_tools)
	for descriptor in [["−",0.8],["+",1.25]]:
		var button := make_button(descriptor[0])
		var factor: float = descriptor[1]
		button.pressed.connect(func(): map.change_zoom(factor,map.size*0.5))
		map_tools.add_child(button)
	var center_button := make_button("Locate me")
	center_button.pressed.connect(func(): map.center_on_player())
	map_tools.add_child(center_button)
	var clear_button := make_button("Use my position")
	clear_button.pressed.connect(func():
		map.has_cursor = false
		map.queue_redraw()
		update_coordinates())
	map_tools.add_child(clear_button)
	expand_button = make_button("Expand map")
	expand_button.pressed.connect(func():
		expanded = not expanded
		expand_button.text = "Compact map" if expanded else "Expand map"
		map_expansion_requested.emit(expanded))
	map_tools.add_child(expand_button)
	projection_button=make_button("View: X/Z")
	projection_button.pressed.connect(func():map.cycle_projection();projection_button.text="View: "+["X/Z","X/Y","Z/Y"][map.projection])
	projection_button.hide();map_tools.add_child(projection_button)
	navigation_controls=preload("res://space/navigation_controls.gd").new();content.add_child(navigation_controls);navigation_controls.hide()
	navigation_controls.jump_requested.connect(func(destination:String):hyperspace_requested.emit(destination))
	navigation_controls.abort_requested.connect(func():hyperspace_abort_requested.emit())
	coordinates = make_label("",16)
	coordinates.modulate = Color("91bdcc")
	column.add_child(coordinates)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	map_toggle = make_button("Planet map")
	map_toggle.pressed.connect(func(): show_map(not map_visible))
	actions.add_child(map_toggle)
	waypoint_button = make_button("New waypoint · my position")
	waypoint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	waypoint_button.pressed.connect(func():
		if busy: return
		var point: Vector3 = map.cursor if map.has_cursor else player_position
		new_waypoint_requested.emit(point,"Map waypoint" if map.has_cursor else "My location"))
	actions.add_child(waypoint_button)
	build_detail()
	select_category(category)
	update_coordinates()

func build_detail() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel",DatapadTheme.frame(28,"tall"))
	detail_panel.name = "DatapadDetails"
	detail_panel.theme = theme
	detail_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	detail_panel.add_child(box)
	box.add_child(make_label("INFORMATION",18))
	detail_title = make_label("Select an entry",28)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_title)
	detail_type = make_label("",16)
	detail_type.modulate = Color("91bdcc")
	box.add_child(detail_type)
	detail_preview = TextureRect.new()
	detail_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_preview.custom_minimum_size.y = 160
	detail_preview.visible = false
	box.add_child(detail_preview)
	detail_description = RichTextLabel.new()
	detail_description.text = "Your saved waypoints and character data appear here."
	detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_description.fit_content = false
	box.add_child(detail_description)
	detail_attributes = make_label("",18)
	detail_attributes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_attributes)
	delete_button = make_button("Delete entry")
	delete_button.disabled = true
	if is_instance_valid(cancel_mission_button):cancel_mission_button.visible=false
	delete_button.pressed.connect(func():
		if not busy and can_delete(selected_entry): delete_entry_requested.emit(selected_entry.duplicate(true)))
	box.add_child(delete_button)
	forget_button = make_button("Forget skill")
	forget_button.hide()
	forget_button.pressed.connect(func():
		if not busy and professions.forget_status(str(selected_skill_detail.get("skill_id", ""))).get("eligible", false):
			forget_skill_requested.emit(str(selected_skill_detail.skill_id)))
	box.add_child(forget_button)
	cancel_mission_button=make_button("Cancel mission")
	cancel_mission_button.visible=false
	cancel_mission_button.tooltip_text="Abandon this mission and remove its associated mission items and investigation."
	cancel_mission_button.pressed.connect(func():
		if not busy and not cancellable_mission_id(selected_entry).is_empty():cancel_mission_requested.emit(selected_entry.duplicate(true)))
	box.add_child(cancel_mission_button)
	vehicle_button=make_button("Call vehicle")
	vehicle_button.visible=false
	vehicle_button.pressed.connect(func():
		if busy:return
		if selected_entry.get("category","")=="ships":ship_action_requested.emit(selected_entry.duplicate(true))
		elif selected_entry.get("category","")=="pets":droid_action_requested.emit(selected_entry.duplicate(true))
		elif selected_entry.get("category","")=="vehicles":
			if selected_entry.get("spawned",false):recall_vehicle_requested.emit(selected_entry.duplicate(true))
			else:call_vehicle_requested.emit(selected_entry.duplicate(true)))
	box.add_child(vehicle_button)

func set_owned_missions(values:Array)->void:
	var next:Dictionary={}
	for mission in values:
		if mission is Dictionary and str(mission.get("id","")).is_valid_int():next[str(mission.id)]=true
	for parcel in mission_parcels:next[str(parcel.get("mission_id",""))]=true
	owned_missions=next
	if is_instance_valid(cancel_mission_button):
		cancel_mission_button.visible=not cancellable_mission_id(selected_entry).is_empty()
		cancel_mission_button.disabled=busy
		delete_button.visible=not cancel_mission_button.visible
func cancellable_mission_id(entry:Dictionary)->String:
	if entry.get("reference_only",false) or entry.get("static",false):return ""
	var id:=str(entry.get("mission_id",entry.get("id","")))
	return id if id.is_valid_int() and owned_missions.has(id) else ""

static func can_delete(entry: Dictionary) -> bool:
	return entry.get("deletable",false) and not entry.get("reference_only",false) and not entry.get("static",false) and not entry.get("server_driven",false) and str(entry.get("source","")) in ["core3_player_waypoint_list","core3_datapad_container"]

func take_detail_panel() -> Control:
	build_ui()
	return detail_panel

func configure(data: Dictionary, directory := "") -> void:
	build_ui()
	manifest = data
	catalog_directory = directory
	var map_descriptor: Dictionary = data.get("maps",{}).get(planet,{}).duplicate(true)
	map_descriptor["icons"] = data.get("icons",{})
	var planet_descriptor:Dictionary=preload("res://scripts/planet_catalog.gd").new().descriptor(planet)
	map_descriptor["service_directory"]=str(planet_descriptor.get("services","res://../runtime/assets/services/catalog.json")).get_base_dir()
	map.configure(map_descriptor,directory)
	var ui: Dictionary = data.get("ui",{})
	for descriptor in ui.get("categories",[]):
		if descriptor is Dictionary and category_buttons.has(str(descriptor.get("id",""))):
			category_buttons[str(descriptor.id)].text = str(descriptor.get("label",category_buttons[str(descriptor.id)].text))

func set_planet(value:String)->void:
	build_ui()
	if value==planet:return
	planet=value
	map.source_services=[];map.native_services=[];map.service_points=[];map.registered_locations=[];map.has_cursor=false;map.zoom=1.0
	if not manifest.is_empty():configure(manifest,catalog_directory)
	set_entries(entries.filter(func(entry):return not entry.get("reference_only",false)))

func set_entries(values: Array) -> void:
	build_ui()
	entries = values.filter(func(entry):return entry.get("type","") not in ["ship","space_mission","mission_parcel","bounty_mission","vendor","harvesting_deed","factory_deed","manufacturing_blueprint"] and not entry.get("reference_only",false)).duplicate(true)
	entries.append_array(ships.duplicate(true))
	entries.append_array(space_missions.duplicate(true))
	# PLAY baselines identify the control device; vehicle snapshots identify its
	# actual mobile. Retain that authoritative association across waypoint and
	# datapad refreshes, without guessing a hull from the device filename.
	var retained:Dictionary={}
	for entry:Dictionary in entries:
		if entry.get("category","")!="vehicles":continue
		var id:=str(entry.get("id",""))
		if str(entry.get("template","")).begins_with("object/mobile/vehicle/"):
			vehicle_details[id]=entry.duplicate(true)
		elif vehicle_details.has(id):
			entry.merge(vehicle_details[id],true)
		if vehicle_details.has(id):retained[id]=vehicle_details[id]
	vehicle_details=retained
	entries.append_array(mission_parcels.duplicate(true))
	entries.append_array(bounty_missions.duplicate(true))
	entries.append_array(vendors.duplicate(true))
	entries.append_array(harvesting_deeds.duplicate(true))
	entries.append_array(factory_blueprints.duplicate(true))
	# Shared original client POIs are reference information, not granted objects.
	for source in manifest.get("points_of_interest",[]):
		if str(source.get("planet", "")).to_lower() != planet: continue
		var reference: Dictionary = source.duplicate(true)
		reference["id"] = "reference:" + str(source.get("id",source.get("name","")))
		reference["category"] = "poi"
		reference["reference_only"] = true
		reference["attributes"] = {"Source":"Original client points of interest", "Datapad space":"None"}
		entries.append(reference)
	connection_status.text = "Character datapad"
	map.waypoints = entries.filter(func(entry): return str(entry.get("category","")) == "waypoints" and str(entry.get("planet",planet)).to_lower() == planet)
	map.queue_redraw()
	select_category(category)

func set_skills(values: Array, complete := true) -> void:
	build_ui()
	professions.set_learned(values, complete)

func set_experience(values: Dictionary, complete := true) -> void:
	build_ui()
	professions.set_experience(values, complete)

func set_skill_forgetting_available(value:bool,reason:String="")->void:
	build_ui();professions.set_forgetting_available(value,reason)

func set_forget_skills(values: Array, points: int = -1) -> void:
	build_ui()
	professions.set_forget_skills(values, points)

func show_skill_detail(detail: Dictionary) -> void:
	if not is_instance_valid(detail_title) or category != "skills": return
	selected_entry = {}
	selected_skill_detail = detail.duplicate(true)
	vehicle_button.visible=false
	delete_button.visible = false
	delete_button.disabled = true
	forget_button.visible = detail.get("state", "") == "Learned"
	var forget: Dictionary = detail.get("forget", {})
	forget_button.disabled = busy or not forget.get("eligible", false)
	forget_button.text = "Forget · regain %d skill points" % int(forget.get("refunded_points", 0))
	forget_button.tooltip_text = str(forget.get("reason", ""))
	if is_instance_valid(cancel_mission_button):cancel_mission_button.visible=false
	detail_title.text = str(detail.name)
	detail_type.text = str(detail.state)
	detail_description.text = str(detail.description)
	detail_attributes.text = ("%d skill points available. " % int(detail.skill_points) if int(detail.get("skill_points", -1)) >= 0 else "") + (str(forget.get("reason", "")) + "\nForgetting refunds skill points; spent XP and credits are not refunded." if forget_button.visible else "Training is available from profession trainers.")
	detail_preview.visible = false

func set_status(text: String) -> void:
	build_ui()
	connection_status.text = text
	connection_status.tooltip_text = text

func set_busy(value: bool, status := "") -> void:
	build_ui()
	busy = value
	if is_instance_valid(forget_button):forget_button.disabled = value or not professions.forget_status(str(selected_skill_detail.get("skill_id", ""))).get("eligible", false)
	waypoint_button.disabled = value
	delete_button.disabled = value or not can_delete(selected_entry)
	cancel_mission_button.disabled=value or cancellable_mission_id(selected_entry).is_empty()
	if not status.is_empty(): set_status(status)

func set_player_position(value: Vector3) -> void:
	build_ui()
	player_position = value
	map.set_player_position(value)
	update_coordinates()

func select_category(id: String) -> void:
	selected_entry = {}
	selected_skill_detail = {}
	forget_button.visible = false
	delete_button.visible = true
	vehicle_button.visible=false
	delete_button.disabled = true
	if is_instance_valid(cancel_mission_button):cancel_mission_button.visible=false
	category = id
	for key in category_buttons: category_buttons[key].button_pressed = key == id
	professions.visible = id == "skills"
	if id == "skills":
		show_map(false)
		list.visible = false
		list_status.visible = false
		professions.show_profession(professions.profession_index)
		return
	list.visible = not map_visible
	list_status.visible = not map_visible
	filtered_entries = entries.filter(func(entry): return str(entry.get("category","data")) == id)
	list.clear()
	list.fixed_icon_size=Vector2i(64,48) if id in ["vehicles","data"] else Vector2i.ZERO
	for entry in filtered_entries: list.add_item(str(entry.get("name","Unnamed entry")),vehicle_icon(entry) if id=="vehicles" else parcel_icon(entry) if entry.get("type","")=="mission_parcel" else null)
	list_status.text = "%s · %d" % [str(category_buttons[id].text),filtered_entries.size()]
	if filtered_entries.is_empty(): list_status.text = "No saved " + str(category_buttons[id].text).to_lower()
	if not filtered_entries.is_empty():
		list.select(0)
		select_entry(0)
	else:
		detail_title.text = "No entries"
		detail_type.text = str(category_buttons[id].text)
		var help_key: String = {"waypoints":"help_wps_icons", "data":"help_data_icon", "pets":"help_data_icon", "vehicles":"help_data_icon", "schematics":"help_draft_icon", "poi":"help_poi_icon"}.get(id,"")
		var original_help := str(manifest.get("ui",{}).get("help",{}).get(help_key,""))
		detail_description.text = "This character has no entries in this category." + ("\n\n" + original_help if not original_help.is_empty() else "")
		detail_attributes.text = ""
		detail_preview.visible = false

func select_entry(index: int) -> void:
	if index < 0 or index >= filtered_entries.size(): return
	var entry: Dictionary = filtered_entries[index]
	selected_entry = entry
	vehicle_button.visible=entry.get("category","") in ["vehicles","ships"] or (entry.get("category","")=="pets" and (entry.get("native_droid",false) or entry.get("native_pet",false)))
	vehicle_button.text=("Recall " if entry.get("spawned",false) else "Call ")+(("droid" if entry.get("pet_kind","droid")=="droid" else "pet") if entry.get("category","")=="pets" else "vehicle")
	if entry.get("category","")=="ships":vehicle_button.text=str(entry.get("action_label","Return to ground" if entry.get("launched",false) else "Prepare launch"))
	vehicle_button.disabled=busy or (entry.get("category","")=="ships" and not entry.get("available",true))
	delete_button.disabled = busy or not can_delete(entry)
	cancel_mission_button.visible=not cancellable_mission_id(entry).is_empty()
	cancel_mission_button.disabled=busy
	delete_button.visible=not cancel_mission_button.visible
	delete_button.tooltip_text = "Delete this saved entry" if can_delete(entry) else str(entry.get("deletion_reason","This entry is managed by the server"))
	detail_title.text = str(entry.get("name","Unnamed entry"))
	detail_type.text = str(entry.get("category","data")).capitalize()
	detail_description.text = str(entry.get("description",""))
	var fields := PackedStringArray()
	if entry.has("planet"): fields.append(str(entry.planet).capitalize())
	if entry.has("position"):
		var point := MapControl.position_of(entry.position)
		fields.append("Position   %.0f, %.0f" % [point.x,point.z])
		# Viewing an existing entry is not a map click and must not silently
		# change the position used by the New waypoint button.
	if entry.has("active"): fields.append("Active" if entry.active else "Inactive")
	# Replication IDs, CRCs and template paths are diagnostics, not item stats.
	var attributes: Dictionary = entry.get("attributes",{})
	if attributes.get("kind","") == "learned_draft_schematic": fields.append("Learned crafting recipe")
	if entry.get("reference_only",false): fields.append("Reference entry · no datapad capacity used")
	detail_attributes.text = "\n".join(fields)
	detail_preview.visible = false
	var preview := str(entry.get("preview_texture",""))
	if preview.is_empty():
		preview = str(manifest.get("template_previews",{}).get(str(entry.get("template","")),{}).get("preview_texture",""))
	if preview.is_empty():
		var icon_key := str(entry.get("icon","waypoint" if str(entry.get("category","")) == "waypoints" else "generic"))
		preview = str(manifest.get("icons",{}).get(icon_key,{}).get("texture",""))
	if not preview.is_empty():
		var path := catalog_directory.path_join(preview)
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null:
				detail_preview.custom_minimum_size.y = 160 if entry.has("preview_texture") or manifest.get("template_previews",{}).has(str(entry.get("template",""))) else 48
				detail_preview.texture = ImageTexture.create_from_image(image)
				detail_preview.visible = true
	if entry.get("category","")=="vehicles":
		var icon:=vehicle_icon(entry)
		if icon!=null:detail_preview.texture=icon;detail_preview.custom_minimum_size.y=160;detail_preview.visible=true
	if entry.get("type","")=="mission_parcel":
		var icon:=parcel_icon(entry)
		if icon!=null:detail_preview.texture=icon;detail_preview.custom_minimum_size.y=160;detail_preview.visible=true
		detail_description.text+="\n\nGrip this entry and pull it away from the datapad to hold the parcel."
	update_coordinates()
	entry_selected.emit(entry)

func set_sector_navigation(data:Dictionary,ship:Dictionary,contacts:Array,catalog:Dictionary)->void:
	build_ui();map.set_sector(data,ship,contacts)
	navigation_controls.visible=map_visible and not data.is_empty()
	projection_button.visible=not data.is_empty()
	map_filters.visible=map_visible and data.is_empty()
	waypoint_button.visible=data.is_empty()
	map_toggle.text="Entry list" if map_visible else "Planet map" if data.is_empty() else "Sector map"
	if not data.is_empty():navigation_controls.configure(catalog,ship)

func show_map(value: bool) -> void:
	if value and category == "skills": select_category("waypoints")
	map_visible = value
	expanded = value
	expand_button.text = "Compact map" if value else "Expand map"
	map_expansion_requested.emit(value)
	map.visible = value
	map_tools.visible = value
	map_filters.visible = value and map.sector.is_empty()
	navigation_controls.visible=value and not map.sector.is_empty()
	projection_button.visible=not map.sector.is_empty()
	list.visible = not value
	list_status.visible = not value
	map_toggle.text = "Entry list" if value else "Planet map" if map.sector.is_empty() else "Sector map"
	update_coordinates()

func update_coordinates() -> void:
	if not map.sector.is_empty():
		var p:Vector3=map.sector_ship;coordinates.text="Sector position   X %.0f   Y %.0f   Z %.0f"%[p.x,p.y,p.z];return
	var selected: bool = map.has_cursor
	var point: Vector3 = map.cursor if selected else player_position
	coordinates.text = "%s   X %.0f   Z %.0f%s" % ["Selected map point" if selected else "Your position",point.x,point.z," · height resolved on save" if selected else ""]
	waypoint_button.text = "New waypoint · map point" if selected else "New waypoint · my position"

func scroll_at(pixel: Vector2, delta: Vector2) -> void:
	# Continuous thumbstick deltas are pixels, in this panel's local coordinates.
	if category == "skills" and professions.visible:
		professions.scroll.scroll_vertical += int(delta.y)
		professions.scroll.scroll_horizontal += int(delta.x)
	elif map_visible and map.get_global_rect().has_point(global_position+pixel):
		map.center -= Vector2(delta.x*(1 if map.right_positive_x else -1),delta.y*(-1 if map.top_positive_z else 1)) / maxf(map.pixels_per_meter(),0.00001)
		map.queue_redraw()
	elif list.get_global_rect().has_point(global_position+pixel):
		list.get_v_scroll_bar().value += delta.y

func navigate_at(pixel: Vector2, steps: int) -> bool:
	if category=="skills" and professions.visible:
		if not busy and steps!=0:professions.navigate(steps);navigation_anchor=pixel
		return true
	if map_visible or not list.get_global_rect().has_point(global_position+pixel):return false
	if busy or list.item_count==0 or steps==0:return true
	var selected:=list.get_selected_items()
	var index:=clampi(0 if selected.is_empty() else selected[0]+steps,0,list.item_count-1)
	list.select(index);list.ensure_current_is_visible();select_entry(index)
	navigation_anchor=pixel
	return true

func navigation_target(pixel:Vector2)->Vector2:
	if category=="skills" and professions.visible and pixel.distance_to(navigation_anchor)<=12:
		var button:Button=professions.buttons.get(professions.selected_skill_id)
		if button!=null:return button.get_global_rect().get_center()-global_position
	if map_visible or not list.visible or pixel.distance_to(navigation_anchor)>12:return pixel
	var selected:=list.get_selected_items()
	if selected.is_empty():return pixel
	return list.global_position-global_position+list.get_item_rect(selected[0]).get_center()

func make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	return label

func make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	return button

func _exit_tree() -> void:
	if is_instance_valid(detail_panel) and detail_panel.get_parent() == null: detail_panel.free()

func set_service_points(values: Array) -> void:
	build_ui();map.set_service_points(values)

func set_registered_locations(values:Array)->void:
	build_ui()
	var points:Array=[]
	for row in values.slice(0,256):
		if not row is Dictionary or not row.get("registered",false) or str(row.get("zone",""))!=planet:continue
		var point:Variant=row.get("position")
		if not point is Array or point.size()!=3:continue
		if not Vector3(float(point[0]),float(point[1]),float(point[2])).is_finite():continue
		var id:=str(row.get("building_id",row.get("id","")))
		if id.is_empty():continue
		points.append({"id":id,"type":"poi","name":str(row.get("name","Registered performance venue"))+" · "+str(row.get("category","entertainer")),"position":point.duplicate(),"source":"Core3 registered venue","native_icon":row.get("native_icon",2)})
	if map.registered_locations==points:return
	map.registered_locations=points;map.queue_redraw()

func set_factory_blueprints(values:Array)->void:
	if values==factory_blueprints:return
	factory_blueprints=values.duplicate(true);set_entries(entries)
