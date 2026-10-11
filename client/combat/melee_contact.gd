extends RefCounted
## Select against the presented original collider, then stop at world geometry.
## A physical swing still owns activation; this replaces delayed server selection.
static func pick(owner:Node3D,actors:Dictionary,session:String,pose:Transform3D,reach:float)->Dictionary:
	var candidates:Array=[];var forward:Vector3=-pose.basis.z.normalized()
	for id:String in actors:
		var actor:Variant=actors[id]
		if not is_instance_valid(actor) or actor.session_id!=session or not actor.is_targetable() or not actor.record.get("attackable",false):continue
		if float(actor.record.get("observation_at",0))<=0:continue
		var shape:CollisionShape3D=actor.get("collider")
		if not is_instance_valid(shape) or shape.disabled or not shape.shape is BoxShape3D:continue
		var along:=clampf((shape.global_position-pose.origin).dot(forward),0,reach)
		var aim:=pose.origin+forward*along
		var half:Vector3=shape.shape.size*.5
		var point:Vector3=shape.to_global(shape.to_local(aim).clamp(-half,half))
		var delta:=point-pose.origin;var distance:=delta.length();along=delta.dot(forward)
		if along<=0 or distance>reach+.35 or (delta-forward*along).length()>.15+along*.26794919243:continue
		candidates.append({"target_id":id,"actor":actor,"point":point,"distance":distance})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	for row:Dictionary in candidates:
		var query:=PhysicsRayQueryParameters3D.create(pose.origin,row.point+(row.point-pose.origin).normalized()*.02,1|8)
		var hit:Dictionary=owner.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider!=row.actor:continue
		row.point=hit.position
		return row
	return {}
