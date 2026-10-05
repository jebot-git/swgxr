extends SceneTree
## Render actual source facial layers under distinct persisted customization values.
const Avatar = preload("res://scripts/avatar.gd")
const Materials = preload("res://scripts/avatar_materials.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.12, 0.14, 0.17)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -30, 0)
	world.add_child(light)
	var avatar := Avatar.new()
	world.add_child(avatar)
	var camera := Camera3D.new()
	camera.fov = 34
	world.add_child(camera)
	var directory := ProjectSettings.globalize_path("res://../runtime/evidence/facial")
	DirAccess.make_dir_recursive_absolute(directory)
	var cases := {
		"human_male": {"/private/index_style_beard": 17, "/private/index_style_eyebrow": 6, "/private/index_style_freckles": 4, "/private/index_color_facial_hair": 87},
		"human_female": {"/private/index_style_eyebrow": 7, "/private/index_style_eyeshadow": 1, "/private/index_color_eyeshadow": 200, "/private/index_color_lips": 80, "/private/index_style_freckles": 4},
		"zabrak_male": {"/private/index_style_tattoo": 2, "/private/index_color_tattoo": 0, "/private/index_style_freckles": 4},
		"twilek_female": {"/private/index_style_eyebrow": 9, "/private/index_style_eyeshadow": 1, "/private/index_color_eyeshadow": 200, "/private/index_color_lips": 80},
		"wookiee_male": {"/shared_owner/index_texture_1": 24, "/shared_owner/index_color_1": 190, "/shared_owner/index_color_3": 10, "/private/index_color_2": 100}
	}
	var results: Array = []
	for race in cases:
		var initial := {"/shared_owner/index_color_skin": 16}
		var report: Dictionary = avatar.configure(race, {"customization": initial})
		assert(report.error == "", report.error)
		avatar.rotation.y = PI
		if avatar.animation_player != null:
			avatar.animation_player.pause()
		if avatar.face_player != null:
			avatar.face_player.pause()
		var head_index := avatar.skeleton.find_bone("head")
		var head := avatar.skeleton.get_bone_global_rest(head_index).origin
		var center_y: float = head.y + avatar.visual_root.position.y + 0.015
		camera.position = Vector3(0, center_y, 1.15)
		camera.look_at(Vector3(0, center_y, 0))
		var previous: Image
		for look in range(3 if race == "human_male" else 2):
			var values := initial.duplicate()
			if look >= 1:
				values.merge(cases[race], true)
			if look == 2:
				values["/private/index_age"] = 3
			for entry in avatar.materials:
				var material: ShaderMaterial
				if entry.material is ShaderMaterial:
					material = entry.material
				else:
					material = Materials.create(entry.source, avatar.catalog_directory)
					for mesh in avatar.meshes:
						for si in range(mesh.mesh.get_surface_count()):
							if mesh.mesh.surface_get_material(si) == entry.material:
								mesh.mesh.surface_set_material(si, material)
					entry.material = material
				Materials.apply(material, values)
			for i in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			var rendered := root.get_texture().get_image()
			rendered.save_png(directory.path_join("%s_%d.png" % [race, look]))
			if previous != null:
				var a := previous.get_data()
				var b := rendered.get_data()
				var changed := 0
				for i in range(mini(a.size(), b.size())):
					if absi(int(a[i]) - int(b[i])) > 8:
						changed += 1
				assert(changed > 100, race + " source facial customization produced no visible change")
				results.append({"race": race, "look": look, "changed_channels": changed, "source_layers": true})
			previous = rendered
	print("FACIAL_MATERIAL_PASS ", JSON.stringify(results))
	quit()
