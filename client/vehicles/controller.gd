extends Node3D
## Native Core3 vehicles with tracked, one-hand controls. HMD/controller poses are
## never overwritten: only their shared origin follows the reserved seat.
const HandInput=preload("res://scripts/tracked_hand_input.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
var app: Node
var body: CharacterBody3D
var origin: XROrigin3D
var head: Camera3D
var left: XRController3D
var right: XRController3D
var assets:=Assets.new()
var controls:=SwgVehicleControls.new()
var yokes:=preload("res://vehicles/yoke_visual.gd").new()
var input: Dictionary={"held":false,"throttle":0.0,"steer":0.0,"left_held":false,"right_held":false}
var state: Dictionary={}
var vehicles: Dictionary={}
var seat: Dictionary={}
var origin_floor_offset:=0.0
var origin_in_seat:=Transform3D.IDENTITY
var last_seat:=Transform3D.IDENTITY
var busy:=false
var epoch:=-1
var ejection_revision:=0
var age:=100.0
var grips_released:=true
var triggers: Dictionary={"left":false,"right":false}
var touching: Dictionary={}
var hint: Label3D
var status:=""
var poll_in:=0.0
var pending_call_until:=0.0
var pending_device:=""
var last_category:=""
func setup(host: Node,inventory: Node3D)->void:
	app=host;body=inventory.body;origin=inventory.rig;head=origin.get_node("XRCamera3D");left=origin.get_node("LeftHand");right=origin.get_node("RightHand")
	body.vehicles=self;assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/vehicles/catalog.json"))
	process_physics_priority=-120;process_priority=-120
	hint=Label3D.new();hint.font=load("res://resources/fonts/Jupiteroid-Regular.ttf");hint.font_size=24;hint.pixel_size=.0015;hint.modulate=Color(.5,.9,1,.8);hint.outline_size=5;add_child(hint);hint.visible=false
func reset()->void:
	unseat();state={};pending_call_until=0;pending_device="";poll_in=0;last_category="";ejection_revision=0;age=100;epoch=app.datapad_epoch;touching={};controls.reset()
	for v: Dictionary in vehicles.values():v.node.queue_free();v.view.queue_free()
	vehicles.clear()
func seated()->bool:return not seat.is_empty()
func yoke_transform()->Transform3D:
	var v:Dictionary=vehicles.get(str(seat.get("vehicle_id","")),{})
	if v.is_empty() or not is_instance_valid(v.get("yoke")):return Transform3D.IDENTITY
	var handles:Array=v.record.controls
	var pivot:Vector3=(Vector3(handles[0][0],handles[0][1],handles[0][2])+Vector3(handles[1][0],handles[1][1],handles[1][2]))*.5
	var rotation:=Basis(Vector3.BACK,float(input.get("wheel_angle",0)))
	return Transform3D(rotation,pivot-rotation*pivot)
func hand_target(side:String)->Variant:
	if not seated() or str(seat.id)!="driver" or age>=1 or not bool(input.get(side+"_held",false)):return null
	var v:Dictionary=vehicles.get(str(seat.vehicle_id),{})
	var index:int=int(input.get(side+"_handle",-1))
	if v.is_empty() or index<0 or index>1:return null
	var bases:Array=v.descriptor.get("control_bases",[])
	if bases.size()!=2:return null
	var columns:Array=bases[index];var point:Array=v.record.controls[index]
	var grip:=Transform3D(Basis(Vector3(columns[0][0],columns[0][1],columns[0][2]),Vector3(columns[1][0],columns[1][1],columns[1][2]),Vector3(columns[2][0],columns[2][1],columns[2][2])),Vector3(point[0],point[1],point[2]))
	return v.view.global_transform*yoke_transform()*grip
func hand_busy(side: String)->bool:return bool(input.get(side+"_held",false)) or touching.get("side","")==side
func available(side: String)->bool:
	var bag: Node3D=app.inventory
	if side==body.dominant_hand and ((is_instance_valid(app.combat_rig) and app.combat_rig.selected>=0) or not bag.held_item.is_empty()):return false
	if side==bag.offhand and (bag.interaction_active or (is_instance_valid(app.medic) and not app.medic.held.is_empty())):return false
	return not bag.interaction_active
func source(point: Vector3)->Array:
	var value:Vector3=app.source_position_at(point)
	return [value.x,value.y,value.z]
func world(point: Array)->Vector3:
	var base: Array=app.stage.get_meta("manifest",{}).get("origin",[0,0,0]) if is_instance_valid(app.stage) else [0,0,0]
	var local:=Vector3(float(point[0])-float(base[0]),float(point[1])-float(base[1]),-(float(point[2])-float(base[2])))
	return app.stage.to_global(local) if is_instance_valid(app.stage) else local
func native_session() -> Node:
	if is_instance_valid(app.live_combat) and app.live_combat.live:return app.live_combat
	var gameplay:Variant=app.get("gameplay_session")
	return gameplay if is_instance_valid(gameplay) and bool(gameplay.get("live")) else null
func request(action: String,detail: Dictionary={})->void:
	if busy:
		if action!="status": status="Vehicle request in progress. Try again shortly."
		return
	if app.datapad_character_id.is_empty(): return
	busy=true;var generation: int=app.datapad_epoch
	var source: Vector3=app.source_position_at(body.global_position)
	var payload: Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"position":[source.x,source.y,source.z],"building_id":"0","cell_index":0}
	if is_instance_valid(app.stage) and app.stage.get("current_cell") is Dictionary:
		var cell: Dictionary=app.stage.current_cell;var key:=str(cell.get("cell_id",""))
		if key.contains(":"):payload.building_id=str(cell.get("building_object_id","0"));payload.cell_index=int(key.get_slice(":",1))
	var session:=native_session()
	if session!=null:payload.live_session_id=str(session.session_id)
	payload.merge(detail,true)
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,"/vehicles/"+action,payload)
	busy=false
	if generation!=app.datapad_epoch:return
	if result.get("ok",false) and result.get("state",{}).get("source_kind","")=="core3_vehicles" and str(result.state.get("character_id",""))==app.datapad_character_id:
		var was_seated:=seated();observe(result.state)
		var mutation: Dictionary=result.get("mutation",{})
		if action=="dismount" and was_seated and not seated() and mutation.has("position"):
			body.apply_world_correction(world(mutation.position)-body.global_position)
		if action=="call" and mutation.get("pending",false):pending_call_until=Time.get_ticks_msec()/1000.0+25.0;pending_device=str(detail.get("device_id",""))
		if state.get("datapad",[]).any(func(e):return str(e.get("id",""))==pending_device and e.get("spawned",false)):pending_call_until=0;pending_device=""
		status="Calling vehicle…" if pending_call_until>Time.get_ticks_msec()/1000.0 else ""
		if action.begins_with("pet_"):
			status=("Calling droid…" if action=="pet_call" else "Recalling droid…") if mutation.get("pending",false) else "Droid ready"
	else:status=str(result.get("error","Vehicle action not confirmed"))
	if is_instance_valid(app.datapad) and (action!="status" or not status.is_empty()):app.datapad.ui.set_status(status if not status.is_empty() else "Vehicle ready")
