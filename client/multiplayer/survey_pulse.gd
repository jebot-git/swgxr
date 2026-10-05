extends Node3D
## Bounded source-style approximation of Core3's survey_tool_*.cef broadcast.
## It is a visual acknowledgement, never a local survey/yield simulation.
const MAX_PULSES := 8
const MAX_DISTANCE := 64.0
const RADIUS := 12.0
const DURATION := 1.8
var camera: Camera3D
var pulses: Array = []
var seen: Dictionary = {}
var material: ShaderMaterial
var ring_mesh: ArrayMesh
var accepted := 0
var rejected := 0

static func shared(owner: Node, eye: Camera3D = null) -> Node3D:
	var viewport := owner.get_viewport()
	for node in owner.get_tree().get_nodes_in_group("swg_survey_pulse"):
		if not node.is_queued_for_deletion() and node.get_world_3d() == viewport.find_world_3d():
			if eye != null: node.camera = eye
			return node
	var manager: Node3D = load("res://multiplayer/survey_pulse.gd").new()
	manager.name = "ConfirmedSurveyPulses"
	viewport.add_child(manager)
	manager.camera = eye if eye != null else viewport.get_camera_3d()
	return manager

func _ready() -> void:
	add_to_group("swg_survey_pulse")
	material = ShaderMaterial.new()
	material.shader = preload("res://multiplayer/survey_pulse.gdshader")
	material.set_shader_parameter("pulse_radius", RADIUS)
	# Two narrow annuli share one immutable mesh. A full transparent ground
	# quad would shade its empty center/outer corners in both XR eyes.
	var vertices := PackedVector3Array()
	var coordinates := PackedVector2Array()
	var indices := PackedInt32Array()
	for layer in range(2):
		var first := vertices.size()
		for segment in range(65):
			var angle := TAU * float(segment) / 64.0
			for edge in range(2):
				vertices.append(Vector3(cos(angle), 0, sin(angle)))
				coordinates.append(Vector2(edge, layer))
		for segment in range(64):
			var i := first + segment * 2
			indices.append_array(PackedInt32Array([i, i+1, i+2, i+1, i+3, i+2]))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = coordinates; arrays[Mesh.ARRAY_INDEX] = indices
	ring_mesh = ArrayMesh.new(); ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func within_view(point: Vector3) -> bool:
	if not is_instance_valid(camera): return true
	if camera.global_position.distance_squared_to(point) > MAX_DISTANCE * MAX_DISTANCE: return false
	# Keep a guard band around the full expanding ring for both OpenXR eyes.
	if camera.is_position_in_frustum(point): return true
	for offset in [Vector3(RADIUS,0,0), Vector3(-RADIUS,0,0), Vector3(0,0,RADIUS), Vector3(0,0,-RADIUS)]:
		if camera.is_position_in_frustum(point + offset): return true
	return false

func play_confirmed(point: Vector3, receipt: String) -> bool:
	if not point.is_finite() or receipt.is_empty() or seen.has(receipt): rejected += 1; return false
	seen[receipt] = true
	while seen.size() > 256: seen.erase(seen.keys()[0])
	if pulses.size() >= MAX_PULSES or not within_view(point): rejected += 1; return false
	var mesh := MeshInstance3D.new()
	mesh.mesh = ring_mesh
	mesh.custom_aabb = AABB(Vector3(-RADIUS-1.0, -0.1, -RADIUS-1.0), Vector3((RADIUS+1.0)*2.0, 0.2, (RADIUS+1.0)*2.0))
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.ignore_occlusion_culling = false
	mesh.visibility_range_end = MAX_DISTANCE
	add_child(mesh)
	mesh.global_position = point + Vector3.UP * 0.055
	pulses.append({"node": mesh, "age": 0.0, "origin": point})
	accepted += 1
	return true

func advance(delta: float) -> void:
	for index in range(pulses.size() - 1, -1, -1):
		var pulse: Dictionary = pulses[index]
		pulse.age += maxf(delta, 0.0)
		if pulse.age >= DURATION:
			pulse.node.queue_free()
			pulses.remove_at(index)
			continue
		pulse.node.visible = within_view(pulse.origin)
		pulse.node.set_instance_shader_parameter("pulse_phase", pulse.age / DURATION)

func _process(delta: float) -> void:
	advance(delta)

func clear() -> void:
	for pulse in pulses: pulse.node.queue_free()
	pulses.clear()
	seen.clear()

func statistics() -> Dictionary:
	return {"active": pulses.size(), "limit": MAX_PULSES, "distance_m": MAX_DISTANCE, "accepted": accepted, "rejected": rejected, "lights": 0, "shadows": 0, "triangles_per_pulse":256, "shared_geometry":true, "source_graph_approximation": true}
