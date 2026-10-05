extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var Host = load("res://scripts/main.gd")
	var app: Node3D = Host.new()
	root.add_child(app)
	var deadline := Time.get_ticks_msec() + 90000
	while not app.world_ready and Time.get_ticks_msec() < deadline: await process_frame
	var report: Dictionary = {"world_ready":app.world_ready,"points":[],"gpu_tested":false}
	if app.world_ready:
		await physics_frame
		await physics_frame
		var space: PhysicsDirectSpaceState3D = app.get_world_3d().direct_space_state
		for x in [3770.0,3790.0,3810.0,3830.0]:
			var point: Vector3 = app.terrain.terrain_position(Vector2(x,-4780))
			var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*8,point-Vector3.UP*5,7)
			query.exclude = [app.player.get_rid()]
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty(): point.y = hit.position.y
			var clear := true
			for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
				var side_query := PhysicsRayQueryParameters3D.create(point+Vector3.UP,point+Vector3.UP+direction*3,7)
				side_query.exclude = [app.player.get_rid()]
				var obstruction: Dictionary = space.intersect_ray(side_query)
				clear = clear and obstruction.is_empty()
			report.points.append({"source":[x,app.source_position_at(point).y,-4780],"terrain_y":point.y,"hit_y":hit.get("position",Vector3(0,NAN,0)).y,"clear_3m":clear,"collider":str(hit.get("collider",""))})
		var a: Vector3 = app.terrain.terrain_position(Vector2(3790,-4780))-Vector3.UP*0.5
		var b: Vector3 = app.terrain.terrain_position(Vector2(3810,-4780))-Vector3.UP*1.5
		var sight_query := PhysicsRayQueryParameters3D.create(a,b,7)
		sight_query.exclude = [app.player.get_rid()]
		report["line_clear"] = space.intersect_ray(sight_query).is_empty()
	report["passed"] = report.world_ready and bool(report.get("line_clear",false)) and report.points.size()==4
	for point: Dictionary in report.points:
		report.passed = report.passed and point.clear_3m and is_finite(float(point.source[1])) and absf(float(point.source[1])-5.0)<0.15
	print(JSON.stringify(report))
	FileAccess.open("res://../runtime/evidence/live-site-ground.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	app.queue_free(); await process_frame; quit(0 if report.passed else 1)
