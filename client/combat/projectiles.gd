extends Node3D
## Swept local presentation. Core3 actors emit contact evidence, never local damage.
signal impact(event: Dictionary)
signal authoritative_contact(shot: Dictionary, target: Dictionary, position: Vector3, normal: Vector3, distance: float)
const WeaponState = preload("res://combat/weapon_state.gd")
var bolts: Array[Dictionary] = []
var excluded: Array[RID] = []
var rng := RandomNumberGenerator.new()
var collision_mask := 15
var effects: Node3D
var collision_stage: Node3D
var source_actor: CharacterBody3D
var actor_state: Dictionary = {}
var actor_previous_feet := Vector3.INF
var visual_allocated := 0
var max_visuals := 256
var visual_drops := 0
var incomplete_queries := 0
var source_cell := ""
var last_incomplete_reason := ""
var incomplete_reasons: Dictionary = {}
var fired_presentations := 0

func record_incomplete(result: Dictionary) -> void:
	incomplete_queries += 1
	last_incomplete_reason = str(result.get("reason", "unknown_coverage"))
	incomplete_reasons[last_incomplete_reason] = int(incomplete_reasons.get(last_incomplete_reason, 0)) + 1

func statistics() -> Dictionary:
	return {"active_bolts":bolts.size(), "fired_presentations":fired_presentations, "incomplete_queries":incomplete_queries, "last_incomplete_reason":last_incomplete_reason, "incomplete_reasons":incomplete_reasons.duplicate()}

func configure_collision(stage: Node3D, actor: CharacterBody3D = null) -> void:
	collision_stage = stage
	source_actor = actor
	actor_state = {}
	actor_previous_feet = Vector3.INF

func actor_cell_at(grip: Vector3) -> Variant:
	if not is_instance_valid(collision_stage): return ""
	if not is_instance_valid(source_actor): return null
	var feet := source_actor.global_position
	if collision_stage.observer == source_actor:
		actor_state = collision_stage.current_cell.duplicate()
	elif not actor_previous_feet.is_finite() or feet.distance_to(actor_previous_feet)>3.0:
		actor_state = collision_stage.classify_world(feet)
	else:
		actor_state = collision_stage.advance_world(actor_previous_feet+Vector3.UP*0.5,feet+Vector3.UP*0.5,actor_state)
	actor_previous_feet = feet
	var hand_state: Dictionary = collision_stage.advance_world(feet+Vector3.UP*0.5,grip,actor_state)
	return str(hand_state.get("cell_id",""))

func acquire_visual(weapon_id: String, pose: Transform3D) -> int:
	if effects==null or visual_allocated>=max_visuals:
		visual_drops += 1
		return -1
	var weapon: Dictionary = effects.assets.catalog.weapons.get(weapon_id,{})
	var handle: int = effects.create_tracer(str(weapon.get("projectile","")),pose)
	if handle<0: visual_drops += 1
	else: visual_allocated += 1
	return handle

func release_visual(handle: int) -> void:
	if handle<0: return
	if effects!=null: effects.release_tracer(handle)
	visual_allocated = maxi(0,visual_allocated-1)


func configure_effects(assets: RefCounted, camera: Camera3D) -> void:
	effects = preload("res://combat/effect_player.gd").new()
	add_child(effects)
	effects.configure(assets,camera)

func _ready() -> void:
	rng.randomize()

