extends RefCounted
## First eligible recipient along the independent medical aim, with world occlusion.
static func first(pose: Transform3D, source: Vector3, ability: Dictionary, candidates: Array, obstruction := INF) -> Dictionary:
	if ability.is_empty() or not pose.origin.is_finite() or not pose.basis.is_finite():return {}
	var selected: Dictionary={};var nearest:=obstruction
	var direction: Vector3=-pose.basis.z.normalized()
	for candidate: Dictionary in candidates:
		if not candidate.get("eligible",false) or source.distance_to(candidate.position)>float(ability.get("range_m",0)):continue
		for box: AABB in candidate.get("bounds",[]):
			var point: Variant=box.intersects_ray(pose.origin,direction)
			if not point is Vector3:continue
			var distance:=pose.origin.distance_to(point)
			if distance<0.03 or distance>=nearest:continue
			nearest=distance;selected=candidate
	return selected
