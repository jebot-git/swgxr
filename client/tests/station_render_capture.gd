extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720);root.msaa_3d=Viewport.MSAA_4X
	var world:=Node3D.new();root.add_child(world)
	var sector:=preload("res://space/sector_scene.gd").new();world.add_child(sector)
	assert(sector.build("res://../runtime/assets/jtl/space_tatooine.json"))
	var p:Vector3=sector.loader.vec(sector.data.instances[0].position)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true;camera.far=30000;camera.near=.1
	var environment:=Environment.new();environment.background_mode=Environment.BG_SKY
	var sky:=Sky.new();sky.sky_material=sector.sky;environment.sky=sky;camera.environment=environment
	sector.observe(Transform3D.IDENTITY)
	var textures:=0;var mipmapped:=0
	for texture:Texture2D in sector.loader.textures.values():
		textures+=1
		if texture.get_image().has_mipmaps():mipmapped+=1
	for i in range(3):
		camera.position=p+Vector3(250+i*25,150,600);camera.look_at(p)
		for frame in range(8):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/mission-combat-20261010/station-%d.png"%i)
	var result:Dictionary={"textures":textures,"mipmapped":mipmapped,"passed":textures>0 and textures==mipmapped,"renderer":"Forward+ Vulkan","xr":false}
	FileAccess.open("res://../runtime/evidence/mission-combat-20261010/station-render.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result));quit(0 if result.passed else 1)
