extends SceneTree
var failures:Array[String]=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var scene:=preload("res://space/scene.gd").new();root.add_child(scene);scene.set_process(false)
	scene.exterior=Node3D.new();scene.add_child(scene.exterior)
	scene.observe_motion(Transform3D.IDENTITY)
	scene.observe_motion(Transform3D(Basis(Vector3.UP,.5),Vector3(10,0,0)))
	check(scene.visual_ship_pose.origin.is_zero_approx(),"New native receipt does not teleport the rendered exterior")
	scene._process(scene.visual_duration*.5)
	check(scene.visual_ship_pose.origin.x>0 and scene.visual_ship_pose.origin.x<10,"Ship exterior interpolates continuously between native receipts")
	check(scene.exterior.transform.is_equal_approx(scene.visual_ship_pose.affine_inverse()),"Station view uses interpolated inverse ship pose")
	scene._process(10)
	check(scene.visual_ship_pose.origin==Vector3(10,0,0),"Presentation stops at the latest native pose without extrapolating authority")
	scene.observe_motion(Transform3D(Basis.IDENTITY,Vector3(20,0,0)),Vector3(10,0,0))
	scene.visual_duration=.5;scene._process(.2)
	var before:=scene.visual_age
	scene.observe_motion(Transform3D(Basis.IDENTITY,Vector3(20,0,0)),Vector3(10,0,0))
	check(scene.visual_age==before and scene.visual_duration==.5,"Duplicate action/player snapshot cannot restart the blend at 50ms")
	scene._process(.4)
	check(scene.visual_ship_pose.origin.x>20,"Presentation bridges brief late receipts with bounded native velocity")
	scene._process(10)
	check(absf(scene.visual_ship_pose.origin.x-27.5)<.001,"Extrapolation stops after 750ms and never drives the player")
	# Every perfectly predicted receipt must preserve frame-to-frame velocity.
	scene.visual_stamp=-1
	scene.observe_motion(Transform3D.IDENTITY,Vector3(100,0,0))
	var worst_error:=0.0
	for frame in range(120):
		if frame>0 and frame%12==0:scene.observe_motion(Transform3D(Basis.IDENTITY,Vector3(frame*100.0/60.0,0,0)),Vector3(100,0,0))
		var previous:Vector3=scene.visual_ship_pose.origin
		scene._process(1.0/60.0)
		worst_error=maxf(worst_error,absf((scene.visual_ship_pose.origin-previous).x-100.0/60.0))
	check(worst_error<.001,"Perfect 5Hz receipts preserve continuous 60Hz flight speed without packet braking")
	var ui:=preload("res://scripts/xr_services.gd").new();root.add_child(ui)
	var keyboard:=Transform3D(Basis.IDENTITY,Vector3(0,1.1,0))
	var raised:Transform3D=ui.terminal_pose({"kind":"starship","position":Vector3.ZERO,"ui_anchors":[keyboard]},Vector3.ZERO,Vector3(0,1.7,1))
	check(raised.origin.y-ui.PANEL_METERS.y*.5>1.35,"Ship hologram lower edge clears keyboard height")
	check(ui.terminal_pose({"kind":"bank","ui_anchors":[keyboard]},Vector3.ZERO,Vector3(0,1.7,1))==keyboard,"Other original terminal screen anchors remain fixed")
	# Do not run unconfigured service teardown hooks in this pose-only test.
	ui.set_script(null);ui.free();scene.free()
	var yacht=preload("res://space/scene.gd").new();root.add_child(yacht)
	check(yacht.build("123456789"),"Original yacht geometry loads for actual doorway walk")
	var body=preload("res://scripts/player.gd").new();root.add_child(body);body.ground_provider=yacht.stage;body.spawn_point=Vector3(0,.6,-20);body.reset_spawn();body.testing=true;body.active=true;yacht.stage.set_observer(body)
	for i in range(60):await physics_frame
	for target in [Vector3(-2.25,0,-20),Vector3(-2.25,0,-15.75)]:
		for i in range(240):
			var d=Vector2(target.x-body.position.x,target.z-body.position.z)
			if d.length()<.07:break
			body.test_input=d.normalized()
			await physics_frame
		body.test_input=Vector2.ZERO
	check(yacht.cell_index()==5 and body.position.distance_to(Vector3(-2.25,.03,-15.75))<.3,"Production locomotion crosses original bridge doorway into cell 5")
	check(body.is_on_floor(),"Original yacht floor supports capsule after room transition")
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","live_xr":false}));quit(0 if failures.is_empty() else 1)
