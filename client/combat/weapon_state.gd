extends RefCounted
## Local simulation seam. Inputs are copied; this never writes Core3 state.
const ArmourModel = preload("res://combat/armour_model.gd")
var armour_scales: Dictionary = {}
var profile: Dictionary = {}
var core: Dictionary = {}
var certificates: Array = []
var rounds := 0
var charge_observation:Dictionary={}
var mode := "semi"
var condition_max := 1000.0
var condition_damage := 0.0
var wear_per_shot := 0.05
var clock := 0.0
var next_shot := 0.0
var reload_until := -1.0
var burst_left := 0
var trigger_down := false
var armed := false
var fired := 0
var swing := SwgMeleeSwing.new()
var swing_feedback: Dictionary = {}
var ability_state: RefCounted

func profession(field: String, fallback: float) -> float:
	return float(profile.get("profession", {}).get(field, fallback))

func observe_armour(scales: Dictionary) -> void:
	var previous := float(armour_scales.get("recovery_scale", profile.get("armour_scales", {}).get("recovery_scale", 1)))
	var current := float(scales.get("recovery_scale", profile.get("armour_scales", {}).get("recovery_scale", 1)))
	if reload_until >= clock and not is_equal_approx(previous, current):
		reload_until = clock + (reload_until-clock) * previous / maxf(0.001, current)
	armour_scales = scales.duplicate(true)

func armour_ratio(key: String) -> float:
	var captured := float(profile.get("armour_scales", {}).get(key, 1))
	return float(armour_scales.get(key, captured)) / maxf(0.001, captured)

func effective_rpm() -> float:
	return float(profile.get("rpm", 0)) * profession("rpm_scale", 1) * armour_ratio("output_scale")

func effective_recovery() -> float:
	return float(profile.get("stance_recovery", 0)) * profession("stance_recovery_scale", 1) * armour_ratio("recovery_scale")

func is_melee() -> bool:
	return profile.get("kind","") == "melee"

func configure(data: Dictionary, owned_certificates: Array, item_condition := {}) -> bool:
	if not valid_profile(data):
		return false
	profile = data.duplicate(true)
	core = profile.core3
	certificates = owned_certificates.duplicate()
	rounds = 0 if is_melee() else int(profile.capacity)
	mode = "melee" if is_melee() else str(profile.fire_modes[0])
	condition_max = maxf(1.0, float(item_condition.get("maxCondition", 1000.0)))
	condition_damage = clampf(float(item_condition.get("conditionDamage", 0.0)), 0, condition_max)
	clock = 0; next_shot = 0; reload_until = -1; burst_left = 0
	trigger_down = false; armed = false; fired = 0; charge_observation.clear()
	swing.reset(); swing_feedback = {}
	return true

static func valid_profile(data: Dictionary) -> bool:
	if data.get("kind","") == "melee":
		for key in ["power","stance_recovery","swing_speed_reference","swing_travel_reference"]:
			if not is_finite(float(data.get(key,0))) or float(data.get(key,0))<=0: return false
		return data.has("core3") and int(data.get("hands",0)) in [1,2]
	return data.has("core3") and is_finite(float(data.get("rpm",0))) and float(data.get("rpm",0))>0 and is_finite(float(data.get("capacity",0))) and float(data.get("capacity",0))==int(data.get("capacity",0)) and int(data.get("capacity",0))>0 and is_finite(float(data.get("reload_seconds",0))) and float(data.get("reload_seconds",0))>0 and not data.get("fire_modes",[]).is_empty()

func refresh_player(data: Dictionary) -> bool:
	if not profile.get("unarmed",false) or not data.get("unarmed",false) or not valid_profile(data): return false
	if data.get("source_kind","")!="core3_player_stats" or str(data.get("character_id",""))!=str(profile.get("character_id","")): return false
	profile=data.duplicate(true); core=profile.core3
	swing.reset(); swing_feedback={}
	return true

