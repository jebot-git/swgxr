extends Node3D
## Independent offhand medical focus. Native Core3 owns all healing and supplies.
const HandInput=preload("res://scripts/tracked_hand_input.gd")
const Targeting=preload("res://medic/targeting.gd")
const ItemTargeting=preload("res://medic/item_targeting.gd")
const STIMPACK="object/tangible/medicine/stimpack_sm_s1.iff"
var app: Node
var bag: Node3D
var body: CharacterBody3D
var rig: XROrigin3D
var hand: XRController3D
var head: Camera3D
var side: String
var state: Dictionary={}
var held: Dictionary={}
var selected := ""
var focus_tap_ability:=""
var epoch := -1
var busy := false
var next_poll := 0.0
var age := 100.0
var grip_armed := false
var provision_attempted := false
var status := ""
var visual: Node3D
var wheel: Node3D
var reticle: MeshInstance3D
var circle: MeshInstance3D
var people: Dictionary={}
var target: Dictionary={}
var drag_motion := SwgMedicDrag.new()
var drag_target := ""
var drag_revision := 0
var drag_grips_released := true
var next_drag := 0.0
var crossed := false
var bandaging=preload("res://medic/bandaging.gd").new()
var focus_trigger=preload("res://medic/focus_trigger.gd").new()
var focus_cast_pending := false
var focus_generation := 0
var doctor_vats:Node3D
var doctor_motion=preload("res://medic/doctor_gestures.gd").new()
var doctor_release_pending:=false
func setup(host: Node, inventory: Node3D) -> void:
	app=host;bag=inventory;body=bag.body;rig=bag.rig;side=bag.offhand
	hand=rig.get_node("LeftHand" if side=="left" else "RightHand");head=rig.get_node("XRCamera3D")
	wheel=preload("res://combat/ability_hologram.gd").new();add_child(wheel)
	reticle=preload("res://combat/aim_reference.gd").new();add_child(reticle)
	circle=preload("res://medic/range_circle.gd").new();add_child(circle)
	doctor_vats=preload("res://medic/doctor_vats.gd").new();add_child(doctor_vats);doctor_vats.setup(self)
	body.medic=self;process_priority=145
	RenderingServer.frame_pre_draw.connect(pose_tool)
func reset() -> void:
	bandaging.reset()
	doctor_motion.reset()
	drag_motion.reset();drag_target="";drag_revision=0;drag_grips_released=true;crossed=false
	stow();state={};selected="";focus_tap_ability="";epoch=app.datapad_epoch;age=100;next_poll=0;provision_attempted=false
	for avatar in people.values():avatar.queue_free()
	people.clear()
func allowed() -> bool:
	return bag.allowed and app.xr_focused and body.active and not (is_instance_valid(body.get("vehicles")) and body.vehicles.hand_busy(side)) and not body.feedback.combat_blocked() and HandInput.controller_tracked(hand)
func weapon_held() -> bool:
	return is_instance_valid(app.combat_rig) and app.combat_rig.selected>=0
func button(button_name: String, controller_side: String) -> bool:
	if button_name!="primary_click" or controller_side!=side or held.is_empty() or not allowed():return false
	focus_generation+=1;focus_trigger.reset()
	if wheel.menu_open:wheel.close()
	elif is_instance_valid(doctor_vats) and doctor_vats.toggle():pass
	elif not weapon_held():wheel.open_on_hand(state.get("abilities",[]).filter(func(entry):return str(entry.get("id","")) in ["tenddamage","firstaid"]),hand,head)
	return true
func named_ability(name:String) -> Dictionary:
	for entry: Dictionary in state.get("abilities",[]):
		if str(entry.id)==name:return entry
	return {}
func request(action: String, detail: Dictionary={}) -> Dictionary:
	if busy or app.datapad_character_id.is_empty():return {}
	busy=true;var version: int=app.datapad_epoch
	var payload: Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"request_id":"medic-%d"%Time.get_ticks_usec()};payload.merge(detail);payload.pose=tracked_pose()
	var native_id:=preload("res://scripts/native_session_identity.gd").id(app)
	if not native_id.is_empty():payload.session_id=native_id
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,"/medic/"+action,payload)
	busy=false
	if version!=app.datapad_epoch:return {}
	if result.get("ok",false) and result.get("state",{}).get("character_id","")==app.datapad_character_id:
		state=result.state;age=0;selected=str(state.get("selected",""));next_poll=0.65 if bag.held_item.get("medical_item",false) or not held.is_empty() or state.get("self",{}).get("needs",{}).get("firstaid",false) or state.get("players",[]).any(func(person):return person.get("needs",{}).get("firstaid",false)) else 5
		observe_drag(state.get("drag",{}));body.feedback.vital.observe(state.get("vital_feedback",{}));sync_inventory();sync_people();status=""
	else:status=str(result.get("error","Medical action not confirmed"));next_poll=2
	return result
