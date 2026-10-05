extends SceneTree
## Original stage/streamed collisions and production main.ground_xr_spawn.
## Saved-location records are synthetic; no server session or live XR is used.
class Host extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
var errors:Array[String]=[]
var rows:Array=[]
func check(ok:bool,message:String)->void:
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host)
	host.stage=host.loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"));host.add_child(host.stage)
	var rig:Node3D=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig)
	host.player=rig.get_node("PlayerBody");host.player.active=false;host.player.set_physics_process(false);host.player.ground_provider=host.stage
	rig.get_node("XRCamera3D").position=Vector3(0,1.7,0)
	host.stage.set_observer(host.player)
	host.world_stream=preload("res://scripts/world_stream.gd").new();host.add_child(host.world_stream);host.world_stream.render_distance=128
	check(host.world_stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"),host.stage),"Original world stream configures")
	host.terrain=preload("res://scripts/terrain_stream.gd").new();host.add_child(host.terrain)
	var origin:Vector3=host.loader.vec(host.loader.report.origin)
	check(host.terrain.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),origin),"Original terrain configures")
	host.terrain.set_cell_source(host.stage)
	var locations:Array=[
		{"name":"source starport foyer4","zone":"tatooine","position":[origin.x-60,origin.y+2,origin.z-10.125],"building_id":"1106368","cell_index":4,"heading_radians":1.2},
		{"name":"source cantina floor triangle92 below terrain","zone":"tatooine","position":[origin.x-190.798396,origin.y-.894992,origin.z-22.327722],"building_id":"1082874","cell_index":3,"heading_radians":.9},
		{"name":"source Mos Eisley starport exterior","zone":"tatooine","position":[3599.894,7,-4780.4487],"building_id":"0","cell_index":0,"heading_radians":-.6}]
	for location:Dictionary in locations:
		check(host.medical_placement.destination_valid(location),"Saved fixture has valid original source location")
		var p:Array=location.position
		var target:Vector3=host.stage.to_global(Vector3(float(p[0])-origin.x,float(p[1])-origin.y,-(float(p[2])-origin.z)))
		host.player.spawn_point=target;host.player.spawn_yaw=-float(location.heading_radians);host.player.reset_spawn()
		host.terrain.update_observer(host.player.global_position);host.world_stream.update_observer(host.player.global_position)
		var deadline:=Time.get_ticks_msec()+90000
		while (not host.terrain.ready_near(target) or not host.world_stream.report.get("ready",false)) and Time.get_ticks_msec()<deadline:await process_frame
		check(host.terrain.ready_near(target) and host.world_stream.report.get("ready",false),"Saved region finishes original terrain/building streaming")
		host.player.prepare_tracked_body()
		var cell:String=host.medical_placement.source_cell(location)
		check(cell.is_empty() or host.stage.definitions.has(cell),"Saved interior identity resolves authored cell")
		host.stage.seed_membership_at(host.player.global_position,cell if not cell.is_empty() else "exterior")
		await physics_frame;await physics_frame
		check(host.ground_xr_spawn(),"Production tracked capsule grounds saved location: "+location.name)
		host.stage.update_cell()
		var saved_source:Vector3=host.source_position_at(host.player.global_position)
		var first:Vector3=host.player.global_position
		if cell=="1082874:3":check(absf(first.y+.894992)<.025 and host.player.collision_mask&2==0,"Saved cantina floor stays below exterior terrain and excludes terrain collision")
		check(absf(saved_source.x-float(p[0]))<.25 and absf(saved_source.z-float(p[2]))<.25,"Grounding stays inside the saved capsule footprint")
		check(absf(host.player.rotation.y+float(location.heading_radians))<.01,"Resume uses original source yaw handedness")
		check(not cell.is_empty() and str(host.stage.current_cell.get("cell_id",""))==cell or cell.is_empty() and str(host.stage.current_cell.get("cell_id","")) in ["","exterior"],"Authored membership remains saved room or exterior after grounding")
		# Simulate a second login using the actual grounded source location, not a
		# convenient raised start: a capsule already on its floor must stay there.
		host.player.apply_world_correction(Vector3(20,0,20))
		host.player.spawn_point=first;host.player.reset_spawn();host.player.prepare_tracked_body()
		host.stage.seed_membership_at(first,cell if not cell.is_empty() else "exterior")
		await physics_frame;await physics_frame
		check(host.ground_xr_spawn() and host.player.global_position.distance_to(first)<.025,"Exact saved floor resumes without slow falling or storey jump")
		rows.append({"name":location.name,"source_position":[saved_source.x,saved_source.y,saved_source.z],"cell":host.stage.current_cell.get("cell_id",""),"collision_mask":host.player.collision_mask,"repeat_drift":host.player.global_position.distance_to(first)})
		print(JSON.stringify(rows.back()))
	var report:Dictionary={"passed":errors.is_empty(),"errors":errors,"locations":rows,"original_geometry":true,"production_grounding":true,"server_mutated":false,"live_xr":false,"renderer":"dummy"}
	FileAccess.open("res://../runtime/evidence/saved-spawn-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	host.queue_free();await process_frame;await process_frame;quit(0 if errors.is_empty() else 1)
