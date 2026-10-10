extends Node3D
## Core3 owns ship, station, flight and decoration persistence. This client only
## renders acknowledged state and sends bounded controller input.
const Hands=preload("res://scripts/tracked_hand_input.gd")
const Scene=preload("res://space/scene.gd")
var app:Node
var preferences:RefCounted
var inputs=preload("res://space/flight_input.gd").new()
var scene:Node3D
var wheel:Node3D
var readout:Label3D
var state:Dictionary={}
var ship:Dictionary={}
var busy:=false
var epoch:=-1
var revision:=-1
var sequence:=0
var walk_sequence:=0
var pending_mutations:Dictionary={}
var poll:=0.0
var age:=100.0
var error:=""
var notice_until:=0
var ground:Dictionary={}
var station:="ground"
var seat_origin:=Transform3D.IDENTITY
var seat_eye_height:=0.0
var seat_floor_offset:=0.0
var seat_height_applied:=false
var view_environment:Environment
var previous_environment:Environment
var terminal_geometry:Dictionary={}
var stars:ShaderMaterial
var trigger_ready:=false
var fire_armed:=false
var recover_ready:=false
var needs_reconcile:=false
var control_handles:Node3D
var portal_view:Node
var lobby_open:=false
var cancel_lobby:=false
var handshake=preload("res://space/crew_handshake.gd").new()
var presentation_sequence:=int(Time.get_unix_time_from_system()*1000000.0)
var crew_poses:Array=[]
var interaction_waiting:=false
var station_labels:Dictionary={}
var station_pointer:Node3D
var hyperspace_effect:Node3D
var space_audio:Node
func setup(host:Node,prefs:RefCounted)->void:
	app=host;preferences=prefs;epoch=app.datapad_epoch
	wheel=preload("res://space/command_wheel.gd").new();add_child(wheel);wheel.selected.connect(command)
	readout=Label3D.new();readout.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");readout.font_size=22;readout.pixel_size=.0007;readout.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(readout);readout.hide()
	control_handles=Node3D.new();add_child(control_handles);control_handles.hide()
	for offset in [Vector3(.28,.60,-.32),Vector3(-.28,.60,-.32)]:
		var handle:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=.022;mesh.bottom_radius=.022;mesh.height=.13;handle.mesh=mesh;handle.position=offset;control_handles.add_child(handle)
	station_pointer=preload("res://scripts/finger_pointer_visual.gd").new();add_child(station_pointer)
	app.player.space=self
	app.datapad.ui.ship_action_requested.connect(datapad_action)
func aboard()->bool:return is_instance_valid(scene) and is_instance_valid(scene.stage) and not ground.is_empty()
func seated()->bool:return aboard() and station in ["pilot","passenger","gunner"]
func seat_pose()->Transform3D:
	return Transform3D(scene.stage.global_basis,scene.world(ship.get("player_position",[0,0,0]))+Vector3.UP*.45)
func rider_pose(race:String)->Dictionary:
	return hyperspace_effect.assets.catalog.get("seat_poses",{}).get(race,{}) if is_instance_valid(hyperspace_effect) else {}
func restore_seat_height()->void:
	if not seat_height_applied:return
	var body_pose:Transform3D=app.player.global_transform
	app.xr_origin.global_position.y=body_pose.origin.y+seat_floor_offset
	app.player.global_transform=body_pose;seat_height_applied=false
func reset()->void:
	fire_armed=false;lobby_open=false;cancel_lobby=false;handshake.reset();crew_poses=[];interaction_waiting=false
	leave_scene();state={};ship={};revision=-1;sequence=0;walk_sequence=0;pending_mutations.clear();needs_reconcile=false;busy=false;age=100;poll=0;station="ground";inputs.reset()
	if is_instance_valid(app):
		epoch=app.datapad_epoch
		if is_instance_valid(app.datapad):app.datapad.ui.set_ships([]);app.datapad.ui.set_skill_forgetting_available(true)
	if is_instance_valid(wheel):wheel.close()
func session()->Node:
	if is_instance_valid(app.live_combat) and app.live_combat.live:return app.live_combat
	return app.gameplay_session if is_instance_valid(app.gameplay_session) and app.gameplay_session.live else null
func assets_ready(template:="")->bool:
	var probe:=Scene.new();var ready:bool=probe.ready_assets(template);error=probe.error;probe.free();return ready
