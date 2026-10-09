extends SceneTree
const Controller=preload("res://medic/controller.gd")
const Vats=preload("res://medic/doctor_vats.gd")
const Combat=preload("res://combat/ranged_rig.gd")
class Vital extends RefCounted:
	func observe(_value:Dictionary)->void:pass
class Feedback extends Node:
	var vital:=Vital.new()
	var blocked:=false
	func combat_blocked()->bool:return blocked
class Body extends CharacterBody3D:
	var active:=true
	var feedback:Feedback
	var medic:Node
	var medical_stick_side:=""
	var tracking:=true
	func combat_tracking_context()->Dictionary:return {"tracked":tracking}
class Scout extends Node:
	func world(value:Array)->Vector3:return Vector3(value[0],value[1],value[2])
	func source_position()->Array:return [0,0,0]
class Services extends Node:
	var free:=true
	func party_hand_free(_side:String)->bool:return free
class Bag extends Node3D:
	var allowed:=true
	var is_open:=false
	var action_pending:=false
	var held_item:Dictionary={}
	var offhand_occupied:=false
	var hologram:Node3D
	var control:XRController3D
	var opposite:="right"
	var finished:Array=[]
	var hip_tool:Dictionary={}
	func held_controller()->XRController3D:return control
	func held_hand_side()->String:return opposite
	func item_hand_pose(_hand:XRController3D,pose:Transform3D)->Transform3D:return pose
	func begin_mutation(_message:String)->void:action_pending=true
	func finish_item_action(success:bool)->void:action_pending=false;finished.append(success)
	func finish_consumable_action(_item:Dictionary,success:bool)->void:action_pending=false;finished.append(success)
	func set_busy(value:bool,_message:="")->void:action_pending=value
class Wheel extends Node3D:
	var menu_open:=false
	func close()->void:menu_open=false
	func update_badge(_a:Dictionary,_b:bool,_c:float,_d:Vector3,_e:bool,_f:="")->void:pass
	func open_on_hand(_abilities:Array,_hand:Node3D,_head:Node3D)->void:menu_open=true
class App extends Node:
	var datapad_epoch:=1
	var datapad_account:="doctor"
	var datapad_character_id:="1"
	var world_ready:=true
	var xr_focused:=true
	var session_leaving:=false
	var loading_stage:=false
	var inventory_request_pending:=false
	var avatar:Node3D
	var combat_rig:Node3D
	var inventory:Node3D
	var services:Services
	var scout:Scout
	var inventory_snapshot:Dictionary={}
	var calls:Array=[]
	var items:Dictionary={}
	var medical:Node3D
	var success:=true
	func owned_inventory_item(id:String)->Dictionary:return items.get(id,{})
	func source_position_at(value:Vector3)->Vector3:return value
	func update_inventory_presentation()->void:pass
	func api(_method:int,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return {"ok":success,"state":medical.state.duplicate(true),"mutation":{"success":success},"error":"fixture refusal"}
class Medic extends "res://medic/controller.gd":
	var controller_allowed:=true
	var boxes:Dictionary={}
	func allowed()->bool:return controller_allowed and body.active and app.xr_focused and HandInput.controller_tracked(hand)
	func sync_people()->void:pass
	func patient_bounds(person:Dictionary)->Array:return boxes.get(str(person.get("id","")),[])
var checks:=0
var errors:Array=[]
var app:App
var medic:Medic
var body:Body
var bag:Bag
var ui:Node3D
var combat:Node3D
var trackers:Dictionary={}
var hands:Dictionary={}
var baseline:Dictionary={}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:create_timer(45).timeout.connect(func():quit(2));call_deferred("run")
func point_at(position:Vector3)->void:
	medic.hand.global_transform=Transform3D(Basis.looking_at((position-medic.hand.global_position).normalized()),medic.hand.global_position)
func reset()->void:
	app.calls.clear();bag.finished.clear();bag.action_pending=false;bag.is_open=false;bag.allowed=true;app.success=true;app.world_ready=true;app.xr_focused=true;app.session_leaving=false;app.loading_stage=false;app.services.free=true
	body.active=true;body.tracking=true;body.feedback.blocked=false;medic.controller_allowed=true;medic.age=0;medic.busy=false;medic.wheel.menu_open=false;medic.focus_cast_pending=false
	medic.state=baseline.duplicate(true);medic.held={"id":"focus","tool_kind":"medical"};bag.held_item={};medic.doctor_motion.reset();ui.close();medic.focus_trigger.reset();medic.doctor_release_pending=false
	for side:String in trackers:
		trackers[side].set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);trackers[side].set_input("trigger",0.);trackers[side].set_input("grip",0.)
	medic.hand.global_position=Vector3(0,1.3,0);point_at(Vector3(0,1.3,-2));medic.head.global_position=Vector3(0,1.7,0)
