extends Node3D
const Hands=preload("res://scripts/tracked_hand_input.gd")
const Gestures=preload("res://fishing/gestures.gd")
var app:Node
var bag:Node3D
var body:CharacterBody3D
var gestures=Gestures.new()
var bait_ui:Node3D
var line:MeshInstance3D
var float_model:MeshInstance3D
var label:Label3D
var rod:Dictionary={}
var state:Dictionary={}
var allowed:=false
var busy:=false
var opened:=false
var open_requested:=false
var pending_stow:=""
var age:=99.0
var poll:=0.0
var generation:=0
var phase:=0.0
var trigger_down:=true
var last_error:=""
func setup(host:Node,inventory:Node3D)->void:
	app=host;bag=inventory;body=bag.body;process_priority=149
	bait_ui=preload("res://fishing/bait_slots.gd").new();add_child(bait_ui);bait_ui.setup(bag.assets);bait_ui.dropped.connect(load_bait)
	line=MeshInstance3D.new();add_child(line);line.material_override=preload("res://fishing/bait_slots.gd").material(.55)
	float_model=MeshInstance3D.new();float_model.mesh=bag.assets.model("object/tangible/fishing/marker.iff");add_child(float_model)
	label=Label3D.new();label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=22;label.pixel_size=.0004;label.modulate=Color("baffff");label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(label)
	bag.item_held_changed.connect(held_changed);visible=false
func set_allowed(value:bool)->void:
	allowed=value
	if not value:gestures.reset();bait_ui.cancel_drag()
func reset()->void:
	generation+=1;rod={};state={};opened=false;open_requested=false;pending_stow="";age=99;gestures.reset();visible=false
	if is_instance_valid(body):body.fishing_stick_side=""
func owns(id:String)->bool:return not rod.is_empty() and str(rod.id)==id
func busy_hand(side:String)->bool:
	return allowed and not rod.is_empty() and not bag.is_open and side!=bag.held_hand_side()
func held_changed(item:Dictionary)->void:
	var next:Dictionary=item.duplicate(true) if item.get("tool_kind","")=="fishing" else {}
	if str(next.get("id",""))==str(rod.get("id","")):return
	if not rod.is_empty():pending_stow=str(rod.id)
	rod=next;state={};opened=false;open_requested=false;poll=0;age=99;gestures.reset();trigger_down=true
	if not rod.is_empty() and is_instance_valid(bag.held_model):
		# Full original dimensions and original object-origin grip. Source shaft +Y
		# maps to controller aim -Z; no vendor-specific controller offset.
		var model:Node3D=bag.held_model.get_child(0);model.scale=Vector3.ONE;model.position=Vector3.ZERO;model.rotation=Vector3(-PI/2,0,0)
func source(point:Vector3)->Array:
	var p:Vector3=app.source_position_at(point);return [p.x,p.y,p.z]
func world(p:Array)->Vector3:return app.vehicles.world(p)
func pose()->Transform3D:return bag.item_hand_pose(bag.held_controller(),bag.held_controller().global_transform)
func request(action:String,extra:Dictionary={},rod_id:String="")->Dictionary:
	if busy or app.datapad_character_id.is_empty():return {}
	var session:=preload("res://scripts/native_session_identity.gd").id(app)
	if session.is_empty():last_error="Fishing needs a connected Core3 session";return {}
	busy=true;var epoch:int=app.datapad_epoch;var version:=generation
	var id:=rod_id if not rod_id.is_empty() else str(rod.get("id",""))
	var data:Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"rod_id":id,"live_session_id":session,"position":source(body.global_position),"request_id":"fish-%d-%d"%[Time.get_unix_time_from_system()*1000000,Time.get_ticks_usec()]}
	data.merge(extra,true)
	var result:Dictionary=await app.api(HTTPClient.METHOD_POST,"/services/fishing_"+action,data)
	if epoch!=app.datapad_epoch or generation!=version:busy=false;return {}
	if result.get("ok",false) and result.get("source_kind","")=="core3_services" and str(result.get("character_id",""))==app.datapad_character_id and str(result.get("state",{}).get("fishing",{}).get("rod_id",""))==id and str(result.get("state",{}).get("inventory",{}).get("character_id",""))==app.datapad_character_id:
		var snapshot:Dictionary=result.get("state",{})
		if owns(id):state=snapshot.get("fishing",{}).duplicate(true);opened=state.get("equipped",false);age=0
		if snapshot.get("inventory",{}).get("source_kind","")=="core3_inventory":
			app.inventory_snapshot=snapshot.inventory.duplicate(true);app.reconcile_inventory_presentations();app.update_inventory_presentation()
			if action in ["open","stow"]:await app.sync_inventory_equipment()
		if opened or action!="status":last_error=""
	else:last_error=str(result.get("error","Fishing request unconfirmed; checking native state"))
	busy=false;poll=1.0
	if not last_error.is_empty():bag.set_busy(false,last_error)
	return result
func load_bait(item:Dictionary)->void:
	if busy or not opened or state.get("active",false):return
	request("bait",{"bait_id":str(item.id)})
