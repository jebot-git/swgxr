extends Node3D
## Persistent source portal membership. Rendering never turns authored collision off.
signal interior_cells_changed
var classifier := SwgCellClassifier.new()
var ground_support := SwgGroundSupport.new()
var combat_collision := SwgCombatCollision.new()
var combat_stage_registered := false
var exterior_instances: Array[MeshInstance3D] = []
var cell_regions: Dictionary = {}
var observer: Node3D
var current_cell: Dictionary = {}
var current_building: int = -1
var previous_position := Vector3.ZERO
var have_previous := false
var seed_pending := true
var definitions: Dictionary = {}
var exterior_ids: Array = []
var collision_bodies: Array[StaticBody3D] = []
var physical_cells: Dictionary = {}
var physical_key := ""
var physical_position := Vector3.INF
var physical_cell_id := "!"
var definition_transforms: Dictionary = {}
var view_buildings: Array[int] = []
var view_buildings_initialized := false
var publication_profile := {}
var retained_collision_bodies: Array[StaticBody3D] = []

var external_world_coverage := false

func set_external_world_coverage(enabled: bool) -> void:
	if enabled == external_world_coverage: return
	external_world_coverage = enabled
	if combat_stage_registered: register_combat_geometry("retained_stage",self,AABB(),0 if enabled else 1)

func _init() -> void:
	process_physics_priority = -200

func _ready() -> void:
	rebuild_support()

func set_observer(node: Node3D) -> void:
	if observer != node:
		observer = node
		have_previous = false
		seed_pending = true
	update_cell()

func seed_membership_at(feet: Vector3, cell_id := "") -> void:
	# Explicit spawn/teleport placement only. Ordinary movement uses portals.
	if cell_id.is_empty():
		current_cell = classify_world(feet)
	elif definitions.has(cell_id) and not definitions[cell_id].get("is_exterior",false):
		var cell: Dictionary = definitions[cell_id]
		current_cell = {"cell_id":cell_id,"name":cell.get("name",""),"building_object_id":cell.get("building_object_id",0)}
	else:
		current_cell = {}
	seed_pending = false
	previous_position = feet
	have_previous = true
	physical_key = ""
	refresh_physical_cells()
	current_building = int(current_cell.get("building_object_id",0))
	if observer is CollisionObject3D:
		observer.collision_mask = 5 if current_building > 0 else 7
	interior_cells_changed.emit()

func register_cell_region(key: String, coordinate_node: Node3D, region_classifier: SwgCellClassifier, exteriors: Array, source_cells: Dictionary = {}, prepared_geometry = null, prepared_support = null, prepared_colliders: Variant = null) -> void:
	var colliders: Array = prepared_colliders if prepared_colliders is Array else []
	if prepared_colliders == null: _collect_colliders_into(coordinate_node,colliders)
	cell_regions[key] = {"node":coordinate_node,"classifier":region_classifier,"exteriors":exteriors,"definitions":source_cells,"colliders":colliders}
	var start_us := Time.get_ticks_usec()
	if prepared_geometry is SwgCombatCollision:
		combat_collision.adopt_geometry(key,prepared_geometry,"prepared")
	else:
		register_combat_geometry(key,coordinate_node,AABB(),0 if external_world_coverage else 1)
	publication_profile["combat_snapshot_ms"] = (Time.get_ticks_usec()-start_us)/1000.0
	start_us = Time.get_ticks_usec()
	if not prepared_support is SwgGroundSupport:
		prepared_support = SwgGroundSupport.new()
		prepared_support.configure([{"transform":coordinate_node.global_transform,"cells":source_cells}])
	ground_support.adopt_region(key,prepared_support)
	rebuild_support(false)
	publication_profile["support_rebuild_ms"] = (Time.get_ticks_usec()-start_us)/1000.0
	start_us = Time.get_ticks_usec()
	update_cell(true)
	interior_cells_changed.emit()
	publication_profile["notify_ms"] = (Time.get_ticks_usec()-start_us)/1000.0

