extends StaticBody3D
## Render/collision projection of one real Core3 identity. Never owns health or AI.
const NPCEquipment=preload("res://scripts/npc_equipment.gd")
const Avatar=preload("res://scripts/avatar.gd")
var catalog_candidates:Array=[]
var record:Dictionary={}
var session_id:=""
var visual:Node3D
var label:Label3D
var collider:CollisionShape3D
var goal:=Transform3D.IDENTITY
var motion:=SwgSnapshotMotion.new()
var speed:=0.0
var motion_counter:=-1
var motion_epoch:=-1
var motion_sequence:=-1
var motion_received_ms:=0
var last_snapshot_position:=Vector3.ZERO
var snapshot_usec:=0
var report:Dictionary={}
var equipment:=NPCEquipment.new()
var rigid_equipment:Array=[]
var carrier:RefCounted
var presentation_floor_offset:=Vector3.ZERO
var presentation_floor_update:Callable
var presentation_floor_height:=0.0
var mobile_sound:Node3D
var action_event_epoch:=-1
var action_event_sequence:=-1
var action_audio_until:=0
var combat_event_epoch:=-1
var combat_event_sequence:=-1
var action_pose:=preload("res://combat/action_pose.gd").new()
var action_pose_owned:=false
var action_pose_status:Dictionary={}
var action_weapon_items:Array=[]
var presented_weapon:="__unknown__"

func original_catalog(template:String,primary:String)->String:
	# Match the complete source appearance ID. Never substitute a same-race body
	# or an unrelated ambient outfit when a live template has not been imported.
	var candidates:Array[String]=[primary,
		ProjectSettings.globalize_path("res://../runtime/assets/combat_population/native_current/catalog.json"),
		ProjectSettings.globalize_path("res://../runtime/assets/combat_population/tatooine/catalog.json"),
		ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"),
		ProjectSettings.globalize_path("res://../runtime/assets/combat_population/tatooine_entities/catalog.json")]
	# Crafted creatures can accompany players on any enabled world. This index
	# resolves their original art only; it does not load another planet or spawn mobs.
	var pets_index:=ProjectSettings.globalize_path("res://../runtime/assets/bioengineer/appearance_catalogs.json")
	if FileAccess.file_exists(pets_index):
		if not Avatar.catalog_cache.has(pets_index):Avatar.catalog_cache[pets_index]=Avatar.read_json(pets_index)
		var pet_catalog:=str(Avatar.catalog_cache[pets_index].get("catalogs",{}).get(template,""))
		if not pet_catalog.is_empty():candidates.append(ProjectSettings.globalize_path("res://../"+pet_catalog))
	for extra in catalog_candidates:
		if not str(extra).is_empty() and not candidates.has(str(extra)):candidates.append(str(extra))
	for path:String in candidates:
		if not FileAccess.file_exists(path):continue
		if not Avatar.catalog_cache.has(path):Avatar.catalog_cache[path]=Avatar.read_json(path)
		if Avatar.catalog_cache[path].get("races",{}).has(template):return path
	return ""

