extends Node3D
signal original_animation_event(event:String)
var animation_events_available:=false

const AvatarMaterials = preload("res://scripts/avatar_materials.gd")
const AnimationClipCache = preload("res://scripts/animation_clip_cache.gd")
const EquipmentAttachments = preload("res://scripts/npc_equipment.gd")
static var animation_cache_enabled_default := true
var animation_cache_enabled := animation_cache_enabled_default
var animation_skeleton_key := ""

static var catalog_cache: Dictionary = {}
static var model_cache: Dictionary = {}
var catalog: Dictionary = {}
var catalog_directory := ""
var race_id := ""
var race: Dictionary = {}
var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var materials: Array[Dictionary] = []
var native_builder := SwgMeshBuilder.new()
var report: Dictionary = {}
var appearance: Dictionary = {}
var visual_root: Node3D
var texture_cache: Dictionary = {}
var height_meters := 1.8
var base_height := 1.8
var base_bottom := 0.0
var animation_time := 0.0
var animation_player: AnimationPlayer
var current_animation := ""
var loaded_parts: Array = []
var animation_library: Dictionary = {}
var animation_graph: Dictionary = {}
var face_player: AnimationPlayer
var motion_state := "idle"
var body_action := ""
var previous_posture := 0
var previously_grounded := true
var airborne_time := 0.0
var face_action := ""
var last_yaw := 0.0
var preview_animation := ""
var preview_time := 0.4
var clip_rates: Dictionary = {}
var clip_speeds: Dictionary = {}
var jump_phases: Dictionary = {}
var tracking_mode := false
var first_person_hidden_bones: Array = []
var equipment_attachments := EquipmentAttachments.new()
var rigid_equipment: Array = []
var hidden_equipment_ids: Array = []
var hidden_equipment_templates: Array = []
var rebuilding_equipment := false

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func asset_path(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path)
	# Export templates have no project directory: globalize_path can leave
	# sibling data paths relative. Anchor them before composing model paths,
	# otherwise get_model prefixes the catalogue directory a second time.
	if not resolved.is_absolute_path():
		resolved = OS.get_executable_path().get_base_dir().path_join(resolved)
	return resolved.simplify_path()

func load_catalog(path := "") -> Dictionary:
	if path.is_empty():
		path = "res://../runtime/assets/characters/catalog.json"
	path = asset_path(path)
	catalog_directory = path.get_base_dir()
	if not catalog_cache.has(path):
		catalog_cache[path] = read_json(path)
	catalog = catalog_cache[path]
	return catalog

func vec(value, fallback := Vector3.ZERO) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

func quat(value) -> Quaternion:
	if value is Array and value.size() >= 4:
		return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
	return Quaternion.IDENTITY

