extends SceneTree
const State = preload("res://combat/weapon_state.gd")
const Rig = preload("res://combat/ranged_rig.gd")
const Target = preload("res://combat/training_target.gd")
var checks := 0
var errors: Array[String] = []
var catalog: Dictionary
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func weapon(id := "knife_survival"):
	var s := State.new()
	var p: Dictionary = catalog.weapons[id]
	check(s.configure(p,p.core3.certificationsRequired),"Configure "+id)
	return s
func gesture(s, speed := 2.0, distance := 0.6, direction := Vector3.RIGHT, hz := 90, support := false, posture := "standing") -> Dictionary:
	s.block()
	var dt := 1.0/hz
	s.sample_swing(dt,true,support,posture,Vector3.ZERO)
	s.sample_swing(dt,true,support,posture,Vector3.ZERO)
	var hit: Dictionary = {}
	for i in range(1,int(distance/(speed*dt))+1):
		var result: Dictionary = s.sample_swing(dt,true,support,posture,direction*speed*dt*i)
		if not result.is_empty(): hit=result
	return hit
func run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var melee_count:=0
	for p in catalog.weapons.values():
		if p.get("kind","")!="melee": continue
		melee_count+=1
		check(not p.has("rpm") and not p.has("capacity") and State.valid_profile(p),"Melee replaces ranged statistics: "+p.id)
	check(melee_count==12,"Twelve original melee profiles")
	for hz in [60,72,90,120]:
		for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.FORWARD,Vector3(1,2,3).normalized()]:
			var s=weapon()
			check(not gesture(s,2,0.4,direction,hz).is_empty() and s.fired==1,"One qualified hit independent of direction at %d Hz"%hz)
	var legacy=weapon();legacy.profile.profession={"accuracy":9999,"hit_radius":9999}
	var legacy_hit:=gesture(legacy,2,0.4)
	check(not legacy_hit.is_empty() and legacy_hit.hit_radius==0,"Cached accuracy cannot widen player melee contacts")
	var s=weapon()
	check(gesture(s,0.5,1).is_empty(),"Slow movement cannot qualify")
	check(gesture(s,4,0.12).is_empty(),"Short fast flick cannot qualify")
	var hit:=gesture(s,2,0.4)
	check(not hit.is_empty(),"Spatial recovery and Power qualify attack without trigger")
	var before:int=s.fired
	# The knife first struck at x=0.2889; remaining distance cannot be reset by rest.
	for i in range(50): s.sample_swing(0.01,true,false,"standing",Vector3(0.4,0,0))
	for i in range(1,7): s.sample_swing(0.01,true,false,"standing",Vector3(0.4+i*0.02,0,0))
	check(s.fired==before,"Rest alone never rearms inside the recovery radius")
	for i in range(1,7): s.sample_swing(0.01,true,false,"standing",Vector3(0.52+i*0.02,0,0))
	check(s.fired==before+1,"Moving recovery distance from last strike allows next attack")
	s.block()
	check(s.sample_swing(0.01,true,false,"standing",Vector3(2,0,0)).is_empty(),"Reactivation seeds a fresh origin without a strike")
	check(s.sample_swing(0.01,true,false,"standing",Vector3(2.02,0,0)).is_empty(),"Pre-block displacement cannot qualify")
	# Many fast circles stay inside a diameter smaller than recovery distance.
	s=weapon(); s.sample_swing(0.01,true,false,"standing",Vector3(0.1,0,0))
	for i in range(1,129): s.sample_swing(0.01,true,false,"standing",Vector3(cos(i*TAU/32),sin(i*TAU/32),0)*0.1)
	check(s.fired==0,"Accumulated circular travel cannot bypass spatial recovery")
	# Slow withdrawal prepares an inward swing; speed still gates the attack.
	s=weapon(); s.sample_swing(0.01,true,false,"standing",Vector3.ZERO)
	for i in range(1,29): s.sample_swing(0.02,true,false,"standing",Vector3(i*0.01,0,0))
	check(s.fired==0,"Slow movement beyond recovery does not attack")
	check(not s.sample_swing(0.01,true,false,"standing",Vector3(0.26,0,0)).is_empty(),"Fast inward start at recovery boundary attacks")
	for i in range(30): s.sample_swing(0.01,true,false,"standing",Vector3(0.26,0,0))
	check(s.fired==1,"Stationary weapon cannot repeat strikes")
	for bad in [NAN,0.0,0.2]:
		s=weapon(); s.sample_swing(0.01,true,false,"standing",Vector3.ZERO)
		s.sample_swing(0.01,true,false,"standing",Vector3.ZERO)
		s.sample_swing(bad,true,false,"standing",Vector3(0.4,0,0))
		check(s.fired==0 and s.sample_swing(0.01,true,false,"standing",Vector3(0.42,0,0)).is_empty(),"Bad timing invalidates gesture")
	s=weapon(); s.sample_swing(0.01,true,false,"standing",Vector3.ZERO)
	s.sample_swing(0.01,true,false,"standing",Vector3.ZERO)
	check(s.sample_swing(0.01,true,false,"standing",Vector3(3,0,0)).is_empty(),"Tracking teleport cannot hit")
	s=weapon(); s.certificates=[]
	check(gesture(s).is_empty(),"Certification enforced")
	s=weapon(); s.condition_damage=s.condition_max
	check(gesture(s).is_empty(),"Broken melee weapon cannot hit")
	# Readiness gates attacks without resetting the last strike/reference point.
	s=weapon(); s.sample_swing(0.01,true,false,"standing",Vector3.ZERO,false)
	for i in range(1,31): s.sample_swing(0.01,true,false,"standing",Vector3(i*0.02,0,0),false)
	check(s.fired==0 and not s.swing_feedback.engaged,"At peace prevents fast qualified motion from attacking")
	check(s.sample_swing(0.01,true,false,"standing",Vector3(0.6,0,0),true).is_empty(),"Trigger press at rest cannot attack")
	check(not s.sample_swing(0.01,true,false,"standing",Vector3(0.62,0,0),true).is_empty(),"Ready movement uses preserved recovery reference")
	s.sample_swing(0.01,true,false,"standing",Vector3(0.64,0,0),false)
	check(s.sample_swing(0.01,true,false,"standing",Vector3(0.66,0,0),true).is_empty() and s.fired==1,"Trigger cycling cannot bypass recovery distance")
	for i in range(1,15): s.sample_swing(0.01,true,false,"standing",Vector3(0.66+i*0.02,0,0),true)
	check(s.fired==2,"Held readiness permits another spatially recovered swing")
	var knife=weapon(); var heavy=weapon("2h_sword_maul")
	check(is_equal_approx(knife.melee_thresholds(true).power,knife.profile.power*1.2),"Two hand knife Power bonus")
	check(is_equal_approx(heavy.melee_thresholds(false).power,heavy.profile.power*0.5),"One hand heavy Power penalty")
	check(gesture(knife,1.1,0.6,Vector3.RIGHT,90,false).is_empty(),"Knife speed below one-hand Power threshold")
	check(not gesture(knife,1.1,0.6,Vector3.RIGHT,90,true).is_empty(),"Same knife motion qualifies with two-hand Power bonus")
	check(gesture(heavy,2,0.6,Vector3.RIGHT,90,false).is_empty(),"One-handed heavy Power penalty rejects weak swing")
	check(not gesture(heavy,2,0.6,Vector3.RIGHT,90,true).is_empty(),"Same heavy swing qualifies with correct grip")
	for w in [knife,heavy]:
		check(w.range_scale(true)==w.range_scale(false) and w.range_scale(false)==1,"Grip never changes melee range")
		check(w.melee_thresholds(true).travel==w.melee_thresholds(false).travel,"Grip never changes required travel")
		for posture in ["standing","crouched","prone"]:
			var one:=gesture(w,4,0.8,Vector3.RIGHT,90,false,posture)
			var two:=gesture(w,4,0.8,Vector3.RIGHT,90,true,posture)
			check(one.range==two.range and one.range==w.core.maxRange*w.melee_range_scale(posture),"Posture reach independent of grip: "+posture)
	s=weapon(); s.profile.stance_recovery*=2
	check(is_equal_approx(s.melee_thresholds(false).travel,knife.melee_thresholds(false).travel/2),"Recovery controls required separation")
	check(is_equal_approx(s.melee_thresholds(false).speed,knife.melee_thresholds(false).speed),"Recovery does not change speed")
	hit=gesture(knife); hit.core3.maxRangeAccuracy=-50; hit.core3.idealAccuracy=-50
	for posture in ["standing","crouched","prone"]:
		hit.firing_posture=posture
		check(State.damage_at(hit,hit.range,{},0,1,1).range_modifier==-50,"Melee never inherits ranged posture damage bonus")
	var clean:Dictionary=State.damage_at(hit,1,{},0,1,0)
	var protected:Dictionary=State.damage_at(hit,1,{"kinetic":50},1,1,0)
	check(protected.damage<clean.damage and clean.wound,"Original melee armour, resistance, wound statistics")
	# Refresh cannot carry separation across crafted stat changes.
	s=weapon(); s.profile.merge({"source_kind":"core3_weapon_instance","item_id":"42","certified":true},true)
	var updated:Dictionary=s.profile.duplicate(true); updated.power*=1.5; updated.stance_recovery*=1.25
	check(s.refresh_instance(updated) and State.crafting_preview(updated).contains("Power"),"Crafted melee statistics refresh and preview")
	check(s.rounds==0 and not s.reload() and s.mode=="melee","Melee has no ammunition or reload")
	# Use real physics and the actual rig; aim intentionally differs from blade.
	var world:=Node3D.new(); root.add_child(world)
	var head:=Camera3D.new(); world.add_child(head); head.position=Vector3(0,1.6,0)
	var body:=CharacterBody3D.new(); world.add_child(body)
	var rig:=Rig.new(); world.add_child(rig)
	check(rig.configure(head,body,[catalog.weapons.knife_survival,catalog.weapons["2h_sword_maul"]]),"Original melee rig")
	rig.set_physics_process(false); rig.set_process(false); rig.set_allowed(true); rig.draw(0)
	var target:=Target.new(); world.add_child(target); target.position=Vector3(0,1.6,-2.5)
	await physics_frame; await physics_frame
	rig.main_grip_down=true
	var pose:=Transform3D(Basis(Vector3.UP,PI/2),Vector3(0.3,1.3,-0.3))
	rig.sample(0.01,pose,pose,1,0,1,true,true)
	rig.sample(0.01,pose,pose,1,0,1,true,true)
	var reference:Transform3D=rig.reticle.global_transform
	for i in range(25):
		pose.origin.x+=0.02
		rig.sample(0.01,pose,pose,1,0,1,true,true)
	check(target.hit_count==1,"Swing away from target hits head-aimed target")
	check(rig.reticle.global_transform.is_equal_approx(reference) and reference.origin.is_equal_approx(head.position+Vector3.FORWARD*3),"Melee reticle stays at fixed distance from head during swing")
	check(rig.rounds_sim.bolts.is_empty(),"Melee emits no projectile")
	hit=gesture(knife)
	check(rig.rounds_sim.strike_melee(hit,head.global_transform,pose).get("collider")==target,"Head ray selects in-range target")
	hit.range=2
	check(rig.rounds_sim.strike_melee(hit,head.global_transform,pose).is_empty(),"Posture-shortened range cannot hit distant target")
	hit.range=4
	var wall:=StaticBody3D.new(); wall.collision_layer=1; world.add_child(wall); wall.position=Vector3(0,1.6,-1)
	var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(2,2,0.1); shape.shape=box; wall.add_child(shape)
	await physics_frame; await physics_frame
	before=target.hit_count
	check(rig.rounds_sim.strike_melee(hit,head.global_transform,pose).get("collider")==wall and target.hit_count==before,"World wall blocks head ray")
	head.rotate_y(PI/2)
	check(rig.rounds_sim.strike_melee(hit,head.global_transform,pose).is_empty(),"Head rotation changes targeting independently of blade")
	world.queue_free(); await create_timer(0.2).timeout
	var report:Dictionary={"test":"melee_combat","passed":errors.is_empty(),"checks":checks,"errors":errors,"hardware_tested":false,"backend_combat_tested":false}
	FileAccess.open("res://../runtime/evidence/melee-combat-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); quit(0 if errors.is_empty() else 1)
