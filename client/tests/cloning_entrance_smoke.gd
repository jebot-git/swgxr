extends SceneTree

var probes: Array[Dictionary] = []
var errors: Array[String] = []
func _initialize() -> void: call_deferred("run")
func point(a: Array, i := 0) -> Vector3: return Vector3(a[i], a[i+1], a[i+2])
func read_json(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func run() -> void:
	var worlds: Array[String] = ["res://../runtime/assets/tatooine_world/world.json"]
	for planet in ["corellia", "dantooine", "dathomir", "endor", "lok", "naboo", "rori", "talus", "yavin4"]:
		worlds.append("res://../runtime/assets/planets/" + planet + "/world/world.json")
	var loader = preload("res://scripts/stage_loader.gd").new()
	var player := CharacterBody3D.new()
	player.collision_layer = 0
	player.collision_mask = 1
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = .22
	collider.shape = capsule
	player.add_child(collider)
	root.add_child(player)
	var buildings := 0
	var retained_walls := 0
	var guarded_closures := 0
	for path: String in worlds:
		var world := read_json(path)
		for descriptor: Dictionary in world.chunks.values():
			var chunk := read_json(path.get_base_dir().path_join(str(descriptor.path)))
			for id: String in chunk.cells:
				var cell: Dictionary = chunk.cells[id]
				if not cell.get("is_exterior", false) or not "cloning" in str(cell.get("source_pob", "")): continue
				buildings += 1
				var building := Node3D.new()
				root.add_child(building)
				for entry: Dictionary in chunk.instances:
					if not str(entry.get("cell_id", "")).begins_with(id.get_slice(":",0)+":"): continue
					var body: StaticBody3D = loader.make_collision_body(entry,world.collisions,null,chunk.cells)
					if body == null: continue
					var q: Array = entry.quaternion
					body.transform = Transform3D(Basis(Quaternion(q[0],q[1],q[2],q[3]).normalized()),point(entry.position))
					building.add_child(body)
				await physics_frame
				await physics_frame
				for portal: Dictionary in cell.portals:
					if not portal.get("passable",false): continue
					var a: Array = portal.vertices
					var center := Vector3.ZERO
					var bottom := INF
					for i in range(0,a.size(),3):
						center += point(a,i)
						bottom = minf(bottom,float(a[i+1]))
					center /= a.size()/3
					center.y = bottom + .87
					var normal := (point(a,3)-point(a)).cross(point(a,6)-point(a)).normalized()
					normal.y = 0
					normal = normal.normalized()
					var sideways := normal.cross(Vector3.UP)
					var half_width := 0.0
					for i in range(0,a.size(),3):
						half_width = maxf(half_width,absf((point(a,i)-center).dot(sideways)))
					for lateral in [-half_width+.5,-.6,0.0,.6,half_width-.5]:
						for direction in [-1.0,1.0]:
							var start: Vector3 = center + sideways*lateral - normal*direction*1.5
							var hit := KinematicCollision3D.new()
							var blocked := player.test_move(Transform3D(Basis.IDENTITY,start),normal*direction*3.0,hit)
							var row := {"planet":world.planet,"cell":id,"source":cell.source_pob,"portal":portal.id,"lateral":lateral,"direction":direction,"blocked":blocked,"center":str(center)}
							if blocked:
								row["hit"] = str(hit.get_position())
								row["normal"] = str(hit.get_normal())
								row["collision"] = hit.get_collider().get_meta("collision_source", "")
								errors.append(str(row))
							probes.append(row)
					# The shell alongside the opening and above its lintel stays solid.
					for wall_center: Vector3 in [center+sideways*(half_width+1.0), Vector3(center.x,bottom+3.6,center.z)]:
						var query := PhysicsRayQueryParameters3D.create(wall_center-normal*3.0,wall_center+normal*3.0,1)
						if player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
							errors.append(id+" doorway cut removed adjacent wall or lintel")
						else: retained_walls += 1
				building.queue_free()
				await process_frame
				await physics_frame
				# Without the connected source approach, the sloped shell must not
				# be opened beyond the original narrow portal tolerance.
				for mode in ["missing_floor", "disabled_portal"]:
					var restricted: Dictionary = cell.duplicate(true)
					if mode == "missing_floor":
						restricted.floor_vertices = []
						restricted.floor_triangles = []
					else:
						for portal: Dictionary in restricted.portals: portal.source_disabled = true
					for entry: Dictionary in chunk.instances:
						if entry.get("cell_id", "") != id or entry.get("collision_id", "") != cell.collision_id or not entry.get("collision_owner",true): continue
						var body: StaticBody3D = loader.make_collision_body(entry,world.collisions,null,{id:restricted})
						var q: Array = entry.quaternion
						body.transform = Transform3D(Basis(Quaternion(q[0],q[1],q[2],q[3]).normalized()),point(entry.position))
						root.add_child(body)
						await physics_frame
						await physics_frame
						var a: Array = cell.portals[0].vertices
						var center := Vector3.ZERO
						var bottom := INF
						for i in range(0,a.size(),3):
							center += point(a,i)
							bottom = minf(bottom,float(a[i+1]))
						center /= a.size()/3
						center.y = bottom+.87
						var normal := (point(a,3)-point(a)).cross(point(a,6)-point(a)).normalized()
						if not player.test_move(Transform3D(Basis.IDENTITY,center-normal*1.5),normal*3.0):
							errors.append(id+" closure incorrectly opened with "+mode)
						else: guarded_closures += 1
						body.queue_free()
						await process_frame
						await physics_frame
	if buildings != 19: errors.append("Expected all 19 original ground cloning centres")
	if retained_walls != 38 or guarded_closures != 38: errors.append("Missing wall-preservation or restricted-portal probes")
	var report := {"passed":errors.is_empty(),"buildings":buildings,"retained_wall_probes":retained_walls,"guarded_closures":guarded_closures,"probes":probes,"errors":errors,"renderer":"dummy","hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/cloning-entrance-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":report.passed,"buildings":buildings,"probes":probes.size(),"failures":errors.size()}))
	player.queue_free()
	await process_frame
	quit(0 if report.passed else 1)
