extends SceneTree
const ServiceWorld = preload("res://scripts/service_world.gd")
var checks := 0
var failures: Array = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := ServiceWorld.new()
	root.add_child(world)
	world.configure(Vector3(3618.98388671875,5,-4801.0859375))
	check(world.catalog.get("failures",[]).is_empty(),"Original service extraction has no failures")
	check(world.static_ids.size()>=333,"Original static service terminal catalog remains populated")
	var p := [3618.98388671875,5,-4801.0859375]
	var rows := [{"id":"source_transport","template":"object/mobile/player_transport.iff","position":p,"heading_radians":0.0,"boarding":true},
		{"id":"source_shuttle","template":"object/creature/npc/theme_park/player_shuttle.iff","position":p,"heading_radians":0.0,"boarding":true,"collector_id":"native-collector","collector_position":[3619.0,5,-4802.0]}]
	world.apply_snapshot({"shuttles":rows,"terminals":[{"id":"dynamic_travel","kind":"travel","position":p},
		{"id":"existing_trainer","kind":"trainer","position":p,"template":"object/tangible/terminal/terminal_travel.iff"}]},Vector3.ZERO)
	await process_frame
	check(world.shuttles.size()==2,"Both original shuttle variants instantiate")
	check(world.terminals.size()==2,"Dynamic original travel and native ticket-collector terminals render")
	var collectors:=ServiceWorld.collector_records({"shuttles":rows})
	check(collectors.size()==1 and collectors[0].shuttle_id=="source_shuttle" and collectors[0].position==rows[1].collector_position,"Boarding terminal uses native collector identity and position")
	check(not world.terminal_pick_geometry(collectors[0]).is_empty(),"Boarding terminal supports whole original mesh picking")
	check(not world.terminals.has("existing_trainer"),"Trainer service discovery never duplicates an existing NPC")
	check(world.errors.is_empty(),"CDF HOBJ attachments instantiate without missing models/bones")
	var transport: Dictionary = world.shuttles.source_transport
	check(transport.actor.rigid_equipment.size()==5,"Transport hull, three struts and door all attached")
	check(transport.actor.visual_root.transform==Transform3D.IDENTITY,"Preserve source origin without humanoid grounding")
	check(world.shuttles.source_shuttle.actor.rigid_equipment.size()==1,"Shuttle hull attached to source root")
	var door_index: int = transport.actor.skeleton.find_bone("hold_transport_door")
	check(door_index>=0,"Original transport door bone")
	var ground: Transform3D = transport.actor.skeleton.get_bone_global_pose(door_index)
	var boarding := world.boarding_rows()
	check(boarding.size()==2,"Both native boarding records enriched")
	check(boarding[0].door_source=="hold_transport_door","Transport entry tracks original door")
	rows[0].boarding=false
	rows[0]["state"]="away"
	world.apply_snapshot({"shuttles":rows},Vector3.ZERO)
	world.advance(0.1)
	var sky: Transform3D = transport.actor.skeleton.get_bone_global_pose(door_index)
	check(not sky.is_equal_approx(ground),"Door source pose differs in flight/ground")
	check(world.boarding_rows().size()==1,"Closed/away shuttle cannot board")
	world.advance(6.0)
	check(world.boarding_rows().is_empty(),"Stale native schedule cannot board")
	check(world.phase_for({})=="","Presence alone does not imply landed")
	rows[0]["is_landing"]=true
	rows[0]["landing_duration_seconds"]=14.0
	rows[0]["phase_elapsed_seconds"]=7.0
	world.apply_snapshot({"shuttles":rows},Vector3.ZERO)
	check(is_equal_approx(float(transport.time),float(transport.source.clips.land.length)*0.5),"Original landing clip normalized to native landing phase")
	check(world.boarding_rows().size()==1,"Landing animation does not authorize boarding")
	var keys := [[0.0,1.0],[2.0,3.0],[4.0,5.0]]
	check(is_equal_approx(world.neighbors(keys,3.0)[2],0.5),"Original clip interpolation")
	check(world.source_position(world.local_position(Vector3(20,9,-40)))==[20.0,9.0,-40.0],"Source/Godot mirrored conversion round trip")
	world.apply_snapshot({"shuttles":rows},Vector3(1000,0,1000))
	check(world.shuttles.is_empty(),"Bounded 128m source model culling")
	var report := {"checks":checks,"failures":failures,"ground_door_pose":str(ground),"flight_door_pose":str(sky),"boarding":boarding,"validation":"Dummy renderer and mocked native rows; no live VR validation"}
	var f:=FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/service-world-smoke.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
