extends SceneTree
## Production live-entry, inventory, performer and tracked input; mocked Core3 transport.
const Fixture=preload("res://tests/entertainer_smoke.gd")
class Body extends Fixture.ControlBody:
	var camera:Camera3D
	var dominant_hand:="right"
	var presentation_height:=1.7
	func get_camera()->Camera3D:return camera
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
class NativeStub extends Fixture.NativeStub:
	var state:Dictionary={}
class Stage extends Node3D:
	var current_cell:Dictionary={}
class Harness extends "res://scripts/main.gd":
	var reject:=false
	var calls:Array=[]
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func update_inventory_presentation()->void:pass
	func source_position_at(point:Vector3)->Vector3:return Vector3(point.x,point.y,-point.z)
	func api(_method:HTTPClient.Method,path:String,_payload:Dictionary={})->Dictionary:
		calls.append(path)
		await get_tree().process_frame
		if path=="/combat/session/stop":return {"ok":true}
		if reject:return {"ok":false,"error":"fixture refused entry"}
		return {"ok":true,"backend":"core3","source_kind":"core3_live_combat","character_id":"500","session_id":"fixture","session_live":true,"sequence":1,"snapshot":{"ready":true,"full":true,"truncated":false,"actors":[],"player":{"ham":[900,900,900],"max_ham":[1000,1000,1000],"wounds":[0,0,0],"posture":0,"dead":false,"incapacitated":false,"shock_wounds":0},"weapon":{"item_id":"202","certified":true,"fire_interval_seconds":.2,"max_range_m":64,"projectile_speed":100}}}
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(20).timeout.connect(func():quit(2))
	var app:=Harness.new();root.add_child(app);app.datapad_character_id="500";app.datapad_account="fixture";app.world_ready=true
	app.stage=Stage.new();app.add_child(app.stage)
	app.mode_label=Label.new();app.add_child(app.mode_label);app.asset_status=Label.new();app.add_child(app.asset_status)
	app.xr_origin=XROrigin3D.new();app.add_child(app.xr_origin)
	app.player=Body.new();app.xr_origin.add_child(app.player)
	app.player.camera=XRCamera3D.new();app.player.camera.name="XRCamera3D";app.xr_origin.add_child(app.player.camera);app.player.camera.position.y=1.7
	app.player.feedback=Fixture.GroundedFeedback.new();app.player.feedback.configure(app.player,app.player.camera)
	var trackers:Array=[]
	for side in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.name=side+"_hand";tracker.type=XRServer.TRACKER_CONTROLLER;XRServer.add_tracker(tracker);trackers.append(tracker)
		tracker.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(-.3 if side=="left" else .3,1.3,-.4)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		var hand:=XRController3D.new();hand.name=side.capitalize()+"Hand";hand.tracker=tracker.name;hand.pose="grip";app.xr_origin.add_child(hand)
	app.inventory=preload("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(app.xr_origin,app.player);app.inventory.set_process(false);app.inventory.set_allowed(true)
	app.inventory.item_held_changed.connect(app.inventory_held_changed)
	app.combat_rig=preload("res://combat/ranged_rig.gd").new();app.add_child(app.combat_rig);app.combat_rig.configure(app.player.camera,app.player,[]);app.combat_rig.set_process(false);app.combat_rig.set_physics_process(false)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	var profile:Dictionary=fixture.weapons.pistol_cdef.duplicate(true);profile.source_kind="core3_weapon_instance";profile.item_id="202";profile.certified=true
	app.combat_rig.set_equipped_inventory_weapons([profile])
	app.entertainer=preload("res://entertainment/controller.gd").new();app.add_child(app.entertainer)
	app.entertainer.configure(app,app.player,app.xr_origin,{"context":{"entertainer":true,"complete":true,"commands":["slitherhorn","startmusic+starwars1"]}},"fixture")
	app.entertainer.native.free();app.entertainer.native=NativeStub.new();app.entertainer.add_child(app.entertainer.native)
	check(await app.start_live_combat(),"Production live entry accepts owned mocked native session")
	app.live_combat.set_process(false);app.live_combat.set_physics_process(false)
	check(app.entertainer.can_process(),"Successful live entry restores performer pose/input processing")
	var item:={"id":"instrument","template":"object/tangible/instrument/slitherhorn.iff"}
	for side in ["right","left"]:
		app.inventory.take_item(item,side);await process_frame
		check(not app.entertainer.item.is_empty() and is_instance_valid(app.entertainer.held_model),"Inventory selects original instrument presentation in "+side+" hand")
		var tracker:XRControllerTracker=trackers[1 if side=="right" else 0]
		var pose:=Transform3D(Basis(Vector3.UP,.4),Vector3(-.4 if side=="left" else .4,1.4,-.55));tracker.set_pose("grip",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);await process_frame;await process_frame
		check(app.entertainer.dominant()==side and app.entertainer.hand_target(side) is Transform3D and app.entertainer.hand_target(side).is_equal_approx(app.xr_origin.get_node(side.capitalize()+"Hand").global_transform),"Rendered instrument and attached hand follow fresh physical tracking: "+side)
		app.entertainer.sample_menu(false,Vector2.ZERO,false,true);app.entertainer.sample_menu(true,Vector2.ZERO,false,true)
		check(not app.entertainer.ui.menu_open and not app.entertainer.eligible_menu().any(func(row):return str(row.id).begins_with("music:")),"Inventory-held instrument cannot perform before weapon-slot equip")
		var equipped:=item.duplicate(true);equipped.equipped=true;equipped.equipped_slots=["hold_r"]
		app.entertainer.sync_equipment([equipped]);app.inventory.clear_held();app.entertainer.sample_menu(false,Vector2.ZERO,false,true);app.entertainer.sample_menu(true,Vector2.ZERO,false,true)
		check(app.entertainer.ui.menu_open and app.entertainer.eligible_menu().any(func(row):return str(row.id).begins_with("music:")),"Native weapon-slot instrument opens learned music menu after live entry")
		app.entertainer.ui.close();app.entertainer.active_performance={"id":"fixture"};app.entertainer.since_reply=0
		app.entertainer.sample_menu(false,Vector2.ZERO,false,true);app.entertainer.sample_menu(false,Vector2.ZERO,true,true)
		check(app.entertainer.native.calls.back().action=="flourish","Instrument interaction reaches native request path")
		app.entertainer.active_performance={};app.entertainer.sync_equipment([]);app.inventory.clear_held()
	var offhand:=item.duplicate(true);offhand.equip_slots=["hold_r","hold_l"];offhand.equipped_slots=["hold_l"]
	app.entertainer.sync_equipment([offhand]);app.entertainer.set_item(item)
	check(not app.entertainer.instrument_ready(),"Possible weapon arrangement cannot authorize an instrument actually equipped in offhand")
	app.entertainer.sync_equipment([]);app.entertainer.set_item({})
	var previous_native:Node=app.entertainer.native
	var native:=preload("res://entertainment/native_controller.gd").new();app.entertainer.add_child(native);native.set_process(false);native.set_physics_process(false);native.host=app;native.performer=app.entertainer;native.age=0;app.entertainer.native=native
	var placed:=item.duplicate(true);placed.id="placed";placed.playable=true;placed.position=[0,0,1];placed.building_id="0";placed.cell_index=0
	native.state={"placed_instruments":[placed]}
	check(native.placed_instruments().size()==1 and app.entertainer.eligible_menu().any(func(row):return row.id=="placed:placed"),"Native nearby playable static instrument appears in performance selection")
	placed.placed=true;app.entertainer.set_item(placed)
	check(app.entertainer.instrument_ready() and not is_instance_valid(app.entertainer.held_model) and app.entertainer.hand_target("right")==null,"Placed instrument is usable in place without attachment to either tracked hand")
	app.player.position.x=4
	check(not app.entertainer.instrument_ready() and native.placed_instruments().is_empty(),"Walking beyond native static interaction range blocks further performance")
	app.player.position.x=0;native.state.placed_instruments[0].cell_index=1
	check(not app.entertainer.instrument_ready(),"A nearby instrument across a cell boundary cannot be selected")
	native.free();app.entertainer.native=previous_native;app.entertainer.set_item({})
	app.entertainer.process_mode=Node.PROCESS_MODE_DISABLED;app.inventory.take_item(item)
	check(app.entertainer.hand_target("right")==null and app.inventory.held_model.visible and not app.entertainer.held_model.visible,"Suspended performer cannot pin hand to stale prop or hide inventory fallback")
	app.inventory.clear_held();await app.stop_live_combat();await process_frame
	check(app.entertainer.can_process() and not app.live_combat_reserved,"Stop restores controller lifecycle and releases session reservation")
	app.reject=true
	check(not await app.start_live_combat() and not app.entertainer.can_process(),"Rejected entry keeps native entertainer suspended")
	await app.stop_live_combat();await process_frame;app.reject=false
	check(await app.start_live_combat() and app.entertainer.can_process(),"Reconnect restores instrument controller after an earlier failure")
	await app.stop_live_combat();await process_frame
	for tracker in trackers:XRServer.remove_tracker(tracker)
	app.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"transport":"mocked CoreCU","original_instrument":true,"renderer":"dummy","headset_validated":false}));quit(0 if errors.is_empty() else 1)