func call_vehicle(entry: Dictionary)->void:
	var generation:int=app.datapad_epoch
	if native_session()==null:
		if not app.has_method("ensure_gameplay_session") or not await app.ensure_gameplay_session():
			status="Vehicle call needs a connected gameplay session. Reconnect and try again."
			if is_instance_valid(app.datapad):app.datapad.ui.set_status(status)
			return
	if generation!=app.datapad_epoch or native_session()==null:return
	await request("call",{"device_id":str(entry.id)})
func recall_vehicle(entry:Dictionary)->void:
	var generation:int=app.datapad_epoch
	if native_session()==null:
		if not app.has_method("ensure_gameplay_session") or not await app.ensure_gameplay_session():
			status="Vehicle recall needs a connected gameplay session. Reconnect and try again."
			if is_instance_valid(app.datapad):app.datapad.ui.set_status(status)
			return
	if generation!=app.datapad_epoch or native_session()==null:return
	await request("recall",{"device_id":str(entry.id)})

func observe(value: Dictionary)->void:
	if value.get("source_kind","")!="core3_vehicles" or str(value.get("character_id",""))!=app.datapad_character_id:return
	var entries_changed: bool=state.get("datapad",[])!=value.get("datapad",[])
	state=value;age=0
	var seen: Dictionary={}
	for record: Dictionary in value.get("vehicles",[]):
		var id:=str(record.id);seen[id]=true
		if not vehicles.has(id):
			var mesh:=assets.model(str(record.template))
			if mesh==null:status="Original vehicle art unavailable";continue
			var node:=CharacterBody3D.new();node.collision_layer=32;node.collision_mask=7;add_child(node)
			var visual:=MeshInstance3D.new();visual.mesh=mesh;add_child(visual)
			var descriptor:Dictionary=assets.descriptor(str(record.template))
			var parts:Dictionary=yokes.meshes(str(record.template),mesh,descriptor)
			var yoke:MeshInstance3D
			if not parts.is_empty():
				visual.mesh=parts.body;yoke=MeshInstance3D.new();yoke.mesh=parts.yoke;visual.add_child(yoke)
			var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();var aabb:=mesh.get_aabb();shape.size=aabb.size;collision.shape=shape;collision.position=aabb.get_center();node.add_child(collision)
			vehicles[id]={"node":node,"view":visual,"smoother":SwgVehicleControls.new(),"record":record,"pose":Transform3D.IDENTITY,"fresh":true,"speed":float(record.speed),"descriptor":descriptor,"yoke":yoke}
		var v: Dictionary=vehicles[id];v.record=record
		v.pose=Transform3D(Basis(Vector3.UP,-float(record.heading_radians)),world(record.position))
		if is_instance_valid(app.stage):v.pose.basis=app.stage.global_basis*v.pose.basis
		if v.fresh:
			v.node.global_transform=v.pose;v.view.global_transform=v.smoother.smooth_pose(v.pose,0,true);v.fresh=false
		if not seated() or str(seat.get("vehicle_id",""))!=id:v.speed=float(record.speed)
	for id: String in vehicles.keys():
		if not seen.has(id):vehicles[id].node.queue_free();vehicles[id].view.queue_free();vehicles.erase(id)
	var next: Dictionary=value.get("seat",{})
	if next!=seat:
		unseat()
		if not next.is_empty() and vehicles.has(str(next.vehicle_id)):board(next)
	var forced: Dictionary=value.get("forced_exit",{})
	if int(forced.get("revision",0))>ejection_revision:
		ejection_revision=int(forced.revision);unseat()
		body.apply_world_correction(world(value.get("position",forced.position))-body.global_position)
		if is_instance_valid(app.get("tracked_avatar")):app.tracked_avatar.reset_life_pose_anchor()
	# Merge only authoritative vehicle entries, retaining waypoints/skills/etc.
	var displayed:Dictionary={}
	var authoritative:Dictionary={}
	if is_instance_valid(app.datapad):
		for entry:Dictionary in app.datapad.ui.entries:
			if entry.get("category","")=="vehicles":displayed[str(entry.id)]=[entry.get("template",""),entry.get("spawned",false)]
	for entry:Dictionary in value.get("datapad",[]):authoritative[str(entry.id)]=[entry.get("template",""),entry.get("spawned",false)]
	if is_instance_valid(app.datapad) and (entries_changed or displayed!=authoritative):
		var entries: Array=app.datapad.ui.entries.filter(func(e):return e.get("category","")!="vehicles" and not e.get("reference_only",false))
		for entry: Dictionary in value.get("datapad",[]):
			var e:=entry.duplicate(true);e.category="vehicles";e.deletable=false;e.description="Called into the world" if e.spawned else "Stored in datapad";entries.append(e)
		var selected_id: String=str(app.datapad.ui.selected_entry.get("id",""))
		app.datapad.ui.set_entries(entries)
		for i in range(app.datapad.ui.filtered_entries.size()):
			if str(app.datapad.ui.filtered_entries[i].id)==selected_id:app.datapad.ui.list.select(i);app.datapad.ui.select_entry(i);break
