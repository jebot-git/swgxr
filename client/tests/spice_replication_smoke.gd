extends SceneTree
## Spice renders locally; peers receive physical targets, independent of visual IK.
const Sync=preload("res://multiplayer/client_sync.gd")
const State=preload("res://multiplayer/replication_state.gd")
class Body extends Node3D:
	var feedback=preload("res://combat/player_feedback.gd").new()
class Avatar extends Node3D:
	var skeleton:=Skeleton3D.new()
	var camera:XRCamera3D
	var head_rest:=Transform3D(Basis(Vector3.UP,.2),Vector3(0,1.6,0))
	var grip_offsets:Dictionary={"left":Transform3D(Basis(Vector3.RIGHT,.3),Vector3(.02,-.03,.01)),"right":Transform3D(Basis(Vector3.RIGHT,-.3),Vector3(-.02,-.03,.01))}
class Host extends Node3D:
	var xr_requested:=true
	var xr_focused:=true
	var tracked_avatar:=Avatar.new()
	var player:=Body.new()
	var stage:=Node3D.new()
	var xr_origin:=XROrigin3D.new()
	func source_position_at(p:Vector3)->Vector3:
		var local:=stage.to_local(p)
		return Vector3(local.x,local.y,-local.z)
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app)
	for node in [app.tracked_avatar,app.player,app.stage,app.xr_origin]:app.add_child(node)
	app.stage.rotation.y=.5;app.stage.position=Vector3(10,2,-4)
	var avatar:=app.tracked_avatar;avatar.add_child(avatar.skeleton)
	avatar.camera=XRCamera3D.new();app.xr_origin.add_child(avatar.camera)
	avatar.camera.transform=Transform3D(Basis(Vector3.UP,.4),Vector3(0,1.65,-.1))
	for name in ["head","lwrist","rwrist"]:
		avatar.skeleton.add_bone(name)
		avatar.skeleton.set_bone_pose_position(avatar.skeleton.find_bone(name),Vector3(8,8,8))
	var head_tracker:=XRPositionalTracker.new();head_tracker.name="head";head_tracker.type=XRServer.TRACKER_HEAD
	head_tracker.set_pose("default",avatar.camera.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker)
	var trackers:Array=[head_tracker]
	for side in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.name=side+"_hand";tracker.type=XRServer.TRACKER_CONTROLLER
		tracker.hand=XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		tracker.set_pose("grip",Transform3D(Basis(Vector3.RIGHT,.4),Vector3(-.3 if side=="left" else .3,1.3,-.4)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker);trackers.append(tracker)
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=tracker.name;controller.pose="grip";app.xr_origin.add_child(controller)
	var sync:=Sync.new();root.add_child(sync);sync.app=app;sync.set_process(false)
	await process_frame
	for effect in [["yarrock","withdrawal"],["muon_gold","withdrawal"],["booster_blue","active"],["booster_blue","withdrawal"]]:
		app.player.feedback.spice.observe(preload("res://tests/spice_smoke.gd").envelope(effect[0],effect[1]))
		var packet:=sync.tracking()
		check(packet.size()==3,"All tracked targets exported for "+str(effect))
		for key in ["head","left_hand","right_hand"]:
			var expected:Transform3D
			if key=="head":expected=avatar.camera.global_transform;expected.basis=expected.basis.orthonormalized()*avatar.head_rest.basis
			else:
				var side:="left" if key=="left_hand" else "right"
				expected=app.xr_origin.get_node(side.capitalize()+"Hand").global_transform*avatar.grip_offsets[side]
			check(State.point(packet[key].position).is_equal_approx(app.source_position_at(expected.origin)) and State.world_rotation(packet[key].rotation,app.stage.global_basis).is_equal_approx(expected.basis),"Peer "+key+" uses raw tracked pose with original source offsets: "+str(effect))
		avatar.skeleton.set_bone_pose_position(2,Vector3(-8,-8,-8))
		check(sync.tracking()==packet,"Virtual gunhand lag/aim/tremor cannot affect peer packet")
	trackers[2].invalidate_pose("grip")
	check(not sync.tracking().has("right_hand"),"Lost physical tracking immediately removes peer hand despite existing visual IK")
	app.player.feedback.spice.reset()
	var ordinary:=sync.tracking()
	check(State.point(ordinary.head.position).is_equal_approx(app.source_position_at(Vector3(8,8,8))),"Unaffected phases preserve existing source skeleton replication")
	for tracker in trackers:XRServer.remove_tracker(tracker)
	sync.free();app.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"renderer":"dummy","tracking":"mocked","headset_validated":false}));quit(0 if errors.is_empty() else 1)
