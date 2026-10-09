extends SceneTree
const Rig = preload("res://combat/ranged_rig.gd")
# The previous fixture asserted the retired radial selector/priming path. Held
# weapons now toggle real-time target VATS without consuming the movement stick.
class Target extends StaticBody3D:
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false}
	var visual:Node3D
	func core3_identity()->Dictionary:return {"id":"201","session_id":"xr-input-fixture"}
	func is_targetable()->bool:return true
	func visual_bounds()->AABB:return AABB(Vector3(-1,0,-.3),Vector3(2,2,.6))
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
	for action in ["ax_button", "by_button", "primary_click", "menu_button"]: item.set_input(action, false)
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
	var profile:Dictionary=fixture.weapons.pistol_cdef.duplicate(true)
	profile["item_id"]="99";profile["certified"]=true
	profile["abilities"]=[{"id":"lethal_shot","label":"Lethal Shot","activation":"native_ranged","conditions_met":true,"sac_policy":"fixed","base_sac":{"health":0,"action":40,"mind":20},"cooldown_seconds":15.,"max_range_m":40.}]
	profile["ability_loadout"]={"slots":["lethal_shot","","",""],"ultimate":""}
	var target:=Target.new();root.add_child(target);target.position=Vector3(0,0,-5);target.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=target.visual_bounds().size;shape.shape=box;shape.position=target.visual_bounds().get_center();target.add_child(shape)
	await physics_frame
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
		check(rig.configure(origin.get_node("XRCamera3D"), body, [profile], dominant, origin), dominant + " configure")
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
		check(rig.target_abilities.target_id=="201" and not rig.ability_ui.menu_open and body.combat_stick_side.is_empty(), dominant + " actual joystick opens target VATS without movement capture")
		body.set_interface_capture(false, false)
		var provider = origin.get_node("LeftHand/MovementDirect" if dominant == "left" else "RightHand/MovementTurn")
		check(provider.enabled, "Other UI release preserves movement during VATS")
		main.set_input("primary_click", false)
		main.set_input("primary", Vector2(0, 0.9))
		await process_frame
		rig._physics_process(0.01)
		check(not rig.ability_ui.menu_open and rig.target_abilities.target_id=="201", dominant + " movement stick leaves target VATS selected")
		check(body.combat_stick_side.is_empty(), "VATS leaves the movement stick available")
		main.set_input("primary", Vector2.ZERO)
		await process_frame
		rig._physics_process(0.01)
		check(body.combat_stick_side.is_empty(), "Neutral restores locomotion")
		var before := menu_signals
		right.set_input("ax_button", true)
		await process_frame
		rig._physics_process(0.01)
		check(not rig.abilities.primed and menu_signals == before, "Actual A cannot prime the retired weapon ability path or open system menu")
		main.set_input("trigger", 1.0)
		await process_frame
		rig._physics_process(0.01)
		check(rig.weapons[0].state.fired == 1 and not rig.abilities.primed and float(rig.abilities.cooldowns.get("lethal_shot",0))<=0, "Trigger fires once without a special attack when no ability marker is aimed")
		left.set_input("menu_button", true)
		await process_frame
		check(menu_signals == before + 1, "Dedicated menu button retains system menu access")
		rig.set_allowed(false)
		check(body.combat_stick_side.is_empty() and not body.combat_prime_active and rig.target_abilities.target_id.is_empty(), "Focus gate closes VATS and releases capture immediately")
		origin.free()
		for controller in [left, right]:
			controller.set_input("ax_button", false)
			controller.set_input("menu_button", false)
			controller.set_input("trigger", 0.0)
		await process_frame
	target.free()
	for item in [left, right, head]: XRServer.remove_tracker(item)
	var report := {"test":"profession_xr_input", "passed":errors.is_empty(), "checks":checks, "errors":errors, "mocked_tracking":true, "hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/professions/xr-input.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