func refresh_instance(data: Dictionary) -> bool:
	# Refresh only this item. No refill, cooldown reset or trigger rearming.
	if not valid_profile(data) or data.get("source_kind","")!="core3_weapon_instance" or str(data.get("item_id",""))!=str(profile.get("item_id","")) or str(data.get("id",""))!=str(profile.get("id","")):
		return false
	if is_melee() != (data.get("kind","")=="melee"): return false
	var old_rpm := effective_rpm()
	var remaining_interval := maxf(0,next_shot-clock)
	var native_charges:int=int(profile.get("charges",-1))
	profile = data.duplicate(true)
	core = profile.core3
	if profile.get("charge_limited",false):
		if native_charges>=0:profile["charges"]=native_charges
	elif not is_melee(): rounds = mini(rounds,int(profile.capacity))
	# Preserve the remaining fraction of the shot interval when RPM changes.
	if is_melee(): swing.reset(); swing_feedback = {}
	else: next_shot = clock + remaining_interval * old_rpm / effective_rpm()
	certificates = core.certificationsRequired.duplicate() if data.get("certified",false) else []
	var condition: Dictionary = data.get("condition",{})
	condition_max = maxf(1,float(condition.get("maxCondition",condition_max)))
	# A stat refresh cannot undo wear from locally predicted shots.
	condition_damage = clampf(maxf(condition_damage,float(condition.get("conditionDamage",0))),0,condition_max)
	if not is_melee() and mode not in profile.fire_modes: mode = str(profile.fire_modes[0]); block()
	return true

static func crafting_preview(data: Dictionary, previous := {}) -> String:
	if not valid_profile(data): return "Weapon statistics unavailable"
	if data.get("kind","") == "melee":
		var text := "Stance recovery: %.1f\nPower: %.1f" % [float(data.stance_recovery),float(data.power)]
		if valid_profile(previous) and previous.get("kind","")=="melee":
			text += "\nChange: %+.1f recovery · %+.1f power" % [float(data.stance_recovery)-float(previous.stance_recovery),float(data.power)-float(previous.power)]
		return text
	if data.get("charge_limited",false):
		return "Rate of fire: %.1f RPM\n"%float(data.rpm)+("Remaining charges: %d"%int(data.charges) if data.has("charges") else "Consumable ammunition")
	var text := "Rate of fire: %.1f RPM\nCapacity: %d shots" % [float(data.rpm),int(data.capacity)]
	if valid_profile(previous) and previous.get("kind","")!="melee":
		text += "\nChange: %+.1f RPM · %+d shots" % [float(data.rpm)-float(previous.rpm),int(data.capacity)-int(previous.capacity)]
	return text

func certified() -> bool:
	for certificate in core.get("certificationsRequired", []):
		if certificate not in certificates: return false
	return true

func block() -> void:
	armed = false
	burst_left = 0
	swing.reset(); swing_feedback = {}

func cycle_mode() -> void:
	if is_melee(): return
	var modes: Array = profile.fire_modes
	mode = str(modes[(modes.find(mode) + 1) % modes.size()])
	block()

func reload() -> bool:
	if is_melee() or profile.get("charge_limited",false): return false
	if reload_until >= 0 or rounds == int(profile.capacity): return false
	reload_until = clock + float(profile.reload_seconds) / (profession("capacity_recovery_scale", 1) * float(armour_scales.get("recovery_scale", profile.get("armour_scales", {}).get("recovery_scale", 1))))
	block()
	return true

func range_scale(two_hands: bool) -> float:
	if is_melee(): return 1.0 # Melee grip modifiers affect Power only.
	return (1.0 if two_hands else 0.30) if int(profile.hands) == 2 else (1.10 if two_hands else 1.0)

func reserve_rounds(count:int)->bool:
	if count<1 or is_melee() or not certified() or reload_until>=0 or rounds<count or condition_max<2 or condition_damage>=condition_max:return false
	rounds-=count
	return true

func refund_rounds(count:int)->void:
	if not is_melee():
		var limit:int=int(profile.get("charges",profile.capacity)) if profile.get("charge_limited",false) else int(profile.capacity)
		rounds=mini(maxi(0,limit),rounds+maxi(0,count))

func observe_native_charges(charges:int, session:String, revision:int, reserved:bool)->bool:
	if not profile.get("charge_limited",false) or charges<0 or session.is_empty() or revision<0:return false
	if charge_observation.get("session","")==session and revision<=int(charge_observation.get("revision",-1)):return false
	# Charges belong to the real consumable item, independent of crafted magazine
	# capacity. Fresh native state restores an uncertain uncommitted reservation;
	# outstanding launches remain reserved until their authoritative receipt.
	profile["charges"]=charges
	rounds=mini(rounds,charges) if reserved else charges
	reload_until=-1
	charge_observation={"session":session,"revision":revision,"charges":charges}
	return true

