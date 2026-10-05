extends SceneTree
## Exact original NPC rig/clothes/material evidence; no substituted player races.
const Avatar = preload("res://scripts/avatar.gd")
const VirtualSkin = preload("res://scripts/virtual_skin_binding.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	RenderingServer.global_shader_parameter_set("swg_environment_tint",Color.WHITE)
	RenderingServer.global_shader_parameter_set("swg_indoor_tint",Color.WHITE)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.14,0.18,0.21)
	environment.environment = settings
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.fov = 40
	camera.cull_mask = 3
	world.add_child(camera)
	camera.make_current()
	var directory := ProjectSettings.globalize_path("res://../runtime/evidence/npc-portraits")
	DirAccess.make_dir_recursive_absolute(directory)
	var reports: Array = []
	for template in ["object/mobile/jawa_male.iff","object/mobile/dressed_stormtrooper_m.iff","object/mobile/dressed_tatooine_mos_eisley_police_officer.iff","object/mobile/space_chassis_broker_05.iff"]:
		var avatar := Avatar.new()
		world.add_child(avatar)
		avatar.load_catalog(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"))
		var definition: Dictionary = avatar.catalog.races[template]
		var result: Dictionary = avatar.configure(template,definition.default_appearance)
		assert(result.error == "")
		var model: Dictionary = avatar.get_model(definition.body)
		var helper: Node = null
		if not model.get("virtual_skin_bones",[]).is_empty():
			helper = VirtualSkin.new()
			avatar.add_child(helper)
			assert(helper.configure(avatar,model.virtual_skin_bones))
		avatar.animation_player.play("idle")
		avatar.animation_player.advance(0.65)
		if helper:helper.update_bindings()
		var height: float = avatar.height_meters
		camera.position = Vector3(-height*0.8,height*0.6,-height*1.8)
		camera.look_at(Vector3(0,height*0.5,0))
		for frame in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(template.get_file().get_basename()+".png"))
		reports.append({"template":template,"surfaces":result.surfaces,"parts":result.parts,"bones":result.bones,"virtual_skin":helper.report if helper else {},"source_idle":model.animations.idle.source,"no_dynamic_lights":true})
		avatar.free()
	var file := FileAccess.open(directory.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"  ")+"\n")
	print("NPC_PORTRAITS ",JSON.stringify(reports))
	quit()