func request(action:String,detail:Dictionary={},synchronize_walk:=false)->Dictionary:
	if busy:
		if (action in ["status","control","walk"] and not synchronize_walk) or interaction_waiting:return {"ok":false,"error":"Ship request in progress"}
		# A trigger press during a flight heartbeat must not silently disappear.
		# Stop scheduling new heartbeats while one deliberate action waits.
		interaction_waiting=true
		var waiting_epoch:int=app.datapad_epoch;var deadline:=Time.get_ticks_msec()+2500
		while busy and waiting_epoch==app.datapad_epoch and not app.session_leaving and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		interaction_waiting=false
		if busy or waiting_epoch!=app.datapad_epoch or app.session_leaving:return {"ok":false,"error":"Wait for the current ship request to finish."}
	if synchronize_walk:
		if not aboard() or seated():return {"ok":false,"error":"Walk inside the ship before placing items."}
		walk_sequence+=1;detail={"position":scene.source(app.player.global_position),"cell_index":scene.cell_index(),"sequence":walk_sequence}
	var native:=session()
	if native==null:return {"ok":false,"error":"Connect your character before using a ship"}
	if action in ["launch","crew_prepare"]:
		var chosen:=str(detail.get("ship_id",launch_stage().get("ship_id","")))
		var template:=""
		for row:Dictionary in state.get("ships",[]):
			if str(row.get("id",""))==chosen:template=str(row.get("template",""));break
		if not assets_ready(template):notice(error);return {"ok":false,"error":error}
		if str(detail.get("terminal_id","")).is_empty():
			var terminal:=launch_terminal()
			if terminal.is_empty():notice("Visit a starship terminal to prepare your launch.");return {"ok":false,"error":error}
			detail.terminal_id=terminal
		if action=="launch" and str(detail.get("launch_id","")).is_empty():notice("Prepare the crew at a starship terminal before confirming launch.");return {"ok":false,"error":error}
	var version:int=app.datapad_epoch
	var payload:Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"session_id":native.session_id,"request_id":"jtl-%d-%d"%[Time.get_unix_time_from_system()*1000000,Time.get_ticks_usec()]}
	payload.merge(detail,true)
	if aboard() and action in ["status","control","walk"]:payload.presentation=presentation()
	var mutation:bool=action not in ["status","control","walk"]
	var key:=action+JSON.stringify(detail)
	if mutation:
		if not pending_mutations.has(key) and pending_mutations.size()>=128:return {"ok":false,"error":"Resolve unconfirmed ship requests before starting another."}
		if pending_mutations.has(key):payload.request_id=pending_mutations[key]
		else:pending_mutations[key]=payload.request_id
	busy=true
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/jtl/"+action,payload)
	if version!=app.datapad_epoch:return {}
	busy=false
	if response.get("source_kind","")!="core3_jtl" or str(response.get("character_id",""))!=app.datapad_character_id:
		error=str(response.get("error","CoreCU did not confirm the ship action"));notice(error)
		if action in ["walk","control"]:needs_reconcile=true;poll=0
		return response
	if mutation:pending_mutations.erase(key)
	var value:Variant=response.get("state",response.get("jtl",{}))
	var live:Variant=response.get("live_response",response.get("live"))
	if not value is Dictionary or value.get("scope","") not in ["noncombat_yacht","noncombat_navigation","original_sectors"] or not value.get("enabled",false):
		if action in ["walk","control"]:needs_reconcile=true;poll=0
		return {"ok":false,"error":"CoreCU returned an incomplete ship snapshot."}
	var native_revision:int=int(live.get("sequence",revision+1)) if live is Dictionary else int(response.get("sequence",revision+1))
	if native_revision<revision:return {"ok":false,"error":"A newer native ship snapshot is already active."}
	var next_ship:Variant=value.get("ship") if value is Dictionary else null
	if next_ship!=null and not next_ship is Dictionary:
		if action in ["walk","control"]:needs_reconcile=true;poll=0
		return {"ok":false,"error":"CoreCU returned an invalid ship state."}
	# A rejected control after the pilot disconnects still carries the native
	# passenger ejection destination. Consume that recovery before reporting failure.
	var landing:bool=(action=="land" and response.get("ok",false)) or (aboard() and (not next_ship is Dictionary or str(next_ship.get("station","ground"))=="ground"))
	if landing:app.world_ready=false;app.player.active=false;app.player.set_physics_process(false)
	crew_poses=response.get("crew_poses",[]) if response.get("crew_poses",[]) is Array else []
	if action=="walk" and not response.get("ok",false):needs_reconcile=true
	if not observe(value,native_revision):return {"ok":false,"error":"The native ship scene could not be displayed. "+error}
	if live is Dictionary:
		if native.has_method("accept_native_response"):native.accept_native_response(live)
		elif native.has_method("accept_response"):native.accept_response(live)
	if landing:
		var destination:Dictionary=live.get("snapshot",{}).get("player",{}) if live is Dictionary else {}
		if not preload("res://combat/live_transport.gd").new().destination_valid(destination):
			notice("CoreCU landing position is unavailable; reconnect to resume on the ground.");return {"ok":false,"error":error}
		if not await app.perform_service_transport({"destination":destination}):return {"ok":false,"error":"The original landing area could not be loaded."}
	if not response.get("ok",false):notice(str(response.get("error","Ship action rejected")));return response
	if action=="crew_prepare":show_lobby()
	if action=="command" and str(detail.get("command_id","")).begins_with("elevator_") and aboard():scene.place_player(app.player,ship.player_position,int(ship.cell_index))
	if response.get("inventory") is Dictionary and str(response.inventory.get("character_id",""))==app.datapad_character_id:
		app.inventory_snapshot=response.inventory.duplicate(true);app.reconcile_inventory_presentations();app.update_inventory_presentation()
	if action not in ["status","control","walk"]:notice(str(response.get("mutation",{}).get("message","Ship action confirmed")))
	return response
