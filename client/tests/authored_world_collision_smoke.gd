extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var assets := "res://../runtime/assets_review" if "--review-assets" in OS.get_cmdline_user_args() else "res://../runtime/assets"
	var loader=load("res://scripts/stage_loader.gd").new()
	var stage=loader.load_stage(ProjectSettings.globalize_path(assets.path_join("mos_eisley/scene.json")))
	assert(stage!=null,loader.report.error)
	root.add_child(stage)
	var stream=load("res://scripts/world_stream.gd").new()
	stream.render_distance=128
	stream.collision_distance=192
	root.add_child(stream)
	assert(stream.configure(ProjectSettings.globalize_path(assets.path_join("tatooine_world/world.json")),stage))
	var body:=CharacterBody3D.new()
	var shape:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.height=1.7;capsule.radius=.25
	shape.shape=capsule;shape.position.y=.85
	body.add_child(shape)
	root.add_child(body)
	body.position=Vector3(-246.63273,.861283,38.20935)
	stage.set_observer(body)
	stream.update_observer(body.position)
	var timeout:=Time.get_ticks_msec()+60000
	while not stream.report.get("ready",false):
		assert(Time.get_ticks_msec()<timeout,"Review world failed readiness")
		await process_frame
	for i in range(3):await physics_frame
	stage.seed_membership_at(body.position)
	for i in range(3):await physics_frame
	assert(stage.current_cell.is_empty() and body.collision_mask==7)
	var context:Dictionary=stage.collision_context(body.position)
	var floor:Dictionary=stage.ground_support.sample_support(body.position,context.allowed_cell_ids,.2,.3)
	assert(floor.get("valid",false),str(context))
	assert(floor.cell_id=="1281533:0" and absf(floor.height-.861283)<.02,str(floor))
	var query:=PhysicsRayQueryParameters3D.create(Vector3(-246.63273,1.3,38.20935),Vector3(-246.63273,-4,38.20935),4,[body.get_rid()])
	var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
	assert(not hit.is_empty() and absf(hit.position.y-floor.height)<.002,str(hit))
	var above:=body.global_transform
	above.origin.y=1.5
	var sweep:=KinematicCollision3D.new()
	assert(body.test_move(above,Vector3.DOWN,sweep))
	assert(above.origin.y+sweep.get_travel().y>.8,"Exterior source stair lost collision")
	var source_null: StaticBody3D =loader.make_collision_body({"collision_id":"test"},{"test":{"status":"null","fallback":"none","extent":{"type":"null"}}},BoxShape3D.new())
	assert(source_null==null,"Authored NULL incorrectly made visual collider")
	# Interior source floor bootstraps intentionally, independent of high spawn.
	stage.seed_membership_at(Vector3(-60,.64,10),"1106368:4")
	assert(stage.current_cell.get("cell_id","")=="1106368:4")
	var report:Dictionary={"test":"authored_world_house_exit_collision","passed":true,"source_stair_height":floor.height,"physical_floor_height":hit.position.y,"exterior_terrain_mask_retained":true,"source_null_no_visual_collision":true,"regions_published_after_geometry":stream.chunks.values().all(func(chunk):return chunk.published),"retained_stage_authored_extents":loader.report.authored_extent_bodies,"retained_stage_visual_fallbacks":loader.report.visual_collision_fallbacks,"world_instances":stream.report.instances}
	print(JSON.stringify(report))
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/authored-world-collision-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	body.queue_free();stream.queue_free();stage.queue_free()
	await process_frame
	quit()