func try_drop(item:Dictionary)->bool:
	if item.get("tool_kind","")!="fishing":return false
	# Releasing the physical rod stows it; it never casts or spends bait.
	pending_stow=str(item.id);bag.finish_item_action(true);return true
func _process(dt:float)->void:
	if not is_instance_valid(app):return
	age+=dt;poll-=dt;phase+=dt
	if not pending_stow.is_empty() and not busy:
		var old:=pending_stow;pending_stow="";request("stow",{},old)
	if rod.is_empty():visible=false;body.fishing_stick_side="";return
	visible=allowed and not bag.is_open and not bag.hologram.active
	if allowed and not busy and pending_stow.is_empty() and poll<=0:
		if not open_requested:open_requested=true;request("open")
		else:request("status")
	var hand:XRController3D=bag.held_controller();var other:XRController3D=bag.tool_pointer_controller();var head:Camera3D=bag.rig.get_node("XRCamera3D")
	var rod_pose:=pose();var local:Transform3D=bag.rig.global_transform.affine_inverse()*rod_pose
	var side:=1.0 if bag.held_hand_side()=="left" else -1.0
	var reel_center:=Vector3(side*.085,-.02,.015)
	var other_local:Vector3=rod_pose.affine_inverse()*other.global_position-reel_center
	var tracked:bool=allowed and body.active and bool(body.combat_tracking_context().tracked) and Hands.controller_tracked(hand) and Hands.controller_tracked(other) and not body.feedback.combat_blocked()
	var permitted:bool=tracked and visible and opened and age<4
	var stage:=int(state.get("stage",0))
	var output:Dictionary=gestures.sample(local,other_local,hand.get_float("trigger"),other.get_float("grip")>.55,dt,permitted,stage,not str(state.get("bait_id","")).is_empty() and not state.get("reward_available",false))
	var released:bool=hand.get_float("trigger")<.25
	var pressed:bool=hand.get_float("trigger")>.65
	if not tracked:trigger_down=true
	elif released:trigger_down=false
	elif pressed and not trigger_down:
		trigger_down=true
		if permitted and state.get("reward_available",false):request("collect")
	if not busy and output.has("cast_direction"):
		var direction:Vector3=bag.rig.global_basis*output.cast_direction;direction.y=0
		var target:=body.global_position+direction.normalized()*float(output.cast_distance)
		var query:=PhysicsRayQueryParameters3D.create(rod_pose.origin,target+Vector3.UP*.2,7)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():request("cast",{"cast_position":source(target)})
		else:last_error="Cast obstructed"
	elif not busy and output.has("gesture"):request("action",{"gesture":output.gesture,"session_id":str(state.get("session_id",""))})
	bait_ui.global_transform=Transform3D(Basis.IDENTITY,rod_pose*Vector3(0,.13,-.18))
	bait_ui.look_at(head.global_position,Vector3.UP,true)
	var tray:bool=permitted and not busy and stage==0
	bait_ui.configure(state.get("baits",[]),str(state.get("bait_status","No bait")),stage==0,str(state.get("bait_template","")))
	bait_ui.visible=visible
	bait_ui.sample(other.global_position,other.get_float("grip"),other.get_vector2("primary"),tray)
	body.fishing_stick_side=("right" if bag.held_hand_side()=="left" else "left") if visible and stage==0 else ""
	label.global_position=rod_pose*Vector3(0,.10,-.06)
	var instructions:="Load bait · hold trigger, swing back/forward, release"
	match stage:
		1:instructions="Watch the float · gentle tugs attract fish"
		2:instructions="Snag · tug up or sideways"
		3:instructions="Nibble · gently tug the rod"
		4:instructions="BITE · lift the rod to set hook"
		5,6,7:instructions="Hooked · grip beside reel and wind offhand"
	if not opened:instructions="Rod not equipped · release and retrieve to retry"
	if state.get("reward_available",false):instructions="Catch ready · click trigger to collect"
	label.text=last_error if not last_error.is_empty() else instructions+"\n"+str(state.get("bait_status",""))+" · "+str(state.get("message",""))
	update_float(rod_pose,stage,dt)
func update_float(rod_pose:Transform3D,stage:int,dt:float)->void:
	var active:bool=state.get("active",false) and state.get("marker",{}).has("position") and age<4
	float_model.visible=active;line.visible=active
	if not active:return
	var target:=world(state.marker.position)
	var dip:=.015*sin(phase*2.5)
	if stage==3:dip-=.05*pow(maxf(0,sin(phase*5)),2)
	elif stage==4:dip-=.14
	target.y+=dip
	if not float_model.has_meta("seeded") or float_model.global_position.distance_to(target)>12:float_model.global_position=target;float_model.set_meta("seeded",true)
	else:float_model.global_position=float_model.global_position.lerp(target,1-exp(-dt*8))
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var start:=rod_pose*Vector3(0,0,-1.12);var end:=float_model.global_position
	for i in 13:
		var t:=float(i)/12;var p:=start.lerp(end,t);p.y-=sin(t*PI)*(.08 if stage>=4 else .2);mesh.surface_add_vertex(to_local(p))
	mesh.surface_end();line.mesh=mesh
