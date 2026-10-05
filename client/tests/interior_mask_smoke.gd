extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func limits(image: Image, point: Vector2, origin: Vector2, size := 128.0) -> Vector2:
	var uv := (point - origin) / size
	var color := image.get_pixel(clampi(floori(uv.x * image.get_width()), 0, image.get_width() - 1), clampi(floori(uv.y * image.get_height()), 0, image.get_height() - 1))
	return Vector2(color.r, color.g)

func run() -> void:
	var rasterizer := SwgInteriorMask.new()
	var triangle := {"bounds_min":[10, 0, -20], "bounds_max":[20, 3, -10], "floor_vertices":[10,0,-10, 20,1,-10, 10,0,-20], "floor_indices":[0,1,2]}
	var elevated := {"bounds_min":[30, 5, -20], "bounds_max":[40, 8, -10], "floor_vertices":[30,5,-10, 40,5,-10, 30,5,-20], "floor_indices":[0,1,2]}
	var exterior: Dictionary = triangle.duplicate(true)
	exterior.is_exterior = true
	exterior.floor_vertices = [50,0,-10, 60,0,-10, 50,0,-20]
	exterior.bounds_min = [50,0,-20]
	exterior.bounds_max = [60,3,-10]
	var result := rasterizer.rasterize([{"cells":{"sloped":triangle,"upper":elevated,"outside":exterior}}], Vector2.ZERO, Vector3.ZERO)
	assert(result.valid and result.has("image"))
	var image: Image = result.image
	var inside := limits(image, Vector2(12.125,12.125), Vector2.ZERO)
	var outside := limits(image, Vector2(18.125,18.125), Vector2.ZERO)
	var boundary := limits(image, Vector2(9.875,12.125), Vector2.ZERO)
	assert(boundary.x > boundary.y, "Wall padding escaped original cell bounds")
	var upper := limits(image, Vector2(32.125,12.125), Vector2.ZERO)
	var shell := limits(image, Vector2(52.125,12.125), Vector2.ZERO)
	assert(absf(inside.x - (0.2125 - 0.06)) < 0.001 and inside.y > 3)
	assert(outside.x > outside.y, "AABB outside triangle was incorrectly cut out")
	assert(upper.x > 4.9 and upper.x > 0, "Elevated floor incorrectly removes lower terrain")
	assert(shell.x > shell.y, "Exterior source cell removed terrain")
	var directory := ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/")
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("world.json")))
	var chunk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(world.chunks["-1:0"].path)))
	var origin: Array = world.origin
	var world_origin := Vector3(origin[0], origin[1], origin[2])
	var point := Vector3(-168.9234, -0.89, 28.47235)
	var source := Vector2(point.x + world_origin.x, world_origin.z - point.z)
	var corner := Vector2(floorf(source.x / 128) * 128, floorf(source.y / 128) * 128)
	var started := Time.get_ticks_usec()
	result = rasterizer.rasterize([{"cells":chunk.cells}], corner, world_origin)
	var elapsed := Time.get_ticks_usec() - started
	assert(result.has("image"))
	var real := limits(result.image, source, corner)
	assert(real.x < -0.89 and real.y > 0.0, "Actual cantina volume does not remove terrain at ground Y0")
	var output := {"test":"source_cell_terrain_volume_mask","passed":true,"resolution_m":0.25,"wall_padding_m":0.3,"padding_clipped_to_source_bounds":true,"actual_cantina_floor_limit":real.x,"actual_cantina_ceiling_limit":real.y,"actual_chunk_cells":result.cells,"actual_chunk_triangles":result.triangles,"actual_chunk_covered_texels":result.covered_texels,"actual_chunk_raster_usec":elapsed,"outside_polygon_preserved":true,"elevated_floor_preserves_lower_ground":true,"exterior_ignored":true,"sloped_floor_interpolated":true}
	print(JSON.stringify(output))
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/interior-mask-smoke.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"  ") + "\n")
	quit()
