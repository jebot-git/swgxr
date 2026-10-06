extends Node3D
const Hands=preload("res://scripts/tracked_hand_input.gd")
const Target=preload("res://pets/creature_targeting.gd")
var host:Node
var app:Node
var vehicles:Node3D
var recognizer:=SwgCreatureGesture.new()
var label:Label3D
var reticle:MeshInstance3D
var claims:=false
var datapad_reserved:=false
var poll:=0.0
var selected:Dictionary={}
var status:=""
var queued:Dictionary={}
var progress:=0.0
var status_until:=0
var last_taming:=""
var tame_request:=""
var tame_succeeded:=false
func setup(owner:Node)->void:
	host=owner;app=host.app;vehicles=host.vehicles;process_physics_priority=-121
	if vehicles.has_signal("creature_action_finished"):vehicles.connect("creature_action_finished",func(_action:String,message:String):outcome(message))
	label=Label3D.new();add_child(label);label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=26;label.pixel_size=.0008;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=Color("b8ffff");label.hide()
	reticle=preload("res://combat/aim_reference.gd").new();add_child(reticle)
	var assets=preload("res://combat/original_assets.gd").new()
	if assets.load_catalog():reticle.configure(assets.texture(assets.catalog.reticle.path))
func reset()->void:
	recognizer.reset();claims=false;datapad_reserved=false;poll=0;selected={};status="";queued={};progress=0;status_until=0;last_taming="";tame_request="";tame_succeeded=false
	if is_instance_valid(label):label.hide()
	if is_instance_valid(reticle):reticle.hide()
func reserves_datapad()->bool:return datapad_reserved and permitted()
func state()->Dictionary:return vehicles.state.get("creature_handler",{})
func taming_pending(value:Dictionary)->bool:
	return value.get("state","")=="pending" and not (tame_succeeded and str(value.get("request_id",""))==tame_request)
func menu_blocked()->bool:
	return is_instance_valid(host.commands) and (host.commands.wheel.menu_open or not host.commands.state.selection.is_empty())
func permitted()->bool:
	return host.allowed and vehicles.body.active and not vehicles.body.feedback.combat_blocked() and not vehicles.seated() and vehicles.native_session()!=null and vehicles.age<8 and vehicles.available("left") and vehicles.available("right") and not menu_blocked()
func hand(side:String)->Dictionary:
	var controller:XRController3D=vehicles.left if side=="left" else vehicles.right
	var data:=Hands.tracked_joints(side)
	if not data.is_empty():return {"tracked":true,"pose":vehicles.origin.global_transform*data.grip,"fist":Target.fist(data.joints,{})}
	return {"tracked":Hands.controller_tracked(controller),"pose":controller.global_transform,"fist":Target.fist({},Hands.controller_state(controller))}
func actor(id:String)->Node3D:return host.commands.actor(id) if is_instance_valid(host.commands) else null
func candidates()->Array:
	var rows:Array=[]
	for entry:Dictionary in state().get("candidates",[]):
		if not entry.get("eligible",false) or not entry.get("can_tame",false):continue
		var visual:=actor(str(entry.id))
		if not is_instance_valid(visual) or not visual.visible or not visual.is_targetable():continue
		rows.append({"id":str(entry.id),"name":str(entry.get("name","Creature")),"pose":visual.global_transform,"bounds":visual.visual_bounds(),"eligible":true})
	return rows
func gaze()->Dictionary:
	var pose:Transform3D=vehicles.head.global_transform
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*8,7))
	var obstruction:float=pose.origin.distance_to(hit.position) if not hit.is_empty() else INF
	return Target.first(pose,vehicles.body.global_position,candidates(),obstruction)
func mount_contact(left:Transform3D,right:Transform3D)->Dictionary:
	for row:Dictionary in vehicles.state.get("pets",[]):
		if not row.get("owned",false) or not row.get("creature_handler",{}).get("train_mount",false):continue
		var anchor:Variant=Target.head_anchor(actor(str(row.id)))
		if not anchor is Vector3:continue
		var point:Vector3=left.origin if left.origin.distance_to(anchor)<right.origin.distance_to(anchor) else right.origin
		if point.distance_to(anchor)>.25:continue
		if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(vehicles.head.global_position,anchor,7)).is_empty():continue
		return {"id":str(row.id),"device_id":str(row.device_id),"name":row.get("name","Pet"),"anchor":anchor,"hand":point}
	return {}
func outcome(message:String)->void:
	status=message;status_until=Time.get_ticks_msec()+8000
