extends "res://scripts/xr_datapad.gd"
## VR scout orchestration around authoritative native commands and camp objects.
var app: Node
var bag: Node3D
var state: Dictionary={}
var gestures=preload("res://scout/gestures.gd").new()
var movement: Node3D
var busy:=false
var next_poll:=0.0
var epoch:=-1
var models: Dictionary={}
var camp_id:=""
var camp_text: Label
var disband: Button
var message:=""
var last_reply:=100.0
var cooldown_queue: Array=[]
var camp_catalog: Dictionary={}
func setup(host: Node, inventory: Node3D) -> void:
	app=host;bag=inventory;rig=bag.rig;body=bag.body;offhand=bag.offhand;process_priority=125
	if FileAccess.file_exists("res://../runtime/assets/scout/catalog.json"):camp_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/scout/catalog.json"))
	movement=rig.get_node("ScoutMovement")
	ui=Control.new();ui.theme=preload("res://scripts/datapad_theme.gd").build();ui.custom_minimum_size=Vector2(560,340);ui.size=Vector2(560,340)
	var panel:=Panel.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_theme_stylebox_override("panel",preload("res://scripts/datapad_theme.gd").box("071c29","3ea8b9",2,14));ui.add_child(panel)
	camp_text=Label.new();camp_text.position=Vector2(24,20);camp_text.size=Vector2(512,230);camp_text.add_theme_font_size_override("font_size",24);ui.add_child(camp_text)
	disband=Button.new();disband.text="Disband camp";disband.position=Vector2(24,268);disband.size=Vector2(512,48);ui.add_child(disband);disband.pressed.connect(disband_camp)
	add_surface(ui,Vector2i(560,340),Vector2(0.55,0.334));surfaces[0].mesh.visible=false;visible=true;surfaces[0].viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	dot=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=0.003;sphere.height=0.006;dot.mesh=sphere;add_child(dot);dot.visible=false
	bag.scout_requested.connect(use_item)
	body.combat_pools.selection_replaced.connect(selection_replaced)
	RenderingServer.frame_pre_draw.connect(update_reticle)
func reset() -> void:
	state={};epoch=app.datapad_epoch;next_poll=0;last_reply=100;gestures.reset();camp_id="";cooldown_queue.clear()
	for node in models.values():node.queue_free()
	models.clear();surfaces[0].mesh.visible=false;movement.state={}
func mask_entry() -> Dictionary:
	if last_reply>12 or not state.get("mask_scent_available",false): return {}
	if is_instance_valid(app.combat_rig) and app.combat_rig.selected>=0: return {}
	return {"id":"mask_scent","label":"Mask Scent","source_command":"maskscent","cooldown_seconds":float(state.get("mask_scent_duration",0)),"base_sac":{"health":0,"action":0,"mind":0}}
func select_mask() -> void:
	var entry:=mask_entry()
	if entry.is_empty(): return
	body.combat_pools.replace_selection(entry,"scout");body.combat_pools.primed=true
func selection_replaced(previous: Dictionary, was_primed: bool) -> void:
	if was_primed and previous.get("id","")=="mask_scent": cooldown_queue.append("discard_mask_scent")
func activate_mask() -> void:
	if busy or mask_entry().is_empty() or body.combat_pools.selected!="mask_scent" or not body.combat_pools.primed: return
	if float(body.combat_pools.cooldowns.get("mask_scent",0))>0: return
	body.combat_pools.primed=false
	request("mask_scent")
func source_position() -> Array:
	var p: Vector3=app.source_position_at(body.global_position);return [p.x,p.y,p.z]
func world(p: Array) -> Vector3:
	var origin: Array=app.stage.get_meta("manifest",{}).get("origin",[0,0,0]) if is_instance_valid(app.stage) else [0,0,0]
	var local:=Vector3(p[0]-origin[0],p[1]-origin[1],-(p[2]-origin[2]))
	return app.stage.to_global(local) if is_instance_valid(app.stage) else local