func unregister_cell_region(key: String) -> void:
	combat_collision.remove_geometry(key)
	ground_support.remove_region(key)
	cell_regions.erase(key)
	rebuild_support(false)
	if not definitions.has(str(current_cell.get("cell_id",""))): current_cell = {}
	update_cell(true)
	interior_cells_changed.emit()

func rebuild_support(rebuild_native := true) -> void:
	if not is_inside_tree(): return
	definitions.clear()
	definition_transforms.clear()
	exterior_ids.clear()
	var regions := all_floor_regions()
	for region: Dictionary in regions:
		for key: String in region.cells:
			definitions[key] = region.cells[key]
			definition_transforms[key] = region.transform
			if bool(region.cells[key].get("is_exterior",false)): exterior_ids.append(key)
	if rebuild_native:
		ground_support.configure([regions[0]])
		for key: String in cell_regions:
			var region: Dictionary = cell_regions[key]
			var prepared := SwgGroundSupport.new()
			prepared.configure([{"transform":region.node.global_transform,"cells":region.definitions}])
			ground_support.adopt_region(key,prepared)
		retained_collision_bodies.clear()
		_collect_colliders_into(self,retained_collision_bodies)
	combat_collision.configure(regions)
	if not combat_stage_registered:
		register_combat_geometry("retained_stage",self,AABB(),0 if external_world_coverage else 1)
		combat_stage_registered = true
	collision_bodies.assign(retained_collision_bodies)
	for region: Dictionary in cell_regions.values():
		collision_bodies.append_array(region.colliders)
	physical_key = ""
	refresh_physical_cells()

func _collect_colliders_into(node: Node, destination: Array) -> void:
	if node is StaticBody3D and node.has_meta("source_layer"): destination.append(node)
	for child in node.get_children(): _collect_colliders_into(child,destination)

func collect_colliders(node: Node) -> void:
	if node is StaticBody3D and node.has_meta("source_layer"):
		collision_bodies.append(node)
	for child in node.get_children():
		collect_colliders(child)

func refresh_collision(body: StaticBody3D) -> void:
	var id := str(body.get_meta("source_cell", ""))
	var relevant := id.is_empty() or physical_cells.has(id)
	body.collision_layer = int(body.get_meta("source_layer", 1)) if relevant and body.get_meta("stream_collision_active", true) else 0

func refresh_physical_cells() -> void:
	var position := observer.global_position if is_instance_valid(observer) else Vector3.ZERO
	var id := str(current_cell.get("cell_id", ""))
	if not physical_key.is_empty() and id == physical_cell_id and physical_position.distance_to(position) < 0.1:
		return
	physical_cell_id = id
	physical_position = position
	var allowed := {}
	var building := int(current_cell.get("building_object_id", 0))
	for key: String in exterior_ids:
		if building == 0 or int(definitions[key].get("building_object_id",0)) != building:
			allowed[key] = true
	if not id.is_empty():
		allowed[id] = true
	var candidates: Array = exterior_ids if id.is_empty() else [id]
	for candidate: String in candidates:
		var cell: Dictionary = definitions.get(candidate,{})
		var transform: Transform3D = definition_transforms.get(candidate,Transform3D.IDENTITY)
		for portal: Dictionary in cell.get("portals",[]):
			if portal.get("passable",false) and portal_distance(position + Vector3.UP * 0.5, portal.vertices, transform) < 0.8:
				allowed[str(portal.leads_to)] = true
	var keys: Array = allowed.keys()
	keys.sort()
	var next := str(keys)
	if next == physical_key:
		return
	physical_key = next
	physical_cells = allowed
	for body in collision_bodies:
		if is_instance_valid(body):
			refresh_collision(body)

