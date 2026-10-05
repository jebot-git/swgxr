extends SceneTree
const Avatar = preload("res://scripts/avatar.gd")
const Tracked = preload("res://scripts/tracked_avatar.gd")
const Combat = preload("res://combat/ranged_rig.gd")
var failures: Array[String]=[]
var checks:=0
var maximum_grip_error:=0.0
var maximum_segment_error:=0.0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)
func verify(tracked, combat, label: String) -> void:
	var skeleton:Skeleton3D=tracked.skeleton
	if combat.selected>=0:
		var visual:Node3D=combat.weapons[combat.selected].visual
		check(visual.global_basis.get_scale().is_equal_approx(Vector3.ONE),label+" source weapon dimensions preserved")
	for side in ["left","right"]:
		var prefix: String="l" if side=="left" else "r"
		for names in [["arm","forearm"],["forearm","wrist"]]:
			var a:=skeleton.find_bone(prefix+names[0]); var b:=skeleton.find_bone(prefix+names[1])
			var expected:=skeleton.get_bone_global_rest(a).origin.distance_to(skeleton.get_bone_global_rest(b).origin)
			var actual:=skeleton.get_bone_global_pose(a).origin.distance_to(skeleton.get_bone_global_pose(b).origin)
			maximum_segment_error=maxf(maximum_segment_error,absf(actual-expected))
			check(absf(actual-expected)<0.0001,label+" rigid "+prefix+names[1])
			check(skeleton.get_bone_pose_position(b).is_equal_approx(skeleton.get_bone_rest(b).origin) and skeleton.get_bone_pose_scale(b).is_equal_approx(Vector3.ONE),label+" unchanged bone translation/scale")
		var target:Variant=combat.hand_target(side)
		if target is Transform3D:
			var hold:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("hold_l" if side=="left" else "hold_r"))
			var error:float=hold.origin.distance_to(target.origin)
			maximum_grip_error=maxf(maximum_grip_error,error)
			check(error<0.001,label+" weapon attached to "+side+" hand, error "+str(error))
			check(hold.basis.orthonormalized().is_equal_approx(target.basis.orthonormalized()),label+" source palm orientation")
func run() -> void:
	create_timer(75).timeout.connect(func(): quit(2))
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/combat/catalog.json"))
	var origin:XROrigin3D=load("res://xr/player_rig.tscn").instantiate(); root.add_child(origin)
	var body=origin.get_node("PlayerBody"); body.set_physics_process(false)
	var camera:XRCamera3D=origin.get_node("XRCamera3D"); camera.position=Vector3(0,1.7,0)
	var camera_start:=camera.transform; var body_start:Transform3D=body.transform
	for race in ["human_male","ithorian_male","wookiee_male"]:
		var tracked:=Tracked.new(); root.add_child(tracked)
		var avatar:=Avatar.new(); tracked.add_child(avatar)
		check(avatar.configure(race,{"profession":"crafting_artisan"}).error=="" and tracked.configure(avatar,origin),"Configure "+race)
		tracked.set_process(false); tracked.set_standing_eye_height(1.7)
		var combat:=Combat.new(); root.add_child(combat)
		var profiles:Array=[catalog.weapons.pistol_cdef,catalog.weapons.rifle_e11]
		for profile in catalog.weapons.values():
			if profile.get("kind","")=="melee": profiles.append(profile)
		check(combat.configure(camera,body,profiles,"right",origin),"Weapons "+race)
		combat.set_process(false); combat.set_physics_process(false); combat.set_allowed(true)
		combat.configure_unarmed(catalog.unarmed)
		combat.tracked_avatar=tracked; tracked.combat_rig=combat
		for fit_height in [0.8,1.7,2.5]:
			tracked.set_standing_eye_height(fit_height)
			for side in ["left","right"]:
				combat.dominant=side
				for height in [1.7,1.0,0.5]:
					var head:=Transform3D(Basis.IDENTITY,Vector3(0,height,0))
					for index in range(profiles.size()):
						combat.draw(index)
						for support in [false,true]:
							combat.two_hands=support
							for point in [Vector3(0.25,1.3,-0.4),Vector3(2,1.3,-2),Vector3(-2,1.4,1),Vector3(0,4,0)]:
								var main:=Transform3D(Basis.IDENTITY,point)
								var off:=Transform3D(Basis.IDENTITY,point+Vector3(0,-0.015,-0.25))
								for frame in range(3):
									combat.pose_weapon(main,off)
									tracked.update_tracking(1.0/90,head,combat.hand_target("left"),combat.hand_target("right"),0,{"grounded":false})
								tracked.update_fingers()
								verify(tracked,combat,race+" "+side+" "+str(height)+" "+str(index)+" "+str(support)+" "+str(point))
		# Empty hands use the same bounded arm solver even when combat ready.
		tracked.set_standing_eye_height(1.7)
		combat.stow()
		for side in ["left","right"]: combat.unarmed[side].sample_swing(0.01,true,false,"standing",Vector3.ZERO,true)
		tracked.update_tracking(1.0/90,Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Transform3D(Basis.IDENTITY,Vector3(-3,3,-3)),Transform3D(Basis.IDENTITY,Vector3(3,3,-3)),0,{"grounded":false})
		verify(tracked,combat,race+" fists beyond reach")
		check(camera.transform==camera_start and body.transform==body_start,"Arm limit never changes tracked head or physics body")
		if race=="human_male" and "--capture" in OS.get_cmdline_user_args():
			combat.dominant="right"; combat.draw(1); combat.two_hands=true
			for frame in range(3):
				combat.pose_weapon(Transform3D(Basis.IDENTITY,Vector3(0.25,1.3,-3)),Transform3D(Basis.IDENTITY,Vector3(0.25,1.3,-3.25)))
				tracked.update_tracking(1.0/90,Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),combat.hand_target("left"),combat.hand_target("right"),0,{"grounded":false})
			tracked.update_fingers()
			# The sweep loads many weapons at the same two sockets. The evidence
			# frame shows only the held rifle rather than overlapping test fixtures.
			for index in range(combat.weapons.size()): combat.weapons[index].visual.visible=index==combat.selected
			var environment:=WorldEnvironment.new(); var settings:=Environment.new()
			settings.background_mode=Environment.BG_COLOR; settings.background_color=Color(0.08,0.1,0.13)
			settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color.WHITE; settings.ambient_light_energy=0.8
			environment.environment=settings; root.add_child(environment)
			var light:=DirectionalLight3D.new(); root.add_child(light); light.rotation_degrees=Vector3(-35,-25,0)
			var view:=Camera3D.new(); root.add_child(view); view.position=Vector3(1.6,1.6,-2.6); view.look_at(Vector3(0,1.1,-0.35)); view.fov=55; view.make_current()
			for frame in range(4): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../runtime/evidence/weapon-arm-limit.png")
			view.queue_free(); environment.queue_free(); light.queue_free()
		combat.free(); tracked.free()
	origin.queue_free(); await process_frame
	var report:Dictionary={"test":"weapon_arm_limits","checks":checks,"passed":failures.is_empty(),"errors":failures,"maximum_grip_error_m":maximum_grip_error,"maximum_segment_error_m":maximum_segment_error,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/weapon-arm-limits.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
