extends Node
## Separate bounded presentation channel. It does not spend native command
## capacity, upload inventory, or accept client-owned RPG state.
const State=preload("res://multiplayer/replication_state.gd")
const HandInput=preload("res://scripts/tracked_hand_input.gd")
const INTERVAL:=0.1
const STALE_MS:=2500
var app:Node
var state:=State.new()
var players:Node3D
var entities:Node3D
var chatter:Node3D
var generation:=0
var owner_character:=""
var owner_session:=""
var busy:=false
var priming:=false
## An owned start may reattach a surviving native session after a client crash.
## Epoch microseconds fit exactly below JSON's 2^53 bound until year 2255.
var request_sequence:=int(Time.get_unix_time_from_system()*1000000.0)
var clock:=0.0
var confirmed_ms:=0
var last_error:=""
var requests:=0
var accepted:=0
func setup(host:Node)->void:
	app=host
	players=preload("res://multiplayer/remote_players.gd").new();app.add_child(players);players.configure()
	if players.has_method("configure_world"):players.configure_world(app)
	entities=preload("res://multiplayer/world_entities.gd").new();app.add_child(entities);entities.setup(app)
	chatter=preload("res://chatter/controller.gd").new();app.add_child(chatter);chatter.setup(app)
func reset()->void:
	generation+=1;owner_character="";owner_session="";busy=false;priming=false;clock=0;confirmed_ms=0;last_error="";state.reset()
	if is_instance_valid(players):players.clear()
	if is_instance_valid(entities):entities.clear()
	if is_instance_valid(chatter):chatter.clear()
func prime()->bool:
	var session:=active_session()
	if not is_instance_valid(session):return false
	priming=true;owner_session=session.session_id;owner_character=app.datapad_character_id
	await poll()
	var deadline:=Time.get_ticks_msec()+5000
	while confirmed_ms>0 and Time.get_ticks_msec()<deadline and (not players.pending.is_empty() or entities.actors.size()<entities.desired.size()):
		# Keep complete world data alive while original appearances warm behind
		# the loading cover; later arrivals still use the bounded worker queue.
		players.snapshot_age=0
		await get_tree().process_frame
	if confirmed_ms>0 and Time.get_ticks_msec()-confirmed_ms>500:await poll()
	return confirmed_ms>0
func active_session()->Node:
	for key in ["live_combat","gameplay_session"]:
		var session:Variant=app.get(key)
		if is_instance_valid(session) and session.live:return session
	return null
func identity()->Dictionary:
	var p:Vector3=app.source_position_at(app.player.global_position)
	var cell:Dictionary=app.stage.current_cell
	var heading:float=-app.player.global_rotation.y
	var tracked_avatar:Variant=app.get("tracked_avatar")
	if is_instance_valid(tracked_avatar):heading=-tracked_avatar.global_rotation.y
	return {"account":app.datapad_account,"character_id":owner_character,"session_id":owner_session,
		"zone":preload("res://scripts/planet_catalog.gd").current(app),"sequence":request_sequence,"world_revision":state.world_revision,"event_sequence":state.event_sequence,"position":[p.x,p.y,p.z],"heading_radians":heading,
		"building_id":str(cell.get("building_object_id","0")),"cell_index":int(str(cell.get("cell_id","0:0")).get_slice(":",1)),"tracking":tracking(),"physical_posture":physical_posture()}
func physical_posture()->int:
	var avatar:Variant=app.get("tracked_avatar")
	if not app.xr_requested or not app.xr_focused or not is_instance_valid(avatar):return 0
	var posture:String=str(avatar.body_motion.posture.state)
	return 2 if posture=="prone" else 1 if posture=="crouched" else 0
func tracking()->Dictionary:
	var result:Dictionary={}
	# Keep the established source skeleton offsets, but local spice hand effects
	# must never enter peer presentation. Tracking loss clears targets immediately.
	if not app.xr_requested or not app.xr_focused or not is_instance_valid(app.tracked_avatar):return result
	var skeleton:Skeleton3D=app.tracked_avatar.skeleton
	if not is_instance_valid(skeleton):return result
	var physical_only:=false
	var body:Variant=app.get("player")
	if is_instance_valid(body):
		var feedback:Variant=body.get("feedback")
		if feedback!=null:
			var policy:Dictionary=feedback.spice.policy()
			physical_only=policy.tremor>0 or policy.sticky_aim or policy.lag_seconds>0
	for pair in [["head","head"],["left_hand","lwrist"],["right_hand","rwrist"]]:
		var tracked:=false
		if pair[0]=="head":
			var tracker=XRServer.get_tracker("head")
			var pose:XRPose=tracker.get_pose("default") if tracker!=null else null
			tracked=pose!=null and pose.has_tracking_data
		else:
			var controller:=app.xr_origin.get_node_or_null("LeftHand" if pair[0]=="left_hand" else "RightHand") as XRController3D
			tracked=controller!=null and HandInput.controller_tracked(controller)
		var index:=skeleton.find_bone(pair[1])
		if not tracked or index<0:continue
		var pose:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(index)
		if physical_only:
			if pair[0]=="head":
				pose=app.tracked_avatar.camera.global_transform
				pose.basis=pose.basis.orthonormalized()*app.tracked_avatar.head_rest.basis
			else:
				var side:="left" if pair[0]=="left_hand" else "right"
				pose=app.xr_origin.get_node(side.capitalize()+"Hand").global_transform*app.tracked_avatar.grip_offsets[side]
		var p:Vector3=app.source_position_at(pose.origin)
		result[pair[0]]={"tracked":true,"position":[p.x,p.y,p.z],"rotation":State.source_rotation(pose.basis,app.stage.global_basis)}
	return result