func sync_inventory() -> void:
	if state.get("inventory",{}).get("source_kind","")!="core3_inventory":return
	var previous: Dictionary={}
	for item: Dictionary in app.inventory_snapshot.get("items",[]):previous[str(item.id)]=item.get("attributes",[])
	app.inventory_snapshot=state.inventory.duplicate(true)
	for item: Dictionary in app.inventory_snapshot.get("items",[]):
		if item.get("attributes",[]).is_empty():item.attributes=previous.get(str(item.id),[])
	var hip: Dictionary=state.hip_tool if state.get("hip_tool") is Dictionary else {}
	app.gathering.state["hip_tool"]=hip;bag.set_hip_tool(app.gathering.hip_item())
	if not held.is_empty() and app.owned_inventory_item(str(held.id)).is_empty():stow()
	app.reconcile_inventory_presentations();app.update_inventory_presentation()
func belt_action(action: String,item: Dictionary) -> void:
	var result:=await request(action,{"item_id":str(item.id)})
	bag.finish_item_action(result.get("ok",false))
	if not result.get("ok",false):bag.set_busy(false,status)
func draw(item: Dictionary) -> void:
	if not held.is_empty() or item.get("tool_kind","")!="medical":return
	var model: Node3D=bag.assets.instance(STIMPACK,0.15,{})
	if model==null:status="Original stimpack appearance unavailable";return
	if str(bag.held_item.get("id",""))==str(item.id):bag.clear_held()
	focus_generation+=1;held=item.duplicate(true);visual=Node3D.new();add_child(visual);visual.add_child(model);bag.offhand_occupied=true
	focus_trigger.reset();wheel.close();next_poll=0;app.update_inventory_presentation();pose_tool()
func stow() -> void:
	focus_generation+=1;held={};target={}
	if is_instance_valid(doctor_vats):doctor_vats.close()
	doctor_motion.reset()
	focus_trigger.reset()
	if is_instance_valid(visual):visual.queue_free()
	visual=null
	if is_instance_valid(wheel):wheel.close();wheel.update_badge({},false,0,Vector3.ZERO,false)
	if is_instance_valid(circle):circle.visible=false
	if is_instance_valid(reticle):reticle.visible=false
	if is_instance_valid(bag):bag.offhand_occupied=false
	if is_instance_valid(body):body.medical_stick_side=""
	if is_instance_valid(app) and is_instance_valid(app.inventory):app.update_inventory_presentation()
func pose_tool() -> void:
	if not is_instance_valid(visual):return
	visual.visible=allowed()
	var pose: Transform3D=bag.item_hand_pose(hand,hand.global_transform)
	if is_instance_valid(app.combat_rig) and is_instance_valid(app.combat_rig.tracked_avatar):
		var skeleton: Skeleton3D=app.combat_rig.tracked_avatar.skeleton
		var hold:=skeleton.find_bone("hold_l" if side=="left" else "hold_r")
		if hold>=0:pose=skeleton.global_transform*skeleton.get_bone_global_pose(hold);pose.basis=pose.basis.orthonormalized()
	# Preserve the presentation scale imported for the original stimpack.
	visual.global_transform=pose
	if is_instance_valid(bag.hip_model) and str(bag.hip_tool.get("id",""))==str(held.get("id","")):bag.hip_model.visible=false
func aim() -> Transform3D:
	var pose: Transform3D=bag.item_hand_pose(hand,hand.global_transform)
	if is_instance_valid(visual):pose.origin=visual.global_position
	return pose
static func bounds(avatar: Node3D, exclude_hands := false) -> Array:
	var result: Array=[]
	if not is_instance_valid(avatar):return result
	if is_instance_valid(avatar.skeleton):
		for i in range(avatar.skeleton.get_bone_count()):
			var bone: String=avatar.skeleton.get_bone_name(i)
			if exclude_hands and ["hand","hold","finger","thumb","index","middle","ring","pinky"].any(func(part):return bone.contains(part)):continue
			var p: Vector3=(avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(i)).origin
			var extent:=0.12
			result.append(AABB(p-Vector3.ONE*extent,Vector3.ONE*extent*2))
	return result
func sync_people() -> void:
	var seen: Array=[]
	for person: Dictionary in state.get("players",[]):
		var id:=str(person.id);seen.append(id)
		if not people.has(id):
			var avatar:=preload("res://scripts/avatar.gd").new();add_child(avatar)
			var report: Dictionary=avatar.configure(str(person.race),{"height":float(person.get("height",1)),"customization":person.get("customization",{})})
			if not str(report.get("error","")).is_empty():avatar.queue_free();continue
			people[id]=avatar
		people[id].global_transform=Transform3D(Basis(Vector3.UP,-float(person.heading_radians)),app.scout.world(person.position))
	for id in people.keys():
		if id not in seen:people[id].queue_free();people.erase(id)
func candidates(entry: Dictionary) -> Array:
	var result: Array=[]
	var action:=str(entry.get("id",""))
	var rows:Array=state.get("players",[])+[state.get("self",{})]
	if action in ["healdamage","healmind"]:rows.append_array(state.get("companions",[]))
	for person: Dictionary in rows:
		if person.is_empty():continue
		var id:=str(person.id);var self_target: bool=id==app.datapad_character_id
		var boxes:=patient_bounds(person)
		if boxes.is_empty():continue
		result.append({"id":id,"name":str(person.get("name","")),"position":body.global_position if self_target else app.scout.world(person.position),"bounds":boxes,"eligible":person.get("healable",false) and not person.get("dead",false) and person.get("needs",{}).get(action,false) and not (action=="healmind" and (self_target or person.get("droid",false)))})
	return result
