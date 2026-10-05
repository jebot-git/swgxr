extends Node
## Clip a building's exterior shell through its authored portal graph per view.
## A mono spectator and stereo eyes select their own camera record in the shader.
const MAX_OPENINGS := 32
const MAX_VERTICES := 20
const ROW_WIDTH := MAX_VERTICES + 2
var stage: Node3D
var head: Camera3D
var spectator: Camera3D
var image: Image
var texture: ImageTexture
var openings: Array = []
var visits := 0
var overflow := false
var report := {}
var portal_cells := {}
# Portal membership is rendering-only; physics, audio and residency never depend on this.
var culling_enabled := true
var revision := 0
var complete := false
var have_visibility := false
var visible_cells := {}
var native_visibility := SwgPortalVisibility.new()
var cell_instances := {}
var cell_visibility := {}
var recently_visible := {}
var graph_signature: Array = []
var view_frusta: Array = []
var bounds_complete := false
var bounds_queries := 0
var bounds_rejected := 0
var view_telemetry := {}
const VISIBILITY_MARGIN := 0.25
const VISIBILITY_HOLD_MSEC := 200

func configure(source: Node3D, camera: Camera3D, observer_camera: Camera3D = null) -> void:
	stage = source
	head = camera
	spectator = observer_camera
	image = Image.create(ROW_WIDTH, MAX_OPENINGS * 2, false, Image.FORMAT_RGBAF)
	texture = ImageTexture.create_from_image(image)
	RenderingServer.global_shader_parameter_set("swg_portal_data", texture)
	stage.interior_cells_changed.connect(refresh_instances)
	refresh_instances()
	update_views()

func refresh_instances() -> void:
	if not is_instance_valid(stage): return
	var signature: Array = [stage.get_instance_id(), stage.get_meta("manifest", {}).get("cells", {}).size()]
	for region: Dictionary in stage.cell_regions.values():
		signature.append(region.node.get_instance_id())
		signature.append(region.get("definitions", {}).size())
	if signature == graph_signature: return
	graph_signature = signature
	rebuild_portal_cells()
	native_visibility.configure(portal_cells)
	cell_instances.clear()
	cell_visibility.clear()
	recently_visible.clear()
	collect_instances(stage)
	for region: Dictionary in stage.cell_regions.values():
		if is_instance_valid(region.node) and not stage.is_ancestor_of(region.node): collect_instances(region.node)
	var instances: Array = stage.exterior_instances.duplicate()
	for region: Dictionary in stage.cell_regions.values(): instances.append_array(region.exteriors)
	for instance: MeshInstance3D in instances:
		if is_instance_valid(instance):
			instance.set_instance_shader_parameter("swg_portal_building", float(instance.get_meta("building_object_id", 0)))
	revision += 1