func ranged_snapshot(two_hands:bool,posture:String)->Dictionary:
	return {"core3":core.duplicate(true),"range_scale":range_scale(two_hands),"range":float(core.maxRange)*range_scale(two_hands),"condition_fraction":1.0-condition_damage/condition_max,"weapon_id":profile.id,"sequence":fired,"speed":float(profile.projectile_speed),"two_hands":two_hands,"firing_posture":posture if posture in ["crouched","prone"] else "standing","range_modifier_bonus":0.0}

func showdown_round(two_hands:bool,posture:String,first:bool)->Dictionary:
	if (first and (rounds<3 or clock+.000001<next_shot)) or not reserve_rounds(1):return {}
	fired+=1;next_shot=clock+.25
	var shot:=ranged_snapshot(two_hands,posture)
	condition_damage=minf(condition_max,condition_damage+wear_per_shot)
	return shot

func tick(delta: float, trigger: float, allowed: bool, two_hands: bool, posture := "standing") -> Dictionary:
	if is_melee(): return {} # Melee requires tracked motion via sample_swing.
	if profile.is_empty() or not is_finite(delta) or delta < 0: return {}
	clock += delta
	if reload_until >= 0 and clock >= reload_until:
		rounds = int(profile.capacity)
		reload_until = -1
	var was_down := trigger_down
	if trigger < 0.2: trigger_down = false
	elif trigger >= 0.75: trigger_down = true
	if profile.get("native_family","")=="commando" and profile.get("commando_family","")!="pistol_launcher" and not two_hands:allowed=false
	if not allowed or not certified() or condition_max < 2 or condition_damage >= condition_max:
		block()
		return {}
	if not trigger_down:
		armed = true
		burst_left = 0 # Peace cancels an unfinished burst immediately.
	if reload_until >= 0:
		block() # Release AFTER cooling, not just during it.
		return {}
	if not armed: return {}
	var edge := trigger_down and not was_down
	if mode == "burst" and edge and burst_left == 0 and clock + 0.000001 >= next_shot:
		burst_left = int(profile.get("burst_count", 3))
	var wants := (trigger_down if mode == "auto" else (burst_left > 0 if mode == "burst" else edge))
	if not wants or clock + 0.000001 < next_shot: return {}
	if rounds <= 0:
		reload()
		return {}
	if ability_state != null and not ability_state.can_attack(profile): return {}
	# No backlog of historical shots after a stall; at most one per tracking frame.
	var interval := 60.0 / effective_rpm()
	if edge or clock-next_shot > interval:
		next_shot = clock + interval
	else:
		next_shot += interval
	rounds -= 1
	fired += 1
	var snapshot := {"core3":core.duplicate(true), "range_scale":range_scale(two_hands),
		"range":float(core.maxRange)*range_scale(two_hands), "condition_fraction":1.0-condition_damage/condition_max,
		"weapon_id":profile.id, "sequence":fired, "speed":float(profile.projectile_speed),
		"two_hands":two_hands, "firing_posture":posture if posture in ["crouched","prone"] else "standing"}
	snapshot["range_modifier_bonus"] = 0.0 # Legacy accuracy bonuses have no player effect.
	if ability_state != null: ability_state.apply_to_attack(snapshot, profile)
	condition_damage = minf(condition_max, condition_damage + wear_per_shot)
	if mode == "burst":
		burst_left -= 1
		if burst_left == 0: next_shot = maxf(next_shot, clock + float(profile.get("burst_recovery", 0.3)))
	if rounds == 0: reload()
	return snapshot

func melee_range_scale(posture: String) -> float:
	if posture=="crouched": return float(profile.get("crouch_range_scale",0.75))
	if posture=="prone": return float(profile.get("prone_range_scale",0.5))
	return 1.0

