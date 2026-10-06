extends SceneTree
const Target=preload("res://pets/creature_targeting.gd")
class Host extends Node:
	var app:Node
	var vehicles:Node3D
class Vehicle extends Node3D:
	var head:Camera3D
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1100,760)
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("101d27");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("f4ead3");env.environment.ambient_light_energy=.9;world.add_child(env)
	var actor:=preload("res://combat/live_actor.gd").new();world.add_child(actor)
	var ok:bool=actor.configure({"id":"42","kind":"creature","template":"object/mobile/bantha_hue.iff","dead":false,"name":"Original bantha · mocked eligibility","health":100,"max_health":100,"scale":.45},"mock",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/combat_population/tatooine/catalog.json"))
	actor.rotation.y=PI+.5
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(1.2,1.45,3.1);camera.look_at(Vector3(0,.75,0));camera.current=true;camera.fov=62
	var anchor:Vector3=Target.head_anchor(actor)
	var marker:=MeshInstance3D.new();world.add_child(marker);marker.position=anchor
	var sphere:=SphereMesh.new();sphere.radius=.07;sphere.height=.14;marker.mesh=sphere
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("6beaf3");marker.material_override=material
	var host:=Host.new();world.add_child(host);host.app=host;host.vehicles=Vehicle.new();world.add_child(host.vehicles);host.vehicles.head=camera
	var handler:=preload("res://pets/creature_handler.gd").new();world.add_child(handler);handler.set_process(false);handler.set_physics_process(false);handler.setup(host);handler.selected={"id":"42","name":"Original bantha"};handler.progress=.76
	handler.show_progress({"progress":.76,"latched":false},"tame",{},false,{},true)
	var caption:=Label.new();root.add_child(caption);caption.position=Vector2(24,24);caption.text="CREATURE HANDLER · DESKTOP ASSET INSPECTION\nMocked eligibility/tracking · cyan marker: original animated head bone";caption.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));caption.add_theme_font_size_override("font_size",21)
	for i in range(6):await process_frame
	await RenderingServer.frame_post_draw
	var path:="res://../runtime/evidence/creature-handler-vulkan.png";var saved:=root.get_texture().get_image().save_png(path)==OK
	var report:Dictionary={"passed":ok and saved,"renderer":RenderingServer.get_current_rendering_method(),"tracking":"mocked","native_eligibility":"mocked","live_xr":false,"head_anchor":str(anchor),"source_template":"object/mobile/bantha_hue.iff"};FileAccess.open("res://../runtime/evidence/creature-handler-vulkan.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));world.free();caption.free();await process_frame;quit(0 if report.passed else 1)
