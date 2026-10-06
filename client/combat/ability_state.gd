extends RefCounted
## Shared by both fists and every weapon. Local prediction, never server HAM.
var character_id := ""
var ham: Array = []
var pools_valid := false
var max_ham: Array = []
var wounds: Array = []
var vitals_valid := false

func update_vitals(context: Dictionary) -> void:
	var maximum: Array = context.get("max_ham", [])
	var blocked: Array = context.get("wounds", [])
	vitals_valid = maximum.size() == 9 and blocked.size() == 9
	for values in [maximum, blocked]:
		for value in values: vitals_valid = vitals_valid and is_finite(float(value)) and float(value) >= 0
	if not vitals_valid: return
	max_ham = maximum.duplicate()
	wounds = blocked.duplicate()

func readout() -> Array:
	var bars: Array = []
	for index in [0, 3, 6]:
		var valid := pools_valid and vitals_valid and ham.size() == 9 and float(max_ham[index]) > 0
		var maximum := float(max_ham[index]) if valid else 1.0
		var blocked := clampf(float(wounds[index]), 0, maximum) if valid else 0.0
		var current := clampf(float(ham[index]), 0, maximum - blocked) if valid else 0.0
		bars.append({"valid":valid, "current":current, "maximum":maximum, "wounds":blocked,
			"fill":current / maximum, "blocker":blocked / maximum})
	return bars
var cooldowns: Dictionary = {}
signal selection_replaced(ability: Dictionary, was_primed: bool)
var selection: Dictionary = {}
var selection_owner := "combat"
var selected := ""
var primed := false
var reason := ""

func refresh_context(context: Dictionary) -> void:
	update_vitals(context)
	var id := str(context.get("character_id", ""))
	var values: Array = context.get("ham", [])
	var complete: bool = context.get("complete", false) and values.size() == 9
	for value in values:
		complete = complete and is_finite(float(value)) and float(value) >= 0
	if id != character_id:
		character_id = id
		ham = []
		cooldowns.clear()
		selection={};selection_owner="combat"
		selected = ""
		primed = false
	if not complete:
		pools_valid = false
		primed = false
		return
	pools_valid = true
	# A disconnected entry refresh must not refill locally spent pools.
	if ham.size() == 9:
		for index in range(9): ham[index] = minf(float(ham[index]), float(values[index]))
	else:
		ham = values.duplicate()

func tick(delta: float) -> void:
	if not is_finite(delta) or delta < 0: return
	for id in cooldowns: cooldowns[id] = maxf(0, float(cooldowns[id]) - delta)
	if reason == "Recovering" and float(cooldowns.get(selected, 0)) <= 0: reason = ""

func definition(profile: Dictionary) -> Dictionary:
	for ability: Dictionary in profile.get("abilities", []):
		if str(ability.get("id", "")) == selected: return ability
	return {}

func reconcile(profile: Dictionary) -> void:
	if selection_owner=="combat" and definition(profile).is_empty() and not selected.is_empty():
		replace_selection({})

func replace_selection(ability: Dictionary, owner := "combat") -> void:
	if selected==str(ability.get("id","")) and selection_owner==owner and not selected.is_empty(): return
	var previous:=selection.duplicate(true)
	var was_primed:=primed
	if primed and not selected.is_empty():
		cooldowns[selected]=maxf(float(cooldowns.get(selected,0)),float(selection.get("cooldown_seconds",0)))
	selected=str(ability.get("id",""));selection=ability.duplicate(true);selection_owner=owner;primed=false;reason=""
	if not previous.is_empty(): selection_replaced.emit(previous,was_primed)

func select(profile: Dictionary, id: String) -> bool:
	for ability: Dictionary in profile.get("abilities", []):
		if str(ability.id) == id:
			replace_selection(ability)
			return true
	return false

func costs(ability: Dictionary) -> Array:
	if not pools_valid or ham.size() != 9: return []
	var result: Array = []
	var index := 0
	for pool in ["health", "action", "mind"]:
		var base := float(ability.get("base_sac", {}).get(pool, NAN))
		if not is_finite(base) or base < 0: return []
		# Core3 calculateCostAdjustment uses current STR/QUI/FOC.
		result.append(maxf(0, base * (1.0 - (float(ham[index + 1]) - 300.0) / 1200.0)))
		index += 3
	return result

func available(profile: Dictionary) -> bool:
	var ability := definition(profile)
	if ability.is_empty(): reason = "Select an ability"; return false
	if float(cooldowns.get(selected, 0)) > 0: reason = "Recovering"; return false
	var cost := costs(ability)
	if cost.size() != 3: reason = "Combat pools unavailable"; return false
	for index in range(3):
		if float(ham[index * 3]) <= float(cost[index]): reason = "Insufficient HAM"; return false
	reason = ""
	return true

func toggle_prime(profile: Dictionary) -> bool:
	if primed: primed = false; return true
	primed = available(profile)
	return primed

func can_attack(profile: Dictionary) -> bool:
	return not primed or available(profile)

func apply_to_attack(shot: Dictionary, profile: Dictionary) -> void:
	if not primed or not available(profile): return
	var ability := definition(profile)
	var cost := costs(ability)
	for index in range(3):
		# inflictDamage receives integer damage after the float affordability test.
		ham[index * 3] = float(ham[index * 3]) - int(cost[index])
	cooldowns[selected] = float(ability.cooldown_seconds)
	shot["ability"] = ability.duplicate(true)
	shot["sac_spent"] = cost.map(func(value): return int(value))
	primed = false

func apply_authoritative(context: Dictionary) -> bool:
	# Native snapshots replace prediction, including regeneration. Secondary HAM
	# attributes remain from the authenticated character-entry snapshot.
	var current: Variant = context.get("ham", [])
	var maximum: Variant = context.get("max_ham", [])
	var blocked: Variant = context.get("wounds", [])
	for values in [current, maximum, blocked]:
		if not values is Array or values.size() != 3: pools_valid = false; vitals_valid = false; return false
		for value in values:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0:
				pools_valid = false; vitals_valid = false; return false
	for index in range(3):
		if float(maximum[index]) <= 0 or float(blocked[index]) > float(maximum[index]) or float(current[index]) > float(maximum[index]):
			pools_valid = false; vitals_valid = false; return false
	if ham.size() != 9: ham.resize(9); ham.fill(0)
	if max_ham.size() != 9: max_ham.resize(9); max_ham.fill(0)
	if wounds.size() != 9: wounds.resize(9); wounds.fill(0)
	for index in range(3):
		ham[index * 3] = current[index]
		max_ham[index * 3] = maximum[index]
		wounds[index * 3] = blocked[index]
	pools_valid = true; vitals_valid = true
	# A native contact command is consumed by its gesture/receipt, not by routine
	# HAM replication while the player reaches towards the creature.
	# The entertainer owns its multi-frame gesture and consumes it on dispatch.
	# Routine HAM replication must not cancel that noncombat selection.
	if selection_owner != "entertainer" and (selected.is_empty() or selection.get("activation","")!="native_contact"): primed = false
	return true
