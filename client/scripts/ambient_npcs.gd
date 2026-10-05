extends Node3D
## Source Core3 placements + original local appearances. Ambient presentation;
## no combat, interaction, AI movement or live server NPC authority.
const Avatar = preload("res://scripts/avatar.gd")
const VirtualSkin = preload("res://scripts/virtual_skin_binding.gd")
const NPCEquipment = preload("res://scripts/npc_equipment.gd")

@export var render_distance := 128.0
@export var animation_distance := 50.0
@export var max_instances := 32
@export var instances_per_frame := 1
var report := {"error":"", "instances":0, "pending":0, "ready":false, "animated":0, "failures":[]}
var manifest: Dictionary = {}
var catalog: Dictionary = {}
var catalog_path := ""
var stage: Node3D
var terrain: Node3D
var observer := Vector3.INF
var records: Dictionary = {}
var pending: Array = []
var candidates: Array = []
var failures: Dictionary = {}
var refresh_time := 0.0
var equipment := NPCEquipment.new()
var animation_cache_enabled := true
var hidden_animation_enabled := true
var visibility_provider: Node
var visibility_clock := 0.0
var live_suppressed: Dictionary = {}

func is_live_suppressed(id: String) -> bool:
	return live_suppressed.has(id)

func set_live_suppressed(ids: Dictionary) -> void:
	if ids == live_suppressed: return
	live_suppressed = ids.duplicate()
	for id in records.keys():
		if not live_suppressed.has(id): continue
		equipment.release(records[id].get("equipment",[]))
		records[id].avatar.visible = false
		records[id].avatar.queue_free()
		records.erase(id)
	pending = pending.filter(func(entry): return not live_suppressed.has(str(entry.id)))
	refresh()
	update_report()

func set_visibility_provider(provider: Node) -> void:
	visibility_provider = provider
	process_priority = 110 # Portal camera sets and original animation updates run first.