func portal_distance(point: Vector3, vertices: Array, transform: Transform3D) -> float:
	if vertices.size() < 9:
		return INF
	var polygon: Array[Vector3] = []
	for index in range(0,vertices.size(),3):
		polygon.append(transform * Vector3(vertices[index],vertices[index+1],vertices[index+2]))
	var normal := (polygon[1]-polygon[0]).cross(polygon[2]-polygon[0]).normalized()
	var projected := point - normal * normal.dot(point-polygon[0])
	var sign_value := 0.0
	var inside := true
	var distance := INF
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index+1)%polygon.size()]
		distance = minf(distance,point.distance_to(Geometry3D.get_closest_point_to_segment(point,a,b)))
		var edge := (b-a).cross(projected-a).dot(normal)
		if absf(edge) > 0.00001:
			if sign_value == 0:
				sign_value = edge
			elif sign_value * edge < 0:
				inside = false
	return absf(normal.dot(point-polygon[0])) if inside else distance

func refresh_exterior(instance: MeshInstance3D) -> void:
	if is_instance_valid(instance):
		instance.set_meta("cell_exterior_hidden", false)
		instance.visible = true

func classify_world(position: Vector3) -> Dictionary:
	var result := classifier.classify(to_local(position))
	if not result.is_empty():
		return result
	for region: Dictionary in cell_regions.values():
		if is_instance_valid(region.node) and region.node.is_inside_tree():
			result = region.classifier.classify(region.node.to_local(position))
			if not result.is_empty():
				return result
	return {}

func advance_world(from: Vector3, to: Vector3, state: Dictionary) -> Dictionary:
	var id := str(state.get("cell_id", ""))
	var local_cells: Dictionary = get_meta("manifest", {}).get("cells", {})
	if id.is_empty() or local_cells.has(id):
		var result := classifier.advance(to_local(from), to_local(to), id)
		if not id.is_empty() or not result.is_empty():
			return result
	for region: Dictionary in cell_regions.values():
		if not is_instance_valid(region.node) or not region.node.is_inside_tree():
			continue
		if id.is_empty() or region.definitions.has(id):
			var result: Dictionary = region.classifier.advance(region.node.to_local(from), region.node.to_local(to), id)
			if not id.is_empty() or not result.is_empty():
				return result
	return state

func collision_context(position: Vector3) -> Dictionary:
	var state := current_cell
	if is_instance_valid(observer) and have_previous:
		state = advance_world(observer.global_position + Vector3.UP * 0.5, position + Vector3.UP * 0.5, state)
	var id := str(state.get("cell_id", ""))
	var allowed: Array = exterior_ids.duplicate() if id.is_empty() else [id]
	# Source neighbors are available only at a real portal transition, not merely
	# because an underground room shares the same projected X/Z footprint.
	var previous_id := str(current_cell.get("cell_id", ""))
	if previous_id != id and not previous_id.is_empty():
		allowed.append(previous_id)
	return {"cell_id":id,"building_object_id":int(state.get("building_object_id",0)),"allowed_cell_ids":allowed}

func _physics_process(_delta: float) -> void:
	update_cell()

func update_cell(force := false) -> void:
	if not is_instance_valid(observer) or not observer.is_inside_tree() or not is_inside_tree():
		return
	var position := observer.global_position
	# A standing observer does not cross portals. Avoid walking every loaded
	# region and rebuilding candidate sets twice per frame while idle.
	if have_previous and not seed_pending and not force and position.distance_squared_to(previous_position) < 0.00000001:
		return
	if have_previous and position.distance_to(previous_position) > 3.0:
		seed_pending = true
	if seed_pending:
		current_cell = classify_world(position)
		if not current_cell.is_empty() or (observer is CharacterBody3D and observer.is_on_floor()):
			seed_pending = false
	elif have_previous:
		current_cell = advance_world(previous_position + Vector3.UP * 0.5, position + Vector3.UP * 0.5, current_cell)
	previous_position = position
	have_previous = true
	var building := int(current_cell.get("building_object_id",0))
	refresh_physical_cells()
	if observer is CollisionObject3D:
		observer.collision_mask = 5 if building != 0 else 7
	if building == current_building and not force:
		return
	current_building = building
	for instance in exterior_instances:
		refresh_exterior(instance)
	for region: Dictionary in cell_regions.values():
		for instance in region.exteriors:
			refresh_exterior(instance)
	interior_cells_changed.emit()

