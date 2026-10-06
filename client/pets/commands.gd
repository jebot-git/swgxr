extends Node3D
const Hands=preload("res://scripts/tracked_hand_input.gd")
const Targeting=preload("res://medic/targeting.gd")
var app:Node
var host:Node
var vehicles:Node3D
var body:CharacterBody3D
var hand:XRController3D
var head:Camera3D
var side:="left"
var wheel:Node3D
var reticle:MeshInstance3D
var state=preload("res://pets/command_state.gd").new()
var menu_pet:Dictionary={}
var status:=""
var available_now:=false
var stick_latched:=false
func setup(owner:Node)->void:
	host=owner;app=host.app;vehicles=host.vehicles;body=vehicles.body;head=vehicles.head
	side="left" if body.dominant_hand=="right" else "right";hand=vehicles.left if side=="left" else vehicles.right
	wheel=preload("res://combat/ability_hologram.gd").new();add_child(wheel)
	reticle=preload("res://combat/aim_reference.gd").new();add_child(reticle)
	var assets=preload("res://combat/original_assets.gd").new()
	if assets.load_catalog():reticle.configure(assets.texture(assets.catalog.reticle.path))
	body.pet_controls=self;process_physics_priority=-110;process_priority=146
func reset()->void:
	state.reset();menu_pet={};available_now=false;stick_latched=false;status=""
	if is_instance_valid(wheel):wheel.close()
	if is_instance_valid(reticle):reticle.visible=false
	if is_instance_valid(body):body.pet_stick_side=""
func hand_empty()->bool:
	if not vehicles.available(side):return false
	var combat:Variant=app.get("combat_rig")
	if is_instance_valid(combat) and combat.support_latched:return false
	var inventory:Variant=app.get("inventory")
	return not is_instance_valid(inventory) or not inventory.offhand_occupied
func blocks_trigger(controller_side:String)->bool:
	if is_instance_valid(host.get("creature_handler")) and host.creature_handler.claims:return true
	return controller_side==side and (state.captured or (available_now and (wheel.menu_open or not state.selection.is_empty())))
func button(name:String,controller_side:String)->bool:
	if name=="primary_click" and controller_side==side and available_now and wheel.menu_open:
		wheel.close();menu_pet={};stick_latched=hand.get_vector2("primary").length()>=.25;body.pet_stick_side=side if stick_latched else "";return true
	return false
func actor(id:String)->Node3D:
	var live:Variant=app.get("live_combat")
	if is_instance_valid(live) and live.live:
		return live.actors.get(id)
	var sync:Variant=app.get("multiplayer_sync")
	if is_instance_valid(sync) and is_instance_valid(sync.entities):return sync.entities.actors.get(id)
	return null
func touches(row:Dictionary,point:Vector3)->bool:
	var visual:=actor(str(row.id))
	return is_instance_valid(visual) and visual.visible and visual.is_targetable() and visual.visual_bounds().grow(.15).has_point(visual.to_local(point))
func near_pet(point:Vector3)->Dictionary:
	var found:Dictionary={};var nearest:=INF
	for row:Dictionary in vehicles.state.get("pets",[]):
		if not row.get("owned",false) or row.get("dead",false) or row.get("incapacitated",false) or not touches(row,point):continue
		var query:=PhysicsRayQueryParameters3D.create(head.global_position,point,7)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():continue
		var distance:=point.distance_squared_to(vehicles.world(row.position))
		if distance<nearest:nearest=distance;found=row
	return found
func current_pet()->Dictionary:
	for row:Dictionary in vehicles.state.get("pets",[]):
		if str(row.get("device_id",""))==state.device_id and str(row.id)==state.pet_id:return row
	return {}
func aim()->Transform3D:
	var pose:=hand.global_transform
	var combat:Variant=app.get("combat_rig")
	if is_instance_valid(combat) and combat.has_method("controller_weapon_pose"):pose=combat.controller_weapon_pose(hand)
	return pose
static func target_eligible(kind:String,row:Dictionary)->bool:
	var alive:bool=not row.get("dead",false) and not row.get("incapacitated",false)
	match kind:
		"hostile":return alive and row.get("attackable",false)
		"friendly":return alive and row.get("kind","")=="creature" and not row.get("attackable",false)
		"player":return alive and row.get("kind","")=="player" and not row.get("attackable",false)
		"droid":return alive and row.get("droid",false)
		"corpse":return row.get("dead",false) and row.get("kind","")=="creature"
	return false
