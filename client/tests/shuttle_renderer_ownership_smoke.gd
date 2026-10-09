extends SceneTree
## Replay native Bestine identities through both generic and original service renderers.
const World=preload("res://scripts/service_world.gd")
const Fixture=preload("res://tests/live_combat_smoke.gd")
class Host extends Fixture.Host:
	var services:Node3D
	var stage:Node3D
	var ambient_npcs:Node3D
	var terrain:Node3D
	var multiplayer_sync:Node
class Services extends Node3D:
	var scenery:Node3D
class Stage extends Node3D:
	var current_cell:Dictionary={}
class Sync extends Node:
	var scenery:Node3D
	func world(point:Array)->Vector3:return scenery.local_position(Vector3(point[0],point[1],point[2]))
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var discovery:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/bestine-services-native.json"))
	var native:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/bestine-appearance-native.json"))
	var shuttle:Dictionary=discovery.state.shuttles[0]
	var rows:Array=native.snapshot.world.actors.filter(func(row):return str(row.id)==str(shuttle.id))
	check(rows.size()==1,"Recorded native services and world actor share exact Bestine shuttle ID")
	if rows.size()!=1:quit(1);return
	var row:Dictionary=rows[0];var p:Array=native.location.position
	var host:=Host.new();root.add_child(host);host.stage=Stage.new();host.add_child(host.stage);host.stage.set_meta("manifest",{"origin":p})
	host.services=Services.new();host.add_child(host.services);host.services.scenery=World.new();host.services.add_child(host.services.scenery);host.services.scenery.configure(Vector3(p[0],p[1],p[2]))
	var body:=CharacterBody3D.new();host.add_child(body);var head:=Camera3D.new();body.add_child(head)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"));var profile:Dictionary=catalog.weapons.pistol_fwg5.duplicate(true);profile.item_id="987";profile.source_kind="core3_weapon_instance";profile.certified=true
	var rig:=Fixture.Rig.new();host.add_child(rig);rig.configure(head,body,[profile]);rig.set_process(false);rig.set_physics_process(false)
	var live:=Fixture.Live.new();host.add_child(live);live.configure(host,rig,host.stage,body);live.set_process(false)
	host.reply={"ok":true,"backend":"core3","source_kind":"core3_live_combat","character_id":"123","session_id":"fixture","sequence":1,"session_live":true,"snapshot":{"ready":true,"full":true,"truncated":false,"actors":[row],"player":{"ham":[900,900,900],"max_ham":[1000,1000,1000],"wounds":[0,0,0],"posture":0,"dead":false,"incapacitated":false,"shock_wounds":0},"weapon":{"item_id":"987","certified":true,"fire_interval_seconds":.2,"max_range_m":64,"projectile_speed":100}}}
	check(await live.start(Vector3.ZERO,0) and live.appearance_report.unavailable==1,"Before service art ownership, exact native shuttle exposes original generic-renderer warning")
	host.services.scenery.apply_snapshot(discovery.state,Vector3.ZERO)
	check(host.services.scenery.errors.is_empty() and host.services.scenery.shuttles[str(shuttle.id)].actor.rigid_equipment.size()==5,"Actual native shuttle renders all five original CDF hull/door/strut attachments")
	check(World.presents_actor(host,row),"Successful source service renderer claims exact native shuttle identity")
	host.reply.sequence=2
	check(live.accept_response(host.reply) and not live.actors.has(str(row.id)) and live.appearance_report.unavailable==0 and live.appearance_report.notice.is_empty(),"Live creature renderer delegates service shuttle and clears duplicate missing-art warning")
	var flying:Dictionary=discovery.state.duplicate(true)
	flying.shuttles[0].boarding=false;flying.shuttles[0].landed=false;flying.shuttles[0].is_landing=false
	host.services.scenery.apply_snapshot(flying,Vector3.ZERO)
	check(World.presents_actor(host,row) and host.services.scenery.shuttles[str(shuttle.id)].phase=="take_off","Native departure retains service ownership during original takeoff clip")
	host.services.scenery.advance(100);host.services.scenery.apply_snapshot(flying,Vector3.ZERO)
	check(World.presents_actor(host,row) and host.services.scenery.shuttles[str(shuttle.id)].phase=="loop_sky","Native away phase retains service ownership while ship is out of view")
	host.services.scenery.shuttles[str(shuttle.id)].actor.visible=false
	live.accept_response(host.reply)
	check(not live.actors.has(str(row.id)) and live.appearance_report.unavailable==0,"Intentionally hidden service shuttle never falls back to generic creature rendering")
	host.services.scenery.apply_snapshot(discovery.state,Vector3.ZERO)
	var missing:=row.duplicate(true);missing.id="998877";missing.template="object/mobile/unavailable_fixture.iff"
	host.reply.sequence=3;host.reply.snapshot.actors.append(missing);live.accept_response(host.reply)
	check(live.appearance_report.unavailable==1 and str(live.appearance_report.actor_errors[0].id)==missing.id,"Unrelated genuinely missing appearance still reports exact unavailable entity")
	var mismatch:=row.duplicate(true);mismatch.id="12345"
	check(not World.presents_actor(host,mismatch),"Matching shuttle template with another native ID is never hidden")
	mismatch=row.duplicate(true);mismatch.template=missing.template
	check(not World.presents_actor(host,mismatch),"Matching native ID with another template is never hidden")
	host.services.scenery.shuttles[str(shuttle.id)].complete=false
	check(not World.presents_actor(host,row),"Incomplete original service attachment load cannot suppress warning")
	host.services.scenery.shuttles[str(shuttle.id)].complete=true
	host.multiplayer_sync=Sync.new();host.add_child(host.multiplayer_sync);host.multiplayer_sync.scenery=host.services.scenery
	var entities:=preload("res://multiplayer/world_entities.gd").new();host.add_child(entities);entities.setup(host);entities.set_process(false);entities.accept([row,missing],"fixture",1);entities._process(0)
	check(not entities.actors.has(str(row.id)) and entities.actors.has(missing.id),"Ordinary multiplayer renderer also delegates shuttle while preserving unknown identity")
	host.services.scenery.apply_snapshot({},Vector3.ZERO);entities._process(0)
	check(entities.actors.has(str(row.id)),"Service removal restores generic identity without waiting for a changed world revision")
	host.services.scenery.apply_snapshot(discovery.state,Vector3.ZERO);entities._process(0)
	check(not entities.actors.has(str(row.id)) and host.services.scenery.shuttles.has(str(row.id)),"Late service ownership removes ordinary duplicate without changed world revision")
	host.services.scenery.apply_snapshot({},Vector3.ZERO);host.reply.sequence=4;live.accept_response(host.reply)
	check(live.appearance_report.unavailable==2,"Live renderer also restores diagnostics if service renderer no longer owns shuttle")
	host.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"rows":"recorded native Bestine world and services","assets":"original service shuttle","renderer":"dummy","headset_validated":false}));quit(0 if errors.is_empty() else 1)
