extends SceneTree
const State = preload("res://combat/weapon_state.gd")
const Abilities = preload("res://combat/ability_state.gd")
const Rig = preload("res://combat/ranged_rig.gd")
var errors: Array[String] = []
var checks := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	var pistol: Dictionary = fixture.weapons.pistol_cdef
	var knife: Dictionary = fixture.weapons.knife_survival
	var abilities := Abilities.new()
	abilities.refresh_context(fixture.player_combat)
	check(not abilities.select(pistol, "melee_assault"), "Wrong weapon cannot select melee ability")
	check(abilities.select(pistol, "lethal_shot") and abilities.toggle_prime(pistol), "Eligible ranged ability primes")
	var state := State.new()
	state.configure(pistol, pistol.core3.certificationsRequired)
	state.ability_state = abilities
	check(state.effective_rpm() > float(pistol.rpm), "Speed increases RPM")
	state.tick(0.01, 0, true, false)
	check(state.tick(1, 1, false, false).is_empty() and abilities.primed, "Blocked attack does not spend prime")
	state.tick(0.01, 0, true, false)
	var shot := state.tick(0.01, 1, true, false)
	check(shot.has("ability") and not abilities.primed, "Next valid attack consumes one prime")
	check(shot.get("ability", {}).get("damage_multiplier", 0) == 3.75, "Original Overcharge Shot 2 multiplier")
	var spent: Array = shot.get("sac_spent", [])
	check(spent.size() == 3 and float(abilities.ham[0]) == 1000 - spent[0] and float(abilities.ham[3]) == 1000 - spent[1] and float(abilities.ham[6]) == 1000 - spent[2], "SAC charges all three pools once")
	var normal := shot.duplicate(true)
	normal.erase("ability")
	var normal_damage := State.damage_at(normal, 1, {}, 0, 0.5, 1)
	var boosted := State.damage_at(shot, 1, {}, 0, 0.5, 1)
	check(is_equal_approx(float(boosted.damage), float(normal_damage.damage) * 3.75), "One attack applies source multiplier")
	check(not abilities.toggle_prime(pistol), "Cooldown blocks re-prime")
	abilities.select(fixture.weapons.rifle_e11, "lethal_shot")
	check(not abilities.toggle_prime(fixture.weapons.rifle_e11), "Switching class cannot bypass shared cooldown")
	var remaining := float(abilities.cooldowns.lethal_shot)
	abilities.refresh_context(fixture.player_combat)
	check(float(abilities.cooldowns.lethal_shot) == remaining and float(abilities.ham[0]) == 1000 - spent[0], "Refresh cannot refill HAM or clear cooldown")
	abilities.refresh_context({"character_id":fixture.player_combat.character_id, "complete":false})
	abilities.refresh_context(fixture.player_combat)
	check(float(abilities.ham[0]) == 1000 - spent[0], "Incomplete then complete refresh cannot refund spent SAC")
	abilities.tick(remaining)
	check(abilities.toggle_prime(pistol), "Cooldown expires")
	abilities.primed = false
	abilities.ham[0] = abilities.costs(pistol.abilities[0])[0]
	check(not abilities.toggle_prime(pistol), "Exact remaining HAM cost is rejected as CoreCU requires")
	abilities.refresh_context({"character_id":"other", "complete":false})
	abilities.select(pistol, "lethal_shot")
	check(not abilities.toggle_prime(pistol), "Missing authoritative pool observation fails closed")
	var melee := State.new()
	melee.configure(knife, knife.core3.certificationsRequired)
	check(melee.melee_thresholds(false).travel < float(knife.swing_travel_reference)*100/float(knife.stance_recovery), "Melee speed shortens stance recovery distance")
	check(is_equal_approx(float(melee.melee_thresholds(false).power), float(knife.power)), "Accuracy and speed do not change Power")
	state.rounds = 1
	state.reload_until = -1
	state.reload()
	check(state.reload_until - state.clock < float(pistol.reload_seconds), "Speed improves capacity recovery")
	# Widened head aiming acquires an off-axis target but respects occlusion.
	var target := preload("res://combat/training_target.gd").new()
	root.add_child(target)
	target.position = Vector3(0.55, 1, -2)
	var projectiles := preload("res://combat/projectiles.gd").new()
	root.add_child(projectiles)
	projectiles.set_physics_process(false)
	await physics_frame
	await physics_frame
	var aim := Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	var hit := {"kind":"melee", "core3":knife.core3, "range_scale":1.0, "range":float(knife.core3.maxRange), "condition_fraction":1.0, "weapon_id":knife.id, "sequence":1, "hit_radius":0.0}
	projectiles.strike_melee(hit, aim, aim)
	check(target.hit_count == 0, "Base head ray misses off-axis target")
	hit.hit_radius = 0.3
	projectiles.strike_melee(hit, aim, aim)
	check(target.hit_count == 1, "Explicit geometry-test tolerance widens hit area")
	hit["ability"] = {"id":"melee_assault", "damage_multiplier":3.0, "knockdown_chance":1.0}
	projectiles.strike_melee(hit, aim, aim)
	check(target.hit_count == 2 and target.knockdown_count == 1, "Ability knockdown propagates on a damaging hit")
	hit.erase("ability")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.1)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.position = Vector3(0, 1, -1)
	await physics_frame
	await physics_frame
	projectiles.strike_melee(hit, aim, aim)
	check(target.hit_count == 2, "Wider hit area cannot hit through a wall")
	wall.free()
	target.position = Vector3(0, 1, -float(hit.range)-1)
	await physics_frame
	await physics_frame
	projectiles.strike_melee(hit, aim, aim)
	check(target.hit_count == 2, "Hit area does not extend weapon range")
	# Ranged controls use local target points; the explicit melee lab retains its circle.
	var body := CharacterBody3D.new()
	root.add_child(body)
	var camera := Camera3D.new()
	body.add_child(camera)
	var rig := Rig.new()
	root.add_child(rig)
	check(rig.configure(camera, body, [pistol, knife]), "Ability rig loads")
	rig.set_physics_process(false)
	rig.set_process(false)
	rig.configure_player_combat(fixture.player_combat)
	rig.set_allowed(true)
	rig.draw(0)
	rig.sample_ability_input(true, Vector2.RIGHT, false, true)
	check(not rig.ability_ui.menu_open and rig.target_abilities.target==null, "Ranged joystick click without eligible actor opens no circle or marker")
	rig.sample_ability_input(false, Vector2.ZERO, true, true)
	check(not rig.abilities.primed, "A does not prime ranged specials")
	rig.sample_ability_input(false, Vector2.ZERO, false, false)
	check(rig.target_abilities.points.is_empty(), "Tracking loss clears local ranged markers")
	rig.draw(1)
	check(rig.active_profile().abilities[0].id == "melee_assault", "Melee weapon exposes only Melee Assault")
	rig.sample_ability_input(true, Vector2.ZERO, false, true)
	rig.sample_ability_input(false, Vector2.ZERO, false, true)
	rig.sample_ability_input(true, Vector2.ZERO, false, true)
	check(not rig.ability_ui.menu_open, "Second stick click closes menu")
	rig.free()
	body.free()
	target.free()
	projectiles.free()
	var report := {"test":"profession_combat", "passed":errors.is_empty(), "checks":checks, "errors":errors, "live_core3":false, "hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/professions/client.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