func configure(id: String, values: Dictionary = {}, equipment: Variant = null) -> Dictionary:
	if catalog.is_empty():
		load_catalog()
	equipment_attachments.release(rigid_equipment)
	rigid_equipment.clear()
	hidden_equipment_ids.clear()
	hidden_equipment_templates.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	meshes.clear()
	materials.clear()
	loaded_parts.clear()
	animation_player = null
	face_player = null
	current_animation = ""
	race_id = id
	appearance = values.duplicate(true)
	race = catalog.get("races", {}).get(id, {})
	report = {"race": id, "parts": 0, "bones": 0, "surfaces": 0, "native": true, "error": ""}
	if race.is_empty():
		report.error = "No locally imported model for " + id
		return report
	visual_root = Node3D.new()
	visual_root.name = "OriginalSWGAvatar"
	add_child(visual_root)
	var body_path: String = race.get("body", race.get("model", ""))
	var model := get_model(body_path)
	if model.is_empty():
		report.error = "Missing imported body model: " + body_path
		return report
	skeleton = build_skeleton(model.get("bones", []))
	first_person_hidden_bones = head_bone_subtree()
	visual_root.add_child(skeleton)
	var skin := Skin.new()
	for i in range(skeleton.get_bone_count()):
		skin.add_bind(i, skeleton.get_bone_global_rest(i).affine_inverse())
	loaded_parts.append({"model": model, "scope": "body", "customization": {}})
	var outfit: Array = race.get("profession_outfits", {}).get(str(values.get("profession", "")), race.get("default_outfit", []))
	if equipment is Array:
		outfit = [] # Explicit authoritative empty means no equipment.
	for item in outfit:
		var path: String = item.get("model", item.get("path", "")) if item is Dictionary else str(item)
		if not path.is_empty():
			loaded_parts.append({"model": get_model(path), "scope": "equipment", "customization": item.get("customization", {}) if item is Dictionary else {},"template":item.get("template","") if item is Dictionary else "","shared_template":item.get("shared_template","") if item is Dictionary else ""})
	var requested_hair: String = values.get("hair_template", "")
	for hair in race.get("hair", []):
		if str(hair.get("template", "")) == requested_hair or str(hair.get("shared_template", "")) == requested_hair:
			loaded_parts.append({"model": get_model(str(hair.get("model", hair.get("path", "")))), "scope": "hair", "customization": {}})
	for record in loaded_parts:
		var first_mesh := meshes.size()
		append_parts(record.model, skin, record.scope, record.customization)
		if record.scope=="equipment":
			for index in range(first_mesh,meshes.size()):
				meshes[index].set_meta("equipment_template",record.get("template",""))
				meshes[index].set_meta("equipment_shared_template",record.get("shared_template",""))
	animation_library = model.get("animation_library", {}).duplicate(true)
	var knockdown_path := ProjectSettings.globalize_path("res://../runtime/assets/combat/player_postures/" + race_id + ".json")
	if FileAccess.file_exists(knockdown_path):
		animation_library["knockdown"] = {"path":knockdown_path}
		# This race-specific original file resolves loop_incapacitated_face_up.
		# DEAD deliberately freezes the same authored pose, not an invented
		# death transition or a clip borrowed from another character skeleton.
		animation_library["incapacitated"] = {"path":knockdown_path, "logical":"loop_incapacitated_face_up"}
		animation_library["dead"] = {"path":knockdown_path, "logical":"loop_incapacitated_face_up", "pose_policy":"Frozen original incapacitated pose for authoritative DEAD"}
	var performance_path := ProjectSettings.globalize_path("res://../runtime/assets/entertainment/catalog.json")
	if FileAccess.file_exists(performance_path):
		var performances: Dictionary = get_model(performance_path)
		for key in performances.get("rigs",{}).get(race_id,{}):
			var clip: Dictionary = performances.rigs[race_id][key].duplicate()
			clip["path"] = performance_path.get_base_dir().path_join(clip.path)
			animation_library[key] = clip
	animation_graph = model.get("animation_graph", {})
	body_action = ""
	face_action = ""
	previous_posture = 0
	previously_grounded = true
	clip_rates.clear()
	clip_speeds.clear()
	build_animations(model.get("animations", {}))
	apply_customization(values)
	# Body bind-space height determines eyes/collision; hair and clothing must
	# never lift the camera or change the character's physical height.
	var lowest := INF
	var highest := -INF
	for part in model.get("parts", []):
		for surface in part.get("mesh", {}).get("surfaces", []):
			var vertices: Array = surface.get("vertices", [])
			for i in range(1, vertices.size(), 3):
				lowest = minf(lowest, float(vertices[i]))
				highest = maxf(highest, float(vertices[i]))
	base_height = highest - lowest if is_finite(highest) and is_finite(lowest) else 1.8
	base_bottom = lowest if is_finite(lowest) else 0.0
	visual_root.position.y = -base_bottom * visual_root.scale.y
	height_meters = maxf(1.0, base_height * visual_root.scale.y)
	update_motion(0.0)
	report["height_meters"] = height_meters
	if tracking_mode:
		set_tracking_mode(true)
	if equipment is Array:
		refresh_equipment(equipment)
	return report

