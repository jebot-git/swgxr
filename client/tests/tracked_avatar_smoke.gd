extends SceneTree
## Source avatar + wrapper integration using synthetic OpenXR grip transforms.
## Optional --capture renders evidence; this is not a hardware tracking claim.
const Avatar = preload("res://scripts/avatar.gd")
const TrackedAvatar = preload("res://scripts/tracked_avatar.gd")
class PlayerBody extends CharacterBody3D:
	var space:Node
class Chair extends Node:
	var enabled:=false
	var poses:Dictionary={}
	func seated()->bool:return enabled
	func seat_pose()->Transform3D:return Transform3D(Basis.IDENTITY,Vector3(0,.45,0))
	func rider_pose(race:String)->Dictionary:return poses.get(race,{})
var capture := false
var results: Array = []
var view: Camera3D
var all_passed := true

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")

func eye_world(tracked: Node3D) -> Vector3:
	var head: Transform3D = tracked.skeleton.get_bone_global_pose(tracked.skeleton.find_bone("head"))
	return tracked.skeleton.global_transform * (head * tracked.eye_in_head)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	if capture:
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color(0.11,0.14,0.17)
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color.WHITE
		settings.ambient_light_energy = 0.7
		environment.environment = settings
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45,20,0)
		world.add_child(light)
		view = Camera3D.new()
		view.fov = 85
		view.near = 0.02
		world.add_child(view)
		view.make_current()
	var rig := XROrigin3D.new()
	world.add_child(rig)
	var player := PlayerBody.new()
	var chair:=Chair.new();world.add_child(chair)
	chair.poses=Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/assets/space_effects/assets.json")).get("seat_poses",{})
	player.space=chair
	player.name = "PlayerBody"
	rig.add_child(player)
	var camera := XRCamera3D.new()
	camera.name = "XRCamera3D"
	camera.current = false
	rig.add_child(camera)
	for name in ["LeftHand","RightHand"]:
		var hand := XRController3D.new()
		hand.name = name
		var glove := Node3D.new()
		glove.name = "Hand"
		hand.add_child(glove)
		rig.add_child(hand)
	var catalog := Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/assets/characters/catalog.json"))
	var fixture := Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/evidence/tracked-avatar-core3-character.json"))
	var races: Array = ["human_male","ithorian_male","wookiee_male"] if capture else catalog.races.keys()
	var directory := ProjectSettings.globalize_path("res://../runtime/evidence/tracked-avatar-wrapper")
	DirAccess.make_dir_recursive_absolute(directory)
	for race in races:
		chair.enabled=false
		var tracked := TrackedAvatar.new()
		world.add_child(tracked)
		var avatar := Avatar.new()
		tracked.add_child(avatar)
		var appearance := {"height":1.0,"profession":"crafting_artisan","customization":{}}
		var equipment: Array = []
		var authoritative := false
		if race == "human_male" and fixture.has("character"):
			appearance = fixture.character.appearance.duplicate(true)
			appearance.profession = fixture.character.profession
			equipment = fixture.character.equipment
			authoritative = true
		var configured: bool = avatar.configure(race,appearance,equipment).error == "" and tracked.configure(avatar,rig)
		tracked.set_process(false)
		var fingers := SwgFingerRetargeter.new()
		var passed := configured and fingers.configure(avatar.skeleton)
		var head := Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
		var left := Transform3D(Basis.IDENTITY,Vector3(-0.27,1.2,-0.34))
		var right := Transform3D(Basis.IDENTITY,Vector3(0.27,1.2,-0.34))
		# A low first HMD sample is posture, never implicit body-size calibration.
		# Reproduce the seated startup that made a full-size staff look enormous.
		var initial_height:=tracked.standing_eye_height
		tracked.update_tracking(1.0/90,Transform3D(Basis.IDENTITY,Vector3(0,1.2,0)),left,right,0.0)
		passed = passed and is_equal_approx(tracked.standing_eye_height,initial_height)
		var startup_fit:float=tracked.fit_scale
		tracked.update_tracking(1.0/90,head,left,right,0.0)
		passed = passed and is_equal_approx(tracked.fit_scale,startup_fit)
		var eye_error := eye_world(tracked).distance_to(head.origin)
		passed = passed and eye_error < 0.0005 and not avatar.animation_player.active and not avatar.face_player.active
		passed = passed and not camera.get_cull_mask_value(2)
		var first_person_parts := 0
		var observer_parts := 0
		for mesh in avatar.meshes:
			if mesh.layers == 1: first_person_parts += 1
			if mesh.layers == 2: observer_parts += 1
		passed = passed and first_person_parts > 0 and observer_parts > 0
		var fit: float = tracked.fit_scale
		# Looking downward rotates the real source head while the camera remains
		# independent. Maintain yaw, rather than look_at() flipping over the body.
		head.basis = Basis.from_euler(Vector3(deg_to_rad(-70),0,0))
		tracked.update_tracking(1.0/90,head,left,right,0.0)
		eye_error = maxf(eye_error,eye_world(tracked).distance_to(head.origin))
		if capture:
			view.fov = 85
			view.global_transform = head
			view.cull_mask = 1
			view.make_current()
			for frame in range(5): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join(race + "_first_person.png"))
			view.cull_mask = 3
			view.fov = 42
			view.global_position = Vector3(0,1.1,-2.4)
			view.look_at(Vector3(0,1.0,0))
			for frame in range(3): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join(race + "_observer.png"))
		if capture:
			var poses := {"open":{},"fist":{"grip":1.0,"trigger":1.0,"thumb_touch":1.0},"point":{"grip":1.0,"trigger":0.0,"thumb_touch":1.0},"thumbs_up":{"grip":1.0,"trigger":1.0,"thumb_touch":0.0}}
			for pose in poses:
				tracked.update_tracking(1.0/90,Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),left,right,0.0)
				fingers.apply_controller(poses[pose],poses[pose])
				view.cull_mask = 1
				view.fov = 50
				view.global_position = Vector3(-0.55,1.18,-0.65)
				view.look_at(Vector3(-0.27,1.17,-0.34))
				for frame in range(3): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory.path_join(race + "_hands_" + pose + ".png"))
			view.cull_mask = 3
			view.fov = 42
			view.global_position = Vector3(0,1.1,-2.4)
			view.look_at(Vector3(0,0.9,0))
		# Source proportions stay calibrated when the physical HMD crouches.
		head = Transform3D(Basis.IDENTITY,Vector3(0,1.22,0))
		left.origin.y -= 0.35
		right.origin.y -= 0.35
		tracked.update_tracking(1.0/90,head,left,right,0.0)
		passed = passed and is_equal_approx(tracked.fit_scale,fit)
		eye_error = maxf(eye_error,eye_world(tracked).distance_to(head.origin))
		var ankle_error := 0.0
		for side in ["left","right"]:
			var index: int = avatar.skeleton.find_bone("lankle" if side == "left" else "rankle")
			var actual: Vector3 = avatar.skeleton.global_transform * avatar.skeleton.get_bone_global_pose(index).origin
			var reference: Vector3 = avatar.visual_root.transform * tracked.ankle_rest[side].origin
			var lift: float = tracked.last_report.get("motion",{}).get("foot_lift",{}).get(side,0.0)
			ankle_error = maxf(ankle_error,absf(actual.y-reference.y*fit-lift*fit*avatar.visual_root.scale.y))
		passed = passed and ankle_error < 0.003
		if capture:
			for frame in range(3): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join(race + "_crouch.png"))
		# World placement and yaw do not leak into source skeleton-space targets.
		var world_offset := Transform3D(Basis(Vector3.UP,1.1),Vector3(24,4,-19))
		head = world_offset * Transform3D(Basis.from_euler(Vector3(-0.3,0,0.1)),Vector3(0,1.7,0))
		left = world_offset * Transform3D(Basis.IDENTITY,Vector3(-0.27,1.2,-0.34))
		right = world_offset * Transform3D(Basis.IDENTITY,Vector3(0.27,1.2,-0.34))
		var rig_before := rig.global_transform
		var camera_before := camera.global_transform
		var player_before := player.global_transform
		tracked.update_tracking(1.0/90,head,left,right,4.0)
		eye_error = maxf(eye_error,eye_world(tracked).distance_to(head.origin))
		passed = passed and rig.global_transform.is_equal_approx(rig_before) and camera.global_transform.is_equal_approx(camera_before) and player.global_transform.is_equal_approx(player_before)
		tracked.update_tracking(1.0/90,head,null,right,4.0)
		passed = passed and not tracked.last_report.left_tracked and tracked.last_report.right_tracked
		passed = passed and avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("lwrist")).origin.is_finite() and eye_error < 0.0005
		chair.enabled=true
		head=Transform3D(Basis.IDENTITY,Vector3(0,1.13,0));left=Transform3D(Basis.IDENTITY,Vector3(-.27,.9,-.34));right=Transform3D(Basis.IDENTITY,Vector3(.27,.9,-.34))
		tracked.update_tracking(1.0/90,head,left,right,0)
		var pelvis:Vector3=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("root")).origin
		var thigh:Vector3=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("lthigh")).origin
		var knee:Vector3=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("lshin")).origin
		var seat_error:=pelvis.distance_to(chair.seat_pose().origin)
		passed=passed and seat_error<.001 and absf((knee-thigh).z)>absf((knee-thigh).y) and rig.global_transform.is_equal_approx(rig_before) and camera.global_transform.is_equal_approx(camera_before) and player.global_transform.is_equal_approx(player_before)
		if capture:
			view.position=Vector3(1,1.15,1.7);view.look_at(Vector3(0,.8,0),Vector3.UP)
			for frame in range(3):await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join(race+"_chair.png"))
		results.append({"race":race,"passed":passed,"seat_pelvis_error":seat_error,"seated_thigh_delta":[(knee-thigh).x,(knee-thigh).y,(knee-thigh).z],"eye_error":eye_error,"crouch_ankle_error":ankle_error,"fit_scale":fit,"first_person_parts":first_person_parts,"observer_head_parts":observer_parts,"original_core3_appearance":authoritative})
		all_passed = all_passed and passed
		tracked.free()
	var output := {"test":"tracked_avatar_wrapper","hardware_tested":false,"native_ik":true,"passed":all_passed,"races":results}
	var report_file := FileAccess.open(directory.path_join("render_report.json" if capture else "report.json"),FileAccess.WRITE)
	report_file.store_string(JSON.stringify(output,"  ")+"\n")
	print("TRACKED_AVATAR_WRAPPER ",JSON.stringify(output))
	quit(0 if all_passed else 1)
