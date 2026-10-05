extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host:=preload("res://tests/crafting_smoke.gd").Host.new();root.add_child(host)
	var rig:=XROrigin3D.new();host.add_child(rig)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";rig.add_child(camera);camera.position=Vector3(0,0.11,0.8);camera.current=true
	for name in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=name;rig.add_child(hand)
	host.player=preload("res://tests/crafting_smoke.gd").Player.new();rig.add_child(host.player)
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("08121b");environment.environment=settings;host.add_child(environment)
	var bag:=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);bag.configure(rig,host.player);bag.set_process(false)
	var craft:=preload("res://scripts/crafting_controller.gd").new();host.add_child(craft);craft.setup(host,bag);craft.set_process(false)
	craft.state=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/artisan-selected.json")).state
	for slot in craft.state.schematic.slots:craft.allocations.append([])
	craft.set_visible_ui(true);craft.rebuild();craft.select_resource(0)
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../runtime/evidence/artisan-assembly-vulkan.png")
	craft.state=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/artisan-assembled.json")).state;craft.rebuild()
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../runtime/evidence/artisan-experiment-vulkan.png")
	host.free()
	await process_frame
	await process_frame
	quit()
