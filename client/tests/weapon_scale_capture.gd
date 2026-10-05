extends SceneTree
## Original staff at two calibrated avatar heights, through the same mono camera.
## Desktop Vulkan evidence only; no headset tracking is simulated as live evidence.
const Avatar=preload("res://scripts/avatar.gd")
const Tracked=preload("res://scripts/tracked_avatar.gd")
const Combat=preload("res://combat/ranged_rig.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var origin:XROrigin3D=load("res://xr/player_rig.tscn").instantiate(); root.add_child(origin)
	var body=origin.get_node("PlayerBody"); body.set_physics_process(false)
	var head:XRCamera3D=origin.get_node("XRCamera3D")
	var tracked:=Tracked.new(); root.add_child(tracked)
	var avatar:=Avatar.new(); tracked.add_child(avatar)
	assert(avatar.configure("human_male",{"height":1.0,"profession":"combat_brawler"}).error=="")
	assert(tracked.configure(avatar,origin)); tracked.set_process(false)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/combat/catalog.json"))
	var combat:=Combat.new(); root.add_child(combat)
	assert(combat.configure(head,body,[catalog.weapons.knife_stone,catalog.weapons.lance_staff_wood_s1],"right",origin))
	combat.set_process(false); combat.set_physics_process(false); combat.set_allowed(true)
	combat.tracked_avatar=tracked; tracked.combat_rig=combat
	var environment:=WorldEnvironment.new(); var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR; settings.background_color=Color(0.08,0.1,0.13)
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color.WHITE; settings.ambient_light_energy=0.8
	environment.environment=settings; root.add_child(environment)
	var light:=DirectionalLight3D.new(); root.add_child(light); light.rotation_degrees=Vector3(-35,-25,0)
	var view:=Camera3D.new(); root.add_child(view); view.position=Vector3(0,1.45,3.2)
	view.look_at(Vector3(0,1,0)); view.fov=55; view.make_current()
	var title:=Label.new(); root.add_child(title); title.position=Vector2(24,24); title.add_theme_font_size_override("font_size",22)
	var examples:Array=[]
	for eye_height in [1.2,1.7]:
		head.position=Vector3(0,eye_height,0); tracked.set_standing_eye_height(eye_height)
		for frame in range(4):
			tracked.update_tracking(1.0/90,head.global_transform,Transform3D(Basis.IDENTITY,Vector3(-0.22,eye_height-0.45,-0.3)),Transform3D(Basis.IDENTITY,Vector3(0.22,eye_height-0.45,-0.3)),0,{"grounded":false})
		combat.update_visuals()
		var visual:Node3D=combat.weapons[1].visual
		var bounds:AABB=combat.weapons[1].bounds
		var length_m:float=(visual.global_basis*Vector3(0,bounds.size.y,0)).length()
		assert(absf(length_m-2.3)<0.00001 and visual.global_basis.get_scale().is_equal_approx(Vector3.ONE))
		title.text="Original wooden staff: %.2f m  |  Calibrated eye height: %.2f m\nFixed camera, original stow pose, no weapon scaling" % [length_m,eye_height]
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var path:="res://../runtime/evidence/weapon-scale-%.1f.png" % eye_height
		assert(root.get_texture().get_image().save_png(path)==OK)
		examples.append({"eye_height_m":eye_height,"avatar_fit_scale":tracked.fit_scale,"staff_length_m":length_m,"capture":path})
	var report:={"test":"original_weapon_scale_capture","passed":true,"examples":examples,"hardware_tested":false,"renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open("res://../runtime/evidence/weapon-scale.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	combat.free(); tracked.free(); origin.queue_free(); await process_frame; quit()
