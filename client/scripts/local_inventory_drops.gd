extends Node3D
## Recoverable session-local presentation. Core3 ownership never changes here.
## Every proxy reserves its original inventory ID until remove()/clear().
const MAX_DROPS := 32
const DISPLAY_EXTENT := 0.28
const DROP_LAYER := 32
const WORLD_MASK := 7
const REMOTE_PICKUP_RANGE := 2.0
const REMOTE_PICKUP_CONE := 0.94 # Approximately20 degrees from deliberate hand aim.
var assets: RefCounted
var records: Dictionary = {}
var report := {"created":0,"removed":0,"rejected":0,"last_error":"","ownership":"CoreCU unchanged; session-local proxy and reserved source slot"}

func configure(source_assets: RefCounted) -> void:
	clear()
	assets=source_assets

func reject(reason: String) -> bool:
	report.rejected+=1
	report.last_error=reason
	return false

func drop(item: Dictionary, pose: Transform3D) -> bool:
	var id:=str(item.get("id",""))
	var template:=str(item.get("template",item.get("shared_template","")))
	if id.is_empty(): return reject("Missing authoritative item ID")
	if records.has(id): return reject("Item already has a session-local drop")
	if records.size()>=MAX_DROPS: return reject("Session-local drop limit reached")
	if not is_inside_tree(): return reject("Drop presentation has no active world")
	if not pose.is_finite() or pose.basis.determinant()<0.000001:
		return reject("Invalid drop transform")
	if assets==null or not assets.has_method("descriptor") or not assets.has_method("instance"):
		return reject("Original inventory assets unavailable")
	var source: Dictionary=assets.call("descriptor",template)
	if source.get("status","")!="ready": return reject("Original item appearance unavailable")
	var customization: Dictionary=item.get("customization",{}) if item.get("customization",{}) is Dictionary else {}
	var visual: MeshInstance3D=assets.call("instance",template,DISPLAY_EXTENT,customization)
	if visual==null or visual.mesh==null:
		if is_instance_valid(visual): visual.free()
		return reject("Original item model failed to load")
	var bounds: AABB=visual.transform*visual.mesh.get_aabb()
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.length_squared()<=0.000001:
		visual.free()
		return reject("Original item model has invalid fitted bounds")
	var body:=RigidBody3D.new()
	body.name="LocalInventoryDrop_"+id.validate_node_name()
	body.collision_layer=DROP_LAYER
	body.collision_mask=WORLD_MASK
	body.continuous_cd=true
	body.can_sleep=true
	body.mass=0.25
	body.linear_damp=0.15
	body.angular_damp=0.3
	var material:=PhysicsMaterial.new()
	material.friction=0.8
	material.bounce=0.0
	body.physics_material_override=material
	var shape:=BoxShape3D.new()
	# Thin authored geometry still needs a nonzero physical proxy thickness.
	shape.size=bounds.size.max(Vector3.ONE*0.012)
	var collision:=CollisionShape3D.new()
	collision.shape=shape
	collision.position=bounds.get_center()
	body.add_child(collision)
	body.add_child(visual)
	body.set_meta("inventory_object_id",id)
	body.set_meta("source_template",template)
	body.set_meta("session_local_inventory_proxy",true)
	add_child(body)
	body.global_transform=Transform3D(pose.basis.orthonormalized(),pose.origin)
	records[id]={"id":id,"item":item.duplicate(true),"body":body,"visual":visual,"collision":collision,"source_bounds":bounds}
	report.created+=1
	report.last_error=""
	return true

func nearest(world_position: Vector3, radius: float=0.22) -> Dictionary:
	if not world_position.is_finite() or not is_finite(radius) or radius<0.0: return {}
	var selected: Dictionary={}
	var closest:=radius
	for id: String in records:
		var record: Dictionary=records[id]
		if record.get("slicing_reserved",false):continue
		var body: RigidBody3D=record.body
		if not is_instance_valid(body): continue
		var distance:=body.global_position.distance_to(world_position)
		if distance>closest: continue
		closest=distance
		selected={"id":id,"item":record.item.duplicate(true),"body":body,"position":body.global_position,"distance":distance}
	return selected

func pickup_candidate(hand_pose: Transform3D) -> Dictionary:
	# Called only on a fresh intentional grip by the inventory controller.
	# Close hand grabs need no aim cone; remote grabs need aim AND clear world LOS.
	if not is_inside_tree() or not hand_pose.is_finite() or absf(hand_pose.basis.determinant())<0.000001: return {}
	var forward := -hand_pose.basis.z.normalized()
	var selected: Dictionary = {}
	var best_score := INF
	for id: String in records:
		var record: Dictionary=records[id]
		if record.get("slicing_reserved",false):continue
		var body: RigidBody3D=record.body
		if not is_instance_valid(body): continue
		var offset := body.global_position-hand_pose.origin
		var distance := offset.length()
		if distance>REMOTE_PICKUP_RANGE: continue
		var alignment := forward.dot(offset/distance) if distance>0.001 else 1.0
		if distance>0.22 and alignment<REMOTE_PICKUP_CONE: continue
		var query := PhysicsRayQueryParameters3D.create(hand_pose.origin,body.global_position,WORLD_MASK)
		query.hit_from_inside=true
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		# Preserve physical near-grab priority, then choose the most directly aimed item.
		var score := distance if distance<=0.22 else 1.0+(1.0-alignment)*8.0+distance*0.05
		if score>=best_score: continue
		best_score=score
		selected={"id":id,"item":record.item.duplicate(true),"body":body,"position":body.global_position,"distance":distance,"remote_grab":distance>0.22}
	return selected

func lock_for_slicing(id:String,pose:Transform3D)->bool:
	if not records.has(id) or not pose.is_finite():return false
	var record:Dictionary=records[id]
	if not is_instance_valid(record.body):return false
	record.slicing_reserved=true
	record.body.freeze=true;record.body.linear_velocity=Vector3.ZERO;record.body.angular_velocity=Vector3.ZERO
	record.body.collision_layer=0;record.body.collision_mask=0;record.body.global_transform=pose
	return true

func remove(id: String) -> void:
	if not records.has(id): return
	var body: RigidBody3D=records[id].body
	if is_instance_valid(body):
		body.freeze=true
		body.collision_layer=0
		body.collision_mask=0
		body.queue_free()
	records.erase(id)
	report.removed+=1

func clear() -> void:
	for id: String in records.keys(): remove(id)

func reserved_ids() -> PackedStringArray:
	return PackedStringArray(records.keys())

func statistics() -> Dictionary:
	var state:=report.duplicate(true)
	state["active"]=records.size()
	state["max_drops"]=MAX_DROPS
	state["reserved_ids"]=reserved_ids()
	state["world_collision_mask"]=WORLD_MASK
	state["drop_collision_layer"]=DROP_LAYER
	return state

func _exit_tree() -> void:
	clear()
