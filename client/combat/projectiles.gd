extends Node3D
## Swept local presentation. Core3 actors emit contact evidence, never local damage.
signal impact(event: Dictionary)
signal authoritative_contact(shot: Dictionary, target: Dictionary, position: Vector3, normal: Vector3, distance: float)
const WeaponState = preload("res://combat/weapon_state.gd")
var bolts: Array[Dictionary] = []
var scatter_groups:Dictionary={}
var scatter_serial:=0
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
		if shot.get("delivery","")!="scatter":resolve_hit(shot,result,0.0)
		return
	if shot.get("delivery","")=="scatter" and not shot.get("cosmetic_only",false):
		scatter_serial+=1
		var id:=str(scatter_serial)
		scatter_groups[id]={"shot":shot.duplicate(true),"remaining":8,"contacts":[]}
		for index in range(8):
			var pellet:=shot.duplicate(true);pellet["scatter_group"]=id;pellet["pellet_index"]=index
			var direction:=pellet_direction(-muzzle.basis.z.normalized(),index)
			spawn_bolt(pellet,Transform3D(Basis.looking_at(direction),muzzle.origin),source_cell)
	else:spawn_bolt(shot,muzzle,source_cell)

static func pellet_direction(direction:Vector3,index:int)->Vector3:
	if index==0:return direction.normalized()
	# Native indices are defined in source space. Reflect Z before the cross
	# products: reflecting an already constructed fan reverses its handedness.
	var forward:=Vector3(direction.x,direction.y,-direction.z).normalized()
	var right:=forward.cross(Vector3.UP if absf(forward.y)<=.99 else Vector3.RIGHT).normalized()
	var up:=right.cross(forward).normalized()
	var azimuth:=TAU*float(index-1)/7.
	var angle:=deg_to_rad(4.)
	var ray:Vector3=(forward*cos(angle)+(right*cos(azimuth)+up*sin(azimuth))*sin(angle)).normalized()
	return Vector3(ray.x,ray.y,-ray.z)

func spawn_bolt(shot:Dictionary,muzzle:Transform3D,cell:String)->void:
	var visual_handle:=acquire_visual(str(shot.weapon_id),muzzle)
	shot=shot.duplicate(true)
	if shot.get("delivery","")=="guided_bolt":
		var actor:Variant=shot.get("guidance_actor")
		if not is_instance_valid(actor) or (-muzzle.basis.z).angle_to((actor.global_position+Vector3.UP-muzzle.origin).normalized())>deg_to_rad(5.):shot.erase("guidance_actor")
	bolts.append({"shot":shot.duplicate(true),"visual_handle":visual_handle,"position":muzzle.origin,"direction":-muzzle.basis.z.normalized(),"distance":0.,"age":0.,"guidance_turn":0.,"cell_id":cell})

func guide(bolt:Dictionary,delta:float)->void:
	if bolt.shot.get("delivery","")!="guided_bolt":return
	var actor:Variant=bolt.shot.get("guidance_actor")
	if not is_instance_valid(actor) or not actor.has_method("is_targetable") or not actor.is_targetable():return
	var point:Vector3=actor.global_position+Vector3.UP
	var offset:Vector3=point-bolt.position
	if offset.length_squared()<.001:return
	var sight:=trace_query(bolt.position,point,str(bolt.cell_id))
	if not sight.get("complete",false) or (sight.get("hit",false) and sight.get("collider")!=actor):return
	var desired:=offset.normalized()
	var angle:float=bolt.direction.angle_to(desired)
	var turn:=minf(angle,minf(deg_to_rad(20.)*delta,maxf(0,deg_to_rad(8.)-float(bolt.guidance_turn))))
	if turn<=.000001:return
	bolt.direction=bolt.direction.slerp(desired,turn/angle).normalized();bolt.guidance_turn=float(bolt.guidance_turn)+turn

func collect_pellet(shot:Dictionary,hit:Dictionary,distance:float)->void:
	var group:Dictionary=scatter_groups.get(str(shot.scatter_group),{})
	if group.is_empty():return
	var actor:Variant=hit.get("collider")
	if not is_instance_valid(actor) or not actor.has_method("core3_identity") or not actor.has_method("is_targetable") or not actor.is_targetable():return
	var record:Variant=actor.get("record")
	if not record is Dictionary or record.get("relation","") not in ["hostile","attackable"] or record.get("dead",false) or record.get("incapacitated",false):return
	if not str(shot.get("ability_id","")).is_empty() and record.get("kind","")!="creature":return
	var identity:Dictionary=actor.core3_identity()
	if not str(shot.get("target_id","")).is_empty() and str(identity.get("id",""))!=str(shot.target_id):return
	group.contacts.append({"pellet_index":int(shot.pellet_index),"hit_position":hit.position,"projectile_age_seconds":float(shot.get("projectile_age_seconds",0)),"hit":hit,"identity":identity,"distance":distance})

func finish_scatter(id:String)->void:
	var group:Dictionary=scatter_groups.get(id,{})
	if group.is_empty():return
	scatter_groups.erase(id)
	var contacts:Array=group.contacts
	if contacts.is_empty():return
	contacts.sort_custom(func(a,b):return int(a.pellet_index)<int(b.pellet_index) if float(a.projectile_age_seconds)==float(b.projectile_age_seconds) else float(a.projectile_age_seconds)<float(b.projectile_age_seconds))
	var first:Dictionary=contacts[0];var primary:=str(first.identity.id)
	var evidence:Array=[]
	for contact:Dictionary in contacts:
		if str(contact.identity.id)==primary:evidence.append({"pellet_index":contact.pellet_index,"hit_position":contact.hit_position,"projectile_age_seconds":contact.projectile_age_seconds})
	var shot:Dictionary=group.shot
	shot["pellet_contacts"]=evidence;shot["projectile_age_seconds"]=first.projectile_age_seconds
	resolve_hit(shot,first.hit,float(first.distance))

