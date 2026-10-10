extends SceneTree
## Original starport floor, production tracked body; synthetic poses, XR off.
class Host extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
var errors:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host)
	host.stage=host.loader.load_stage("res://../runtime/assets/mos_eisley/scene.json");host.add_child(host.stage)
	var rig=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig)
	var body=rig.get_node("PlayerBody");host.player=body;body.ground_provider=host.stage;body.active=false;body.set_physics_process(false)
	var head=body.get_camera();head.position.y=1.65
	body.spawn_point=Vector3(-60,.7,10);body.reset_spawn();body.prepare_tracked_body();host.stage.set_observer(body);host.stage.seed_membership_at(body.global_position,"1106368:4")
	await physics_frame;await physics_frame
	check(host.ground_xr_spawn(),"Original starport start grounds")
	var floor_y:float=body.global_position.y;var start:Vector3=body.global_position
	var origin_y:float=rig.global_position.y
	for height in [1.0,.5,.3,1.65,.4,1.65]:
		head.position.y=height;head.rotation.x=-1.3
		var pose:Transform3D=head.transform
		body._update_body_under_camera(1.0/90)
		check(absf(body.global_position.y-floor_y)<.02,"Posture resize preserves foot plane at eye height "+str(height))
		for i in range(45):
			body._update_body_under_camera(1.0/90)
			body._update_ground_information(1.0/90)
			body.ground_control_velocity=Vector2(.25,0)
			body.move_player(Vector3(.25,0,0))
			await physics_frame
		check(absf(body.global_position.y-floor_y)<.02,"Low-posture locomotion retains original floor at "+str(height))
		check(absf(rig.global_position.y-origin_y)<.02,"Posture locomotion cannot accumulate origin height drift at "+str(height))
		check(head.transform==pose,"Ground correction leaves raw tracked pose unchanged")
	check(body.global_position.x>start.x+.5,"Regression performs actual capsule locomotion")
	# Login while physically prone must not lower an already valid saved foot point.
	head.position.y=.25;body.prepare_tracked_body()
	check(absf(body.global_position.y-floor_y)<.02 and host.ground_xr_spawn(),"Prone login preserves and grounds saved foot position")
	# An old corrupted save recovers only to geometry in the same original room.
	body.apply_world_correction(Vector3.DOWN*.8)
	check(host.ground_xr_spawn() and absf(body.global_position.y-floor_y)<.025,"Buried saved foot position recovers to the same original room floor")
	check(str(host.stage.current_cell.get("cell_id",""))=="1106368:4","Recovery retains the saved native room")
	var blocker:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1,2,1);collision.shape=box;blocker.add_child(collision);host.add_child(blocker);blocker.global_position=body.global_position+Vector3.UP
	await physics_frame;await physics_frame
	body.apply_world_correction(Vector3.DOWN*.8)
	var blocked:Vector3=body.global_position
	check(not host.ground_xr_spawn() and body.global_position==blocked,"Buried recovery refuses an obstructed full capsule")
	blocker.free();await physics_frame
	check(host.ground_xr_spawn(),"Removing obstruction permits geometry-backed recovery")
	body.apply_world_correction(Vector3.DOWN*3)
	var too_deep:Vector3=body.global_position
	check(not host.ground_xr_spawn() and body.global_position==too_deep,"Recovery cannot search beyond its two-metre bound")
	body.apply_world_correction(Vector3.UP*100)
	var unsupported:Vector3=body.global_position
	check(not host.ground_xr_spawn() and body.global_position==unsupported,"Missing floor remains an error without an invented spawn")
	print(JSON.stringify({"passed":errors.is_empty(),"checks":checks,"errors":errors,"original_geometry":true,"tracking":"synthetic","live_xr":false}));host.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
