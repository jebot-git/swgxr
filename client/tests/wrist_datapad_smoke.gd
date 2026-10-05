extends SceneTree
## Native math fixtures only; no live headset claim.
var failures: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var hinge = ClassDB.instantiate("SwgWristDatapad")
	check(hinge != null,"Native wrist helper registered")
	if hinge == null: quit(1); return
	var mount := Transform3D(Basis.from_euler(Vector3(0.1,0.8,-0.4)),Vector3(124.3,1.2,-92.1))
	var viewer := mount * Vector3(0.4,2,0.6)
	var limit := deg_to_rad(25)
	var poses: Array = []
	for fps in [30,60,90,144]:
		hinge.reset()
		var pose: Dictionary = {}
		for frame in fps:
			pose = hinge.follow(mount,viewer,1.0/fps,limit,12.0)
			check(pose.valid,"Follow valid at %dHz" % fps)
			check(pose.transform.origin.distance_to(mount.origin)<0.00001,"Mount anchor preserved")
			check(absf(pose.pitch)<=limit+0.000001 and pose.roll==0,"Pitch constrained and local roll zero")
			var expected: Basis = mount.basis.orthonormalized()*Basis(Vector3.UP,pose.yaw)*Basis(Vector3.RIGHT,pose.pitch)
			check(expected.is_equal_approx(pose.transform.basis),"Hinge operates in wrist-local basis")
		poses.append(pose)
	for pose in poses:
		check(absf(pose.yaw-poses[0].yaw)<0.000001 and absf(pose.pitch-poses[0].pitch)<0.000001,"Delta-rate invariance for constant target")
	hinge.reset()
	check(hinge.follow(mount,mount.origin,0.016).transform.is_equal_approx(Transform3D(mount.basis.orthonormalized(),mount.origin)),"Coincident viewer stable")
	check(not hinge.follow(mount,Vector3(NAN,0,0),0.016).valid,"Invalid viewer rejected")
	check(not hinge.follow(Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO),Vector3.ONE,0.016).valid,"Singular wrist rejected")
	var screen := Transform3D(Basis.from_euler(Vector3(0.4,-0.9,0.2)),Vector3(-203,1.25,405))
	var size := Vector2(0.4,0.25)
	var pixels := Vector2(900,625)
	var ray: Dictionary = hinge.point(screen,size,pixels,screen*Vector3(0.08,0.05,0.3),screen.basis*Vector3.FORWARD)
	check(ray.valid and not ray.touching,"Rotated plane front ray hits")
	check(ray.pixel.distance_to(Vector2(630,187.5))<0.1,"Rotated ray projects expected pixel")
	check(ray.world.distance_to(screen*Vector3(0.08,0.05,0))<0.0001,"Ray world result lies on plane")
	check(absf(ray.distance-0.3)<0.0001,"World ray distance preserved")
	check(not hinge.point(screen,size,pixels,screen*Vector3(0,0,-0.2),screen.basis*Vector3.BACK).valid,"Back-side ray rejected")
	check(not hinge.point(screen,size,pixels,screen*Vector3(0,0,0.3),screen.basis*Vector3.BACK).valid,"Ray pointing away rejected")
	check(not hinge.point(screen,size,pixels,screen*Vector3(0.3,0,0.3),screen.basis*Vector3.FORWARD).valid,"Outside panel rejected")
	check(not hinge.point(screen,size,pixels,screen*Vector3(0,0,0.8),screen.basis*Vector3.FORWARD).valid,"Beyond reach rejected")
	for depth in [0.01,-0.01]:
		var touch: Dictionary = hinge.point(screen,size,pixels,screen*Vector3(0,0,depth),Vector3.ZERO)
		check(touch.valid and touch.touching and touch.pixel.distance_to(pixels*0.5)<0.1,"Direct fingertip touch works across thin plane")
	check(not hinge.point(screen,Vector2.ZERO,pixels,Vector3.ZERO,Vector3.FORWARD).valid,"Zero panel rejected")
	check(not hinge.point(screen,size,pixels,Vector3(NAN,0,0),Vector3.FORWARD).valid,"Nonfinite finger rejected")
	check(not hinge.point(screen,size,pixels,Vector3.ZERO,Vector3(NAN,0,0)).valid,"Nonfinite ray rejected")
	check(not hinge.point(screen,Vector2(NAN,0.25),pixels,screen*Vector3(0,0,0.3),screen.basis*Vector3.FORWARD).valid,"Nonfinite panel dimensions rejected")
	check(not hinge.point(screen,size,Vector2(INF,625),screen*Vector3(0,0,0.3),screen.basis*Vector3.FORWARD).valid,"Nonfinite pixels rejected")
	check(not hinge.point(screen,size,pixels,screen*Vector3(0,0,0.3),screen.basis*Vector3.FORWARD,NAN).valid,"Nonfinite reach rejected")
	check(not hinge.point(screen,size,pixels,screen*Vector3(0,0,0.3),screen.basis*Vector3.FORWARD,0.65,NAN).valid,"Nonfinite touch depth rejected")
	var report := {"test":"wrist_datapad_native","passed":failures.is_empty(),"hardware_tested":false,"checks":checks,"frame_rates":[30,60,90,144],"failures":failures}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/wrist-datapad-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
