extends Node3D
## Uses the existing inventory, services panel, native world and datapad paths.
const Presentation=preload("res://bounty/presentation.gd")
var services:Node3D
var app:Node
var busy:=false
var generation:=0
var mission_id:=""
var delivered:Dictionary={}
var previous_stage:=""
var assets:RefCounted
var notice:Label3D
var notice_until:=0
func setup(owner:Node3D)->void:
	services=owner;app=owner.app
	notice=Label3D.new();add_child(notice);notice.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");notice.font_size=24;notice.pixel_size=.001;notice.width=680;notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.modulate=Color("baffff");notice.billboard=BaseMaterial3D.BILLBOARD_ENABLED;notice.hide()
	var bag:Variant=app.get("inventory")
	if is_instance_valid(bag) and bag.has_signal("bounty_droid_requested"):bag.bounty_droid_requested.connect(use_droid)
func reset()->void:
	generation+=1;busy=false;mission_id="";delivered.clear();previous_stage="";notice_until=0
	if is_instance_valid(notice):notice.hide()
	if is_instance_valid(app) and is_instance_valid(app.get("datapad")) and is_instance_valid(app.datapad.get("ui")) and app.datapad.ui.has_method("set_bounty_missions"):app.datapad.ui.set_bounty_missions([])
func state()->Dictionary:return services.state.get("bounty",{})
func contacts()->Array:return Presentation.contacts(state())
func observe(_response:Dictionary)->void:
	var current:=state()
	var entry:=Presentation.entry(current)
	if is_instance_valid(app.get("datapad")) and is_instance_valid(app.datapad.get("ui")) and app.datapad.ui.has_method("set_bounty_missions"):app.datapad.ui.set_bounty_missions([] if entry.is_empty() else [entry])
	var next_mission:=str(current.get("mission_id",""))
	if next_mission!=mission_id:delivered.clear();previous_stage="";mission_id=next_mission
	var probe:Dictionary=current.get("probe",{})
	var id:=str(probe.get("id",""))
	if current.get("pve_only",false) and not id.is_empty() and str(probe.get("status",""))=="searching" and not delivered.has(id):
		# Joining an existing session is not a new landing. Play only an observed delivery.
		if previous_stage=="probe_calling":delivery_effect(probe)
		delivered[id]=true
	if not previous_stage.is_empty() and previous_stage!=str(current.get("stage","")):outcome(Presentation.progress_text(current))
	previous_stage=str(current.get("stage",""))
	sync_menu()
func sync_menu()->void:
	if not is_instance_valid(services.ui):return
	var ui:Node3D=services.ui
	var kind:=str(ui.terminal.get("kind",""))
	if kind=="bounty_droid":
		var item_id:=str(ui.terminal.get("item_id",""))
		var choices:=Presentation.choices(state(),item_id)
		if choices.is_empty() or str(ui.terminal.get("mission_id",""))!=str(state().get("mission_id","")):ui.close_interface();return
		var row:Dictionary=ui.terminal.duplicate(true);row.options=choices
		ui.apply_response({"terminal":row},false)
	elif kind=="bounty_informant":
		for row:Dictionary in contacts():
			if str(row.get("id",""))==str(ui.terminal.get("id","")):
				ui.apply_response({"terminal":row},false);return
		ui.close_interface()
func use_droid(item:Dictionary)->void:
	if busy or not Presentation.droid_item(item) or not app.world_ready or app.loading_stage or app.session_leaving or not is_instance_valid(services.ui):return
	var bag:Variant=app.get("inventory")
	var id:=str(item.get("id",""))
	if not is_instance_valid(bag) or str(bag.held_item.get("id",""))!=id or app.owned_inventory_item(id).is_empty():return
	busy=true
	var version:=generation;var character_epoch:int=app.datapad_epoch
	# Release only the local hand presentation. Core3 retains and consumes the item.
	bag.clear_held()
	var deadline:=Time.get_ticks_msec()+2000
	while (services.busy or not services.allowed) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		if version!=generation or character_epoch!=app.datapad_epoch:return
	var response:Dictionary={}
	if services.allowed and not services.busy:response=await services.request("status",{})
	if version!=generation or character_epoch!=app.datapad_epoch:return
	busy=false
	if not response.get("ok",false):outcome(str(response.get("error","Droid launch was not confirmed. Draw it again to retry.")));return
	if not services.allowed or not app.world_ready or app.loading_stage or app.session_leaving:return
	var launch:=Presentation.launch_action(state(),id)
	if not launch.is_empty():
		await services.request(launch,{"item_id":id})
		return
	var choices:=Presentation.choices(state(),id)
	if choices.is_empty():
		outcome("No available PvE bounty action for this droid. Check your current investigation in Data.")
		return
	services.ui.open_terminal({"id":"bounty-droid:"+id,"item_id":id,"mission_id":str(state().get("mission_id","")),"kind":"bounty_droid","name":"ARAKYD PROBE · SELECT PLANET","options":choices,"position":app.player.global_position})
func delivery_effect(probe:Dictionary)->void:
	if not app.world_ready or not probe.get("position") is Array or probe.position.size()!=3:return
	var rig:Variant=app.get("combat_rig")
	if not is_instance_valid(rig) or not is_instance_valid(rig.get("rounds_sim")):return
	if assets==null:
		assets=preload("res://combat/original_assets.gd").new();assets.directory=ProjectSettings.globalize_path("res://../runtime/assets/bounty")
		if not assets.load_catalog():assets=null;return
	var path:=str(assets.catalog.get("bounty_effects",{}).get("probot_delivery",""))
	var effect:Dictionary=assets.catalog.get("effects",{}).get(path,{})
	var point:Vector3=services.world(probe.position)
	var manager:Node3D=rig.rounds_sim.effects.ensure_manager()
	for appearance:Dictionary in effect.get("appearances",[]):manager.burst(str(appearance.particle),Transform3D(Basis.IDENTITY,point),float(appearance.duration),"impact",assets)
	var audio:=get_node_or_null("/root/SWGSpatialAudio")
	if audio!=null:
		for sound:String in effect.get("sounds",[]):audio.play_original(assets,sound,point,1)
	# Original camera shake never alters the tracked HMD.

func outcome(message:String)->void:
	if is_instance_valid(notice):notice.text=message;notice_until=Time.get_ticks_msec()+8000
	if is_instance_valid(app.get("datapad")) and is_instance_valid(app.datapad.get("ui")):app.datapad.ui.set_status(message)
func _process(_delta:float)->void:
	if not is_instance_valid(notice) or not is_instance_valid(app):return
	var rig:Variant=app.get("xr_origin")
	notice.visible=is_instance_valid(rig) and app.world_ready and not app.loading_stage and not app.session_leaving and Time.get_ticks_msec()<notice_until and not services.blocks_combat()
	if notice.visible:
		var head:Camera3D=rig.get_node("XRCamera3D")
		notice.global_position=head.global_position-head.global_basis.z*.85-Vector3.UP*.18