func observe(value:Dictionary,incoming_revision:int=-1)->bool:
	if str(value.get("source_kind","core3_jtl"))!="core3_jtl" or str(value.get("character_id",app.datapad_character_id))!=app.datapad_character_id:return false
	if value.get("scope","") not in ["noncombat_yacht","noncombat_navigation","original_sectors"] or not value.get("enabled",false):return false
	if incoming_revision>=0 and incoming_revision<revision:return false
	var incoming:Variant=value.get("ship")
	if incoming!=null and not incoming is Dictionary:return false
	var next_ship:Dictionary=incoming if incoming is Dictionary else {}
	var next:=str(next_ship.get("station","ground"))
	if next not in ["pilot","passenger","gunner","interior","ground"]:return false
	revision=maxi(revision,incoming_revision);state=value.duplicate(true);ship=next_ship.duplicate(true);age=0
	sequence=maxi(sequence,int(ship.get("control_sequence",0)));walk_sequence=maxi(walk_sequence,int(ship.get("walk_sequence",0)))
	var changed:=station!=next
	if changed:restore_seat_height()
	if aboard() and next!="ground" and scene.ship_id!=str(ship.get("id","")):leave_scene();changed=true
	if next!="ground" and not aboard():
		if not enter_scene(ship):notice(error);return false
		changed=true
	elif next=="ground" and aboard():leave_scene()
	station=next
	if aboard():
		scene.observe(ship)
		if is_instance_valid(space_audio):space_audio.observe(ship,state.get("combat_events",[]),scene.visual_ship_pose)
		if is_instance_valid(hyperspace_effect):hyperspace_effect.observe(ship.get("hyperspace",{}),app.player.get_camera())
		scene.update_nearby(state.get("nearby_ships",[]),ship,state.get("nearby_ships_busy",false))
		if is_instance_valid(scene.combat_effects):scene.combat_effects.receive(state.get("combat_events",[]))
		if changed and is_instance_valid(wheel):wheel.close()
		if changed or needs_reconcile or bool(ship.get("walk_corrected",false)):
			scene.place_player(app.player,ship.get("player_position",[-.76,.43,21.14] if next=="pilot" else [0,.4,20]),int(ship.get("cell_index",1)))
			inputs.reset();needs_reconcile=false
			if next in ["pilot","passenger","gunner"]:
				# Rotate the play-space origin once; tracked HMD/controller local poses stay untouched.
				app.player.rotate_player(app.player.get_camera().global_rotation.y-scene.stage.global_rotation.y)
				scene.place_player(app.player,ship.get("player_position",[0,0,0]),int(ship.get("cell_index",1)))
				if not seat_height_applied:
					seat_floor_offset=app.xr_origin.global_position.y-app.player.global_position.y
					var body_pose:Transform3D=app.player.global_transform
					app.xr_origin.global_position.y+=seat_pose().origin.y+.68-app.player.get_camera().global_position.y
					app.player.global_transform=body_pose;seat_height_applied=true
				seat_origin=app.xr_origin.global_transform;seat_eye_height=app.player.get_camera().global_position.y
		app.player._update_locomotion()
		update_crew()
	update_lobby()
	refresh_datapad()
	return true
func enter_scene(value:Dictionary)->bool:
	var created:=Scene.new();add_child(created);created.position=Vector3(0,10000,0)
	if not created.build(str(value.get("id","")),str(value.get("template","")),str(value.get("zone","space_tatooine"))):error=created.error;created.queue_free();return false
	ground={"stage":app.stage,"position":app.player.global_position,"origin":app.xr_origin.global_transform,"provider":app.player.ground_provider,"camera_far":app.player.get_camera().far,"hidden":[],"environment_active":false}
	if is_instance_valid(app.environment_presentation):
		ground.environment_active=app.environment_presentation.active;app.environment_presentation.set_active(false)
	for key in ["stage","terrain","world_stream","ambient_npcs","environment_presentation","portal_visibility","housing","vehicles","gameplay_combat"]:
		var node:Variant=app.get(key)
		if is_instance_valid(node):
			ground.hidden.append({"node":node,"process":node.process_mode,"visible":node.visible if node is Node3D else false})
			node.process_mode=Node.PROCESS_MODE_DISABLED
			if node is Node3D:node.hide()
	scene=created
	space_audio=preload("res://space/audio.gd").new();scene.add_child(space_audio)
	hyperspace_effect=preload("res://space/hyperspace.gd").new();scene.add_child(hyperspace_effect);hyperspace_effect.setup(app.player.get_camera())
	scene.align_cockpit(app.player.get_camera().global_position.y-app.player.global_position.y)
	app.stage=scene.stage;app.player.ground_provider=scene.stage;scene.stage.set_observer(app.player)
	portal_view=preload("res://scripts/portal_visibility.gd").new();scene.add_child(portal_view);portal_view.configure(scene.stage,app.player.get_camera(),app.xr_spectator.camera if is_instance_valid(app.xr_spectator) and app.xr_spectator.enabled else null)
	previous_environment=app.player.get_camera().environment
	app.player.get_camera().far=20000.0
	view_environment=Environment.new();view_environment.background_mode=Environment.BG_SKY;view_environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;view_environment.ambient_light_color=Color(.5,.6,.8);view_environment.ambient_light_energy=.6
	var sky:=Sky.new();stars=scene.exterior.sky;sky.sky_material=stars;view_environment.sky=sky;app.player.get_camera().environment=view_environment
	RenderingServer.global_shader_parameter_set("swg_environment_tint",Color.WHITE)
	for combat in [app.live_combat,app.gameplay_combat]:
		if is_instance_valid(combat):combat.discard_movement_commands()
	if is_instance_valid(app.combat_rig):app.combat_rig.set_allowed(false)
	lobby_open=false;cancel_lobby=false
	if is_instance_valid(app.services) and is_instance_valid(app.services.ui):app.services.ui.close_interface()
	if is_instance_valid(app.datapad):app.datapad.set_open(false);app.datapad.ui.set_skill_forgetting_available(false,"Return to ground before forgetting skills.")
	return true
func leave_scene()->void:
	restore_seat_height()
	show_station_targets(false)
	terminal_geometry.clear()
	if is_instance_valid(station_pointer):station_pointer.hide()
	if not aboard():return
	app.stage=ground.stage;app.player.ground_provider=ground.provider
	app.xr_origin.global_transform=ground.origin;app.player.global_position=ground.position;app.player.velocity=Vector3.ZERO
	for row:Dictionary in ground.hidden:
		if is_instance_valid(row.node):
			row.node.process_mode=row.process
			if row.node is Node3D:row.node.visible=row.visible
	if is_instance_valid(app.environment_presentation):app.environment_presentation.set_active(bool(ground.environment_active))
	app.player.get_camera().environment=previous_environment
	app.player.get_camera().far=float(ground.camera_far)
	if is_instance_valid(app.portal_visibility):
		if app.stage.interior_cells_changed.is_connected(app.portal_visibility.refresh_instances):app.stage.interior_cells_changed.disconnect(app.portal_visibility.refresh_instances)
		app.portal_visibility.configure(app.stage,app.player.get_camera(),app.xr_spectator.camera if is_instance_valid(app.xr_spectator) and app.xr_spectator.enabled else null)
	scene.queue_free();scene=null;ground={};station="ground";inputs.reset();app.player._update_locomotion()
	readout.hide();control_handles.hide();wheel.close()
	if is_instance_valid(app.datapad):app.datapad.ui.set_skill_forgetting_available(true)
	if is_instance_valid(app.services):app.services.poll_clock=0
