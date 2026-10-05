extends RefCounted
## Source forearm attachment: recover wrist axial roll discarded by two-bone IK.
## Wrist flexion cannot move the anchor or tilt its lengthwise axis.
var cached_skeleton := 0
var cached_side := ""
var bone := -1
var local_frame := Transform3D.IDENTITY
var wrist_bone := -1
var wrist_rest_relative := Quaternion.IDENTITY
func resolve(skeleton: Skeleton3D, side: String, fallback: Transform3D) -> Transform3D:
	if not is_instance_valid(skeleton):return fallback_pose(side,fallback)
	if cached_skeleton!=skeleton.get_instance_id() or cached_side!=side:
		cached_skeleton=skeleton.get_instance_id();cached_side=side;bone=-1
		var prefix:="l" if side=="left" else "r"
		var wrist:=skeleton.find_bone(prefix+"wrist")
		wrist_bone=wrist
		var index:=skeleton.find_bone(prefix+"index01")
		var ring:=skeleton.find_bone(prefix+"ring01")
		for name in [prefix+"forearm",prefix+"elbow"]:
			bone=skeleton.find_bone(name)
			if bone>=0:break
		if bone<0 and wrist>=0:bone=skeleton.get_bone_parent(wrist)
		if wrist>=0 and index>=0 and ring>=0 and bone>=0:
			var w:=skeleton.get_bone_global_rest(wrist)
			var arm:=skeleton.get_bone_global_rest(bone)
			var i:=skeleton.get_bone_global_rest(index).origin
			var r:=skeleton.get_bone_global_rest(ring).origin
			var across:=(r-i).normalized()
			var hand_up:=(w.origin-(i+r)*.5).slide(across).normalized()
			var up:=(arm.origin-w.origin).normalized()
			if up.length_squared()<.5:up=hand_up
			var normal:=(hand_up.cross(across)*(1.0 if side=="left" else -1.0)).slide(up).normalized()
			var along:=up*(-1.0 if side=="left" else 1.0)
			var basis:=Basis(along,normal.cross(along).normalized(),normal)
			# Distal forearm, kept proximal enough that the whole panel clears the joint.
			var anchor:=w.origin+up*minf(.105,w.origin.distance_to(arm.origin)*.45)
			local_frame=arm.affine_inverse()*Transform3D(basis,anchor)
			wrist_rest_relative=(arm.basis.inverse()*w.basis).get_rotation_quaternion()
		else:bone=-1
	if bone<0:return fallback_pose(side,fallback)
	var result:=skeleton.global_transform*skeleton.get_bone_global_pose(bone)*local_frame
	result=result.orthonormalized()
	# Native IK solves elbow swing but places all tracked pronation in the wrist.
	# Swing/twist decomposition removes hand flexion from that relative rotation.
	var arm_pose:=skeleton.get_bone_global_pose(bone)
	var wrist_pose:=skeleton.get_bone_global_pose(wrist_bone)
	var relative: Quaternion=(arm_pose.basis.orthonormalized().inverse()*wrist_pose.basis.orthonormalized()).get_rotation_quaternion()
	var delta: Quaternion=relative*wrist_rest_relative.inverse()
	var axis:=local_frame.basis.x.normalized()
	var projected:=axis*Vector3(delta.x,delta.y,delta.z).dot(axis)
	var twist:=Quaternion(projected.x,projected.y,projected.z,delta.w)
	if twist.length_squared()>0.00001:
		twist=twist.normalized()
		var rotated:=Basis(twist)*local_frame.basis
		result.basis=(skeleton.global_basis*arm_pose.basis*rotated).orthonormalized()
	result.origin+=result.basis.z*.085
	return result
static func fallback_pose(side: String, grip: Transform3D) -> Transform3D:
	var pose:=grip.orthonormalized()
	var normal:=pose.basis.x*(1.0 if side=="left" else -1.0)
	var along:=pose.basis.y*(-1.0 if side=="left" else 1.0)
	return Transform3D(Basis(along,normal.cross(along).normalized(),normal),pose.origin+pose.basis.y*.16+normal*.085)
