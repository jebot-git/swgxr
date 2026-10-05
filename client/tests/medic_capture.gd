extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,2,5);camera.look_at(Vector3(0,0.8,0));camera.current=true
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("1c2631");settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=0.8;environment.environment=settings;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);world.add_child(light)
	var ground:=StaticBody3D.new();ground.collision_layer=2;world.add_child(ground)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(20,0.1,20);collision.shape=shape;collision.position.y=-0.05;ground.add_child(collision)
	var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(20,20);floor_mesh.mesh=plane;ground.add_child(floor_mesh)
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("6d6251");floor_mesh.material_override=mat
	var avatar=preload("res://scripts/avatar.gd").new();world.add_child(avatar);avatar.configure("human_male",{"profession":"science_medic"})
	var circle=preload("res://medic/range_circle.gd").new();world.add_child(circle)
	var effect=preload("res://combat/vital_feedback.gd").new();effect.configure(camera)
	var caption:=Label.new();caption.position=Vector2(22,18);caption.text="Medical range and recipient feedback · desktop Vulkan · illustrative 3m radius";world.add_child(caption)
	await physics_frame;await physics_frame;circle.update_circle(Vector3.ZERO,3,true,0.2)
	for mode in ["neutral","heal","damage"]:
		effect.reset();effect.initialized=true
		if mode!="neutral":effect.observe({"damage":1 if mode=="damage" else 0,"heal":1 if mode=="heal" else 0,"age_seconds":0});effect.advance(0.1);effect.advance(0.04)
		caption.text="Medical range and recipient feedback · desktop Vulkan · "+mode
		for i in range(4):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/medic-"+mode+"-vulkan.png")
	print(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"circle_visible":circle.visible,"live_headset_validated":false}));world.free();quit()
