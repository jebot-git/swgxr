extends SceneTree
const Spectator = preload("res://scripts/xr_spectator.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	var world := Node3D.new()
	root.add_child(world)
	var xr := SubViewport.new()
	xr.size = Vector2i(640,480)
	xr.world_3d = world.get_world_3d()
	xr.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(xr)
	var rig := XROrigin3D.new()
	xr.add_child(rig)
	var head := XRCamera3D.new()
	head.name="XRCamera3D"
	head.position=Vector3(0,1.7,0)
	head.cull_mask=1
	rig.add_child(head)
	head.make_current()
	var body := CharacterBody3D.new()
	body.name="PlayerBody"
	body.collision_mask=3
	rig.add_child(body)
	var mirror := Spectator.new()
	root.add_child(mirror)
	assert(mirror.configure(rig,body))
	mirror.set_process(false)
	mirror.set_physics_process(false)
	var pose := head.global_transform
	mirror.update_camera(1.0)
	assert(xr.get_camera_3d()==head and mirror.viewport.get_camera_3d()==mirror.camera)
	assert(not mirror.viewport.use_xr and mirror.viewport.world_3d==xr.world_3d)
	assert(mirror.camera.cull_mask==3 and head.cull_mask==1)
	for i in range(90): mirror.request_render(1.0/90)
	assert(mirror.render_requests==30)
	mirror.enabled=false
	mirror.request_render(1.0)
	assert(mirror.render_requests==30 and mirror.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED)
	mirror.enabled=true
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(5,5,.2)
	shape.shape=box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position=Vector3(0,1,1.4)
	for i in range(3): await physics_frame
	mirror.positioned=false
	mirror.update_camera(1.0)
	assert(mirror.collision_limited and mirror.camera.global_position.z < 1.2)
	assert(head.global_transform.is_equal_approx(pose) and head.current and rig.global_transform==Transform3D.IDENTITY)
	wall.queue_free()
	await process_frame
	if capture:
		var loader=load("res://scripts/stage_loader.gd").new()
		var stage=loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
		world.add_child(stage)
		rig.position=Vector3(-60,0.64,10)
		for name in ["LeftHand","RightHand"]:
			var hand:=XRController3D.new()
			hand.name=name
			rig.add_child(hand)
			var glove:=Node3D.new()
			glove.name="Hand"
			hand.add_child(glove)
		var tracked=load("res://scripts/tracked_avatar.gd").new()
		world.add_child(tracked)
		var avatar=load("res://scripts/avatar.gd").new()
		tracked.add_child(avatar)
		assert(avatar.configure("human_male",{"height":1.0,"profession":"crafting_artisan","customization":{}}).error=="")
		assert(tracked.configure(avatar,rig))
		tracked.set_process(false)
		tracked.update_tracking(1.0/60,head.global_transform,Transform3D(Basis.IDENTITY,rig.position+Vector3(-.28,1.2,-.3)),Transform3D(Basis.IDENTITY,rig.position+Vector3(.28,1.2,-.3)),.64)
		mirror.orbit_yaw=PI
		mirror.positioned=false
		for i in range(3): await physics_frame
		mirror.update_camera(1.0)
		mirror.request_render(1.0)
		await RenderingServer.frame_post_draw
		var path:=ProjectSettings.globalize_path("res://../runtime/evidence/xr-spectator.png")
		mirror.viewport.get_texture().get_image().save_png(path)
		print("SPECTATOR_CAPTURE "+path)
	var report={"test":"xr_independent_desktop_spectator","passed":true,"headset_pose_and_camera_unchanged":true,"full_avatar_layers":true,"shared_world_single_mono_view":true,"cap_30_requests_per_90_ticks":true,"disabled_no_renders":true,"wall_clearance":true,"resolution":str(mirror.viewport.size),"hardware_tested":false}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/xr-spectator-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	mirror.queue_free()
	world.queue_free()
	xr.queue_free()
	await process_frame
	quit()
