extends Node3D
## Bounded interest-set presentation. Caller supplies authenticated authoritative
## IDs and already converted world coordinates. Full snapshots remove absence.
const RemotePlayer = preload("res://multiplayer/remote_player.gd")
const Avatar = preload("res://scripts/avatar.gd")
const Warmup = preload("res://multiplayer/appearance_warmup.gd")
var peers: Dictionary = {}
var catalog_path := ""
var max_players := 16
var radius := 128.0
var observer_position := Vector3.ZERO
var snapshot_age := 100.0
var report: Dictionary = {}
var desired: Dictionary = {}
var pending: Dictionary = {}
var worker: Thread
var worker_id := ""
var worker_key := ""
var build_peak_ms := 0.0
var cached_build_peak_ms := 0.0
var appearance_cache := preload("res://multiplayer/avatar_instance_cache.gd").new()
var deployments: Node3D
var pulse_manager: Node3D
var seen_events: Dictionary = {}
var effect_assets: RefCounted
var effect_manager: Node3D
var source_effects: Node3D
var omitted_effects := 0

func configure_world(app: Node) -> void:
	var eye: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(app.get("player")) and app.player.has_method("get_camera"): eye = app.player.get_camera()
	pulse_manager = preload("res://multiplayer/survey_pulse.gd").shared(self, eye)
	if is_instance_valid(app.get("inventory")):
		deployments = preload("res://multiplayer/remote_deployments.gd").new()
		add_child(deployments)
		deployments.configure(app.inventory.assets)
		deployments.set_context(app.stage, app.player, app.terrain)
	if is_instance_valid(app.get("combat_rig")) and app.combat_rig.get("assets") != null:
		effect_assets = app.combat_rig.assets
	else:
		effect_assets = preload("res://combat/original_assets.gd").new()
		effect_assets.load_catalog()
	if not effect_assets.catalog.is_empty():
		source_effects = preload("res://combat/effect_player.gd").new()
		add_child(source_effects)
		source_effects.configure(effect_assets, eye)
		effect_manager = source_effects.manager

func event_weapon(event: Dictionary) -> Dictionary:
	if effect_assets == null: return {}
	var template := str(event.get("weapon_template", ""))
	var actor: Dictionary = desired.get(str(event.get("actor_id", "")), {})
	var weapon_id := str(event.get("weapon_id", ""))
	if not weapon_id.is_empty():
		template = ""
		for item: Dictionary in actor.get("appearance", {}).get("equipment", []):
			if str(item.get("id", "")) == weapon_id:
				template = str(item.get("shared_template", item.get("template", "")))
				break
		# A delayed shot must not adopt the different weapon equipped meanwhile.
		if template.is_empty(): return {}
	elif template.is_empty():
		for item: Dictionary in actor.get("appearance", {}).get("equipment", []):
			if item.get("equipped_slots", []).has("hold_r") or item.get("equipped_slots", []).has("hold_l"):
				template = str(item.get("shared_template", item.get("template", "")))
	if template.is_empty(): return {}
	var shared := template if template.get_file().begins_with("shared_") else template.get_base_dir().path_join("shared_" + template.get_file())
	for weapon: Dictionary in effect_assets.catalog.get("weapons", {}).values():
		if str(weapon.get("shared_template", "")) == shared: return weapon
	return {}

