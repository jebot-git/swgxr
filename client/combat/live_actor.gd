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
var speed:=0.0
var last_snapshot_position:=Vector3.ZERO
var snapshot_usec:=0
var report:Dictionary={}
var equipment:=NPCEquipment.new()
var rigid_equipment:Array=[]
var carrier:RefCounted
var presentation_floor_offset:=Vector3.ZERO
var presentation_floor_height:=0.0
var mobile_sound:Node3D

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
	if bool(record.get("droid",false)) and source_visual.is_empty():
		mobile_sound=preload("res://audio/mobile_emitter.gd").new();add_child(mobile_sound)
	var bounds:=visual_bounds()
	collider=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=bounds.size.max(Vector3.ONE*0.05);collider.shape=box;collider.position=bounds.get_center();add_child(collider)
	collision_layer=0 if record.dead or carrier!=null else 8
	if carrier!=null:collider.disabled=true
	make_label(Vector3(bounds.get_center().x,bounds.end.y+0.18,bounds.get_center().z))
	if carrier!=null:label.hide()
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

func apply_record(value:Dictionary,pose:Transform3D,seconds:float,initial:=false)->void:
	if not initial and is_instance_valid(mobile_sound) and not value.dead and float(value.health)<float(record.get("health",value.health)):
		mobile_sound.queue_event("hitlight")
	record=value.duplicate(true);snapshot_usec=Time.get_ticks_usec()
	if carrier!=null:carrier.apply(int(record.get("posture",0)))
	speed=last_snapshot_position.distance_to(pose.origin)/maxf(seconds,0.05) if not initial else 0.0
	if is_instance_valid(mobile_sound):mobile_sound.observe(str(record.template),speed,not bool(record.dead))
	last_snapshot_position=pose.origin;goal=pose
	if initial or global_position.distance_to(goal.origin)>8:global_transform=goal
	collision_layer=8 if is_targetable() else 0
	refresh_label()

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
	label.text=str(record.get("name","Core3 entity"))+"\n"+("Dead · Core3 confirmed" if record.dead else "%d / %d"%[int(record.health),int(record.max_health)])

	if report.get("appearance_status","")=="partial":label.text+="\nSome original components unavailable"
	elif report.get("appearance_status","")=="unavailable":label.text+="\nOriginal appearance unavailable · cannot target"

func core3_identity()->Dictionary:
	return {"id":str(record.id),"session_id":session_id,"dead":bool(record.dead),"targetable":is_targetable()}

func get_radar_contact()->Dictionary:
	return {"id":str(record.id),"position":global_position,"kind":"mob","relation":str(record.get("relation","neutral")),"alive":not bool(record.dead),"radar_visible":record.kind=="creature"}

func _process(delta:float)->void:
	global_transform=global_transform.interpolate_with(goal,1.0-exp(-delta*14.0))
	if carrier==null and is_instance_valid(visual) and visual.has_method("update_motion") and not record.dead:visual.update_motion(delta,speed,{"grounded":true,"velocity":Vector3(0,0,-speed)})

func _exit_tree()->void:
	equipment.release(rigid_equipment)
