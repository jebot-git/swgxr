extends SceneTree
## Production XR orchestration with native APAS paths and real Jolt collision.
var checks:=0
var errors:Array=[]
var rows:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var evaluator:=SwgTerrainEvaluator.new()
	check(evaluator.configure({"fractals":[],"source_chunk_size":8,"source_tiles_per_chunk":2,"layers":[{"enabled":true,"boundaries":[{"type":"BREC","enabled":true,"rect":[4,0,7.9,7.9]}],"affectors":[{"type":"APAS","enabled":true,"passable":false,"feather_threshold":.5}]}]}),"Source passability fixture loads")
	for mode in ["controller","roomscale"]:
		for airborne in [false,true]:
			var world:=Node3D.new();root.add_child(world)
			var floor_body:=StaticBody3D.new();floor_body.collision_layer=2;world.add_child(floor_body)
			var floor_shape:=CollisionShape3D.new();floor_shape.shape=BoxShape3D.new();floor_shape.shape.size=Vector3(30,.2,30);floor_shape.position.y=-.1;floor_body.add_child(floor_shape)
			var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();world.add_child(rig)
			var player=rig.get_node("PlayerBody");player.set_physics_process(false);player.active=true;player.prepare_tracked_body();player.collision_mask=7
			player.step_solver.configure_terrain(evaluator,Vector3.ZERO,0)
			player.global_position=Vector3(3.5,3 if airborne else .001,-2)
			player.on_ground=not airborne;player.jump_in_progress=airborne
			await physics_frame;await physics_frame
			var before:Vector3=player.global_position
			var raw_head:Transform3D=player.get_camera().transform
			if mode=="controller":
				player.move_player(Vector3(120,0,-30))
			else:
				# Physical head intent crosses the blocked tile; the unblocked Z
				# component remains available even when the capsule is airborne.
				player.get_camera().global_position=before+Vector3(2,1.7,-.5)
				raw_head=player.get_camera().transform
				player._in_physics_movement=true
				player._update_body_under_camera(.016)
				player._in_physics_movement=false
			var finish:Vector3=player.global_position
			rows.append({"mode":mode,"airborne":airborne,"start":str(before),"finish":str(finish)})
			check(absf(finish.x-before.x)<.001,"Blocked APAS tile cannot be crossed: %s airborne=%s"%[mode,airborne])
			check(finish.z<before.z-.1,"Free Z slide survives APAS block: %s airborne=%s"%[mode,airborne])
			check(player.collision_mask==7,"Passability preserves building/terrain capsule mask")
			check(player.get_camera().transform.is_equal_approx(raw_head),"Passability never rewrites physical HMD transform")
			world.free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"rows":rows,"renderer":"dummy","tracking":"mocked","headset_validated":false}
	FileAccess.open("res://../runtime/evidence/xr-terrain-passability-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
