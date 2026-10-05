extends SceneTree
## Desktop Vulkan inspection of original tool/corpse assets on authored starport floor.
const Loader=preload("res://scripts/stage_loader.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
const Tools=preload("res://scripts/deployed_resource_tools.gd")
const Corpses=preload("res://scripts/corpse_visuals.gd")
func _initialize() -> void: call_deferred("run")
func point(vertices: Array,index: int) -> Vector3: return Vector3(vertices[index*3],vertices[index*3+1],vertices[index*3+2])
func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Requires desktop Forward+ Vulkan"); quit(2); return
	root.size=Vector2i(1100,800)
	var loader:=Loader.new(); var stage:=loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	if stage==null: push_error(loader.report.error); quit(2); return
	root.add_child(stage); stage.set_physics_process(false)
	var camera:=Camera3D.new(); root.add_child(camera); camera.make_current(); camera.fov=58
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("6d737b")
	root.add_child(environment)
	var assets:=Assets.new(); assets.configure()
	var tools:=Tools.new(); root.add_child(tools); tools.configure(assets); tools.set_context(stage,camera); tools.set_physics_process(false)
	await physics_frame; await physics_frame
	var scene: Dictionary=stage.get_meta("manifest"); var center:=Vector3.ZERO; var largest:=0.0; var floor_id:=""
	for id: String in scene.cells:
		if id!="1106368:0": continue
		var cell: Dictionary=scene.cells[id]; var vertices: Array=cell.floor_vertices
		for triangle: Dictionary in cell.floor_triangles:
			if bool(triangle.get("fallthrough",false)) or float(triangle.normal[1])<0.999: continue
			var a:=point(vertices,int(triangle.indices[0])); var b:=point(vertices,int(triangle.indices[1])); var c:=point(vertices,int(triangle.indices[2])); var p:=(a+b+c)/3.0
			camera.position=p+Vector3.UP
			var placement:=tools.ground_placement(Transform3D(Basis.IDENTITY,p+Vector3.UP*0.4))
			var area:=(b-a).cross(c-a).length()
			if placement.get("valid",false) and area>largest: largest=area; center=placement.position; floor_id=id
	if floor_id.is_empty(): push_error("Actual exterior floor unavailable"); quit(2); return
	camera.position=center+Vector3(1.65,1.75,2.6); camera.look_at(center+Vector3(0,0.78,0))
	tools.set_states([{"id":"capture:1","tool_id":"capture","template":"object/tangible/survey_tool/survey_tool_mineral.iff","world_position":center,"state":"sampling","resource_name":"Original mineral tool · reference preview","buffer":[{"quantity":12}]}]); tools.sync_visuals()
	var corpses:=Corpses.new(); root.add_child(corpses); corpses.configure(); corpses.set_context(stage,camera); corpses.set_physics_process(false)
	corpses.set_states([{"id":"capture_corpse","template":"object/mobile/worrt_hue.iff","world_position":center+Vector3(0.6,0,0),"dead":true,"scale":1.0,"heading_radians":0.2,"customization":{"/private/index_color_1":3}}]); corpses.sync_visuals()
	for i in range(12): await process_frame
	await RenderingServer.frame_post_draw
	var path:="res://../runtime/evidence/gathering-world-vulkan.png"
	var image:=root.get_texture().get_image(); image.save_png(path)
	var cyan:=0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color:=image.get_pixel(x,y)
			if color.g>0.35 and color.b>0.35 and color.r<color.g*0.7: cyan+=1
	var result:={"ok":tools.visuals.size()==1 and corpses.visuals.size()==1 and cyan>80,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"headset_tested":false,"authority":"Reference capture using original model assets; synthetic counts/IDs are not a backend validation","source_floor":floor_id,"sampling_position":[center.x,center.y,center.z],"cyan_pixels":cyan,"image":path}
	FileAccess.open("res://../runtime/evidence/gathering-world-vulkan.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result)); tools.queue_free(); corpses.queue_free(); stage.queue_free(); camera.queue_free(); environment.queue_free(); await process_frame; quit(0 if result.ok else 1)
