extends SceneTree
class MockRuntime extends XRInterfaceExtension:
	func _get_name() -> StringName: return &"PortalTrackingRegression"
	func _is_initialized() -> bool: return true
	func _get_view_count() -> int: return 2
	func _get_tracking_status() -> XRInterface.TrackingStatus: return XRInterface.XR_UNKNOWN_TRACKING
	func _get_transform_for_view(view: int, cam_transform: Transform3D) -> Transform3D:
		return cam_transform * Transform3D(Basis.IDENTITY, Vector3(-0.032 if view==0 else 0.032,1.7,0))
	func _get_projection_for_view(_view: int, aspect: float, z_near: float, z_far: float) -> PackedFloat64Array:
		var projection:=Projection.create_perspective(100,aspect,z_near,z_far)
		var values:=PackedFloat64Array()
		for column in range(4):
			for row in range(4): values.append(projection[column][row])
		return values
class Stage extends Node3D:
	var observer: Node3D
	var current_cell: Dictionary={}
	func advance_world(_from:Vector3,_to:Vector3,_state:Dictionary)->Dictionary:return {}
var errors:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	if not value: errors.append(message);push_error(message)
func run()->void:
	var previous:=XRServer.primary_interface
	var runtime:=MockRuntime.new()
	XRServer.add_interface(runtime)
	XRServer.primary_interface=runtime
	var tracker:=XRPositionalTracker.new()
	tracker.name=&"head"
	tracker.type=XRServer.TRACKER_HEAD
	tracker.set_pose(&"default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	var origin:=XROrigin3D.new()
	root.add_child(origin)
	var head:=XRCamera3D.new()
	origin.add_child(head)
	var stage:=Stage.new()
	stage.observer=origin
	root.add_child(stage)
	var visibility=load("res://scripts/portal_visibility.gd").new()
	visibility.stage=stage;visibility.head=head
	check(runtime.get_tracking_status()==XRInterface.XR_UNKNOWN_TRACKING,"Mock must reproduce unreliable generic tracking status")
	var views:Array=visibility.collect_culling_views()
	check(views.size()==2 and visibility.bounds_complete,"Valid tracked head must enable both runtime eye views despite generic UNKNOWN status")
	check(visibility.view_telemetry.fail_open_reason.is_empty(),"Healthy tracked pose reported failure")
	var valid_report:Dictionary=visibility.view_telemetry.duplicate()
	tracker.invalidate_pose(&"default")
	check(visibility.collect_culling_views().is_empty() and not visibility.bounds_complete,"Invalidated tracking must fail open")
	check(visibility.view_telemetry.fail_open_reason=="head_pose_invalidated","Missing invalidation reason telemetry")
	for confidence in [XRPose.XR_TRACKING_CONFIDENCE_NONE,XRPose.XR_TRACKING_CONFIDENCE_LOW]:
		tracker.set_pose(&"default",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,confidence)
		check(visibility.collect_culling_views().is_empty(),"Uncertain pose must fail open")
	tracker.set_pose(&"default",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	check(visibility.collect_culling_views().size()==2 and visibility.bounds_complete,"Recovered high-confidence tracking must resume culling")
	XRServer.remove_tracker(tracker)
	check(visibility.collect_culling_views().is_empty() and visibility.view_telemetry.fail_open_reason=="head_pose_missing","Absent head tracker must fail open with reason")
	XRServer.primary_interface=previous
	XRServer.remove_interface(runtime)
	var result:Dictionary={"test":"portal_xr_pose_validity","passed":errors.is_empty(),"errors":errors,"generic_status":"UNKNOWN","valid_pose":valid_report,"runtime_views":views.size(),"tracking_loss_and_recovery":errors.is_empty(),"gpu_tested":false,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/portal-xr-tracking-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	visibility.free();stage.free();origin.free()
	quit(0 if errors.is_empty() else 1)