func update_target(delta: float) -> void:
	if reticle.mesh==null and is_instance_valid(app.combat_rig):reticle.configure(app.combat_rig.assets.texture(app.combat_rig.assets.catalog.reticle.path))
	var supply_ability:=str(bag.held_item.get("medical_command",""))
	if supply_ability in ["reviveplayer","extinguishfire"]:
		var controller:XRController3D=bag.held_controller();var entry:=doctor_entry(supply_ability)
		var hint:="Place both pads on the chest · Squeeze free grip, hold, release" if supply_ability=="reviveplayer" else "Place blanket on torso · Sweep across, return and settle"
		reticle.visible=false;circle.visible=false
		wheel.update_badge({"source_command":"revivePlayer" if supply_ability=="reviveplayer" else "extinguishFire","label":str(bag.held_item.get("name","Medical supply"))},false,float(entry.get("cooldown_seconds",0)),controller.global_position+Vector3.UP*.15,doctor_allowed(),status if not status.is_empty() else hint)
		return
	if is_instance_valid(doctor_vats) and doctor_vats.active():
		reticle.update_aim(aim(),true)
		var hostile:bool=doctor_vats.mode=="hostile"
		var point:Dictionary=doctor_vats.hit(aim());var row:Dictionary=doctor_vats.person(doctor_vats.target_id)
		circle.update_circle(app.scout.world(row.get("position",[0,0,0])),float(point.get("area_radius_m",0)),hostile and not point.is_empty() and float(point.get("area_radius_m",0))>0,delta)
		var ability:=str(point.get("ability","healstate"));var entry:Dictionary=combat_medic_entry(ability) if hostile else doctor_entry("healstate")
		wheel.update_badge({"source_command":ability,"label":"Delivery" if hostile else "Treat Condition"},false,float(entry.get("cooldown_seconds",0)),hand.global_position+Vector3.UP*.15,true,status if not status.is_empty() else "Aim at a delivery · Squeeze and release · Click to close" if hostile else "Aim at a condition · Squeeze and release to treat · Click to close")
		return
	if update_supply_target(delta):return
	var tap:=direct_tap_ability();var entry:=named_ability(tap);var showing:=direct_focus_permitted()
	if focus_trigger.pressing:entry=named_ability("healmind" if focus_trigger.second and not named_ability("healmind").is_empty() else "quickheal")
	reticle.update_aim(aim(),showing)
	target={}
	if showing:
		target=focus_recipient()
	circle.update_circle(target.get("position",Vector3.ZERO),float(entry.get("area_radius_m",0)),showing and not target.is_empty(),delta)
	var hint:=str(target.get("name","Aim at a recipient"))+" · Tap: "+str(named_ability(tap).get("label","Tend Damage"))+" · Hold: Quick Heal"
	if not named_ability("healmind").is_empty():hint+=" · Double tap: Heal Mind (transfers your Mind)"
	if focus_trigger.pressing:
		hint=("Release: Heal Mind · " if focus_trigger.second and not named_ability("healmind").is_empty() else "")+"Hold for Quick Heal · %d%%"%roundi(clampf(focus_trigger.elapsed/focus_trigger.HOLD_SECONDS,0,1)*100)
	elif doctor_entry("healstate").get("learned",false) or not state.get("combat_medic",{}).get("abilities",[]).is_empty():hint+=" · Click target: Medical options"
	wheel.update_badge(entry,false,float(entry.get("cooldown_seconds",0)),hand.global_position+Vector3.UP*0.15,showing,status if not status.is_empty() else hint)
func update_supply_target(delta:float)->bool:
	var item:Dictionary=bag.held_item
	if not item.get("medical_ranged",false):return false
	var controller:XRController3D=bag.held_controller()
	var showing:bool=age<3 and body.active and app.xr_focused and HandInput.controller_tracked(controller) and not body.feedback.combat_blocked() and not bag.is_open
	var entry:Dictionary={"id":"healdamage","label":str(item.get("name","Ranged stim")),"range_m":float(item.get("medical_range_m",0)),"area_radius_m":float(item.get("medical_area_m",0))}
	var pose:Transform3D=bag.item_hand_pose(controller,controller.global_transform)
	reticle.update_aim(pose,showing);target={}
	if showing:
		var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*(float(entry.range_m)+2),7,[body.get_rid()]))
		var obstruction:float=pose.origin.distance_to(hit.position) if not hit.is_empty() else INF
		target=Targeting.first(pose,body.global_position,entry,candidates(entry),obstruction)
	circle.update_circle(target.get("position",Vector3.ZERO),float(entry.area_radius_m),showing and not target.is_empty(),delta)
	wheel.update_badge(entry,false,float(state.get("medical_item_cooldowns",{}).get("healdamage",0)),controller.global_position+Vector3.UP*.15,showing,str(target.get("name","Aim at an injured patient")))
	return true
