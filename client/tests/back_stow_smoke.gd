extends SceneTree
const Rig = preload("res://combat/ranged_rig.gd")
const Avatar = preload("res://scripts/avatar.gd")
class TrackedProbe extends Node3D:
	var avatar: Node3D
	var skeleton: Skeleton3D
var checks := 0
var errors: Array[String] = []
var examples: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,1.7,0)
	var body := CharacterBody3D.new()
	world.add_child(body)
	var rig := Rig.new()
	world.add_child(rig)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/combat/catalog.json"))
	check(rig.configure(camera,body,[catalog.weapons.pistol_dl44,catalog.weapons.rifle_e11]),"Original weapon models and source mount data load")
	rig.set_physics_process(false)
	rig.set_process(false)
	var original_head := camera.transform
	var original_body := body.transform
	for race in ["human_male","human_female","wookiee_male","ithorian_male"]:
		var avatar := Avatar.new()
		world.add_child(avatar)
		avatar.race_id = race
		avatar.load_catalog()
		var model: Dictionary = avatar.get_model(avatar.catalog.races[race].body)
		avatar.skeleton = avatar.build_skeleton(model.bones)
		avatar.add_child(avatar.skeleton)
		var tracked := TrackedProbe.new()
		world.add_child(tracked)
		tracked.avatar = avatar; tracked.skeleton = avatar.skeleton
		rig.tracked_avatar = tracked
		var neck := avatar.skeleton.find_bone("neck")
		var torso := avatar.skeleton.find_bone("spine3")
		for scale_value in [0.75,1.0,1.3]:
			avatar.transform = Transform3D(Basis(Vector3.UP,0.7).scaled(Vector3.ONE*scale_value),Vector3(4,2,-6))
			for crouched in [false,true]:
				avatar.skeleton.reset_bone_poses()
				if crouched:
					avatar.position.y -= 0.45
					avatar.skeleton.set_bone_pose_rotation(torso,Quaternion(Vector3.RIGHT,0.35))
				avatar.skeleton.force_update_all_bone_transforms()
				for side in ["left","right"]:
					rig.dominant = side
					var grab := rig.holster_transform(2)
					var carry := rig.visual_stow_transform(1)
					var mount: Dictionary = rig.assets.stow_mount(race,2,side)
					var anchor: Transform3D = avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(torso)
					var up: Vector3 = (anchor.basis*Vector3(mount.carry.up[0],mount.carry.up[1],mount.carry.up[2])).normalized()
					var back: Vector3 = (anchor.basis*Vector3(mount.carry.back[0],mount.carry.back[1],mount.carry.back[2])).normalized()
					var back_surface: Vector3 = anchor*Vector3(mount.carry.center[0],mount.carry.center[1],mount.carry.center[2])
					var shoulder: Vector3 = avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(neck).origin
					var highest := -INF
					var old_highest := -INF
					var nearest_back := INF
					for corner in range(8):
						var point: Vector3 = rig.weapons[1].bounds.get_endpoint(corner)
						highest = maxf(highest,(carry*point-shoulder).dot(up))
						old_highest = maxf(old_highest,(grab*point-shoulder).dot(up))
						nearest_back = minf(nearest_back,(carry*point-back_surface).dot(back))
					var label := "%s/%s/%.2f/crouch:%s" % [race,side,scale_value,crouched]
					check(highest<=0.001,"Weapon remains below source shoulder/neck boundary: "+label)
					check(old_highest-highest>0.20*scale_value,"Back carry lowers the source reach pose by torso-relative distance: "+label)
					check(nearest_back>=0.024,"Weapon clears original torso rear surface: "+label)
					check(carry.basis.is_equal_approx(grab.basis) and absf(carry.basis.determinant()-1)<0.001,"Original weapon orientation and dimensions retained: "+label)
					check(rig.visual_stow_transform(0).is_equal_approx(rig.holster_transform(1)),"Hip mount remains unchanged: "+label)
					if not crouched and side=="right" and scale_value==1.0:
						examples.append({"race":race,"grab_above_shoulder_m":old_highest,"carry_above_shoulder_m":highest,"lowered_m":old_highest-highest,"torso_clearance_m":nearest_back})
				if crouched: avatar.position.y += 0.45
		rig.tracked_avatar = null
		tracked.queue_free(); avatar.queue_free()
	check(camera.transform==original_head and body.transform==original_body,"Carry fitting never moves tracked head or physics body")
	var shoulder_grab := rig.holster_transform(2)
	rig.set_allowed(true)
	rig.sample(0.01,shoulder_grab,Transform3D.IDENTITY,0,0,0,true,true)
	rig.sample(0.01,shoulder_grab,Transform3D.IDENTITY,0.9,0,0,true,true)
	check(rig.selected==1,"Original over-shoulder grab zone still draws the lowered weapon")
	rig.sample(0.01,shoulder_grab,Transform3D.IDENTITY,0,0,0,true,true)
	check(rig.selected==-1 and rig.weapons[1].visual.global_transform.is_equal_approx(rig.visual_stow_transform(1)),"Release returns weapon to its torso carry pose")
	var report := {"test":"source_torso_back_carry","checks":checks,"passed":errors.is_empty(),"errors":errors,"examples":examples,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/back-stow-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	world.queue_free()
	var particles := root.get_node_or_null("SwgOptimizedParticles")
	if particles!=null: particles.queue_free()
	await process_frame
	await process_frame
	quit(0 if errors.is_empty() else 1)