func seat_pose()->Transform3D:
	var v: Dictionary=vehicles.get(str(seat.get("vehicle_id","")),{})
	if v.is_empty():return last_seat
	for s: Dictionary in v.record.seats:
		if str(s.id)==str(seat.id):return v.view.global_transform*Transform3D(Basis.IDENTITY,Vector3(s.position[0],s.position[1],s.position[2]))
	return last_seat
func board(value: Dictionary)->void:
	body.feedback.remove_offset();origin_floor_offset=origin.global_position.y-body.global_position.y;seat=value.duplicate();controls.reset();last_seat=seat_pose()
	var local_head: Transform3D=origin.global_transform.affine_inverse()*head.global_transform
	var yaw:=atan2(local_head.basis.z.x,local_head.basis.z.z)
	var basis:=last_seat.basis*Basis(Vector3.UP,-yaw)
	origin.global_transform=Transform3D(basis,last_seat.origin+Vector3.UP*.68-basis*local_head.origin)
	origin_in_seat=last_seat.affine_inverse()*origin.global_transform
	body.global_transform=last_seat;body.velocity=Vector3.ZERO;body.ground_control_velocity=Vector2.ZERO
	body._update_locomotion()
func unseat()->void:
	var previous:Dictionary=vehicles.get(str(seat.get("vehicle_id","")),{})
	if is_instance_valid(previous.get("yoke")):previous.yoke.transform=Transform3D.IDENTITY
	if seated() and is_instance_valid(origin):origin.global_position.y=body.global_position.y+origin_floor_offset
	seat={};controls.reset();input={"held":false,"throttle":0.0,"steer":0.0,"left_held":false,"right_held":false}
	if is_instance_valid(body):body.velocity=Vector3.ZERO;body._update_locomotion()
