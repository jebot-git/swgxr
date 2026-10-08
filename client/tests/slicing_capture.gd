extends SceneTree
## Desktop Forward+ Vulkan evidence with explicitly mocked challenges and outcomes.
const Board=preload("res://slicing/board.gd")
const View=preload("res://slicing/grid_view.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,960);root.content_scale_size=Vector2i(1280,960)
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(.92,1.72,1.12);camera.look_at(Vector3(0,1.26,0));camera.fov=48;camera.current=true
	var env:=WorldEnvironment.new();world.add_child(env);env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("030b13");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8
	var label:=Label.new();root.add_child(label);label.position=Vector2(25,20);label.text="SPATIAL SLICING · MOCK CHALLENGE · DESKTOP VULKAN FORWARD+ · XR DISABLED";label.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));label.add_theme_font_size_override("font_size",20)
	var board:=Board.new();var challenge:Dictionary={"size":5,"pairs":[
		{"color":0,"ends":[{"cell":[0,0,0],"face":[-1,0,0]},{"cell":[4,4,0],"face":[1,0,0]}]},
		{"color":1,"ends":[{"cell":[0,0,2],"face":[-1,0,0]},{"cell":[4,0,2],"face":[1,0,0]}]},
		{"color":2,"ends":[{"cell":[2,2,0],"face":[0,0,-1]},{"cell":[2,2,4],"face":[0,0,1]}]},
		{"color":3,"ends":[{"cell":[0,4,4],"face":[-1,0,0]},{"cell":[4,4,4],"face":[1,0,0]}]}],"preconnected":[
		{"color":0,"cells":[[0,0,0],[0,1,0],[0,2,0],[0,3,0],[1,3,0],[2,3,0],[3,3,0],[4,3,0],[4,4,0]]},
		{"color":1,"cells":[[0,0,2],[1,0,2],[2,0,2],[3,0,2],[4,0,2]]}]}
	if not board.configure(challenge):push_error(board.error);quit(1);return
	board.touch({"color":2,"end":0});board.extend([2,2,1]);board.extend([2,2,2]);board.extend([2,2,3])
	var grid:=View.new();world.add_child(grid);grid.position=Vector3(0,1.25,0);grid.configure(board);grid.set_status("SLICING · 2 / 4 PIPES · 142s")
	var assets:=preload("res://scripts/inventory_assets.gd").new();assets.configure()
	var target:=assets.instance("object/weapon/ranged/pistol/pistol_cdef.iff",.27)
	if target!=null:world.add_child(target);target.position+=Vector3(0,.78,0);target.rotation=Vector3(.1,.5,0)
	var item_caption:=Label3D.new();world.add_child(item_caption);item_caption.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");item_caption.text="CRAFTED WEAPON · RESERVED IN INVENTORY";item_caption.position=Vector3(0,.61,0);item_caption.font_size=24;item_caption.pixel_size=.001;item_caption.modulate=Color("c9fbff");item_caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	var knife:=assets.instance("object/tangible/slicing/slicing_laser_knife.iff",.22)
	if knife!=null:
		world.add_child(knife);knife.rotation=Vector3(0,PI,0);knife.position=grid.to_global(board.center([2,2,3]))+Vector3(0,0,.14)
	grid.show_cursor(board.center([2,2,3]),true)
	var instruction:=Label.new();root.add_child(instruction);instruction.position=Vector2(25,900);instruction.text="Touch matching ends. Detach by touching a connected end. Occupied cubes block the wire.";instruction.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));instruction.add_theme_font_size_override("font_size",20)
	await capture("slicing-grid-vulkan.png")
	board.configure(preload("res://tests/slicing_board_smoke.gd").fixture(3,2));grid.configure(board);grid.set_status("SLICING · 0 / 2 PIPES · 180s");grid.show_cursor(Vector3.ZERO,false)
	if knife!=null:knife.hide()
	await capture("slicing-grid-small-vulkan.png")
	print(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"mock_challenge":true,"original_tool_and_item":target!=null and knife!=null,"headset_validated":false}))
	world.free();label.free();instruction.free();quit()
func capture(filename:String)->void:
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/"+filename))!=OK:push_error("Unable to capture "+filename);quit(1)