func observe_outcome()->void:
	var taming:Dictionary=state().get("taming",{})
	var request:=str(taming.get("request_id",""))
	if request!=tame_request:tame_request=request;tame_succeeded=false
	if taming.get("state","")=="succeeded" and not request.is_empty():tame_succeeded=true
	var signature:=request+":"+str(taming.get("state",""))
	if signature!=last_taming:
		last_taming=signature
		if taming.get("state","")=="succeeded":outcome("Core3 confirmed: creature tamed and added to your datapad.")
		elif taming.get("state","")=="failed" and not tame_succeeded:outcome("Taming failed. "+str(taming.get("reason",taming.get("message","The creature was not acquired."))))
	if Time.get_ticks_msec()>status_until:status=""
func submit(action:String,detail:Dictionary)->void:
	var epoch:int=app.datapad_epoch
	await vehicles.request(action,detail)
	if epoch==app.datapad_epoch:
		outcome(vehicles.status);observe_outcome()
func _process(delta:float)->void:
	if not is_instance_valid(app):return
	poll-=delta;observe_outcome()
	if host.generation!=app.datapad_epoch:reset();return
	if poll<=0 and host.allowed and vehicles.native_session()!=null and not vehicles.busy and (not app.has_method("try_background_poll") or app.try_background_poll("creature_handler")):
		poll=2;vehicles.request("ch_status")
func _physics_process(delta:float)->void:
	if not is_instance_valid(app):return
	var left:=hand("left");var right:=hand("right")
	var head_pose=XRServer.get_tracker("head");var pose:XRPose=head_pose.get_pose("default") if head_pose!=null else null
	var tracked:bool=pose!=null and pose.has_tracking_data and left.tracked and right.tracked
	var allowed:=permitted() and tracked
	var taming:Dictionary=state().get("taming",{})
	var pending:bool=taming_pending(taming)
	selected=gaze() if allowed and not pending else {}
	var mount:=mount_contact(left.pose,right.pose) if allowed and not pending else {}
	var buff_key:="enrage" if left.pose.origin.y>vehicles.head.global_position.y+.08 and right.pose.origin.y>vehicles.head.global_position.y+.08 else "embolden"
	var buffs:bool=vehicles.state.get("pets",[]).any(func(row):return row.get("owned",false) and not row.get("dead",false) and not row.get("incapacitated",false) and row.get("creature_handler",{}).get(buff_key,false))
	var kind:="buff" if buffs and left.fist>=.7 and right.fist>=.7 else "mount" if not mount.is_empty() else "tame"
	var id:="owned-pets" if kind=="buff" else str(mount.id) if kind=="mount" else str(selected.get("id",""))
	var sample:Dictionary=recognizer.sample(delta,id,kind,vehicles.head.global_transform,left.pose,right.pose,mount.get("anchor",Vector3.INF),tracked,allowed and not pending,left.fist,right.fist)
	progress=float(sample.progress)
	claims=allowed and (progress>0 or bool(sample.latched) or (kind=="buff" and not str(sample.mode).is_empty()))
	# A deliberate two-fist ability owns its opening chord before the wrist UI
	# reaches its shorter hold threshold. Release either fist to reclaim the UI.
	datapad_reserved=allowed and (progress>0 or (kind=="buff" and bool(sample.latched) and left.fist>=.7 and right.fist>=.7))
	show_progress(sample,kind,mount,pending,taming,allowed)
	if not str(sample.action).is_empty():
		var detail:Dictionary={"request_id":"ch-"+Crypto.new().generate_random_bytes(16).hex_encode()}
		if sample.action=="ch_tame":detail.target_id=id
		if sample.action=="ch_train_mount":detail.device_id=mount.device_id;detail.hand=vehicles.source(mount.hand)
		queued={"action":str(sample.action),"detail":detail,"id":id,"expires":Time.get_ticks_msec()+1500}
	if not queued.is_empty():
		if not allowed or queued.id!=id or Time.get_ticks_msec()>int(queued.expires):queued={}
		elif not vehicles.busy:
			submit(str(queued.action),queued.detail);queued={};poll=1

func show_progress(sample:Dictionary,kind:String,mount:Dictionary,pending:bool,taming:Dictionary,allowed:bool)->void:
	reticle.update_aim(vehicles.head.global_transform,not selected.is_empty())
	label.visible=allowed and (pending or not selected.is_empty() or float(sample.progress)>0 or not status.is_empty())
	label.global_position=vehicles.head.global_position-vehicles.head.global_basis.z*.75+Vector3.DOWN*.22
	label.text=("Core3 taming · %d / %d seconds"%[int(taming.get("elapsed_seconds",0)),int(taming.get("duration_seconds",30))]) if pending else status if not status.is_empty() and (progress==0 or bool(sample.latched)) else str(selected.get("name",mount.get("name","Pet")))+"\n"+("Clap or beckon continuously" if kind=="tame" else "Stroke the original head" if kind=="mount" else "Embolden pets · hold fists" if sample.get("mode","")=="ch_embolden" else "Enrage pets · hold fists" if sample.get("mode","")=="ch_enrage" else "Hold fists")+" · %d%%"%roundi(float(sample.progress)*100)
