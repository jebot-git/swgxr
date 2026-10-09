extends "res://scripts/xr_datapad.gd"
## VR scout orchestration around authoritative native commands and camp objects.
var ranger:Node3D
var inspection:Node3D
var app: Node
var bag: Node3D
var state: Dictionary={}
var dna_input=preload("res://bioengineer/sampling.gd").new()
var gestures=preload("res://scout/gestures.gd").new()
var mask_gesture=preload("res://scout/mask_scent_gesture.gd").new()
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
	var panel:=Panel.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_theme_stylebox_override("panel",preload("res://scripts/datapad_theme.gd").frame(14,"wide"));ui.add_child(panel)
	camp_text=Label.new();camp_text.position=Vector2(24,20);camp_text.size=Vector2(512,230);camp_text.add_theme_font_size_override("font_size",24);ui.add_child(camp_text)
	disband=Button.new();disband.text="Disband camp";disband.position=Vector2(24,268);disband.size=Vector2(512,48);ui.add_child(disband);disband.pressed.connect(disband_camp)
	add_surface(ui,Vector2i(560,340),Vector2(0.55,0.334));surfaces[0].mesh.visible=false;visible=true;surfaces[0].viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	dot=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=0.003;sphere.height=0.006;dot.mesh=sphere;add_child(dot);dot.visible=false
	bag.scout_requested.connect(use_item)
	ranger=preload("res://scout/ranger.gd").new();add_child(ranger);ranger.setup(self)
	inspection=preload("res://scout/creature_inspection.gd").new();add_child(inspection);inspection.setup(self)
	body.combat_pools.selection_replaced.connect(selection_replaced)
	RenderingServer.frame_pre_draw.connect(update_reticle)
func reset() -> void:
	if is_instance_valid(ranger):ranger.reset()
	if is_instance_valid(inspection):inspection.reset()
	state={};epoch=app.datapad_epoch;next_poll=0;last_reply=100;gestures.reset();dna_input.reset();camp_id="";cooldown_queue.clear()
	mask_gesture.reset()
	var terrain:Variant=app.get("terrain")
	if is_instance_valid(terrain) and terrain.has_method("set_modification_group"):terrain.set_modification_group("camps",[])
	for node in models.values():node.queue_free()
	models.clear();surfaces[0].mesh.visible=false;movement.state={}
func mask_entry() -> Dictionary:
	if last_reply>12 or not state.get("mask_scent_available",false): return {}
	if is_instance_valid(app.combat_rig) and app.combat_rig.selected>=0: return {}
	return {"id":"mask_scent","label":"Mask Scent","source_command":"maskscent","cooldown_seconds":float(state.get("mask_scent_duration",0)),"base_sac":{"health":0,"action":0,"mind":0}}
func dna_entry() -> Dictionary:
	if last_reply>12 or not state.get("sample_dna_available",false): return {}
	return {"id":"sample_dna","label":"Sample DNA","source_command":"sampledna","activation":"native_contact","cooldown_seconds":float(state.get("sample_dna_recovery",11)),"base_sac":{"health":0,"action":0,"mind":200}}

func dna_target_at(hand: Vector3) -> String:
	var target_id:="";var nearest:=INF
	for target: Dictionary in state.get("targets",[]):
		if not target.get("dna_eligible",false): continue
		var actor:=live_actor(target)
		# Physical contact must be with a visible original creature, never a stale
		# remote sphere or the combat reticle. Current actor pose follows movement.
		if actor==null or not dna_input.touches(actor.global_transform,actor.visual_bounds(),hand): continue
		var distance:=hand.distance_squared_to(actor.global_position)
		if distance>=nearest: continue
		var query:=PhysicsRayQueryParameters3D.create(rig.get_node("XRCamera3D").global_position,hand,7)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		nearest=distance;target_id=str(target.id)
	return target_id