func candidates()->Array:
	var result:Array=[];var actors:Dictionary={}
	var live:Variant=app.get("live_combat");var sync:Variant=app.get("multiplayer_sync")
	if is_instance_valid(live) and live.live:actors=live.actors
	elif is_instance_valid(sync) and is_instance_valid(sync.entities):actors=sync.entities.actors
	var kind:=str(state.selection.get("target_kind",""))
	for id in actors:
		var visual:Node3D=actors[id];var row:Dictionary=visual.record
		if str(id)==state.pet_id or not visual.visible or not is_instance_valid(visual.visual) or not target_eligible(kind,row):continue
		result.append({"id":str(id),"position":visual.global_position,"bounds":[visual.global_transform*visual.visual_bounds()],"eligible":true})
	if is_instance_valid(sync) and is_instance_valid(sync.players):
		for id in sync.players.peers:
			var peer:Node3D=sync.players.peers[id];var row:Dictionary=peer.row.duplicate(true);row.kind="player"
			if not peer.visible or not is_instance_valid(peer.avatar) or not (target_eligible(kind,row) or (kind=="friendly" and not row.get("dead",false) and not row.get("incapacitated",false) and not row.get("attackable",false))):continue
			result.append({"id":str(id),"position":peer.global_position,"bounds":preload("res://medic/controller.gd").bounds(peer.avatar,true),"eligible":true})
	if kind=="friendly" and is_instance_valid(app.get("avatar")):
		result.append({"id":str(app.datapad_character_id),"position":body.global_position,"bounds":preload("res://medic/controller.gd").bounds(app.avatar,true),"eligible":true})
	return result
func target_id()->String:
	var pose:=aim();var obstruction:=INF
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*64,7))
	if not hit.is_empty():obstruction=pose.origin.distance_to(hit.position)
	var found:Dictionary=Targeting.first(pose,body.global_position,state.selection,candidates(),obstruction)
	return str(found.get("id",""))
func menu_entries(row:Dictionary)->Array:
	var entries:Array=row.get("commands",[]).duplicate(true)
	for option:Dictionary in row.get("creature_handler",{}).get("train_commands",[]):
		entries.append({"id":"ch_train:%d"%int(option.command_id),"command_id":int(option.command_id),"label":"Train "+str(option.label),"action":"ch_train_command","requires_target":false})
	return entries
func reconcile()->void:
	if not state.selection.is_empty():
		var row:=current_pet()
		if row.is_empty() or row.get("dead",false) or row.get("incapacitated",false) or not menu_entries(row).any(func(e):return e.id==state.selection.id):state.clear()
	if wheel.menu_open:
		var rows:Array=vehicles.state.get("pets",[])
		if not rows.any(func(row):return str(row.id)==str(menu_pet.get("id","")) and not row.get("dead",false) and not row.get("incapacitated",false)):wheel.close();menu_pet={}
func frame(trigger:float,stick:Vector2,permitted:bool,nearby:Dictionary)->void:
	available_now=permitted
	var click:bool=state.click(trigger,permitted)
	if not permitted:
		wheel.close();menu_pet={};state.aiming=false;stick_latched=false;body.pet_stick_side="";return
	reconcile()
	if wheel.menu_open:
		var chosen:String=wheel.sample_stick(stick)
		if not chosen.is_empty():
			for entry:Dictionary in menu_entries(menu_pet):
				if str(entry.id)==chosen:state.select(entry,str(menu_pet.device_id),str(menu_pet.id));status="Prepared";break
		elif click:wheel.close()
	elif click and not vehicles.busy:
		if not state.selection.is_empty():
			var target:=target_id() if state.aiming else ""
			var action:=str(state.selection.get("action","pet_command"))
			var proposal:Dictionary=state.activate(target)
			if not proposal.is_empty():
				proposal.request_id="pet-%d"%Time.get_ticks_usec();status="Command requested";vehicles.request(action,proposal)
			elif state.aiming:status="Aim, then click trigger"
		elif not nearby.is_empty():
			menu_pet=nearby.duplicate(true);stick_latched=true;wheel.open_on_hand(menu_entries(menu_pet),hand,head);state.captured=true;status=""
	if not wheel.menu_open and stick.length()<.25:stick_latched=false
	body.pet_stick_side=side if wheel.menu_open or stick_latched else ""
func _physics_process(_delta:float)->void:
	if not is_instance_valid(app):return
	if host.generation!=app.datapad_epoch:reset();return
	var tracked:bool=body.active and bool(body.combat_tracking_context().tracked) and Hands.controller_tracked(hand)
	var grips:bool=vehicles.left.get_float("grip")>.65 and vehicles.right.get_float("grip")>.65
	var permitted:bool=not (is_instance_valid(host.get("creature_handler")) and host.creature_handler.claims) and host.allowed and tracked and hand_empty() and not body.feedback.combat_blocked() and vehicles.age<8 and vehicles.native_session()!=null and not grips
	frame(hand.get_float("trigger"),hand.get_vector2("primary"),permitted,near_pet(hand.global_position) if permitted else {})
func _process(_delta:float)->void:
	if not is_instance_valid(hand):return
	reticle.update_aim(aim(),available_now and state.aiming)
	wheel.update_badge(state.selection,state.aiming,0,hand.global_position+Vector3.UP*.20,available_now,status)
func _exit_tree()->void:
	if is_instance_valid(body):body.pet_controls=null;body.pet_stick_side=""
