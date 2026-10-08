extends SceneTree
## Native view-follow through production orchestration, with mocked tracking.
var errors:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var head:=XRCamera3D.new();head.name="XRCamera3D";rig.add_child(head)
	head.transform=Transform3D(Basis(Vector3.UP,.7),Vector3(210,1.7,-153))
	for side in ["LeftHand","RightHand"]:
		var controller:=XRController3D.new();controller.name=side;rig.add_child(controller)
	var pad:=preload("res://scripts/xr_datapad.gd").new();world.add_child(pad)
	pad.configure(rig,null);pad.set_process(false);pad.set_allowed(true)
	var original:=head.transform
	for expanded in [false,true]:
		pad.ui.expanded=expanded;pad.resize_map(expanded);pad.set_open(true)
		var initial:Transform3D=pad.global_transform
		check(head.to_local(initial.origin).z<-.7 and head.to_local(initial.origin).z> -1,"Opens ahead at reading distance")
		# Look at each actual mesh corner. Include summary and detached details.
		for surface:Dictionary in pad.surfaces:
			for x in [-.5,.5]:
				for y in [-.5,.5]:
					var corner:Vector3=surface.mesh.global_transform*Vector3(x*surface.meters.x,y*surface.meters.y,0)
					head.look_at(corner,Vector3.UP)
					for i in 45:pad.update_view_follow(head.global_transform,1.0/90)
					check(pad.global_transform.is_equal_approx(initial),"Looking at panel corner does not chase view (expanded=%s)"%expanded)
		head.transform=original
		head.rotate_object_local(Vector3.FORWARD,.4)
		pad.update_view_follow(head.global_transform,1.0/90)
		check(pad.global_transform.is_equal_approx(initial),"Head roll does not roll interface")
		head.transform=original;head.position+=Vector3(.04,.025,0)
		for i in 45:pad.update_view_follow(head.global_transform,1.0/90)
		check(pad.global_transform.is_equal_approx(initial),"Small leaning has translation dead zone")
		head.transform=original;head.rotate_y(deg_to_rad(100))
		pad.pressed=true
		for i in 30:pad.update_view_follow(head.global_transform,1.0/90)
		check(pad.global_transform.is_equal_approx(initial),"Captured click freezes target during head turn")
		pad.pressed=false;pad.update_view_follow(head.global_transform,1.0/90)
		check(pad.global_position.distance_to(initial.origin)>.001 and pad.global_position.distance_to(initial.origin)<.05,"Large turn starts smooth follow without snapping")
		for i in 180:pad.update_view_follow(head.global_transform,1.0/90)
		var heading:Vector3=-head.global_basis.z
		check(heading.angle_to(-pad.global_basis.z)<deg_to_rad(45),"Large turn brings whole interface back within view allowance")
		var previous:Vector3=pad.global_position;head.position+=Vector3(2,0,0)
		pad.update_view_follow(head.global_transform,1.0/90)
		check(pad.global_position.distance_to(previous)<.1,"Walking follow is damped")
		for i in 270:pad.update_view_follow(head.global_transform,1.0/90)
		check(head.global_position.distance_to(pad.global_position)<1.2,"Interface follows walking instead of remaining behind")
		pad.set_open(false);head.transform=original
	# Opening commonly happens while looking down at the wrist minimap.
	for tilt in [-.6,.6]:
		for expanded in [false,true]:
			head.transform=original;head.rotate_object_local(Vector3.RIGHT,tilt)
			pad.ui.expanded=expanded;pad.resize_map(expanded);pad.set_open(true)
			var tilted:Transform3D=pad.global_transform
			for surface:Dictionary in pad.surfaces:
				for x in [-.5,.5]:
					for y in [-.5,.5]:
						head.look_at(surface.mesh.global_transform*Vector3(x*surface.meters.x,y*surface.meters.y,0),Vector3.UP)
						for i in 30:pad.update_view_follow(head.global_transform,1.0/90)
						check(pad.global_transform.is_equal_approx(tilted),"Tilted opening preserves room to inspect every corner")
			pad.set_open(false)
	head.transform=original
	pad.set_open(true);pad.update_tracking_state(true,false,false,0,0,.1)
	check(pad.is_open,"Hands can be lowered or lose tracking without dismissing full datapad")
	pad.update_tracking_state(false,false,false,0,0,.1)
	check(not pad.is_open,"Head tracking loss closes floating interface")
	head.transform=Transform3D(Basis(Vector3.UP,-2),Vector3(-200,2,400));pad.set_open(true)
	check(absf(head.to_local(pad.global_position).x)<.001,"Reopening recenters immediately at new view")
	pad.set_allowed(false)
	check(not pad.is_open,"World or menu gate still dismisses interface")
	var math:=SwgWristDatapad.new()
	check(not math.follow_view(Transform3D(Basis.IDENTITY,Vector3(NAN,0,0)),Vector2.ONE,.016).valid,"Nonfinite view rejected")
	check(not math.follow_view(Transform3D.IDENTITY,Vector2.ZERO,.016).valid,"Invalid interface bounds rejected")
	var poses:Array=[]
	for fps in [30,60,90,144]:
		math.reset();math.follow_view(original,Vector2(.82,.25),0)
		var turn:=original;turn.basis=Basis(Vector3.UP,2)*turn.basis
		for i in fps:math.follow_view(turn,Vector2(.82,.25),1.0/fps)
		poses.append(math.follow_view(turn,Vector2(.82,.25),0).transform)
	for pose:Transform3D in poses:check(pose.is_equal_approx(poses[0]),"Follow is invariant at30/60/90/144Hz")
	var result:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"headset_tested":false,"tracking":"mocked"}
	FileAccess.open("res://../runtime/evidence/floating-datapad.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result))
	world.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