func sample_dna_hand(side: String, pose: Transform3D, trigger: float, tracked: bool, permitted: bool) -> bool:
	var pools=body.combat_pools
	var armed: bool=pools.selected=="sample_dna" and pools.primed
	var result: Dictionary=dna_input.sample(side,trigger,tracked,permitted,armed)
	if not result.attempt or busy or not cooldown_queue.is_empty() or dna_entry().is_empty() or state.get("sample_dna_pending",false) or float(pools.cooldowns.get("sample_dna",0))>0: return result.capture
	var target:=dna_target_at(pose.origin)
	if target.is_empty(): pools.reason="Hold hand over an eligible creature";return result.capture
	var source: Vector3=app.source_position_at(pose.origin)
	pools.primed=false;pools.reason="Sampling requested"
	# No deferred click and no automatic retry after an uncertain mutation.
	request_dna({"target_id":target,"hand_position":[source.x,source.y,source.z]})
	return true

func request_dna(detail: Dictionary) -> void:
	var version: int=app.datapad_epoch
	var result:=await request("sample_dna",detail)
	if version!=app.datapad_epoch: return
	if body.combat_pools.selected=="sample_dna":
		body.combat_pools.reason="Sampling…" if result.get("mutation",{}).get("sampling_started",false) else message

func select_mask() -> void:
	var entry:=mask_entry()
	if entry.is_empty(): return
	body.combat_pools.replace_selection(entry,"scout");body.combat_pools.primed=true
func selection_replaced(previous: Dictionary, was_primed: bool) -> void:
	if was_primed and previous.get("id","")=="mask_scent": cooldown_queue.append("discard_mask_scent")
	if was_primed and previous.get("id","")=="sample_dna": cooldown_queue.append("discard_sample_dna")
func activate_mask(from_gesture: bool = false) -> void:
	if busy or not cooldown_queue.is_empty() or mask_entry().is_empty(): return
	if not from_gesture and (body.combat_pools.selected!="mask_scent" or not body.combat_pools.primed): return
	if from_gesture and state.get("mask_scent_active",false): return
	if float(body.combat_pools.cooldowns.get("mask_scent",0))>0: return
	if body.combat_pools.selected=="mask_scent": body.combat_pools.primed=false
	request("mask_scent")

func sample_mask_gesture(delta: float, left: XRController3D, right: XRController3D) -> void:
	var permitted: bool=app.world_ready and not app.loading_stage and not app.session_leaving and body.active and not body.feedback.combat_blocked() and bag.allowed and not blocks_interactions()
	if bool(app.get("xr_requested")) and not bool(app.get("xr_focused")): permitted=false
	var tracker=XRServer.get_tracker("head")
	var pose: XRPose=tracker.get_pose("default") if tracker!=null else null
	permitted=permitted and pose!=null and pose.has_tracking_data and HandInput.controller_tracked(left) and HandInput.controller_tracked(right)
	# Reuse the free-hand gates for tools, weapons, wallet, UI, performance and
	# vehicle controls; rubbing never captures a trigger or drops a held item.
	var services: Variant=app.get("services")
	permitted=permitted and is_instance_valid(services) and services.party_hand_free("left") and services.party_hand_free("right")
	var avatar: Variant=app.get("tracked_avatar")
	var skeleton: Skeleton3D=avatar.skeleton if is_instance_valid(avatar) else null
	var left_arm: Dictionary=mask_gesture.forearm(skeleton,"left")
	var right_arm: Dictionary=mask_gesture.forearm(skeleton,"right")
	permitted=permitted and not left_arm.is_empty() and not right_arm.is_empty()
	# An open rubbing hand keeps this distinct from fist/minimap gestures.
	if left.get_float("grip")>=0.65 or left.get_float("trigger")>=0.65: right_arm={}
	if right.get_float("grip")>=0.65 or right.get_float("trigger")>=0.65: left_arm={}
	if mask_gesture.sample(delta,left.global_position,right.global_position,left_arm,right_arm,permitted): activate_mask(true)
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
		state=result.state;last_reply=0;movement.observe(state);next_poll=2.0 if state.get("foraging",false) or state.get("trap_pending",false) or state.get("sample_dna_pending",false) or state.get("ranger",{}).get("tracking",{}).get("state","")=="pending" else 5.0
		body.combat_pools.cooldowns.mask_scent=maxf(float(body.combat_pools.cooldowns.get("mask_scent",0)),float(state.get("mask_scent_cooldown",0)))
		body.combat_pools.cooldowns.sample_dna=maxf(float(body.combat_pools.cooldowns.get("sample_dna",0)),float(state.get("sample_dna_cooldown",0)))
		if body.combat_pools.selected=="sample_dna" and action=="status": body.combat_pools.reason="Sampling…" if state.get("sample_dna_pending",false) else ""
		if body.combat_pools.ham.size()==9 and state.get("ham",[]).size()==9: body.combat_pools.ham=state.ham.duplicate()
		sync_items();sync_camps();message="Searching…" if state.get("foraging",false) else ""
	else:message=str(result.get("error","Scout action not confirmed"))
	if is_instance_valid(ranger):ranger.observe(result)
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
	if hip.get("tool_kind","") in ["trap","grenade"] or bag.hip_tool.get("tool_kind","") in ["trap","grenade"]:
		app.gathering.state["hip_tool"]=hip;bag.set_hip_tool(app.gathering.hip_item())
	app.reconcile_inventory_presentations();app.update_inventory_presentation()