func configure(value:Dictionary,session:String,assets:RefCounted,dead_assets:RefCounted,catalog_path:String)->bool:
	record=value.duplicate(true);session_id=session;collision_layer=0;collision_mask=0
	name="Core3_"+str(record.id)
	report={"appearance_status":"complete","missing_components":[]}
	var template:=str(record.template)
	var source_visual:Dictionary=record.get("source_placement_visual",{})
	var appearance_id:=str(source_visual.get("appearance_id",template))
	var dead_model:ArrayMesh=dead_assets.model(template,record.get("customization",{})) if record.kind=="creature" and record.dead else null
	if record.kind=="creature" and (not record.dead or dead_model==null or not source_visual.is_empty()):
		var selected_catalog:=str(source_visual.get("catalog","")) if not source_visual.is_empty() else original_catalog(template,catalog_path)
		if not selected_catalog.is_empty() and not Avatar.catalog_cache.has(selected_catalog):Avatar.catalog_cache[selected_catalog]=Avatar.read_json(selected_catalog)
		if not selected_catalog.is_empty() and not Avatar.catalog_cache[selected_catalog].get("races",{}).has(appearance_id):selected_catalog=""
		if selected_catalog.is_empty():return unavailable("Exact original appearance unavailable: "+template)
		var descriptor:Dictionary=Avatar.catalog_cache[selected_catalog].races[appearance_id]
		report["source_catalog"]=selected_catalog;report["source_appearance"]=appearance_id
		if not descriptor.get("appearance_complete",true):
			report.appearance_status="partial";report.missing_components=descriptor.get("appearance_failures",[]).duplicate(true)
		var avatar:=Avatar.new();add_child(avatar);avatar.load_catalog(selected_catalog)
		var appearance:Dictionary=descriptor.get("default_appearance",{}).duplicate(true)
		appearance.height=float(record.get("scale",1.0));appearance.customization=record.get("customization",appearance.get("customization",{}))
		var result:Dictionary=avatar.configure(appearance_id,appearance)
		if avatar.meshes.is_empty():avatar.free();return unavailable(str(result.get("error","Original body geometry unavailable: "+template)))
		if not str(result.get("error","")).is_empty():
			report.appearance_status="partial";report.missing_components.append({"phase":"body","error":result.error})
		if record.dead:
			if avatar.ensure_animation("incapacitated"):
				avatar.animation_player.play("incapacitated")
				avatar.animation_player.seek(0.0,true)
				avatar.animation_player.advance(0.0)
				report["corpse_pose"]=descriptor.get("incapacitated_pose",{}).duplicate(true)
			else:
				report.appearance_status="partial";report.missing_components.append({"phase":"pose","error":"Original incapacitated pose unavailable"})
			if avatar.animation_player!=null:avatar.animation_player.pause()
			if avatar.face_player!=null:avatar.face_player.pause()
			avatar.skeleton.force_update_all_bone_transforms()
		var attached:=equipment.attach(avatar,descriptor.get("rigid_equipment",[]),selected_catalog.get_base_dir(),not str(source_visual.get("cell_id","")).is_empty())
		rigid_equipment=attached.items
		if not attached.failures.is_empty():
			report.appearance_status="partial";report.missing_components.append_array(attached.failures)
		if not source_visual.is_empty():
			report["equipment_provenance"]="source_placement_equipment"
			report["source_placement_id"]=str(source_visual.get("placement_id",""))
			report["native_equipment_authoritative"]=false
			report["source_variant_ready"]=attached.failures.is_empty() and attached.items.size()==descriptor.get("rigid_equipment",[]).size() and avatar.loaded_parts.filter(func(part):return part.scope=="equipment").size()==descriptor.get("default_outfit",[]).size() and avatar.loaded_parts.all(func(part):return not part.model.get("parts",[]).is_empty())
		# Local-player head exclusion never applies to replicated NPCs.
		for original_mesh:MeshInstance3D in avatar.meshes:original_mesh.layers=1
		visual=avatar
	else:
		var model:ArrayMesh=dead_model if record.kind=="creature" else assets.model(template,record.get("customization",{}))
		if model==null:return unavailable("Original entity geometry unavailable: "+template)
		var mesh:=MeshInstance3D.new();mesh.mesh=model;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mesh);visual=mesh
		mesh.scale=Vector3.ONE*float(record.get("scale",1))
		if record.kind=="creature":mesh.position.y=-(mesh.transform*model.get_aabb()).position.y
		# Lair origin is authored: underground roots/log must not be lifted to bounds.
	if template==preload("res://gcw/carrier_animation.gd").TEMPLATE and visual is Avatar:
		carrier=preload("res://gcw/carrier_animation.gd").new()
		report["carrier_animation_ready"]=carrier.configure(visual)
		carrier.apply(int(record.get("posture",0)))
		report["carrier_phase_policy"]="Original loops on first snapshot; original transitions on observed posture change."
	if record.kind=="creature":
		mobile_sound=preload("res://audio/mobile_emitter.gd").new();add_child(mobile_sound)
		mobile_sound.ambient_allowed=source_visual.is_empty() # Placed NPC ambience already belongs to the environment.
		if visual is Avatar:
			mobile_sound.animation_driven=visual.animation_events_available and not record.get("droid",false)
			visual.original_animation_event.connect(func(event:String):
				if is_instance_valid(mobile_sound) and not record.dead:
					if event!="footstep" or mobile_sound.animation_driven:mobile_sound.queue_event(event))
	var bounds:=visual_bounds()
	collider=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=bounds.size.max(Vector3.ONE*0.05);collider.shape=box;collider.position=bounds.get_center();add_child(collider)
	collision_layer=0 if record.dead or carrier!=null else 8
	if carrier!=null:collider.disabled=true
	make_label(Vector3(bounds.get_center().x,bounds.end.y+0.18,bounds.get_center().z))
	if carrier!=null:label.hide()
	sync_active_weapon()
	return true