func consume_events(events: Array) -> void:
	for event: Dictionary in events.slice(0, 256):
		var id := str(event.get("id", ""))
		if id.is_empty() or seen_events.has(id): continue
		seen_events[id] = true
		while seen_events.size() > 256: seen_events.erase(seen_events.keys()[0])
		var point: Variant = event.get("position")
		if not point is Vector3 or not point.is_finite() or point.distance_to(observer_position) > 100.0: continue
		match str(event.get("kind", "")):
			"survey":
				if not is_instance_valid(pulse_manager): pulse_manager = preload("res://multiplayer/survey_pulse.gd").shared(self)
				pulse_manager.play_confirmed(point, "remote:" + id)
			"fire", "impact":
				var weapon := event_weapon(event)
				if is_instance_valid(source_effects) and not weapon.is_empty():
					var firing := str(event.kind) == "fire"
					var path := str(weapon.get("effects", {}).get("fire" if firing else "hit_creature" if not str(event.get("target_id", "")).is_empty() else "hit", ""))
					var origin: Variant = event.get("origin", point)
					if not origin is Vector3 or not origin.is_finite(): origin = point
					var direction: Variant = event.get("direction", Vector3.FORWARD)
					if not direction is Vector3 or not direction.is_finite() or direction.length_squared() < 0.01: direction = Vector3.FORWARD
					var basis := Basis.looking_at(direction.normalized())
					if firing: basis = basis * Basis(Vector3.RIGHT, -PI / 2.0)
					source_effects.play(path, Transform3D(basis, origin if firing else point))
				else: omitted_effects += 1

func apply_deployments(rows: Array, local_character_id: String, observer: Vector3) -> void:
	if not is_instance_valid(deployments): return
	var confirmed: Array = []
	for row: Dictionary in rows.slice(0, 64):
		var point: Variant = row.get("position")
		if str(row.get("owner_id", "")) == local_character_id or not point is Vector3 or not point.is_finite() or point.distance_to(observer) > 64.0: continue
		var value := row.duplicate(true)
		value.world_position = point
		value["tool"] = {"customization": row.get("customization", {})}
		confirmed.append(value)
	deployments.set_states(confirmed)

func configure(path := "") -> void:
	catalog_path = path if not path.is_empty() else ProjectSettings.globalize_path("res://../runtime/assets/characters/catalog.json")

func apply_snapshot(rows: Array, local_character_id: String, observer: Vector3, current_cell := "", full_snapshot := true) -> void:
	if not observer.is_finite(): return
	observer_position = observer
	snapshot_age = 0.0
	var candidates: Array = []
	var seen: Dictionary = {}
	for value: Variant in rows.slice(0, 128):
		if not value is Dictionary: continue
		var id := str(value.get("id", ""))
		var point: Variant = value.get("position")
		if id.is_empty() or id == local_character_id or seen.has(id) or not point is Vector3 or not point.is_finite(): continue
		seen[id] = true
		if point.distance_squared_to(observer) > radius * radius: continue
		candidates.append(value)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = a.position.distance_squared_to(observer)
		var db: float = b.position.distance_squared_to(observer)
		return str(a.id) < str(b.id) if is_equal_approx(da, db) else da < db)
	var retained: Dictionary = {}
	for value: Dictionary in candidates.slice(0, clampi(max_players, 1, 32)):
		var id := str(value.id)
		retained[id] = true
		desired[id] = value.duplicate(true)
		if not peers.has(id):
			pending[id] = true
			continue
		var peer: Node3D = peers[id]
		if JSON.stringify(value.get("appearance", {})) != peer.appearance_key:
			pending[id] = true
			var motion_only := value.duplicate()
			motion_only["appearance"] = peer.row.get("appearance", {})
			peer.apply_peer(motion_only)
		else:
			pending.erase(id)
			peer.apply_peer(value)
		# Cell geometry owns occlusion; avoid culling the person on the other
		# side of an open portal merely because their floor membership differs.
		peer.animation_interval = 0.1 if value.position.distance_squared_to(observer) > 32.0 * 32.0 else 0.0
		peer.label.visible = value.position.distance_squared_to(observer) <= 32.0 * 32.0
		peer.set_meta("same_cell", str(value.get("cell_id", "")) == current_cell)
	if full_snapshot:
		for id in desired.keys():
			if not retained.has(id): remove_peer(id)
	# Even delta callers cannot bypass the hard resource budget.
	while desired.size() > clampi(max_players, 1, 32):
		var farthest := ""
		var distance := -1.0
		for id in desired:
			var d: float = desired[id].position.distance_squared_to(observer)
			if d > distance: distance = d; farthest = id
		remove_peer(farthest)
	report = {"rendered_players": peers.size(), "pending_appearances": pending.size(), "eligible_players": candidates.size(), "limit": max_players, "radius_m": radius, "local_character_excluded": local_character_id, "appearance_build_peak_ms": build_peak_ms}

