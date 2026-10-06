extends RefCounted
const Hands=preload("res://scripts/tracked_hand_input.gd")
static func is_kit(item:Dictionary)->bool:
	var template:=str(item.get("template",item.get("shared_template",""))).replace("/shared_","/")
	return template in ["object/tangible/scout/camokit/camokit_corellia.iff","object/tangible/scout/camokit/camokit_dantooine.iff","object/tangible/scout/camokit/camokit_dathomir.iff","object/tangible/scout/camokit/camokit_endor.iff","object/tangible/scout/camokit/camokit_lok.iff","object/tangible/scout/camokit/camokit_naboo.iff","object/tangible/scout/camokit/camokit_rori.iff","object/tangible/scout/camokit/camokit_talus.iff","object/tangible/scout/camokit/camokit_tatooine.iff","object/tangible/scout/camokit/camokit_yavin.iff"]
static func curl(joints:Dictionary,finger:String)->float:
	var a:Vector3=joints.get(finger+"_proximal",Vector3.ZERO);var b:Vector3=joints.get(finger+"_intermediate",Vector3.ZERO);var c:Vector3=joints.get(finger+"_distal",Vector3.ZERO);var d:Vector3=joints.get(finger+"_tip",Vector3.ZERO)
	if a.distance_to(b)<.001 or b.distance_to(c)<.001 or c.distance_to(d)<.001:return NAN
	return clampf((acos(clampf((b-a).normalized().dot((c-b).normalized()),-1,1))+acos(clampf((c-b).normalized().dot((d-c).normalized()),-1,1)))/2.2,0,1)
static func pointing(joints:Dictionary,input:Dictionary)->bool:
	if joints.is_empty():return float(input.get("trigger",1))<.2 and float(input.get("grip",0))>.65
	return curl(joints,"index")<.3 and curl(joints,"ring")>.6
static func target(ray:Dictionary,candidates:Array,source:Vector3,maximum:float,obstruction:=INF)->String:
	var nearest:=minf(maximum,obstruction);var selected:=""
	if not ray.get("tip") is Vector3 or not ray.get("direction") is Vector3:return ""
	for row:Dictionary in candidates:
		if not row.get("eligible",false) or source.distance_to(row.pose.origin)>maximum:continue
		var inverse:Transform3D=row.pose.affine_inverse();var point:Variant=row.bounds.grow(.05).intersects_ray(inverse*ray.tip,inverse.basis*Vector3(ray.direction))
		if not point is Vector3:continue
		var distance:float=Vector3(ray.tip).distance_to(row.pose*point)
		if distance>.02 and distance<nearest:nearest=distance;selected=str(row.id)
	return selected