func equipment_selection(equipment: Array) -> Dictionary:
	var result := {"parts":[],"rigid":[],"failures":[]}
	var known: Array = race.get("default_outfit", []).duplicate()
	for items in race.get("profession_outfits", {}).values(): known.append_array(items)
	var directory := asset_path("res://../runtime/assets/inventory")
	var inventory_catalog := read_json(directory.path_join("catalog.json"))
	var variants: Dictionary = inventory_catalog.get("equipment",{}).get(race_id,{})
	for value in equipment:
		var item: Dictionary = value if value is Dictionary else {"template":str(value)}
		var template := str(item.get("template",item.get("shared_template","")))
		var shared := str(item.get("shared_template",template))
		# Core3 equips the intrinsic unarmed attack object in default_weapon.
		# This logical combat object has no worn/held source geometry.
		if template in ["object/weapon/melee/unarmed/unarmed_default_player.iff", "object/weapon/melee/unarmed/shared_unarmed_default_player.iff"] and item.get("equipped_slots", []).has("default_weapon"):
			continue
		var selected: Dictionary = {}
		var material_directory := catalog_directory
		# Fresh prepared variants take precedence over source starter choices.
		for candidate: Dictionary in variants.values():
			if template==str(candidate.get("template","")) or shared==str(candidate.get("shared_template","")) or template==str(candidate.get("shared_template","")):
				if candidate.get("status","")=="ready": selected=candidate; material_directory=directory
				break
		if selected.is_empty():
			for candidate: Dictionary in known:
				if template==str(candidate.get("template","")) or shared==str(candidate.get("shared_template","")) or template==str(candidate.get("shared_template","")):
					selected=candidate; break
		if selected.is_empty():
			var key: String=str(inventory_catalog.get("aliases",{}).get(template,template))
			var candidate: Dictionary=inventory_catalog.get("items",{}).get(key,{})
			if candidate.get("status","")=="ready" and candidate.get("material_pipeline","")=="original_static":
				selected=candidate.duplicate(); selected["kind"]="rigid"; material_directory=directory
		if selected.is_empty():
			result.failures.append({"id":str(item.get("id","")),"template":template,"error":"Original equipped appearance is not prepared for "+race_id})
			continue
		var path := str(selected.get("model",selected.get("path","")))
		if not path.is_absolute_path(): path=material_directory.path_join(path)
		if selected.get("kind","skinned")=="rigid":
			var allowed: Array=item.get("equipped_slots",[])
			var bone := ""
			for slots: Array in selected.get("source_arrangements",[]):
				for slot in slots:
					if (allowed.is_empty() or allowed.has(slot)) and skeleton.find_bone(str(slot))>=0:
						bone=str(slot); break
				if not bone.is_empty(): break
			var grip_basis:=Basis.IDENTITY
			var attachment_provenance:="original_source_arrangement"
			# Core3 explicitly equips these four legacy inventory-only heavies in
			# hold_both. Preserve the original empty descriptor; the verified
			# equipped slots supply this narrow authored attachment exception.
			var native_heavy:bool=template in ["object/weapon/ranged/heavy/heavy_particle_beam.iff","object/weapon/ranged/heavy/heavy_acid_beam.iff","object/weapon/ranged/heavy/heavy_lightning_beam.iff","object/weapon/ranged/heavy/heavy_rocket_launcher.iff"]
			if bone.is_empty() and native_heavy and selected.get("source_arrangement","")=="abstract/slot/arrangement/wearables/empty.iff" and allowed.has("hold_r") and allowed.has("hold_l") and skeleton.find_bone("hold_r")>=0:
				bone="hold_r"
				grip_basis=preload("res://combat/original_assets.gd").grip_basis(template.get_file().get_basename())
				attachment_provenance="native_commando_hold_both"
			if bone.is_empty():
				result.failures.append({"id":str(item.get("id","")),"template":template,"error":"No original equipped arrangement maps to this skeleton"})
				continue
			var local_transform:Array=[grip_basis.x.x,grip_basis.y.x,grip_basis.z.x,0,grip_basis.x.y,grip_basis.y.y,grip_basis.z.y,0,grip_basis.x.z,grip_basis.y.z,grip_basis.z.z,0]
			result.rigid.append({"id":str(item.get("id","")),"template":template,"shared_template":shared,"bone":bone,"model":path,"directory":material_directory,"local_transform":local_transform,"local_transform_layout":"row_major_3x4","source_arrangement":selected.get("source_arrangement",""),"attachment_provenance":attachment_provenance})
			continue
		var model := get_model(path)
		if model.is_empty():
			result.failures.append({"id":str(item.get("id","")),"template":template,"error":"Missing imported equipped model: "+path})
			continue
		var bones: Array=model.get("bones",[])
		var compatible := not model.is_empty() and bones.size()==skeleton.get_bone_count()
		if compatible:
			for index in range(bones.size()):
				var bone: Dictionary=bones[index]
				var rest := Transform3D(Basis(quat(bone.get("rest_rotation",[]))),vec(bone.get("rest_position",[])))
				if str(bone.name)!=skeleton.get_bone_name(index) or int(bone.get("parent",-1))!=skeleton.get_bone_parent(index) or not rest.is_equal_approx(skeleton.get_bone_rest(index)):
					compatible=false; break
		if not compatible:
			result.failures.append({"id":str(item.get("id","")),"template":template,"error":"Equipped model does not match the existing original skeleton"})
			continue
		result.parts.append({"model":model,"scope":"equipment","customization":item.get("customization",{}),"template":template,"shared_template":shared,"id":str(item.get("id","")),"directory":material_directory})
	return result