func refresh_datapad()->void:
	if not is_instance_valid(app.datapad):return
	var rows:Array=[]
	for row:Dictionary in state.get("ships",[]):
		var available:bool=str(row.id)==str(ship.get("id","")) and station=="pilot" if aboard() else bool(row.get("eligible",row.get("supported",true)))
		var description:=str(row.get("reason",""))
		if description.is_empty():description="Prepare departure at a starship terminal; shake hands to form your crew, then confirm Launch."
		rows.append({"id":str(row.id),"category":"ships","type":"ship","name":str(row.get("name","Starship")),"template":row.get("template",""),"launched":row.get("launched",false),"description":description,"deletable":false,"action_label":("Contact station" if available else "Land at a station first") if aboard() else "Prepare launch","available":available})
	var own:Dictionary=return_ship_record()
	if not own.is_empty():
		rows=rows.filter(func(row):return str(row.id)!=str(own.get("ship_id","")))
		rows.append({"id":"return:"+str(own.get("ship_id","")),"category":"ships","type":"ship","name":"Return to your ship","description":"Leave this ship and launch your own craft nearby.","temporary_return":true,"action_label":"Return to your ship","deletable":false,"available":true})
	app.datapad.ui.set_ships(rows)
	app.datapad.ui.set_space_missions(state.get("missions",[]))
	if not app.datapad.ui.hyperspace_requested.is_connected(hyperspace):
		app.datapad.ui.hyperspace_requested.connect(hyperspace)
		app.datapad.ui.hyperspace_abort_requested.connect(abort_hyperspace)
	app.datapad.ui.set_sector_navigation(scene.exterior.data if aboard() else {},ship,state.get("nearby_ships",[])+state.get("waypoints",[]),scene.catalog if aboard() else {})
	if is_instance_valid(app.datapad.get("radar")):app.datapad.radar.set_sector(scene.exterior.data if aboard() else {},ship,state.get("nearby_ships",[])+state.get("waypoints",[]))
func hyperspace(destination:String)->void:
	if aboard() and station=="pilot":request("hyperspace",{"destination":destination})
func abort_hyperspace()->void:
	if aboard() and station=="pilot":request("abort_hyperspace")
func terminal_records()->Array:
	var rows:Array=[]
	if not aboard() or seated():return rows
	for source:Dictionary in ship.get("interactions",[]):
		if int(source.get("cell_index",0))!=scene.cell_index():continue
		var row:=source.duplicate(true);row.position=scene.world(source.position)
		row.pob=true;row.name=str(source.get("label","Ship terminal"));row.item_count=ship.get("item_count",0);row.item_limit=ship.get("item_limit",0)
		row.options=[]
		if source.get("kind","")=="house":
			for item:Dictionary in ship.get("decorations",[]):
				row.options.append({"id":str(item.id),"name":"Recover "+str(item.get("name",item.get("template","Item").get_file())),"description":"Room %d · return this item to your inventory"%int(item.get("cell_index",0)),"item_id":str(item.id)})
		else:row.options=[{"id":"activate","name":row.name,"command_id":source.command_id}]
		var key:=str(source.id)
		if not terminal_geometry.has(key):
			var path:=str(source.get("template",""));var shared:=path.get_base_dir().path_join("shared_"+path.get_file())
			for node:Node in scene.stage.find_children("*","MeshInstance3D",true,false):
				if str(node.get_meta("source_template",""))==shared and node.global_position.distance_to(row.position)<.5:
					terminal_geometry[key]={"pick_geometry":{"faces":node.mesh.get_faces(),"bounds":node.mesh.get_aabb()},"pick_pose":node.global_transform};break
		row.merge(terminal_geometry.get(key,{}),true);rows.append(row)
	return rows
func terminal_request(action:String,detail:Dictionary)->Dictionary:
	var ui:Node=app.services.ui
	var revision:int=ui.interaction_epoch
	var terminal_id:=str(detail.get("terminal_id",ui.terminal.get("id","")))
	var response:Dictionary
	var walked:=await request("walk",{},true)
	if not walked.get("ok",false):response=walked
	elif action=="pob_recover":response=await request("terminal_recover",{"terminal_id":terminal_id,"item_id":str(detail.get("item_id",""))})
	elif action=="ship_terminal_command":response=await request("command",{"interaction_id":terminal_id,"command_id":str(detail.get("command_id",""))})
	elif ui.terminal.get("kind","")=="house":response=await request("terminal",{"terminal_id":terminal_id})
	else:response=await request("status")
	if action=="pob_recover" and response.get("ok",false):app.refresh_inventory()
	if revision!=ui.interaction_epoch or ui.terminal.is_empty():return response
	ui.set_pending(false)
	var records:=terminal_records().filter(func(row):return str(row.id)==terminal_id)
	if not records.is_empty():ui.terminal=records[0];ui.panel.configure(records[0],{})
	ui.panel.message="Item returned to inventory." if action=="pob_recover" and response.get("ok",false) else "Confirmed by CoreCU" if response.get("ok",false) else str(response.get("error","Ship terminal request rejected."))
	ui.panel.queue_redraw();return response
func launch_terminal()->String:
	if not is_instance_valid(app.services):return ""
	for row:Dictionary in app.services.terminal_records():
		if row.get("kind","")=="starship" and row.position.distance_to(app.player.global_position)<=6.0:return str(row.id)
	return ""
func datapad_action(entry:Dictionary)->void:
	if entry.get("temporary_return",false):request("return_ship");return
	if aboard():command("communications")
	else:request("crew_prepare",{"ship_id":str(entry.get("id",""))})
func launch_stage()->Dictionary:
	var value:Variant=state.get("launch_stage")
	return value if value is Dictionary else {}
