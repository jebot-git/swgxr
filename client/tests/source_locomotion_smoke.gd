extends SceneTree
## Source-derived numeric policy and production XR input/physics, native profile mocked.
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
static func profile()->Dictionary:
	return {"run_speed":7.0,"walk_speed":2.5,"run_acceleration":3.0,"walk_acceleration":5.0,"speed_multiplier_base":1.2,"speed_multiplier_mod":1.5,"acceleration_multiplier_base":1.0,"acceleration_multiplier_mod":1.0,"slope_mod_angle_radians":PI/6,"slope_mod_percent":.2,"water_mod_percent":.4,"swim_height":.65,"server_max_speed":10.5,"movement_allowed":true,"frozen":false,"swimming":false}
func sample(p:Dictionary,current:float,input:=1.0,environment:Dictionary={},walking:=false,delta:=1.0)->Dictionary:
	return SwgScoutLocomotion.source_movement(p,current,input,walking,environment,delta)
func _initialize()->void:call_deferred("run")
func run()->void:
	var p:=profile();var result:=sample(p,0)
	check(result.valid and is_equal_approx(result.desired_speed,12.6) and is_equal_approx(result.speed,5),"Native base and mod multiply once; standing acceleration uses walk acceleration")
	result=sample(p,5);check(is_equal_approx(result.acceleration,3) and is_equal_approx(result.speed,8),"Crossing effective walk speed switches to original run acceleration")
	result=sample(p,8);check(is_equal_approx(result.speed,10.5),"Native server speed limit caps acceleration despite larger base-scaled target")
	check(is_equal_approx(sample(p,0,1,{},true).speed,4.5),"Walking uses scaled native walk speed")
	check(is_equal_approx(sample(p,0,.5).desired_speed,6.3),"Analog movement scales desired source speed")
	check(is_equal_approx(sample(p,.2,0,{},false,.1).speed,0),"Source deceleration reaches rest without overshoot")
	var environment:Dictionary={"terrain":true,"normal_dot_forward":-.75}
	result=sample(p,0,1,environment)
	check(is_equal_approx(result.terrain_modifier,.6) and is_equal_approx(result.desired_speed,7.56),"Original slope threshold/interpolation uses native angle and percent")
	environment.normal_dot_forward=-.4;check(sample(p,0,1,environment).terrain_modifier==1,"Below native slope tolerance is unpenalized")
	environment.normal_dot_forward=.75;check(sample(p,0,1,environment).terrain_modifier==1,"Downhill receives no artificial acceleration or penalty")
	environment.normal_dot_forward=-.75;environment.terrain=false;check(sample(p,0,1,environment).terrain_modifier==1,"Authored solid floors bypass terrain slope penalty")
	environment.terrain=true;environment.below_water=true;check(is_equal_approx(sample(p,0,1,environment).terrain_modifier,.4),"Wading uses native water modifier instead of slope modifier")
	environment.swimming=true;check(sample(p,0,1,environment).terrain_modifier==1,"Swimming bypasses wading and terrain modifier as original client")
	p.frozen=true;check(sample(p,8).speed==0,"Native freeze immediately disallows virtual movement")
	p.frozen=false;p.movement_allowed=false;check(sample(p,8).speed==0,"Native movement lock immediately disallows virtual movement")
	p=profile();p.erase("run_speed");check(not sample(p,0).valid,"Incomplete profile cannot invent native movement values")
	p=profile();check(not sample(p,0,NAN).valid,"Nonfinite input is rejected")
	p.slope_mod_angle_radians=1.5707963705062866;check(sample(p,0).valid,"Native float pi/2 remains a valid slope threshold")
	var root_node:=Node3D.new();root.add_child(root_node)
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=2;root_node.add_child(floor_body);floor_body.position.y=-.1
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(20,.2,20);floor_body.add_child(shape)
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();root_node.add_child(rig)
	var player=rig.get_node("PlayerBody");player.set_physics_process(false);player.active=true;player.prepare_tracked_body();player.global_position=Vector3(0,.001,0);player.on_ground=true
	var provider:Node3D=rig.get_node("ScoutMovement")
	player.feedback.observe({"character_id":"native-fixture","locomotion":profile()})
	check(player.feedback.locomotion==profile(),"Owner feedback adopts complete native movement projection")
	provider.observe({"burst_active":true,"burst_remaining":30,"slope_fraction":1})
	player.ground_control_velocity=Vector2(rig.get_node("LeftHand/MovementDirect").max_speed,0)
	provider.physics_movement(.1,player,false)
	check(player.source_movement_active and is_equal_approx(player.source_movement_velocity.length(),.5),"Production movement provider uses native acceleration without old Burst Run multiplier")
	await physics_frame;await physics_frame
	var head:Transform3D=player.get_camera().transform;var before:Vector3=player.global_position
	player.move_player(Vector3(100,0,0))
	check(absf(player.global_position.x-before.x-.5*player.get_physics_process_delta_time())<.001,"Actual capsule movement uses source velocity, not addon traction or unbounded requested velocity")
	check(player.get_camera().transform.is_equal_approx(head),"Native movement policy leaves local HMD transform unchanged")
	p=profile();p.frozen=true;player.feedback.observe({"character_id":"native-fixture","locomotion":p})
	before=player.global_position;player.get_camera().position.x+=.1;var tracked_head:Transform3D=player.get_camera().transform
	player._update_body_under_camera(.016)
	check(player.global_position.is_equal_approx(before) and player.get_camera().transform==tracked_head,"Native freeze anchors body without rewriting physical head tracking")
	player.feedback.observe({"character_id":"another-owner","locomotion":profile()});player.ground_control_velocity=Vector2(rig.get_node("LeftHand/MovementDirect").max_speed,0);provider.physics_movement(.1,player,false)
	check(is_equal_approx(provider.source_speed,.5),"Changing owner resets prior acceleration state")
	provider.physics_movement(.1,player,true);check(player.source_movement_active and player.source_movement_velocity.is_zero_approx(),"Disabled movement cannot retain addon momentum")
	var native_profile:Dictionary={}
	var native_path:="res://../runtime/evidence/movement-native-smoke.json"
	if FileAccess.file_exists(native_path):
		var native:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(native_path))
		for row:Dictionary in native.get("responses",[]):
			var native_player:Dictionary=row.get("response",{}).get("snapshot",{}).get("player",{})
			if native_player.has("locomotion") and not native_player.locomotion.frozen:
				native_profile=native_player.locomotion
				player.feedback.observe(native_player)
				check(player.feedback.locomotion==native_profile and sample(native_profile,0).valid,"Actual Core3 envelope passes owner observer and source movement policy")
				provider.source_speed=0;player.ground_control_velocity=Vector2(rig.get_node("LeftHand/MovementDirect").max_speed,0);provider.physics_movement(1,player,false)
				check(is_equal_approx(player.source_movement_velocity.length(),native_profile.server_max_speed),"Actual Core3 speed replaces offline XR speed")
				break
	var desktop=load("res://scripts/player.gd").new();root_node.add_child(desktop);desktop.testing=true;desktop.active=true;desktop.position=Vector3(0,.02,3)
	desktop.configure_player_combat({"character_id":"desktop-native","locomotion":native_profile if not native_profile.is_empty() else profile()})
	check(desktop.locomotion_profile==desktop.feedback.locomotion,"Desktop observer forwards identical native policy")
	desktop.test_input=Vector2(1,0)
	for _i in 45:await physics_frame
	var desktop_cap:float=desktop.feedback.locomotion.server_max_speed
	check(desktop.velocity.x>0 and desktop.velocity.x<=desktop_cap+.001,"Desktop native capsule obeys shared acceleration and native speed limit")
	var frozen:Dictionary=desktop.feedback.locomotion.duplicate(true);frozen.frozen=true
	desktop.feedback.observe({"character_id":"desktop-native","locomotion":frozen})
	var desktop_before:Vector3=desktop.position
	for _i in 3:await physics_frame
	check(absf(desktop.position.x-desktop_before.x)<.001,"Desktop movement immediately obeys authoritative freeze")
	root_node.free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"renderer":"dummy","native_profile_replayed":not native_profile.is_empty(),"headset_validated":false,"source_revision":"949451032647e45e42c3aaef3f41b132c8af36e3"}
	FileAccess.open("res://../runtime/evidence/source-locomotion-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