func spawn(shot: Dictionary, muzzle: Transform3D, grip: Vector3, initial_cell: Variant = null) -> void:
	# An accepted discharge sounds once even when the muzzle is blocked or the
	# collision stream is incomplete. Damage still requires complete geometry.
	fired_presentations += 1
	if effects != null:
		var weapon: Dictionary = effects.assets.catalog.get("unarmed",{}) if shot.weapon_id=="unarmed" else effects.assets.catalog.weapons.get(shot.weapon_id,{})
		var flash := muzzle
		flash.basis = flash.basis * Basis(Vector3.RIGHT,-PI/2)
		effects.play(str(weapon.get("effects",{}).get("fire","")),flash)
	# Membership belongs to this projectile, independently of the render observer.
	var membership: Variant = initial_cell if initial_cell != null else actor_cell_at(grip)
	if membership == null:
		record_incomplete({"reason":"unknown_source_cell"})
		return # An elevated hand cannot be classified using the feet-floor probe.
	source_cell = str(membership)
	var result := trace_query(grip,muzzle.origin,source_cell)
	if not result.get("complete",true):
		record_incomplete(result)
		return
	source_cell = str(result.get("end_cell_id",source_cell))
	if result.get("hit",false):
		resolve_hit(shot,result,0.0)
		return
	var visual_handle := acquire_visual(str(shot.weapon_id),muzzle)
	bolts.append({"shot":shot.duplicate(true),"visual_handle":visual_handle,"position":muzzle.origin,"direction":-muzzle.basis.z.normalized(),"distance":0.0,"cell_id":source_cell})

func play_melee_swing(shot:Dictionary,weapon_pose:Transform3D)->void:
	if effects != null:
		var weapon: Dictionary = effects.assets.catalog.get("unarmed",{}) if shot.weapon_id=="unarmed" else effects.assets.catalog.weapons.get(shot.weapon_id,{})
		effects.play(str(weapon.get("effects",{}).get("swing","")),weapon_pose)

func strike_melee(shot: Dictionary, aim: Transform3D, weapon_pose: Transform3D) -> Dictionary:
	# Swing shape never selects the victim. Resolve the head-reticle ray at the
	# qualification instant, through the same view-independent world query.
	play_melee_swing(shot,weapon_pose)
	var membership: Variant = actor_cell_at(aim.origin)
	if membership == null:
		incomplete_queries += 1
		return {}
	var end := aim.origin-aim.basis.z.normalized()*float(shot.range)
	var result := trace_query(aim.origin,end,str(membership))
	if not result.get("complete",false):
		incomplete_queries += 1
		return {}
	if not result.get("hit", false) and float(shot.get("hit_radius", 0)) > 0:
		result = widened_melee_query(aim.origin, end, str(membership), float(shot.hit_radius))
	if result.get("hit",false):
		resolve_hit(shot,result,aim.origin.distance_to(result.position))
		return result
	return {}

func widened_melee_query(from: Vector3, to: Vector3, cell: String, radius: float) -> Dictionary:
	# Godot's native swept sphere supplies candidate contact; the existing world
	# ray validates line of sight and source cell membership to that exact point.
	var sphere := SphereShape3D.new()
	sphere.radius = clampf(radius, 0.001, 0.35)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = collision_mask & 8
	query.exclude = excluded
	var space := get_world_3d().direct_space_state
	var fraction := space.cast_motion(query)
	if fraction.size() != 2 or fraction[0] >= 1: return {}
	query.transform.origin += query.motion * fraction[1]
	query.motion = Vector3.ZERO
	var contact := space.get_rest_info(query)
	if contact.is_empty(): return {}
	var point: Vector3 = contact.point
	if from.distance_to(point) > from.distance_to(to): return {}
	var result := trace_query(from, point + (point - from).normalized() * 0.005, cell)
	if not result.get("complete", false): incomplete_queries += 1; return {}
	return result if result.get("hit", false) else {}

func trace(from: Vector3, to: Vector3, cell := "") -> Dictionary:
	var result := trace_query(from,to,cell)
	return result if result.get("hit",false) and result.get("complete",true) else {}

func trace_query(from: Vector3, to: Vector3, cell: String) -> Dictionary:
	if from.is_equal_approx(to): return {"hit":false,"complete":true,"end_cell_id":cell}
	var result := {"hit":false,"complete":true,"end_cell_id":cell}
	var mask := collision_mask
	if is_instance_valid(collision_stage):
		result = collision_stage.combat_collision.trace_segment(from,to,cell,collision_mask & 7)
		if not result.get("complete",false): return result
		# Live target collision remains distinct from view-scoped world colliders.
		mask = collision_mask & ~7
	var query := PhysicsRayQueryParameters3D.create(from,to,mask,excluded)
	query.hit_from_inside = true
	var dynamic_hit := get_world_3d().direct_space_state.intersect_ray(query) if mask != 0 else {}
	if not dynamic_hit.is_empty() and (not result.get("hit",false) or from.distance_squared_to(dynamic_hit.position)<from.distance_squared_to(result.position)):
		dynamic_hit.merge({"hit":true,"complete":true,"end_cell_id":cell})
		return dynamic_hit
	return result

