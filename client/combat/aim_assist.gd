extends RefCounted
## One bounded correction at launch. Never rotates tracked nodes or steers a bolt.
const FRESH_SECONDS := 0.15
const STALE_SECONDS := 0.5
const MAX_DEGREES := 0.5

static func eligible_profile(profile:Dictionary,shot:Dictionary)->bool:
	if not str(shot.get("ability_id","")).is_empty() or shot.has("aim_point"):return false
	if str(profile.get("delivery","bolt"))!="bolt" or str(profile.get("native_family",""))=="commando":return false
	return str(profile.get("class","")) in ["holdout","pistol","heavy_pistol","carbine","burst_carbine","rifle"] and not str(profile.get("template","")).contains("scatter")

static func angular_limit(age:float)->float:
	if not is_finite(age) or age<0:return 0
	return MAX_DEGREES*(1.0-clampf((age-FRESH_SECONDS)/(STALE_SECONDS-FRESH_SECONDS),0,1))

static func eligible_actor(actor:Variant)->bool:
	if not is_instance_valid(actor) or not actor is StaticBody3D or not actor.is_visible_in_tree() or not actor.has_method("is_targetable") or not actor.is_targetable():return false
	# A pet mount can keep its native identity/collider while the ride layer
	# suppresses this visual. Out-of-cell actors similarly lose combat collision.
	if (actor.collision_layer & 8)==0:return false
	var visual:Variant=actor.get("visual")
	if not is_instance_valid(visual) or not visual is Node3D or not visual.is_visible_in_tree():return false
	var record:Variant=actor.get("record")
	return record is Dictionary and record.get("kind","")=="creature" and record.get("relation","") in ["hostile","attackable"] and not record.get("dead",false) and not record.get("incapacitated",false) and not record.get("pet",false)

static func clamp_point(point:Vector3,half:Vector3)->Vector3:
	return point.clamp(-half,half)

static func near_body_point(pose:Transform3D,collider:CollisionShape3D,maximum:float)->Vector3:
	# Work in the actual oriented target collider, not an enlarged world AABB.
	# Distance from a line segment to a convex box is convex: bounded minimization
	# finds the closest surface without enlarging the target's hit volume.
	var inverse:=collider.global_transform.affine_inverse()
	var origin:Vector3=inverse*pose.origin
	var direction:Vector3=inverse.basis*(-pose.basis.z.normalized())
	var half:Vector3=(collider.shape as BoxShape3D).size*.5
	var low:=0.0;var high:=maximum
	for step in range(32):
		var a:=lerpf(low,high,1.0/3.0);var b:=lerpf(low,high,2.0/3.0)
		var pa:=origin+direction*a;var pb:=origin+direction*b
		if pa.distance_squared_to(clamp_point(pa,half))<pb.distance_squared_to(clamp_point(pb,half)):high=b
		else:low=a
	var point:=clamp_point(origin+direction*((low+high)*.5),half)
	# Aim just inside the body, avoiding a numerically tangent/grazing ray.
	point=point.move_toward(Vector3.ZERO,minf(.02,half.length()*.05))
	return collider.global_transform*point

func correct(pose:Transform3D,profile:Dictionary,shot:Dictionary,candidates:Array,trace:Callable)->Dictionary:
	if not eligible_profile(profile,shot) or not trace.is_valid() or not pose.origin.is_finite() or not pose.basis.is_finite():return {}
	var maximum:=minf(128,float(shot.get("range",profile.get("core3",{}).get("maxRange",0))))
	if not is_finite(maximum) or maximum<=0:return {}
	var forward:Vector3=-pose.basis.z.normalized()
	var original:Dictionary=trace.call(pose.origin,pose.origin+forward*maximum)
	if not original.get("complete",false):return {}
	# A shot already hitting any character retains that exact target and aim.
	if original.get("hit",false) and is_instance_valid(original.get("collider")) and original.collider.has_method("is_targetable"):return {}
	var best:Dictionary={};var best_angle:=INF;var best_distance:=INF
	for row:Dictionary in candidates:
		var limit:=angular_limit(float(row.get("age_seconds",INF)))
		var actor:Variant=row.get("actor")
		if limit<=0 or not eligible_actor(actor):continue
		var collider:Variant=actor.get("collider")
		if not collider is CollisionShape3D or collider.disabled or not collider.shape is BoxShape3D:continue
		var center:Vector3=collider.global_position-pose.origin
		var half:Vector3=collider.shape.size*.5
		var radius:float=(collider.global_basis*Vector3(half.x,0,0)).length()+(collider.global_basis*Vector3(0,half.y,0)).length()+(collider.global_basis*Vector3(0,0,half.z)).length()
		var along:float=center.dot(forward)
		if along+radius<=0 or along-radius>maximum or (center-forward*along).length()>radius+tan(deg_to_rad(limit))*maxf(0,along+radius):continue
		var point:=near_body_point(pose,collider,maximum)
		var delta:=point-pose.origin;var distance:=delta.length()
		if distance<.2 or distance>maximum or delta.dot(forward)<=0:continue
		var direction:=delta/distance
		var angle:=rad_to_deg(forward.angle_to(direction))
		if angle<=.0001 or angle>limit or angle>best_angle or (is_equal_approx(angle,best_angle) and distance>=best_distance):continue
		if original.get("hit",false) and pose.origin.distance_to(original.get("position",pose.origin))<distance:continue
		var hit:Dictionary=trace.call(pose.origin,point+direction*.03)
		if not hit.get("complete",false) or not hit.get("hit",false) or hit.get("collider")!=actor:continue
		var corrected:=pose
		corrected.basis=Basis.looking_at(direction,Vector3.RIGHT if absf(direction.y)>.99 else Vector3.UP)
		best={"pose":corrected,"degrees":angle,"target_id":str(actor.record.get("id","")),"age_seconds":float(row.age_seconds)}
		best_angle=angle;best_distance=distance
	return best