func use_wound_pack(item:Dictionary)->void:
	await use_medical_item(item)
func use_medical_item(item:Dictionary)->void:
	var controller:XRController3D=bag.held_controller()
	if busy or not body.active or not app.xr_focused or not HandInput.controller_tracked(controller) or body.feedback.combat_blocked():
		bag.finish_consumable_action({},false);bag.set_busy(false,"Medical treatment is unavailable.");return
	if age>=2:await request("status")
	if age>=3 or not body.active or not app.xr_focused or not HandInput.controller_tracked(controller) or str(bag.held_item.get("id",""))!=str(item.id):
		bag.finish_consumable_action({},false);return
	var recipient:Dictionary={};var nearest:=INF
	var ranged_candidates:Array=[]
	for person:Dictionary in state.get("players",[])+state.get("companions",[])+[state.get("self",{})]:
		if not ItemTargeting.eligible(item,person):continue
		var own:bool=str(person.id)==str(app.datapad_character_id)
		var avatar:Node3D=app.avatar if own else people.get(str(person.id))
		var boxes:Array=bounds(avatar,own)
		if person.get("companion",false):
			var actor:Node3D
			if is_instance_valid(app.live_combat) and app.live_combat.live:actor=app.live_combat.actors.get(str(person.id))
			elif is_instance_valid(app.get("multiplayer_sync")) and is_instance_valid(app.multiplayer_sync.entities):actor=app.multiplayer_sync.entities.actors.get(str(person.id))
			if is_instance_valid(actor):boxes=[actor.global_transform*actor.visual_bounds()]
		ranged_candidates.append({"id":str(person.id),"name":str(person.get("name","")),"position":body.global_position if own else app.scout.world(person.position),"bounds":boxes,"eligible":true})
		for box:AABB in boxes:
			var distance:float=controller.global_position.distance_squared_to(box.get_center())
			if box.grow(.18).has_point(controller.global_position) and distance<nearest:
				nearest=distance;recipient=person
	if recipient.is_empty() and item.get("medical_ranged",false):
		var pose:Transform3D=bag.item_hand_pose(controller,controller.global_transform)
		var distance:float=float(item.get("medical_range_m",0))
		var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*(distance+2),7,[body.get_rid()]))
		var obstruction:float=pose.origin.distance_to(hit.position) if not hit.is_empty() else INF
		recipient=Targeting.first(pose,body.global_position,{"range_m":distance},ranged_candidates,obstruction)
	if recipient.is_empty():
		bag.finish_consumable_action({},false);bag.set_busy(false,"Touch a patient needing this supply and trigger. Ranged stims can be aimed at a patient.");return
	var result:Dictionary=await request("medical_item",{"item_id":str(item.id),"target_id":str(recipient.id)})
	var success:bool=result.get("ok",false) and result.get("mutation",{}).get("success",false)
	bag.finish_consumable_action(app.owned_inventory_item(str(item.id)).duplicate(true) if success else {},success)
	if not success:bag.set_busy(false,str(result.get("error","Medical item treatment was not confirmed.")))

func focus_permitted()->bool:
	return app.world_ready and allowed() and not held.is_empty() and age<3 and not bag.is_open and not wheel.menu_open and not bag.action_pending and not focus_cast_pending
func captures_combat()->bool:
	if is_instance_valid(doctor_vats) and doctor_vats.active():return true
	if doctor_release_pending and is_instance_valid(rig):
		for hand_name in ["LeftHand","RightHand"]:
			var controller:XRController3D=rig.get_node(hand_name)
			if not HandInput.controller_tracked(controller) or controller.get_float("trigger")>=.25:return true
		doctor_release_pending=false
	return false
func patient_bounds(person:Dictionary)->Array:
	var own:bool=str(person.get("id",""))==str(app.datapad_character_id)
	if not person.get("companion",false):return bounds(app.avatar if own else people.get(str(person.get("id",""))),own)
	var actor:Node3D
	if is_instance_valid(app.get("live_combat")) and app.live_combat.live:actor=app.live_combat.actors.get(str(person.id))
	elif is_instance_valid(app.get("multiplayer_sync")) and is_instance_valid(app.multiplayer_sync.entities):actor=app.multiplayer_sync.entities.actors.get(str(person.id))
	return [actor.global_transform*actor.visual_bounds()] if is_instance_valid(actor) else []
func medical_ui_closed()->bool:
	if app.get("loading_stage")==true or app.get("session_leaving")==true or wheel.menu_open or (is_instance_valid(bag.get("hologram")) and bag.hologram.active):return false
	for key in ["datapad","crafting"]:
		var ui:Variant=app.get(key)
		if is_instance_valid(ui) and ui.get("is_open")==true:return false
	return true