func request(action: String, detail: Dictionary={}) -> Dictionary:
	if busy or app.datapad_character_id.is_empty(): return {}
	busy=true;var version: int=app.datapad_epoch
	var payload: Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"position":source_position(),"request_id":"scout-%d"%Time.get_ticks_usec()};payload.merge(detail)
	if is_instance_valid(app.combat_rig):payload.posture=app.combat_rig.current_firing_posture().replace("crouched","kneeling")
	var native_id:=preload("res://scripts/native_session_identity.gd").id(app)
	if not native_id.is_empty():payload.session_id=native_id
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,"/scout/"+action,payload)
	busy=false
	if version!=app.datapad_epoch:return {}
	if result.get("ok",false) and result.get("state",{}).get("character_id","")==app.datapad_character_id:
		state=result.state;last_reply=0;movement.observe(state);next_poll=2.0 if state.get("foraging",false) or state.get("trap_pending",false) else 5.0
		body.combat_pools.cooldowns.mask_scent=maxf(float(body.combat_pools.cooldowns.get("mask_scent",0)),float(state.get("mask_scent_cooldown",0)))
		if body.combat_pools.ham.size()==9 and state.get("ham",[]).size()==9: body.combat_pools.ham=state.ham.duplicate()
		sync_items();sync_camps();message="Searching…" if state.get("foraging",false) else ""
	else:message=str(result.get("error","Scout action not confirmed"))
	return result
func sync_items() -> void:
	if not app.inventory_snapshot.get("source_kind","")=="core3_inventory":return
	if state.get("inventory",{}).get("source_kind","")=="core3_inventory":
		var previous: Dictionary={}
		for item: Dictionary in app.inventory_snapshot.get("items",[]):previous[str(item.id)]=item.get("attributes",[])
		app.inventory_snapshot=state.inventory.duplicate(true)
		for item: Dictionary in app.inventory_snapshot.get("items",[]):
			if item.get("attributes",[]).is_empty():item["attributes"]=previous.get(str(item.id),[])
	var hip: Dictionary=state.hip_tool if state.get("hip_tool") is Dictionary else {}
	if hip.get("tool_kind","")=="trap" or bag.hip_tool.get("tool_kind","")=="trap":
		app.gathering.state["hip_tool"]=hip;bag.set_hip_tool(app.gathering.hip_item())
	app.reconcile_inventory_presentations();app.update_inventory_presentation()
func belt_action(action: String, item: Dictionary) -> void:
	var result:=await request(action,{"item_id":str(item.id)})
	bag.finish_item_action(result.get("ok",false))
	if not result.get("ok",false):bag.set_busy(false,message)

func use_item(item: Dictionary) -> void:
	if item.get("tool_kind","")=="camp":
		var result:=await request("camp",{"item_id":str(item.id)})
		if result.get("ok",false):bag.finish_item_action(true)
		else:bag.set_busy(false,message)
	else:bag.show_equipment_hologram(rig.get_node("XRCamera3D").global_transform)
func trap_held() -> bool:return bag.held_item.get("tool_kind","")=="trap"
func equipped_weapon() -> int:
	var combat: Node3D=app.combat_rig
	if not is_instance_valid(combat):return -1
	if combat.selected>=0:return combat.selected
	for i in range(combat.weapons.size()):
		if not combat.weapons[i].get("inventory_only",false):return i
	return -1
func ranged_reticle() -> bool:
	var index:=equipped_weapon()
	return index>=0 and not app.combat_rig.weapons[index].state.is_melee()
func aim_pose() -> Transform3D:
	var combat: Node3D=app.combat_rig
	if ranged_reticle():
		if combat.selected>=0:return combat.muzzle_pose(combat.selected)
		var hand: XRController3D=rig.get_node("RightHand" if offhand=="left" else "LeftHand")
		return combat.controller_weapon_pose(hand)
	return rig.get_node("XRCamera3D").global_transform
static func ray_entry(pose: Transform3D, center: Vector3, radius: float) -> float:
	var direction: Vector3=-pose.basis.z.normalized();var offset:=center-pose.origin
	var along:=direction.dot(offset);var perpendicular:=offset.length_squared()-along*along
	if radius<=0 or perpendicular>radius*radius:return INF
	var half:=sqrt(maxf(0,radius*radius-perpendicular))
	if along+half<=0:return INF
	return maxf(0.001,along-half)