func belt_action(action: String, item: Dictionary) -> void:
	var result:=await request(action,{"item_id":str(item.id)})
	bag.finish_item_action(result.get("ok",false))
	if not result.get("ok",false):bag.set_busy(false,message)

func blocks_interactions()->bool:return is_instance_valid(ranger) and ranger.blocks_interactions()
func use_item(item: Dictionary) -> void:
	if preload("res://scout/ranger_input.gd").is_kit(item):
		if is_instance_valid(ranger):ranger.conceal(item)
		return
	if item.get("tool_kind","")=="camp":
		var result:=await request("camp",{"item_id":str(item.id)})
		if result.get("ok",false):bag.finish_item_action(true)
		else:bag.set_busy(false,message)
	else:bag.show_equipment_hologram(rig.get_node("XRCamera3D").global_transform)
func trap_held() -> bool:return bag.held_item.get("tool_kind","") in ["trap","grenade"]
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
	var actor:Node3D
	if is_instance_valid(app.live_combat) and app.live_combat.live:actor=app.live_combat.actors.get(str(target.id))
	elif is_instance_valid(app.get("multiplayer_sync")) and is_instance_valid(app.multiplayer_sync.entities):actor=app.multiplayer_sync.entities.actors.get(str(target.id))
	return actor if is_instance_valid(actor) and actor.is_targetable() else null
func target_center(target: Dictionary) -> Vector3:
	var actor:=live_actor(target)
	if actor!=null:return actor.to_global(actor.collider.position)
	var values: Array=target.get("bounds",{}).get("center",[0,0,0])
	return world(target.position)+Basis(Vector3.UP,-float(target.get("heading_radians",0)))*Vector3(values[0],values[1],-values[2])
func throwable_volley_intent(grenade:bool,target:="")->Dictionary:
	if not is_instance_valid(app.combat_rig) or not is_instance_valid(app.combat_rig.get("squad_leader")):return {}
	return app.combat_rig.squad_leader.volley_intent(aim_pose(),32. if grenade else 64.,target)
func target_under_reticle(grenade := false) -> String:
	var volley:=throwable_volley_intent(grenade)
	if not volley.is_empty():return str(volley.volley_target_id)
	var pose:=aim_pose();var distance:=INF;var selected:=""
	for target: Dictionary in state.get("targets",[]):
		if not target.get("grenade_eligible" if grenade else "eligible",false):continue
		var along:=INF
		var actor:=live_actor(target)
		if actor!=null:
			var local: Transform3D=actor.global_transform.affine_inverse()*pose
			var point: Variant=actor.visual_bounds().intersects_ray(local.origin,-local.basis.z)
			if point is Vector3:along=pose.origin.distance_to(actor.to_global(point))
		elif target.get("bounds") is Dictionary:along=ray_entry(pose,target_center(target),float(target.bounds.radius))
		if along>=distance or along>(32.0 if grenade else 64.0):continue
		var hit:=pose.origin-pose.basis.z.normalized()*along
		var query:=PhysicsRayQueryParameters3D.create(pose.origin,hit,7)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():continue
		distance=along;selected=str(target.id)
	return selected
func try_throw(item: Dictionary) -> bool:
	if item.get("tool_kind","") not in ["trap","grenade"] or not gestures.valid_throw():return false
	if busy or bag.is_open or not bag.allowed or last_reply>=12:return false
	var grenade:bool=item.get("tool_kind","")=="grenade"
	if grenade and float(state.get("grenade_cooldown",0))-last_reply>0:return false
	var target:=target_under_reticle(grenade)
	if target.is_empty():return false
	if grenade:throw_grenade(item,target)
	else:throw_trap(item,target)
	return true
