extends RefCounted
## Ray tests stay in each source mesh's local frame, not an enlarged world box.
static func first(head:Transform3D,source:Vector3,candidates:Array,obstruction:float=INF)->Dictionary:
	var selected:Dictionary={};var nearest:=minf(8.0,obstruction)
	if not head.origin.is_finite() or not head.basis.is_finite():return {}
	for row:Dictionary in candidates:
		if not row.get("eligible",false) or source.distance_to(row.pose.origin)>8.0:continue
		var inverse:Transform3D=row.pose.affine_inverse()
		var origin:Vector3=inverse*head.origin;var direction:Vector3=inverse.basis*(-head.basis.z)
		var bounds:AABB=row.bounds.grow(.07)
		var point:Variant=bounds.intersects_ray(origin,direction)
		if not point is Vector3:continue
		var distance:=head.origin.distance_to(row.pose*point)
		if distance>=.03 and distance<nearest:nearest=distance;selected=row
	return selected
static func head_anchor(actor:Node3D)->Variant:
	if not is_instance_valid(actor) or not is_instance_valid(actor.get("visual")):return null
	var skeleton:Skeleton3D=actor.visual.get("skeleton")
	if not is_instance_valid(skeleton):return null
	var index:=-1
	for name in ["head","head_base","fambaa_head"]:
		index=skeleton.find_bone(name)
		if index>=0:break
	return skeleton.global_transform*skeleton.get_bone_global_pose(index).origin if index>=0 else null
static func fist(joints:Dictionary,fallback:Dictionary)->float:
	if joints.is_empty():return minf(float(fallback.get("grip",0)),float(fallback.get("trigger",0)))
	var curl:=1.0
	for finger in ["index","ring"]:
		var a:Vector3=joints.get(finger+"_proximal",Vector3.ZERO);var b:Vector3=joints.get(finger+"_intermediate",Vector3.ZERO);var c:Vector3=joints.get(finger+"_distal",Vector3.ZERO);var d:Vector3=joints.get(finger+"_tip",Vector3.ZERO)
		if a.distance_to(b)<.001 or b.distance_to(c)<.001 or c.distance_to(d)<.001:return 0
		var bend:=acos(clampf((b-a).normalized().dot((c-b).normalized()),-1,1))+acos(clampf((c-b).normalized().dot((d-c).normalized()),-1,1))
		curl=minf(curl,clampf(bend/2.2,0,1))
	return curl
