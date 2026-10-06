extends SceneTree
## Native-normalized source appearance/options may be replayed; no server mutation.
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1060,760)
	var file:="res://../runtime/evidence/entertainment/image-design-preview.json"
	var state:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(file))
	var panel:=preload("res://entertainment/image_design_panel.gd").new();root.add_child(panel);panel.position=Vector2(100,90);panel.apply_design(state)
	panel.message="Original appearance preview · exact proposal requires both players' acceptance"
	for frame in range(6):await process_frame
	await RenderingServer.frame_post_draw
	var path:="res://../runtime/evidence/entertainment/image-design-vulkan.png"
	var error:=root.get_texture().get_image().save_png(path)
	print(JSON.stringify({"capture":ProjectSettings.globalize_path(path),"saved":error==OK,"renderer":RenderingServer.get_current_rendering_method(),"live_xr":false,"avatar_report":panel.preview_avatar.report}))
	panel.free();await process_frame;quit(0 if error==OK else 1)