func melee_thresholds(two_hands: bool) -> Dictionary:
	var power_scale := 1.0
	if int(profile.hands)==1 and two_hands: power_scale=float(profile.get("two_hand_power_bonus",1.2))
	elif int(profile.hands)==2 and not two_hands: power_scale=float(profile.get("one_hand_power_penalty",0.5))
	var power := float(profile.power) * armour_ratio("output_scale")*power_scale
	return {"power":power,"speed":float(profile.swing_speed_reference)*100.0/power,
		"travel":float(profile.swing_travel_reference)*100.0/effective_recovery()}

func sample_swing(delta: float, allowed: bool, two_hands: bool, posture: String, position: Vector3, combat_ready := true) -> Dictionary:
	if not is_melee(): return {}
	var thresholds := melee_thresholds(two_hands)
	var permitted := allowed and certified() and condition_max>=2 and condition_damage<condition_max
	swing_feedback = swing.sample(delta,position,permitted,thresholds.speed,thresholds.travel,combat_ready)
	if not swing_feedback.hit: return {}
	if ability_state != null and not ability_state.can_attack(profile): return {}
	fired += 1
	var scale := melee_range_scale(posture)
	var hit := {"kind":"melee","core3":core.duplicate(true),"range_scale":scale,"range":float(core.maxRange)*scale,
		"condition_fraction":1.0-condition_damage/condition_max,"weapon_id":profile.id,"sequence":fired,
		"firing_posture":posture,"power":thresholds.power,"stance_recovery":effective_recovery(),
		"swing_speed":swing_feedback.speed,"swing_travel":swing_feedback.travel}
	hit["hit_radius"] = 0.0 # Contacts are not widened by accuracy skills.
	if ability_state != null: ability_state.apply_to_attack(hit, profile)
	if not profile.get("unarmed",false): condition_damage=minf(condition_max,condition_damage+wear_per_shot)
	return hit

static func damage_at(shot: Dictionary, distance: float, resistance: Dictionary, armor_rating: int, damage_roll: float, wound_roll: float) -> Dictionary:
	if distance < 0 or distance > float(shot.range): return {"damage":0.0,"wound":false}
	var stats: Dictionary = shot.core3
	var scale: float = shot.range_scale
	var near_distance := float(stats.pointBlankRange) * scale
	var middle := float(stats.idealRange) * scale
	var far_distance: float = shot.range
	var modifier: float
	if distance <= middle:
		modifier = lerpf(float(stats.pointBlankAccuracy), float(stats.idealAccuracy), clampf((distance-near_distance)/maxf(0.0001,middle-near_distance),0,1))
	else:
		modifier = lerpf(float(stats.idealAccuracy), float(stats.maxRangeAccuracy), clampf((distance-middle)/maxf(0.0001,far_distance-middle),0,1))
	var raw_modifier := modifier
	# Preserve the original Marksman stance mitigation of negative distance damage.
	# Player skill accuracy remains unrelated to damage or hit chance.
	if modifier < 0 and shot.get("kind","")!="melee":
		match str(shot.get("firing_posture","standing")):
			"crouched": modifier *= 0.5
			"prone": modifier = 0.0
	var base := lerpf(float(stats.minDamage), float(stats.maxDamage), clampf(damage_roll,0,1))
	# Core3 TangibleObject condition reduction starts at 75% condition damage.
	var condition := clampf(float(shot.condition_fraction),0,1)
	var pierce := int(stats.armorPiercing) if condition > 0 else 0
	# Legacy AR is intentionally unused. Profiles carry bounded mitigation bypass.
	var converted: Dictionary = stats.get("damage_profile", ArmourModel.weapon(str(stats.damageType), pierce, condition <= 0))
	if condition <= 0:
		converted = ArmourModel.weapon(str(stats.damageType), 0, true)
	var condition_multiplier := 1.0-maxf(0.0,((1.0-condition)*100.0-75.0)/50.0)
	var amount := ArmourModel.damage(base * maxf(0,1.0+modifier/100.0) * condition_multiplier, converted, resistance)
	amount *= float(shot.get("ability", {}).get("damage_multiplier", 1))
	return {"damage":amount,"damage_type":stats.damageType,"wound":amount>0 and wound_roll < clampf(float(stats.woundsRatio)/100.0,0,1),"armor_piercing":pierce,"range_modifier":modifier,"raw_range_modifier":raw_modifier,"firing_posture":shot.get("firing_posture","standing")}
