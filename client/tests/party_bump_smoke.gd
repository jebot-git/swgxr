extends SceneTree
const Policy=preload("res://scripts/party_bump.gd")
const Fixture=preload("res://tests/entertainer_extension_smoke.gd")
const Harness=preload("res://tests/datapad_equipment_summary_smoke.gd").Harness
class Body extends Fixture.Body:
	var dominant_hand:="right"
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
class Surface extends Node3D:
	var wallet_held:=false
	var terminal:Dictionary={}
	var pointer_pressed:=false
var checks:=0
var errors:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(15).timeout.connect(func():quit(2))
	var policy:=Policy.new()
	check(Policy.hand_sample([0,1,0],true,.9,.9,true).fist,"Free tracked grip plus trigger is a fist")
	for flags in [[false,.9,.9,true],[true,.9,.1,true],[true,.1,.9,true],[true,.9,.9,false]]:
		check(not Policy.hand_sample([0,1,0],flags[0],flags[1],flags[2],flags[3]).fist,"Untracked, open or occupied hand cannot produce fist proof")
	var peer:Dictionary={"id":"456","group_bump_ready":true,"group_bump_id":"0123456789abcdef01234567"}
	var receipt:Dictionary=policy.take_ready("123",[peer])
	check(receipt.get("request_id","")=="bump_0123456789abcdef01234567","Digit-leading native hex gesture ID produces stable receipt")
	check(policy.take_ready("123",[peer]).is_empty(),"Sustained contact cannot resubmit the same proof")
	peer.group_bump_ready=false;policy.take_ready("123",[peer]);peer.group_bump_ready=true
	check(policy.take_ready("123",[peer]).is_empty(),"Staleness or readiness flicker cannot rearm consumed contact")
	peer.group_bump_id="1123456789abcdef01234567"
	check(policy.take_ready("789",[peer]).is_empty() and not policy.take_ready("123",[peer]).is_empty(),"Only lower numeric owner submits; fresh server contact can rearm")
	var app:=Harness.new();root.add_child(app);app.datapad_character_id="123";app.datapad_account="fixture";app.world_ready=true
	app.stage=Fixture.Stage.new();app.add_child(app.stage)
	app.gameplay_session=Fixture.Session.new();app.add_child(app.gameplay_session)
	app.xr_origin=XROrigin3D.new();app.add_child(app.xr_origin)
	var head:=XRCamera3D.new();head.name="XRCamera3D";app.xr_origin.add_child(head);head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;app.xr_origin.add_child(hand)
	var body:=Body.new();app.xr_origin.add_child(body);app.player=body;body.camera=head;body.feedback=Fixture.Fixture.GroundedFeedback.new();body.feedback.configure(body,head)
	app.inventory=preload("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(app.xr_origin,body);app.inventory.set_process(false)
	app.entertainer=preload("res://entertainment/controller.gd").new();app.add_child(app.entertainer);app.entertainer.configure(app,body,app.xr_origin,{"context":{}},"fixture");app.entertainer.set_process(false);app.entertainer.set_physics_process(false);app.entertainer.native.set_process(false);app.entertainer.native.set_physics_process(false)
	app.services=preload("res://scripts/services_controller.gd").new();app.add_child(app.services);app.services.set_process(false);app.services.app=app;app.services.allowed=true;app.services.ui=Surface.new();app.services.add_child(app.services.ui)
	check(app.services.party_hand_free("left") and app.services.party_hand_free("right"),"Both physically free hands are eligible")
	var trackers:Array=[]
	var head_tracker:=XRPositionalTracker.new();head_tracker.name="head";head_tracker.type=XRServer.TRACKER_HEAD;head_tracker.set_pose("default",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker);trackers.append(head_tracker)
	for side in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.name=side+"_hand";tracker.type=XRServer.TRACKER_CONTROLLER;tracker.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(-.3 if side=="left" else .3,1.2,-.4)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",.9);tracker.set_input("trigger",.9);XRServer.add_tracker(tracker);trackers.append(tracker)
		var controller:XRController3D=app.xr_origin.get_node(side.capitalize()+"Hand");controller.tracker=tracker.name;controller.pose="grip"
	await process_frame;await process_frame
	app.services.presence_token="fixture-proof";app.services.state={"player":{"building_id":"77","cell_index":2}}
	app.reply={"ok":true,"source_kind":"authenticated_hand_presence","character_id":"123","peers":[]}
	await app.services.update_presence()
	var packet:Dictionary=app.calls.back().payload
	check(packet.hands.left.fist and packet.hands.right.fist and packet.hand.grip and packet.main_hand_side=="right","Production presence carries either raw tracked fist beside unchanged wallet hand")
	app.services.ui.wallet_held=true;await app.services.update_presence();packet=app.calls.back().payload
	check(packet.wallet_held and packet.hand.grip and not packet.hands.left.free and not packet.hands.right.fist,"Wallet packet retains handshake while excluding party fists")
	app.services.ui.wallet_held=false;XRServer.remove_tracker(head_tracker);await app.services.update_presence();packet=app.calls.back().payload
	check(not packet.hands.left.tracked and not packet.hands.right.fist,"Head tracking loss suppresses both party proofs")
	for tracker in trackers:
		if tracker!=head_tracker:XRServer.remove_tracker(tracker)
	app.calls.clear()

	app.services.ui.wallet_held=true
	check(not app.services.party_hand_free("left") and not app.services.party_hand_free("right"),"Wallet handshake cannot form a party")
	app.services.ui.wallet_held=false;app.inventory.held_item={"id":"prop"};app.inventory.held_side="left"
	check(not app.services.party_hand_free("left") and app.services.party_hand_free("right"),"Held prop blocks only its occupied hand")
	app.inventory.held_item={};app.inventory.held_side=""
	app.inventory.current_equipment=[{"id":"weapon","equipped_slots":["hold_r"]}]
	check(not app.services.party_hand_free("right"),"Unknown equipped hand item remains occupied")
	app.combat_rig=preload("res://combat/ranged_rig.gd").new();app.add_child(app.combat_rig);app.combat_rig.set_process(false);app.combat_rig.set_physics_process(false);app.combat_rig.body=body;app.combat_rig.ability_ui=preload("res://combat/ability_hologram.gd").new();app.combat_rig.add_child(app.combat_rig.ability_ui)
	app.combat_rig.weapons.append({"state":{"profile":{"item_id":"weapon"}}});app.combat_rig.selected=-1
	check(app.services.party_hand_free("right"),"Known physically holstered weapon frees dominant fist despite native hold_r")
	app.combat_rig.selected=0
	check(not app.services.party_hand_free("right") and app.services.party_hand_free("left"),"Drawn weapon blocks dominant fist while free offhand remains eligible")
	app.combat_rig.selected=-1;app.inventory.current_equipment=[]
	app.reply={"ok":true,"source_kind":"core3_entertainer","character_id":"123","sequence":1,"state":{"zone":"tatooine","skills":[],"commands":[],"flourishes":[],"group_id":"789","group_leader_id":"456"},"mutation":{"success":true,"message":"Party formed"}}
	peer.group_bump_id="2123456789abcdef01234567"
	await app.services.consume_party_bumps([peer])
	check(app.calls.size()==1 and app.calls[0].path=="/entertainer/group_bump","Observed authenticated proof requests real native party endpoint")
	check(app.calls[0].payload.request_id=="bump_2123456789abcdef01234567" and app.calls[0].payload.target_id=="456" and app.calls[0].payload.live_session_id=="native-fixture","Party request preserves proof receipt, peer and owner session")
	check(app.entertainer.native.state.group_id=="789" and app.services.party_notice.text=="Party formed" and app.services.party_notice.visible and app.services.poll_clock==0,"Confirmed native membership creates feedback and refreshes wallet/voice group state")
	await app.services.consume_party_bumps([peer]);check(app.calls.size()==1,"Repeated presence cannot duplicate native party mutation")
	check(not app.entertainer.context.entertainer and app.combat_rig.circle_entries({}).any(func(row):return row.id=="group_leave" and row.label=="Leave Party"),"Unarmed circle exposes Leave Party without profession grants")
	check(app.combat_rig.circle_entries({"abilities":[{"id":"last_ditch"}]}).size()==2,"Armed circle retains weapon abilities and adds Leave Party")
	check(app.entertainer.eligible_menu().any(func(row):return row.id=="group_leave"),"Existing performer circle also exposes Leave Party")
	app.combat_rig.abilities=body.combat_pools;body.combat_pools.replace_selection({"id":"last_ditch","activation":"native_ranged"});body.combat_pools.primed=true
	app.combat_rig.select_circle_entry("group_leave",{});await process_frame;await process_frame
	check(body.combat_pools.selected=="last_ditch" and body.combat_pools.primed,"Leave Party does not replace or consume the armed combat ability")
	check(app.calls.back().path=="/entertainer/group_leave","Circle Leave Party uses existing native leave action")
	app.entertainer.native.age=16
	check(not app.combat_rig.circle_entries({}).any(func(row):return row.id=="group_leave"),"Stale native membership cannot invent an available party action")
	app.services.update_party_notice(4);check(not app.services.party_notice.visible,"Confirmation notice expires")
	# Avoid fixture-only dictionary weapon state entering the rig's normal cleanup.
	app.combat_rig.weapons.clear();app.queue_free();await process_frame
	var result:Dictionary={"checks":checks,"passed":errors.is_empty(),"errors":errors,"native_mocked":true,"tracked_input_mocked":true,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/party-bump-client.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result));quit(0 if errors.is_empty() else 1)