func refresh_equipment(equipment: Array) -> Dictionary:
	if not is_instance_valid(skeleton): return {"ok":false,"error":"Avatar skeleton is unavailable"}
	var selection := equipment_selection(equipment)
	var previous_meshes := meshes
	var previous_materials := materials
	var previous_parts := loaded_parts
	var previous_report := report.duplicate(true)
	var visual_transform := visual_root.transform
	var physical_height := height_meters
	loaded_parts=[]
	for part: Dictionary in previous_parts:
		if part.scope!="equipment": loaded_parts.append(part)
	loaded_parts.append_array(selection.parts)
	meshes=[]; materials=[]
	report.parts=0; report.surfaces=0; report.error=""; report["partitioned_head_triangles"]=0
	var skin := Skin.new()
	for index in range(skeleton.get_bone_count()): skin.add_bind(index,skeleton.get_bone_global_rest(index).affine_inverse())
	rebuilding_equipment=true
	for record: Dictionary in loaded_parts:
		var start := meshes.size()
		append_parts(record.model,skin,record.scope,record.customization,str(record.get("directory",catalog_directory)))
		if record.scope=="equipment":
			for index in range(start,meshes.size()):
				meshes[index].set_meta("equipment_id",str(record.get("id","")))
				meshes[index].set_meta("equipment_template",record.get("template",""))
				meshes[index].set_meta("equipment_shared_template",record.get("shared_template",""))
	rebuilding_equipment=false
	if not str(report.error).is_empty():
		var failure := str(report.error)
		for mesh in meshes: mesh.free()
		meshes=previous_meshes; materials=previous_materials; loaded_parts=previous_parts; report=previous_report
		return {"ok":false,"error":failure,"failures":selection.failures}
	apply_customization(appearance)
	# Calibration/tracking may have moved/scaled the visual root since configure.
	visual_root.transform=visual_transform; height_meters=physical_height
	for mesh in previous_meshes: mesh.free()
	for mesh in meshes: mesh.visible=true
	for item: Dictionary in rigid_equipment:
		if is_instance_valid(item.get("attachment")): item.attachment.visible=false
	equipment_attachments.release(rigid_equipment)
	rigid_equipment=[]
	for item: Dictionary in selection.rigid:
		var attached := equipment_attachments.attach(self,[item],str(item.directory),false)
		rigid_equipment.append_array(attached.items)
		selection.failures.append_array(attached.failures)
		for attachment: Dictionary in attached.items:
			attachment.instance.set_meta("equipment_id",str(item.id))
			attachment.instance.set_meta("equipment_template",str(item.template))
			attachment.instance.set_meta("equipment_shared_template",str(item.shared_template))
	set_equipment_visual_hidden(hidden_equipment_ids,hidden_equipment_templates)
	report["equipment_failures"]=selection.failures
	report["equipment_requested"]=equipment.size()
	report["equipment_skinned_items"]=selection.parts.size()
	report["equipment_rigid_items"]=rigid_equipment.size()
	report["equipment_complete"]=selection.failures.is_empty()
	return {"ok":true,"complete":selection.failures.is_empty(),"skinned_items":selection.parts.size(),"rigid_items":rigid_equipment.size(),"failures":selection.failures}

func set_equipment_visual_hidden(ids: Array, templates: Array=[]) -> void:
	hidden_equipment_ids=ids.duplicate(); hidden_equipment_templates=templates.duplicate()
	var equipment_meshes: Array=meshes.duplicate()
	for record: Dictionary in rigid_equipment:
		if is_instance_valid(record.get("instance")): equipment_meshes.append(record.instance)
	for mesh: MeshInstance3D in equipment_meshes:
		if not mesh.has_meta("equipment_template"): continue
		mesh.visible=not (ids.has(str(mesh.get_meta("equipment_id",""))) or templates.has(str(mesh.get_meta("equipment_template",""))) or templates.has(str(mesh.get_meta("equipment_shared_template",""))))

