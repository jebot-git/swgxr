extends SceneTree
## Camera is fixed at original avatar eyes, looking toward the raised hands.
## Only native IK wrist orientation changes between the hidden/revealed views.
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,900)
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("030b13");settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.85;environment.environment=settings;world.add_child(environment)
	var avatar:=preload("res://scripts/avatar.gd").new();world.add_child(avatar);avatar.configure("human_male");avatar.set_tracking_mode(true)
	var skeleton: Skeleton3D=avatar.skeleton
	var solver:=SwgTrackedIK.new();solver.configure(skeleton)
	var camera:=Camera3D.new();camera.near=.01;camera.fov=65;camera.cull_mask=1;world.add_child(camera)
	var eye:=skeleton.get_bone_global_rest(skeleton.find_bone("head")).origin+Vector3(0,.075,-.09)
	camera.global_position=skeleton.global_transform*eye
	camera.look_at(camera.global_position+Vector3(0,-.38,-.42),Vector3.UP)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var voice:=preload("res://scripts/xr_voice_controls.gd").new();world.add_child(voice);voice.configure(rig);voice.avatar=avatar;voice.set_process(false)
	voice.apply_state({"granted_channels":["proximity","planet"],"active_channel":"proximity","mic_mode":"muted","connected":true});voice.set_allowed(true);voice.update_tracking(true,true,true)
	var ham:=preload("res://combat/wrist_ham.gd").new();world.add_child(ham);ham.avatar=avatar;ham.pools=preload("res://combat/ability_state.gd").new()
	ham.pools.refresh_context({"character_id":"mock","complete":true,"ham":[750,1000,1000,650,1000,1000,900,1000,1000],"max_ham":[1000,1000,1000,1000,1000,1000,1000,1000,1000],"wounds":[100,0,0,50,0,0,0,0,0]})
	var label:=Label.new();label.position=Vector2(24,24);label.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));label.add_theme_font_size_override("font_size",22);root.add_child(label)
	var directory:=ProjectSettings.globalize_path("res://../runtime/evidence/forearm-roll");DirAccess.make_dir_recursive_absolute(directory)
	for side in ["left","right"]:
		voice.set_offhand(side)
		var prefix:="l" if side=="left" else "r"
		var target:=skeleton.get_bone_global_rest(skeleton.find_bone(prefix+"wrist"))
		target.origin=eye+Vector3(-.15 if side=="left" else .15,-.38,-.42)
		solver.solve({side+"_hand":target},1.0/90)
		var wrist_position:=skeleton.get_bone_global_pose(skeleton.find_bone(prefix+"wrist")).origin
		var forearm_position:=skeleton.get_bone_global_pose(skeleton.find_bone(prefix+"forearm")).origin
		var rest_wrist:=skeleton.get_bone_global_rest(skeleton.find_bone(prefix+"wrist"))
		var rest_finger:=skeleton.get_bone_global_rest(skeleton.find_bone(prefix+"index01")).origin
		target.basis=Basis(Quaternion((rest_finger-rest_wrist.origin).normalized(),(wrist_position-forearm_position).normalized()))*rest_wrist.basis
		solver.solve({side+"_hand":target},1.0/90)
		var frame: Transform3D=voice.underside_mount(Transform3D.IDENTITY)
		var axis:=skeleton.global_basis.inverse()*frame.basis.x
		for degrees in [0,90,180,270]:
			var rolled:=target;rolled.basis=Basis(axis,deg_to_rad(degrees))*target.basis
			solver.solve({side+"_hand":rolled},1.0/90)
			voice.global_transform=voice.underside_mount(Transform3D.IDENTITY);voice.show();ham.hide()
			label.text="FIXED WEARER VIEW / %s ARM / TRACKED ROLL %d°\nOriginal skeleton + native IK · desktop Vulkan · no headset"%[side.to_upper(),degrees]
			for i in range(4):await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/%s-%d.png"%[side,degrees])
			if degrees==90 or degrees==270:
				voice.hide();ham.side=side;ham.update_readout(Transform3D.IDENTITY,camera.global_position,true)
				label.text="FIXED WEARER VIEW / %s HAM / TRACKED ROLL %d°\nOriginal skeleton + native IK · desktop Vulkan · no headset"%[side.to_upper(),degrees]
				for i in range(4):await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory+"/ham-%s-%d.png"%[side,degrees])
	world.queue_free();label.queue_free()
	for i in range(3):await process_frame
	print("Fixed original-eye viewpoint roll captures complete; no live XR.");quit()
