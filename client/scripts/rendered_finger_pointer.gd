extends RefCounted
## One visual pointer origin for every diegetic interface. Original SWG fingers have
## two joints; cache their terminal skin extent instead of inventing a third joint.
static var endpoints: Dictionary={}
static var click_rays: Dictionary={}
static func pose(avatar: Node3D, side: String, rig: XROrigin3D=null, controller: XRController3D=null, stabilize_click:=true) -> Dictionary:
	if is_instance_valid(avatar):
		var skeleton: Skeleton3D=avatar.get("skeleton")
		if is_instance_valid(skeleton):
			var prefix:="l" if side=="left" else "r"
			var first:=skeleton.find_bone(prefix+"index01")
			var last:=skeleton.find_bone(prefix+"index02")
			if first>=0 and last>=0:
				var source_avatar: Node3D=avatar
				if avatar.get("avatar") is Node3D:source_avatar=avatar.get("avatar")
				var key:="%s:%s"%[source_avatar.get("race_id"),side]
				if not endpoints.has(key):endpoints[key]=skin_endpoint(source_avatar,skeleton,first,last)
				var endpoint: Vector3=endpoints[key]
				var distal:=skeleton.global_transform*skeleton.get_bone_global_pose(last)
				var result:Dictionary={"tip":distal*endpoint,"direction":(distal.basis*endpoint).normalized(),"source":"rendered_skin","bone":last,"local_tip":endpoint}
				var wrist:=skeleton.find_bone(prefix+"wrist")
				if stabilize_click and is_instance_valid(controller) and wrist>=0:
					return stabilize(result,skeleton.global_transform*skeleton.get_bone_global_pose(wrist),controller.get_float("trigger"),str(avatar.get_instance_id())+":"+side)
				return result
	if is_instance_valid(rig):
		var tracker:=XRServer.get_tracker("/user/hand_tracker/"+side) as XRHandTracker
		if tracker!=null and tracker.has_tracking_data:
			var tip_id:=XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
			var distal_id:=XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL
			if tracker.get_hand_joint_flags(tip_id)&XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID and tracker.get_hand_joint_flags(distal_id)&XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID:
				var joint:=XRPose.new();joint.transform=tracker.get_hand_joint_transform(tip_id)
				var tip: Vector3=(rig.global_transform*joint.get_adjusted_transform()).origin
				joint.transform=tracker.get_hand_joint_transform(distal_id)
				var distal: Vector3=(rig.global_transform*joint.get_adjusted_transform()).origin
				if tip.distance_squared_to(distal)>.000001:return {"tip":tip,"direction":(tip-distal).normalized(),"source":"optical"}
	if is_instance_valid(controller):
		var tracker=XRServer.get_tracker(controller.tracker)
		var aim: XRPose=tracker.get_pose("aim") if tracker!=null else null
		if aim!=null and aim.has_tracking_data and is_instance_valid(rig):
			var target: Transform3D=rig.global_transform*aim.get_adjusted_transform()
			return {"tip":target.origin,"direction":-target.basis.z,"source":"controller_aim"}
		return {"tip":controller.global_position,"direction":-controller.global_basis.z,"source":"controller"}
	return {}
static func stabilize(pointer:Dictionary, wrist:Transform3D, trigger:float, key:String)->Dictionary:
	# Aim from the last extended visual finger in wrist space. Curl changes the
	# visible beam origin only; wrist translation/rotation continues to aim freely.
	# Consumers raycast ray_origin, then draw from the actual skinned fingertip.
	var now:=Time.get_ticks_msec()
	if click_rays.size()>32:click_rays.clear()
	var record:Dictionary=click_rays.get(key,{})
	if trigger<.05 or record.is_empty() or now-int(record.get("time",0))>500:
		record={"origin":wrist.affine_inverse()*Vector3(pointer.tip),"direction":wrist.basis.inverse()*Vector3(pointer.direction)}
	record.time=now;click_rays[key]=record
	var result:=pointer.duplicate()
	result.ray_origin=wrist*Vector3(record.origin)
	result.direction=(wrist.basis*Vector3(record.direction)).normalized()
	result.click_stabilized=trigger>=.05
	return result

static func skin_endpoint(avatar: Node3D,skeleton: Skeleton3D,first: int,last: int) -> Vector3:
	var rest:=skeleton.get_bone_global_rest(last)
	var direction: Vector3=(rest.origin-skeleton.get_bone_global_rest(first).origin).normalized()
	var extent:=0.0
	var records: Variant=avatar.get("loaded_parts")
	if records is Array:
		for record: Dictionary in records:
			if record.get("scope","")!="body":continue
			for part: Dictionary in record.get("model",{}).get("parts",[]):
				for surface: Dictionary in part.get("mesh",{}).get("surfaces",[]):
					var vertices: Array=surface.get("vertices",[])
					var bones: Array=surface.get("bones",[])
					var weights: Array=surface.get("weights",[])
					var count:=vertices.size()/3
					var stride:=bones.size()/maxi(1,count)
					for vertex in range(count):
						var influence:=0.0
						for j in range(stride):
							if int(bones[vertex*stride+j])==last:influence+=float(weights[vertex*stride+j])
						if influence<.5:continue
						var point:=Vector3(vertices[vertex*3],vertices[vertex*3+1],vertices[vertex*3+2])
						extent=maxf(extent,(point-rest.origin).dot(direction))
	# Unsupported/unskinned models fall back to the measured source phalanx length.
	if extent<.001:extent=rest.origin.distance_to(skeleton.get_bone_global_rest(first).origin)
	return rest.basis.inverse()*direction*extent
