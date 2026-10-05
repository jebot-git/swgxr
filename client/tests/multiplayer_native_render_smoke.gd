extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var file := ProjectSettings.globalize_path("res://../runtime/evidence/multiplayer-native-world.json")
	var evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	var native_row: Dictionary = {}
	for record: Dictionary in evidence.get("responses", []):
		if str(record.get("path", "")) != "/session/sync": continue
		var players: Array = record.get("response", {}).get("world", {}).get("players", [])
		if not players.is_empty(): native_row = players[0].duplicate(true); break
	if native_row.is_empty(): push_error("No actual native peer snapshot available"); quit(1); return
	var original_position: Array = native_row.position.duplicate()
	native_row.position = Vector3.ZERO
	native_row.heading_radians = -float(native_row.get("heading_radians", 0.0))
	var peer := preload("res://multiplayer/remote_player.gd").new(); root.add_child(peer); peer.configure(); peer.apply_peer(native_row); peer.advance(0.1)
	var failures: Array = []
	if peer.avatar == null: failures.append("Actual native player appearance did not resolve")
	elif not peer.avatar.report.get("equipment_complete", false): failures.append("Actual native equipment incomplete")
	var cache := preload("res://multiplayer/avatar_instance_cache.gd").new()
	cache.remember(native_row.appearance, peer.avatar)
	var second_appearance: Dictionary = native_row.appearance.duplicate(true)
	for item: Dictionary in second_appearance.equipment: item.id = "different-" + str(item.id)
	var second: Node3D = cache.instantiate(second_appearance)
	if second == null: failures.append("Native identical outfit did not reuse assembled geometry cache")
	else:
		for mesh: MeshInstance3D in second.meshes:
			if mesh.has_meta("equipment_id") and not str(mesh.get_meta("equipment_id")).begins_with("different-"): failures.append("Cached native outfit retained previous owner's equipment ID")
		for index in range(12):
			var alternate: Dictionary = second_appearance.duplicate(true); alternate.height = 0.9 + index * 0.01
			cache.remember(alternate, second)
		if cache.entries.size() > cache.MAX_ENTRIES: failures.append("Assembled appearance LRU exceeded hard cap")
		cache.clear()
		if not is_instance_valid(second.skeleton): failures.append("Cache eviction freed a live player's skeleton")
		second.free()
	cache.clear()
	var result := {"passed":failures.is_empty(), "failures":failures, "native_evidence_sha256":FileAccess.get_sha256(file), "native_player_id":native_row.id, "native_source_position":original_position, "presentation_origin":"Translated to zero for isolated renderer check", "source_appearance":native_row.get("appearance", {}), "visual_report":peer.avatar.report if peer.avatar != null else peer.report, "validation":"Actual local Core3 payload replayed through original source avatar renderer under dummy rendering; no live-headset or GPU claim"}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/multiplayer-native-render.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"native_player_id":native_row.id,"equipment_report":peer.avatar.report.get("equipment_complete", false) if peer.avatar != null else false}))
	peer.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
