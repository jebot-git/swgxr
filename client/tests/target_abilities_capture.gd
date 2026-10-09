extends SceneTree
## Original avatar/gun assets; mocked combat state; desktop Forward+ Vulkan only.
const Fixture=preload("res://tests/target_abilities_smoke.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("08131b");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("b5dbe5");env.ambient_light_energy=.7;environment.environment=env;world.add_child(environment)
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-30,-35,0);light.light_energy=1.4
	var body:=CharacterBody3D.new();world.add_child(body)
	var head:=Camera3D.new();world.add_child(head);head.position=Vector3(0,1.1,0);head.fov=52;head.current=true
	var actor:=Fixture.Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-3.7);actor.rotation.y=PI;actor.collision_layer=8
	var avatar:=preload("res://scripts/avatar.gd").new();actor.add_child(avatar);actor.visual=avatar
	var report:Dictionary=avatar.configure("human_male",{"height":1.0})
	if not str(report.get("error","")).is_empty():push_error(str(report.error));quit(1);return
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=actor.visual_bounds().size;collision.shape=shape;collision.position=actor.visual_bounds().get_center();actor.add_child(collision)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.pistol_fwg5.duplicate(true);profile.item_id="99";profile.source_kind="core3_weapon_instance";profile.certified=true;profile.abilities=[]
	for id:String in ["concussion_shot_improved","lethal_shot","low_blow","restraining_shot","last_ditch"]:profile.abilities.append({"id":id,"activation":"native_ranged","base_sac":{"health":0,"action":10,"mind":10},"cooldown_seconds":30,"max_range_m":40,"conditions_met":true})
	profile.ability_loadout={"family":"pistols","slots":["concussion_shot_improved","lethal_shot","low_blow","restraining_shot"],"ultimate":"last_ditch","revision":1}
	var rig:=preload("res://combat/ranged_rig.gd").new();world.add_child(rig);rig.configure(head,body,[profile]);rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0)
	rig.abilities.apply_authoritative({"ham":[1000,1000,1000],"max_ham":[1000,1000,1000],"wounds":[0,0,0]})
	rig.weapons[0].visual.global_transform=Transform3D(Basis.looking_at(Vector3(-.25,.2,-3.7)),Vector3(.25,.9,-.5))
	var caption:=Label.new();root.add_child(caption);caption.position=Vector2(30,25);caption.text="LOCAL TARGET ABILITIES  /  MOCK STATE  /  DESKTOP VULKAN  /  XR OFF";caption.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));caption.add_theme_font_size_override("font_size",22)
	await physics_frame;await physics_frame
	rig.target_abilities.toggle(Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	for i in range(10):rig.target_abilities.refresh();await process_frame
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path("res://../runtime/evidence/target-abilities-vulkan.png")
	root.get_texture().get_image().save_png(path)
	print(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"mocked_state":true,"markers":rig.target_abilities.points.size(),"live_xr":false,"capture":path}))
	world.free();quit()
