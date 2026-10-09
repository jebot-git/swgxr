extends SceneTree
## Original skeleton + clips and mocked tracking; not live headset validation.
const Avatar=preload("res://scripts/avatar.gd")
const Tracked=preload("res://scripts/tracked_avatar.gd")
const Combat=preload("res://combat/ranged_rig.gd")
var errors:Array=[]
var checks:=0
var scenarios:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func velocity_trial(driver,body,render_hz:int)->Dictionary:
	driver.have_body_position=false;driver.measured_velocity=Vector3.ZERO;body.position=Vector3.ZERO;body.velocity=Vector3.ZERO
	driver.sample_body_velocity(1.0/60)
	var ticks:=0;var previous:=Vector3.ZERO;var legacy:=Vector3.ZERO
	var actual_min:=INF;var actual_max:=-INF;var legacy_min:=INF;var legacy_max:=-INF
	for frame in range(render_hz*3):
		var target_ticks:=int(floor((frame+1)*60.0/render_hz))
		while ticks<target_ticks:
			body.position.z-=5.0/60 # Includes room-scale displacement with body.velocity==0.
			driver.sample_body_velocity(1.0/60);ticks+=1
		var render_delta:=1.0/render_hz
		legacy=legacy.lerp((body.position-previous)/render_delta,1-exp(-16*render_delta));previous=body.position
		var actual:Vector3=driver.sample_body_context(render_delta).velocity
		if frame>render_hz:
			actual_min=minf(actual_min,-actual.z);actual_max=maxf(actual_max,-actual.z)
			legacy_min=minf(legacy_min,-legacy.z);legacy_max=maxf(legacy_max,-legacy.z)
	var report:Dictionary={"render_hz":render_hz,"physics_hz":60,"fixed_sample_speed_span_mps":actual_max-actual_min,"legacy_render_difference_speed_span_mps":legacy_max-legacy_min}
	check(actual_max-actual_min<0.001 and absf(actual_max-5)<0.001,"Constant actual displacement has stable gait velocity at %d Hz"%render_hz)
	check(legacy_max-legacy_min>0.2,"Fixture exposes old render/physics aliasing at %d Hz"%render_hz)
	body.position+=Vector3(100,0,0);driver.sample_body_velocity(1.0/60)
	check(driver.measured_velocity.is_zero_approx(),"Teleport resets presentation velocity")
	return report
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	var origin:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();root.add_child(origin)
	var body=origin.get_node("PlayerBody");body.set_physics_process(false)
	var camera:XRCamera3D=origin.get_node("XRCamera3D");camera.position=Vector3(0,1.7,0)
	var tracked:=Tracked.new();root.add_child(tracked)
	var avatar:=Avatar.new();tracked.add_child(avatar)
	check(avatar.configure("human_male",{"profession":"crafting_artisan"}).error=="" and tracked.configure(avatar,origin),"Actual original human avatar and source locomotion configure")
	tracked.set_process(false);tracked.set_physics_process(false);tracked.set_standing_eye_height(1.7)
	var rates:Array=[]
	for hz in [90,120]:rates.append(velocity_trial(tracked,body,hz))
	body.position=Vector3.ZERO
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var combat:=Combat.new();root.add_child(combat)
	check(combat.configure(camera,body,[catalog.weapons.pistol_fwg5,catalog.weapons.rifle_e11],"right",origin),"Original FWG5 and E11 configure")
	combat.set_process(false);combat.set_physics_process(false);combat.set_allowed(true);combat.tracked_avatar=tracked;tracked.combat_rig=combat
	check(not RenderingServer.frame_pre_draw.is_connected(combat.refresh_render_pose),"No gun-only overwrite after shared avatar solve")
	check(combat.process_priority<tracked.process_priority,"Tracking request is gathered before shared IK render finalization")
	var maximum_grip_error:=0.0;var maximum_segment_error:=0.0
	for side:String in ["left","right"]:
		combat.dominant=side
		for scenario:String in ["fixed_tracking_run_clip","locomotion","turn","crouch","unreachable"]:
			combat.draw(0 if scenario!="turn" else 1);combat.two_hands=scenario=="turn"
			var previous_local:=Vector3.ZERO;var maximum_step:=0.0;var maximum_correction:=0.0
			for frame in range(240):
				var t:=frame/90.0
				var base:=Transform3D(Basis(Vector3.UP,t*0.65 if scenario=="turn" else 0.0),Vector3(t*0.8,0,-t*5) if scenario=="locomotion" else Vector3.ZERO)
				origin.global_transform=base
				var height:=1.7-0.6*(0.5-0.5*cos(t*2)) if scenario=="crouch" else 1.7
				camera.position=Vector3(0,height,0)
				var main_local:=Vector3(-0.22 if side=="left" else 0.22,height-0.4,-0.35)
				if scenario=="unreachable":main_local=Vector3(-2 if side=="left" else 2,2.1,-2)
				var requested:=base*Transform3D(Basis.IDENTITY,main_local)
				var support:=base*Transform3D(Basis.IDENTITY,main_local+Vector3(0,0,-0.24))
				var camera_before:=camera.global_transform;var body_before:Transform3D=body.global_transform
				combat.pose_weapon(requested,support)
				tracked.update_tracking(1.0/90,camera.global_transform,combat.hand_target("left"),combat.hand_target("right"),0,{"velocity":base.basis*Vector3(0,0,-5),"grounded":true})
				check(camera.global_transform==camera_before and body.global_transform==body_before,"Presentation never drives tracking/body")
				var visual:Node3D=combat.weapons[combat.selected].visual
				var local:Vector3=base.affine_inverse()*visual.global_position
				if frame>30:maximum_step=maxf(maximum_step,local.distance_to(previous_local))
				previous_local=local;maximum_correction=maxf(maximum_correction,visual.global_position.distance_to(requested.origin))
				check(combat.requested_weapon_pose.is_equal_approx(requested) if not combat.two_hands else combat.requested_weapon_pose.origin.is_equal_approx(requested.origin),"Bounded presentation never feeds back into physical request")
				for hand:String in ["left","right"]:
					var prefix:="l" if hand=="left" else "r"
					var target:Variant=combat.hand_target(hand)
					if target is Transform3D:
						var actual:Transform3D=tracked.skeleton.global_transform*tracked.skeleton.get_bone_global_pose(tracked.skeleton.find_bone("hold_"+prefix))
						maximum_grip_error=maxf(maximum_grip_error,actual.origin.distance_to(target.origin))
						check(actual.origin.distance_to(target.origin)<0.001 and actual.basis.orthonormalized().is_equal_approx(target.basis.orthonormalized()),"Animated original palm remains rigidly attached to weapon")
					for pair in [["arm","forearm"],["forearm","wrist"]]:
						var a:=tracked.skeleton.find_bone(prefix+pair[0]);var b:=tracked.skeleton.find_bone(prefix+pair[1])
						var rest:=tracked.skeleton.get_bone_global_rest(a).origin.distance_to(tracked.skeleton.get_bone_global_rest(b).origin)
						var posed:=tracked.skeleton.get_bone_global_pose(a).origin.distance_to(tracked.skeleton.get_bone_global_pose(b).origin)
						maximum_segment_error=maxf(maximum_segment_error,absf(rest-posed))
						check(absf(rest-posed)<0.0001,"Original arm lengths remain rigid")
			var result:Dictionary={"side":side,"scenario":scenario,"maximum_frame_step_m":maximum_step,"maximum_tracking_reach_correction_m":maximum_correction}
			scenarios.append(result)
			check(maximum_step<0.04,"Shared reachable/reach-bound presentation is continuous during "+scenario+" "+side+": "+str(maximum_step))
	check(maximum_grip_error<0.001 and maximum_segment_error<0.0001,"All motion samples preserve common grip and source anatomy")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"maximum_grip_error_m":maximum_grip_error,"maximum_segment_error_m":maximum_segment_error,"velocity_sampling":rates,"scenarios":scenarios,"tracking_mocked":true,"gpu_tested":false,"headset_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/xr-weapon-pose-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	combat.free();tracked.free();origin.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