func get_model(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var full_path: String = path if path.is_absolute_path() else catalog_directory.path_join(path)
	if not model_cache.has(full_path):
		model_cache[full_path] = read_json(full_path)
	return model_cache[full_path]

func build_skeleton(bones: Array) -> Skeleton3D:
	animation_skeleton_key = AnimationClipCache.digest(bones)
	var result := Skeleton3D.new()
	result.name = "Skeleton"
	for bone in bones:
		result.add_bone(str(bone.get("name", "bone_%d" % result.get_bone_count())))
	for i in range(bones.size()):
		var bone: Dictionary = bones[i]
		var parent := int(bone.get("parent", -1))
		if parent >= 0 and parent < bones.size():
			result.set_bone_parent(i, parent)
		var transform := Transform3D(Basis(quat(bone.get("rest_rotation", [0, 0, 0, 1]))), vec(bone.get("rest_position", [0, 0, 0])))
		result.set_bone_rest(i, transform)
	result.reset_bone_poses()
	report.bones = bones.size()
	return result

func append_parts(model: Dictionary, skin: Skin, scope := "body", item_customization: Dictionary = {}, material_directory := "") -> void:
	if model.is_empty():
		return
	for part in model.get("parts", []):
		var definition: Dictionary = part.get("mesh", {}).duplicate(false)
		var covered := {}
		var layer: int = int(definition.get("occlusion_layer", 0))
		for record in loaded_parts:
			for other in record.model.get("parts", []):
				var other_mesh: Dictionary = other.get("mesh", {})
				if int(other_mesh.get("occlusion_layer", 0)) > layer:
					for zone in other_mesh.get("occludes", []):
						covered[zone] = true
		var filtered: Array = []
		for original_surface in definition.get("surfaces", []):
			var surface: Dictionary = original_surface.duplicate(false)
			var indices: Array = surface.get("indices", [])
			var zones: Array = surface.get("triangle_zones", [])
			if not covered.is_empty() and zones.size() == indices.size() / 3:
				var visible_indices: Array = []
				var visible_zones: Array = []
				for triangle in range(zones.size()):
					var hidden: bool = not zones[triangle].is_empty()
					for zone in zones[triangle]:
						if not covered.has(zone):
							hidden = false
					if not hidden:
						visible_indices.append_array(indices.slice(triangle * 3, triangle * 3 + 3))
						visible_zones.append(zones[triangle])
				surface["indices"] = visible_indices
				surface["triangle_zones"] = visible_zones
				if visible_indices.is_empty():
					continue
			filtered.append(surface)
		definition["surfaces"] = filtered
		if filtered.is_empty():
			continue
		definition["bone_count"] = skeleton.get_bone_count()
		var part_name: String = str(part.get("id", "AvatarPart"))
		var authored_head := scope == "hair" or "head" in part_name.to_lower() or "face" in part_name.to_lower()
		if authored_head:
			append_partition(definition, skin, part_name, true, scope, item_customization,material_directory)
			continue
		var split: Dictionary = native_builder.partition_avatar(definition, first_person_hidden_bones, 0.45)
		if split.is_empty():
			report.error = "Native first-person partition rejected avatar part " + part_name
			continue
		append_partition(split.body, skin, part_name, false, scope, item_customization,material_directory)
		append_partition(split.head, skin, part_name + "_neck_head", true, scope, item_customization,material_directory)
		report["partitioned_head_triangles"] = int(report.get("partitioned_head_triangles", 0)) + int(split.statistics.head_triangles)

func head_bone_subtree() -> Array:
	var hidden: Array = []
	var neck := skeleton.find_bone("neck")
	var head := skeleton.find_bone("head")
	for index in range(skeleton.get_bone_count()):
		var ancestor := index
		while ancestor >= 0:
			if ancestor == neck or ancestor == head:
				hidden.append(index)
				break
			ancestor = skeleton.get_bone_parent(ancestor)
	return hidden

func append_partition(definition: Dictionary, skin: Skin, part_name: String, head_part: bool, scope: String, item_customization: Dictionary, material_directory := "") -> void:
	var surfaces: Array = definition.get("surfaces", [])
	if surfaces.is_empty():
		return
	var mesh: ArrayMesh = native_builder.create_avatar_mesh(definition)
	if mesh == null:
		report.error = "Native conversion rejected avatar part " + part_name
		return
	var instance := MeshInstance3D.new()
	instance.name = part_name.replace("/", "_")
	instance.mesh = mesh
	instance.skin = skin
	instance.skeleton = NodePath("..")
	# Layer 1 is the visible first-person body/arms. Layer 2 completes the
	# original mesh for other cameras; no bone scaling or global hiding occurs.
	instance.layers = 2 if head_part else 1
	instance.set_meta("head_part", head_part)
	instance.set_meta("scope", scope)
	instance.visible=not rebuilding_equipment
	skeleton.add_child(instance)
	for i in range(mesh.get_surface_count()):
		var material := AvatarMaterials.create(surfaces[i],catalog_directory if material_directory.is_empty() else material_directory)
		mesh.surface_set_material(i, material)
		materials.append({"material": material, "source": surfaces[i], "scope": scope, "customization": item_customization})
	meshes.append(instance)
	report.parts += 1
	report.surfaces += mesh.get_surface_count()

func set_tracking_mode(enabled: bool) -> void:
	tracking_mode = enabled
	report["tracking_mode"] = enabled
	body_action = ""
	face_action = ""
	preview_animation = ""
	current_animation = ""
	for player in [animation_player, face_player]:
		if player != null:
			player.pause()
			player.active = not enabled
	if skeleton != null:
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
	if enabled:
		motion_state = "tracked_rest"
		report["tracking_neutral_pose"] = "source_skeleton_rest"
	elif animation_player != null:
		previous_posture = 0
		previously_grounded = true
		update_motion(0.0)
		animation_player.advance(0.0)
		if face_player != null and ensure_animation("face_idle"):
			face_player.play("face_idle")

func make_material(surface: Dictionary) -> Material:
	return AvatarMaterials.create(surface, catalog_directory)

func apply_customization(values: Dictionary) -> void:
	appearance = values.duplicate(true)
	var custom: Dictionary = values.get("customization", {})
	var hair_custom: Dictionary = values.get("hair_customization", {})
	var controls = race.get("customizations", race.get("appearance_controls", []))
	if controls is Dictionary:
		var converted: Array = []
		for key in controls:
			var entry: Dictionary = controls[key].duplicate(true)
			entry["id"] = key
			converted.append(entry)
		controls = converted
	for mesh in meshes:
		for blend_idx in range(mesh.mesh.get_blend_shape_count()):
			var blend_name: String = str(mesh.mesh.get_blend_shape_name(blend_idx))
			var shape_values: Dictionary = hair_custom if mesh.get_meta("scope", "body") == "hair" else custom
			mesh.set_blend_shape_value(blend_idx, clampf(custom_value(shape_values, blend_name, custom_value(custom, blend_name, 0)) / 255.0, -1.0, 1.0))
	for entry in materials:
		var scoped: Dictionary = custom.duplicate() if entry.scope == "body" else {}
		if entry.scope != "body":
			for key in custom:
				if str(key).begins_with("/shared_owner/"):
					scoped[key] = custom[key]
			scoped.merge(entry.customization if entry.scope == "equipment" else hair_custom, true)
		AvatarMaterials.apply(entry.material, scoped)
	if visual_root != null:
		var factor := float(values.get("height", 1.0))
		visual_root.scale = Vector3.ONE * factor
		visual_root.position.y = -base_bottom * factor
		height_meters = maxf(1.0, base_height * factor)

func custom_value(values: Dictionary, key: String, fallback := 0.0) -> float:
	if values.has(key):
		return float(values[key])
	var short_name := key.get_file()
	for candidate in values:
		if str(candidate).get_file() == short_name:
			return float(values[candidate])
	return fallback

func make_animation_player(node_name: String) -> AnimationPlayer:
	var result := AnimationPlayer.new()
	result.name = node_name
	visual_root.add_child(result)
	result.root_node = NodePath("..")
	result.add_animation_library("", AnimationLibrary.new())
	return result

func build_animations(clips: Dictionary) -> void:
	if clips.is_empty():
		return
	animation_player = make_animation_player("OriginalAnimations")
	face_player = make_animation_player("OriginalFaceAnimations")
	for clip_name in clips:
		add_animation_clip(str(clip_name), clips[clip_name], animation_player)
	report["animation_source"] = "original_swg_ans"
	report["animation_states"] = clips.keys()
	report["animation_actions"] = animation_library.keys()
	report["animation_limitations"] = animation_graph.get("unavailable", [])
	update_motion(0.0)
	animation_player.advance(0.0)
	if not tracking_mode and ensure_animation("face_idle"):
		face_player.play("face_idle")

func add_animation_clip(clip_name: String, clip: Dictionary, target: AnimationPlayer) -> void:
	if not clip.get("messages",[]).is_empty():animation_events_available=true
	clip_rates[clip_name] = float(clip.get("source_speed_scale", 1.0))
	if clip.has("source_speed_mps"):
		clip_speeds[clip_name] = float(clip.source_speed_mps)
	if clip_name == "jump":
		jump_phases = derive_jump_phases(clip)
	var cache_key := AnimationClipCache.key(clip_name,clip,animation_skeleton_key) if animation_cache_enabled else ""
	var cached: Animation = AnimationClipCache.find(cache_key) if animation_cache_enabled else null
	if cached!=null:
		target.get_animation_library("").add_animation(clip_name,cached)
		return
	var animation := Animation.new()
	animation.length = maxf(0.1, float(clip.get("length", 1)))
	animation.loop_mode = Animation.LOOP_LINEAR if clip.get("loop", true) else Animation.LOOP_NONE
	for track in clip.get("tracks", []):
		var bone_name: String = str(track.get("name", ""))
		if skeleton.find_bone(bone_name) < 0:
			continue
		var rotations: Array = track.get("rotations", [])
		if not rotations.is_empty():
			var index := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(index, NodePath("Skeleton:" + bone_name))
			for key in rotations:
				animation.rotation_track_insert_key(index, float(key[0]), Quaternion(float(key[1]), float(key[2]), float(key[3]), float(key[4])).normalized())
		var positions: Array = track.get("positions", [])
		if not positions.is_empty():
			var index := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(index, NodePath("Skeleton:" + bone_name))
			for key in positions:
				var position := Vector3(float(key[1]), float(key[2]), float(key[3]))
				if bone_name == "root":
					var rest: Vector3 = skeleton.get_bone_rest(skeleton.find_bone(bone_name)).origin
					position.x = rest.x
					position.z = rest.z
					if clip_name == "jump":
						# Remove authored upward root travel already supplied by
						# physics; retain the original landing compression.
						position.y = minf(position.y, float(jump_phases.get("baseline", rest.y)))
				animation.position_track_insert_key(index, float(key[0]), position)
	var messages:Array=clip.get("messages",[])
	if not messages.is_empty():
		var event_track:=animation.add_track(Animation.TYPE_METHOD)
		animation.track_set_path(event_track,NodePath(".."))
		for message:Dictionary in messages:
			var original:=str(message.get("message",""))
			var event:=""
			if original.begins_with("event_"):event=original.trim_prefix("event_")
			elif original.begins_with("hpevent_"):event=original.get_slice("_",original.get_slice_count("_")-1)
			if not event.is_empty():
				animation.track_insert_key(event_track,float(message.seconds),{"method":"emit_original_animation_event","args":[event]})
	if animation_cache_enabled: AnimationClipCache.publish(cache_key,animation)
	target.get_animation_library("").add_animation(clip_name, animation)

func derive_jump_phases(clip: Dictionary) -> Dictionary:
	var result := {"takeoff": 0.0, "apex": float(clip.length) * 0.5, "land": float(clip.length) * 0.65}
	for track in clip.get("tracks", []):
		if track.get("name", "") != "root" or track.get("positions", []).is_empty():
			continue
		var keys: Array = track.positions
		var baseline := float(keys[0][2])
		var peak := 0
		for i in range(keys.size()):
			if float(keys[i][2]) > float(keys[peak][2]):
				peak = i
		result.baseline = baseline
		result.apex = float(keys[peak][0])
		for i in range(peak, -1, -1):
			if float(keys[i][2]) <= baseline:
				result.takeoff = float(keys[mini(i + 1, peak)][0])
				break
		for i in range(peak, keys.size()):
			if float(keys[i][2]) <= baseline:
				result.land = float(keys[i][0])
				break
	return result

func ensure_animation(key: String) -> bool:
	var target := face_player if key.begins_with("face_") else animation_player
	if target == null:
		return false
	if target.has_animation(key):
		return true
	if not animation_library.has(key):
		return false
	var clip := get_model(str(animation_library[key].path))
	if clip.is_empty():
		return false
	add_animation_clip(key, clip, target)
	return true

func play_action(key: String) -> bool:
	if tracking_mode or not ensure_animation(key):
		return false
	if key.begins_with("face_"):
		face_player.play(key, 0.12)
		face_player.speed_scale = float(clip_rates.get(key, 1))
		face_action = key
	else:
		animation_player.play(key, 0.15)
		animation_player.speed_scale = float(clip_rates.get(key, 1))
		body_action = key
		current_animation = key
	return true

func sample_life_pose(key: String, seconds: float) -> Dictionary:
	# Full source-skeleton sampling for an authoritative life lock. Animation
	# players remain disabled in tracking mode; no HMD/controller node is touched.
	if key not in ["incapacitated","dead"] or not is_finite(seconds) or not ensure_animation(key):
		return {"valid":false,"error":"Original character life pose unavailable"}
	var animation: Animation = animation_player.get_animation(key)
	var sample_time := 0.0 if key == "dead" else fposmod(maxf(seconds,0.0),animation.length)
	animation_player.pause()
	if face_player != null: face_player.pause()
	skeleton.reset_bone_poses()
	var bones: Dictionary = {}
	for track in range(animation.get_track_count()):
		var path: NodePath = animation.track_get_path(track)
		if path.get_subname_count() < 1: continue
		var bone := skeleton.find_bone(str(path.get_subname(0)))
		if bone < 0: continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone,animation.position_track_interpolate(track,sample_time))
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone,animation.rotation_track_interpolate(track,sample_time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone,animation.scale_track_interpolate(track,sample_time))
		bones[bone] = true
	skeleton.force_update_all_bone_transforms()
	current_animation = key
	motion_state = key
	var original := get_model(str(animation_library[key].path))
	return {"valid":not bones.is_empty(),"state":key,"time":sample_time,"full_body":true,"bones":bones.size(),
		"source":original.get("source",""),"source_sha256":original.get("source_sha256",""),
		"frozen":key == "dead","pose_policy":"Original incapacitated_face_up loop; native DEAD freezes this original pose, without an invented death transition"}

