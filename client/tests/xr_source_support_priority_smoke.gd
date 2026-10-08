extends SceneTree
class Provider extends Node3D:
	var ground_support:=SwgGroundSupport.new()
	var interior:=false
	func collision_context(_point:Vector3)->Dictionary:return {"building_object_id":123 if interior else 0,"allowed_cell_ids":["floor"]}
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var provider:=Provider.new();world.add_child(provider)
	check(provider.ground_support.configure([{"transform":Transform3D.IDENTITY,"cells":{"floor":{"building_object_id":123,"floor_vertices":[-2,.1,-2,2,.1,-2,2,.1,2,-2,.1,2],"floor_triangles":[{"id":0,"indices":[0,1,2],"normal":[0,1,0],"neighbors":[-1,-1,1],"edge_flags":[0,0,1],"portal_ids":[-1,-1,-1]},{"id":1,"indices":[0,2,3],"normal":[0,1,0],"neighbors":[0,-1,-1],"edge_flags":[1,0,0],"portal_ids":[-1,-1,-1]}]}}}]),"Authored floor fixture loads")
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=2;world.add_child(floor_body)
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(10,.2,10);floor_body.add_child(shape);floor_body.position.y=.1
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();world.add_child(rig)
	var player=rig.get_node("PlayerBody");player.set_physics_process(false);player.active=true;player.prepare_tracked_body();player.collision_mask=7;player.ground_provider=provider
	player.global_position=Vector3(0,.201,0)
	await physics_frame;await physics_frame
	var support:Dictionary=player._source_support(player.global_position,.3,.3)
	check(support.valid and support.get("terrain",false) and is_equal_approx(support.height,.2),"Higher exterior terrain wins over lower attached authored floor")
	floor_body.position.y=-.1
	await physics_frame;await physics_frame
	support=player._source_support(player.global_position,.3,.3)
	check(support.valid and not support.get("terrain",false) and is_equal_approx(support.height,.1),"Higher attached authored floor wins over exterior terrain")
	var wet:=SwgTerrainEvaluator.new();wet.configure({"fractals":[],"layers":[],"global_water_enabled":true,"global_water_height":1.2})
	player.step_solver.configure_terrain(wet,Vector3.ZERO,1)
	support=player._source_support(player.global_position,.3,.3)
	check(support.valid and support.get("swimming",false) and is_equal_approx(support.height,.2),"Logical water surface wins over submerged low pier")
	provider.interior=true
	support=player._source_support(player.global_position,.3,.3)
	check(support.valid and not support.get("terrain",false) and is_equal_approx(support.height,.1),"Interior remains attached to its authored floor below external water")
	provider.interior=false
	var desktop=load("res://scripts/player.gd").new();world.add_child(desktop);desktop.testing=true;desktop.active=true;desktop.collision_mask=7;desktop.ground_provider=provider;desktop.position=Vector3(1,.101,0)
	desktop.step_solver.configure_terrain(wet,Vector3.ZERO,1)
	for _i in 4:await physics_frame
	check(absf(desktop.position.y-.201)<.002,"Desktop follows logical water above a submerged authored floor")
	world.free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"renderer":"dummy","headset_validated":false}
	FileAccess.open("res://../runtime/evidence/xr-source-support-priority-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
