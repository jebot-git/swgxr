extends Node3D
## A free hand held at the chin requests original native creature knowledge.
const Hands=preload("res://scripts/tracked_hand_input.gd")
var scout:Node
var app:Node
var label:Label3D
var candidate:=""
var dwell:=0.0
var latched:=false
var busy:=false
var message_until:=0
func setup(owner:Node)->void:
	scout=owner;app=scout.app
	label=Label3D.new();add_child(label);label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=22;label.pixel_size=.0006;label.width=620;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.hide()
func reset()->void:
	candidate="";dwell=0;latched=false;busy=false;message_until=0
	if is_instance_valid(label):label.hide()
func sample(delta:float,head:Transform3D,hand:Transform3D,grip:float,trigger:float,target:String,permitted:bool)->String:
	var chin:=head.origin-head.basis.y*.15-head.basis.z*.09
	var pondering:bool=permitted and not target.is_empty() and grip>=.65 and trigger<.35 and hand.origin.distance_to(chin)<=.14
	if not pondering:candidate="";dwell=0;latched=false;return ""
	if target!=candidate:candidate=target;dwell=0;latched=false
	if latched:return ""
	dwell+=maxf(0,delta)
	if dwell<.65:return ""
	latched=true;return candidate
func gaze_target(head:Transform3D)->String:
	var actors:Dictionary={}
	if is_instance_valid(app.get("live_combat")) and app.live_combat.live:actors=app.live_combat.actors
	elif is_instance_valid(app.get("multiplayer_sync")) and is_instance_valid(app.multiplayer_sync.entities):actors=app.multiplayer_sync.entities.actors
	var best:="";var nearest:=INF
	for id in actors:
		var actor:Node3D=actors[id]
		if not is_instance_valid(actor) or not actor.visible or actor.record.get("kind","")!="creature" or actor.report.get("appearance_status","")!="complete":continue
		var point:Vector3=actor.to_global(actor.visual_bounds().get_center())
		var ray:Vector3=point-head.origin;var distance:=ray.length()
		if distance<=0 or distance>64 or distance>=nearest or (-head.basis.z).dot(ray/distance)<.985:continue
		var query:=PhysicsRayQueryParameters3D.create(head.origin,point,7,[scout.body.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():continue
		best=str(id);nearest=distance
	return best
func inspect(target:String)->void:
	if busy:return
	busy=true
	var epoch:int=app.datapad_epoch
	var result:Dictionary=await scout.request("inspect",{"target_id":target})
	busy=false
	if epoch!=app.datapad_epoch:return
	var info:Dictionary=result.get("mutation",{}).get("inspection",{})
	if not result.get("ok",false) or str(info.get("id",""))!=target:return
	var lines:PackedStringArray=[str(info.get("name","Creature"))]
	for attribute:Dictionary in info.get("attributes",[]):lines.append(str(attribute.get("name","")).replace("_"," ").capitalize()+": "+str(attribute.get("value","")))
	label.text="\n".join(lines);message_until=Time.get_ticks_msec()+12000
func _physics_process(delta:float)->void:
	if not is_instance_valid(scout) or not is_instance_valid(scout.rig):return
	var permitted:bool=app.world_ready and not app.loading_stage and not app.session_leaving and scout.body.active and not scout.body.feedback.combat_blocked() and scout.last_reply<12 and scout.state.get("inspect_available",false) and not scout.bag.is_open
	if bool(app.get("xr_requested")) and not bool(app.get("xr_focused")):permitted=false
	for key in ["menu","creator"]:
		var view:Variant=app.get(key)
		if is_instance_valid(view) and view.visible:permitted=false
	if is_instance_valid(app.get("datapad")) and app.datapad.is_open:permitted=false
	if is_instance_valid(scout.ranger) and scout.ranger.blocks_interactions():permitted=false
	var head:Camera3D=scout.rig.get_node("XRCamera3D")
	var tracker=XRServer.get_tracker("head");var pose:XRPose=tracker.get_pose("default") if tracker!=null else null
	permitted=permitted and pose!=null and pose.has_tracking_data
	var target:=gaze_target(head.global_transform) if permitted else ""
	var chosen:XRController3D
	for side in ["left","right"]:
		if not scout.bag.held_item.is_empty() and scout.bag.held_hand_side()==side:continue
		if is_instance_valid(app.get("slicing")) and app.slicing.owns_tool() and app.slicing.tool_hand()==scout.bag.controller_for(side):continue
		var combat:Variant=app.get("combat_rig")
		if is_instance_valid(combat) and ((combat.selected>=0 and combat.dominant==side) or (side!=combat.dominant and (combat.offhand_occupied or combat.support_latched))):continue
		var hand:XRController3D=scout.bag.controller_for(side)
		if Hands.controller_tracked(hand) and hand.get_float("grip")>=.65 and hand.global_position.distance_to(head.global_position-head.global_basis.y*.15-head.global_basis.z*.09)<=.14:chosen=hand;break
	var trigger:=sample(delta,head.global_transform,chosen.global_transform if chosen!=null else Transform3D.IDENTITY,chosen.get_float("grip") if chosen!=null else 0,chosen.get_float("trigger") if chosen!=null else 0,target,permitted and chosen!=null)
	if not trigger.is_empty() and not busy and not scout.busy:inspect(trigger)
	label.visible=permitted and Time.get_ticks_msec()<message_until
	if label.visible:label.global_position=head.global_position-head.global_basis.z*.65-Vector3.UP*.17
