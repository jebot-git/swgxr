extends SceneTree
var errors: Array[String]=[]
var checks:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var gesture=preload("res://scout/gestures.gd").new()
	var runs:=0;var digs:=0
	for i in range(270):
		var t:=i/90.0;var head:=Transform3D(Basis.IDENTITY,Vector3(t,1.7,0));var pump:=sin(t*TAU*2)*0.22
		var result: Dictionary=gesture.sample(1.0/90,head,head.origin+Vector3(-0.2,-0.45,-0.35+pump),head.origin+Vector3(0.2,-0.45,-0.35-pump),1,1,true)
		if result.burst_run:runs+=1
	check(runs>0,"Repeated alternating arm strokes trigger Burst Run while translating")
	gesture.reset();runs=0
	for i in range(270):
		var head:=Transform3D(Basis.IDENTITY,Vector3(i*0.02,1.7,0));var result: Dictionary=gesture.sample(1.0/90,head,head.origin+Vector3(-0.2,-0.4,-0.3),head.origin+Vector3(0.2,-0.4,-0.3),1,1,true)
		if result.burst_run:runs+=1
	check(runs==0,"Locomotion without arm strokes does not activate Burst Run")
	gesture.reset()
	for i in range(450):
		var y:=0.08+0.055*sin(i/90.0*TAU*2)
		var result: Dictionary=gesture.sample(1.0/90,Transform3D.IDENTITY,Vector3(-0.2,y,0),Vector3(0.2,y,0),y,y,true)
		if result.forage:digs+=1
	check(digs==1,"Repeated ground strokes trigger once until hands leave ground")
	gesture.reset();digs=0
	for i in range(270):
		var y:=0.8+0.05*sin(i/90.0*TAU*2);var result: Dictionary=gesture.sample(1.0/90,Transform3D.IDENTITY,Vector3(-0.2,y,0),Vector3(0.2,y,0),y,y,true)
		if result.forage:digs+=1
	check(digs==0,"Air gestures cannot forage")
	gesture.reset()
	for i in range(20):
		gesture.sample(1.0/90,Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,1,1,true)
		gesture.sample_throw(1.0/90,Transform3D.IDENTITY,Vector3(0,0,-i*0.02),true)
	check(gesture.valid_throw(),"Moving then releasing trap meets speed and travel gates")
	gesture.reset();check(not gesture.valid_throw(),"No motion cannot throw trap")
	var abilities=preload("res://combat/ability_state.gd").new()
	var first: Dictionary={"id":"first","cooldown_seconds":20};var second: Dictionary={"id":"second","cooldown_seconds":30}
	abilities.replace_selection(first);abilities.replace_selection(second)
	check(not abilities.cooldowns.has("first"),"Replacing selected unarmed ability does not apply cooldown")
	abilities.primed=true;abilities.replace_selection(first,"entertainer")
	check(abilities.cooldowns.second==30 and not abilities.primed and abilities.selected=="first","Replacing armed ability across professions cools it down without activating")
	check(abilities.ham.is_empty(),"Discarding armed selection charges no attack SAC")
	var root_node:=Node3D.new();root.add_child(root_node)
	var head:=Node3D.new();root_node.add_child(head);head.position=Vector3(0,1.7,0)
	var hand:=Node3D.new();root_node.add_child(hand);hand.position=Vector3(0.3,1.2,-0.4)
	var ui:=preload("res://combat/ability_hologram.gd").new();root_node.add_child(ui)
	ui.open_on_hand([{"id":"mask_scent","label":"Mask Scent","source_command":"maskscent"}],hand,head)
	var previous: Vector3=ui.panel.global_position
	root_node.position+=Vector3(4,0,2);ui.follow_controller()
	check(ui.panel.global_position.is_equal_approx(previous+Vector3(4,0,2)),"Open radial follows controller through locomotion")
	hand.position+=Vector3(0.2,-0.1,0);ui.follow_controller()
	check(ui.panel.global_position.is_equal_approx(hand.global_position+Vector3.UP*0.16),"Menu follows hand independently of head")
	check(SwgScoutLocomotion.terrain_factor(40,1,1)>SwgScoutLocomotion.terrain_factor(40,1,0),"Terrain negotiation reduces uphill penalty")
	check(SwgScoutLocomotion.terrain_factor(0,1,0)==1 and SwgScoutLocomotion.terrain_factor(40,0,0)==1,"Terrain negotiation does not accelerate flat or downhill walking")
	# Load the complete controller with actual XR Tools autoloads initialized.
	var scout=load("res://scout/controller.gd")
	check(scout!=null,"Scout controller and dependencies load")
	check(is_equal_approx(scout.ray_entry(Transform3D.IDENTITY,Vector3(0,0,-5),1),4),"Trap targets original sphere front surface")
	check(is_inf(scout.ray_entry(Transform3D.IDENTITY,Vector3(2,0,-5),1)) and is_inf(scout.ray_entry(Transform3D.IDENTITY,Vector3(0,0,5),1)),"Off-reticle and behind-head targets are rejected")
	var rig: XROrigin3D=load("res://xr/player_rig.tscn").instantiate();root_node.add_child(rig)
	var player=rig.get_node("PlayerBody");player.set_physics_process(false)
	var provider: Node3D=rig.get_node("ScoutMovement")
	check(provider in player._movement_providers,"Scout movement is registered in the actual XR Tools provider chain")
	player.ground_control_velocity=Vector2(0,-2);player.on_ground=true;player.ground_angle=0;player.ground_vector=Vector3.UP
	provider.observe({"burst_active":true,"burst_remaining":30,"slope_fraction":1})
	provider.physics_movement(0.01,player,false)
	check(is_equal_approx(player.ground_control_velocity.length(),3.644),"Confirmed native Burst Run scales virtual controller motion")
	player.ground_control_velocity=Vector2(0,-2);provider.physics_movement(13,player,false)
	check(player.ground_control_velocity.length()==2,"Stale native state cannot extend Burst Run")
	root_node.queue_free()
	await process_frame
	await process_frame
	var report: Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"mocked_tracking":true,"live_core3":false,"headset_tested":false};print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/scout-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
