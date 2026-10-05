extends SceneTree
## Render source-derived reference thumbnails from already-imported original models.
## Invoke with Godot --xr-mode off --path client --script ../tools/assets/render_datapad_previews.gd
const Avatar = preload("res://scripts/avatar.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := ProjectSettings.globalize_path("res://../runtime/assets/datapad")
	var source := ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json")
	var catalog_path := directory.path_join("catalog.json")
	var catalog := Avatar.read_json(catalog_path)
	if catalog.is_empty(): push_error("Prepare datapad catalog first"); quit(1); return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512,512)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var avatar := Avatar.new()
	viewport.add_child(avatar)
	avatar.load_catalog(source)
	var identity := "object/mobile/nhelper_droid.iff"
	if not avatar.catalog.get("races",{}).has(identity): push_error("Exact source helper R2 model unavailable"); quit(1); return
	var descriptor: Dictionary = avatar.catalog.races[identity]
	var result: Dictionary = avatar.configure(identity,descriptor.get("default_appearance",{}),[])
	if not str(result.get("error","")).is_empty(): push_error(str(result)); quit(1); return
	avatar.set_tracking_mode(true)
	for mesh in avatar.meshes: mesh.layers = 1
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = avatar.height_meters*1.22
	camera.cull_mask = 3
	var center := Vector3(0,avatar.height_meters*0.5,0)
	camera.position = center+Vector3(-1.6,0.7,-3.0)
	camera.look_at(center)
	camera.make_current()
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory.path_join("previews"))
	var relative := "previews/nhelper_droid.png"
	var error := viewport.get_texture().get_image().save_png(directory.path_join(relative))
	if error!=OK: push_error("Failed to save original helper preview"); quit(1); return
	var metadata := {"template":"object/intangible/pet/shared_nhelper_droid.iff","preview_texture":relative,"source_mobile":identity,"source_appearance":descriptor.appearance,"source_cdf":descriptor.source_cdf,"source_model":descriptor.body,"source_catalog_sha256":FileAccess.get_sha256(source),"source_model_sha256":FileAccess.get_sha256(source.get_base_dir().path_join(descriptor.body)),"default_customization":descriptor.get("default_appearance",{}).get("customization",{}),"policy":"Reference thumbnail rendered from original helper R2 mobile mesh and its authored default CDF customization. Does not grant a pet or replace authoritative character customization."}
	var previews: Dictionary = catalog.get("template_previews",{})
	previews[metadata.template]=metadata
	catalog["template_previews"]=previews
	FileAccess.open(catalog_path,FileAccess.WRITE).store_string(JSON.stringify(catalog,"  ")+"\n")
	FileAccess.open(directory.path_join("previews/manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(previews,"  ")+"\n")
	print(JSON.stringify({"preview":relative,"source":identity,"ok":true}))
	viewport.queue_free()
	await process_frame
	quit()