func open_vats()->bool:return medic.button("primary_click",medic.side) and ui.active()
func flush()->void:
	await process_frame;await process_frame;await process_frame
func treatment_calls()->Array:return app.calls.filter(func(value):return value.path=="/medic/doctor")
func gesture_frame(held_point:Vector3,other_point:Vector3,grip:float)->void:
	bag.control.global_position=held_point;hands.left.global_position=other_point;trackers.left.set_input("grip",grip);medic.sample_doctor_gestures(.01)
func gesture_move(anchor:Vector3,from:Vector3,to:Vector3,free_from:Vector3,free_to:Vector3,grip:float)->void:
	for frame in range(1,36):gesture_frame(anchor+from.lerp(to,frame/35.),anchor+free_from.lerp(free_to,frame/35.),grip)
func run()->void:
	app=App.new();root.add_child(app)
	body=Body.new();root.add_child(body);body.feedback=Feedback.new();body.add_child(body.feedback)
	bag=Bag.new();root.add_child(bag);app.inventory=bag
	medic=Medic.new();root.add_child(medic);medic.set_process(false);medic.app=app;medic.body=body;medic.bag=bag;body.medic=medic;app.medical=medic
	medic.rig=XROrigin3D.new();medic.add_child(medic.rig)
	for side:String in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side+"_hand";tracker.set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(tracker);trackers[side]=tracker
		var hand:=XRController3D.new();hand.name=side.capitalize()+"Hand";hand.tracker=tracker.name;hand.pose="aim";medic.rig.add_child(hand);hands[side]=hand
	medic.side="left";medic.hand=hands.left;bag.control=hands.right
	medic.head=Camera3D.new();medic.rig.add_child(medic.head);medic.wheel=Wheel.new();medic.add_child(medic.wheel)
	ui=Vats.new();medic.add_child(ui);ui.setup(medic);medic.doctor_vats=ui
	app.scout=Scout.new();app.add_child(app.scout);app.services=Services.new();app.add_child(app.services)
	combat=Combat.new();root.add_child(combat);combat.set_process(false);combat.set_physics_process(false);combat.body=body;app.combat_rig=combat
	app.items={"focus":{"id":"focus","tool_kind":"medical"},"statepack":{"id":"statepack","medical_command":"healstate"},"revive":{"id":"revive","medical_command":"reviveplayer"},"blanket":{"id":"blanket","medical_command":"extinguishfire"}}
	baseline={"character_id":"1","abilities":[],"players":[{"id":"patient","name":"Patient","position":[0,0,-2],"healable":true,"dead":false,"states":1,"doctor_needs":{"healstate":true,"reviveplayer":false,"extinguishfire":false}}],"self":{},"doctor":{"healstate":{"learned":true,"range_m":6,"cooldown_seconds":0,"supplies":[{"item_id":"statepack","state":"stunned","state_mask":1,"label":"Stabilization Pack","charges":3}]},"reviveplayer":{"learned":true,"range_m":6,"cooldown_seconds":0},"extinguishfire":{"learned":true,"range_m":6,"cooldown_seconds":0}}}
	medic.boxes={"patient":[AABB(Vector3(-.3,0,-2.2),Vector3(.6,1.8,.4))]}
	reset();check(open_vats(),"Held Doctor focus opens friendly VATS on a native-eligible patient")
	check(ui.points.size()==1 and ui.points[0].item_id=="statepack","VATS exposes only current condition with exact owned supply")
	check(not combat.combat_actions_allowed(),"Friendly VATS blocks shared ranged, melee, volley and ultimate attack gate")
	check(medic.captures_combat(),"Active medical VATS owns control capture")
	point_at(ui.points[0].position);medic.sample_focus_trigger(.01,0);medic.sample_focus_trigger(.01,1);medic.sample_focus_trigger(.01,0);await flush()
	check(treatment_calls().size()==1,"Focus squeeze-and-release routes one Doctor treatment")
	if not treatment_calls().is_empty():
		var payload:Dictionary=treatment_calls()[0].payload
		check(payload.get("ability")=="healstate" and payload.get("item_id")=="statepack" and payload.get("focus_id")=="focus" and payload.get("target_id")=="patient","Exact supply, actual held focus and friendly patient reach /medic/doctor")
		check(payload.get("pose",{}).get("tracked",false) and not payload.has("state") and not payload.has("ability_id"),"Native selects state from exact pack; tracked pose stays medical rather than hostile attack payload")
	check(bag.finished==[true],"Successful state treatment reconciles native inventory action")
	for mode in ["no_focus","statepack_only","wrong_tool","unlearned","hostile","dead","missing_supply","empty_supply","wrong_state","no_need","cooldown","stale","bag","menu","unfocused","head_tracking","hand_tracking","stow","tool_change","aim_change","held_trigger","busy","failure"]:
		reset()
		match mode:
			"no_focus":medic.held={}
			"statepack_only":medic.held={};bag.held_item=app.items.statepack
			"wrong_tool":medic.held={"id":"focus","tool_kind":"crafting"}
			"unlearned":medic.state.doctor.healstate.learned=false
			"hostile":medic.state.players[0].healable=false
			"dead":medic.state.players[0].dead=true
			"missing_supply":medic.state.doctor.healstate.supplies=[]
			"empty_supply":medic.state.doctor.healstate.supplies[0].charges=0
			"wrong_state":medic.state.players[0].states=2
			"no_need":medic.state.players[0].doctor_needs.healstate=false
			"cooldown":medic.state.doctor.healstate.cooldown_seconds=3
			"stale":medic.age=5
			"bag":bag.is_open=true
			"menu":medic.wheel.menu_open=true
			"unfocused":app.xr_focused=false
			"head_tracking":body.tracking=false
			"hand_tracking":trackers.left.invalidate_pose("aim")
			"busy":medic.busy=true
			"failure":app.success=false
		open_vats()
		if not ui.points.is_empty():
			point_at(ui.points[0].position)
			if mode!="held_trigger":medic.sample_focus_trigger(.01,0)
			medic.sample_focus_trigger(.01,1)
			if mode=="stow":medic.stow()
			if mode=="tool_change":medic.held={"id":"otherfocus","tool_kind":"medical"}
			if mode=="aim_change":point_at(Vector3(2,1.3,-2))
			medic.sample_focus_trigger(.01,0)
		await flush()
		check(treatment_calls().size()==(1 if mode=="failure" else 0),"Production friendly treatment gate: "+mode)
		if mode in ["no_focus","statepack_only","wrong_tool","stow","tool_change","hand_tracking"]:check(not ui.active(),"Friendly markers clear without current held Doctor focus: "+mode)
		if mode=="failure":check(bag.finished==[false],"Rejected native treatment does not claim success")
	reset();open_vats();medic.stow();check(not ui.active() and combat.combat_actions_allowed(),"Stowing focus clears friendly markers and releases combat capture")
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	for profile_id in ["pistol_dl44","rifle_e11","carbine_ee3"]:
		reset();var weapon=preload("res://combat/weapon_state.gd").new();var profile:Dictionary=catalog.weapons[profile_id];weapon.configure(profile,profile.core3.certificationsRequired)
		weapon.tick(.01,0,combat.combat_actions_allowed(),false);open_vats();trackers.right.set_input("trigger",1.);trackers.left.set_input("trigger",1.)
		check(weapon.tick(.01,1,combat.combat_actions_allowed(),false).is_empty(),"Medical selection cannot fire held weapon: "+profile_id)
		medic.stow()
		for frame in range(100):weapon.tick(.01,1,combat.combat_actions_allowed(),false)
		check(weapon.fired==0 and not combat.combat_actions_allowed(),"Stow while triggers held preserves medical release gate: "+profile_id)
		trackers.right.set_input("trigger",0.);trackers.left.set_input("trigger",0.);weapon.tick(.01,0,combat.combat_actions_allowed(),false)
		check(not weapon.tick(.01,1,combat.combat_actions_allowed(),false).is_empty(),"Fresh release/press restores ordinary weapon use: "+profile_id)
	reset();open_vats();var chord=preload("res://combat/ultimate_input.gd").new();chord.sample(.01,0,0,true,combat.combat_actions_allowed());trackers.left.set_input("trigger",1.);trackers.right.set_input("trigger",1.);ui.close()
	check(not chord.sample(.01,1,1,true,combat.combat_actions_allowed()).ultimate and not combat.combat_actions_allowed(),"Closing friendly overlay cannot reinterpret held triggers as a combat ultimate")
	trackers.left.set_input("trigger",0.);trackers.right.set_input("trigger",0.);chord.sample(.01,0,0,true,combat.combat_actions_allowed())
	check(chord.sample(.01,1,1,true,combat.combat_actions_allowed()).ultimate,"Fresh chord after both controls release can use existing combat ultimate")
	for ability:String in ["reviveplayer","extinguishfire"]:
		for mode in ["success","wrong_item","not_held","not_needed","cooldown","unlearned","dead_healer","untracked","menu","busy","consent","failure"]:
			reset();medic.held={};var id:="revive" if ability=="reviveplayer" else "blanket";bag.held_item=app.items[id].duplicate();medic.state.players[0].doctor_needs[ability]=true;medic.state.players[0].dead=ability=="reviveplayer"
			match mode:
				"wrong_item":id="statepack"
				"not_held":bag.held_item={}
				"not_needed":medic.state.players[0].doctor_needs[ability]=false
				"cooldown":medic.state.doctor[ability].cooldown_seconds=2
				"unlearned":medic.state.doctor[ability].learned=false
				"dead_healer":body.feedback.blocked=true
				"untracked":body.tracking=false
				"menu":bag.is_open=true
				"busy":medic.busy=true
				"consent":medic.state.players[0].healable=false
				"failure":app.success=false
			await medic.cast_doctor(ability,id,"patient")
			check(treatment_calls().size()==(1 if mode in ["success","failure"] else 0),"Production held supply route %s: %s"%[ability,mode])
			if mode=="success":check(bag.finished==[true] and treatment_calls()[0].payload.item_id==id and not treatment_calls()[0].payload.has("focus_id"),"Exact held supply confirmed and reconciled: "+ability)
	for ability:String in ["reviveplayer","extinguishfire"]:
		for mode in ["normal","seated","mirror","trigger_pressed","freehand_occupied","tracking_loss","item_swap"]:
			reset();medic.held={};var id:="revive" if ability=="reviveplayer" else "blanket";bag.held_item=app.items[id].duplicate();medic.state.players[0].doctor_needs[ability]=true;medic.state.players[0].dead=ability=="reviveplayer"
			var anchor:=Vector3(0,1.224,-2)
			if mode=="seated":anchor.y-=.55;medic.boxes.patient=[AABB(Vector3(-.3,-.55,-2.2),Vector3(.6,1.8,.4))]
			if mode=="mirror":
				medic.side="right";medic.hand=hands.right;bag.control=hands.left;bag.opposite="left"
			# Drive the actual held-controller/read-pose routing on both handedness.
			var off:XRController3D=hands.right if mode=="mirror" else hands.left
			var off_tracker:XRControllerTracker=trackers.right if mode=="mirror" else trackers.left
			var begin:=Vector3(-.12,0,.6);var begin_other:=Vector3(.12,0,.6);var end:=Vector3(-.12,0,.08);var end_other:=Vector3(.12,0,.08)
			bag.control.global_position=anchor+begin;off.global_position=anchor+begin_other;medic.sample_doctor_gestures(.01)
			if mode=="trigger_pressed":trackers[bag.opposite].set_input("trigger",1.)
			if mode=="freehand_occupied":app.services.free=false
			for frame in range(1,36):
				bag.control.global_position=anchor+begin.lerp(end,frame/35.);off.global_position=anchor+begin_other.lerp(end_other,frame/35.);medic.sample_doctor_gestures(.01)
			if mode=="tracking_loss":body.tracking=false
			if mode=="item_swap":bag.held_item=app.items.statepack
			if ability=="reviveplayer":
				off_tracker.set_input("grip",1.)
				for frame in range(80):medic.sample_doctor_gestures(.01)
				off_tracker.set_input("grip",0.);medic.sample_doctor_gestures(.01)
			else:
				for frame in range(20):medic.sample_doctor_gestures(.01)
				for frame in range(1,36):bag.control.global_position=anchor+end+Vector3(.34,0,0)*(frame/35.);medic.sample_doctor_gestures(.01)
				for frame in range(1,36):bag.control.global_position=anchor+end+Vector3(.34,0,0)*(1-frame/35.);medic.sample_doctor_gestures(.01)
				for frame in range(40):medic.sample_doctor_gestures(.01)
			await flush()
			check(treatment_calls().size()==(1 if mode in ["normal","seated","mirror"] else 0),"Actual tracked gesture routing %s: %s"%[ability,mode])
			medic.side="left";medic.hand=hands.left;bag.control=hands.right;bag.opposite="right";medic.boxes.patient=[AABB(Vector3(-.3,0,-2.2),Vector3(.6,1.8,.4))]
	# Geometry remains depth-tested and the production acquisition respects LOS.
	reset();var wall:=StaticBody3D.new();root.add_child(wall);wall.collision_layer=1;var collision:=CollisionShape3D.new();collision.shape=BoxShape3D.new();collision.shape.size=Vector3(3,3,.2);wall.add_child(collision);wall.position=Vector3(0,1,-1);await physics_frame
	check(not open_vats(),"World obstruction blocks friendly medical acquisition");wall.free()
	for side:String in trackers:XRServer.remove_tracker(trackers[side])
	combat.free();medic.free();bag.free();body.free();app.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","mocked_tracking":true,"native_transport":"mocked","headset_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/doctor-routing.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
