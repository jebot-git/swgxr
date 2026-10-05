extends SceneTree
## Two simultaneous desktop views exercise the actual exterior portal shader.
class Stage extends Node3D:
	signal interior_cells_changed
	var exterior_instances: Array[MeshInstance3D] = []
	var cell_regions := {}
	var observer: Node3D
	var current_cell := {"cell_id":"1:1", "building_object_id":1}
	func advance_world(_from: Vector3, to: Vector3, state: Dictionary) -> Dictionary:
		return {} if to.x > 2.0 else state
	func all_floor_regions() -> Array:
		return [{"transform":Transform3D.IDENTITY, "cells":{
			"1:1":{"building_object_id":1,"is_exterior":false,"portals":[{"leads_to":"1:2","vertices":[-0.5,0.5,-3, -0.5,1.5,-3, 0.5,1.5,-3, 0.5,0.5,-3]}]},
			"1:2":{"building_object_id":1,"is_exterior":false,"portals":[{"leads_to":"1:0","vertices":[-1,0,-4, -1,2,-4, 1,2,-4, 1,0,-4]}]},
			"1:0":{"building_object_id":1,"is_exterior":true,"portals":[]}}}]

var errors: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)
func mesh(stage: Stage, position: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/static_baked.gdshader")
	material.set_shader_parameter("albedo_color", color)
	instance.material_override = material
	instance.position = position
	instance.set_meta("building_object_id", 1)
	stage.add_child(instance)
	stage.exterior_instances.append(instance)
func view(world: World3D, position: Vector3) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320,240)
	viewport.world_3d = world
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = position
	viewport.add_child(camera)
	camera.make_current()
	return viewport
func run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.observer = Node3D.new()
	stage.add_child(stage.observer)
	stage.observer.position = Vector3(0,0.5,0)
	mesh(stage, Vector3(0,1,-2), Vector3(12,4,0.1), Color(1,0.05,0.05))
	mesh(stage, Vector3(0,1,-6), Vector3(6,2,0.1), Color(0.05,1,0.05))
	var inside := view(stage.get_world_3d(), Vector3(0,1,0))
	var outside := view(stage.get_world_3d(), Vector3(4,1,0))
	var visibility = load("res://scripts/portal_visibility.gd").new()
	root.add_child(visibility)
	visibility.configure(stage, inside.get_camera_3d(), outside.get_camera_3d())
	visibility.update_views()
	check(visibility.report.views[0].openings == 1 and visibility.report.views[0].building == 1, "Interior portal opening was not projected")
	check(visibility.report.views[1].building == 0, "Spectator incorrectly inherited interior cell")
	if DisplayServer.get_name() != "headless":
		for i in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var left := inside.get_texture().get_image()
		var right := outside.get_texture().get_image()
		var a := left.get_pixel(160,120)
		var b := right.get_pixel(160,120)
		check(a.g > a.r * 2.0, "Interior ray failed to hide foreground shell/preserve exterior through portal: %s" % a)
		check(b.r > b.g * 2.0, "Exterior spectator lost its building shell: %s" % b)
		left.save_png(ProjectSettings.globalize_path("res://../runtime/evidence/portal-inside.png"))
		right.save_png(ProjectSettings.globalize_path("res://../runtime/evidence/portal-outside.png"))
		# Visibility budget exhaustion must preserve the exterior without
		# falsifying camera membership used by the independent terrain masks.
		visibility.set_process(false)
		visibility.image.set_pixel(0, 0, Color(-1, 0, 0, 0))
		visibility.texture.update(visibility.image)
		for i in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var fallback := inside.get_texture().get_image().get_pixel(160,120)
		check(fallback.r > fallback.g * 2.0, "Portal budget fallback incorrectly discarded exterior geometry")
	var report := {"test":"per_view_portal_visibility", "passed":errors.is_empty(), "errors":errors, "views":visibility.report.views, "gpu_tested":DisplayServer.get_name() != "headless", "hardware_tested":false}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/portal-render-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	visibility.queue_free()
	inside.queue_free()
	outside.queue_free()
	stage.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
