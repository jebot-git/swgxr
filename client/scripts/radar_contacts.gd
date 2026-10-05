extends RefCounted
## Local contact presentation, independent of avatar visibility/render budgets.
## Authored ambient placements are neutral; only explicit entity data supplies hostility.
const TILE_SIZE := 64.0
const MAX_CONTACTS := 128
const MAX_RANGE := 64.0
var source_ref: WeakRef
var source_transform := Transform3D.IDENTITY
var tiles: Dictionary = {}
var report := {"indexed":0,"visited":0,"returned":0,"queries":0}

func clear() -> void:
	source_ref = null
	tiles.clear()
	report = {"indexed":0,"visited":0,"returned":0,"queries":0}

func configure(source: Node3D) -> void:
	clear()
	if not is_instance_valid(source): return
	source_ref = weakref(source)
	rebuild(source)

func rebuild(source: Node3D) -> void:
	tiles.clear()
	source_transform = source.global_transform
	var manifest: Dictionary = source.get("manifest")
	var seen: Dictionary = {}
	for entry: Dictionary in manifest.get("instances",[]):
		var values: Array = entry.get("position",[])
		var id := str(entry.get("id",""))
		if values.size()!=3 or id.is_empty() or seen.has(id): continue
		var position := source_transform * Vector3(float(values[0]),float(values[1]),float(values[2]))
		if not position.is_finite(): continue
		seen[id] = true
		var key := tile(position)
		if not tiles.has(key): tiles[key] = []
		tiles[key].append({"id":id,"position":position,"kind":"npc","relation":"neutral","source":"ambient_placement"})
	report.indexed = seen.size()

func tile(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x/TILE_SIZE),floori(position.z/TILE_SIZE))

func append_contact(result: Array[Dictionary], contact: Dictionary, center: Vector3, radius_squared: float) -> void:
	if not bool(contact.get("alive",true)) or not bool(contact.get("radar_visible",true)): return
	if str(contact.get("kind","npc")) not in ["npc","mob"]: return
	var position: Variant = contact.get("position")
	if not position is Vector3 or not position.is_finite(): return
	var offset: Vector3 = position-center
	var distance_squared := offset.x*offset.x+offset.z*offset.z
	if distance_squared>radius_squared: return
	var copy := contact.duplicate()
	copy.id = str(contact.get("id",""))
	copy.kind = "mob" if str(copy.get("kind","npc"))=="mob" else "npc"
	var relation := str(copy.get("relation","neutral"))
	copy.relation = relation if relation in ["neutral","attackable","friendly","hostile"] else "neutral"
	copy.distance_squared = distance_squared
	result.append(copy)

func query(center: Vector3, requested_radius := MAX_RANGE) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	report.queries += 1
	report.visited = 0
	report.returned = 0
	if not center.is_finite() or not is_finite(requested_radius) or requested_radius<=0: return result
	var source: Node3D = source_ref.get_ref() if source_ref!=null else null
	if not is_instance_valid(source) or source.is_queued_for_deletion(): return result
	if not source.global_transform.is_equal_approx(source_transform): rebuild(source)
	var radius := minf(requested_radius,MAX_RANGE)
	var radius_squared := radius*radius
	# A moved rendered actor must override its old authored position even when it
	# crossed a tile boundary. Visibility never changes contact eligibility.
	var overrides: Dictionary = {}
	var records: Dictionary = source.get("records")
	for id: String in records:
		if source.has_method("is_live_suppressed") and source.is_live_suppressed(id): continue
		var actor: Node3D = records[id].get("avatar")
		if is_instance_valid(actor) and not actor.is_queued_for_deletion():
			overrides[id] = {"id":id,"position":actor.global_position,"kind":"npc","relation":"neutral","source":"ambient_avatar"}
	# Explicit contract for moving local mobs and future replicated entities.
	# No training props, meshes or physics bodies are guessed to be creatures.
	for actor: Node in source.get_tree().get_nodes_in_group("swg_radar_contacts"):
		if actor.is_queued_for_deletion() or not actor.has_method("get_radar_contact"): continue
		var value: Variant = actor.call("get_radar_contact")
		if not value is Dictionary: continue
		var id := str(value.get("id",""))
		if not id.is_empty(): overrides[id] = value
	var minimum := tile(center-Vector3(radius,0,radius))
	var maximum := tile(center+Vector3(radius,0,radius))
	for z in range(minimum.y,maximum.y+1):
		for x in range(minimum.x,maximum.x+1):
			for contact: Dictionary in tiles.get(Vector2i(x,z),[]):
				report.visited += 1
				if source.has_method("is_live_suppressed") and source.is_live_suppressed(str(contact.id)): continue
				if not overrides.has(contact.id): append_contact(result,contact,center,radius_squared)
	for contact: Dictionary in overrides.values():
		report.visited += 1
		append_contact(result,contact,center,radius_squared)
	result.sort_custom(func(a: Dictionary,b: Dictionary):
		if a.distance_squared==b.distance_squared: return str(a.id)<str(b.id)
		return a.distance_squared<b.distance_squared)
	if result.size()>MAX_CONTACTS: result.resize(MAX_CONTACTS)
	report.returned = result.size()
	return result
