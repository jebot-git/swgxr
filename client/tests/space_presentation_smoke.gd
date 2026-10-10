extends SceneTree
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720)
	var world:=Node3D.new();root.add_child(world)
	var eye:=Camera3D.new();world.add_child(eye);eye.current=true;eye.far=20000
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color.BLACK;eye.environment=env
	var effects:=preload("res://space/hyperspace.gd").new();world.add_child(effects);effects.setup(eye)
	if not effects.available:failures.append("Original hyperspace assets unavailable")
	for phase:String in ["countdown","travel","arrival","idle"]:
		effects.observe({"phase":phase,"iteration":9 if phase=="travel" else 10},eye)
		await create_timer(2.1 if phase=="travel" else .8).timeout
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../runtime/evidence/ship-controls-20261010/hyperspace-"+phase+".png")
	if eye.transform!=Transform3D.IDENTITY:failures.append("Hyperspace moved camera")
	print(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"xr":false,"renderer":RenderingServer.get_current_rendering_method(),"original_assets":effects.available}));quit(0 if failures.is_empty() else 1)