func return_ship_record()->Dictionary:
	var boarding:Variant=state.get("boarding",{})
	var value:Variant=boarding.get("return_ship") if boarding is Dictionary else null
	return value if value is Dictionary else {}
func lobby_closed()->void:
	if not lobby_open:return
	lobby_open=false
	if not aboard() and str(launch_stage().get("pilot_id",""))==app.datapad_character_id:cancel_lobby=true;poll=0
func show_lobby()->void:
	var prepared:=launch_stage()
	if prepared.is_empty() or str(prepared.get("pilot_id",""))!=app.datapad_character_id or not is_instance_valid(app.services) or not is_instance_valid(app.services.ui):return
	var ui:Node3D=app.services.ui
	if not ui.allowed:cancel_lobby=true;return
	var terminal:Dictionary={}
	for row:Dictionary in app.services.terminal_records(false):
		if str(row.get("id",""))==str(prepared.get("terminal_id","")):terminal=row;break
	if terminal.is_empty() or app.player.global_position.distance_to(terminal.position)>3.0:cancel_lobby=true;return
	# Reuse the original terminal screen anchor and finger interaction surface.
	if ui.terminal.is_empty():ui.open_terminal(terminal)
	lobby_open=true;update_lobby()
func update_lobby()->void:
	if not lobby_open or not is_instance_valid(app.get("services")) or not is_instance_valid(app.services.ui):return
	var ui:Node3D=app.services.ui;var prepared:=launch_stage()
	if prepared.is_empty() or aboard():
		lobby_open=false;ui.close_interface();return
	var record:Dictionary=ui.terminal.duplicate(true)
	record.merge({"id":str(prepared.get("terminal_id","")),"kind":"ship_crew","name":"CONFIRM DEPARTURE","launch_id":str(prepared.get("id","")),"pilot_id":str(prepared.get("pilot_id","")),"is_pilot":str(prepared.get("pilot_id",""))==app.datapad_character_id,"capacity":prepared.get("capacity",1),"members":prepared.get("members",[])},true)
	if record!=ui.terminal:
		ui.terminal=record;ui.panel.configure(record,ui.wallet,ui.tickets);ui.panel.selected=-1
	ui.set_pending(busy)
func consume_crew_handshakes(peers:Array)->void:
	if busy or aboard() or not launch_stage().is_empty() or not is_instance_valid(app.services):return
	var side:="right" if app.vr_settings.offhand=="left" else "left"
	if not app.services.party_hand_free(side,true):return
	var detail:Dictionary=handshake.take_ready(app.datapad_character_id,peers)
	if not detail.is_empty():
		var result:Dictionary=await request("crew_join",detail)
		if result.get("ok",false):app.services.show_party_notice("Joined the flight crew. Stay near the terminal until the pilot launches.")
func presentation()->Dictionary:
	presentation_sequence+=1
	var tracking:Dictionary={};var posture:=0
	if is_instance_valid(app.get("multiplayer_sync")):
		tracking=app.multiplayer_sync.tracking();posture=app.multiplayer_sync.physical_posture()
	var body:Node3D=app.tracked_avatar if is_instance_valid(app.tracked_avatar) else app.player
	return {"sequence":presentation_sequence,"position":scene.source(app.player.global_position),"heading_radians":-body.global_rotation.y,"cell_index":int(ship.get("cell_index",scene.cell_index())),"tracking":tracking,"physical_posture":posture}
func update_crew()->void:
	if aboard():scene.update_crew(ship,crew_poses,app.datapad_character_id,app.player.global_position)
func notice(message:String)->void:
	error=message;notice_until=Time.get_ticks_msec()+5000
	if is_instance_valid(app.datapad):app.datapad.ui.set_status(message)
func pilot_pose()->Transform3D:
	var location:Array=[-.76,.43,21.14]
	for row:Dictionary in ship.get("stations",[]):
		if row.get("id","")=="pilot":location=row.get("position",location);break
	return Transform3D(Basis.IDENTITY,scene.world(location))
func button(name:String,side:String)->bool:
	if not aboard() or name!="primary_click":return false
	if not seated():return false
	if side==app.player.dominant_hand:
		if wheel.opened:wheel.close()
		else:wheel.open(app.player.get_camera().global_transform,command_rows())
	else:
		wheel.close()
		if seated() and ship.get("kind","pob")=="pob":request("leave")
	return true
func station_option(candidate:Dictionary)->Dictionary:
	var id:=str(candidate.get("id",""))
	var reason:=""
	if not aboard() or seated() or ship.get("kind","pob")!="pob":reason="Leave your current station first."
	elif id not in ["pilot","passenger"]:reason="Station unavailable."
	elif id=="pilot" and str(ship.get("owner_id",""))!=app.datapad_character_id:reason="Only the ship owner can pilot."
	elif str(candidate.get("occupied_by","")) not in ["","0",app.datapad_character_id]:reason="Station occupied."
	elif int(candidate.get("cell_index",0))!=scene.cell_index():reason="Return to the bridge."
	elif app.player.global_position.distance_to(scene.world(candidate.position))>2.75:reason="Move closer to the seat."
	return {"id":"station:"+id,"label":"Take pilot seat" if id=="pilot" else "Take passenger seat","available":reason.is_empty(),"reason":reason}
func take_station(id:String)->void:
	for candidate:Dictionary in ship.get("stations",[]):
		if str(candidate.get("id",""))!=id:continue
		var option:=station_option(candidate)
		if not option.available:notice(option.reason);return
		# request() queues deliberate input behind an in-flight walk/flight update.
		request("station",{"station_id":id});return
	notice("Station unavailable. Refresh ship status and try again.")