func unavailable(reason:String)->bool:
	# Keep native identity, state and a visible diagnostic. Never fabricate source
	# art or collider dimensions for an appearance whose geometry is unknown.
	report.appearance_status="unavailable";report["error"]=reason
	report.missing_components.append({"phase":"appearance","error":reason})
	collision_layer=0;make_label(Vector3.UP*0.3)
	return true

func make_label(position_value:Vector3)->void:
	label=Label3D.new();label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=22;label.pixel_size=0.0015;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=Color("ffcf80") if report.appearance_status!="complete" else Color("ccf7ff");label.position=position_value;add_child(label)
	refresh_label()

func is_targetable()->bool:
	return carrier==null and not bool(record.dead) and report.get("appearance_status","")!="unavailable" and is_instance_valid(visual) and collider!=null

func visual_bounds()->AABB:
	if not is_instance_valid(visual):return AABB()
	if visual is MeshInstance3D:return visual.transform*visual.get_aabb()
	var bounds:=AABB();var found:=false
	for mesh:MeshInstance3D in visual.meshes:
		var transformed:AABB=global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		bounds=transformed if not found else bounds.merge(transformed);found=true
	for item:Dictionary in rigid_equipment:
		if is_instance_valid(item.instance):bounds=bounds.merge(global_transform.affine_inverse()*item.instance.global_transform*item.instance.get_aabb())
	return bounds

func apply_record(value:Dictionary,pose:Transform3D,seconds:float,initial:=false,sample_time:float=-1.0)->void:
	if not initial and is_instance_valid(mobile_sound):
		if bool(value.dead) and not bool(record.get("dead",false)):
			mobile_sound.queue_event("hitheavy");mobile_sound.queue_event("hitground")
		elif not value.dead and float(value.health)<float(record.get("health",value.health)):
			mobile_sound.queue_event("hitlight")
	var relocated:=not record.is_empty() and (str(record.get("cell_id","0"))!=str(value.get("cell_id","0")) or str(record.get("zone",""))!=str(value.get("zone","")))
	# Large source warps and cell transfers reset history; a delayed running
	# creature crossing the old 8m threshold must still travel continuously.
	relocated=relocated or (not initial and last_snapshot_position.distance_to(pose.origin)>maxf(32,seconds*40))
	record=value.duplicate(true);snapshot_usec=Time.get_ticks_usec()
	sync_active_weapon()
	if carrier!=null:carrier.apply(int(record.get("posture",0)))
	speed=last_snapshot_position.distance_to(pose.origin)/maxf(seconds,0.05) if not initial else 0.0
	if is_instance_valid(mobile_sound):mobile_sound.observe(str(record.template),speed,not bool(record.dead))
	var stamp:=sample_time if sample_time>=0 else Time.get_ticks_usec()/1000000.0
	var counter:=int(value.get("movement_counter",-1))
	var stopped:=bool(value.get("dead",false)) or bool(value.get("incapacitated",false))
	# Health updates must not rewind a newer native movement goal. Equal counters
	# also preserve the next-step endpoint: Core3 broadcasts it ahead of its body.
	var fresh:=motion_counter<0 or counter<0 or ((counter-motion_counter)&0xffffffff)>0 and ((counter-motion_counter)&0xffffffff)<0x80000000
	if initial or relocated or stopped or fresh or Time.get_ticks_msec()-motion_received_ms>2000:
		last_snapshot_position=pose.origin;goal=pose;motion_counter=counter
		motion.push_goal(goal,stamp,float(value.get("walk_speed",2.5)),float(value.get("run_speed",7)),float(value.get("movement_speed",0)),initial or relocated or stopped)
		if initial or relocated or stopped:global_transform=goal
	collision_layer=8 if is_targetable() else 0
	refresh_label()