func collect_instances(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D and child.has_meta("cell_id"):
			var id := str(child.get_meta("cell_id", ""))
			if not cell_instances.has(id): cell_instances[id] = []
			cell_instances[id].append(child)
		collect_instances(child)

func is_cell_visible(id: String) -> bool:
	return not have_visibility or not portal_cells.has(id) or bool(portal_cells[id].get("is_exterior", false)) or visible_cells.has(id)

func is_bounds_visible(bounds: AABB) -> bool:
	bounds_queries += 1
	if not bounds_complete or not bounds.position.is_finite() or not bounds.size.is_finite(): return true
	var center := bounds.get_center()
	var half := bounds.size.abs() * 0.5
	for planes: Array in view_frusta:
		var outside := false
		for plane: Plane in planes:
			var radius := plane.normal.abs().dot(half)
			if plane.distance_to(center) + radius < -VISIBILITY_MARGIN:
				outside = true
				break
		if not outside: return true
	bounds_rejected += 1
	return false

func add_frustum(projection: Projection, pose: Transform3D) -> bool:
	if not pose.is_finite(): return false
	if not is_finite(projection.determinant()) or absf(projection.determinant()) < 1e-12: return false
	var planes: Array = []
	# Ignore far/near planes: a near eye or far actor must never flicker from these cuts.
	var forward_point := pose.origin - pose.basis.z * 2.0
	for index in [Projection.PLANE_LEFT, Projection.PLANE_RIGHT, Projection.PLANE_TOP, Projection.PLANE_BOTTOM]:
		var plane: Plane = pose * projection.get_projection_plane(index)
		if not plane.normal.is_finite() or not is_finite(plane.d) or plane.normal.length_squared() < 0.5: return false
		if plane.distance_to(forward_point) < 0: plane = -plane
		planes.append(plane)
	view_frusta.append(planes)
	return true

func head_pose_failure(pose: XRPose) -> String:
	if pose == null: return "head_pose_missing"
	if not pose.has_tracking_data: return "head_pose_invalidated"
	if pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_HIGH: return "head_pose_low_or_no_confidence"
	if not pose.transform.is_finite(): return "head_pose_nonfinite"
	return ""

func fail_open_views(reason: String) -> Array:
	bounds_complete = false
	view_frusta.clear()
	view_telemetry["fail_open_reason"] = reason
	return []

func collect_culling_views() -> Array:
	var views: Array = []
	view_frusta.clear()
	bounds_complete = true
	view_telemetry = {"source":"desktop","fail_open_reason":"","head_pose_confidence":-1,"head_pose_has_tracking_data":false}
	if head is XRCamera3D:
		view_telemetry.source = "xr_runtime_eyes"
		var interface := XRServer.primary_interface
		if interface == null or not interface.is_initialized(): return fail_open_views("xr_interface_uninitialized")
		if interface.get_view_count() < 1 or interface.get_view_count() > 4: return fail_open_views("xr_view_count_unsupported")
		# The generic interface status is not a portable pose-validity signal.
		# Pinned Godot OpenXR returns an unmaintained tracking_state member.
		# Actual head pose confidence is updated from xrLocateSpace each process.
		var tracker := XRServer.get_tracker("head") as XRPositionalTracker
		var tracked_pose: XRPose = tracker.get_pose("default") if tracker != null else null
		if tracked_pose != null:
			view_telemetry.head_pose_confidence = int(tracked_pose.tracking_confidence)
			view_telemetry.head_pose_has_tracking_data = tracked_pose.has_tracking_data
		var reason := head_pose_failure(tracked_pose)
		if not reason.is_empty(): return fail_open_views(reason)
		var origin := head.get_parent() as XROrigin3D
		if origin == null: return fail_open_views("xr_origin_missing")
		for index in range(interface.get_view_count()):
			var pose := interface.get_transform_for_view(index, origin.global_transform)
			if not pose.is_finite(): return fail_open_views("xr_eye_transform_nonfinite")
			var state: Dictionary = stage.advance_world(stage.observer.global_position + Vector3.UP * 0.5, pose.origin, stage.current_cell)
			views.append({"position":pose.origin,"cell_id":str(state.get("cell_id", ""))})
			if not add_frustum(interface.get_projection_for_view(index, 1.0, head.near, head.far), pose): return fail_open_views("xr_eye_projection_invalid")
	else:
		views.append({"position":head.global_position,"cell_id":str(camera_state(head).get("cell_id", ""))})
		if not add_frustum(head.get_camera_projection(), head.global_transform):
			bounds_complete = false
			view_telemetry.fail_open_reason = "desktop_projection_invalid"
	if is_instance_valid(spectator):
		views.append({"position":spectator.global_position,"cell_id":str(camera_state(spectator).get("cell_id", ""))})
		if not add_frustum(spectator.get_camera_projection(), spectator.global_transform):
			bounds_complete = false
			view_telemetry.fail_open_reason = "spectator_projection_invalid"
	return views

func update_culling() -> void:
	var start := Time.get_ticks_usec()
	var result: Dictionary = native_visibility.solve(collect_culling_views(), VISIBILITY_MARGIN, 8192)
	complete = bool(result.get("complete", false))
	have_visibility = true
	var next: Dictionary = result.get("visible_cells", {})
	if int(result.get("known_cells", 0)) != portal_cells.size():
		for id: String in portal_cells: next[id] = true
	var now := Time.get_ticks_msec()
	for id: String in next: recently_visible[id] = now + VISIBILITY_HOLD_MSEC
	for id: String in recently_visible.keys():
		if int(recently_visible[id]) >= now and portal_cells.has(id): next[id] = true
		else: recently_visible.erase(id)
	if next != visible_cells:
		visible_cells = next
		revision += 1
	var hidden := 0
	var managed := 0
	for id: String in cell_instances:
		var shown := not culling_enabled or is_cell_visible(id)
		managed += cell_instances[id].size()
		if not shown: hidden += cell_instances[id].size()
		if cell_visibility.get(id, null) == shown: continue
		cell_visibility[id] = shown
		for instance: MeshInstance3D in cell_instances[id]:
			if is_instance_valid(instance): instance.visible = shown
	result["enabled"] = culling_enabled
	result["managed_instances"] = managed
	result["hidden_instances"] = hidden
	result["revision"] = revision
	result["bounds_complete"] = bounds_complete
	result["view_tracking"] = view_telemetry.duplicate()
	result["bounds_queries"] = bounds_queries
	result["bounds_rejected"] = bounds_rejected
	result["view_count"] = view_frusta.size()
	result["cpu_usec"] = Time.get_ticks_usec() - start
	result.erase("visible_cells")
	report["culling"] = result

func _process(_delta: float) -> void:
	update_views()

func _exit_tree() -> void:
	for instances: Array in cell_instances.values():
		for instance: MeshInstance3D in instances:
			if is_instance_valid(instance): instance.visible = true
	RenderingServer.global_shader_parameter_set("swg_portal_view_a", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("swg_portal_view_b", Vector4.ZERO)

func plane_for_polygon(polygon: PackedVector3Array) -> Plane:
	return Plane(polygon[0], polygon[1], polygon[2])

func clip_polygon(polygon: PackedVector3Array, plane: Plane) -> PackedVector3Array:
	var output := PackedVector3Array()
	if polygon.is_empty():
		return output
	var previous := polygon[-1]
	var previous_distance := plane.distance_to(previous)
	for point in polygon:
		var distance := plane.distance_to(point)
		var inside := distance >= -0.001
		var previous_inside := previous_distance >= -0.001
		if inside != previous_inside:
			var denominator := previous_distance - distance
			if absf(denominator) > 0.000001:
				output.append(previous.lerp(point, previous_distance / denominator))
		if inside:
			output.append(point)
		previous = point
		previous_distance = distance
	return output

func walk_portals(cells: Dictionary, id: String, eye: Vector3, planes: Array[Plane], visited: Array[String]) -> void:
	visits += 1
	if visits > 256 or visited.size() > 16 or openings.size() >= MAX_OPENINGS:
		overflow = true
		return
	var cell: Dictionary = cells.get(id, {})
	for portal: Dictionary in cell.get("portals", []):
		var next := str(portal.get("leads_to", ""))
		if next.is_empty() or next in visited or not cells.has(next):
			continue
		var polygon: PackedVector3Array = portal.world_vertices
		if polygon.size() < 3:
			continue
		for plane in planes:
			polygon = clip_polygon(polygon, plane)
			if polygon.size() < 3:
				break
		if polygon.size() < 3:
			continue
		var portal_plane := plane_for_polygon(polygon)
		if absf(portal_plane.distance_to(eye)) < 0.002:
			continue
		if cells[next].get("is_exterior", false):
			if polygon.size() > MAX_VERTICES or openings.size() >= MAX_OPENINGS:
				overflow = true
				return
			openings.append(polygon)
			continue
		var center := Vector3.ZERO
		for point in polygon:
			center += point
		center /= polygon.size()
		var next_planes: Array[Plane] = planes.duplicate()
		for i in range(polygon.size()):
			var edge_plane := Plane(eye, polygon[i], polygon[(i + 1) % polygon.size()])
			if edge_plane.distance_to(center) < 0:
				edge_plane = -edge_plane
			# A few centimetres of conservative stereo tolerance avoids clipping
			# an eye's doorway edge against a center-eye portal projection.
			edge_plane.d -= 0.04
			next_planes.append(edge_plane)
		if portal_plane.distance_to(eye) > 0:
			portal_plane = -portal_plane
		next_planes.append(portal_plane)
		var next_visited: Array[String] = visited.duplicate()
		next_visited.append(next)
		walk_portals(cells, next, eye, next_planes, next_visited)

func camera_state(camera: Camera3D) -> Dictionary:
	if not is_instance_valid(camera):
		return {}
	var from: Vector3 = stage.observer.global_position + Vector3.UP * 0.5
	return stage.advance_world(from, camera.global_position, stage.current_cell)

func update_views() -> void:
	if not is_instance_valid(stage) or not is_instance_valid(head) or not is_instance_valid(stage.observer):
		return
	image.fill(Color(0, 0, 0, 0))
	var counts: Array = []
	var view_buildings: Array = []
	for view_index in range(2):
		var camera: Camera3D = head if view_index == 0 else spectator
		var state := camera_state(camera)
		var building := int(state.get("building_object_id", 0))
		if building > 0 and not view_buildings.has(building):
			view_buildings.append(building)
		openings = []
		visits = 0
		overflow = false
		if building != 0:
			var id := str(state.cell_id)
			walk_portals(portal_cells, id, camera.global_position, [], [id])
		# Fail open if a source graph exceeds the explicit renderer budget;
		# traversal/collision is never changed by a rendering limit.
		var position := camera.global_position if is_instance_valid(camera) else Vector3.ZERO
		RenderingServer.global_shader_parameter_set("swg_portal_view_a" if view_index == 0 else "swg_portal_view_b", Vector4(position.x, position.y, position.z, float(building)))
		if overflow:
			image.set_pixel(0, view_index * MAX_OPENINGS, Color(-1, 0, 0, 0))
		for index in range(0 if overflow else openings.size()):
			var polygon: PackedVector3Array = openings[index]
			var row := view_index * MAX_OPENINGS + index
			image.set_pixel(0, row, Color(float(polygon.size()), 0, 0, 0))
			var plane := plane_for_polygon(polygon)
			image.set_pixel(1, row, Color(plane.normal.x, plane.normal.y, plane.normal.z, plane.d))
			for vertex_index in range(polygon.size()):
				var point := polygon[vertex_index]
				image.set_pixel(vertex_index + 2, row, Color(point.x, point.y, point.z, 0))
		counts.append({"building":building,"openings":openings.size(),"overflow":overflow,"visits":visits})
	texture.update(image)
	report["views"] = counts
	update_culling()
	if stage.has_method("set_view_buildings"):
		stage.set_view_buildings(view_buildings)

func rebuild_portal_cells() -> void:
	portal_cells.clear()
	for region: Dictionary in stage.all_floor_regions():
		for id: String in region.cells:
			var cell: Dictionary = region.cells[id].duplicate()
			var portals: Array = []
			for original: Dictionary in cell.get("portals", []):
				var portal := original.duplicate()
				var vertices: Array = portal.get("vertices", [])
				var polygon := PackedVector3Array()
				for index in range(0, vertices.size() - 2, 3):
					polygon.append(region.transform * Vector3(vertices[index], vertices[index+1], vertices[index+2]))
				portal["world_vertices"] = polygon
				portals.append(portal)
			cell["portals"] = portals
			portal_cells[id] = cell