func seat_step()->void:
	if not seated():return
	var current:=seat_pose()
	origin.global_transform=current*origin_in_seat
	body.global_transform=current;body.velocity=Vector3.ZERO;body.on_ground=true;body.near_ground=true
	last_seat=current
func button(name: String,side: String)->bool:
	if seated() and name=="primary_click" and side!=body.dominant_hand:
		request("dismount");return true
	return false
func drive_payload()->Dictionary:
	return {"held":bool(input.held) and age<1.0,"throttle":float(input.throttle) if age<1 else 0.0,"steer":float(input.steer) if age<1 else 0.0}
func _physics_process(delta: float)->void:
	if epoch!=app.datapad_epoch:reset()
	age+=delta;hint.visible=false
	if native_session()==null:
		if seated():unseat()
		return
	var tracking: bool=body.active and bool(body.combat_tracking_context().tracked)
	var lt: bool=tracking and HandInput.controller_tracked(left);var rt: bool=tracking and HandInput.controller_tracked(right)
	if seated():
		var v: Dictionary=vehicles.get(str(seat.vehicle_id),{})
		if v.is_empty():unseat();return
		if str(seat.id)=="driver" and not body.feedback.combat_blocked() and age<1:
			var handles: Array=v.record.controls
			input=controls.sample(str(v.record.kind),v.view.global_transform,left.global_transform,right.global_transform,Vector3(handles[0][0],handles[0][1],handles[0][2]),Vector3(handles[1][0],handles[1][1],handles[1][2]),left.get_float("grip"),right.get_float("grip"),available("left") and lt,available("right") and rt,tracking,(left if body.dominant_hand=="left" else right).get_vector2("primary").y if (lt if body.dominant_hand=="left" else rt) else 0.0)
		else:controls.reset();input={"held":false,"throttle":0.0,"steer":0.0,"left_held":false,"right_held":false}
		touching={}
	else:
		input={"held":false,"throttle":0.0,"steer":0.0,"left_held":false,"right_held":false}
		interaction(lt,rt)
	for id: String in vehicles:
		var v: Dictionary=vehicles[id];var target: Transform3D=v.pose
		if seated() and str(seat.vehicle_id)==id and str(seat.id)=="driver" and age<1:
			var motion: Dictionary=SwgVehicleControls.advance(v.speed,input.throttle,input.steer,v.record.max_speed,v.record.reverse_speed,v.record.acceleration,v.record.turn_rate,delta)
			v.speed=motion.speed;v.node.rotate_y(-float(motion.yaw))
			var collision: KinematicCollision3D=v.node.move_and_collide(-v.node.global_basis.z*float(motion.distance))
			if collision!=null:v.speed=0.0
			# Continue the authoritative trajectory through the same wheel turn.
			# Reconciling to a stale straight heading fought every steering input.
			var prediction_age:=minf(age,.4)
			var predicted_yaw:float=-float(input.steer)*float(v.record.turn_rate)*clampf(float(v.record.speed)/3.0,-1.0,1.0)*prediction_age
			target.origin+=-(target.basis*Basis(Vector3.UP,predicted_yaw*.5)).z*float(v.record.speed)*prediction_age
			target.basis=target.basis*Basis(Vector3.UP,predicted_yaw)
			v.node.global_position=v.node.global_position.lerp(target.origin,1-exp(-delta*5))
			v.node.quaternion=v.node.quaternion.slerp(target.basis.get_rotation_quaternion(),1-exp(-delta*3))
		else:v.node.global_transform=v.node.global_transform.interpolate_with(target,1-exp(-delta*14))

