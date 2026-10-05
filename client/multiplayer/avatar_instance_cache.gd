extends RefCounted
## Bounded assembled source geometry cache. Skeletons, animation playback,
## material overrides and blend shapes are independent per remote player.
const Avatar = preload("res://scripts/avatar.gd")
const MAX_ENTRIES := 8
var entries: Dictionary = {}
var serial := 0
var hits := 0
var misses := 0

func key(appearance: Dictionary) -> String:
	var visual := appearance.duplicate(true)
	var equipment: Array = []
	for item: Dictionary in visual.get("equipment", []):
		equipment.append({"template":item.get("template",""),"shared_template":item.get("shared_template",""),"customization":item.get("customization",{}),"equipped_slots":item.get("equipped_slots",[])})
	visual["equipment"] = equipment
	return JSON.stringify(visual)

func instantiate(appearance: Dictionary) -> Node3D:
	var fingerprint := key(appearance)
	if not entries.has(fingerprint): misses += 1; return null
	serial += 1; hits += 1; entries[fingerprint].used = serial
	var source: Node3D = entries[fingerprint].avatar
	var result := copy_avatar(source)
	# Object IDs are ownership identities, not geometric variation. Never retain
	# another character's equipment IDs in an otherwise identical cached outfit.
	var current: Dictionary = {}
	for item: Dictionary in appearance.get("equipment", []):
		current[str(item.get("template", item.get("shared_template", "")))] = str(item.get("id", ""))
	for mesh: MeshInstance3D in result.meshes:
		if mesh.has_meta("equipment_template"):
			mesh.set_meta("equipment_id", current.get(str(mesh.get_meta("equipment_template")), ""))
	for item: Dictionary in result.rigid_equipment:
		item.instance.set_meta("equipment_id", current.get(str(item.instance.get_meta("equipment_template", "")), ""))
	return result

func remember(appearance: Dictionary, source: Node3D) -> void:
	if source == null or source.visual_root == null: return
	var fingerprint := key(appearance)
	if entries.has(fingerprint): return
	while entries.size() >= MAX_ENTRIES:
		var oldest: String = entries.keys()[0]
		for candidate: String in entries:
			if entries[candidate].used < entries[oldest].used: oldest = candidate
		entries[oldest].avatar.free(); entries.erase(oldest)
	serial += 1
	entries[fingerprint] = {"avatar":copy_avatar(source), "used":serial}

func copy_avatar(source: Node3D) -> Node3D:
	var copy := Avatar.new()
	# All three resources below contain immutable imported dictionaries; avoid
	# copying hundreds of thousands of source vertices for every player.
	for property in ["catalog", "race", "loaded_parts", "animation_library", "animation_graph", "texture_cache"]:
		copy.set(property, source.get(property))
	for property in ["catalog_directory", "race_id", "animation_skeleton_key", "animation_cache_enabled", "height_meters", "base_height", "base_bottom", "current_animation", "motion_state", "previous_posture", "previously_grounded", "tracking_mode", "preview_animation", "preview_time"]:
		copy.set(property, source.get(property))
	for property in ["report", "appearance", "clip_rates", "clip_speeds", "jump_phases", "first_person_hidden_bones"]:
		copy.set(property, source.get(property).duplicate(true))
	copy.visual_root = source.visual_root.duplicate(0)
	copy.add_child(copy.visual_root)
	copy.skeleton = mapped_node(source.visual_root, copy.visual_root, source.skeleton)
	for property in ["animation_player", "face_player"]:
		var original: AnimationPlayer = source.get(property)
		if original == null: continue
		var player: AnimationPlayer = mapped_node(source.visual_root, copy.visual_root, original)
		copy.set(property, player)
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name).duplicate()
			player.remove_animation_library(library_name)
			player.add_animation_library(library_name, library)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var materials: Dictionary = {}
	for original: MeshInstance3D in source.meshes:
		var mesh: MeshInstance3D = mapped_node(source.visual_root, copy.visual_root, original)
		copy.meshes.append(mesh)
		for surface in range(mesh.mesh.get_surface_count()):
			var material: Material = original.get_active_material(surface)
			if material == null: continue
			var id := material.get_instance_id()
			if not materials.has(id): materials[id] = material.duplicate()
			mesh.set_surface_override_material(surface, materials[id])
	for entry: Dictionary in source.materials:
		var value := entry.duplicate()
		value.material = materials.get(entry.material.get_instance_id(), entry.material.duplicate())
		copy.materials.append(value)
	for original: Dictionary in source.rigid_equipment:
		var item := original.duplicate()
		item.attachment = mapped_node(source.visual_root, copy.visual_root, original.attachment)
		item.instance = mapped_node(source.visual_root, copy.visual_root, original.instance)
		copy.rigid_equipment.append(item)
	return copy

func mapped_node(source_root: Node, target_root: Node, original: Node) -> Node:
	# Godot may rename generated @MeshInstance names during duplicate. Child
	# indices preserve the source graph without relying on those transient names.
	var indices: Array[int] = []
	while original != source_root:
		indices.push_front(original.get_index())
		original = original.get_parent()
	var target := target_root
	for index in indices: target = target.get_child(index)
	return target

func clear() -> void:
	for entry in entries.values(): entry.avatar.free()
	entries.clear()