func command_rows()->Array:
	var rows:Array=[]
	if not seated():return rows
	rows.append({"id":"navigation","label":"Sector map · hyperspace planner","available":true})
	for group in ["shield","power","droid"]:
		var available:bool=ship.get("commands",[]).any(func(row):return str(row.get("id","")).begins_with(group))
		if available:rows.append({"id":"group_"+group,"label":{"shield":"Shield distribution","power":"Power distribution","droid":"Droid commands"}[group],"available":true})
	if not state.get("nearby_ships",[]).is_empty():rows.append({"id":"boarding_targets","label":"Nearby ships · board request","available":station=="pilot"})
	var boarding:Dictionary=state.get("boarding",{})
	if not boarding.get("incoming",[]).is_empty():rows.append({"id":"boarding_incoming","label":"Boarding requests · pilot consent","available":station=="pilot"})
	if not return_ship_record().is_empty():rows.append({"id":"return_ship","label":"Return to your ship","available":true})
	rows.append({"id":"communications","label":"Communications · request landing","available":station=="pilot","reason":"The pilot contacts the station."})
	if seated() and ship.get("kind","pob")=="pob":rows.append({"id":"leave","label":"Leave station","available":true})
	return rows
func command(id:String)->void:
	if id=="communications":
		var rows:Array=[]
		for target:Dictionary in state.get("nearby_ships",[]):
			if target.get("station_comms",false):rows.append({"id":"comm:"+str(target.id),"label":str(target.get("name","Station"))+" · %.0f m"%float(target.get("distance_m",0)),"available":target.get("comm_in_range",false),"reason":"Approach the station to communicate."})
		if rows.is_empty():rows.append({"id":"unavailable","label":"No station in range · consult sector map","available":false})
		rows.append({"id":"back","label":"Back","available":true});wheel.open(app.player.get_camera().global_transform,rows);return
	if id.begins_with("comm:") or id.begins_with("comm_option:"):
		var detail:Dictionary={"station_id":id.trim_prefix("comm:")}
		var action:="comm_begin"
		if id.begins_with("comm_option:"):
			var conversation:Dictionary=state.get("station_conversation",{})
			detail={"station_id":str(conversation.get("npc_id","")),"screen_token":str(conversation.get("screen_token","")),"option":int(id.trim_prefix("comm_option:"))};action="comm_choose"
		var result:=await request(action,detail)
		if result.get("ok",false):show_communications()
		return
	if id=="navigation":
		wheel.close();refresh_datapad();app.datapad.set_open(true);app.datapad.ui.show_map(true);return
	if id.begins_with("station:"):take_station(id.trim_prefix("station:"));return
	if id in ["boarding_targets","boarding_incoming"]:
		var rows:Array=[]
		if id=="boarding_targets":
			for nearby:Dictionary in state.get("nearby_ships",[]):
				rows.append({"id":"board:"+str(nearby.get("id",nearby.get("ship_id",""))),"label":str(nearby.get("name","Ship"))+" · %.0f m"%float(nearby.get("distance",nearby.get("distance_m",0))),"available":nearby.get("boarding_eligible",nearby.get("boarding_available",nearby.get("can_board",false))),"reason":str(nearby.get("boarding_reason",nearby.get("reason","Boarding is unavailable.")))})
		else:
			for incoming:Dictionary in state.get("boarding",{}).get("incoming",[]):
				var requester:=str(incoming.get("character_id",incoming.get("requester_id","")))
				rows.append({"id":"board_accept:"+requester,"label":"Allow "+str(incoming.get("name","Visitor")),"available":true})
				rows.append({"id":"board_decline:"+requester,"label":"Decline "+str(incoming.get("name","Visitor")),"available":true})
		rows.append({"id":"back","label":"Back","available":true});wheel.open(app.player.get_camera().global_transform,rows);return
	if id.begins_with("board:"):request("boarding_request",{"target_ship_id":id.trim_prefix("board:")});return
	if id.begins_with("board_accept:"):request("boarding_accept",{"requester_id":id.trim_prefix("board_accept:")});return
	if id.begins_with("board_decline:"):request("boarding_decline",{"requester_id":id.trim_prefix("board_decline:")});return
	if id.begins_with("group_"):
		var rows:Array=[]
		var prefix:=id.trim_prefix("group_")
		var labels:Dictionary={"shield_front":"Shields forward","shield_rear":"Shields aft","shield_balance":"Balance shields","power_engines":"Engine priority","power_balanced":"Balanced power","droidcommand_shieldadjustfrontone":"Droid · forward shields","droidcommand_shieldadjustrearone":"Droid · aft shields","droidcommand_engineoverloadone":"Droid · engine overload","droidcommand_enginenormalize":"Droid · normalize engine"}
		for entry:Dictionary in ship.get("commands",[]):
			if str(entry.get("id","")).begins_with(prefix):
				var row:=entry.duplicate(true);row.label=labels.get(str(row.id),str(row.get("label","")).replace("_"," ").capitalize());rows.append(row)
		rows.append({"id":"back","label":"Back","available":true})
		wheel.open(app.player.get_camera().global_transform,rows);return
	if id=="back":wheel.open(app.player.get_camera().global_transform,command_rows());return
	if id in ["leave","return_ship"]:request(id)
	else:request("command",{"command_id":id})
func show_communications()->void:
	var conversation:Dictionary=state.get("station_conversation",{})
	var rows:Array=[]
	for option:Dictionary in conversation.get("options",[]):
		rows.append({"id":"comm:"+str(conversation.get("npc_id","")) if option.get("begin",false) else "comm_option:"+str(option.get("option",0)),"label":str(option.get("name","Reply")),"available":true})
	rows.append({"id":"back","label":"Close communications","available":true})
	notice(str(conversation.get("dialogue","Station communications")))
	wheel.open(app.player.get_camera().global_transform,rows)
	wheel.show_dialogue(str(conversation.get("dialogue","Station communications")))