func present_heavy(shot:Dictionary, muzzle:Transform3D, grip:Vector3, profile:Dictionary)->void:
	# Native cone/beam delivery is not a moving bolt. Original-source bursts are
	# sampled along a bounded, geometry-clipped volume; they never emit contacts.
	fired_presentations+=1
	if effects==null:return
	var source:Dictionary=effects.assets.catalog.weapons.get(str(shot.get("weapon_id","")),{})
	var membership:Variant=actor_cell_at(grip)
	if membership==null:record_incomplete({"reason":"unknown_source_cell"});return
	var clearance:=trace_query(grip,muzzle.origin,str(membership))
	if not clearance.get("complete",false):record_incomplete(clearance);return
	if clearance.get("hit",false):return
	effects.play(str(source.get("effects",{}).get("fire","")),muzzle)
	var distance:=clampf(float(shot.get("range",profile.get("core3",{}).get("maxRange",0))),0,64)
	var angles:Array=[0.]
	if profile.get("delivery","")=="cone":
		var angle:=clampf(float(profile.get("cone_angle_degrees",40))*.5,0,30)
		angles=[-angle,0.,angle]
	for angle:float in angles:
		var direction:Vector3=-(muzzle.basis*Basis(Vector3.UP,deg_to_rad(angle))).z.normalized()
		var end:=muzzle.origin+direction*distance
		var hit:=trace_query(muzzle.origin,end,str(clearance.get("end_cell_id",membership)))
		if not hit.get("complete",false):record_incomplete(hit);continue
		if hit.get("hit",false):end=hit.position
		var reach:=muzzle.origin.distance_to(end)
		var steps:=clampi(ceili(reach/2.),1,8)
		for index in range(steps):
			var point:=muzzle.origin+direction*reach*(float(index)+.5)/steps
			effects.emit_particle(str(source.get("projectile","")),Transform3D(Basis.looking_at(direction),point),"tracer")
		if hit.get("hit",false):effects.play(str(source.get("effects",{}).get("hit","")),Transform3D(Basis.looking_at(direction),end))

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
		guide(bolt,delta)
		var end: Vector3 = bolt.position + bolt.direction * length
		var hit := trace_query(bolt.position,end,str(bolt.cell_id))
		if not hit.get("complete",true):
			record_incomplete(hit)
			remove_bolt(i)
			continue
		bolt.cell_id = str(hit.get("end_cell_id",bolt.cell_id))
		if hit.get("hit",false):
			bolt.shot["projectile_age_seconds"]=float(bolt.get("age",0))+bolt.position.distance_to(hit.position)/maxf(float(bolt.shot.speed),1.)
			resolve_hit(bolt.shot,hit,float(bolt.distance)+bolt.position.distance_to(hit.position))
			remove_bolt(i)
			continue
		bolt.age=float(bolt.get("age",0))+length/maxf(float(bolt.shot.speed),1.)
		bolt.distance += length
		bolt.position = end
		if int(bolt.visual_handle)>=0 and effects!=null:
			effects.update_tracer(bolt.visual_handle,Transform3D(Basis.looking_at(bolt.direction),end))
		if length >= remaining: remove_bolt(i)

func resolve_hit(shot: Dictionary, hit: Dictionary, distance: float) -> void:
	if shot.has("scatter_group"):
		collect_pellet(shot,hit,distance);return
	var target = hit.get("collider")
	var live_identity: Dictionary=target.core3_identity() if is_instance_valid(target) and target.has_method("core3_identity") else {}
	var live_shot: bool=not str(shot.get("live_session","")).is_empty()
	var result: Dictionary
	if shot.get("cosmetic_only",false):
		result={"damage":0.0,"wound":false,"knockdown":false,"cosmetic_only":true}
	elif live_shot or not live_identity.is_empty():
		# Contact is evidence only. Health, resistance, rolls and death stay on Core3.
		result={"damage":0.0,"wound":false,"knockdown":false,"authority_pending":true,"shot_id":str(shot.get("shot_id","")),"target_id":str(live_identity.get("id",""))}
		if live_shot and not live_identity.is_empty(): authoritative_contact.emit(shot.duplicate(true),live_identity.duplicate(true),hit.position,hit.normal,distance)
		elif live_shot and shot.get("delivery","")=="rocket":authoritative_contact.emit(shot.duplicate(true),{"id":"0","session_id":str(shot.live_session)},hit.position,hit.normal,distance)
	else:
		var defenses: Dictionary = target.combat_defenses() if is_instance_valid(target) and target.has_method("combat_defenses") else {}
		result=WeaponState.damage_at(shot,distance,defenses.get("resistances",{}),int(defenses.get("armor_rating",0)),rng.randf(),rng.randf())
		if shot.get("delivery","")=="scatter":result.damage=float(result.damage)*float(shot.get("pellet_contacts",[]).size())/8.
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
	var group:=str(bolts[index].shot.get("scatter_group",""))
	release_visual(bolts[index].visual_handle)
	bolts.remove_at(index)
	if scatter_groups.has(group):
		scatter_groups[group].remaining=int(scatter_groups[group].remaining)-1
		if int(scatter_groups[group].remaining)<=0:finish_scatter(group)

func clear() -> void:
	scatter_groups.clear() # Reset/disconnect never emits delayed contact evidence.
	for i in range(bolts.size()-1,-1,-1): remove_bolt(i)

func _exit_tree() -> void:
	# The shared batch outlives an individual actor: release all owned handles.
	clear()