func doctor_allowed()->bool:
	if not app.world_ready or not body.active or not app.xr_focused or body.feedback.combat_blocked() or not bag.allowed or bag.is_open or bag.action_pending or age>=3 or not medical_ui_closed():return false
	var left:XRController3D=rig.get_node("LeftHand");var right:XRController3D=rig.get_node("RightHand")
	if body.has_method("combat_tracking_context") and not body.combat_tracking_context().get("tracked",false):return false
	return HandInput.controller_tracked(left) and HandInput.controller_tracked(right) and tracked_pose().tracked
func doctor_entry(ability:String)->Dictionary:return state.get("doctor",{}).get(ability,{})
func combat_medic_entry(ability:String)->Dictionary:
	for entry:Dictionary in state.get("combat_medic",{}).get("abilities",[]):
		if str(entry.get("id",""))==ability:return entry
	return {}
func combat_medic_actor(id:String)->Node3D:
	if is_instance_valid(app.get("live_combat")) and app.live_combat.live:return app.live_combat.actors.get(id)
	if is_instance_valid(app.get("multiplayer_sync")) and is_instance_valid(app.multiplayer_sync.entities):return app.multiplayer_sync.entities.actors.get(id)
	return null
func combat_medic_target_valid(person:Dictionary)->bool:
	if str(person.get("id",""))==app.datapad_character_id or not person.get("eligible",false) or person.get("dead",false) or person.get("relation","") not in ["hostile","attackable"]:return false
	var actor:=combat_medic_actor(str(person.get("id","")))
	if not is_instance_valid(actor):return true
	if actor.has_method("is_targetable") and not actor.is_targetable():return false
	var record:Variant=actor.get("record")
	return not (record is Dictionary) or (not record.get("dead",false) and not record.get("incapacitated",false) and record.get("relation",person.relation) in ["hostile","attackable"])
func combat_medic_bounds(person:Dictionary)->Array:
	var actor:=combat_medic_actor(str(person.get("id","")))
	if is_instance_valid(actor):return [actor.global_transform*actor.visual_bounds()]
	var avatar:Node3D=people.get(str(person.get("id","")))
	if is_instance_valid(avatar):return bounds(avatar)
	var box:Dictionary=person.get("bounds",{});var center:Array=box.get("center",[]);var size:Array=box.get("size",[])
	if center.size()!=3 or size.size()!=3:return []
	var local:=Vector3(float(center[0]),float(center[1]),-float(center[2]));var extent:=Vector3(float(size[0]),float(size[1]),float(size[2]))
	if not local.is_finite() or not extent.is_finite() or extent.x<=0 or extent.y<=0 or extent.z<=0:return []
	var pose:=Transform3D(Basis(Vector3.UP,-float(person.get("heading_radians",0))),app.scout.world(person.position))
	return [pose*AABB(local-extent*.5,extent)]
func cast_combat_medic(ability:String,item_id:String,target_id:String,focus_id:String)->void:
	if busy or not doctor_allowed() or not focus_permitted() or focus_id.is_empty() or str(held.get("id",""))!=focus_id or held.get("tool_kind","")!="medical":return
	if not is_instance_valid(doctor_vats) or not doctor_vats.active() or doctor_vats.mode!="hostile" or doctor_vats.target_id!=target_id:return
	var entry:=combat_medic_entry(ability)
	if ability not in ["applypoison","applydisease"] or not entry.get("learned",false) or float(entry.get("cooldown_seconds",0))>0:return
	doctor_vats.refresh()
	var point:Dictionary=doctor_vats.hit(aim())
	if point.get("item_id","")!=item_id or point.get("target_id","")!=target_id or point.get("ability","")!=ability:return
	if app.owned_inventory_item(item_id).is_empty():return
	bag.begin_mutation("Applying poison…" if ability=="applypoison" else "Applying disease…")
	var version:int=app.datapad_epoch
	var result:=await request("combat_medic",{"ability":ability,"focus_id":focus_id,"item_id":item_id,"target_id":target_id})
	if version!=app.datapad_epoch:return
	var success:bool=result.get("ok",false) and result.get("mutation",{}).get("success",false)
	bag.finish_item_action(success)
	if not success:bag.set_busy(false,str(result.get("error","Combat Medic delivery was not confirmed.")))
	doctor_vats.refresh()
func doctor_patient(ability:String,id:String)->Dictionary:
	for person:Dictionary in state.get("players",[])+state.get("companions",[])+[state.get("self",{})]:
		if str(person.get("id",""))!=id or not person.get("healable",false):continue
		if person.get("doctor_needs",{}).get(ability,false):return person
	return {}