func _physics_process(delta: float) -> void:
	for i in range(bolts.size()-1,-1,-1):
		var bolt := bolts[i]
		var remaining := maxf(0,float(bolt.shot.range)-float(bolt.distance))
		var length := minf(float(bolt.shot.speed)*delta,remaining)
		var end: Vector3 = bolt.position + bolt.direction * length
		var hit := trace_query(bolt.position,end,str(bolt.cell_id))
		if not hit.get("complete",true):
			record_incomplete(hit)
			remove_bolt(i)
			continue
		bolt.cell_id = str(hit.get("end_cell_id",bolt.cell_id))
		if hit.get("hit",false):
			resolve_hit(bolt.shot,hit,float(bolt.distance)+bolt.position.distance_to(hit.position))
			remove_bolt(i)
			continue
		bolt.distance += length
		bolt.position = end
		if int(bolt.visual_handle)>=0 and effects!=null:
			effects.update_tracer(bolt.visual_handle,Transform3D(Basis.looking_at(bolt.direction),end))
		if length >= remaining: remove_bolt(i)

func resolve_hit(shot: Dictionary, hit: Dictionary, distance: float) -> void:
	var target = hit.get("collider")
	var live_identity: Dictionary=target.core3_identity() if is_instance_valid(target) and target.has_method("core3_identity") else {}
	var live_shot: bool=not str(shot.get("live_session","")).is_empty()
	var result: Dictionary
	if live_shot or not live_identity.is_empty():
		# Contact is evidence only. Health, resistance, rolls and death stay on Core3.
		result={"damage":0.0,"wound":false,"knockdown":false,"authority_pending":true,"shot_id":str(shot.get("shot_id","")),"target_id":str(live_identity.get("id",""))}
		if live_shot and not live_identity.is_empty(): authoritative_contact.emit(shot.duplicate(true),live_identity.duplicate(true),hit.position,hit.normal,distance)
	else:
		var defenses: Dictionary = target.combat_defenses() if is_instance_valid(target) and target.has_method("combat_defenses") else {}
		result=WeaponState.damage_at(shot,distance,defenses.get("resistances",{}),int(defenses.get("armor_rating",0)),rng.randf(),rng.randf())
		var ability: Dictionary = shot.get("ability", {})
		result["ability_id"] = str(ability.get("id", ""))
		result["knockdown"] = float(result.damage) > 0 and not ability.is_empty() and rng.randf() < clampf(float(ability.get("knockdown_chance", 0)), 0, 1)
		if is_instance_valid(target) and target.has_method("receive_local_hit"): target.receive_local_hit(result)
	result.merge({"position":hit.position,"distance":distance,"weapon_id":shot.weapon_id,"sequence":shot.sequence})
	if effects != null:
		var weapon: Dictionary = effects.assets.catalog.get("unarmed",{}) if shot.weapon_id=="unarmed" else effects.assets.catalog.weapons.get(shot.weapon_id,{})
		var normal: Vector3 = hit.normal
		var side := Vector3.RIGHT if absf(normal.dot(Vector3.RIGHT))<0.95 else Vector3.FORWARD
		var z := side.cross(normal).normalized()
		var pose := Transform3D(Basis(normal.cross(z),normal,z),hit.position+normal*0.005)
		effects.play(str(weapon.get("effects",{}).get("hit","")),pose)
	impact.emit(result)

func remove_bolt(index: int) -> void:
	release_visual(bolts[index].visual_handle)
	bolts.remove_at(index)

func clear() -> void:
	for i in range(bolts.size()-1,-1,-1): remove_bolt(i)

func _exit_tree() -> void:
	# The shared batch outlives an individual actor: release all owned handles.
	clear()
