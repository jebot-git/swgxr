extends SceneTree
const Policy=preload("res://combat/movement_reconciliation.gd")
class Host extends Node:
	var active_planet:="tatooine"
	var player:CharacterBody3D
	var stage:Node3D
func _initialize()->void:call_deferred("run")
func run()->void:
	var snapshot:Dictionary={"zone":"tatooine","position":[1,0,2],"building_id":"0","cell_index":0}
	assert(not Policy.annotate(snapshot,{"mutation":{"movement_accepted":true}}).has("movement_rejected"))
	assert(not Policy.annotate(snapshot,{"mutation":{"movement_accepted":false,"transport_acknowledged":true}}).has("movement_rejected"))
	var rejected:=Policy.annotate(snapshot,{"sequence":12,"mutation":{"movement_accepted":false,"error_code":"movement_speed"}})
	assert(rejected.movement_rejected.reason=="movement_speed")
	var host:=Host.new();root.add_child(host)
	host.stage=preload("res://scripts/stage_loader.gd").new().empty_stream_stage({"planet":"tatooine","origin":[0,0,0]},Vector3.ZERO);host.add_child(host.stage)
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig)
	host.player=rig.get_node("PlayerBody");host.player.ground_provider=host.stage
	host.player.active=false;host.player.prepare_tracked_body()
	var head:XRCamera3D=host.player.get_camera();var before:=head.transform
	assert(Policy.apply(host,rejected))
	assert(host.player.global_position.is_equal_approx(Vector3(1,0,-2)))
	assert(head.transform.is_equal_approx(before),"Authoritative correction rewrote tracked head pose")
	host.player.apply_world_correction(Vector3(.1,0,0))
	assert(not Policy.apply(host,rejected) and host.player.global_position.is_equal_approx(Vector3(1.1,0,-2)),"Duplicate correction rolled back new local motion")
	var older:=rejected.duplicate(true);older.movement_rejected.sequence=11
	assert(not Policy.apply(host,older),"Older correction reapplied")
	var stamped:=Policy.stamp_request({"position":[1,0,2]},{"locomotion":{"movement_revision":7}})
	assert(stamped.movement_revision==7)
	assert(Policy.stamp_request(stamped,{"locomotion":{"movement_revision":8}}).movement_revision==7,"Queued request borrowed newer movement authority")
	assert(not Policy.stamp_request({"position":[1,0,2]},{}).has("movement_revision"),"Legacy snapshot fabricated movement revision")
	assert(not Policy.apply(host,snapshot),"Ordinary accepted snapshot corrected local height")
	var wrong:=rejected.duplicate(true);wrong.zone="naboo"
	assert(not Policy.apply(host,wrong),"Cross-zone rejection bypassed transport loading")
	# Production spawn routine uses logical water support above real resident ground.
	var evaluator:=SwgTerrainEvaluator.new();assert(evaluator.configure({"fractals":[],"layers":[],"global_water_enabled":true,"global_water_height":2}))
	var floor:=StaticBody3D.new();floor.collision_layer=2
	var shape:=CollisionShape3D.new();shape.shape=SwgMeshBuilder.new().create_terrain_collision(evaluator.build_chunk(-8,-8,16,8));floor.add_child(shape);floor.position=Vector3(-8,0,8);host.add_child(floor)
	host.player.step_solver.configure_terrain(evaluator,Vector3.ZERO,1)
	host.player.apply_world_correction(Vector3(0,2,0)-host.player.global_position)
	for i in 3:await physics_frame
	var app=load("res://scripts/main.gd").new();app.player=host.player
	assert(app.ground_xr_spawn(),"Water spawn failed")
	assert(absf(host.player.global_position.y-1.001)<.002,"Water spawn sank to physical seabed")
	assert(head.transform.is_equal_approx(before),"Water spawn rewrote tracked head")
	app.free();host.queue_free();await process_frame
	print(JSON.stringify({"passed":true,"checks":16,"hardware_tested":false}));quit()