func cast_doctor(ability:String,item_id:String,target_id:String,focus_id:="")->void:
	if busy or not doctor_allowed():return
	var entry:=doctor_entry(ability)
	if not entry.get("learned",false) or float(entry.get("cooldown_seconds",0))>0:return
	var person:=doctor_patient(ability,target_id)
	if person.is_empty():return
	var item:Dictionary=app.owned_inventory_item(item_id)
	if str(item.get("medical_command",""))!=ability:return
	if ability=="healstate":
		if focus_id.is_empty() or str(held.get("id",""))!=focus_id or held.get("tool_kind","")!="medical" or not focus_permitted() or not is_instance_valid(doctor_vats) or not doctor_vats.active() or doctor_vats.mode!="friendly" or doctor_vats.target_id!=target_id:return
		if not doctor_vats.supplies(person).any(func(supply):return str(supply.item_id)==item_id):return
	elif str(bag.held_item.get("id",""))!=item_id:return
	var payload:Dictionary={"ability":ability,"item_id":item_id,"target_id":target_id}
	if not focus_id.is_empty():payload.focus_id=focus_id
	bag.begin_mutation("Treating condition…" if ability=="healstate" else "Resuscitating patient…" if ability=="reviveplayer" else "Extinguishing fire…")
	var version:int=app.datapad_epoch
	var result:=await request("doctor",payload)
	if version!=app.datapad_epoch:return
	var success:bool=result.get("ok",false) and result.get("mutation",{}).get("success",false)
	if ability=="healstate":bag.finish_item_action(success)
	else:bag.finish_consumable_action(app.owned_inventory_item(item_id).duplicate(true) if success else {},success)
	if not success:bag.set_busy(false,str(result.get("error","Doctor treatment was not confirmed.")))
	if is_instance_valid(doctor_vats):doctor_vats.refresh()
func sample_doctor_gestures(delta:float)->void:
	var item:Dictionary=bag.held_item;var ability:=str(item.get("medical_command",""))
	var entry:=doctor_entry(ability)
	var permitted:bool=ability in ["reviveplayer","extinguishfire"] and doctor_allowed() and held.is_empty() and entry.get("learned",false) and float(entry.get("cooldown_seconds",0))<=0
	var controller:XRController3D=bag.held_controller()
	var other_side:="right" if bag.held_hand_side()=="left" else "left"
	var other:XRController3D=rig.get_node(other_side.capitalize()+"Hand")
	var services:Variant=app.get("services")
	permitted=permitted and is_instance_valid(services) and services.party_hand_free(other_side) and controller.get_float("trigger")<.25 and other.get_float("trigger")<.25
	var chosen:Dictionary={};var nearest:=INF
	if permitted:
		for person:Dictionary in state.get("players",[])+state.get("companions",[])+[state.get("self",{})]:
			if doctor_patient(ability,str(person.get("id",""))).is_empty():continue
			var boxes:=patient_bounds(person)
			if boxes.is_empty():continue
			var combined:AABB=boxes[0]
			for box:AABB in boxes:combined=combined.merge(box)
			var anchor:=combined.position+combined.size*Vector3(.5,.68,.5)
			var avatar:Node3D=app.avatar if str(person.id)==app.datapad_character_id else people.get(str(person.id))
			if is_instance_valid(avatar) and is_instance_valid(avatar.get("skeleton")):
				for bone_name in ["chest","spine2","spine1"]:
					var bone:int=avatar.skeleton.find_bone(bone_name)
					if bone>=0:anchor=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(bone).origin;break
			var distance:=controller.global_position.distance_to(anchor)
			if distance>.85 or distance>=nearest:continue
			if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(controller.global_position,anchor,7,[body.get_rid()])).is_empty():continue
			nearest=distance;chosen={"id":str(person.id),"anchor":anchor}
	var identity:="" if chosen.is_empty() else str(item.id)+":"+str(chosen.id)
	if doctor_motion.sample(delta,identity,ability,controller.global_position-chosen.get("anchor",Vector3.ZERO),other.global_position-chosen.get("anchor",Vector3.ZERO),other.get_float("grip"),permitted) and not chosen.is_empty():cast_doctor(ability,str(item.id),str(chosen.id))
func direct_focus_permitted()->bool:
	return focus_permitted() and held.get("tool_kind","")=="medical" and medical_ui_closed() and not (is_instance_valid(doctor_vats) and doctor_vats.active()) and not (doctor_release_pending and captures_combat())
func focus_recipient()->Dictionary:
	# A Mind-only patient must be selectable before the second tap, even with
	# full Health. Each candidate still has to meet its own action's range.
	var options:Array=[];var maximum:=0.
	for name:String in [direct_tap_ability(),"quickheal","healmind"]:
		var entry:=named_ability(name)
		var range_m:=float(entry.get("range_m",0));maximum=maxf(maximum,range_m)
		for person:Dictionary in candidates(entry):
			if person.get("eligible",false) and body.global_position.distance_to(person.position)<=range_m:options.append(person)
	if options.is_empty():return {}
	var pose:=aim()
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*(maximum+2),7,[body.get_rid()]))
	return Targeting.first(pose,body.global_position,{"range_m":maximum},options,pose.origin.distance_to(hit.position) if not hit.is_empty() else INF)
