extends SceneTree
const PetFixture=preload("res://tests/pet_commands_smoke.gd")
class Host extends "res://scripts/main.gd":
	var reply:Dictionary={}
	var calls:Array=[]
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func api(_method:HTTPClient.Method,path:String,body:Dictionary={})->Dictionary:
		calls.append({"path":path,"body":body.duplicate(true)});await get_tree().process_frame;return reply.duplicate(true)
class Peer extends Node3D:
	var avatar:Node3D
class Ranger extends "res://scout/ranger.gd":
	var selected_contact:Dictionary={"id":"","blocked":false}
	func conceal_target(_point:Vector3)->Dictionary:return selected_contact.duplicate()
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func inventory(items:Array)->Dictionary:return {"source_kind":"core3_inventory","inventory":{"id":"1","capacity":80,"occupied":items.size()},"items":items,"equipment":[]}
func response(items:Array)->Dictionary:return {"ok":true,"source_kind":"core3_scout","state":{"character_id":"123","inventory":inventory(items),"ranger":{"track_types":["animal"],"tracking":{},"targets":[]}},"mutation":{"action":"conceal","success":true}}
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host);host.world_ready=true;host.loading_stage=false;host.xr_requested=false;host.datapad_character_id="123";host.datapad_account="fixture"
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig);host.player=rig.get_node("PlayerBody");host.player.active=true;host.player.set_physics_process(false)
	var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name="right_hand";tracker.hand=XRPositionalTracker.TRACKER_HAND_RIGHT;tracker.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(.2,1.2,-.4)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",0.0);tracker.set_input("trigger",0.0);XRServer.add_tracker(tracker)
	var bag:=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);host.inventory=bag;bag.configure(rig,host.player);bag.set_process(false);bag.set_allowed(true)
	var scout:=preload("res://scout/controller.gd").new();host.add_child(scout);host.scout=scout;scout.setup(host,bag);scout.set_process(false);scout.epoch=host.datapad_epoch
	scout.ranger.free();var ranger:=Ranger.new();scout.add_child(ranger);scout.ranger=ranger;ranger.setup(scout);ranger.set_process(false);ranger.set_physics_process(false)
	var item:Dictionary={"id":"kit","template":"object/tangible/scout/camokit/camokit_tatooine.iff","tool_kind":"camouflage","charges":3,"quantity":1,"container_id":"1","consumable":true,"consume_available":true}
	host.inventory_snapshot=inventory([item]);bag.set_snapshot(host.inventory_snapshot);bag.take_item(item);bag.is_open=false
	var visual:=bag.held_model
	var remaining:=item.duplicate(true);remaining.charges=2;host.reply=response([remaining])
	bag.update_held_trigger(0,Transform3D.IDENTITY);bag.update_held_trigger(.9,Transform3D.IDENTITY)
	await process_frame;await process_frame
	check(host.calls.size()==1 and host.calls[0].path=="/scout/conceal" and not host.calls[0].body.has("target_id"),"Ordinary profession held-kit trigger requests self conceal through native scout")
	check(bag.held_item.get("charges",0)==2 and bag.held_model==visual and is_instance_valid(visual),"Actual Main reconciliation retains held original model with authoritative remaining charges")
	host.reply={"ok":false,"error":"Kit is for a different planet"};bag.update_held_trigger(0,Transform3D.IDENTITY);bag.update_held_trigger(.9,Transform3D.IDENTITY);await process_frame;await process_frame
	check(bag.held_item.get("charges",0)==2 and bag.held_model==visual and not bag.action_pending,"Rejected wrong-planet use preserves charges/model and releases pending state")
	var before:=host.calls.size();ranger.selected_contact={"id":"other","blocked":true}
	bag.update_held_trigger(0,Transform3D.IDENTITY);bag.update_held_trigger(.9,Transform3D.IDENTITY);await process_frame
	check(host.calls.size()==before and bag.held_item.get("charges",0)==2,"Invalid contacted player never falls back to consuming kit on self")
	ranger.selected_contact={"id":"other","blocked":false};remaining.charges=1;host.reply=response([remaining]);bag.update_held_trigger(0,Transform3D.IDENTITY);bag.update_held_trigger(.9,Transform3D.IDENTITY);await process_frame;await process_frame
	check(host.calls.back().body.target_id=="other" and host.calls.back().body.has("hand_position") and bag.held_item.charges==1,"Valid contacted player receives exact held-kit native request with source hand position")
	ranger.selected_contact={"id":"","blocked":false};host.reply=response([]);bag.update_held_trigger(0,Transform3D.IDENTITY);bag.update_held_trigger(.9,Transform3D.IDENTITY);await process_frame;await process_frame
	check(bag.held_item.is_empty() and not is_instance_valid(bag.held_model),"Last-charge native removal clears held model through actual Main ownership reconciliation")
	var left_tracker:=XRControllerTracker.new();left_tracker.type=XRServer.TRACKER_CONTROLLER;left_tracker.name="left_hand";left_tracker.hand=XRPositionalTracker.TRACKER_HAND_LEFT;left_tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);left_tracker.set_input("grip",1.0);left_tracker.set_input("trigger",0.0);XRServer.add_tracker(left_tracker)
	tracker.set_input("grip",1.0);tracker.set_input("trigger",0.0)
	var head_tracker:=XRPositionalTracker.new();head_tracker.type=XRServer.TRACKER_HEAD;head_tracker.name="head";head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker)
	var sync:=PetFixture.Sync.new();host.add_child(sync);host.multiplayer_sync=sync;sync.entities=PetFixture.World.new();sync.add_child(sync.entities)
	var target:=PetFixture.Actor.new();host.add_child(target);target.position=Vector3(0,0,-3);sync.entities.actors["42"]=target
	ranger.state={"rescue_available":true,"rescue_range_m":32,"targets":[{"id":"42","kind":"rescue","eligible":true}],"track_types":["animal"]};scout.last_reply=0
	var left:XRController3D=rig.get_node("LeftHand");var right:XRController3D=rig.get_node("RightHand");var head:Camera3D=rig.get_node("XRCamera3D")
	left.global_transform=Transform3D(Basis.IDENTITY,Vector3(-.2,1.2,-.4));right.global_transform=Transform3D(Basis.IDENTITY,Vector3(.2,1.2,-.4));head.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
	host.reply=response([]);before=host.calls.size()
	for i in range(95):ranger._physics_process(1.0/90)
	await process_frame;await process_frame
	check(host.calls.size()==before+1 and host.calls.back().path=="/scout/rescue" and host.calls.back().body.target_id=="42","Production two tracked index rays on the same eligible actor execute native Rescue once")
	var pet_controls:=preload("res://pets/controller.gd").new();host.add_child(pet_controls);pet_controls.set_process(false);pet_controls.app=host;host.pets=pet_controls
	check(pet_controls.gesture_claimed(),"Recognized Rescue suppresses the conflicting two-grip pet recall")
	ranger.reset();check(not pet_controls.gesture_claimed(),"Ordinary pet recall remains free when no Ranger gesture claims inputs")
	ranger.reset();ranger.state={"area_track_available":true,"track_types":["animal","npc"],"targets":[],"tracking":{}};scout.last_reply=0
	tracker.set_input("grip",0.0);left_tracker.set_input("grip",0.0);host.reply=response([]);host.reply.state.ranger={"area_track_available":true,"track_types":["animal","npc"],"tracking":{"state":"pending","results":[]}}
	before=host.calls.size()
	for i in range(270):
		var h:=Transform3D(Basis(Vector3.UP,.62*sin(float(i)/90*2.2)),Vector3(0,1.7,0));head.global_transform=h;left.global_position=h*Vector3(-.2,.1,-.15);right.global_position=h*Vector3(.2,-.45,-.4);ranger._physics_process(1.0/90)
	await process_frame;await process_frame
	check(host.calls.size()==before+1 and host.calls.back().path=="/scout/area_track" and host.calls.back().body.track_type=="animal","Production scouting gesture starts native default search immediately")
	check(ranger.blocks_interactions() and ranger.panel.panel.pending and ranger.panel.panel.tracking.state=="pending","Native six-second pending state appears in mutually exclusive tracking interface")
	check(host.entertainer_interaction_blocks(),"Main interaction gate includes the Ranger result interface")
	ranger.panel.set_process(false)
	var completed:=response([]);completed.state.ranger={"area_track_available":true,"track_types":["animal","npc","player"],"tracking":{"state":"succeeded","results":[{"name":"Bantha"}]}}
	ranger.observe(completed)
	check(not ranger.panel.pending and not ranger.panel.panel.pending,"Native completed status clears both XR pointer and visible tracking busy latches")
	before=host.calls.size()
	var filter_hit:Dictionary={"pixel":ranger.panel.panel.type_rect(1).get_center()}
	ranger.panel.pointer_frame(filter_hit,0,0);ranger.panel.pointer_frame(filter_hit,.9,0);ranger.panel.pointer_frame(filter_hit,0,0)
	await process_frame;await process_frame
	check(host.calls.size()==before+1 and host.calls.back().body.track_type=="npc","Actual XR press/release on completed tracking panel requests NPC category")
	ranger.observe(completed);scout.busy=true;before=host.calls.size()
	ranger.panel.pointer_frame(filter_hit,0,0);ranger.panel.pointer_frame(filter_hit,.9,0);ranger.panel.pointer_frame(filter_hit,0,0)
	check(host.calls.size()==before and not ranger.panel.pending,"Filter click during background poll cannot wedge XR input latch")
	scout.busy=false
	var peer:=Peer.new();host.add_child(peer);peer.position=Vector3(0,0,-1.4);peer.avatar=preload("res://scripts/avatar.gd").new();peer.add_child(peer.avatar);peer.avatar.configure("human_male",{})
	sync.players=PetFixture.Players.new();sync.add_child(sync.players);sync.players.peers["other"]=peer
	var actual_ranger:=preload("res://scout/ranger.gd").new();actual_ranger.app=host;actual_ranger.scout=scout;host.add_child(actual_ranger);actual_ranger.set_process(false);actual_ranger.set_physics_process(false);actual_ranger.state={"targets":[{"id":"other","kind":"player","eligible":true}]}
	head.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0));var contact:=peer.global_position+Vector3(0,1.2,0)
	var found:Dictionary=actual_ranger.conceal_target(contact)
	check(found.id=="other" and not found.blocked,"Kit contact targets actual original remote player body geometry")
	actual_ranger.state.targets[0].eligible=false;found=actual_ranger.conceal_target(contact)
	check(found.id=="other" and found.blocked,"Contacted but native-ineligible original player is blocked instead of self fallback")
	actual_ranger.state.targets[0].eligible=true
	var wall:=StaticBody3D.new();wall.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,3,.12);shape.shape=box;wall.add_child(shape);host.add_child(wall);wall.position=Vector3(0,1.2,-.7);await physics_frame;await physics_frame
	found=actual_ranger.conceal_target(contact);check(found.id=="other" and found.blocked,"World collision prevents kit application through a wall")
	XRServer.remove_tracker(left_tracker);XRServer.remove_tracker(head_tracker)
	host.free();XRServer.remove_tracker(tracker);await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"tracking":"mocked controller","target_contact":"mocked selection","native":"mocked responses","controllers":"production inventory scout and Main reconciliation","renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/ranger-inventory-integration.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
