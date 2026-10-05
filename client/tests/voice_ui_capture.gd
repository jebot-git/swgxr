extends SceneTree
const Avatar=preload("res://scripts/avatar.gd")
const Wrist=preload("res://scripts/xr_voice_controls.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,900);root.content_scale_size=Vector2i.ZERO
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("030b13")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=0.85
	environment.environment=settings;world.add_child(environment)
	var avatar:=Avatar.new();world.add_child(avatar);var result: Dictionary=avatar.configure("human_male")
	if not str(result.get("error","")).is_empty():quit(1);return
	avatar.set_tracking_mode(true)
	var solver:=SwgTrackedIK.new();solver.configure(avatar.skeleton)
	var targets: Dictionary={}
	for side in ["left","right"]:
		var prefix:="l" if side=="left" else "r"
		var wrist_rest: Transform3D=avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(prefix+"wrist"))
		var shoulder: Vector3=avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(prefix+"arm")).origin
		targets[side+"_hand"]=Transform3D(wrist_rest.basis,shoulder+Vector3(-0.12 if side=="left" else 0.12,-0.05,-0.55))
	solver.solve(targets,1.0/90)
	var camera:=Camera3D.new();camera.fov=47;camera.near=0.01;world.add_child(camera)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var wrist:=Wrist.new();world.add_child(wrist);wrist.configure(rig);wrist.avatar=avatar;wrist.set_process(false)
	var ham:=preload("res://combat/wrist_ham.gd").new();world.add_child(ham);ham.avatar=avatar;ham.hide()
	ham.pools=preload("res://combat/ability_state.gd").new()
	ham.pools.refresh_context({"character_id":"mock","complete":true,"ham":[750,1000,1000,650,1000,1000,900,1000,1000],"max_ham":[1000,1000,1000,1000,1000,1000,1000,1000,1000],"wounds":[100,0,0,50,0,0,0,0,0]})
	var state: Dictionary={"granted_channels":["proximity","planet"],"reasons":{"group":"Join a group to use group voice","faction":"Faction voice requires native membership"},"active_channel":"proximity","mic_mode":"muted","connected":true,"transmitting":false}
	wrist.apply_state(state);wrist.set_allowed(true);wrist.update_tracking(true,true,true)
	var label:=Label.new();label.position=Vector2(26,24);label.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));label.add_theme_font_size_override("font_size",22);root.add_child(label)
	var directory:=ProjectSettings.globalize_path("res://../runtime/evidence/voice")
	for side in ["left","right"]:
		wrist.show();ham.hide();wrist.set_offhand(side)
		var prefix:="l" if side=="left" else "r"
		var skeleton: Skeleton3D=avatar.skeleton
		var bone: Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(prefix+"wrist"))
		var index: Vector3=(skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(prefix+"index01"))).origin
		var ring: Vector3=(skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(prefix+"ring01"))).origin
		var fingers:=(index+ring)*0.5;var z:=(ring-index).normalized();var y:=(bone.origin-fingers).slide(z).normalized();var x:=y.cross(z).normalized();y=z.cross(x).normalized()
		var grip:=Transform3D(Basis(x,y,z),bone.origin.lerp(fingers,0.55))
		wrist.global_transform=wrist.underside_mount(grip)
		camera.global_position=wrist.global_position+wrist.global_basis.z*0.34+wrist.global_basis.x*0.035
		camera.look_at(wrist.global_position,Vector3.UP)
		for _frame in range(3):await process_frame
		wrist.pointer_frame({"pixel":wrist.panel.mode_buttons.vox.get_global_rect().get_center()},0)
		label.text="VOICE / "+side.to_upper()+" OFFHAND FOREARM / LENGTHWISE\nOriginal SWG avatar · simulated tracking · microphone off"
		for _frame in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/wrist-"+side+".png")
		wrist.hide();ham.side=side;ham.update_readout(grip,camera.global_position,true)
		label.text="HAM / "+side.to_upper()+" FOREARM / LENGTHWISE\nOriginal SWG avatar · mocked native HAM values · XR off"
		for _frame in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/ham-"+side+".png")
	var panel:=preload("res://scripts/voice_panel.gd").new();root.add_child(panel);panel.position=Vector2(320,290);panel.apply_state(state);panel.set_active(true)
	world.hide();label.text="VOICE / DESKTOP INSPECTION\nF12 · Controls    B · Push to talk\nMocked grants · no microphone or network"
	for _frame in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/desktop-controls.png")
	panel.queue_free();world.queue_free();label.queue_free()
	for _frame in range(4):await process_frame
	print(JSON.stringify({"passed":true,"renderer":"Forward+ Vulkan","xr":"off; simulated tracking","original_avatar":true,"microphone":false,"network":false}));quit()
