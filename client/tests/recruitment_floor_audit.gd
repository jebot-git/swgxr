extends SceneTree
## Production streaming/material paths, original Tatooine scene and source X31.
const World=preload("res://scripts/world_stream.gd")
const Terrain=preload("res://scripts/terrain_stream.gd")
const Ambient=preload("res://scripts/ambient_npcs.gd")
const Actor=preload("res://combat/live_actor.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
const SourceFont=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1600,1000)
	RenderingServer.global_shader_parameter_set("swg_environment_tint",Color.WHITE);RenderingServer.global_shader_parameter_set("swg_indoor_tint",Color(.95,.92,.86));RenderingServer.global_shader_parameter_set("swg_daylight",1.0)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("8ba6b4");root.add_child(environment)
	var stream:=World.new();root.add_child(stream);stream.render_distance=256;stream.collision_distance=256
	if not stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json")):push_error("Original world unavailable");quit(1);return
	var center:=Vector3(-114,0,-64)
	var eye:=Camera3D.new();root.add_child(eye);eye.current=true;eye.fov=66;eye.position=center+Vector3(1,2.1,-5);eye.look_at(center+Vector3(0,.8,0));stream.cell_owner.set_observer(eye)
	var ground:=Terrain.new();root.add_child(ground);var origin:Array=stream.manifest.origin
	ground.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),Vector3(origin[0],origin[1],origin[2]));ground.set_cell_source(stream.cell_owner);ground.update_observer(center);stream.update_observer(center)
	var deadline:=Time.get_ticks_msec()+90000
	while not stream.report.get("ready",false) or not ground.ready_near(center,0):
		if Time.get_ticks_msec()>deadline:push_error("Production world stream did not become ready");quit(1);return
		await process_frame
	var placements:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json")))
	var ambient:=Ambient.new();root.add_child(ambient);ambient.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json"),stream.cell_owner,ground)
	var rows:Array=[];var failures:Array=[];var checks:=0
	for entry:Dictionary in placements.instances:
		if str(entry.get("building_object_id","0"))!="1280129":continue
		var point:=Vector3(entry.position[0],entry.position[1],entry.position[2]);eye.position=point+Vector3.UP*1.6;stream.cell_owner.seed_membership_at(point,str(entry.cell_id))
		for i:int in range(4):await physics_frame
		var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.5,point-Vector3.UP*2,1)
		var hit:Dictionary=stream.get_world_3d().direct_space_state.intersect_ray(ray)
		var support:Dictionary=stream.cell_owner.ground_support.sample_support(point,[str(entry.cell_id)],1.5,2,{})
		var projected:Vector3=ambient.grounded_position(entry);checks+=1
		if not support.get("valid",false) or absf(projected.y-float(support.height))>.005:failures.append("Source FLR support mismatch: "+str(entry.id))
		# Deliberate non-floor prop collider above this source floor must not
		# become an NPC support surface as it did with unrestricted prop rays.
		var prop:=StaticBody3D.new();root.add_child(prop);prop.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.5,.2,.5);shape.shape=box;prop.add_child(shape);prop.global_position=point+Vector3.UP
		for i:int in range(2):await physics_frame
		checks+=1
		var prop_hit:Dictionary=stream.get_world_3d().direct_space_state.intersect_ray(ray)
		if prop_hit.is_empty() or Vector3(prop_hit.position).y<=projected.y+.05:failures.append("Injected nonfloor prop was not exercised by legacy ray")
		if not ambient.grounded_position(entry).is_equal_approx(projected):failures.append("Prop displaced original floor grounding")
		prop.queue_free()
		rows.append({"projected_position":projected,"id":entry.id,"template":entry.template,"cell":entry.cell_id,"source_position":point,"ray_position":hit.get("position"),"source_floor":support})
	var seated:Dictionary=placements.instances.filter(func(item):return str(item.get("building_object_id","0"))=="1280129")[0].duplicate(true);seated.mood="npc_sitting_chair";checks+=1
	if not ambient.grounded_position(seated).is_equal_approx(ambient.to_global(ambient.vec(seated.position))):failures.append("Seated source pose moved")
	for entry:Dictionary in placements.instances:
		if str(entry.id)!="tatooine_mos_eisley:gcwMobs:11:2":continue
		checks+=1;var projected:=ambient.grounded_position(entry)
		if absf(projected.y-.52789)>.005:failures.append("Original raised imperial platform not preserved")
	var elevated:Dictionary={"position":[-114.0,20.0,-64.0],"cell_id":"","mood":""};checks+=1
	if not ambient.grounded_position(elevated).is_equal_approx(Vector3(-114,20,-64)):failures.append("Explicit airborne/elevated source placement was reset to terrain")
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"rows":rows,"renderer":"dummy","headset_validated":false}
	print(JSON.stringify(result));FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/npc-floating/recruitment-floor-audit.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "));ambient.queue_free();ground.queue_free();stream.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
