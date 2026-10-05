extends SceneTree
## Full source life poses with synthetic tracking; no headset or backend mutation.
const Avatar=preload("res://scripts/avatar.gd")
const Tracked=preload("res://scripts/tracked_avatar.gd")
var errors:Array=[]
var checks:=0
var cases:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	var rig:=XROrigin3D.new();root.add_child(rig)
	var body:=CharacterBody3D.new();body.name="PlayerBody";rig.add_child(body);body.position=Vector3(12,4,-7)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";rig.add_child(camera)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;rig.add_child(hand)
		var glove:=Node3D.new();glove.name="Hand";hand.add_child(glove)
	var catalog:Dictionary=Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/assets/characters/catalog.json"))
	for race:String in catalog.races:
		body.position=Vector3(12,4,-7)
		var driver:=Tracked.new();root.add_child(driver)
		var avatar:=Avatar.new();driver.add_child(avatar)
		check(avatar.configure(race,{"profession":"crafting_artisan"}).error=="" and driver.configure(avatar,rig),"Source avatar configures: "+race)
		driver.set_process(false);driver.set_physics_process(false);driver.set_standing_eye_height(1.7)
		var body_before:=body.global_transform;var rig_before:=rig.global_transform
		camera.global_transform=Transform3D(Basis(Vector3.UP,0.3),body.global_position+Vector3(0,1.7,0))
		driver.update_tracking(1.0/90,camera.global_transform,null,null,4,{"grounded":true})
		var presentation:Dictionary={"life_locked":true,"life_state":"incapacitated","life_animation":"incapacitated","life_pose_frozen":false}
		for frame in range(10):
			camera.global_transform=Transform3D(Basis(Vector3.UP,0.3+frame*0.1),body.global_position+Vector3(frame*0.03,0.28,0))
			var head_before:=camera.global_transform
			driver.update_tracking(1.0/90,camera.global_transform,Transform3D(Basis.IDENTITY,Vector3(90,90,90)),Transform3D(Basis.IDENTITY,Vector3(-90,-90,-90)),4,{"presentation":presentation})
			check(driver.last_report.life_pose.get("valid",false),"Authored full-body incap pose exists: "+race)
			check(driver.global_position.is_equal_approx(body.global_position) and absf(driver.global_basis.orthonormalized().get_euler().y-0.3)<0.001,"Original life pose remains feet-anchored, independent of tracked head movement")
			check(camera.global_transform==head_before and body.global_transform==body_before and rig.global_transform==rig_before,"Life-pose presentation leaves raw tracking and physical body untouched")
		check(not driver.last_report.tracking_ik_applied,"Life pose does not get overwritten by tracked limbs")
		var entry_anchor:=driver.global_transform
		body.global_position+=Vector3(0.4,0.1,-0.3) # Physical room-scale following stays enabled.
		var roomscale_body:=body.global_transform
		driver.update_tracking(1.0/90,camera.global_transform,null,null,4.1,{"presentation":presentation})
		check(driver.global_transform.is_equal_approx(entry_anchor),"Room-scale body/floor changes do not slide incapacitated source body")
		check(body.global_transform==roomscale_body,"Anchoring never undoes physical room-scale movement")
		var source_pose:Array=[]
		presentation.merge({"life_state":"dead","life_animation":"dead","life_pose_frozen":true},true)
		for frame in range(10):
			driver.update_tracking(1.0/90,camera.global_transform,null,null,4,{"presentation":presentation});driver.update_fingers()
			for bone in range(driver.skeleton.get_bone_count()):
				var pose:Transform3D=driver.skeleton.get_bone_pose(bone)
				if frame==0:source_pose.append(pose)
				else:check(pose.is_equal_approx(source_pose[bone]),"Dead original source pose including hands/head remains frozen")
		check(driver.life_pose_time==0 and driver.last_report.life_pose.get("valid",false),"Dead source pose frozen at exact authored sample")
		check(driver.global_transform.is_equal_approx(entry_anchor),"Native incapacitated-to-dead transition retains original floor anchor")
		body.global_position=Vector3(18,4,-12)
		camera.global_transform=Transform3D(Basis(Vector3.UP,0.8),body.global_position+Vector3(0,0.28,0))
		driver.reset_life_pose_anchor()
		check(not driver.life_pose_locked,"Authoritative relocation explicitly releases cached anchor")
		driver.update_tracking(1.0/90,camera.global_transform,null,null,4,{"presentation":presentation})
		check(driver.global_position.is_equal_approx(body.global_position) and absf(driver.life_pose_heading-0.8)<0.001,"First covered destination sample binds relocated floor and heading")
		var report:Dictionary=driver.last_report.duplicate(true)
		camera.global_position=body.global_position+Vector3(0,1.7,0)
		for frame in range(30):driver.update_tracking(1.0/90,camera.global_transform,null,null,4,{"grounded":true})
		check(not driver.life_pose_locked and driver.last_report.has("left") and driver.last_report.has("right"),"Confirmed recovery resumes tracked limb solver")
		check(driver.last_report.motion.valid,"Confirmed recovery resumes original locomotion")
		check(driver.life_pose_anchor==Vector3.ZERO,"Confirmed recovery clears cached immobilized anchor")
		cases.append({"race":race,"life_pose":report.life_pose,"bone_count":driver.skeleton.get_bone_count()})
		driver.free()
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"races":cases,"tracking_mocked":true,"headset_tested":false,"backend_tested":false}
	FileAccess.open("res://../runtime/evidence/tracked-life-pose-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	rig.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