func throw_trap(item: Dictionary,target: String) -> void:
	var launch: Transform3D=bag.held_model.global_transform if is_instance_valid(bag.held_model) else aim_pose()
	var destination:=launch.origin
	for entry: Dictionary in state.get("targets",[]):
		if str(entry.id)==target:destination=target_center(entry);break
	var detail:Dictionary={"item_id":str(item.id),"target_id":target};detail.merge(throwable_volley_intent(false,target))
	var result:=await request("trap",detail)
	if result.get("ok",false):
		if result.get("mutation",{}).get("volley_consumed",false) and is_instance_valid(app.combat_rig.get("squad_leader")):app.combat_rig.squad_leader.consumed(str(detail.get("volley_mark_id","")))
		var visual: Node3D=bag.assets.instance(str(item.template),0.28,item.get("customization",{}))
		if visual!=null:
			app.add_child(visual);visual.global_transform=launch
			var tween:=visual.create_tween()
			tween.tween_method(func(t: float):
				visual.global_position=launch.origin.lerp(destination,t)+Vector3.UP*sin(t*PI)*0.45,0.0,1.0,2.0)
			tween.tween_callback(visual.queue_free)
		bag.finish_item_action(true)
	else:bag.finish_item_action(false);bag.set_busy(false,message)
static func grenade_flight(mutation: Dictionary, received_unix_ms: float) -> Dictionary:
	# The native receipt locks both the world landing point and detonation time.
	# A delayed response skips the elapsed part of the arc instead of delaying damage.
	var point: Variant=mutation.get("landing_position")
	var fuse:=float(mutation.get("fuse_seconds",NAN))
	var deadline:=float(mutation.get("detonation_at_ms",NAN))
	if not point is Array or point.size()!=3 or not is_finite(fuse) or fuse<=0 or fuse>10 or not is_finite(deadline) or not is_finite(received_unix_ms):return {}
	for value in point:
		if not (value is float or value is int) or not is_finite(float(value)):return {}
	var remaining:=clampf((deadline-received_unix_ms)/1000.0,0,fuse)
	return {"landing_position":point.duplicate(),"remaining":remaining,"progress":1.0-remaining/fuse}

func throw_grenade(item: Dictionary, target: String) -> void:
	var launch_epoch:int=app.datapad_epoch
	var sent_ms:=Time.get_ticks_msec()
	var launch: Transform3D=bag.held_model.global_transform if is_instance_valid(bag.held_model) else aim_pose()
	var detail:Dictionary={"item_id":str(item.id),"target_id":target};detail.merge(throwable_volley_intent(true,target))
	var result:=await request("grenade",detail)
	if launch_epoch!=app.datapad_epoch:return
	if not result.get("ok",false):
		bag.finish_item_action(false);bag.set_busy(false,message);return
	bag.finish_item_action(true)
	var mutation:Dictionary=result.get("mutation",{})
	if mutation.get("volley_consumed",false) and is_instance_valid(app.combat_rig.get("squad_leader")):app.combat_rig.squad_leader.consumed(str(detail.get("volley_mark_id","")))
	# Use the native clock, accounting for the entire request round trip. This
	# conservative visual deadline cannot drift late because client/server wall
	# clocks disagree or the reply arrived slowly.
	var server_ms:=float(result.get("state",{}).get("server_time_ms",NAN))
	var observed_ms:=server_ms+maxi(0,Time.get_ticks_msec()-sent_ms)
	var flight:=grenade_flight(mutation,observed_ms)
	if flight.is_empty():return # Never invent timing or a position after an uncertain receipt.
	var destination:=world(flight.landing_position)
	var visual:Node3D=bag.assets.instance(str(item.template),0.28,item.get("customization",{}))
	if visual==null:return
	app.add_child(visual);visual.global_transform=launch
	# Model decoding may consume time too; never extend the native fuse for it.
	flight=grenade_flight(mutation,server_ms+maxi(0,Time.get_ticks_msec()-sent_ms))
	var arc:=func(t:float):visual.global_position=launch.origin.lerp(destination,t)+Vector3.UP*sin(t*PI)*0.45
	arc.call(float(flight.progress))
	if float(flight.remaining)>0:
		var tween:=visual.create_tween()
		tween.tween_method(arc,float(flight.progress),1.0,float(flight.remaining))
		tween.tween_callback(func():
			visual.queue_free()
			grenade_detonation(item,destination,launch_epoch))
	else:
		visual.queue_free()
		grenade_detonation(item,destination,launch_epoch)

