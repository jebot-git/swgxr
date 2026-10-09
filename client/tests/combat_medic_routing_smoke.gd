extends SceneTree
const Fixture=preload("res://tests/doctor_routing_smoke.gd")
const Vats=preload("res://medic/doctor_vats.gd")
const Combat=preload("res://combat/ranged_rig.gd")
class Host extends Fixture.App:
	var mutation:=""
	var live_combat:Node
	func api(_method:int,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		if path=="/medic/select":
			medical.state.selected=payload.ability
			match mutation:
				"aim":medical.hand.global_basis=Basis(Vector3.UP,PI)
				"stow":medical.stow()
				"epoch":datapad_epoch+=1
				"relation":medical.state.players[0].healable=false
				"menu_after":medical.wheel.menu_open=true
				"vats_after":medical.button("primary_click",medical.side)
				"menu_roundtrip_after":medical.state.doctor={};medical.state.combat_medic={};medical.button("primary_click",medical.side);medical.button("primary_click",medical.side)
				"stow_redraw_after":medical.stow();medical.held={"id":"focus","tool_kind":"medical"}
				"tracking_after":medical.body.tracking=false
				"cooldown_after":medical.state.abilities[2].cooldown_seconds=5
				"unlearned_after":medical.state.abilities=medical.state.abilities.filter(func(value):return value.id!="healmind")
		return {"ok":success,"state":medical.state.duplicate(true),"mutation":{"success":success},"error":"fixture refusal"}
class Session extends Node:
	var live:=true
	var session_id:="cm-session"
	var actors:Dictionary={}
class Actor extends StaticBody3D:
	var record:Dictionary={"dead":false,"incapacitated":false,"relation":"hostile"}
	func is_targetable()->bool:return not record.dead
	func visual_bounds()->AABB:return AABB(Vector3(-.3,0,-.2),Vector3(.6,1.8,.4))
var checks:=0
var errors:Array=[]
var app:Host
var medic:Node3D
var body:CharacterBody3D
var bag:Node3D
var ui:Node3D
var combat:Node3D
var hands:Dictionary={}
var trackers:Dictionary={}
var baseline:Dictionary={}
var items:Dictionary={}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:create_timer(45).timeout.connect(func():quit(2));call_deferred("run")
func aim(at:Vector3)->void:medic.hand.global_basis=Basis.looking_at((at-medic.hand.global_position).normalized())
func flush()->void:
	await process_frame;await process_frame;await process_frame
func calls(path:String)->Array:return app.calls.filter(func(call):return call.path=="/medic/"+path)
func reset()->void:
	app.calls.clear();app.items=items.duplicate(true);app.success=true;app.mutation="";app.world_ready=true;app.xr_focused=true
	bag.action_pending=false;bag.is_open=false;bag.allowed=true;bag.held_item={};bag.finished.clear();body.tracking=true;body.active=true;body.feedback.blocked=false
	medic.state=baseline.duplicate(true);medic.held={"id":"focus","tool_kind":"medical"};medic.focus_tap_ability="";medic.selected="";medic.age=0;medic.busy=false;medic.controller_allowed=true;medic.wheel.menu_open=false;medic.focus_cast_pending=false;medic.focus_trigger.reset();ui.close();medic.doctor_release_pending=false
	for side:String in trackers:
		trackers[side].set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);trackers[side].set_input("trigger",0.);trackers[side].set_input("grip",0.)
	medic.hand.global_position=Vector3(0,1.3,0);medic.head.global_position=Vector3(0,1.7,0);aim(Vector3(0,1.3,-3))
func open()->bool:return medic.button("primary_click",medic.side) and ui.active()
func entry(id:String)->Dictionary:
	for point:Dictionary in ui.points:
		if point.state==id:return point
	return {}
func tap()->void:medic.sample_focus_trigger(.01,0);medic.sample_focus_trigger(.01,1);medic.sample_focus_trigger(.01,0)
func settle_tap()->void:
	for i in range(31):medic.sample_focus_trigger(.01,0)