func vec(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func configure(path: String, existing_stage: Node3D = null, terrain_stream: Node3D = null) -> bool:
	manifest = Avatar.read_json(path)
	if not manifest.has("instances") or not manifest.has("origin"):
		report.error = "Original NPC placement manifest missing or invalid: " + path
		return false
	catalog_path = path.get_base_dir().path_join(str(manifest.get("catalog", "catalog.json")))
	catalog = Avatar.read_json(catalog_path)
	if not catalog.has("races"):
		report.error = "Original NPC appearance catalog missing: " + catalog_path
		return false
	stage = existing_stage
	terrain = terrain_stream
	if stage != null:
		var stage_manifest: Dictionary = stage.get_meta("manifest", {})
		if stage_manifest.has("origin") and vec(stage_manifest.origin).distance_to(vec(manifest.origin)) > 0.001:
			report.error = "NPC and environment manifests have different coordinate origins."
			return false
	var unsupported := {}
	for entry: Dictionary in manifest.instances:
		if catalog.races.has(str(entry.appearance_id)):
			candidates.append(entry)
		else:
			unsupported[str(entry.appearance_id)] = true
	report.merge({"source_placements":manifest.instances.size(), "compatible_placements":candidates.size(),
		"unavailable_appearances":unsupported.keys(), "mode":"source static placements; noninteractive local ambient presentation",
		"source_statistics":manifest.get("statistics", {})}, true)
	name = "OriginalAmbientNPCs"
	return true

func cell_available(entry: Dictionary) -> bool:
	if str(entry.get("cell_id", "")).is_empty() or stage == null:
		return true
	var cell: Dictionary = stage.classify_world(to_global(vec(entry.position) + Vector3.UP * 0.25))
	return str(cell.get("building_object_id", "")) == str(entry.get("building_object_id", ""))

func update_observer(position: Vector3) -> void:
	var moved := not observer.is_finite() or position.distance_to(observer) > 4.0
	observer = position
	if moved:
		refresh()

func refresh() -> void:
	if not observer.is_finite() or manifest.is_empty() or catalog.is_empty():
		return
	var nearby: Array = []
	for entry: Dictionary in candidates:
		var distance := observer.distance_to(to_global(vec(entry.position)))
		if distance <= render_distance and not live_suppressed.has(str(entry.id)) and not failures.has(str(entry.id)) and cell_available(entry):
			nearby.append({"entry":entry, "distance":distance})
	nearby.sort_custom(func(a, b): return a.distance < b.distance)
	if nearby.size() > max_instances:
		nearby.resize(max_instances)
	var wanted := {}
	pending.clear()
	for item: Dictionary in nearby:
		var id := str(item.entry.id)
		wanted[id] = true
		if not records.has(id):
			pending.append(item.entry)
	for id in records.keys():
		if not wanted.has(id):
			equipment.release(records[id].get("equipment",[]))
			records[id].avatar.queue_free()
			records.erase(id)
	refresh_time = 0.0
	update_report()

func grounded_position(entry: Dictionary) -> Vector3:
	var source := to_global(vec(entry.position))
	if str(entry.get("mood", "")).contains("sitting"):
		return source
	var cell_id := str(entry.get("cell_id", ""))
	var exterior := cell_id.is_empty()
	var support: Dictionary = {}
	if is_instance_valid(stage) and stage.get("ground_support") != null:
		var allowed: Array = stage.exterior_ids if exterior else [cell_id]
		# An empty allowed set means ALL cells to the native sampler. Never
		# borrow a basement, upstairs room or unloaded region's floor instead.
		if not allowed.is_empty():
			support = stage.ground_support.sample_support(source, allowed, 0.15 if exterior else 0.6, 2.0, {})
	if not exterior:
		# Exact authored cell floors, not prop/desk tops or visibility-dependent
		# collision layers. Keep the source placement until its FLR is loaded.
		return Vector3(support.position) if support.get("valid",false) else source
	var terrain_point := source
	var has_terrain := is_instance_valid(terrain) and bool(terrain.get("configured"))
	if has_terrain:
		var local := to_local(source)
		var world: Vector2 = terrain.source_position(local)
		local.y = terrain.evaluator.sample_height(world.x, world.y) - vec(manifest.origin).y
		terrain_point = to_global(local)
	# An authored platform close to the placement wins over distant ground;
	# an overhead exterior roof never wins merely by being the highest ray hit.
	if support.get("valid",false) and (not has_terrain or absf(float(support.height)-source.y) < absf(terrain_point.y-source.y)+0.001):
		return Vector3(support.position)
	# Preserve explicitly elevated/flying source placements when terrain is
	# beyond the old two-metre support reach; this is not a global Y reset.
	return terrain_point if has_terrain and source.y-terrain_point.y <= 2.0 else source

func instantiate_entry(entry: Dictionary) -> void:
	var actor := Avatar.new()
	actor.animation_cache_enabled = animation_cache_enabled
	actor.load_catalog(catalog_path)
	add_child(actor)
	var descriptor: Dictionary = catalog.races[str(entry.appearance_id)]
	var appearance: Dictionary = descriptor.get("default_appearance", {}).duplicate(true)
	appearance.height = float(appearance.get("height", 1.0)) * float(entry.get("scale", 1.0))
	var built: Dictionary = actor.configure(str(entry.appearance_id), appearance)
	if not str(built.get("error", "")).is_empty():
		failures[str(entry.id)] = built.error
		report.failures.append({"id":entry.id, "template":entry.template, "error":built.error})
		actor.queue_free()
		return
	var model: Dictionary = actor.get_model(str(descriptor.body))
	var virtual_definitions: Array = model.get("virtual_skin_bones", [])
	if not virtual_definitions.is_empty():
		var virtual_binding := VirtualSkin.new()
		actor.add_child(virtual_binding)
		if not virtual_binding.configure(actor, virtual_definitions):
			failures[str(entry.id)] = "Exact dense skin binding failed"
			report.failures.append({"id":entry.id, "template":entry.template, "error":failures[str(entry.id)]})
			actor.queue_free()
			return
		actor.set_meta("virtual_skin_binding", virtual_binding)
	actor.global_position = grounded_position(entry)
	var q: Array = entry.get("quaternion", [0,0,0,1])
	actor.quaternion = Quaternion(q[0], q[1], q[2], q[3]).normalized()
	actor.set_meta("source", entry)
	var inside := not str(entry.get("cell_id", "")).is_empty()
	for mesh: MeshInstance3D in actor.meshes:
		# The player's own source head is hidden on layer2; NPC heads remain visible.
		mesh.layers = 1
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.set_instance_shader_parameter("swg_indoor", 1.0 if inside else 0.0)
	var mood := str(entry.get("mood", ""))
	var animation := str(descriptor.get("mood_animations", {}).get(mood, "idle"))
	var mood_restored := animation != "idle" or mood in ["", "neutral"]
	if not actor.ensure_animation(animation):
		animation = "idle"
		mood_restored = false
	if actor.ensure_animation(animation):
		actor.animation_player.play(animation)
		var clip: Animation = actor.animation_player.get_animation(animation)
		actor.animation_player.seek(float(abs(str(entry.id).hash()) % 10000) / 10000.0 * clip.length, true)
		actor.animation_player.speed_scale = float(actor.clip_rates.get(animation, 1.0))
	else:
		animation = ""
	# Synchronize the exact virtual bind after the seeded initial pose too;
	# distant NPC animations may be frozen before their first process tick.
	var dense_skin: Node = actor.get_meta("virtual_skin_binding") if actor.has_meta("virtual_skin_binding") else null
	if dense_skin != null:
		dense_skin.update_bindings()
	actor.set_meta("ambient_animation", animation)
	actor.set_meta("mood_restored", mood_restored)
	var attached := equipment.attach(actor,descriptor.get("rigid_equipment",[]),catalog_path.get_base_dir(),inside)
	for failure: Dictionary in attached.failures:
		report.failures.append({"id":entry.id,"template":entry.template,"phase":"rigid_equipment","detail":failure})
	actor.set_meta("rigid_equipment",attached.items)
	records[str(entry.id)] = {"avatar":actor, "entry":entry, "animation":animation, "mood_restored":mood_restored,
		"equipment":attached.items,"equipment_failures":attached.failures,"visibility_bounds":actor_bounds(actor,attached.items),"last_visible":visibility_clock,"suspended":false,"hidden_elapsed":0.0,"paused_players":[],
		"ground_adjustment":actor.global_position.y - to_global(vec(entry.position)).y}

func update_report() -> void:
	var animated := 0
	var moods := 0
	for record: Dictionary in records.values():
		var actor: Node3D = record.avatar
		if actor.animation_player != null and actor.animation_player.active and not str(record.animation).is_empty():
			animated += 1
		if record.mood_restored:
			moods += 1
	report.merge({"instances":records.size(), "live_suppressed":live_suppressed.size(), "pending":pending.size(), "ready":pending.is_empty(),
		"animated":animated,"moods_restored":moods,"equipment":equipment.statistics(),
		"hidden":records.values().filter(func(r): return not r.avatar.visible).size(),
		"suspended":records.values().filter(func(r): return r.get("suspended",false)).size(),
		"animation_cache":Avatar.AnimationClipCache.statistics(),"animation_cache_enabled":animation_cache_enabled,"hidden_animation_enabled":hidden_animation_enabled}, true)

func _process(delta: float) -> void:
	refresh_time += delta
	if refresh_time >= 1.0:
		refresh()
	for i in range(mini(instances_per_frame, pending.size())):
		instantiate_entry(pending.pop_front())
	update_visibility(delta)
	update_report()

func actor_bounds(actor: Node3D, items: Array) -> AABB:
	# Original bind bounds plus a half-body-height motion margin cover ambient
	# gestures; equipment contributes its complete authored mesh envelope.
	var bounds := AABB(Vector3.ZERO,Vector3(0.01,actor.height_meters,0.01))
	var inverse := actor.global_transform.affine_inverse()
	for mesh: MeshInstance3D in actor.meshes:
		bounds = bounds.merge((inverse*mesh.global_transform)*mesh.get_aabb())
	for item: Dictionary in items:
		var mesh: MeshInstance3D = item.instance
		bounds = bounds.merge((inverse*mesh.global_transform)*mesh.get_aabb())
	return bounds.grow(maxf(0.5,actor.height_meters*0.5))

func update_visibility(delta: float) -> void:
	visibility_clock += maxf(0.0,delta)
	for record: Dictionary in records.values():
		var actor: Node3D = record.avatar
		if actor.tracking_mode: continue
		var visible_to_views := true
		if is_instance_valid(visibility_provider) and visibility_provider.has_method("is_cell_visible"):
			visible_to_views = visibility_provider.is_cell_visible(str(record.entry.get("cell_id","")))
			if visible_to_views and record.has("visibility_bounds") and visibility_provider.has_method("is_bounds_visible"):
				visible_to_views = visibility_provider.is_bounds_visible(actor.global_transform*record.visibility_bounds)
		if visible_to_views:
			record.last_visible = visibility_clock
		elif visibility_clock-float(record.get("last_visible",-1.0))<0.2:
			visible_to_views = true
		var animate := actor.global_position.distance_to(observer)<=animation_distance and (visible_to_views or not hidden_animation_enabled)
		if record.get("suspended",false): record.hidden_elapsed += maxf(0.0,delta)
		if not animate and not record.get("suspended",false):
			record.paused_players = []
			for player: AnimationPlayer in [actor.animation_player,actor.face_player]:
				if player==null: continue
				record.paused_players.append({"player":player,"name":player.current_animation,"position":player.current_animation_position if not player.current_animation.is_empty() else 0.0,"speed":player.get_playing_speed(),"playing":player.is_playing()})
				player.active = false
			record.suspended = true
			record.hidden_elapsed = 0.0
		elif animate and record.get("suspended",false):
			for state: Dictionary in record.paused_players:
				var player: AnimationPlayer = state.player
				player.active = true
				if not state.playing or str(state.name).is_empty() or not player.has_animation(state.name): continue
				var clip: Animation = player.get_animation(state.name)
				var position: float = float(state.position)+float(record.hidden_elapsed)*float(state.speed)
				if clip.loop_mode==Animation.LOOP_LINEAR: position = fposmod(position,clip.length)
				else: position = clampf(position,0.0,clip.length)
				player.seek(position,true)
			actor.skeleton.force_update_all_bone_transforms()
			for item: Dictionary in record.get("equipment",[]):
				if is_instance_valid(item.get("attachment")):
					item.attachment.transform = actor.skeleton.get_bone_global_pose(int(item.bone_index))
			var binding: Node = actor.get_meta("virtual_skin_binding") if actor.has_meta("virtual_skin_binding") else null
			if is_instance_valid(binding): binding.update_bindings()
			record.suspended = false
			record.paused_players.clear()
		# Reveal only after body, face and virtual bind have the resumed pose.
		actor.visible = visible_to_views or (is_instance_valid(visibility_provider) and not bool(visibility_provider.get("culling_enabled")))