func apply_motion(value:Dictionary,pose:Transform3D,epoch:int)->bool:
	if bool(record.get("dead",false)) or bool(record.get("incapacitated",false)) or str(value.get("cell_id","0"))!=str(record.get("cell_id","0")):return false
	var counter:=int(value.get("movement_counter",-1))
	var sequence:=int(value.get("sequence",-1))
	if epoch==motion_epoch and sequence<=motion_sequence:return false
	if counter<0 or (motion_counter>=0 and ((counter-motion_counter)&0xffffffff)>=0x80000000):return false
	motion_epoch=epoch;motion_sequence=sequence;motion_counter=counter;motion_received_ms=Time.get_ticks_msec()
	goal=pose;last_snapshot_position=pose.origin
	motion.push_goal(pose,Time.get_ticks_usec()/1000000.0,float(record.get("walk_speed",2.5)),float(record.get("run_speed",7)),float(value.get("movement_speed",0)))
	# Move the StaticBody, appearance and contact identity together in _process.
	# This receipt does not refresh health/ability snapshot_usec.
	return true

func set_presentation_floor_offset(height:float)->void:
	var change:=height-presentation_floor_height
	if is_instance_valid(visual):visual.position.y+=change
	if collider!=null:collider.position.y+=change
	if label!=null:label.position.y+=change
	presentation_floor_height=height
	presentation_floor_offset=global_basis*Vector3.UP*height
	report["presentation_floor_offset"]=presentation_floor_offset

func refresh_label()->void:
	if label==null:return
	label.modulate=Color("ff2020") if label.get_meta("spice_hostile_illusion",false) else preload("res://scripts/entity_relationship.gd").color(record)
	label.text=str(record.get("name","CoreCU entity"))+"\n"+("Dead · CoreCU confirmed" if record.dead else "%d / %d"%[int(record.health),int(record.max_health)])

	if report.get("appearance_status","")=="partial":label.text+="\nSome original components unavailable"
	elif report.get("appearance_status","")=="unavailable":label.text+="\nOriginal appearance unavailable · cannot target"

func core3_identity()->Dictionary:
	return {"id":str(record.id),"session_id":session_id,"dead":bool(record.dead),"targetable":is_targetable()}

func get_radar_contact()->Dictionary:
	return {"id":str(record.id),"position":global_position,"kind":"mob","relation":str(record.get("relation","neutral")),"alive":not bool(record.dead),"radar_visible":record.kind=="creature"}

func _process(delta:float)->void:
	global_transform=motion.advance(Time.get_ticks_usec()/1000000.0,delta)
	if presentation_floor_update.is_valid():presentation_floor_update.call()
	speed=motion.get_velocity().length()
	if present_action_pose():return
	if carrier==null and is_instance_valid(visual) and visual.has_method("update_motion") and not record.dead:visual.update_motion(delta,speed,{"grounded":true,"velocity":Vector3(0,0,-speed)})

func present_action_pose()->bool:
	var pose:=action_pose.sample(Time.get_ticks_usec()/1000000.0)
	if record.get("dead",false) or record.get("incapacitated",false):action_pose.event.clear();pose={}
	# Native preparation pose, not animation root motion: keep the planted body
	# and collider aligned with the exact warning revision, bypassing travel lag.
	if not pose.is_empty() and action_pose.event.has("_world_pose"):
		global_transform=action_pose.event._world_pose
	if not pose.is_empty() and visual is Avatar and not visual.tracking_mode and visual.ensure_animation(str(pose.key)):
		var player:AnimationPlayer=visual.animation_player
		if not action_pose_owned or player.assigned_animation!=str(pose.key):player.play(str(pose.key),0)
		player.pause()
		# update_only suppresses frame-zero audio during the wind-up hold.
		player.seek(float(pose.seconds)*float(visual.clip_rates.get(pose.key,1)),true,true)
		visual.current_animation=str(pose.key);visual.skeleton.force_update_all_bone_transforms()
		action_pose_owned=true;action_pose_status=pose
		if pose.sound and pose.role!="support" and is_instance_valid(mobile_sound):
			mobile_sound.queue_event("attacklight")
			var weapon:=str(record.get("weapon_template",""))
			if not weapon.is_empty():mobile_sound.queue_event("weapon:"+weapon)
		return true
	if action_pose_owned and visual is Avatar:
		visual.current_animation="";visual.body_action=""
	action_pose_owned=false;action_pose_status={}
	return false

func _exit_tree()->void:
	equipment.release(rigid_equipment)
	equipment.release(action_weapon_items)

