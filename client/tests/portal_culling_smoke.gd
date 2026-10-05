extends SceneTree
## Conservative native selection plus actual streamed cantina geometry; Dummy only.
var errors: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); push_error(message)
func polygon(x: float, z: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(x-0.5,0,z),Vector3(x+0.5,0,z),Vector3(x+0.5,2,z),Vector3(x-0.5,2,z)])
func synthetic() -> void:
	var graph := {
		"1:0":{"building_object_id":1,"is_exterior":true,"portals":[{"leads_to":"1:1","world_vertices":polygon(0,0)}]},
		"1:1":{"building_object_id":1,"portals":[{"leads_to":"1:0","world_vertices":polygon(0,0)},{"leads_to":"1:2","world_vertices":polygon(4,-2)}]},
		"1:2":{"building_object_id":1,"portals":[{"leads_to":"1:1","world_vertices":polygon(4,-2)}]}}
	var solver := SwgPortalVisibility.new()
	solver.configure(graph)
	var outside := {"position":Vector3(0,1,5),"cell_id":""}
	var result := solver.solve([outside])
	check(result.complete and result.visible_cells.has("1:1") and not result.visible_cells.has("1:2"),"Native portal cones failed to hide occluded side room")
	result=solver.solve([outside,{"position":Vector3(4,1,-1),"cell_id":"1:1"}])
	check(result.visible_cells.has("1:2"),"Independent second view did not preserve its room")
	result=solver.solve([{"position":Vector3(4,1,-2),"cell_id":"1:1"}])
	check(result.visible_cells.has("1:2"),"Eye exactly on doorway plane hid destination")
	result=solver.solve([outside],0.25,1)
	check(not result.complete and result.visible_cells.size()==3,"Traversal overflow did not fail open")
	result=solver.solve([{"position":Vector3.ZERO,"cell_id":"unknown"}])
	check(result.visible_cells.size()==3,"Unknown view membership did not fail open")
	graph["1:1"].portals.append({"leads_to":"missing","world_vertices":polygon(1,1)})
	solver.configure(graph)
	check(solver.solve([outside]).visible_cells.size()==3,"Incomplete source graph did not fail open")

func run() -> void:
	synthetic()
	var stream=load("res://scripts/world_stream.gd").new()
	stream.render_distance=128.0
	root.add_child(stream)
	var scene: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/mos_eisley/scene.json"))
	var observer:=CharacterBody3D.new()
	root.add_child(observer)
	observer.position=Vector3(-190.798396,-0.894992,22.327722)
	var camera:=Camera3D.new()
	observer.add_child(camera)
	camera.position=Vector3(0,1.7,0)
	camera.make_current()
	check(stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"),scene),"Stream configure failed")
	stream.set_observer(observer)
	var deadline:=Time.get_ticks_msec()+60000
	while not stream.report.get("ready",false) and Time.get_ticks_msec()<deadline: await process_frame
	check(stream.report.get("ready",false),"Actual world did not become ready")
	var stage=stream.cell_owner
	stage.seed_membership_at(observer.position,"1082874:3")
	var support_before: Dictionary=stage.ground_support.sample_support(observer.position,["1082874:3"],0.1,0.1)
	var collision_before: Dictionary=stage.combat_collision.statistics()
	var mask_before:=observer.collision_mask
	var visibility=load("res://scripts/portal_visibility.gd").new()
	root.add_child(visibility)
	visibility.configure(stage,camera)
	visibility.set_process(false)
	visibility.update_views()
	var culled: Dictionary=visibility.report.culling.duplicate(true)
	var doorway_checks:=0
	for id: String in visibility.portal_cells:
		var cell: Dictionary=visibility.portal_cells[id]
		for portal: Dictionary in cell.get("portals",[]):
			var polygon: PackedVector3Array=portal.world_vertices
			if polygon.size()<3: continue
			var center:=Vector3.ZERO
			for point: Vector3 in polygon: center+=point
			center/=polygon.size()
			var door_result: Dictionary=visibility.native_visibility.solve([{"position":center,"cell_id":id}])
			check(door_result.visible_cells.has(id) and door_result.visible_cells.has(str(portal.leads_to)),"Actual doorway culling severed "+id+" -> "+str(portal.leads_to))
			doorway_checks+=1
	check(culled.hidden_instances>0,"Actual cantina view did not cull any resident geometry")
	check(visibility.is_cell_visible("1082874:3"),"Observer's actual cantina room hidden")
	check(visibility.is_cell_visible("missing"),"Unknown cell must remain visible")
	check(visibility.is_cell_visible("1082874:0"),"Exterior shell/exit geometry hidden")
	var hidden_cells:=0
	for id: String in visibility.cell_instances:
		if not visibility.is_cell_visible(id): hidden_cells+=1
	var front:=AABB(camera.global_position+Vector3(-0.2,-0.2,-5),Vector3.ONE*0.4)
	var back:=AABB(camera.global_position+Vector3(-0.2,-0.2,5),Vector3.ONE*0.4)
	check(visibility.is_bounds_visible(front),"Front actor bounds incorrectly culled")
	check(not visibility.is_bounds_visible(back),"Offscreen actor bounds not rejected")
	var spectator:=Camera3D.new()
	root.add_child(spectator)
	spectator.global_position=camera.global_position
	spectator.rotation.y=PI
	visibility.spectator=spectator
	visibility.update_views()
	check(visibility.is_bounds_visible(back),"Spectator union lost actor visible only in mirror")
	visibility.culling_enabled=false
	visibility.update_views()
	check(visibility.report.culling.hidden_instances==0,"Mesh culling toggle did not restore geometry")
	check(hidden_cells>0,"Actual authored cell graph produced no hidden rooms")
	check(visibility.visible_cells.size()<visibility.portal_cells.size(),"Independent animation query stopped computing while mesh culling disabled")
	var support_after: Dictionary=stage.ground_support.sample_support(observer.position,["1082874:3"],0.1,0.1)
	check(support_before.get("valid",false) and support_after==support_before,"Visibility changed floor support")
	check(stage.combat_collision.statistics()==collision_before and observer.collision_mask==mask_before,"Visibility changed gameplay collision")
	var result: Dictionary={"test":"native_actual_portal_culling","passed":errors.is_empty(),"errors":errors,"gpu_tested":false,"headset_tested":false,"actual_cantina":culled,"hidden_cells":hidden_cells,"actual_doorway_checks":doorway_checks,"floor_unchanged":support_after==support_before,"collision_unchanged":stage.combat_collision.statistics()==collision_before}
	FileAccess.open("res://../runtime/evidence/portal-culling-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	visibility.queue_free();spectator.queue_free();stream.queue_free();observer.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