var grenade_assets:RefCounted
func grenade_detonation(item:Dictionary, destination:Vector3, launch_epoch:int)->void:
	if not is_instance_valid(app) or launch_epoch!=app.datapad_epoch or not app.world_ready or not is_instance_valid(app.combat_rig) or not is_instance_valid(app.combat_rig.rounds_sim):return
	if grenade_assets==null:
		grenade_assets=preload("res://combat/original_assets.gd").new()
		grenade_assets.directory=ProjectSettings.globalize_path("res://../runtime/assets/grenades")
		if not grenade_assets.load_catalog():grenade_assets=null;return
	var path:=str(grenade_assets.catalog.get("grenade_effects",{}).get(str(item.get("throwable_kind","")),""))
	var effect:Dictionary=grenade_assets.catalog.get("effects",{}).get(path,{})
	if effect.is_empty():return
	var manager:Node3D=app.combat_rig.rounds_sim.effects.ensure_manager()
	for appearance:Dictionary in effect.get("appearances",[]):
		manager.burst(str(appearance.particle),Transform3D(Basis.IDENTITY,destination),float(appearance.duration),"impact",grenade_assets)
	var audio:=get_node_or_null("/root/SWGSpatialAudio")
	if audio!=null:
		for sound:String in effect.get("sounds",[]):audio.play_original(grenade_assets,sound,destination,1)
	# Original camera shake is deliberately omitted: no effect moves the HMD.

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
	var terrain:Variant=app.get("terrain")
	if is_instance_valid(terrain) and terrain.has_method("set_modification_group"):
		terrain.set_modification_group("camps",state.get("camps",[]))
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
	if not is_instance_valid(app) or not app.world_ready:
		mask_gesture.sample(delta,Vector3.ZERO,Vector3.ZERO,{},{},false);return
	if app.get("live_combat_reserved")==true and (not is_instance_valid(app.live_combat) or not app.live_combat.live):
		mask_gesture.sample(delta,Vector3.ZERO,Vector3.ZERO,{},{},false);return
	if epoch!=app.datapad_epoch:reset()
	last_reply+=delta;next_poll-=delta
	if is_instance_valid(app.combat_rig):app.combat_rig.scout=self
	var head: Node3D=rig.get_node("XRCamera3D");var left: XRController3D=rig.get_node("LeftHand");var right: XRController3D=rig.get_node("RightHand")
	var tracked: bool=bag.allowed and HandInput.controller_tracked(left) and HandInput.controller_tracked(right)
	sample_mask_gesture(delta,left,right)
	if not busy and not app.inventory_request_pending and not bag.action_pending:
		if not cooldown_queue.is_empty():request(cooldown_queue.pop_front())
		elif next_poll<=0 and (not app.has_method("try_background_poll") or app.try_background_poll("scout")):next_poll=5;request("ranger_status")
	var sample:=gestures.sample(delta,head.global_transform,left.global_position,right.global_position,ground_distance(left.global_position),ground_distance(right.global_position),tracked)
	var main: XRController3D=left if bag.held_hand_side()=="left" else right
	gestures.sample_throw(delta,head.global_transform,main.global_position,tracked and trap_held())
	if not busy and not bag.is_open and last_reply<12:
		if sample.forage and state.get("forage_available",false) and not state.get("foraging",false) and bag.held_item.is_empty():request("forage")
		elif sample.burst_run and state.get("burst_available",false) and not state.get("burst_active",false) and float(state.get("burst_cooldown",0))<=0:request("burst_run")
	update_camp_ui();update_reticle()
func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(update_reticle):RenderingServer.frame_pre_draw.disconnect(update_reticle)
	if is_instance_valid(movement):movement.state={}
	for node in models.values():if is_instance_valid(node):node.queue_free()
