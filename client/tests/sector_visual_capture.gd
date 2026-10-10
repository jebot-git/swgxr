extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720)
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true;camera.far=20000;camera.fov=95
	var env:=Environment.new();env.background_mode=Environment.BG_SKY
	camera.environment=env
	var directory:="res://../runtime/evidence/jtl-sectors-20261010"
	for zone in ["space_corellia","space_dantooine","space_dathomir","space_endor","space_lok","space_naboo","space_tatooine","space_yavin4","space_light1","space_heavy1"]:
		var sector:=preload("res://space/sector_scene.gd").new();world.add_child(sector)
		if not sector.build("res://../runtime/assets/jtl/"+zone+".json"):push_error(sector.error);quit(1);return
		sector.observe(Transform3D.IDENTITY)
		var sky:=Sky.new();sky.sky_material=sector.sky;env.sky=sky
		var p:Array=sector.data.environment.planets[0].position if not sector.data.environment.planets.is_empty() else [0,0,-1]
		camera.look_at(Vector3(p[0],p[1],p[2]),Vector3.FORWARD if absf(Vector3(p[0],p[1],p[2]).normalized().y)>.99 else Vector3.UP)
		for i in range(12):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(zone+".png"))
		print(JSON.stringify({"zone":zone,"renderer":"Forward+ Vulkan","xr":"off","children":sector.get_child_count()}))
		sector.free()
	quit()
