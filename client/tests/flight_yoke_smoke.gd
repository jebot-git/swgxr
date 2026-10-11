extends SceneTree
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,what:String)->void:
 checks+=1
 if not ok:failures.append(what);push_error(what)
func _initialize()->void:call_deferred("run")
func run()->void:
 var control:=preload("res://space/flight_yoke.gd").new()
 var prefs:=preload("res://space/preferences.gd").new()
 var grips:Array=[Vector3(-.2,0,0),Vector3(.2,0,0)]
 var frame:=Transform3D(Basis.from_euler(Vector3(.1,1.2,.2)),Vector3(4,10000,8))
 var l:=Transform3D(Basis.IDENTITY,grips[0]);var r:=Transform3D(Basis.IDENTITY,grips[1])
 control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016)
 var initial_l:=l;var initial_r:=r
 l.origin.z+=.18;r.origin.z+=.18
 var out:Dictionary=control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016)
 check(out.pitch<-.99 and absf(out.yaw)<.001 and absf(out.roll)<.001,"Pull yoke raises SWG nose without yaw/roll")
 l.origin.z-=.36;r.origin.z-=.36
 out=control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016)
 check(out.pitch>.99,"Push yoke lowers SWG nose")
 control.reset();l=initial_l;r=initial_r
 control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016)
 l.origin=Basis(Vector3.BACK,.55)*grips[0];r.origin=Basis(Vector3.BACK,.55)*grips[1]
 out=control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016)
 check(out.roll>.99 and absf(out.pitch)<.001,"Wheel arc controls roll without pitch")
 control.reset();l=initial_l;r=initial_r
 control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016)
 l.origin=Basis(Vector3.UP,.55)*grips[0];r.origin=Basis(Vector3.UP,.55)*grips[1]
 out=control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016)
 check(out.yaw<-.99 and absf(out.pitch)<.001,"Sideways turning controls yaw")
 var before:Dictionary=out.duplicate()
 out=control.sample(prefs,frame,grips,frame*l,frame*r,0,1,true,Vector2.ZERO,.016)
 check(is_equal_approx(out.yaw,before.yaw) and not control.state.left_held and control.state.right_held,"Releasing one hand preserves control without a jump")
 r.origin.z+=.18
 out=control.sample(prefs,frame,grips,frame*l,frame*r,0,1,true,Vector2.ZERO,.016)
 check(out.pitch<-.99,"Single held hand can pull for pitch")
 for i in 120:out=control.sample(prefs,frame,grips,frame*l,frame*r,0,1,true,Vector2(0,1),1.0/60)
 check(out.throttle>.99,"Joystick increases throttle independently of pushed/pulled controls")
 var pre_loss:Dictionary=out.duplicate()
 out=control.sample(prefs,frame,grips,frame*l,frame*r,0,1,false,Vector2.ONE,.016)
 check(out.pitch==0 and out.yaw==0 and out.roll==0 and out.throttle==0 and control.state.right_held,"Tracking loss neutralizes output and retains vehicle-style hand attachment")
 r.origin+=Vector3(.3,.2,.1)
 out=control.sample(prefs,frame,grips,frame*l,frame*r,0,1,true,Vector2.ZERO,.016)
 check(is_equal_approx(out.pitch,pre_loss.pitch),"Tracking recovery rebases the controller without a control jump")
 out=control.sample(prefs,frame,grips,frame*l,frame*r,0,0,true,Vector2.ZERO,.016)
 check(out.pitch==0 and not control.state.right_held,"Physical grip release detaches and centers the yoke")
 control.reset();l=initial_l;r=initial_r
 control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016,"stick")
 check(control.state.right_held and not control.state.left_held,"Central stick accepts one hand without overlapping attachments")
 r.origin.z+=.18
 out=control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016,"stick")
 check(out.pitch<-.99,"Central stick pull raises nose")
 r.origin.x+=.18;r.basis=Basis(Vector3.UP,.55)
 out=control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016,"stick")
 check(out.roll<-.99 and out.yaw<-.99,"Central stick sideways roll and wrist twist yaw")
 control.sample(prefs,frame,grips,frame*l,frame*r,1,0,true,Vector2.ZERO,.016,"stick")
 check(control.state.left_held and not control.state.right_held,"Central stick can transfer to the left hand")
 var scene:=preload("res://space/scene.gd").new();root.add_child(scene)
 check(scene.build("77","object/ship/player/player_tiefighter.iff"),"Actual original TIE control geometry loads")
 scene.align_cockpit(Vector3(0,1.13,0))
 control.reset();l=initial_l;r=initial_r;control.sample(prefs,frame,grips,frame*l,frame*r,1,1,true,Vector2.ZERO,.016)
 control.update_visual(scene)
 var target:Transform3D=control.hand_target("left",scene)
 check(target.origin.distance_to(scene.control_node.to_global(scene.control_grips()[0]))<.001,"Hand attachment uses actual animated cockpit grip")
 check(l.basis==initial_l.basis and r.basis==initial_r.basis,"Control sampling does not rotate physical controller poses")
 var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();root.add_child(rig)
 var body:Node3D=rig.get_node("PlayerBody");body.set_process(false);body.set_physics_process(false)
 var camera:XRCamera3D=rig.get_node("XRCamera3D");camera.position=Vector3(0,1.13,0)
 var tracker:=XRPositionalTracker.new();tracker.name="head";tracker.type=XRServer.TRACKER_HEAD;tracker.set_pose("default",camera.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(tracker)
 var hand_trackers:Array=[]
 for side in ["left","right"]:
  var hand:=XRControllerTracker.new();hand.name=side+"_hand";hand.type=XRServer.TRACKER_CONTROLLER;hand.hand=XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
  hand.set_pose("grip",control.hand_target(side,scene),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);hand.set_input("grip",1.0);XRServer.add_tracker(hand);hand_trackers.append(hand)
 var flight:=preload("res://space/controller.gd").new();root.add_child(flight);flight.set_process(false)
 flight.scene=scene;flight.ground={"test":true};flight.station="pilot";flight.ship={"kind":"fighter","capacity":1,"player_position":[0,0,0]};flight.preferences=prefs;flight.yoke=control;body.space=flight
 var tracked:=preload("res://scripts/tracked_avatar.gd").new();root.add_child(tracked)
 var avatar:=preload("res://scripts/avatar.gd").new();tracked.add_child(avatar);avatar.configure("human_male",{"profession":"science_medic"});tracked.configure(avatar,rig);tracked.set_standing_eye_height(1.7);tracked.set_process(false)
 await process_frame
 var hmd_before:=camera.transform
 for i in 8:tracked._process(1.0/90)
 for side in ["left","right"]:
  var actual:Transform3D=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("hold_l" if side=="left" else "hold_r"))
  var expected:Transform3D=flight.hand_target(side)
  check(actual.origin.distance_to(expected.origin)<.015,side+": avatar hold socket reaches actual TIE control grip")
  check(tracked.last_report.fingers[side].mode=="vehicle_grip",side+": same closed-finger attachment rules as vehicles")
 check(camera.transform.is_equal_approx(hmd_before),"Flight hand IK preserves tracked HMD pose")
 control.reset()
 check(flight.hand_target("left")==null and flight.hand_target("right")==null,"Control reset releases both visual hands")
 tracked.free();flight.scene=null;flight.free();rig.free();XRServer.remove_tracker(tracker)
 for hand in hand_trackers:XRServer.remove_tracker(hand)
 scene.free()
 print(JSON.stringify({"checks":checks,"failures":failures,"live_xr":false,"renderer":"dummy"}));quit(0 if failures.is_empty() else 1)
