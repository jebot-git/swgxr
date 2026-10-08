extends SceneTree
const Frame=preload("res://entertainment/image_frame_gesture.gd")
const Fixture=preload("res://tests/entertainer_extension_smoke.gd")
const Entertainer=preload("res://tests/entertainer_smoke.gd")
var errors:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:
	create_timer(30).timeout.connect(func():quit(2))
	call_deferred("run")
func hands(space:=Transform3D.IDENTITY,flip:=1.0)->Array:
	return [{"position":space*Vector3(-.18,-.12*flip,-.4),"index":space.basis*Vector3.UP*flip,"thumb":space.basis*Vector3.RIGHT},
		{"position":space*Vector3(.18,.12*flip,-.4),"index":space.basis*Vector3.DOWN*flip,"thumb":space.basis*Vector3.LEFT}]
func hold(frame:RefCounted,seconds:float,pair:Array,tracked:=true,permitted:=true)->int:
	var count:=0
	for i in range(roundi(seconds*90)):
		if frame.sample(1.0/90,Transform3D.IDENTITY,pair[0],pair[1],tracked,permitted):count+=1
	return count
func run()->void:
	for hz in [45.0,72.0,90.0,120.0]:
		for flip in [-1.0,1.0]:
			var frame:=Frame.new();var fired:=0
			for i in range(int(hz*2)):
				var space:=Transform3D(Basis(Vector3.UP,i/hz*.4),Vector3(i/hz,1.7,-i/hz*.2));var pair:=hands(space,flip)
				if frame.sample(1/hz,space,pair[0],pair[1],true,true):fired+=1
			check(fired==1,"Both frame diagonals work once while walking/turning at %s Hz"%hz)
	for mode in ["one_hand","same_height","behind","low","close","wide","index_wrong","thumb_wrong","blocked","untracked"]:
		var pair:=hands();var frame:=Frame.new()
		match mode:
			"one_hand":pair[0]={}
			"same_height":pair[1].position.y=pair[0].position.y
			"behind":pair[0].position.z=.4;pair[1].position.z=.4
			"low":pair[0].position.y-=.6;pair[1].position.y-=.6
			"close":pair[0].position.x=-.03;pair[1].position.x=.03
			"wide":pair[0].position.x=-.5;pair[1].position.x=.5
			"index_wrong":pair[0].index=Vector3.FORWARD
			"thumb_wrong":pair[1].thumb=Vector3.RIGHT
		check(hold(frame,2,pair,mode!="untracked",mode!="blocked")==0,"Reject "+mode)
	var frame:=Frame.new();var pair:=hands()
	check(hold(frame,.7,pair)==0,"Brief frame cannot activate")
	hold(frame,.1,pair,false)
	check(hold(frame,.7,pair)==0 and hold(frame,.1,pair)==1,"Tracking loss cancels partial hold")
	hold(frame,.1,pair,false);hold(frame,.1,pair,true,false)
	check(hold(frame,1,pair)==0,"Tracking/focus recovery cannot repeat completed frame")
	frame.sample(.02,Transform3D.IDENTITY,{},pair[1],true,true)
	check(hold(frame,.8,pair)==1,"Observed release rearms frame")
	var joints:Dictionary={"index_proximal":Vector3.ZERO,"index_intermediate":Vector3(0,.03,0),"index_distal":Vector3(0,.055,0),"index_tip":Vector3(0,.08,0),"thumb_proximal":Vector3.ZERO,"thumb_tip":Vector3(.04,0,0),"ring_proximal":Vector3.ZERO,"ring_tip":Vector3(0,.025,0)}
	check(not Frame.optical_hand({"joints":joints,"wrist":Transform3D.IDENTITY},Transform3D.IDENTITY).is_empty(),"Optical extended thumb/index L accepted")
	for mode in ["curled_index","closed_thumb","parallel","open_ring"]:
		var changed:=joints.duplicate()
		match mode:
			"curled_index":changed.index_tip=Vector3(0,.025,0)
			"closed_thumb":changed.thumb_tip=Vector3(.01,0,0)
			"parallel":changed.thumb_tip=Vector3(0,.04,0)
			"open_ring":changed.ring_tip=Vector3(0,.09,0)
		check(Frame.optical_hand({"joints":changed,"wrist":Transform3D.IDENTITY},Transform3D.IDENTITY).is_empty(),"Optical rejects "+mode)
	var origin:=XROrigin3D.new();root.add_child(origin)
	var trackers:Array=[];var controllers:Array=[]
	for side in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.name=side+"_hand";tracker.type=XRServer.TRACKER_CONTROLLER
		tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		tracker.set_input("grip",.9);tracker.set_input("trigger",0.0);tracker.set_input("trigger_touch",false);tracker.set_input("thumbrest_touch",false)
		XRServer.add_tracker(tracker);trackers.append(tracker)
		var controller:=XRController3D.new();controller.tracker=tracker.name;controller.pose="grip";origin.add_child(controller);controllers.append(controller)
	await process_frame
	controllers[0].global_transform=Transform3D(Basis(Vector3.FORWARD,Vector3.RIGHT,Vector3.DOWN),pair[0].position)
	controllers[1].global_transform=Transform3D(Basis(Vector3.FORWARD,Vector3.LEFT,Vector3.UP),pair[1].position)
	check(Frame.frame_pose(Transform3D.IDENTITY,Frame.hand(controllers[0],"left"),Frame.hand(controllers[1],"right")),"Tracked controller L approximation forms the same frame")
	for action in ["trigger_touch","thumbrest_touch"]:
		trackers[0].set_input(action,true)
		check(Frame.hand(controllers[0],"left").is_empty(),"Controller rejects finger resting on "+action)
		trackers[0].set_input(action,false)
	trackers[0].set_input("grip",0.0)
	check(Frame.hand(controllers[0],"left").is_empty(),"Open controller grip is not a framing L")
	origin.free()
	for tracker in trackers:XRServer.remove_tracker(tracker)
	var host:=Fixture.Host.new();root.add_child(host);host.gameplay_session=Fixture.Session.new();host.add_child(host.gameplay_session)
	var body:=Fixture.Body.new();host.add_child(body);body.camera=Camera3D.new();body.add_child(body.camera);body.feedback=Entertainer.GroundedFeedback.new();body.feedback.configure(body,body.camera)
	var performer:=preload("res://entertainment/controller.gd").new();host.add_child(performer);performer.set_process(false);performer.set_physics_process(false);performer.native.set_process(false);performer.native.set_physics_process(false)
	performer.configure(host,body,null,{"token":"fixture","context":{}},"fixture")
	var native:Node=performer.native
	for mode in ["eligible","unlearned","stale","menu","unfocused","held","performing","untracked"]:
		native.design_ui.close_interface();native.image_frame.reset();native.age=0;native.state={"commands":["imagedesign"],"nearby_players":[{"id":"123","name":"Self"}]}
		host.xr_requested=true;host.xr_focused=mode!="unfocused";performer.item={};performer.active_performance={};performer.since_reply=0
		if mode=="unlearned":native.state.commands=[]
		if mode=="stale":native.age=20
		if mode=="held":performer.item={"id":"instrument"}
		if mode=="performing":performer.active_performance={"id":"dance"}
		if mode=="menu":performer.ui.open([{"id":"image_design","label":"Image Design"}],Transform3D.IDENTITY)
		else:performer.ui.close()
		for i in range(180):native.sample_image_frame(1.0/90,Transform3D.IDENTITY,pair[0],pair[1],mode!="untracked")
		check((native.design_ui.terminal.get("id","")=="image-design-targets")== (mode=="eligible"),"Production selector routing: "+mode)
	check(host.calls.is_empty(),"Frame only opens selector; it never bypasses recipient selection or consent")
	host.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","mocked_tracking":true,"live_xr":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/image-frame.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