func cast_focus(name:String,binding:Dictionary={})->void:
	if not direct_focus_permitted() or busy or (name=="healmind" and not doctor_allowed()):return
	if not binding.is_empty() and (int(binding.epoch)!=app.datapad_epoch or str(binding.item_id)!=str(held.get("id",""))):return
	var entry:=named_ability(name)
	if entry.is_empty():status="Medical ability not learned";return
	if float(entry.get("cooldown_seconds",0))>0:status="Medical ability recovering";return
	# Resolve the aimed recipient for this action, including its own need/range.
	var pose:=aim();var range_m:=float(entry.get("range_m",0))+2
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*range_m,7,[body.get_rid()]))
	var recipient:=Targeting.first(pose,body.global_position,entry,candidates(entry),pose.origin.distance_to(hit.position) if not hit.is_empty() else INF)
	if recipient.is_empty() or (not binding.is_empty() and str(binding.target_id)!=str(recipient.id)):return
	var item_id:=str(held.id);var version:int=app.datapad_epoch;var generation:=focus_generation
	focus_cast_pending=true
	var reply:=await request("select",{"item_id":item_id,"ability":name})
	focus_cast_pending=false
	if generation!=focus_generation or version!=app.datapad_epoch or str(held.get("id",""))!=item_id or not direct_focus_permitted() or not reply.get("ok",false) or selected!=name or (name=="healmind" and not doctor_allowed()):return
	# Selection is asynchronous: recheck aim, so a moved/obscured recipient or
	# released tool cannot receive a delayed treatment.
	entry=named_ability(name)
	if entry.is_empty() or float(entry.get("cooldown_seconds",0))>0:return
	pose=aim();hit=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*range_m,7,[body.get_rid()]))
	var current:=Targeting.first(pose,body.global_position,entry,candidates(entry),pose.origin.distance_to(hit.position) if not hit.is_empty() else INF)
	if str(current.get("id",""))!=str(recipient.id):return
	await request("heal",{"item_id":item_id,"ability":name,"target_id":str(recipient.id)})
func sample_focus_trigger(delta:float,trigger:float)->void:
	if is_instance_valid(doctor_vats) and doctor_vats.active():
		focus_trigger.reset();doctor_vats.sample(delta,trigger);return
	# Preserve an explicit First Aid fallback across Quick Heal/Mind selection.
	if focus_tap_ability.is_empty() and age<3 and str(state.get("character_id",""))==app.datapad_character_id:focus_tap_ability=direct_tap_ability()
	var permitted:=direct_focus_permitted() and not busy
	var recipient:=focus_recipient() if permitted else {}
	var binding:Dictionary={"epoch":app.datapad_epoch,"item_id":str(held.get("id","")),"target_id":str(recipient.get("id",""))}
	var identity:=JSON.stringify([binding.epoch,app.datapad_character_id,binding.item_id,binding.target_id,direct_tap_ability()])
	var action:String=focus_trigger.sample(delta,trigger,permitted and not recipient.is_empty(),identity,permitted and doctor_allowed())
	if action=="tenddamage":action=direct_tap_ability()
	if not action.is_empty():cast_focus(action,binding)
func direct_tap_ability()->String:
	if focus_tap_ability in ["tenddamage","firstaid"]:return focus_tap_ability
	return "firstaid" if selected=="firstaid" else "tenddamage"
func select_focus_choice(ability:String)->void:
	if ability not in ["tenddamage","firstaid"] or not focus_permitted() or busy:return
	var version:int=app.datapad_epoch;var item_id:=str(held.id)
	var result:=await request("select",{"item_id":item_id,"ability":ability})
	if result.get("ok",false) and version==app.datapad_epoch and str(held.get("id",""))==item_id and selected==ability:focus_tap_ability=ability;focus_trigger.reset()