func all_floor_regions() -> Array:
	var result: Array = [{"transform":global_transform,"cells":get_meta("manifest",{}).get("cells",{})}]
	for region: Dictionary in cell_regions.values():
		if is_instance_valid(region.node) and region.node.is_inside_tree():
			result.append({"transform":region.node.global_transform,"cells":region.definitions})
	return result

func set_view_buildings(ids: Array) -> void:
	var next: Array[int] = []
	for value in ids:
		var id := int(value)
		if id > 0 and id not in next and next.size() < 2:
			next.append(id)
	next.sort()
	if view_buildings_initialized and next == view_buildings:
		return
	view_buildings_initialized = true
	view_buildings = next
	interior_cells_changed.emit()

func interior_view_regions() -> Array:
	var ids: Array = view_buildings if view_buildings_initialized else ([current_building] if current_building > 0 else [])
	var groups: Array = []
	for id: int in ids:
		groups.append({"building_id":id,"regions":interior_floor_regions(id)})
	return groups

func interior_floor_regions(building_id := -1) -> Array:
	var selected := current_building if building_id < 0 else building_id
	if selected <= 0:
		return []
	var result: Array = []
	for region: Dictionary in all_floor_regions():
		var cells := {}
		for id: String in region.cells:
			var cell: Dictionary = region.cells[id]
			if not cell.get("is_exterior",false) and int(cell.get("building_object_id",0)) == selected:
				cells[id] = cell
		if not cells.is_empty():
			result.append({"transform":region.transform,"cells":cells})
	return result

# Combat owns immutable geometry snapshots, independently from the observer's
# CharacterBody collision layers. Each actor/projectile retains its own cell id.
func register_combat_geometry(key: String, node: Node3D, coverage: AABB = AABB(), coverage_layer := 1) -> void:
	var surfaces: Array = []
	_collect_combat_surfaces(node, surfaces)
	if node.has_meta("combat_coverage"):
		coverage = node.get_meta("combat_coverage")
	if coverage.size == Vector3.ZERO:
		var first := true
		for surface: Dictionary in surfaces:
			for point: Vector3 in surface.get("faces", PackedVector3Array()):
				var world: Vector3 = surface.transform * point
				coverage = AABB(world, Vector3.ZERO) if first else coverage.expand(world)
				first = false
	combat_collision.set_geometry(key, surfaces, coverage, coverage_layer)

func _collect_combat_surfaces(node: Node, surfaces: Array) -> void:
	if node is StaticBody3D:
		for child in node.get_children():
			if not child is CollisionShape3D or child.shape == null:
				continue
			var faces := PackedVector3Array()
			var shape: Shape3D = child.shape
			if shape is ConcavePolygonShape3D:
				faces = shape.get_faces()
			elif shape is BoxShape3D:
				var mesh := BoxMesh.new()
				mesh.size = shape.size
				faces = mesh.get_faces()
			elif shape is SphereShape3D:
				var mesh := SphereMesh.new()
				mesh.radius = shape.radius
				mesh.height = shape.radius * 2.0
				faces = mesh.get_faces()
			elif shape is CylinderShape3D:
				var mesh := CylinderMesh.new()
				mesh.top_radius = shape.radius
				mesh.bottom_radius = shape.radius
				mesh.height = shape.height
				faces = mesh.get_faces()
			else:
				push_error("Unsupported combat collision shape: " + shape.get_class())
				surfaces.append({"unsupported":true})
				continue
			surfaces.append({"faces":faces,"transform":child.global_transform,"cell_id":str(node.get_meta("source_cell","")),"layer":int(node.get_meta("source_layer",node.collision_layer))})
	for child in node.get_children():
		_collect_combat_surfaces(child,surfaces)
