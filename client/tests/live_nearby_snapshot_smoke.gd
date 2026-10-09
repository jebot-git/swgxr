extends SceneTree
## Replays saved genuine Core3 data; transport is mocked and no character is connected.
const Live=preload("res://combat/live_world.gd")
const Ambient=preload("res://scripts/ambient_npcs.gd")
const Rig=preload("res://combat/ranged_rig.gd")
class Host extends Node3D:
	var args:Dictionary={}
	var datapad_account:="saved_snapshot_replay"
	var datapad_character_id:=""
	var world_ready:=false
	var xr_requested:=false
	var xr_focused:=false
	var reply:Dictionary={}
	func source_position_at(point:Vector3)->Vector3:return Vector3(point.x+3790,point.y+5,-point.z-4780)
	func api(_method:HTTPClient.Method,_path:String,_payload:Dictionary={})->Dictionary:
		await get_tree().process_frame
		return reply.duplicate(true)
var checks:=0
var errors:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var source_path:="res://../runtime/evidence/live-nearby-asset-preflight.json"
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var host:=Host.new();root.add_child(host);host.datapad_character_id=str(saved.character_id);host.reply=saved.duplicate(true);host.reply.ok=true
	var stage:=Node3D.new();host.add_child(stage);stage.set_meta("manifest",{"origin":[3790,5,-4780]})
	var body:=CharacterBody3D.new();host.add_child(body)
	var head:=Camera3D.new();host.add_child(head);head.position.y=1.7
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.pistol_fwg5.duplicate(true);profile.item_id=str(saved.snapshot.weapon.item_id);profile.source_kind="core3_weapon_instance";profile.certified=true
	var rig:=Rig.new();host.add_child(rig);check(rig.configure(head,body,[profile]),"Actual original FWG5 profile configures with recorded native item identity")
	rig.set_process(false);rig.set_physics_process(false)
	var live:=Live.new();host.add_child(live);live.configure(host,rig,stage,body);live.set_process(false)
	var ambient:=Ambient.new();host.add_child(ambient);ambient.set_process(false);ambient.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json"));live.configure_ambient(ambient)
	check(saved.snapshot.actors.size()==14,"Saved native nearby preflight contains all14 expected actors")
	check(await live.start(Vector3.ZERO,0),"Full saved Core3 snapshot admits every original actor: "+live.last_error)
	check(live.actors.size()==saved.snapshot.actors.size(),"No source actor omitted or replaced by generic geometry")
	check(not live.is_ready() and not live.native_ready,"Saved protected loading snapshot remains disarmed")
	check(ambient.live_suppressed.size()==4,"All four exact duplicates preserve their source visual variant before local suppression")
	var projections:Array=[]
	for value:Dictionary in saved.snapshot.actors:
		var id:=str(value.id)
		if not live.actors.has(id):continue
		var actor=live.actors[id]
		var bounds:AABB=actor.visual_bounds()
		check(actor.record.template==value.template and bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length()>0.01 and bounds.size.length()<40,"Exact bounded source projection: "+value.template)
		var expected:=Vector3(float(value.position[0])-3790,float(value.position[1])-5,-float(value.position[2])-4780)
		check(actor.global_position.is_equal_approx(expected),"Native source position preserved: "+id)
		var record:Dictionary={"id":id,"template":value.template,"kind":value.kind,"source_catalog":actor.report.get("source_catalog",""),"bounds_size":[bounds.size.x,bounds.size.y,bounds.size.z]}
		if value.kind=="creature":
			var avatar=actor.visual
			var outfits:int=avatar.race.get("default_outfit",[]).size()
			var equipment:int=avatar.loaded_parts.filter(func(part):return part.scope=="equipment").size()
			check(avatar.skeleton.get_bone_count()>0 and not avatar.meshes.is_empty() and avatar.meshes.all(func(mesh):return mesh.skin!=null),"Original skin binding retained: "+value.template)
			check(equipment==outfits and avatar.loaded_parts.all(func(part):return not part.model.get("parts",[]).is_empty() and part.model.parts.all(func(source_part):return not source_part.get("mesh",{}).get("surfaces",[]).is_empty())),"Complete source body and CDF outfit parts: "+value.template)
			record.merge({"bones":avatar.skeleton.get_bone_count(),"cdf_outfit_parts":outfits,"loaded_outfit_parts":equipment})
		projections.append(record)
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"snapshot_source":"runtime/evidence/live-nearby-asset-preflight.json","actors":projections,"transport_mocked":true,"source_snapshot_native":true,"gpu_tested":false,"headset_tested":false,"real_http_requests":0}
	FileAccess.open("res://../runtime/evidence/live-nearby-model-replay.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":errors.is_empty(),"checks":checks,"actors":projections.size(),"errors":errors}))
	live.reset("Replay complete");host.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
