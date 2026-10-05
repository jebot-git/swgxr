extends SceneTree
const Rig = preload("res://combat/ranged_rig.gd")
var errors: Array[String] = []
var checks := 0
var menu_signals := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func tracker(side: String) -> XRControllerTracker:
	var item := XRControllerTracker.new()
	item.type = XRServer.TRACKER_CONTROLLER
	item.name = side + "_hand"
	item.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	for action in ["ax_button", "by_button", "primary_click"]: item.set_input(action, false)
	item.set_input("primary", Vector2.ZERO)
	item.set_input("grip", 0.9)
	item.set_input("trigger", 0.0)
	var pose := Transform3D(Basis.IDENTITY, Vector3(-0.2 if side == "left" else 0.2, 1.4, -0.4))
	item.set_pose("grip", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	item.set_pose("aim", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(item)
	return item

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	var head := XRPositionalTracker.new()
	head.type = XRServer.TRACKER_HEAD
	head.name = "head"
	head.set_pose("default", Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(head)
	var left := tracker("left")
	var right := tracker("right")
	for dominant in ["left", "right"]:
		var origin: XROrigin3D = load("res://xr/player_rig.tscn").instantiate()
		root.add_child(origin)
		var body = origin.get_node("PlayerBody")
		body.active = true
		body.set_physics_process(false)
		body.menu_requested.connect(func(): menu_signals += 1)
		var rig := Rig.new()
		origin.add_child(rig)
		check(rig.configure(origin.get_node("XRCamera3D"), body, [fixture.weapons.pistol_cdef], dominant, origin), dominant + " configure")
		rig.set_physics_process(false)
		rig.set_process(false)
		rig.configure_player_combat(fixture.player_combat)
		rig.set_allowed(true)
		rig.draw(0)
		await process_frame
		rig._physics_process(0.01)
		var main: XRControllerTracker = left if dominant == "left" else right
		main.set_input("primary_click", true)
		await process_frame
		rig._physics_process(0.01)
		check(rig.ability_ui.menu_open and body.combat_stick_side == dominant, dominant + " actual joystick opens and captures")
		body.set_interface_capture(false, false)
		var provider = origin.get_node("LeftHand/MovementDirect" if dominant == "left" else "RightHand/MovementTurn")
		check(not provider.enabled, "Other UI release cannot override combat capture")
		main.set_input("primary_click", false)
		main.set_input("primary", Vector2(0, 0.9))
		await process_frame
		rig._physics_process(0.01)
		check(not rig.ability_ui.menu_open and rig.abilities.selected == "lethal_shot", dominant + " real stick selects")
		check(body.combat_stick_side == dominant, "Selection retains capture until stick neutral")
		main.set_input("primary", Vector2.ZERO)
		await process_frame
		rig._physics_process(0.01)
		check(body.combat_stick_side.is_empty(), "Neutral restores locomotion")
		var before := menu_signals
		right.set_input("ax_button", true)
		await process_frame
		rig._physics_process(0.01)
		check(rig.abilities.primed and menu_signals == before, "Actual A primes without opening system menu")
		main.set_input("trigger", 1.0)
		await process_frame
		rig._physics_process(0.01)
		check(rig.weapons[0].state.fired == 1 and not rig.abilities.primed and rig.abilities.cooldowns.has("lethal_shot"), "Actual trigger consumes exactly one ability")
		left.set_input("ax_button", true)
		await process_frame
		check(menu_signals == before + 1, "X retains system menu access")
		rig.set_allowed(false)
		check(body.combat_stick_side.is_empty() and not body.combat_prime_active, "Focus gate releases ability capture immediately")
		origin.free()
		for controller in [left, right]:
			controller.set_input("ax_button", false)
			controller.set_input("trigger", 0.0)
		await process_frame
	for item in [left, right, head]: XRServer.remove_tracker(item)
	var report := {"test":"profession_xr_input", "passed":errors.is_empty(), "checks":checks, "errors":errors, "mocked_tracking":true, "hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/professions/xr-input.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