func station_target(pointer:Dictionary,hand_position:Vector3)->Dictionary:
	var nearest:Dictionary={};var best:=INF
	for candidate:Dictionary in ship.get("stations",[]):
		if not station_option(candidate).available:continue
		var point:Vector3=scene.world(candidate.position)+Vector3(0,.95,0)
		var distance:=hand_position.distance_to(point)
		var hit:=distance<.65
		if not pointer.is_empty():
			var origin:Vector3=pointer.ray_origin;var direction:Vector3=pointer.direction
			var along:float=(point-origin).dot(direction)
			if along>=0 and along<=3 and (origin+direction*along).distance_to(point)<.3:hit=true;distance=along
		if hit and distance<best:nearest={"station":candidate,"world":point};best=distance
	return nearest
func show_station_targets(permitted:bool)->void:
	for label:Label3D in station_labels.values():label.hide()
	if not permitted or seated() or not aboard():return
	for candidate:Dictionary in ship.get("stations",[]):
		if not station_option(candidate).available:continue
		var id:=str(candidate.id)
		if not station_labels.has(id):
			var label:=Label3D.new();label.font=readout.font;label.font_size=22;label.pixel_size=.0008
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.outline_size=5;add_child(label);station_labels[id]=label
		var label:Label3D=station_labels[id]
		label.global_position=scene.world(candidate.position)+Vector3(0,.95,0)
		label.text=("Take pilot seat" if id=="pilot" else "Take passenger seat")+"\nAim · Trigger";label.show()
func hotas_pose()->Transform3D:
	var pose:=pilot_pose()
	pose.origin.y=seat_eye_height-1.05 # Handles are .60m above this frame, .45m below the seated eyes.
	pose.basis=scene.stage.global_basis.orthonormalized()
	return pose
func hand_busy(side:String)->bool:
	if not seated() or station!="pilot" or preferences.mode!="virtual_hotas":return false
	var hand:XRController3D=app.xr_origin.get_node(side.capitalize()+"Hand")
	var anchor:=Vector3(-.28 if side=="left" else .28,.60,-.32)
	return (inputs.throttle_held if side=="left" else inputs.stick_held) or (hotas_pose().affine_inverse()*hand.global_position).distance_to(anchor)<preferences.grip_radius
func flight_inventory_busy()->bool:
	var bag:Node3D=app.inventory
	return is_instance_valid(bag) and (bag.is_open or not bag.held_item.is_empty() or not bag.equipment_drag.is_empty() or bag.hologram.active or bag.action_pending)
func controls(delta:float)->Dictionary:
	var left:XRController3D=app.xr_origin.get_node("LeftHand");var right:XRController3D=app.xr_origin.get_node("RightHand")
	var tracked:bool=bool(app.player.combat_tracking_context().tracked) and Hands.controller_tracked(left) and Hands.controller_tracked(right)
	if app.menu.visible or not app.xr_focused or not bool(app.player.combat_tracking_context().tracked) or wheel.opened or app.datapad.is_open or flight_inventory_busy() or (is_instance_valid(app.services) and app.services.blocks_combat()) or age>3:
		inputs.reset();fire_armed=false;return inputs.neutral()
	var output:Dictionary=inputs.sample(preferences,tracked,left.global_transform,right.global_transform,left.get_float("grip"),right.get_float("grip"),left.get_vector2("primary"),right.get_vector2("primary"),hotas_pose(),delta,preferences.physical_values() if preferences.mode=="physical_hotas" else {})
	var main:XRController3D=right if app.player.dominant_hand=="right" else left
	var firing:bool=main.get_float("trigger")>.65
	if preferences.mode=="physical_hotas":firing=preferences.physical_fire()
	if not firing:fire_armed=true
	output.primary_fire=tracked and fire_armed and firing and not ship.get("combat_excluded",true)
	return output
func _process(delta:float)->void:
	if not is_instance_valid(app) or app.session_leaving:return
	if epoch!=app.datapad_epoch:reset();return
	age+=delta;poll-=delta
	if not error.is_empty() and Time.get_ticks_msec()>notice_until:error=""
	if session()==null:
		if aboard():inputs.reset()
		return
	if not app.world_ready:return
	if interaction_waiting:return
	if not aboard():
		if cancel_lobby and not busy:
			cancel_lobby=false;request("crew_cancel");return
		if app.world_ready and not busy and poll<=0:
			poll=.5 if not launch_stage().is_empty() else 5.0;request("status")
		return
	readout.show();readout.global_position=pilot_pose().origin+Vector3(0,1.05,-.85)
	var position:Array=ship.get("position",[0,0,0]);readout.text="%s · %s\n%.0f m/s · X %.0f  Y %.0f  Z %.0f\n%s"%[str(ship.get("name","Starship")).to_upper(),"NON-COMBAT" if ship.get("combat_excluded",true) else "COMBAT SHIP",float(ship.get("speed_mps",0)),float(position[0]),float(position[1]),float(position[2]),("Crew %d · Right stick click · commands"%ship.get("crew",[]).size()) if error.is_empty() else error]
	if ship.get("hyperspacing",false):
		var jump:Dictionary=ship.get("hyperspace",{})
		readout.text+="\nHyperspace · "+str(jump.get("phase","calculating")).capitalize()+(" · %d"%int(jump.countdown) if int(jump.get("countdown",0))>0 else "")
	if not ship.get("combat_excluded",true):
		var hull:Dictionary=ship.get("hull",{});var shields:Dictionary=ship.get("shields",{});var capacitor:Dictionary=ship.get("capacitor",{})
		readout.text+="\nHull %.0f / %.0f · Shields %.0f / %.0f · Capacitor %.0f"%[float(hull.get("current",0)),float(hull.get("maximum",0)),float(shields.get("front",0)),float(shields.get("rear",0)),float(capacitor.get("current",0))]
	if not state.get("boarding",{}).get("incoming",[]).is_empty():readout.text+="\nBoarding request · open commands to allow or decline"
	elif not state.get("boarding",{}).get("pending",{}).is_empty():readout.text+="\nAwaiting the other pilot’s boarding consent"
	control_handles.visible=seated() and station=="pilot" and preferences.mode=="virtual_hotas";control_handles.global_transform=hotas_pose()
	if ship.get("quaternion") is Array and ship.quaternion.size()==4:
		if stars!=scene.exterior.sky:stars=scene.exterior.sky;view_environment.sky.sky_material=stars
		stars.set_shader_parameter("ship_rotation",scene.visual_ship_pose.basis)
	var output:=controls(delta) if seated() and station=="pilot" else inputs.neutral()
	if seated() and station=="pilot":readout.text+="\nThrottle %d%% · Engine limit %.0f m/s"%[roundi(float(output.throttle)*100),float(ship.get("max_speed_mps",0))]
	if seated():
		app.xr_origin.global_transform=seat_origin;app.player.velocity=Vector3.ZERO
		if not busy and poll<=0:
			if needs_reconcile:poll=.5;request("status");return
			if station=="pilot" and not ship.get("hyperspacing",false):sequence+=1;output.sequence=sequence;poll=.1;request("control",output)
			else:poll=.5;request("status")
	elif not busy and poll<=0:
		poll=.25
		if needs_reconcile:request("status");return
		walk_sequence+=1;request("walk",{"position":scene.source(app.player.global_position),"cell_index":scene.cell_index(),"sequence":walk_sequence})
	interaction()
