extends SceneTree
var checks := 0
var errors: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func wait_physics(count: int) -> void:
	for i in range(count): await physics_frame

func run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/player_postures/catalog.json"))
	var curve := PackedVector2Array()
	for point in source.jump.height_curve: curve.append(Vector2(point[0], point[1]))
	var model := SwgViewPosture.new()
	check(model.configure_jump(curve), "Original jump curve accepted")
	check(not model.configure_jump(PackedVector2Array([Vector2(0,0),Vector2(0,1)])), "Malformed time curve rejected")
	check(model.press_jump(0, true, true).action == "jump", "Grounded standing jump starts")
	check(model.press_jump(0, true, true).action == "none", "Jump cannot stack")
	var peak := 0.0
	for i in range(360):
		peak = maxf(peak, float(model.advance(1.0/90, 0, 1.7, true).offset))
	check(peak > 0.48 and peak < 0.53 and model.get_jump_time() < 0, "Source jump height and duration preserved")
	check(not model.knock_down(2), "Prone is immune")
	check(model.knock_down(0), "Standing can be knocked down")
	model.advance(0.5, 0, 1.7, true)
	check(model.is_knocked_down() and model.get_view_offset() < -1.3, "Knockdown lowers viewpoint")
	check(model.press_jump(1, true, true).posture == 1, "Jump requests kneeling recovery")
	model.resolve_recovery(false)
	check(model.is_knocked_down(), "Rejected recovery remains knocked down")
	model.advance(0.2, 0, 1.7, true)
	check(model.press_jump(0, true, true).posture == 0, "Fresh attempt requests standing recovery")
	model.resolve_recovery(true)
	check(not model.is_knocked_down(), "Accepted recovery clears knockdown")
	model.knock_down(0)
	check(model.advance(0.01, 2, 0.5, true).auto_prone_recovery and not model.is_knocked_down(), "Physical prone auto-recovers")
	# HAM uses three independent segments: current, empty, and wounded.
	var pools := preload("res://combat/ability_state.gd").new()
	var context := {"character_id":"feedback-test", "complete":true,
		"ham":[700,300,300,400,300,300,900,300,300], "max_ham":[1000,300,300,1000,300,300,1000,300,300],
		"wounds":[200,0,0,100,0,0,50,0,0], "posture":0}
	pools.refresh_context(context)
	var bars := pools.readout()
	check(is_equal_approx(float(bars[0].fill), 0.7) and is_equal_approx(float(bars[0].blocker), 0.2), "Health fill and wound blocker are distinct")
	check(bars[1].current == 400 and bars[2].wounds == 50, "Action and mind bind correct HAM indices")
	var hud := preload("res://combat/wrist_ham.gd").new()
	root.add_child(hud)
	hud.pools = pools
	hud.update_readout(Transform3D(Basis.IDENTITY, Vector3(0,1,-0.4)), Vector3(0,1.7,0), true)
	check(hud.visible and hud.bars[0].blocker.visible and hud.bars[0].wounds.text == "−200", "Wrist hologram shows visible wound block")
	check(hud.global_position.y > 1.10, "HAM readout clears the top of weapon wrist")
	for roll in [0.0, PI/2, PI, -PI/2]:
		for side in [-1.0, 1.0]:
			var mount := Transform3D(Basis(Vector3.FORWARD, roll), Vector3(side*0.3,1,-0.4))
			hud.update_readout(mount,Vector3(0,1.7,0),true)
			check(hud.global_position.distance_to(mount.origin) >= 0.119 and hud.global_basis.is_finite(), "HAM clears rolled wrist on either hand")
	pools.refresh_context({"character_id":"feedback-test", "complete":false})
	hud.update_readout(Transform3D.IDENTITY, Vector3(0,1,1), true)
	check(not hud.bars[0].fill.visible and hud.bars[0].wounds.text == "—", "Unknown pools never display fabricated health")
	hud.free()
	# Original skill graph layout and authenticated learned-state presentation.
	var ui := preload("res://scripts/datapad_ui.gd").new()
	root.add_child(ui)
	ui.size = Vector2(900,625)
	ui.set_skills(["combat_marksman_novice", "combat_marksman_pistol_01"], true)
	ui.select_category("skills")
	var index := -1
	for i in range(ui.professions.catalog.professions.size()):
		if ui.professions.catalog.professions[i].id == "combat_marksman": index = i
	ui.professions.show_profession(index)
	check(ui.professions.catalog.professions.size() == 49 and ui.professions.buttons.size() == 18, "49 source professions; all 18 Marksman boxes present")
	check(ui.professions.buttons.combat_marksman_pistol_01.text.strip_edges().ends_with("Learned"), "Owned box displays learned")
	check(ui.professions.buttons.combat_marksman_pistol_02.text.strip_edges().ends_with("Prerequisites met"), "Next box uses source prerequisites")
	check(ui.professions.buttons.combat_marksman_master.text.strip_edges().ends_with("Locked"), "Master cannot appear unlocked from novice")
	ui.professions.buttons.combat_marksman_pistol_02.pressed.emit()
	check(ui.detail_description.text.contains("Credits:") and ui.detail_description.text.contains("Prerequisites:") and ui.delete_button.disabled, "Skill details show costs and cannot be deleted")
	ui.set_skills([], false)
	check(ui.professions.buttons.combat_marksman_novice.text.strip_edges().ends_with("Unknown"), "Missing learned-state is distinct from untrained")
	ui.select_category("waypoints")
	check(not ui.professions.visible and ui.list.visible, "Skills tab does not break datapad entry list")
	ui.free()
	# Actual desktop native controller: jump changes camera, never capsule Y.
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20,0.2,20)
	shape.shape = box
	floor.add_child(shape)
	floor.position.y = -0.1
	root.add_child(floor)
	for action in ["move_left", "move_right", "move_forward", "move_back", "sprint", "jump"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var player := preload("res://scripts/player.gd").new()
	root.add_child(player)
	player.active = true
	await wait_physics(12)
	var start_y := player.global_position.y
	var eye_y := player.get_camera().global_position.y
	var input := InputEventAction.new()
	input.action = "jump"
	input.pressed = true
	Input.parse_input_event(input)
	await wait_physics(2)
	input = InputEventAction.new()
	input.action = "jump"
	input.pressed = false
	Input.parse_input_event(input)
	var camera_peak := 0.0
	var body_peak := 0.0
	for i in range(200):
		await physics_frame
		camera_peak = maxf(camera_peak, player.get_camera().global_position.y - eye_y)
		body_peak = maxf(body_peak, absf(player.global_position.y - start_y))
	check(camera_peak > 0.48 and body_peak < 0.01, "Actual jump input raises viewpoint without lifting physics body")
	check(player.receive_combat_knockdown(), "Desktop knockdown accepted")
	await wait_physics(30)
	check(player.feedback.motion.is_knocked_down() and not player.combat_actions_allowed(), "Knockdown persists and blocks combat")
	player.request_posture(2)
	await wait_physics(3)
	check(not player.feedback.motion.is_knocked_down() and player.get_posture() == 2, "Desktop prone recovers without jump")
	player.request_posture(0)
	player.receive_combat_knockdown()
	await wait_physics(15)
	player.reset_spawn()
	await wait_physics(3)
	check(not player.feedback.motion.is_knocked_down() and not player.movement_locked and absf(player.presentation_height)<0.01, "Desktop reset clears presentation and movement lock")
	player.free()
	floor.free()
	var report := {"test":"player_feedback", "checks":checks, "passed":errors.is_empty(), "errors":errors, "live_core3":false, "gpu_validation":false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../runtime/evidence/player-feedback"))
	FileAccess.open("res://../runtime/evidence/player-feedback/client.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
