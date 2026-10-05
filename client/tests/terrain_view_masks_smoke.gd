extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	var stage = load("res://scripts/cell_stage.gd").new()
	var cells := {}
	for id in [1,2]:
		var height := -1.0 if id == 1 else 2.0
		cells[str(id)+":1"]={"building_object_id":id,"name":"test","bounds_min":[0,height,-16],"bounds_max":[16,height+2,0],"floor_vertices":[0,height,0,16,height,0,0,height,-16,16,height,-16],"floor_indices":[0,2,1,1,2,3]}
	stage.set_meta("manifest",{"cells":cells})
	root.add_child(stage)
	stage.current_building=0
	var stream=load("res://scripts/terrain_stream.gd").new()
	root.add_child(stream)
	stream.set_process(false)
	stream.set_cell_source(stage)
	stage.set_view_buildings([1])
	stream._refresh_interior_masks()
	assert(stream.interior_view_groups.size()==1,"Trailing interior spectator lost mask while player outside")
	stage.set_view_buildings([1,2])
	stream._refresh_interior_masks()
	var node:=MeshInstance3D.new()
	var material:=ShaderMaterial.new()
	material.shader=load("res://shaders/terrain.gdshader")
	node.material_override=material
	root.add_child(node)
	stream._apply_interior_mask(node,Vector2i.ZERO)
	assert(material.get_shader_parameter("volume_mask_building")==1 and material.get_shader_parameter("volume_mask_building2")==2)
	var first:Image=material.get_shader_parameter("interior_volume_mask").get_image()
	var second:Image=material.get_shader_parameter("interior_volume_mask2").get_image()
	var a:=first.get_pixel(24,24)
	var b:=second.get_pixel(24,24)
	assert(a.r<0 and a.g>0 and b.r>1.9 and b.g>3.9,"Different building volumes were merged")
	var gpu_proof := false
	if capture:
		var evaluator:=SwgTerrainEvaluator.new()
		assert(evaluator.configure({"fractals":[],"layers":[]}))
		var data:=evaluator.build_chunk(0,0,16,1)
		var weights:PackedColorArray=data.shader_weights
		for i in range(weights.size()):weights[i]=Color(1,0,0,0)
		data.shader_weights=weights
		node.mesh=SwgMeshBuilder.new().create_terrain_mesh(data,0)
		var albedo:=Image.create(1,1,false,Image.FORMAT_RGBA8);albedo.fill(Color.WHITE)
		var normal:=Image.create(1,1,false,Image.FORMAT_RGBA8);normal.fill(Color(.5,.5,1,1))
		var albedos:=Texture2DArray.new();albedos.create_from_images([albedo])
		var normals:=Texture2DArray.new();normals.create_from_images([normal])
		material.set_shader_parameter("terrain_albedo",albedos)
		material.set_shader_parameter("terrain_normal",normals)
		var environment:=WorldEnvironment.new()
		environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR
		environment.environment.background_color=Color(1,0,0)
		root.add_child(environment)
		var viewports:Array[SubViewport]=[]
		var cameras:Array[Camera3D]=[]
		for height in [.5,3.0]:
			var viewport:=SubViewport.new();viewport.size=Vector2i(320,240);viewport.world_3d=node.get_world_3d()
			root.add_child(viewport)
			var camera:=Camera3D.new();viewport.add_child(camera)
			camera.position=Vector3(6,height,-6);camera.look_at(Vector3(6,0,-7));camera.make_current()
			viewports.append(viewport);cameras.append(camera)
		RenderingServer.global_shader_parameter_set("swg_portal_view_a",Vector4(cameras[0].position.x,cameras[0].position.y,cameras[0].position.z,1))
		RenderingServer.global_shader_parameter_set("swg_portal_view_b",Vector4(cameras[1].position.x,cameras[1].position.y,cameras[1].position.z,2))
		for viewport in viewports:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var image_a:=viewports[0].get_texture().get_image()
		var image_b:=viewports[1].get_texture().get_image()
		image_a.save_png("res://../runtime/evidence/terrain-view-a.png")
		image_b.save_png("res://../runtime/evidence/terrain-view-b.png")
		var pixel_a:=image_a.get_pixel(160,120);var pixel_b:=image_b.get_pixel(160,120)
		assert(pixel_a.r>pixel_a.g+.4 and absf(pixel_b.r-pixel_b.g)<.15 and pixel_b.g>.3,"GPU applied another camera's terrain cutout "+str(pixel_a)+str(pixel_b))
		gpu_proof=true
		for viewport in viewports:viewport.queue_free()
		environment.queue_free()
	stage.set_view_buildings([])
	stream._refresh_interior_masks()
	stream._apply_interior_mask(node,Vector2i.ZERO)
	assert(not material.get_shader_parameter("volume_mask_enabled") and not material.get_shader_parameter("volume_mask_enabled2"))
	var report:Dictionary={"test":"independent_headset_spectator_terrain_masks","passed":true,"outside_player_inside_spectator_retains_mask":true,"two_buildings_separate_volumes":true,"both_views_outside_clears_masks":true,"gpu_per_view_selection":gpu_proof}
	print(JSON.stringify(report))
	FileAccess.open("res://../runtime/evidence/terrain-view-masks-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	node.queue_free();stream.queue_free();stage.queue_free()
	await process_frame
	quit()