func select_motion_state(local_velocity: Vector3, grounded: bool, posture: int, turning := 0.0) -> String:
	if not grounded:
		return "jump" if local_velocity.y > 0.1 else "fall"
	var moving := Vector2(local_velocity.x, local_velocity.z).length() > 0.2
	if posture == 3:
		return "sit"
	if posture == 2:
		return "crawl" if moving else "prone"
	if posture == 1:
		return "crouch_walk" if moving else "crouch"
	if moving:
		if absf(local_velocity.x) > absf(local_velocity.z) * 0.9:
			return "strafe_right" if local_velocity.x > 0 else "strafe_left"
		if local_velocity.z > 0.2:
			return "backpedal"
		return "run" if Vector2(local_velocity.x, local_velocity.z).length() > 6.5 else "walk"
	if absf(turning) > 0.4:
		return "turn_left" if turning > 0 else "turn_right"
	return "idle"

func update_motion(delta: float, movement_speed := 0.0, context: Dictionary = {}) -> void:
	if tracking_mode or animation_player == null:
		return
	var presentation: Dictionary = context.get("presentation", {})
	var forced := "knockdown" if presentation.get("knocked_down", false) else "jump" if float(presentation.get("jump_time", -1)) >= 0 else ""
	if presentation.get("life_locked",false): forced = str(presentation.get("life_animation","incapacitated"))
	if forced.is_empty(): forced = str(presentation.get("performance_clip",""))
	if not forced.is_empty() and ensure_animation(forced):
		if current_animation != forced: animation_player.play(forced, 0.12)
		current_animation = forced
		motion_state = forced
		if forced == "dead":
			animation_player.seek(0.0,true)
			animation_player.pause()
		elif forced == "jump": animation_player.seek(float(presentation.jump_time), true)
		elif forced.begins_with("perform_"):
			var duration: float = animation_player.get_animation(forced).length
			animation_player.seek(fmod(float(presentation.get("performance_time",0)),duration),true)
		return
	if not preview_animation.is_empty() and ensure_animation(preview_animation):
		animation_player.play(preview_animation)
		animation_player.seek(preview_time, true)
		animation_player.pause()
		motion_state = preview_animation
		return
	var velocity: Vector3 = context.get("velocity", Vector3(0, 0, -movement_speed))
	var grounded: bool = context.get("grounded", true)
	var posture: int = context.get("posture", 0)
	motion_state = select_motion_state(velocity, grounded, posture, float(context.get("turn_rate", 0)))
	if face_player != null and not face_action.is_empty() and not face_player.is_playing():
		face_action = ""
		if ensure_animation("face_idle"):
			face_player.play("face_idle", 0.15)
	if posture != previous_posture:
		var names := ["stand", "crouch", "prone", "sit"]
		var transition: String = names[previous_posture] + "_to_" + names[posture]
		body_action = ""
		if ensure_animation(transition):
			play_action(transition)
		previous_posture = posture
	if not grounded and ensure_animation("jump"):
		airborne_time = airborne_time + delta if not previously_grounded else 0.0
		animation_player.play("jump", 0.08)
		var takeoff := float(jump_phases.get("takeoff", 0))
		var apex := float(jump_phases.get("apex", 0.3))
		var pose_time := minf(apex, takeoff + airborne_time)
		if velocity.y <= 0:
			pose_time = minf(float(jump_phases.get("land", apex)), apex + maxf(0, airborne_time - (apex - takeoff)))
		animation_player.seek(pose_time, true)
		animation_player.pause()
		current_animation = "jump"
		body_action = ""
		previously_grounded = false
		return
	if not previously_grounded and grounded and ensure_animation("jump"):
		animation_player.play("jump", 0.08)
		animation_player.seek(float(jump_phases.get("land", animation_player.get_animation("jump").length * 0.65)), true)
		animation_player.speed_scale = 1.5
		body_action = "landing"
		current_animation = "jump"
		motion_state = "land"
	previously_grounded = grounded
	if not body_action.is_empty():
		if body_action.begins_with("emote_") and (movement_speed > 0.2 or posture != 0):
			body_action = ""
		elif animation_player.is_playing():
			if body_action == "landing":
				motion_state = "land"
			return
		else:
			body_action = ""
	var desired := motion_state
	if not ensure_animation(desired):
		desired = "idle"
	if desired != current_animation and animation_player.has_animation(desired):
		animation_player.play(desired, 0.15)
		current_animation = desired
	animation_player.speed_scale = float(clip_rates.get(desired, 1.0)) * (clampf(movement_speed / (7.0 if desired == "run" else 3.0), 0.7, 1.8) if desired in ["walk", "run", "strafe_left", "strafe_right", "backpedal"] else 1.0)

func main_palette_variables(model_path: String) -> Array:
	# Historical method name retained for creator compatibility. The material
	# helper now evaluates primary/secondary palettes, texture selectors and TRT.
	var result: Array = []
	for part in get_model(model_path).get("parts", []):
		for surface in part.get("mesh", {}).get("surfaces", []):
			for variable in AvatarMaterials.supported_variables(surface):
				if not variable in result:
					result.append(variable)
	return result

func emit_original_animation_event(event:String)->void:
	if not tracking_mode:original_animation_event.emit(event)
