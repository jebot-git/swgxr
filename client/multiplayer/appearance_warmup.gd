extends RefCounted
## Worker performs immutable file I/O / JSON parsing only. Godot scene objects,
## caches and mesh construction stay on the main thread.
static func read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 64 * 1024 * 1024: return {}
	var result: Variant = JSON.parse_string(file.get_as_text())
	return result if result is Dictionary else {}

static func load_appearance(path: String, appearance: Dictionary, catalog: Dictionary, cached_models: Dictionary) -> Dictionary:
	if catalog.is_empty(): catalog = read_dictionary(path)
	var directory := path.get_base_dir()
	var descriptor: Dictionary = {}
	var race := ""
	var template := str(appearance.get("template", appearance.get("shared_template", "")))
	for id: String in catalog.get("races", {}):
		var candidate: Dictionary = catalog.races[id]
		if not template.is_empty() and template in [str(candidate.get("template", "")), str(candidate.get("shared_template", ""))]:
			descriptor = candidate
			race = id
			break
	var paths: Array = []
	if not descriptor.is_empty():
		paths.append(directory.path_join(str(descriptor.get("body", descriptor.get("model", "")))))
		for hair: Dictionary in descriptor.get("hair", []):
			if str(appearance.get("hair_template", "")) in [str(hair.get("template", "")), str(hair.get("shared_template", ""))]:
				paths.append(directory.path_join(str(hair.get("model", hair.get("path", "")))))
		var inventory_directory := ProjectSettings.globalize_path("res://../runtime/assets/inventory")
		var inventory := read_dictionary(inventory_directory.path_join("catalog.json"))
		var candidates: Array = []
		for item: Dictionary in inventory.get("equipment", {}).get(race, {}).values():
			candidates.append({"item": item, "directory": inventory_directory})
		var original: Array = descriptor.get("default_outfit", []).duplicate()
		for outfit: Array in descriptor.get("profession_outfits", {}).values(): original.append_array(outfit)
		for item: Dictionary in original: candidates.append({"item": item, "directory": directory})
		for worn: Dictionary in appearance.get("equipment", []):
			var source := str(worn.get("template", worn.get("shared_template", "")))
			var shared := str(worn.get("shared_template", source))
			for candidate: Dictionary in candidates:
				var item: Dictionary = candidate.item
				if source == str(item.get("template", "")) or shared == str(item.get("shared_template", "")):
					var model := str(item.get("model", item.get("path", "")))
					paths.append(model if model.is_absolute_path() else str(candidate.directory).path_join(model))
					break
	var loaded: Dictionary = {}
	var budget := 32 * 1024 * 1024
	var index := 0
	while index < paths.size() and index < 32 and budget > 0:
		var file_path: String = paths[index]
		index += 1
		if file_path.is_empty() or loaded.has(file_path): continue
		var model: Dictionary = cached_models.get(file_path, {})
		if model.is_empty():
			var file := FileAccess.open(file_path, FileAccess.READ)
			if file == null or file.get_length() > budget: continue
			budget -= file.get_length()
			model = read_dictionary(file_path)
			if not model.is_empty(): loaded[file_path] = model
		# The source loader retains paths relative to the character catalog.
		if index == 1:
			for key in ["idle", "walk", "run", "strafe_left", "strafe_right", "backpedal", "crouch", "crouch_walk", "prone", "crawl", "sit", "face_idle"]:
				var clip := str(model.get("animation_library", {}).get(key, {}).get("path", ""))
				if not clip.is_empty(): paths.append(clip if clip.is_absolute_path() else directory.path_join(clip))
	return {"catalog": catalog, "models": loaded}
