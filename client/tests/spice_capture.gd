extends SceneTree
## Desktop Vulkan evidence only: mocked spice phases, original SWG actor meshes.
const State=preload("res://spice/state.gd")
const Screen=preload("res://spice/screen_effect.gd")
const Actor=preload("res://combat/live_actor.gd")
const World=preload("res://spice/world_effects.gd")
var camera:Camera3D
var effect:CompositorEffect
var world:Node3D
var caption:Label
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,960);world=Node3D.new();root.add_child(world)
	camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,1.6,4);camera.look_at(Vector3(0,1,0));camera.fov=48;camera.current=true
	var environment:=WorldEnvironment.new();world.add_child(environment);environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("244654");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.9
	var floor_mesh:=MeshInstance3D.new();floor_mesh.mesh=BoxMesh.new();floor_mesh.mesh.size=Vector3(6,.1,5);world.add_child(floor_mesh);floor_mesh.position.y=-.06
	var floor_material:=StandardMaterial3D.new();floor_material.albedo_color=Color("a99073");floor_mesh.material_override=floor_material
	var assets:=preload("res://scripts/inventory_assets.gd").new();assets.configure();var dead:=preload("res://scripts/inventory_assets.gd").new();dead.configure("res://../runtime/assets/corpses/catalog.json")
	var actors:Array=[]
	for index in range(2):
		var actor:=Actor.new();world.add_child(actor)
		var row:={"id":str(100+index),"name":"Aggressive henchman" if index==0 else "Neutral bystander","kind":"creature","template":"object/mobile/dressed_tatooine_valarian_henchman.iff","dead":false,"health":100,"max_health":100,"scale":1.0,"aggressive":index==0,"relation":"hostile" if index==0 else "neutral"}
		if not actor.configure(row,"mocked_capture",assets,dead,"res://../runtime/assets/combat_population/native_current/catalog.json"):push_error("Missing original NPC appearance");quit(1);return
		actor.position=Vector3(-.75 if index==0 else .75,0,0);actor.set_process(false);actors.append(actor)
	var wall:=MeshInstance3D.new();wall.mesh=BoxMesh.new();wall.mesh.size=Vector3(1.25,2.3,.12);world.add_child(wall);wall.position=Vector3(-.75,1.1,.4)
	var wall_material:=StandardMaterial3D.new();wall_material.albedo_color=Color("59636d");wall.material_override=wall_material
	var overlay:=World.new();world.add_child(overlay);overlay.set_process(false);overlay.outline_material=ShaderMaterial.new();overlay.outline_material.shader=preload("res://spice/outline.gdshader");overlay.hostile_material=ShaderMaterial.new();overlay.hostile_material.shader=preload("res://spice/hostile_illusion.gdshader")
	effect=Screen.new();effect.attach(camera)
	caption=Label.new();root.add_child(caption);caption.position=Vector2(20,20);caption.add_theme_font_size_override("font_size",21)
	var state:=State.new()
	for scenario in [{"name":"baseline","id":"","phase":"active","time":0.0},{"name":"giggledust-outline","id":"giggledust","phase":"active","time":1.0},{"name":"booster-monochrome","id":"booster_blue","phase":"active","time":1.0},{"name":"giggledust-withdrawal","id":"giggledust","phase":"withdrawal","time":8.0},{"name":"neutron-blue","id":"neutron_pixey","phase":"withdrawal","time":1.0},{"name":"sedative-noise","id":"sedative_h4b","phase":"active","time":1.0},{"name":"gunjack-dark","id":"gunjack","phase":"withdrawal","time":15.0},{"name":"pyrepenol-hostility","id":"pyrepenol","phase":"withdrawal","time":1.0}]:
		state.reset();state.observe(preload("res://tests/spice_smoke.gd").envelope(scenario.id,scenario.phase,180,scenario.time));var policy:Dictionary=state.policy()
		effect.set_policy(policy);overlay.refresh(actors,[],Vector3.ZERO,policy);overlay.copy_transforms()
		caption.text="SPICE · "+str(scenario.name).to_upper()+"\nMOCKED PHASE · ORIGINAL ACTORS · DESKTOP VULKAN · XR DISABLED"
		for frame in range(6):await process_frame
		await RenderingServer.frame_post_draw
		var path:=ProjectSettings.globalize_path("res://../runtime/evidence/spice-"+scenario.name+"-vulkan.png")
		if root.get_texture().get_image().save_png(path)!=OK:push_error("Capture failed");quit(1);return
	print(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"shader_compiled":effect.pipeline.is_valid(),"shader_failed":effect.failed,"original_actor_meshes":true,"phase":"mocked","headset_validated":false}))
	world.free();caption.free();await process_frame;quit(1 if effect.failed else 0)