func live_actor(target: Dictionary) -> Node3D:
	if not is_instance_valid(app.live_combat):return null
	var actor: Node3D=app.live_combat.actors.get(str(target.id))
	return actor if is_instance_valid(actor) and actor.is_targetable() else null
func target_center(target: Dictionary) -> Vector3:
	var actor:=live_actor(target)
	if actor!=null:return actor.to_global(actor.collider.position)
	var values: Array=target.get("bounds",{}).get("center",[0,0,0])
	return world(target.position)+Basis(Vector3.UP,-float(target.get("heading_radians",0)))*Vector3(values[0],values[1],-values[2])
func target_under_reticle() -> String:
	var pose:=aim_pose();var distance:=INF;var selected:=""
	for target: Dictionary in state.get("targets",[]):
		if not target.get("eligible",false):continue
		var along:=INF
		var actor:=live_actor(target)
		if actor!=null:
			var local: Transform3D=actor.global_transform.affine_inverse()*pose
			var point: Variant=actor.visual_bounds().intersects_ray(local.origin,-local.basis.z)
			if point is Vector3:along=pose.origin.distance_to(actor.to_global(point))
		elif target.get("bounds") is Dictionary:along=ray_entry(pose,target_center(target),float(target.bounds.radius))
		if along>=distance or along>64:continue
		var hit:=pose.origin-pose.basis.z.normalized()*along
		var query:=PhysicsRayQueryParameters3D.create(pose.origin,hit,7)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():continue
		distance=along;selected=str(target.id)
	return selected
func try_throw(item: Dictionary) -> bool:
	if item.get("tool_kind","")!="trap" or not gestures.valid_throw():return false
	var target:=target_under_reticle()
	if target.is_empty():return false
	throw_trap(item,target);return true
func throw_trap(item: Dictionary,target: String) -> void:
	var launch: Transform3D=bag.held_model.global_transform if is_instance_valid(bag.held_model) else aim_pose()
	var destination:=launch.origin
	for entry: Dictionary in state.get("targets",[]):
		if str(entry.id)==target:destination=target_center(entry);break
	var result:=await request("trap",{"item_id":str(item.id),"target_id":target})
	if result.get("ok",false):
		var visual: Node3D=bag.assets.instance(str(item.template),0.28,item.get("customization",{}))
		if visual!=null:
			app.add_child(visual);visual.global_transform=launch
			var tween:=visual.create_tween()
			tween.tween_method(func(t: float):
				visual.global_position=launch.origin.lerp(destination,t)+Vector3.UP*sin(t*PI)*0.45,0.0,1.0,2.0)
			tween.tween_callback(visual.queue_free)
		bag.finish_item_action(true)
	else:bag.finish_item_action(false);bag.set_busy(false,message)
func update_reticle() -> void:
	if not is_instance_valid(app) or not is_instance_valid(app.combat_rig) or not is_instance_valid(rig) or not trap_held() or bag.is_open:return
	var combat: Node3D=app.combat_rig
	if ranged_reticle():combat.reticle.update_aim(aim_pose(),bag.allowed)
	else:combat.reticle.update_head_aim(rig.get_node("XRCamera3D"),bag.allowed)
func ground_distance(point: Vector3) -> float:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.1,point-Vector3.UP*0.25,2)
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP)<0.65:return INF
	return point.y-Vector3(hit.position).y