func _process(delta: float) -> void:
	if not is_instance_valid(app) or not app.world_ready:
		bandaging.reset();focus_trigger.reset();doctor_motion.reset()
		if is_instance_valid(doctor_vats):doctor_vats.close()
		return
	if epoch!=app.datapad_epoch:reset()
	if app.get("live_combat_reserved")==true and (not is_instance_valid(app.live_combat) or not app.live_combat.live):bandaging.reset();focus_trigger.reset();return
	age+=delta;next_poll-=delta;update_drag(delta)
	if bag.held_item.get("medical_item",false) and age>=.65:next_poll=0
	bandaging.frame(self,delta)
	sample_doctor_gestures(delta)
	for entry: Dictionary in state.get("abilities",[]):entry.cooldown_seconds=maxf(0,float(entry.get("cooldown_seconds",0))-delta)
	for ability:String in ["healstate","reviveplayer","extinguishfire"]:
		var entry:=doctor_entry(ability)
		if not entry.is_empty():entry.cooldown_seconds=maxf(0,float(entry.get("cooldown_seconds",0))-delta)
	for entry:Dictionary in state.get("combat_medic",{}).get("abilities",[]):entry.cooldown_seconds=maxf(0,float(entry.get("cooldown_seconds",0))-delta)
	for command_name in state.get("medical_item_cooldowns",{}):state.medical_item_cooldowns[command_name]=maxf(0,float(state.medical_item_cooldowns[command_name])-delta)
	if not busy and not focus_cast_pending and (held.is_empty() or hand.get_float("trigger")<.25) and not focus_trigger.active() and not app.inventory_request_pending and not bag.action_pending and next_poll<=0 and (not app.has_method("try_background_poll") or app.try_background_poll("medic")):
		next_poll=5
		if not provision_attempted and not state.get("abilities",[]).is_empty() and not state.get("focus_issued",true) and not app.inventory_snapshot.get("items",[]).any(func(item):return item.get("tool_kind","")=="medical") and bag.hip_tool.get("tool_kind","")!="medical":
			provision_attempted=true;request("provision")
		else:request("status")
	if not allowed():
		focus_trigger.reset();grip_armed=false;wheel.close()
		if is_instance_valid(doctor_vats):doctor_vats.close()
	else:
		var grip:=hand.get_float("grip")
		if grip<0.25:
			grip_armed=true
			if not held.is_empty():stow()
		elif grip>0.65 and grip_armed:
			grip_armed=false
			if held.is_empty() and not bag.is_open:
				if bag.hip_tool.get("tool_kind","")=="medical" and hand.global_position.distance_to(bag.hip_transform().origin)<0.2:draw(bag.hip_tool)
				elif bag.held_item.get("tool_kind","")=="medical" and is_instance_valid(bag.held_model) and hand.global_position.distance_to(bag.held_model.global_position)<0.18:
					var item: Dictionary=bag.held_item.duplicate(true);bag.clear_held();draw(item)
		if not held.is_empty():
			if weapon_held():wheel.close()
			var chosen: String=wheel.sample_stick(hand.get_vector2("primary"))
			if not chosen.is_empty() and not busy:select_focus_choice(chosen)
			sample_focus_trigger(delta,hand.get_float("trigger"))
	body.medical_stick_side=side if wheel.menu_open or captures_combat() else ""
	if is_instance_valid(app.combat_rig):app.combat_rig.offhand_occupied=not held.is_empty()
	for person: Dictionary in state.get("players",[]):
		var avatar: Node3D=people.get(str(person.id))
		if is_instance_valid(avatar):avatar.update_motion(delta,0,{"posture":2 if int(person.posture)==2 else 1 if int(person.posture)==1 else 0,"presentation":{"life_locked":int(person.posture) in [13,14] or bool(person.get("feigning_death",false)),"life_animation":"dead" if int(person.posture)==14 else "incapacitated"}})
	pose_tool();update_target(delta)
func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(pose_tool):RenderingServer.frame_pre_draw.disconnect(pose_tool)

func tracked_pose() -> Dictionary:
	var left: XRController3D=rig.get_node("LeftHand");var right: XRController3D=rig.get_node("RightHand")
	var tracked: bool=body.active and HandInput.controller_tracked(left) and HandInput.controller_tracked(right) and app.xr_focused
	crossed=SwgMedicDrag.crossed(head.global_transform,left.global_position,right.global_position,tracked)
	return {"tracked":tracked,"crossed":crossed,"grips":tracked and left.get_float("grip")>0.65 and right.get_float("grip")>0.65,"left":app.scout.source_position() if not tracked else source_point(left.global_position),"right":app.scout.source_position() if not tracked else source_point(right.global_position)}
func source_point(p: Vector3) -> Array:
	var value: Vector3=app.source_position_at(p);return [value.x,value.y,value.z]
func observe_drag(value: Dictionary) -> void:
	var revision:=int(value.get("revision",0))
	if revision<=drag_revision:return
	drag_revision=revision
	if crossed or not (body.feedback.life_locked or body.feedback.feigning_death) or value.get("position",[]).size()!=3:return
	var destination: Vector3=app.scout.world(value.position)
	var movement:=destination-body.global_position
	if movement.length()>3:return
	if not body.test_move(body.global_transform,movement):body.apply_world_correction(movement)
func update_drag(delta: float) -> void:
	next_drag-=delta
	var pose:=tracked_pose()
	if not pose.grips:
		drag_motion.reset()
		drag_grips_released=true
		if not drag_target.is_empty() and not busy:
			var old:=drag_target;drag_target="";request("drag",{"target_id":old,"release":true})
		return
	if not held.is_empty() or not bag.held_item.is_empty() or bag.is_open or weapon_held() or not allowed() or not state.get("drag_available",false):return
	var left: XRController3D=rig.get_node("LeftHand");var right: XRController3D=rig.get_node("RightHand")
	if drag_target.is_empty() and drag_grips_released:
		for person: Dictionary in state.get("players",[]):
			var avatar: Node3D=people.get(str(person.id))
			if (int(person.posture)!=13 and not bool(person.get("feigning_death",false))) or person.get("drag",{}).get("blocked",true) or not is_instance_valid(avatar):continue
			if SwgMedicDrag.both_touch(bounds(avatar),left.global_position,right.global_position):
				drag_target=str(person.id);drag_grips_released=false;next_drag=0;break
	if not drag_target.is_empty():
		var sample: Dictionary=drag_motion.sample((left.global_position+right.global_position)*0.5,true,age<3,delta)
		if not sample.active:
			drag_target="";drag_grips_released=false;return
	if not drag_target.is_empty() and not busy and next_drag<=0:
		next_drag=0.3;send_drag()
func send_drag() -> void:
	var result:=await request("drag",{"target_id":drag_target,"release":false})
	if not result.get("ok",false):drag_target="";drag_grips_released=false
