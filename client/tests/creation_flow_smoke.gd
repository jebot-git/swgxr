extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func wait_idle(app: Node, timeout := 100.0) -> bool:
	var until := Time.get_ticks_msec() + int(timeout * 1000)
	while app.busy and Time.get_ticks_msec() < until:
		await process_frame
	return not app.busy

func finish(report: Dictionary, passed: bool) -> void:
	report["passed"] = passed
	print(JSON.stringify(report))
	var output := ProjectSettings.globalize_path("res://../runtime/evidence/creation-flow.json")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0 if passed else 1)

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	var report := {"test": "creator_ui_to_core3_avatar"}
	if not await wait_idle(app) or not app.core3_ready:
		report.error = "Core3 readiness failed"
		finish(report, false)
		return
	var suffix := ""
	var seed_value := Time.get_ticks_usec() + int(Time.get_unix_time_from_system())
	for i in range(7):
		suffix += String.chr(97 + seed_value % 26)
		seed_value = seed_value / 26
	app.account_input.text = "creator" + suffix
	app.open_creator()
	var creator = app.creator
	creator.select_race_id("human_female")
	for i in range(creator.profession_pick.item_count):
		if creator.profession_pick.get_item_metadata(i) == "combat_brawler":
			creator.profession_pick.select(i)
			creator.profession_pick.item_selected.emit(i)
			break
	creator.name_input.text = "Rena" + suffix
	creator.biography.text = "Created through the native prototype character creator."
	creator.height_slider.value = 1.025
	var sliders: Array = creator.controls_box.find_children("*", "HSlider", true, false)
	if not sliders.is_empty():
		var slider: HSlider = sliders[0]
		slider.value = slider.min_value + (slider.max_value - slider.min_value) * 0.7
	for slider in creator.hair_controls_box.find_children("*", "HSlider", true, false):
		slider.value = minf(slider.max_value, slider.value + 2)
	await process_frame
	var requested: Dictionary = creator.payload()
	report["account"] = app.account_input.text
	report["requested"] = requested.duplicate(true)
	report["connected_ui"] = not creator.create_button.disabled and "Connected" in creator.status_label.text
	creator.create_button.pressed.emit()
	if not await wait_idle(app) or app.characters.is_empty() or creator.visible:
		report.error = creator.status_label.text
		finish(report, false)
		return
	var character: Dictionary = app.characters[app.character_list.get_selected_items()[0]]
	report["created"] = character
	app.enter_button.pressed.emit()
	if not await wait_idle(app) or app.avatar == null or app.stage == null:
		report.error = app.status.text
		finish(report, false)
		return
	app.player.testing = true
	var authoritative: Dictionary = await app.api(HTTPClient.METHOD_GET, "/characters/" + str(character.id) + "?account=" + app.account_input.text.uri_encode())
	var actual: Dictionary = authoritative.get("character", {}).get("appearance", {})
	var exact: bool = not actual.is_empty() and actual.get("source", "") == "core3_replication"
	for key in requested.customization:
		exact = exact and actual.get("customization", {}).get(key) == requested.customization[key]
	var hair: Dictionary = actual.get("hair", {}) if actual.get("hair") is Dictionary else {}
	for key in requested.hair_customization:
		exact = exact and hair.get("customization", {}).get(key) == requested.hair_customization[key]
	exact = exact and absf(float(actual.get("height", 0)) - float(requested.height)) < 0.0001
	report["authoritative"] = actual
	report["exact_appearance"] = exact
	report["avatar"] = app.avatar.report
	report["local_stage_loaded"] = app.stage != null
	report["session"] = app.session_mode
	report["capsule_height"] = app.player.avatar_height
	finish(report, exact and report.connected_ui and character.name == requested.name and app.avatar.report.get("parts", 0) > 0 and str(app.avatar.report.get("error", "")).is_empty())