func remove_peer(id: String) -> void:
	var peer: Node = peers.get(id)
	peers.erase(id)
	desired.erase(id)
	pending.erase(id)
	if is_instance_valid(peer):
		remove_child(peer)
		peer.queue_free()

func clear() -> void:
	for id in desired.keys(): remove_peer(id)
	for id in peers.keys(): remove_peer(id)
	snapshot_age = 100.0
	report.clear()
	appearance_cache.clear()
	seen_events.clear()
	if is_instance_valid(deployments): deployments.clear()
	if is_instance_valid(pulse_manager): pulse_manager.clear()

func reset() -> void:
	clear()

func _process(delta: float) -> void:
	snapshot_age += maxf(delta, 0.0)
	if snapshot_age > 2.0:
		if not desired.is_empty() or not peers.is_empty(): clear()
		return
	for peer in peers.values(): peer.advance(delta)
	advance_appearance_queue()

func advance_appearance_queue() -> void:
	if worker != null:
		if worker.is_alive(): return
		var warmed: Dictionary = worker.wait_to_finish()
		worker = null
		if not Avatar.catalog_cache.has(catalog_path): Avatar.catalog_cache[catalog_path] = warmed.get("catalog", {})
		for path: String in warmed.get("models", {}):
			if not Avatar.model_cache.has(path): Avatar.model_cache[path] = warmed.models[path]
		if desired.has(worker_id) and JSON.stringify(desired[worker_id].get("appearance", {})) == worker_key:
			var start := Time.get_ticks_usec()
			var cached_before: int = appearance_cache.hits
			if not peers.has(worker_id):
				var peer := RemotePlayer.new()
				add_child(peer)
				peer.configure(catalog_path)
				peer.appearance_cache = appearance_cache
				peers[worker_id] = peer
			var peer: Node3D = peers[worker_id]
			peer.apply_peer(desired[worker_id])
			peer.animation_interval = 0.1 if peer.global_position.distance_squared_to(observer_position) > 32.0 * 32.0 else 0.0
			peer.label.visible = peer.global_position.distance_squared_to(observer_position) <= 32.0 * 32.0
			pending.erase(worker_id)
			build_peak_ms = maxf(build_peak_ms, float(Time.get_ticks_usec() - start) / 1000.0)
			if appearance_cache.hits > cached_before:
				cached_build_peak_ms = maxf(cached_build_peak_ms, float(Time.get_ticks_usec() - start) / 1000.0)
		# Exactly one scene/avatar construction per process frame. Background
		# parsing never touches Godot Nodes or publishes shared cache entries.
		return
	if pending.is_empty(): return
	if catalog_path.is_empty(): configure()
	worker_id = str(pending.keys()[0])
	worker_key = JSON.stringify(desired[worker_id].get("appearance", {}))
	worker = Thread.new()
	var catalog: Dictionary = Avatar.catalog_cache.get(catalog_path, {})
	# Snapshot the dictionary structure; model dictionaries are immutable once
	# published by the existing source loader.
	var error := worker.start(Warmup.load_appearance.bind(catalog_path, desired[worker_id].get("appearance", {}).duplicate(true), catalog, Avatar.model_cache.duplicate()))
	if error != OK:
		worker = null
		report["appearance_worker_error"] = error

func _exit_tree() -> void:
	if worker != null:
		worker.wait_to_finish()
		worker = null
	appearance_cache.clear()
