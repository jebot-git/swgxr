extends Node3D
const InputRules=preload("res://scout/ranger_input.gd")
const Hands=preload("res://scripts/tracked_hand_input.gd")
const Pointer=preload("res://scripts/rendered_finger_pointer.gd")
var scout:Node3D
var app:Node
var bag:Node3D
var state:Dictionary={}
var recognizer:=SwgRangerGesture.new()
var panel:Node3D
var label:Label3D
var track_type:="animal"
var message:=""
var message_until:=0
var queued:Dictionary={}
var claims:=false
func setup(owner:Node3D)->void:
	scout=owner;app=scout.app;bag=scout.bag;process_physics_priority=-109
	panel=preload("res://scout/ranger_surface.gd").new();add_child(panel);panel.configure(scout.rig,scout.body,scout.offhand);panel.action_requested.connect(action)
	label=Label3D.new();add_child(label);label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=26;label.pixel_size=.0008;label.modulate=Color("b8ffff");label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.hide()
func reset()->void:
	state={};recognizer.reset();track_type="animal";message="";message_until=0;queued={};claims=false
	if is_instance_valid(panel):panel.close_interface()
	if is_instance_valid(label):label.hide()
func blocks_interactions()->bool:return is_instance_valid(panel) and not panel.terminal.is_empty()
func allowed()->bool:
	if not app.world_ready or app.loading_stage or (app.xr_requested and not app.xr_focused) or not scout.body.active or scout.body.feedback.combat_blocked():return false
	for key in ["menu","creator"]:
		var view:Variant=app.get(key)
		if is_instance_valid(view) and view.visible:return false
	return true
func observe(reply:Dictionary)->void:
	if reply.get("ok",false) and reply.get("state",{}).get("ranger") is Dictionary:
		state=reply.state.ranger.duplicate(true)
		if not track_type in state.get("track_types",[]):track_type=str(state.get("track_types",["animal"])[0]) if not state.get("track_types",[]).is_empty() else ""
		if blocks_interactions():panel.show_state(state)
	var mutation:Dictionary=reply.get("mutation",{})
	if not reply.get("ok",false):show_message(str(reply.get("error","Ranger action was not confirmed.")))
	elif str(mutation.get("action",mutation.get("operation","")))=="rescue":
		show_message("Rescue succeeded · attacker distracted" if mutation.get("rescued",false) else "Rescue attempt failed to distract the attacker.")
	elif str(mutation.get("action",mutation.get("operation","")))=="conceal":show_message(str(mutation.get("message","Camouflage applied · CoreCU confirmed")))
func show_message(value:String)->void:
	message=value;message_until=Time.get_ticks_msec()+8000
	if is_instance_valid(panel):panel.panel.message=value;panel.panel.queue_redraw()
func actor(id:String)->Node3D:
	var live:Variant=app.get("live_combat")
	if is_instance_valid(live) and live.live:return live.actors.get(id)
	var sync:Variant=app.get("multiplayer_sync")
	if is_instance_valid(sync) and is_instance_valid(sync.entities):return sync.entities.actors.get(id)
	return null
func rescue_candidates()->Array:
	var result:Array=[]
	for row:Dictionary in state.get("targets",[]):
		if row.get("kind","")!="rescue" or not row.get("eligible",false):continue
		var visual:=actor(str(row.id))
		if is_instance_valid(visual) and visual.visible and visual.is_targetable():result.append({"id":str(row.id),"pose":visual.global_transform,"bounds":visual.visual_bounds(),"eligible":true})
	return result
func finger_target(ray:Dictionary,rows:Array)->String:
	if ray.is_empty():return ""
	var limit:float=float(state.get("rescue_range_m",0))
	var tip:Vector3=ray.tip;var direction:Vector3=ray.direction
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(tip,tip+direction*limit,7))
	return InputRules.target(ray,rows,scout.body.global_position,limit,tip.distance_to(hit.position) if not hit.is_empty() else INF)
func hand(side:String)->Dictionary:
	var controller:XRController3D=scout.rig.get_node(side.capitalize()+"Hand");var optical:=Hands.tracked_joints(side)
	return {"tracked":not optical.is_empty() or Hands.controller_tracked(controller),"pose":scout.rig.global_transform*optical.grip if not optical.is_empty() else controller.global_transform,"pointing":InputRules.pointing(optical.get("joints",{}),Hands.controller_state(controller)),"ray":Pointer.pose(app.get("tracked_avatar"),side,scout.rig,controller)}
