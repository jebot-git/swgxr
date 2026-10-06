extends RefCounted
var catalog: Dictionary = {}
var directory := ProjectSettings.globalize_path("res://../runtime/entertainment")
var cache: Dictionary = {}
func load_catalog() -> bool:
	var path := directory.path_join("catalog.json")
	if not FileAccess.file_exists(path): return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return false
	catalog = parsed
	# Old local caches may still list the retired dance prop.
	if catalog.get("items",{}) is Dictionary: catalog.items.erase("object/static/item/item_ribbon.iff")
	return true
func sound(path: String) -> AudioStream:
	if not cache.has(path):
		if cache.size() >= 32: cache.erase(cache.keys()[0])
		cache[path] = AudioStreamWAV.load_from_file(directory.path_join(path))
	return cache[path]
func performances(context: Dictionary, item: Dictionary) -> Array:
	if not context.get("complete",false): return []
	var descriptor: Dictionary = catalog.get("items",{}).get(str(item.get("template","")).replace("/shared_","/"),{})
	var instrument := "dance" if item.is_empty() else str(descriptor.get("instrument",""))
	var commands: Array = context.get("commands",[]).map(func(command): return str(command).to_lower())
	if instrument != "dance" and not instrument in commands: return []
	var result: Array = []
	for performance: Dictionary in catalog.get("performances",{}).values():
		if performance.instrument == instrument and str(performance.required_command).to_lower() in commands: result.append(performance)
	return result