func sync_camps() -> void:
	var live_ids: Array=[]
	for camp: Dictionary in state.get("camps",[]):
		for entry: Dictionary in [camp]+camp.get("objects",[]):
			var id:=str(entry.id);live_ids.append(id)
			if not models.has(id):
				var mesh: ArrayMesh=bag.assets.model(str(entry.template))
				if mesh==null:continue
				var visual:=MeshInstance3D.new();visual.mesh=mesh;app.add_child(visual);models[id]=visual
				for child: Dictionary in camp_catalog.get("camps",{}).get(str(entry.template),{}).get("children",[]):
					var child_mesh: ArrayMesh=bag.assets.model(str(child.template))
					if child_mesh==null:continue
					var prop:=MeshInstance3D.new();prop.mesh=child_mesh;visual.add_child(prop)
					prop.position=Vector3(child.position[0],child.position[1],-child.position[2]);prop.rotation.y=-float(child.heading_radians)
			models[id].global_transform=Transform3D(Basis(Vector3.UP,-float(entry.heading_radians)),world(entry.position))
	for id in models.keys():
		if id not in live_ids:models[id].queue_free();models.erase(id)
func disband_camp() -> void:
	if camp_id.is_empty():return
	await request("disband",{"terminal_id":camp_id})
func update_camp_ui() -> void:
	var nearest: Dictionary={};var distance:=4.0
	for camp: Dictionary in state.get("camps",[]):
		if not camp.has("terminal_position"):continue
		var d:=body.global_position.distance_to(world(camp.terminal_position))
		if d<distance:distance=d;nearest=camp
	is_open=not nearest.is_empty() and bag.allowed and not bag.is_open
	surfaces[0].mesh.visible=is_open
	if not is_open:camp_id="";cancel_press();clear_hover();dot.visible=false;return
	camp_id=str(nearest.terminal_id)
	var head: Node3D=rig.get_node("XRCamera3D");var point:=world(nearest.terminal_position)+Vector3.UP*1.0
	var facing: Vector3=(head.global_position-point).slide(Vector3.UP).normalized()
	if facing.length_squared()>0.5:global_transform=Transform3D(Basis(Vector3.UP.cross(facing),Vector3.UP,facing),point)
	camp_text.text="CAMP STATUS\nOwner: %s\nTime: %dm %ds\nVisitors: %d%s"%[str(nearest.owner),int(nearest.uptime_seconds)/60,int(nearest.uptime_seconds)%60,int(nearest.visitors),"\nAbandoned" if nearest.abandoned else ""]
	disband.disabled=busy or not nearest.can_disband
	var hand: XRController3D=rig.get_node(("RightHand" if offhand=="left" else "LeftHand"))
	update_pointer(find_hit(bag.pointing_pose(hand)),hand.get_float("trigger"))
func _process(delta: float) -> void:
	if not is_instance_valid(app) or not app.world_ready:return
	if app.get("live_combat_reserved")==true and (not is_instance_valid(app.live_combat) or not app.live_combat.live):return
	if epoch!=app.datapad_epoch:reset()
	last_reply+=delta;next_poll-=delta
	if is_instance_valid(app.combat_rig):app.combat_rig.scout=self
	if not busy and not app.inventory_request_pending and not bag.action_pending:
		if not cooldown_queue.is_empty():request(cooldown_queue.pop_front())
		elif next_poll<=0 and (not app.has_method("try_background_poll") or app.try_background_poll("scout")):next_poll=5;request("status")
	var head: Node3D=rig.get_node("XRCamera3D");var left: XRController3D=rig.get_node("LeftHand");var right: XRController3D=rig.get_node("RightHand")
	var tracked: bool=bag.allowed and HandInput.controller_tracked(left) and HandInput.controller_tracked(right)
	var sample:=gestures.sample(delta,head.global_transform,left.global_position,right.global_position,ground_distance(left.global_position),ground_distance(right.global_position),tracked)
	var main: XRController3D=right if offhand=="left" else left
	gestures.sample_throw(delta,head.global_transform,main.global_position,tracked and trap_held())
	if not busy and not bag.is_open and last_reply<12:
		if sample.forage and state.get("forage_available",false) and not state.get("foraging",false) and bag.held_item.is_empty():request("forage")
		elif sample.burst_run and state.get("burst_available",false) and not state.get("burst_active",false) and float(state.get("burst_cooldown",0))<=0:request("burst_run")
	update_camp_ui();update_reticle()
func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(update_reticle):RenderingServer.frame_pre_draw.disconnect(update_reticle)
	if is_instance_valid(movement):movement.state={}
	for node in models.values():if is_instance_valid(node):node.queue_free()