func world(value:Array)->Vector3:
	var origin:Vector3=app.loader.vec(app.loader.report.get("origin",[0,0,0]))
	var p:Vector3=State.point(value)-origin
	return app.stage.to_global(Vector3(p.x,p.y,-p.z))
func normalized_players()->Array:
	var rows:Array=[]
	for value:Dictionary in state.players:
		var row:=value.duplicate(true)
		row.position=world(value.position)
		row.heading_radians=(app.stage.global_basis*Basis(Vector3.UP,-float(value.heading_radians))).get_euler().y
		row.tracking={}
		for key in value.tracking:
			var target:Dictionary=value.tracking[key]
			row.tracking[key]=Transform3D(State.world_rotation(target.rotation,app.stage.global_basis),world(target.position))
		rows.append(row)
	return rows
func apply_response(result:Dictionary,sent_sequence:int)->bool:
	var zone:=preload("res://scripts/planet_catalog.gd").current(app)
	if str(result.get("zone",zone))!=zone or (result.get("world") is Dictionary and str(result.world.get("zone",zone))!=zone):last_error="Discarded multiplayer world from previous planet.";return false
	if not state.accept(result,owner_character,owner_session,sent_sequence):last_error=state.error;return false
	accepted+=1;confirmed_ms=Time.get_ticks_msec();last_error=""
	var status:Variant=app.get("asset_status")
	if is_instance_valid(status) and str(status.text).begins_with("Multiplayer world sync interrupted:"):status.text="Persistent Core3 session · multiplayer world sync restored."
	var cell:Dictionary=app.stage.current_cell
	var cell_id:=str(cell.get("native_cell_id",cell.get("cell_id","0")))
	# The manager normalizes source cell IDs; the player membership below uses
	# native building/index to avoid comparing native object IDs with scene keys.
	var rows:=normalized_players()
	for row:Dictionary in rows:row.cell_id=str(row.get("building_id","0"))+":"+str(row.get("cell_index",0))
	cell_id=str(cell.get("building_object_id","0"))+":"+str(int(str(cell.get("cell_id","0:0")).get_slice(":",1)))
	players.apply_snapshot(rows,owner_character,app.player.global_position,cell_id,true)
	var events:Array=[]
	for value:Dictionary in state.events:
		if str(value.get("actor_id",""))==owner_character:continue
		var event:=value.duplicate(true)
		event.position=world(value.position)
		if State.finite_point(value.get("origin")):event.origin=world(value.origin)
		if State.finite_point(value.get("direction")):
			var source_direction:=State.point(value.direction)
			event.direction=app.stage.global_basis*Vector3(source_direction.x,source_direction.y,-source_direction.z)
		events.append(event)
	if players.has_method("consume_events"):players.consume_events(events)
	if players.has_method("apply_deployments"):
		var deployments:Array=[]
		for value:Dictionary in state.native_world.get("deployments",[]):
			var deployment:=value.duplicate(true);deployment.position=world(value.position);deployments.append(deployment)
		players.apply_deployments(deployments,owner_character,app.player.global_position)
	if not app.live_combat_reserved:entities.accept(state.actors,owner_session,state.world_revision)
	if is_instance_valid(chatter):chatter.accept(result.get("npc_speech"))
	return true
func _process(delta:float)->void:
	if not is_instance_valid(app):return
	if is_instance_valid(app.get("space")) and app.space.aboard():
		if not owner_session.is_empty():reset()
		return
	if priming:
		if not app.world_ready:return
		priming=false
	var session:=active_session()
	if app.session_leaving or not app.world_ready or app.loading_stage or not is_instance_valid(session):
		if not owner_session.is_empty():reset()
		return
	if owner_session!=session.session_id or owner_character!=app.datapad_character_id:
		reset();owner_session=session.session_id;owner_character=app.datapad_character_id
	clock-=delta
	if confirmed_ms>0 and Time.get_ticks_msec()-confirmed_ms>STALE_MS:
		players.clear();entities.clear();confirmed_ms=0
		if is_instance_valid(chatter):chatter.clear()
		var status:Variant=app.get("asset_status")
		if is_instance_valid(status):status.text="Multiplayer world sync interrupted: "+last_error
	if not busy and clock<=0:poll()
func poll()->void:
	busy=true;clock=INTERVAL;request_sequence+=1;requests+=1
	var epoch:=generation
	var sequence:=request_sequence
	var result:Dictionary=await app.api(HTTPClient.METHOD_POST,"/session/sync",identity())
	if epoch!=generation:return
	busy=false
	if not apply_response(result,sequence):clock=maxf(clock,.3)
func statistics()->Dictionary:
	return {"requests":requests,"accepted":accepted,"busy":busy,"world_revision":state.world_revision,"event_sequence":state.event_sequence,"native_players":state.players.size(),"native_actors":state.actors.size(),"last_error":last_error,"snapshot_age_ms":Time.get_ticks_msec()-confirmed_ms if confirmed_ms>0 else -1,"visuals":players.report.duplicate(true) if is_instance_valid(players) else {},"npc_speech":chatter.statistics() if is_instance_valid(chatter) else {}}
func _exit_tree()->void:
	if is_instance_valid(players):players.queue_free()
	if is_instance_valid(entities):entities.queue_free()
	if is_instance_valid(chatter):chatter.queue_free()