func conceal_target(point:Vector3)->Dictionary:
	var sync:Variant=app.get("multiplayer_sync")
	if not is_instance_valid(sync) or not is_instance_valid(sync.players):return {"id":"","blocked":false}
	for id in sync.players.peers:
		var peer:Node3D=sync.players.peers[id]
		if not peer.visible or not is_instance_valid(peer.avatar):continue
		var boxes:Array=preload("res://medic/controller.gd").bounds(peer.avatar,true)
		if not boxes.any(func(box:AABB):return box.grow(.12).has_point(point)):continue
		var eligible:bool=state.get("targets",[]).any(func(row):return str(row.get("id",""))==str(id) and row.get("kind","")=="player" and row.get("eligible",false))
		var occluded:bool=not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(scout.rig.get_node("XRCamera3D").global_position,point,7)).is_empty()
		return {"id":str(id),"blocked":not eligible or occluded}
	return {"id":"","blocked":false}
func conceal(item:Dictionary)->void:
	if scout.busy or not allowed():bag.set_busy(false,"Wait until the current action finishes.");return
	var held:=str(bag.held_item.get("id",""))
	if held!=str(item.get("id","")) or not InputRules.is_kit(item):bag.set_busy(false,"Hold the camouflage kit first.");return
	var sample:=hand(bag.held_hand_side())
	if not sample.tracked:bag.set_busy(false,"Hand tracking is unavailable.");return
	var target:=conceal_target(sample.pose.origin)
	if target.blocked:bag.set_busy(false,"That player cannot be concealed here.");return
	var detail:Dictionary={"item_id":held}
	if not str(target.id).is_empty():
		detail.target_id=str(target.id);var source:Vector3=app.source_position_at(sample.pose.origin);detail.hand_position=[source.x,source.y,source.z]
	var epoch:int=app.datapad_epoch
	var result:Dictionary=await scout.request("conceal",detail)
	if epoch!=app.datapad_epoch:return
	bag.set_busy(false,message if not result.get("ok",false) else "Camouflage applied · CoreCU confirmed")
func action(kind:String,detail:Dictionary={})->void:
	if kind!="area_track" or scout.busy or not allowed():return
	var chosen:=str(detail.get("track_type",track_type))
	if not chosen in state.get("track_types",[]) or state.get("tracking",{}).get("state","")=="pending":return
	track_type=chosen;panel.set_allowed(true);panel.show_state(state);panel.set_pending(true)
	await scout.request("area_track",{"track_type":chosen})
	panel.set_pending(state.get("tracking",{}).get("state","")=="pending")
func _physics_process(delta:float)->void:
	if not is_instance_valid(app):return
	var head:Camera3D=scout.rig.get_node("XRCamera3D");var left:=hand("left");var right:=hand("right")
	var head_tracker=XRServer.get_tracker("head");var head_pose:XRPose=head_tracker.get_pose("default") if head_tracker!=null else null
	var tracked:bool=left.tracked and right.tracked and head_pose!=null and head_pose.has_tracking_data
	var permitted:bool=allowed() and bag.allowed and not bag.is_open and bag.held_item.is_empty() and not bag.offhand_occupied and not blocks_interactions() and scout.last_reply<12
	var vehicle:Variant=app.get("vehicles")
	if is_instance_valid(vehicle) and vehicle.seated():permitted=false
	var pets:Variant=app.get("pets")
	if is_instance_valid(pets) and is_instance_valid(pets.commands) and (pets.commands.wheel.menu_open or not pets.commands.state.selection.is_empty()):permitted=false
	var combat:Variant=app.get("combat_rig")
	if is_instance_valid(combat) and (combat.selected>=0 or combat.support_latched):permitted=false
	var pointing:bool=left.pointing and right.pointing
	var rows:=rescue_candidates() if permitted and pointing else []
	var l:=finger_target(left.ray,rows) if not rows.is_empty() else "";var r:=finger_target(right.ray,rows) if not rows.is_empty() else ""
	var target:=l if l==r else ""
	var mode:="rescue" if pointing else "area_track"
	var eligible:bool=state.get("rescue_available",false) if mode=="rescue" else state.get("area_track_available",false)
	var result:Dictionary=recognizer.sample(delta,mode,target,head.global_transform,left.pose.origin,right.pose.origin,pointing,tracked,permitted and eligible)
	claims=permitted and tracked and (float(result.progress)>0 or bool(result.latched))
	panel.avatar=app.get("tracked_avatar");panel.set_allowed(allowed())
	if Time.get_ticks_msec()>message_until:message=""
	label.visible=allowed() and not blocks_interactions() and (float(result.progress)>0 or not message.is_empty())
	label.global_position=head.global_position-head.global_basis.z*.7+Vector3.DOWN*.2
	label.text=("Rescue · keep pointing" if mode=="rescue" else "Area Track · look left and right")+" · %d%%"%roundi(float(result.progress)*100) if float(result.progress)>0 else message
	if not str(result.action).is_empty():queued={"action":str(result.action),"target":target,"expires":Time.get_ticks_msec()+1500}
	if not queued.is_empty():
		if not permitted or not tracked or not result.latched or queued.target!=target or Time.get_ticks_msec()>int(queued.expires):queued={}
		elif not scout.busy:
			var pending:Dictionary=queued;queued={}
			if pending.action=="rescue":scout.request("rescue",{"target_id":pending.target})
			else:action("area_track")
