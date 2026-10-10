extends RefCounted
## Explicit Core3 movement rejection, never ordinary height/pose replication.
static func stamp_request(body:Dictionary,player_state:Dictionary)->Dictionary:
	var revision:Variant=player_state.get("locomotion",{}).get("movement_revision")
	if body.has("movement_revision") or not (revision is int or revision is float) or not is_finite(float(revision)) or float(revision)<0 or float(revision)!=floorf(float(revision)) or float(revision)>9007199254740991.0:return body
	var stamped:=body.duplicate(true);stamped.movement_revision=int(revision);return stamped

static func annotate(snapshot:Dictionary,response:Dictionary)->Dictionary:
	var result:=snapshot.duplicate(true)
	var mutation:Dictionary=response.get("mutation",{})
	var reason:=str(mutation.get("error_code",response.get("error_code","")))
	if mutation.get("movement_accepted",true)==false and not reason.is_empty():
		result["movement_rejected"]={"reason":reason,"sequence":int(response.get("sequence",-1)),"session_id":str(response.get("session_id","")),"character_id":str(response.get("character_id",snapshot.get("id","")))}
	return result

static func apply(app:Node,snapshot:Dictionary)->bool:
	if not snapshot.get("movement_rejected") is Dictionary:return false
	if str(snapshot.get("zone",""))!=str(app.active_planet):return false
	if not preload("res://combat/live_transport.gd").new().destination_valid(snapshot):return false
	var player:CharacterBody3D=app.player
	var stage:Node3D=app.stage
	if not is_instance_valid(player) or not is_instance_valid(stage):return false
	var correction:Dictionary=snapshot.movement_rejected
	var previous:Dictionary=player.get_meta("swgxr_movement_correction",{})
	if previous.get("session_id") == correction.get("session_id") and previous.get("character_id") == correction.get("character_id") and int(previous.get("sequence",-1))>=int(correction.get("sequence",-1)):return false
	var origin:Array=stage.get_meta("manifest",{}).get("origin",[0,0,0])
	var p:Array=snapshot.position
	var target:=stage.to_global(Vector3(float(p[0])-float(origin[0]),float(p[1])-float(origin[1]),float(origin[2])-float(p[2])))
	var cell:=preload("res://combat/live_transport.gd").new().source_cell(snapshot)
	stage.seed_membership_at(target,cell if not cell.is_empty() else "exterior")
	# Core3's continuous terrain evaluator and the client tile triangles need
	# not have identical Y. Restore authoritative horizontal/cell position while
	# retaining the original client's resident support selection for elevation.
	if player.has_method("_source_support"):
		# A rejection is a horizontal rollback, not permission to climb onto
		# an overhead landing pad or roof. Search around the current feet with
		# normal step tolerance; the old +/-8m query chose the highest storey.
		var foot_probe:=Vector3(target.x,player.global_position.y,target.z)
		var support:Dictionary=player._source_support(foot_probe,.35,.6)
		if support.get("valid",false):target.y=float(support.get("body_height",support.height))
	if player.has_method("apply_world_correction"):player.apply_world_correction(target-player.global_position)
	else:player.global_position=target
	player.velocity=Vector3.ZERO
	stage.seed_membership_at(target,cell if not cell.is_empty() else "exterior")
	player.set_meta("swgxr_movement_correction",correction.duplicate(true))
	var session:Variant=app.get("gameplay_session")
	if is_instance_valid(session) and session.has_method("movement_corrected"):session.movement_corrected()
	for key in ["gameplay_combat","live_combat"]:
		var combat:Variant=app.get(key)
		if is_instance_valid(combat) and combat.has_method("discard_movement_commands"):combat.discard_movement_commands()
	return true