func _process(delta: float)->void:
	if not is_instance_valid(app):return
	poll_in-=delta
	var category:=str(app.datapad.ui.category) if is_instance_valid(app.datapad) and bool(app.datapad.get("is_open")) else ""
	if category=="vehicles" and last_category!="vehicles":poll_in=0
	last_category=category
	var live: bool=native_session()!=null
	if not busy and not app.datapad_character_id.is_empty() and poll_in<=0 and (pending_call_until>Time.get_ticks_msec()/1000.0 or (not live and (category=="vehicles" or not vehicles.is_empty()))):
		if not app.has_method("try_background_poll") or app.try_background_poll("vehicles"):
			poll_in=1.0 if pending_call_until>0 else 3.0
			request("status")
	for v: Dictionary in vehicles.values():
		if native_session()==null:v.node.global_transform=v.node.global_transform.interpolate_with(v.pose,1-exp(-delta*14))
		v.view.global_transform=v.smoother.smooth_pose(v.node.global_transform,delta)
	if seated():
		var v:Dictionary=vehicles.get(str(seat.vehicle_id),{})
		if is_instance_valid(v.get("yoke")):v.yoke.transform=yoke_transform()
		seat_step()

func interaction(lt: bool,rt: bool)->void:
	touching={};var best:=.28
	for id: String in vehicles:
		var v: Dictionary=vehicles[id]
		if absf(float(v.record.speed))>.25:continue
		for s: Dictionary in v.record.seats:
			if not str(s.occupant_id).is_empty() or (str(s.id)=="driver" and not v.record.owned):continue
			var p: Vector3=v.view.to_global(Vector3(s.position[0],s.position[1],s.position[2]))
			for side: String in ["left","right"]:
				var hand: XRController3D=left if side=="left" else right
				if not (lt if side=="left" else rt) or not available(side):continue
				var distance:=hand.global_position.distance_to(p)
				if distance<best:best=distance;touching={"vehicle_id":id,"seat":str(s.id),"side":side,"point":p}
	if not touching.is_empty():
		hint.visible=true;hint.global_position=touching.point+Vector3.UP*.2;hint.text="Trigger · "+str(touching.seat).capitalize();hint.look_at(head.global_position,Vector3.UP,true)
	for side: String in ["left","right"]:
		var hand: XRController3D=left if side=="left" else right
		var pressed: bool=(lt if side=="left" else rt) and hand.get_float("trigger")>.6
		if pressed and not triggers[side] and touching.get("side","")==side and not busy:
			request("board",{"vehicle_id":touching.vehicle_id,"seat":touching.seat,"hand":source(hand.global_position)})
		triggers[side]=pressed
	var grips: bool=lt and rt and available("left") and available("right") and left.get_float("grip")>.65 and right.get_float("grip")>.65
	if not grips:grips_released=true;return
	if not grips_released:return
	grips_released=false
	for v: Dictionary in vehicles.values():
		if not v.record.owned or absf(float(v.record.speed))>.1:continue
		if v.record.seats.any(func(s):return not str(s.occupant_id).is_empty()):continue
		var d: Dictionary=assets.descriptor(str(v.record.template));var lo:=Vector3(d.bounds_min[0],d.bounds_min[1],d.bounds_min[2]);var hi:=Vector3(d.bounds_max[0],d.bounds_max[1],d.bounds_max[2]);var box:=AABB(lo,hi-lo).grow(.1)
		if box.has_point(v.view.to_local(left.global_position)) and box.has_point(v.view.to_local(right.global_position)):
			request("store",{"device_id":str(v.record.device_id),"left":source(left.global_position),"right":source(right.global_position)});return

func rider_pose(race: String)->Dictionary:
	if not seated() or not vehicles.has(str(seat.vehicle_id)):return {}
	var record: Dictionary=vehicles[str(seat.vehicle_id)].record
	for s: Dictionary in record.seats:
		if str(s.id)==str(seat.id):return assets.catalog.get("rider_poses",{}).get(race,{}).get(str(s.rider_pose),{})
	return {}