func interaction()->void:
	show_station_targets(false);station_pointer.hide()
	if is_instance_valid(app.services) and app.services.blocks_combat():trigger_ready=false;return
	if is_instance_valid(app.get("voice_controls")) and app.voice_controls.blocks_combat():trigger_ready=false;return
	if is_instance_valid(app.inventory) and app.inventory.blocks_services():trigger_ready=false;return
	var left:XRController3D=app.xr_origin.get_node("LeftHand");var right:XRController3D=app.xr_origin.get_node("RightHand")
	var tracked:bool=Hands.controller_tracked(left) and Hands.controller_tracked(right) and bool(app.player.combat_tracking_context().tracked) and app.xr_focused and not app.menu.visible
	var main:XRController3D=right if app.player.dominant_hand=="right" else left
	if not tracked:trigger_ready=false;return
	var pressed:bool=tracked and main.get_float("trigger")>.65
	if not pressed:trigger_ready=true
	if wheel.opened:
		wheel.choose(main.get_vector2("primary"))
		if pressed and trigger_ready:trigger_ready=false;wheel.confirm()
	elif not seated() and tracked:
		show_station_targets(true)
		var pointer:Dictionary=preload("res://scripts/rendered_finger_pointer.gd").pose(null,app.player.dominant_hand,app.xr_origin,main)
		var target:=station_target(pointer,main.global_position)
		station_pointer.update_pointer(pointer.get("tip",main.global_position),target)
		if not target.is_empty():
			readout.text="Take "+str(target.station.id)+" seat · Trigger"
			if pressed and trigger_ready:trigger_ready=false;take_station(str(target.station.id))
	var grips:bool=tracked and left.get_float("grip")>.65 and right.get_float("grip")>.65
	if not grips:recover_ready=true
	elif recover_ready and not busy and app.inventory.held_item.is_empty() and not app.inventory.is_open:
		for id in scene.decorations:
			var node:MeshInstance3D=scene.decorations[id]
			var row:Dictionary=node.get_meta("native",{})
			if int(row.get("cell_index",0))!=scene.cell_index():continue
			if node.mesh.get_aabb().grow(.1).has_point(node.to_local(left.global_position)) and node.mesh.get_aabb().grow(.1).has_point(node.to_local(right.global_position)):
				recover_ready=false
				recover_item({"item_id":id,"left_hand":scene.source(left.global_position),"right_hand":scene.source(right.global_position)},scene.cell_index());break
func recover_item(payload:Dictionary,cell:int)->void:
	if seated():notice("Leave your seat before recovering items.");return
	var version:int=app.datapad_epoch
	app.inventory.begin_mutation("Recovering item…")
	var walked:=await request("walk",{},true)
	if version!=app.datapad_epoch:return
	if not walked.get("ok",false) or int(ship.get("cell_index",0))!=cell:
		app.inventory.set_busy(false,"Room not confirmed. Touch the item again to retry.");return
	var result:=await request("recover",payload)
	if version!=app.datapad_epoch:return
	app.inventory.set_busy(false,"Item returned to inventory." if result.get("ok",false) else str(result.get("error","Recovery not confirmed. Check inventory before retrying.")))
func try_drop(item:Dictionary,pose:Transform3D)->bool:
	if not aboard():return false
	if seated():app.inventory.finish_item_action(false,"Leave your seat before placing items.");return true
	var placement:Dictionary=app.housing.decoration_pose(pose)
	var actual:Transform3D=placement.pose
	var q:=actual.basis.get_rotation_quaternion()
	app.inventory.set_busy(true,"Placing item in ship…")
	finish_drop({"item_id":str(item.id),"cell_index":scene.cell_index(),"placement_position":scene.source(actual.origin),"local_quaternion":[-q.x,-q.y,q.z,q.w],"suspended":placement.suspended})
	return true
func finish_drop(payload:Dictionary)->void:
	var version:int=app.datapad_epoch
	var walked:Dictionary=await request("walk",{},true)
	if version!=app.datapad_epoch:return
	if not walked.get("ok",false) or scene.cell_index()!=int(ship.get("cell_index",0)):
		app.inventory.finish_item_action(false,str(walked.get("error","Wait until your current room is confirmed before placing an item.")));return
	if int(payload.cell_index)!=int(ship.get("cell_index",0)):
		app.inventory.finish_item_action(false,"Room changed while placing the item. Release it inside your current room.");return
	var response:=await request("decorate",payload)
	if version!=app.datapad_epoch:return
	var success:bool=response.get("ok",false) and response.get("mutation",{}).get("success",false)
	app.inventory.finish_item_action(success,str(response.get("error",response.get("mutation",{}).get("message","Placement was not confirmed. Check inventory before retrying."))))