func double_tap()->void:tap();tap()
func run()->void:
	app=Host.new();root.add_child(app);body=Fixture.Body.new();root.add_child(body);body.feedback=Fixture.Feedback.new();body.add_child(body.feedback)
	bag=Fixture.Bag.new();root.add_child(bag);app.inventory=bag
	medic=Fixture.Medic.new();root.add_child(medic);medic.set_process(false);medic.app=app;medic.body=body;medic.bag=bag;body.medic=medic;app.medical=medic
	medic.rig=XROrigin3D.new();medic.add_child(medic.rig)
	for side:String in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side+"_hand";tracker.set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(tracker);trackers[side]=tracker
		var hand:=XRController3D.new();hand.name=side.capitalize()+"Hand";hand.tracker=tracker.name;hand.pose="aim";medic.rig.add_child(hand);hands[side]=hand
	medic.side="left";medic.hand=hands.left;bag.control=hands.right;medic.head=Camera3D.new();medic.rig.add_child(medic.head);medic.wheel=Fixture.Wheel.new();medic.add_child(medic.wheel)
	ui=Vats.new();medic.add_child(ui);ui.setup(medic);medic.doctor_vats=ui
	app.scout=Fixture.Scout.new();app.add_child(app.scout);app.services=Fixture.Services.new();app.add_child(app.services)
	combat=Combat.new();root.add_child(combat);combat.set_process(false);combat.set_physics_process(false);combat.body=body;app.combat_rig=combat
	baseline={"character_id":"1","selected":"","abilities":[{"id":"tenddamage","label":"Tend Damage","range_m":6,"cooldown_seconds":0},{"id":"quickheal","label":"Quick Heal","range_m":6,"cooldown_seconds":0},{"id":"healmind","label":"Heal Mind","range_m":5,"cooldown_seconds":0}],"players":[{"id":"patient","name":"Patient","position":[2,0,-3],"healable":true,"dead":false,"states":1,"needs":{"healmind":true,"tenddamage":true,"quickheal":true},"doctor_needs":{"healstate":true}}],"companions":[],"self":{},"doctor":{"healstate":{"learned":true,"range_m":6,"cooldown_seconds":0,"supplies":[{"item_id":"statepack","state":"stunned","state_mask":1,"label":"State Pack","charges":3}]}},"combat_medic":{"abilities":[{"id":"applypoison","learned":true,"cooldown_seconds":0,"action_cost":50,"mind_cost":80},{"id":"applydisease","learned":true,"cooldown_seconds":0,"action_cost":50,"mind_cost":80}],"supplies":[],"targets":[{"id":"enemy","name":"Enemy","position":[0,0,-3],"eligible":true,"dead":false,"relation":"hostile","bounds":{"center":[0,.9,0],"size":[.6,1.8,.4]},"ability_available":{"applypoison":true,"applydisease":true}}]}}
	for ability:String in ["applypoison","applydisease"]:
		for area in [false,true]:
			var id:=ability+("_area" if area else "")
			baseline.combat_medic.supplies.append({"item_id":id,"ability":ability,"label":"Native "+id,"charges":3,"range_m":30.,"area_radius_m":6. if area else 0.,"potency":80.})
			items[id]={"id":id}
	items["statepack"]={"id":"statepack","medical_command":"healstate"};items["focus"]={"id":"focus","tool_kind":"medical"}
	medic.boxes={"patient":[AABB(Vector3(1.7,0,-3.2),Vector3(.6,1.8,.4))],"pet":[AABB(Vector3(-.3,0,-2.2),Vector3(.6,1.8,.4))],"1":[AABB(Vector3(-.3,0,-1.2),Vector3(.6,1.8,.4))]}
	for side:String in ["left","right"]:
		medic.side=side;medic.hand=hands[side]
		for id:String in ["applypoison","applydisease","applypoison_area","applydisease_area"]:
			reset();check(open() and ui.mode=="hostile","Held tool acquires hostile patient mode: "+side+id);check(ui.points.size()==4,"All four single/area variants have distinct markers")
			var point:=entry(id);check(not point.is_empty(),"Specific native delivery is visible: "+id)
			if point.is_empty():continue
			aim(point.position);check(not combat.combat_actions_allowed(),"Offensive medical selection blocks simultaneous weapon fire")
			tap();await flush()
			check(calls("combat_medic").size()==1,"Exactly one delivery request: "+side+id)
			if not calls("combat_medic").is_empty():
				var payload:Dictionary=calls("combat_medic")[0].payload
				check(payload.focus_id=="focus" and payload.item_id==id and payload.target_id=="enemy" and payload.ability==point.ability and payload.pose.tracked,"Exact tool, variant pack, opponent and tracked pose route through medical endpoint")
			check(calls("doctor").is_empty() and calls("heal").is_empty() and bag.finished==[true],"Hostile delivery cannot become friendly healing; native success reconciles inventory")
	medic.side="left";medic.hand=hands.left
	# Native ability_available is per disease type, not per inventory pack. A
	# stronger short-range pack must not hide a usable longer-range variant.
	for variant:String in ["applypoison","applydisease","applypoison_area","applydisease_area"]:
		reset();var distant:Dictionary=medic.state.combat_medic.supplies.filter(func(supply):return supply.item_id==variant)[0]
		var close_pack:=distant.duplicate(true);close_pack.item_id="short_range";close_pack.potency=100.;close_pack.range_m=2.
		app.items.short_range={"id":"short_range"};medic.state.combat_medic.supplies=[close_pack,distant]
		check(open(),"Usable lower-potency pack still acquires target outside stronger pack range: "+variant)
		var point:=entry(variant)
		check(point.get("item_id","")==variant,"Marker chooses strongest pack that actually reaches target: "+variant)
		if not point.is_empty():aim(point.position);tap();await flush()
		check(calls("combat_medic").size()==1 and calls("combat_medic")[0].payload.item_id==variant,"Range-filtered exact supply reaches native endpoint: "+variant)
	reset();var near_pack:Dictionary=medic.state.combat_medic.supplies[0].duplicate(true);near_pack.item_id="near_poison";near_pack.potency=100.;near_pack.range_m=4.
	app.items.near_poison={"id":"near_poison"};medic.state.combat_medic.supplies.append(near_pack);open();var armed_point:=entry("applypoison")
	check(armed_point.get("item_id","")=="near_poison","Highest potency is retained when the exact pack reaches the target")
	if not armed_point.is_empty():aim(armed_point.position);medic.sample_focus_trigger(.01,0);medic.sample_focus_trigger(.01,1)
	medic.state.combat_medic.targets[0].position=[0,0,-5];ui.refresh()
	check(entry("applypoison").get("item_id","")=="applypoison" and ui.pressing.is_empty(),"Moving out of selected pack range cancels press before selecting another pack")
	if not entry("applypoison").is_empty():aim(entry("applypoison").position)
	medic.sample_focus_trigger(.01,0);await flush();check(calls("combat_medic").is_empty(),"Release cannot silently substitute longer-range supply")
	for mode:String in ["no_focus","wrong_tool","pack_only","unlearned","empty","zero_charges","cooldown","out_of_range","friendly","neutral","dead","self","immune","stale","tracking","head_tracking","bag","menu","stow","focus_swap","pack_swap","variant_swap","target_swap","relation_swap","aim_swap","held_trigger","busy","rejected"]:
		reset()
		match mode:
			"no_focus":medic.held={}
			"wrong_tool":medic.held={"id":"focus","tool_kind":"crafting"}
			"pack_only":medic.held={};bag.held_item=items.applypoison
			"unlearned":medic.state.combat_medic.abilities=[]
			"empty":medic.state.combat_medic.supplies=[]
			"zero_charges":medic.state.combat_medic.supplies[0].charges=0
			"cooldown":medic.state.combat_medic.abilities[0].cooldown_seconds=5
			"out_of_range":medic.state.combat_medic.targets[0].position=[0,0,-35]
			"friendly":medic.state.combat_medic.targets[0].relation="friendly"
			"neutral":medic.state.combat_medic.targets[0].eligible=false
			"dead":medic.state.combat_medic.targets[0].dead=true
			"self":medic.state.combat_medic.targets[0].id="1"
			"immune":medic.state.combat_medic.targets[0].ability_available.applypoison=false
			"stale":medic.age=5
			"tracking":trackers.left.invalidate_pose("aim")
			"head_tracking":body.tracking=false
			"bag":bag.is_open=true
			"menu":medic.wheel.menu_open=true
			"busy":medic.busy=true
			"rejected":app.success=false
		open();var point:=entry("applypoison")
		if not point.is_empty():
			aim(point.position)
			if mode!="held_trigger":medic.sample_focus_trigger(.01,0)
			medic.sample_focus_trigger(.01,1)
			match mode:
				"stow":medic.stow()
				"focus_swap":medic.held.id="other_focus"
				"pack_swap":medic.state.combat_medic.supplies[0].item_id="replacement"
				"variant_swap":medic.state.combat_medic.supplies[0].area_radius_m=8.
				"target_swap":medic.state.combat_medic.targets[0].id="other_enemy"
				"relation_swap":medic.state.combat_medic.targets[0].relation="friendly"
				"aim_swap":aim(entry("applydisease").position)
			medic.sample_focus_trigger(.01,0)
		await flush();check(calls("combat_medic").size()==(1 if mode=="rejected" else 0),"Hostile medical route cancellation: "+mode)
		if mode=="rejected":check(bag.finished==[false],"Native rejection does not claim pack use")
	reset();open();medic.sample_focus_trigger(.01,0);aim(entry("applypoison").position);medic.sample_focus_trigger(.01,1);medic.button("primary_click",medic.side);aim(Vector3(2,1.3,-3));medic.button("primary_click",medic.side)
	check(ui.active() and ui.mode=="friendly","Fresh click switches from hostile overlay to friendly condition treatment")
	if not ui.points.is_empty():aim(ui.points[0].position)
	medic.sample_focus_trigger(.01,1);medic.sample_focus_trigger(.01,0);await flush();check(app.calls.is_empty(),"Held hostile squeeze cannot become friendly treatment across mode switch")
	reset();open();trackers.left.set_input("trigger",1.);trackers.right.set_input("trigger",1.);ui.close();check(not combat.combat_actions_allowed(),"Closing hostile markers retains both-trigger weapon release latch")
	trackers.left.set_input("trigger",0.);trackers.right.set_input("trigger",0.);check(combat.combat_actions_allowed(),"Released medical controls restore ordinary combat")
	# Double tap uses the actual existing focus select/heal endpoints, without
	# selecting Heal Mind first or sending an initial Tend Damage.
	for mode:String in ["double","hold","double_after_hold","unlearned","no_need","mind_only","self","pet","droid","hostile","dead","cooldown","stale","aim","stow","epoch","relation","failure","wrong_tool","single","restored_mind","second_hold","menu_after","vats_after","tracking_after","cooldown_after","unlearned_after","single_without_opposite","hold_without_opposite","menu_roundtrip_after","stow_redraw_after"]:
		reset();aim(Vector3(2,1.3,-3))
		match mode:
			"unlearned":medic.state.abilities=medic.state.abilities.filter(func(value):return value.id!="healmind")
			"no_need":medic.state.players[0].needs.healmind=false
			"mind_only":medic.state.players[0].needs.tenddamage=false;medic.state.players[0].needs.quickheal=false
			"self":medic.state.players=[];medic.state.self={"id":"1","healable":true,"dead":false,"position":[0,0,-1],"needs":{"healmind":true}};aim(Vector3(0,1,-1))
			"pet","droid":medic.state.players=[];medic.state.companions=[{"id":"pet","healable":true,"dead":false,"droid":mode=="droid","companion":true,"position":[0,0,-2],"needs":{"healmind":true}}];aim(Vector3(0,1,-2))
			"hostile":medic.state.players[0].healable=false
			"dead":medic.state.players[0].dead=true
			"cooldown":medic.state.abilities[2].cooldown_seconds=5
			"stale":medic.age=5
			"aim","stow","epoch","relation","menu_after","vats_after","tracking_after","cooldown_after","unlearned_after","menu_roundtrip_after","stow_redraw_after":app.mutation=mode
			"failure":app.success=false
			"wrong_tool":medic.held.tool_kind="scanner"
			"restored_mind":medic.selected="healmind";medic.state.selected="healmind"
			"single_without_opposite","hold_without_opposite":trackers["right" if medic.side=="left" else "left"].invalidate_pose("aim");body.tracking=false
		if mode in ["hold","double_after_hold","second_hold","hold_without_opposite"]:
			if mode=="second_hold":tap()
			medic.sample_focus_trigger(.01,0)
			for frame in range(70):medic.sample_focus_trigger(.01,1)
			await flush();medic.sample_focus_trigger(.01,0)
			if mode=="double_after_hold":await flush();app.calls.clear();aim(Vector3(2,1.3,-3));double_tap()
		elif mode in ["single","restored_mind","single_without_opposite"]:tap();check(calls("select").is_empty(),"Single tap waits before selecting Tend Damage");settle_tap()
		else:
			tap();check(calls("select").is_empty(),"First tap never dispatches a preliminary heal: "+mode);tap()
		await flush();settle_tap();await flush();var heals:=calls("heal");var expected:=mode in ["double","hold","double_after_hold","mind_only","pet","single","restored_mind","second_hold","single_without_opposite","hold_without_opposite"]
		check(heals.size()==(1 if expected else 0),"Direct quick healing production dispatch: "+mode)
		if not heals.is_empty():check(heals[0].payload.ability==("quickheal" if mode in ["hold","second_hold","hold_without_opposite"] else "tenddamage" if mode in ["single","restored_mind","single_without_opposite"] else "healmind") and heals[0].payload.item_id=="focus" and (heals[0].payload.pose.tracked or mode in ["single_without_opposite","hold_without_opposite"]),"Correct quick action keeps exact tool and tracked pose: "+mode)
		check(calls("combat_medic").is_empty() and calls("doctor").is_empty(),"Quick healing never uses a VATS marker or hostile endpoint: "+mode)
	# Interruptions between taps cancel the whole sequence, including its delayed
	# Tend Damage. A later squeeze must not inherit the previous patient's tap.
	for mode:String in ["target","tool","epoch","stow","stale","tracking","head_tracking","bag","menu","world","relation","vats","menu_roundtrip","opposite_trigger","opposite_tracking_roundtrip","head_tracking_roundtrip"]:
		reset();aim(Vector3(2,1.3,-3));tap()
		match mode:
			"target":medic.state.players[0].id="other";medic.boxes.other=medic.boxes.patient
			"tool":medic.held.id="other_focus"
			"epoch":app.datapad_epoch+=1
			"stow":medic.stow()
			"stale":medic.age=5
			"tracking":trackers.left.invalidate_pose("aim")
			"head_tracking":body.tracking=false
			"opposite_tracking_roundtrip":
				var other:String="right" if medic.side=="left" else "left"
				trackers[other].invalidate_pose("aim");medic.sample_focus_trigger(.01,0)
				trackers[other].set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
			"head_tracking_roundtrip":body.tracking=false;medic.sample_focus_trigger(.01,0);body.tracking=true
			"bag":bag.is_open=true
			"menu":medic.wheel.menu_open=true
			"world":app.world_ready=false
			"relation":medic.state.players[0].healable=false
			"vats":open();ui.close()
			"menu_roundtrip":medic.state.doctor={};medic.state.combat_medic={};medic.button("primary_click",medic.side);medic.button("primary_click",medic.side)
			"opposite_trigger":medic.doctor_release_pending=true;trackers["right" if medic.side=="left" else "left"].set_input("trigger",1.)
		medic.sample_focus_trigger(.01,1);medic.sample_focus_trigger(.01,0);settle_tap();await flush()
		check(app.calls.is_empty(),"Between-tap invalidation cancels all quick actions: "+mode)
	reset();await medic.select_focus_choice("healmind");check(app.calls.is_empty() and medic.direct_tap_ability()=="tenddamage","Heal Mind no longer becomes a selectable single-tap action")
	medic.state.abilities.append({"id":"firstaid","range_m":6,"cooldown_seconds":0});medic.state.players[0].needs.firstaid=true
	await medic.select_focus_choice("firstaid");app.calls.clear();aim(Vector3(2,1.3,-3));double_tap();await flush()
	check(calls("heal").size()==1 and calls("heal")[0].payload.ability=="healmind","Double tap remains Heal Mind with explicit First Aid fallback")
	app.calls.clear();tap();settle_tap();await flush()
	check(calls("heal").size()==1 and calls("heal")[0].payload.ability=="firstaid","Explicit First Aid single tap survives Heal Mind selection")
	reset();medic.age=100;medic.state.selected="healmind";aim(Vector3(2,1.3,-3));medic.sample_focus_trigger(.01,0)
	await medic.request("status");tap();settle_tap();await flush()
	check(calls("heal").size()==1 and calls("heal")[0].payload.ability=="tenddamage","Restored native Heal Mind selection cannot remap the single-tap control")
	# Real actor collision must be accepted as the target, while actor state
	# invalidation wins immediately over an older medical status response.
	app.live_combat=Session.new();app.add_child(app.live_combat)
	var actor:=Actor.new();root.add_child(actor);actor.position=Vector3(0,0,-3);actor.collision_layer=1;var actor_shape:=CollisionShape3D.new();actor_shape.shape=BoxShape3D.new();actor_shape.shape.size=Vector3(.6,1.8,.4);actor_shape.position=Vector3(0,.9,0);actor.add_child(actor_shape);app.live_combat.actors.enemy=actor;await physics_frame
	for invalidation:String in ["none","dead","friendly","incapacitated"]:
		actor.record={"dead":false,"incapacitated":false,"relation":"hostile"};reset()
		check(open() and ui.mode=="hostile","Native world actor collider remains targetable in medical VATS")
		var point:=entry("applypoison")
		if not point.is_empty():
			aim(point.position);medic.sample_focus_trigger(.01,0);medic.sample_focus_trigger(.01,1)
			if invalidation=="dead":actor.record.dead=true
			if invalidation=="friendly":actor.record.relation="friendly"
			if invalidation=="incapacitated":actor.record.incapacitated=true
			medic.sample_focus_trigger(.01,0)
		await flush();check(calls("combat_medic").size()==(1 if invalidation=="none" else 0),"Current world actor invalidates armed delivery: "+invalidation)
		if invalidation=="none" and not calls("combat_medic").is_empty():check(calls("combat_medic")[0].payload.session_id=="cm-session","Medical delivery preserves active native session identity")
	app.live_combat.actors.clear();actor.free()
	# Actual physics obstruction rejects acquisition and invalidates an armed marker.
	reset();open();aim(entry("applypoison").position);medic.sample_focus_trigger(.01,0);medic.sample_focus_trigger(.01,1)
	var wall:=StaticBody3D.new();root.add_child(wall);wall.collision_layer=1;var collision:=CollisionShape3D.new();collision.shape=BoxShape3D.new();collision.shape.size=Vector3(4,3,.2);wall.add_child(collision);wall.position=Vector3(0,1,-1);await physics_frame
	medic.sample_focus_trigger(.01,0);await flush();check(calls("combat_medic").is_empty(),"New obstruction cancels armed hostile medical delivery");ui.close();aim(Vector3(0,1.3,-3));check(not open(),"World obstruction blocks hostile medical acquisition");wall.free()
	for side:String in trackers:XRServer.remove_tracker(trackers[side])
	combat.free();medic.free();bag.free();body.free();app.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","mocked_tracking":true,"native_transport":"mocked","headset_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/combat-medic-routing.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
