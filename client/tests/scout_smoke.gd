extends SceneTree
class InputHost extends Node:
	var inventory_request_pending:=false
class InputBag extends Node3D:
	var is_open:=false
	var action_pending:=false
	var held_item:Dictionary={}
class InputScout extends "res://scout/controller.gd":
	var calls:Array=[]
	func request(action:String,_detail:Dictionary={})->Dictionary:
		calls.append(action);return {}
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
	for i in range(450):
		var y:=.225+.075*sin(i/90.0*TAU*2)
		var result:Dictionary=gesture.sample(1.0/90,Transform3D(Basis.IDENTITY,Vector3(0,.8,0)),Vector3(-.2,y,-.3),Vector3(.2,y,-.3),y,y,true)
		if result.forage:digs+=1
	check(digs==1,"Three comfortable scoops trigger while controller origins stay 15cm above floor")
	gesture.reset();digs=0
	for i in range(270):
		var y:=.17+.015*sin(i/90.0*TAU*2)
		if gesture.sample(1.0/90,Transform3D.IDENTITY,Vector3(-.2,y,0),Vector3(.2,y,0),y,y,true).forage:digs+=1
	check(digs==0,"Near-ground tracking jitter cannot forage")
	gesture.reset();digs=0
	for i in range(270):
		var y:=0.8+0.05*sin(i/90.0*TAU*2);var result: Dictionary=gesture.sample(1.0/90,Transform3D.IDENTITY,Vector3(-0.2,y,0),Vector3(0.2,y,0),y,y,true)
		if result.forage:digs+=1
	check(digs==0,"Air gestures cannot forage")
	for mode in ["one_hand", "alternating", "shovel", "sideways", "head_turn", "walking_low", "jitter_low"]:
		gesture.reset();digs=0
		for i in range(720):
			if i<270:
				gesture.sample(1.0/90,Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,.25,.8,true)
				continue
			var t:=(i-270)/90.0
			var head:=Transform3D(Basis.IDENTITY,Vector3(0,.8,0))
			var x:=-.2
			var ly:=.225+.075*sin(t*TAU*2)
			var ry:=.225-.075*sin(t*TAU*2) if mode=="alternating" else .8
			var z:=-.3
			if mode in ["shovel","walking_low","jitter_low"]:
				ly=.20;z+=sin(t*TAU*2)*(.1 if mode!="jitter_low" else .02)
			if mode=="sideways":ly=.20;x+=sin(t*TAU*2)*.1
			if mode=="head_turn":ly=.20;head.basis=Basis(Vector3.UP,sin(t*TAU*2)*.8)
			if mode=="walking_low": head.origin.z=z+.3
			if gesture.sample(1.0/90,head,Vector3(x,ly,z),Vector3(.2,ry,-.3),ly,ry,true).forage:digs+=1
		check(digs==(0 if mode in ["walking_low","jitter_low","head_turn"] else 1),"Forage trace "+mode+" recognizes deliberate strokes only and latches")
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
	var dispatch:=InputScout.new();dispatch.app=InputHost.new();dispatch.bag=InputBag.new()
	dispatch.last_reply=0;dispatch.state={"forage_available":true};dispatch.busy=true
	dispatch.gesture_actions({"forage":true,"burst_run":false},true)
	check(dispatch.calls.is_empty() and dispatch.forage_pending_until>Time.get_ticks_msec(),"Foraging survives a simultaneous background status request")
	dispatch.busy=false;dispatch.gesture_actions({"forage":false,"burst_run":false},true)
	dispatch.gesture_actions({"forage":false,"burst_run":false},true)
	check(dispatch.calls==["forage"],"Completed gesture dispatches exactly once after status response")
	dispatch.forage_pending_until=Time.get_ticks_msec()-1
	dispatch.gesture_actions({"forage":false,"burst_run":false},true)
	check(dispatch.calls.size()==1,"Expired gesture cannot activate later")
	dispatch.forage_pending_until=Time.get_ticks_msec()+2000
	dispatch.gesture_actions({"forage":false,"burst_run":false},false)
	check(dispatch.calls.size()==1 and dispatch.forage_pending_until==0,"Tracking loss cancels deferred gesture")
	dispatch.app.free();dispatch.bag.free();dispatch.free()
	# Load the complete controller with actual XR Tools autoloads initialized.
	var scout=load("res://scout/controller.gd")
	check(scout!=null,"Scout controller and dependencies load")
	var controller= scout.new();root_node.add_child(controller);controller.set_process(false)
	var floor_body:=StaticBody3D.new();root_node.add_child(floor_body);floor_body.collision_layer=1
	var floor_shape:=CollisionShape3D.new();floor_body.add_child(floor_shape);var box:=BoxShape3D.new();box.size=Vector3(4,.1,4);floor_shape.shape=box;floor_body.position.y=-.05
	await physics_frame;await physics_frame
	check(is_equal_approx(controller.ground_distance(root_node.global_position+Vector3(0,.3,0)),.3),"Foraging detects interior floor layer from reachable controller height")
	check(is_inf(controller.ground_distance(root_node.global_position+Vector3(0,.8,0))),"Ground probe does not reach a distant floor")
	floor_body.collision_layer=2
	await physics_frame;await physics_frame
	check(is_equal_approx(controller.ground_distance(root_node.global_position+Vector3(0,.3,0)),.3),"Foraging also detects terrain layer")

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
