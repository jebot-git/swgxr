extends SceneTree
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	assert(value,label)
func body_at(point:Vector3)->CharacterBody3D:
	var body:=CharacterBody3D.new();body.collision_mask=7
	var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new()
	capsule.radius=.25;capsule.height=1.7;shape.shape=capsule;shape.position.y=.85
	body.add_child(shape);root.add_child(body);body.position=point
	return body
func run()->void:
	var source:Dictionary={"fractals":[],"source_chunk_size":8,"source_tiles_per_chunk":2,"layers":[{"enabled":true,"boundaries":[{"type":"BREC","enabled":true,"rect":[4,0,7.9,7.9]}],"affectors":[{"type":"APAS","enabled":true,"passable":false,"feather_threshold":.5}]}]}
	var evaluator:=SwgTerrainEvaluator.new();check(evaluator.configure(source),"configure APAS")
	check(evaluator.movement_sample(3.99,2).passable,"adjacent tile blocked")
	check(not evaluator.movement_sample(7.99,2).passable,"source whole-tile impassability missing")
	check(evaluator.movement_sample(8,2).passable,"next tile blocked")
	check(not evaluator.movement_sample(8192,0).passable,"map edge bypass")
	var body:=body_at(Vector3(1,.001,-1));var solver:=SwgXRStepSolver.new()
	solver.configure_terrain(evaluator,Vector3.ZERO,1)
	await physics_frame
	check(solver.constrain_terrain_motion(body,Vector3(8,0,0)).is_zero_approx(),"crossed impassable strip to passable endpoint")
	check(solver.constrain_terrain_motion(body,Vector3(4,0,-2)).is_equal_approx(Vector3(0,0,-2)),"world Z boundary slide missing")
	check(solver.constrain_terrain_motion(body,Vector3(-2,0,-1)).is_equal_approx(Vector3(-2,0,-1)),"free motion changed")
	# Water changes logical foot support, never creates support over absent terrain.
	var wet:=SwgTerrainEvaluator.new();check(wet.configure({"fractals":[],"layers":[],"global_water_enabled":true,"global_water_height":2}),"configure water")
	solver.configure_terrain(wet,Vector3.ZERO,1)
	body.position=Vector3(1,1.001,-1)
	check(not solver.terrain_support(body,body.position).valid,"water invented resident ground")
	var floor:=StaticBody3D.new();floor.collision_layer=2
	var floor_shape:=CollisionShape3D.new();floor_shape.shape=SwgMeshBuilder.new().create_terrain_collision(wet.build_chunk(-8,-8,16,8))
	floor.add_child(floor_shape);floor.position=Vector3(-8,0,8);root.add_child(floor)
	for i in 3:await physics_frame
	var support:Dictionary=solver.terrain_support(body,body.position)
	check(support.valid and support.swimming and support.below_water,"logical water attachment missing")
	check(is_equal_approx(support.height,1) and is_zero_approx(support.real_height),"source water minus swim height differs")
	var followed:Dictionary=solver.move_on_terrain(body,Vector3(1,0,0))
	check(followed.handled and is_equal_approx(body.position.x,2) and absf(body.position.y-1.001)<.001,"swimming horizontal move changed")
	solver.set_swim_height(3)
	body.position.y=.001
	support=solver.terrain_support(body,body.position)
	check(support.valid and not support.swimming and support.below_water and is_zero_approx(support.height),"wading should keep real terrain support")
	body.queue_free();floor.queue_free();await physics_frame
	var report:Dictionary={"passed":true,"checks":checks,"rules":"APAS tile threshold, path passability, axis slide, logical water support","hardware_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/terrain-navigation-policy.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit()
