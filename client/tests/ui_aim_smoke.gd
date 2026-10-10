extends SceneTree
const Aim=preload("res://scripts/rendered_finger_pointer.gd")
var failures:Array=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
 checks+=1
 if not value:failures.append(message);push_error(message)
func run()->void:
 var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();root.add_child(rig)
 rig.get_node("PlayerBody").set_physics_process(false)
 rig.transform=Transform3D(Basis(Vector3.UP,.4),Vector3(2,0,3))
 var avatar=preload("res://scripts/avatar.gd").new();root.add_child(avatar);avatar.configure("rodian_male");avatar.set_tracking_mode(true)
 var pad=preload("res://scripts/xr_datapad.gd").new()
 var bag=preload("res://scripts/xr_inventory.gd").new()
 var services=preload("res://scripts/xr_services.gd").new()
 var voice=preload("res://scripts/xr_voice_controls.gd").new()
 for consumer in [pad,bag,services,voice]:consumer.rig=rig;consumer.avatar=avatar
 for side in ["left","right"]:
  var hand:XRController3D=rig.get_node(side.capitalize()+"Hand")
  var tracker:=XRControllerTracker.new();tracker.name=hand.tracker;tracker.type=XRServer.TRACKER_CONTROLLER;XRServer.add_tracker(tracker)
  var target:=Transform3D(Basis.from_euler(Vector3(.2,.3,.1)),Vector3(.2,1.2,-.4))
  tracker.set_pose("aim",target,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
  var first:=Aim.pose(avatar,side,rig,hand)
  check(first.source=="controller_aim" and Vector3(first.ray_origin).is_equal_approx((rig.global_transform*target).origin),side+" uses runtime aim in world coordinates")
  for trigger in [0.0,.2,.8,0.0]:
   tracker.set_input("trigger",trigger)
   for bone in ["index01","index02","ring01","ring02"]:
    var index:int=avatar.skeleton.find_bone(("l" if side=="left" else "r")+bone)
    avatar.skeleton.set_bone_pose_rotation(index,Quaternion(Vector3.UP,1.1+trigger))
   avatar.skeleton.force_update_all_bone_transforms()
   for consumer in [pad,bag,services,voice]:consumer.offhand="right" if side=="left" else "left"
   for value in [pad.pointing_pose(hand),bag.tool_pointer_pose(hand),services.finger_pose(hand),voice.finger_pose(hand)]:
    check(value==first,side+" every UI ignores finger articulation at trigger "+str(trigger))
  var pointer=hand.get_node("FunctionPointer");pointer._process(.016)
  check(pointer.global_position.is_equal_approx(first.ray_origin) and (-pointer.global_basis.z).is_equal_approx(first.direction),side+" menu and diegetic UI share exactly the same aim")
  check(pointer.show_laser==XRToolsFunctionPointer.LaserShow.HIDE,side+" menu laser is hidden")
  target.origin.x+=.15;target.basis=Basis(Vector3.UP,.5)*target.basis
  tracker.set_pose("aim",target,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
  var moved:=Aim.pose(avatar,side,rig,hand)
  check(Vector3(moved.ray_origin).distance_to(first.ray_origin)>.1 and Vector3(moved.direction).distance_to(first.direction)>.1,side+" wrist/controller motion remains responsive")
  tracker.invalidate_pose("aim")
  check(Aim.pose(avatar,side,rig,hand).source=="controller_grip",side+" missing aim uses stable XR Tools grip offset")
  XRServer.remove_tracker(tracker)
 var cue=preload("res://scripts/finger_pointer_visual.gd").new();root.add_child(cue);cue.update_pointer(Vector3.ZERO,{"world":Vector3(0,0,-.5)})
 check(cue.visible and cue.dot.visible and cue.get_child_count()==1,"Only the targeting dot is visible; white ray is hidden")
 check(Aim.pose(avatar,"left").is_empty(),"Missing tracked controller cannot fall back to articulated finger aim")
 for consumer in [pad,bag,services,voice]:consumer.free()
 cue.free();avatar.free();rig.free()
 print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"headless dummy","tracking":"mocked; no headset validation"}));quit(0 if failures.is_empty() else 1)
