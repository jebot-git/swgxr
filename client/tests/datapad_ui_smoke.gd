extends SceneTree
const UI = preload("res://scripts/datapad_ui.gd")
var ui: Control
var selected: Dictionary = {}
var requested: Dictionary = {}
var deleted: Dictionary = {}
var report := {"test":"datapad_ui", "passed":false}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1450,625)
	ui = UI.new()
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(900,625)
	var detail: Control = ui.take_detail_panel()
	root.add_child(detail)
	detail.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	detail.position = Vector2(910,0)
	detail.size = Vector2(540,625)
	var directory := ProjectSettings.globalize_path("res://../runtime/assets/datapad")
	var manifest: Dictionary = {}
	if FileAccess.file_exists(directory.path_join("catalog.json")): manifest = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("catalog.json")))
	ui.configure(manifest,directory)
	ui.entry_selected.connect(func(entry): selected = entry)
	ui.new_waypoint_requested.connect(func(position,label): requested={"position":position,"label":label})
	ui.delete_entry_requested.connect(func(entry): deleted=entry)
	ui.set_player_position(Vector3(3528,5,-4800))
	ui.set_entries([{"id":"fixture1","name":"Mos Eisley starport","category":"waypoints","planet":"tatooine","position":[3528,5,-4800],"description":"UI test fixture: saved navigation marker.","active":true}])
	assert(selected.id == "fixture1" and detail.get_parent() == root)
	assert(not ui.map.has_cursor and ui.delete_button.disabled)
	ui.waypoint_button.pressed.emit()
	assert(requested.position == Vector3(3528,5,-4800) and requested.label == "My location")
	ui.show_map(true)
	await process_frame
	await process_frame
	assert(ui.size.y<=625 and ui.waypoint_button.get_global_rect().end.y<=625)
	var target := Vector3(1500,0,-2200)
	var screen: Vector2 = ui.map.world_to_screen(target)
	assert(ui.map.screen_to_world(screen).distance_to(target) < 0.01)
	var before: Vector3 = ui.map.screen_to_world(screen)
	ui.map.change_zoom(2.0,screen)
	assert(ui.map.screen_to_world(screen).distance_to(before)<0.02)
	var old_center: Vector2 = ui.map.center
	ui.scroll_at(ui.map.get_global_rect().get_center()-ui.global_position,Vector2(20,35))
	assert(ui.map.center != old_center)
	var click := InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.position=ui.map.world_to_screen(target)
	click.pressed=true
	ui.map._gui_input(click)
	click.pressed=false
	ui.map._gui_input(click)
	ui.waypoint_button.pressed.emit()
	assert(requested.position.distance_to(target)<0.01 and requested.label == "Map waypoint")
	ui.show_map(false)
	ui.waypoint_button.pressed.emit()
	assert(requested.position.distance_to(target)<0.01)
	ui.map.has_cursor=false
	ui.update_coordinates()
	ui.waypoint_button.pressed.emit()
	assert(requested.position==ui.player_position and requested.label=="My location")
	ui.set_entries([{"id":"42","name":"User waypoint","category":"waypoints","source":"core3_player_waypoint_list","deletable":true}])
	assert(not ui.delete_button.disabled)
	ui.delete_button.pressed.emit()
	assert(deleted.id=="42")
	assert(not UI.can_delete({"deletable":true,"source":"core3_player_waypoint_list","server_driven":true}))
	assert(not UI.can_delete({"deletable":true,"source":"core3_datapad_container","reference_only":true}))
	ui.set_busy(true,"Saving to CoreCU…")
	assert(ui.waypoint_button.disabled and ui.delete_button.disabled)
	ui.set_busy(false,"UI test fixture")
	ui.select_category("pets")
	assert(ui.filtered_entries.is_empty() and ui.detail_title.text == "No entries")
	ui.select_category("waypoints")
	ui.map.center = Vector2(3528,-4800)
	ui.map.zoom = 3
	ui.map.queue_redraw()
	if "--capture" in OS.get_cmdline_user_args():
		ui.show_map(true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/datapad-ui-map.png"))
		ui.show_map(false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/datapad-ui-list.png"))
	report.passed = true
	report.coordinate_roundtrip = true
	report.zoom_anchor_preserved = true
	report.continuous_scroll = true
	report.explicit_waypoint_origin = true
	report.empty_categories_not_fabricated = true
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/datapad-ui-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	ui.queue_free()
	detail.queue_free()
	await process_frame
	quit()