var ground_attack_id:=-1
var ground_state_revision:=-1
func sync_active_weapon(confirmed: String="", explicit:=false) -> void:
	if not visual is Avatar or (not explicit and not record.has("weapon_template")): return
	var weapon:=confirmed if explicit else str(record.weapon_template)
	# A changed motion weapon ID can temporarily lack its template; wait for
	# the next full snapshot instead of inventing a weapon from appearance.
	if weapon.is_empty() or weapon==presented_weapon: return
	presented_weapon=weapon;equipment.release(action_weapon_items);action_weapon_items.clear()
	report["active_weapon_failures"]=[];report["action_weapon_visible"]=false
	var matched:=false
	for item:Dictionary in rigid_equipment:
		var template:=str(item.source.get("template",""))
		if not template.begins_with("object/weapon/"): continue
		item.instance.visible=template==weapon;matched=matched or template==weapon
	if "/unarmed/" in weapon:
		report["active_weapon_presentation"]="unarmed";return
	if matched:
		report["active_weapon_presentation"]=weapon;report["action_weapon_visible"]=true;return
	var selection:Dictionary=visual.equipment_selection([{"template":weapon,"equipped_slots":["hold_r"]}])
	var failures:Array=selection.failures.duplicate()
	for descriptor:Dictionary in selection.rigid:
		var attached:Dictionary=equipment.attach(visual,[descriptor],str(descriptor.directory),false)
		action_weapon_items.append_array(attached.items);failures.append_array(attached.failures)
	report["active_weapon_presentation"]=weapon if not action_weapon_items.is_empty() else "original_weapon_unavailable"
	report["active_weapon_failures"]=failures
	report["action_weapon_visible"]=not action_weapon_items.is_empty()

func apply_action_event(event:Dictionary,epoch:int,transit:float=0.0,world_pose:Variant=null)->void:
	if event.get("protocol",1)==2:
		if epoch<action_event_epoch:return
		if epoch>action_event_epoch:ground_attack_id=-1;ground_state_revision=-1
		var attack_id:=int(str(event.attack_id));var revision:=int(event.state_revision)
		if attack_id<ground_attack_id or (attack_id==ground_attack_id and revision<=ground_state_revision):return
		ground_attack_id=attack_id;ground_state_revision=revision;action_event_epoch=epoch
	else:
		if epoch<action_event_epoch or (epoch==action_event_epoch and int(event.get("sequence",-1))<=action_event_sequence):return
		action_event_epoch=epoch;action_event_sequence=int(event.get("sequence",-1))
	action_audio_until=Time.get_ticks_msec()+2000
	if event.has("animation"):
		sync_active_weapon(str(event.get("weapon_template",record.get("weapon_template",""))),true)
		var presentation:=event.duplicate(true)
		if world_pose is Transform3D:presentation["_world_pose"]=world_pose
		action_pose.ingest(presentation,Time.get_ticks_usec()/1000000.0,transit)
		return
	if event.get("phase","")!="active" or event.get("role","")=="support" or bool(record.get("dead",false)) or not is_instance_valid(mobile_sound):return
	mobile_sound.queue_event("attacklight")
	var weapon:=str(record.get("weapon_template",""))
	if not weapon.is_empty():mobile_sound.queue_event("weapon:"+weapon)

func apply_combat_event(event:Dictionary,epoch:int)->void:
	if epoch<combat_event_epoch or (epoch==combat_event_epoch and int(event.get("sequence",-1))<=combat_event_sequence):return
	combat_event_epoch=epoch;combat_event_sequence=int(event.get("sequence",-1))
	if bool(record.get("dead",false)) or bool(record.get("incapacitated",false)) or not is_instance_valid(mobile_sound):return
	if event.get("event","")!="attack" or Time.get_ticks_msec()<action_audio_until:return
	mobile_sound.queue_event("attacklight")
	var weapon:=str(event.get("weapon_template",""))
	if not weapon.is_empty():mobile_sound.queue_event("weapon:"+weapon)

func finish_death_audio()->void:
	# The living mesh is replaced by the original corpse. Let its bounded audio
	# tail survive that replacement at the last rendered position.
	if bool(record.get("dead",false)) or not is_instance_valid(mobile_sound):return
	var tail:Node3D=mobile_sound;mobile_sound=null
	tail.reparent(get_parent(),true)
	tail.observe(str(record.template),0,false)
	tail.queue_event("hitheavy");tail.queue_event("hitground")
	get_tree().create_timer(8).timeout.connect(func():
		if is_instance_valid(tail):tail.queue_free())
