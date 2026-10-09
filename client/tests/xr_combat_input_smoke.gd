extends SceneTree
## Actual XRController3D action/pose reads with mocked runtime-neutral trackers.
const Rig = preload("res://combat/ranged_rig.gd")
class ScoutBadge extends Node3D:
	func mask_entry()->Dictionary:return {"id":"mask_scent","label":"Mask Scent","source_command":"maskscent"}
	func dna_entry()->Dictionary:return {}
var checks := 0
var errors: Array[String] = []
var trackers: Array[XRPositionalTracker] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func controller(side: String) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = side+"_hand"
	tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	tracker.set_input("grip",0.0); tracker.set_input("trigger",0.0); tracker.set_input("by_button",false)
	tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	trackers.append(tracker)
	return tracker
func pose(tracker: XRPositionalTracker, transform: Transform3D) -> void:
	tracker.set_pose("grip",transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_pose("aim",transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
func run() -> void:
	create_timer(20).timeout.connect(func(): push_error("XR combat input timeout"); quit(2))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/combat/catalog.json")))
	var origin: XROrigin3D = load("res://xr/player_rig.tscn").instantiate()
	var head_tracker := XRPositionalTracker.new()
	head_tracker.name = "head"; head_tracker.type = XRServer.TRACKER_HEAD
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(head_tracker); trackers.append(head_tracker)
	var left := controller("left")
	var right := controller("right")
	root.add_child(origin)
	var camera: XRCamera3D = origin.get_node("XRCamera3D")
	var body = origin.get_node("PlayerBody")
	body.set_physics_process(false)
	body.on_ground = true
	var rig := Rig.new(); origin.add_child(rig)
	check(rig.configure(camera,body,[catalog.weapons.pistol_cdef,catalog.weapons.rifle_e11],"left",origin),"Left-handed XR rig configured")
	rig.set_physics_process(false); rig.set_process(false); rig.set_allowed(true)
	await process_frame
	pose(left,rig.grab_transform(1)); await process_frame
	rig._physics_process(0.01)
	left.set_input("grip",0.9); await process_frame
	rig._physics_process(0.01)
	check(rig.selected==0,"Actual left grip action draws dominant hip pistol")
	# The shared hand/weapon solve retains rigid grips even at the edge of reach.
	var aim := Transform3D(Basis.IDENTITY,Vector3(-0.25,1.3,-0.4))
	pose(left,aim * Transform3D(Basis(Vector3.RIGHT,deg_to_rad(60)),Vector3.ZERO))
	left.set_pose("aim",aim,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await process_frame
	rig._physics_process(0.01)
	check(rig.weapons[0].visual.global_transform.is_equal_approx(aim) and not origin.get_node("LeftHand").global_basis.is_equal_approx(aim.basis),"Runtime aim corrects 60-degree grip offset without rotating tracked controller")
	pose(right,Transform3D(Basis.IDENTITY,rig.support_point(0))); right.set_input("grip",0.9)
	await process_frame; rig._physics_process(0.01)
	check(rig.two_hands,"Actual right grip action supplies secondary hold")
	var attached: Transform3D = rig.hand_target("right")
	var weapon_pose: Transform3D = rig.weapons[0].visual.global_transform
	pose(right,Transform3D(Basis.from_euler(Vector3(1,0.7,2)),Vector3(0.8,0.7,0.2)))
	await process_frame; rig._physics_process(0.01)
	check(rig.two_hands and rig.hand_target("right").is_equal_approx(attached),"Pistol offhand stays attached despite controller separation and rotation")
	check(rig.weapons[0].visual.global_transform.is_equal_approx(weapon_pose),"Attached pistol offhand never steers barrel")
	check(origin.get_node("RightHand").global_position.distance_to(attached.origin)>0.5,"Physical offhand remains tracked independently of rendered hand")
	await physics_frame; await process_frame
	check(origin.get_node("RightHand/Hand").global_position.distance_to(attached.origin)<0.01,"Unmodified XR Tools glove follows weapon attachment")
	var aim_direction: Vector3 = (rig.reticle.global_position-rig.muzzle_pose(0).origin).normalized()
	check(aim_direction.dot(-rig.weapons[0].visual.global_basis.z)>0.99999,"CDEF barrel points at fixed-distance reticle")
	var avatar = preload("res://scripts/avatar.gd").new()
	var tracked = preload("res://scripts/tracked_avatar.gd").new()
	root.add_child(tracked); tracked.add_child(avatar)
	check(avatar.configure("human_male",{"height":1.0,"profession":"crafting_artisan","customization":{}},[]).error=="" and tracked.configure(avatar,origin),"Original avatar configured for weapon-hand IK")
	tracked.set_process(false); tracked.combat_rig = rig; rig.tracked_avatar = tracked
	tracked.set_standing_eye_height(1.7)
	var left_node: XRController3D = origin.get_node("LeftHand")
	var right_node: XRController3D = origin.get_node("RightHand")
	tracked.update_tracking(1.0/90,camera.global_transform,tracked.hand_target(left_node,"left"),tracked.hand_target(right_node,"right"),0)
	for side in ["left","right"]:
		var wrist: Transform3D = tracked.skeleton.get_bone_global_pose(tracked.skeleton.find_bone("lwrist" if side=="left" else "rwrist"))
		var actual: Transform3D = tracked.skeleton.global_transform * tracked.skeleton.get_bone_global_pose(tracked.skeleton.find_bone("hold_l" if side=="left" else "hold_r"))
		var requested: Transform3D = rig.hand_target(side)
		check(actual.origin.distance_to(requested.origin)<0.005 and actual.basis.orthonormalized().is_equal_approx(requested.basis.orthonormalized()),"Original avatar %s palm aligned to gun grip (error %.4f, IK %s)" % [side,actual.origin.distance_to(requested.origin),str(tracked.last_report.get(side,{}))])
	tracked.update_fingers()
	check(tracked.last_report.fingers.right.mode=="weapon_grip" and tracked.finger_state(right_node,"right").trigger==1.0,"Attached support fingers keep a closed weapon grip")
	if "--capture" in OS.get_cmdline_user_args():
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR; settings.background_color = Color(0.08,0.1,0.13)
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color = Color.WHITE; settings.ambient_light_energy = 0.8
		environment.environment = settings; root.add_child(environment)
		var light := DirectionalLight3D.new(); root.add_child(light); light.rotation_degrees = Vector3(-35,-25,0)
		var observer := Camera3D.new(); root.add_child(observer)
		observer.global_position = Vector3(-0.65,1.55,-0.85); observer.look_at(aim.origin); observer.fov = 55; observer.near = 0.02; observer.make_current()
		for i in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/combat-cdef-avatar-grip.png"))
		observer.queue_free(); camera.make_current()
	for sample in [[1.0,"crouched"],[0.5,"prone"],[1.7,"standing"]]:
		head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,sample[0],0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await process_frame
		check(rig.current_firing_posture()==sample[1],"Actual XR body facade classifies "+sample[1])
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,0.5,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await process_frame
	body.jump_in_progress = true
	check(rig.current_firing_posture()=="standing","Jumping removes physical stance advantage")
	body.jump_in_progress = false
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.0,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await process_frame
	left.set_input("trigger",0.9); await process_frame
	rig._physics_process(0.01)
	check(rig.weapons[0].state.fired==1,"Actual dominant trigger action fires")
	check(rig.rounds_sim.bolts.size()==1 and rig.rounds_sim.bolts[0].shot.firing_posture=="crouched" and is_equal_approx(rig.rounds_sim.bolts[0].shot.range_scale,1.1),"Controller shot snapshots physical crouch and pistol support independently")
	right.set_input("grip",0.0); await process_frame; rig._physics_process(0.01)
	check(not rig.two_hands and rig.hand_target("right")==null and tracked.hand_target(right_node,"right")==right_node.global_transform,"Releasing offhand restores tracked avatar hand immediately")
	await physics_frame; await process_frame
	check(origin.get_node("RightHand/Hand").global_position.distance_to(right_node.global_position)<0.01,"Releasing offhand restores fallback glove tracking")
	var hand_pose: Transform3D = origin.get_node("LeftHand").transform
	var head_pose := camera.transform
	rig.set_allowed(false); rig._physics_process(1)
	check(rig.selected==-1 and rig.rounds_sim.bolts.is_empty(),"Menu/focus gate stows and clears live local rounds")
	rig.set_allowed(true); rig._physics_process(1)
	check(rig.selected==-1,"Held grip cannot silently redraw after focus returns")
	left.set_input("grip",0.0); left.set_input("trigger",0.0)
	pose(left,rig.grab_transform(2)); await process_frame; rig._physics_process(0.01)
	left.set_input("grip",0.9); await process_frame; rig._physics_process(0.01)
	check(rig.selected==1,"Fresh left over-shoulder action draws longarm")
	left.set_input("by_button",true); await process_frame; rig._physics_process(0.01)
	check(rig.weapons[1].state.mode=="semi","Dominant Y cycles supported E-11 fire modes")
	left.set_pose("grip",hand_pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_NONE)
	left.invalidate_pose("grip"); await process_frame; rig._physics_process(0.01)
	check(rig.selected==-1 and not rig.reticle.visible,"Runtime tracking invalidation disables weapon and aiming overlay")
	check(camera.transform==head_pose,"Controller combat never overrides tracked camera")
	# Aim follows tracking-space rotation; its origin must not displace the handle.
	var original_origin := origin.transform
	origin.rotate_y(0.4)
	pose(right,Transform3D(Basis.from_euler(Vector3(0.8,0.2,0.1)),Vector3(0.1,1.2,-0.3)))
	var runtime_aim := Transform3D(Basis.from_euler(Vector3(-0.2,0.4,0.15)),Vector3(0.2,1.3,-0.5))
	right.set_pose("aim",runtime_aim,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await process_frame
	var corrected: Transform3D = rig.controller_weapon_pose(right_node)
	check(corrected.basis.is_equal_approx((origin.global_transform*runtime_aim).basis) and corrected.origin.is_equal_approx(right_node.global_position),"Right-hand aim respects XR origin while handle stays at grip")
	right.invalidate_pose("aim"); await process_frame
	corrected = rig.controller_weapon_pose(right_node)
	check(corrected.basis.is_equal_approx(right_node.global_basis*Basis(Vector3.RIGHT,-PI/4)),"Missing runtime aim uses pinned XR Tools grip correction")
	origin.transform = original_origin
	# Source-derived holsters use full animated bone transforms, for both hands.
	for side in ["left","right"]:
		rig.dominant = side
		for hands in [1,2]:
			var mount: Dictionary = rig.assets.stow_mount("human_male",hands,side)
			var bone: int = tracked.skeleton.find_bone(mount.anchor)
			var expected: Transform3D = tracked.skeleton.global_transform * tracked.skeleton.get_bone_global_pose(bone) * mount.local
			expected.basis = expected.basis.orthonormalized()
			check(rig.holster_transform(hands).is_equal_approx(expected),"Source stow position AND orientation used for %s/%d" % [side,hands])
	var previous: Transform3D = rig.holster_transform(1)
	var root_bone: int = tracked.skeleton.find_bone("root")
	tracked.skeleton.set_bone_pose_rotation(root_bone,Quaternion(Vector3.FORWARD,0.2)*tracked.skeleton.get_bone_pose_rotation(root_bone))
	rig.update_visuals()
	check(not rig.weapons[0].visual.global_transform.is_equal_approx(previous) and rig.weapons[0].visual.global_transform.is_equal_approx(rig.holster_transform(1)),"Stowed gun rotates with animated hip bone")
	if "--capture" in OS.get_cmdline_user_args():
		var observer := Camera3D.new(); root.add_child(observer)
		observer.global_position = Vector3(2.3,1.3,2.3); observer.look_at(Vector3(0,1.1,0)); observer.fov = 45; observer.make_current()
		for i in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/combat-source-stow-mounts.png"))
		observer.queue_free()
	rig.stow();rig.dominant="right"
	var scout_badge:=ScoutBadge.new();root.add_child(scout_badge);rig.scout=scout_badge
	rig.abilities.replace_selection(scout_badge.mask_entry(),"scout");rig.update_visuals()
	check(rig.ability_ui.badge.visible and rig.ability_ui.badge.global_position.is_equal_approx(right_node.global_position+Vector3.UP*.23),"Mask Scent has a physical dominant-hand anchor")
	right.invalidate_pose("grip");right.invalidate_pose("aim");await process_frame;rig.update_visuals()
	check(not rig.ability_ui.badge.visible and not rig.ability_ui.status.visible,"Lost controller tracking hides Mask Scent rather than pinning it to the head")
	pose(right,Transform3D(Basis.IDENTITY,Vector3(.25,1.1,-.4)));await process_frame;rig.update_visuals()
	check(rig.ability_ui.badge.visible and rig.ability_ui.badge.global_position.is_equal_approx(right_node.global_position+Vector3.UP*.23),"Tracking restoration returns the ability badge to the hand")
	rig.ability_ui.open_on_hand([{"id":"ch_train:1","label":"Train attack"}],right_node,camera)
	check(rig.ability_ui.menu_open and rig.ability_ui.entries.size()==1 and rig.ability_ui.panel.get_child_count()==4,"Native text-only pet options produce a complete selectable radial page without missing-icon errors")
	rig.close_ability_menu();rig.scout=null;scout_badge.free();rig.abilities.replace_selection({})
	var inventory:=preload("res://scripts/xr_inventory.gd").new();root.add_child(inventory);inventory.configure(origin,body);inventory.set_process(false);inventory.set_allowed(true)
	inventory.set_hip_tool({"id":"owned-tool","template":"object/tangible/survey_tool/survey_tool_mineral.iff","tool_kind":"survey"});rig.inventory=inventory
	# Recover through actual controller action edges after looking away from locomotion.
	for side in ["left","right"]:
		rig.dominant=side;inventory.offhand="right" if side=="left" else "left"
		var dominant_tracker:XRControllerTracker=left if side=="left" else right
		for yaw in [-1.6,1.6]:
			head_tracker.set_pose("default",Transform3D(Basis.from_euler(Vector3(.4,yaw,.2)),Vector3(.3,1.45,-.2)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
			left.set_input("grip",0.0);right.set_input("grip",0.0);left.set_input("trigger",0.0);right.set_input("trigger",0.0)
			await process_frame;rig._physics_process(.01)
			var expected:=camera.global_position+Basis(Vector3.UP,yaw)*Vector3(-.22 if side=="left" else .22,-.75,0)
			pose(right if side=="left" else left,inventory.hip_transform())
			pose(dominant_tracker,Transform3D(Basis.IDENTITY,expected));await process_frame;rig._physics_process(.01)
			dominant_tracker.set_input("grip",.9);await process_frame;rig._physics_process(.01)
			check(rig.selected==0,"Physical %s grip recovers pistol with idle offhand parked at tool hip after headset yaw %.1f"%[side,yaw])
			dominant_tracker.set_input("grip",0.0)
			var shoulder:=camera.global_position+Basis(Vector3.UP,yaw)*Vector3(-.19 if inventory.offhand=="left" else .19,-.16,.12)
			pose(right if side=="left" else left,Transform3D(Basis.IDENTITY,shoulder))
			await process_frame;rig._physics_process(.01)
			dominant_tracker.set_input("grip",.9);await process_frame;rig._physics_process(.01)
			check(rig.selected==0,"Physical %s grip recovers pistol with released offhand at backpack shoulder after headset yaw %.1f"%[side,yaw])
		inventory.set_open(true);rig._physics_process(.01)
		check(rig.selected==-1 and inventory.blocks_combat(),side+" genuine open bag still stows and blocks weapon")
		inventory.set_open(false)
		pose(dominant_tracker,inventory.hip_transform());await process_frame
		check(inventory.blocks_combat(),side+" same-hand tool holster interaction retains priority")
	inventory.queue_free()
	tracked.queue_free();
	origin.queue_free(); await create_timer(0.12).timeout
	for tracker in trackers: XRServer.remove_tracker(tracker)
	var report := {"test":"xr_combat_action_input","passed":errors.is_empty(),"checks":checks,"errors":errors,"hardware_tested":false}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/xr-combat-input-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); quit(0 if errors.is_empty() else 1)
