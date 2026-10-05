extends SceneTree
## Original avatars, real native limb/body solvers, synthetic tracking only.
const Avatar = preload("res://scripts/avatar.gd")
const Driver = preload("res://scripts/tracked_avatar.gd")
var errors: Array[String] = []
var checks := 0
var rows: Array = []
var capture := false
func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func point(skeleton: Skeleton3D, name: String) -> Vector3:
	return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var origin := XROrigin3D.new(); world.add_child(origin)
	var body := CharacterBody3D.new(); body.name="PlayerBody"; origin.add_child(body)
	var camera := XRCamera3D.new(); camera.name="XRCamera3D"; origin.add_child(camera)
	for side in ["LeftHand","RightHand"]:
		var hand := XRController3D.new(); hand.name=side; origin.add_child(hand)
	var observer := Camera3D.new(); world.add_child(observer); observer.make_current(); observer.fov=45
	if capture:
		var environment := WorldEnvironment.new(); world.add_child(environment)
		var settings := Environment.new(); settings.background_mode=Environment.BG_COLOR; settings.background_color=Color(0.1,0.13,0.16)
		settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color.WHITE; settings.ambient_light_energy=0.8; environment.environment=settings
		var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees=Vector3(-40,-25,0)
		var floor_mesh := MeshInstance3D.new(); world.add_child(floor_mesh); floor_mesh.mesh=PlaneMesh.new()
		floor_mesh.scale=Vector3(10,1,10)
	var catalog := Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/assets/characters/catalog.json"))
	var directory := ProjectSettings.globalize_path("res://../runtime/evidence/tracked-posture")
	DirAccess.make_dir_recursive_absolute(directory)
	for race in (["human_male","ithorian_male","wookiee_male"] if capture else catalog.races.keys()):
		var driver := Driver.new(); world.add_child(driver); driver.set_process(false)
		var avatar := Avatar.new(); driver.add_child(avatar)
		check(avatar.configure(race,{"height":1.0,"profession":"crafting_artisan","customization":{}},[]).error=="" and driver.configure(avatar,origin),"Configure original "+race)
		driver.set_standing_eye_height(1.7)
		var original_origin := origin.transform
		var original_camera := camera.transform
		var original_body := body.transform
		for scenario in [["idle",1.7,Vector3.ZERO],["crouch",1.15,Vector3.ZERO],["crouch",0.85,Vector3.ZERO],["prone",0.5,Vector3.ZERO],["crawl",0.5,Vector3(0,0,-0.5)],["crouch",1.0,Vector3.ZERO],["idle",1.7,Vector3.ZERO],
			["knockdown",0.35,Vector3.ZERO,{"knocked_down":true}], ["jump",2.2,Vector3.ZERO,{"jump_time":0.8}], ["idle",1.7,Vector3.ZERO]]:
			var state: String=scenario[0]; var height: float=scenario[1]; var velocity: Vector3=scenario[2]
			var head := Transform3D(Basis.IDENTITY,Vector3(0,height,0))
			var left := Transform3D(Basis.IDENTITY,Vector3(-0.2,maxf(0.15,height-0.35),-0.3))
			var right := Transform3D(Basis.IDENTITY,Vector3(0.2,maxf(0.15,height-0.35),-0.3))
			var context := {"velocity":velocity,"grounded":true}
			if scenario.size() > 3:
				context["presentation"] = scenario[3]
				context["physical_eye_height"] = 1.7
			for frame in range(90): driver.update_tracking(1.0/90,head,left,right,0,context)
			var skeleton: Skeleton3D=avatar.skeleton
			var label := "%s/%s/%.2f" % [race,state,height]
			check(driver.last_report.motion.state==state,"Select physical posture "+label)
			var eye: Vector3=skeleton.global_transform*(skeleton.get_bone_global_pose(skeleton.find_bone("head"))*driver.eye_in_head)
			check(eye.distance_to(head.origin)<0.001,"Keep tracked eye position "+label)
			for side in ["l","r"]:
				var hip := point(skeleton,side+"thigh"); var knee := point(skeleton,side+"shin"); var ankle := point(skeleton,side+"ankle")
				check(ankle.y>=-0.005 and knee.y>=-0.03,"Leg stays above supported floor %s%s (hip %s knee %s ankle %s)" % [label,side,hip,knee,ankle])
				if state=="crouch":
					var bend := (knee-hip).slide((ankle-hip).normalized())
					check(bend.dot(Vector3.FORWARD)>0.02,"Knee bends forward, never backwards "+label+side)
				if state in ["prone","crawl"]:
					check(ankle.z-head.origin.z>0.45,"Prone legs extend behind tracked head "+label+side)
			if state in ["prone","crawl"]:
				var torso := (point(skeleton,"spine3")-point(skeleton,"root")).normalized()
				check(absf(torso.dot(Vector3.UP))<0.65,"Prone torso remains horizontal "+label)
			rows.append({"race":race,"state":state,"eye_height":height,"motion":driver.last_report.motion.state})
			if capture:
				observer.global_position=Vector3(2.5,1.1,0.3 if state not in ["prone","crawl"] else 0.8)
				observer.look_at(Vector3(0,0.75 if state not in ["prone","crawl"] else 0.25,0.35 if state in ["prone","crawl"] else 0))
				for i in range(3): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory.path_join("%s_%s_%.2f.png" % [race,state,height]))
		check(origin.transform==original_origin and camera.transform==original_camera and body.transform==original_body,"Posture never changes tracking or physics nodes "+race)
		driver.free()
	var report := {"test":"tracked_crouch_prone_ik","checks":checks,"passed":errors.is_empty(),"errors":errors,"hardware_tested":false,"poses":rows}
	FileAccess.open(directory.path_join("render-report.json" if capture else "report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"test":report.test,"checks":checks,"passed":report.passed,"errors":errors,"hardware_tested":false}))
	world.queue_free(); await process_frame; quit(0 if errors.is_empty() else 1)
