extends SceneTree

var checks := 0
var errors: Array[String] = []
var probes: Array[Dictionary] = []
const SOURCES := [
	"appearance/mun_tato_starport_s01_u01.pob#cell:0",
	"appearance/mun_corl_starport_s01_u01.pob#cell:0",
	"appearance/mun_nboo_starport_s01_u01.pob#cell:0",
]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		errors.append(label)
		push_error(label)

func read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func point(values: Array, offset := 0) -> Vector3:
	return Vector3(values[offset], values[offset + 1], values[offset + 2])

func entry_transform(entry: Dictionary) -> Transform3D:
	var q: Array = entry.quaternion
	var basis := Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized())
	if entry.has("scale"):
		basis = basis.scaled(point(entry.scale))
	return Transform3D(basis, point(entry.position))

func portal_frame(cell: Dictionary, id: int) -> Dictionary:
	for portal: Dictionary in cell.portals:
		if int(portal.id) != id:
			continue
		var vertices: Array = portal.vertices
		var center := Vector3.ZERO
		for offset in range(0, vertices.size(), 3):
			center += point(vertices, offset)
		center /= vertices.size() / 3
		var normal := (point(vertices, 3) - point(vertices)).cross(point(vertices, 6) - point(vertices)).normalized()
		return {"center": center, "normal": normal, "floor_portal_index": portal.floor_portal_index}
	return {}

func sweep(player: CharacterBody3D, frame: Dictionary, start: float, finish: float) -> Dictionary:
	var from: Vector3 = frame.center + frame.normal * start
	var motion: Vector3 = frame.normal * (finish - start)
	var hit := KinematicCollision3D.new()
	var blocked := player.test_move(Transform3D(Basis.IDENTITY, from), motion, hit)
	return {"blocked": blocked, "from": str(from), "motion": str(motion),
		"hit": str(hit.get_position()) if blocked else "", "normal": str(hit.get_normal()) if blocked else ""}

func run() -> void:
	var worlds: Array[String] = ["res://../runtime/assets/tatooine_world/world.json"]
	for planet in ["corellia", "dantooine", "dathomir", "endor", "lok", "naboo", "rori", "talus", "yavin4"]:
		worlds.append("res://../runtime/assets/planets/" + planet + "/world/world.json")
	var placements: Array[Dictionary] = []
	for path: String in worlds:
		var world := read_json(path)
		for descriptor: Dictionary in world.chunks.values():
			var chunk := read_json(path.get_base_dir().path_join(str(descriptor.path)))
			for entry: Dictionary in chunk.instances:
				if not SOURCES.has(str(entry.get("collision_id", ""))) or not entry.get("collision_owner", true):
					continue
				placements.append({"planet": world.planet, "entry": entry, "cell": chunk.cells[entry.cell_id], "definitions": world.collisions})
	check(placements.size() == 15, "All 15 original starport placements loaded")
	var loader = preload("res://scripts/stage_loader.gd").new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = .22
	var player := CharacterBody3D.new()
	player.collision_layer = 0
	player.collision_mask = 1
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	player.add_child(collider)
	root.add_child(player)
	for placement: Dictionary in placements:
		var entry: Dictionary = placement.entry
		var original: Dictionary = placement.cell
		var departure := portal_frame(original, 2)
		var arrival := portal_frame(original, 0)
		var toe_height := INF
		for triangle: Dictionary in original.floor_triangles:
			if triangle.get("fallthrough",false): continue
			for vertex in triangle.indices:
				toe_height = minf(toe_height,float(original.floor_vertices[int(vertex)*3+1]))
		var lower: Dictionary = departure.duplicate()
		lower.center.y = toe_height + capsule.height * .5 + .02
		check(not departure.is_empty() and not arrival.is_empty(), str(entry.cell_id) + " original portals present")
		if departure.is_empty() or arrival.is_empty():
			continue
		for mode in ["legacy_without_floor", "connected_floor", "closed_floor_adjacency", "wall_base_adjacency", "wall_top_adjacency"]:
			var cell: Dictionary = original.duplicate(true)
			if mode == "legacy_without_floor":
				cell.floor_vertices = []
				cell.floor_triangles = []
			elif mode != "connected_floor":
				var modified := 0
				for triangle: Dictionary in cell.floor_triangles:
					if not triangle.portal_ids.has(departure.floor_portal_index):
						continue
					for edge in range(3):
						if triangle.neighbors[edge] >= 0 and triangle.edge_flags[edge] != 0:
							triangle.edge_flags[edge] = 2 if mode == "wall_base_adjacency" else (3 if mode == "wall_top_adjacency" else 0)
							modified += 1
				check(modified > 0, str(entry.cell_id) + " fixture restricts real portal-root floor adjacency: " + mode)
			var body: StaticBody3D = loader.make_collision_body(entry, placement.definitions, null, {str(entry.cell_id): cell})
			check(body != null, str(entry.cell_id) + " authored shell built " + mode)
			if body == null:
				continue
			body.transform = entry_transform(entry)
			root.add_child(body)
			await physics_frame
			await physics_frame
			var inward := sweep(player, departure, -2.7, .45)
			var outward := sweep(player, departure, .45, -2.7)
			var distant := sweep(player, arrival, 7.8, 9.7)
			var lower_inward := sweep(player, lower, -2.7, -1.3)
			var lower_outward := sweep(player, lower, -1.3, -2.7)
			var below: Vector3 = departure.center
			below.y = toe_height - .15
			var basement := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(below + departure.normal * -2.7,below + departure.normal * -.8,1))
			var expected_block: bool = mode != "connected_floor"
			var label: String = str(placement.planet) + ":" + str(entry.cell_id) + " " + mode
			check(bool(inward.blocked) == expected_block, label + " departures inward capsule clearance")
			check(bool(outward.blocked) == expected_block, label + " departures outward capsule clearance")
			check(bool(distant.blocked), label + " unrelated arrivals wall at 8.725m remains solid")
			check(bool(lower_inward.blocked) == expected_block, label + " original stair-toe capsule inward clearance below portal sill")
			check(bool(lower_outward.blocked) == expected_block, label + " original stair-toe capsule outward clearance below portal sill")
			check(not basement.is_empty(), label + " shell below the actual source floor remains solid")
			probes.append({"planet": placement.planet, "cell": entry.cell_id, "collision": entry.collision_id,
				"mode": mode, "departures_inward": inward, "departures_outward": outward, "distant_arrivals_wall": distant,
				"toe_height":toe_height,"lower_inward":lower_inward,"lower_outward":lower_outward,"below_floor_shell_retained":not basement.is_empty()})
			body.queue_free()
			await process_frame
			await physics_frame
	player.queue_free()
	await process_frame
	var report := {"test": "source_floor_portal_corridor", "passed": errors.is_empty(), "checks": checks,
		"errors": errors, "placements": placements.size(), "probes": probes, "actual_source_assets": true,
		"actual_cell_transforms": true, "native_capsule_physics": true, "renderer": "dummy", "hardware_tested": false,
		"scope": "CMSH shell clearance above original floors; actual stair walking is tested separately."}
	FileAccess.open("res://../runtime/evidence/source-floor-portal-corridor-smoke.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print(JSON.stringify({"passed": report.passed, "checks": checks, "placements": placements.size(), "errors": errors}))
	quit(0 if errors.is_empty() else 1)
