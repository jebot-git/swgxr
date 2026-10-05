extends PanelContainer
const FrontendChoice=preload("res://scripts/frontend_choice.gd")

signal create_requested(payload: Dictionary)
signal closed
const Avatar = preload("res://scripts/avatar.gd")
var options: Dictionary = {}
var tabs: TabContainer
var catalog: Dictionary = {}
var race_id := "human_male"
var customization: Dictionary = {}
var hair_customization: Dictionary = {}
var backend_ready := false
var working := false
var species_pick: FrontendChoice
var sex_pick: FrontendChoice
var hair_pick: FrontendChoice
var profession_pick: FrontendChoice
var name_input: LineEdit
var biography: TextEdit
var height_slider: HSlider
var controls_box: VBoxContainer
var hair_controls_box: VBoxContainer
var status_label: Label
var summary: Label
var create_button: Button
var preview: Node3D
var avatar: Node3D
var preview_camera: Camera3D
var viewport: SubViewport
var race_options: Dictionary = {}
var updating := false
var refresh_pending := false
var rendered_signature := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 32
	offset_top = 74
	offset_right = -32
	offset_bottom = -26
	theme = preload("res://scripts/frontend_theme.gd").build()
	add_theme_stylebox_override("panel", preload("res://scripts/datapad_theme.gd").box("071c29", "3ea8b9", 2, 20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 2)
	header.add_child(heading)
	var eyebrow := label("CHARACTER REGISTRATION", 16)
	eyebrow.add_theme_color_override("font_color", Color("65deee"))
	heading.add_child(eyebrow)
	heading.add_child(label("Create your character", 30))
	var close_button := Button.new()
	close_button.text = "Back to characters"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(func(): closed.emit())
	header.add_child(close_button)
	column.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)
	tabs = TabContainer.new()
	tabs.custom_minimum_size.x = 470
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_stretch_ratio = 1.1
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(tabs)
	var species_tab := stage_page("01 Species")
	species_tab.add_child(label("Choose your species", 23))
	species_tab.add_child(hint_label("Your species sets your appearance and available customization."))
	species_tab.add_child(field_label("SPECIES"))
	species_pick = preload("res://scripts/frontend_choice.gd").new()
	species_pick.fit_to_longest_item = false
	species_pick.custom_minimum_size.y = 44
	species_pick.item_selected.connect(func(_index): rebuild_sexes())
	species_tab.add_child(species_pick)
	species_tab.add_child(field_label("SEX"))
	sex_pick = preload("res://scripts/frontend_choice.gd").new()
	sex_pick.custom_minimum_size.y = 44
	sex_pick.item_selected.connect(func(_index): select_race())
	species_tab.add_child(sex_pick)
	species_tab.add_child(hint_label("Continue to customize your face, body and hair."))
	var appearance_tab := stage_page("02 Appearance")
	appearance_tab.add_child(label("Make it your own", 23))
	appearance_tab.add_child(field_label("HAIR / HEAD DETAIL"))
	hair_pick = preload("res://scripts/frontend_choice.gd").new()
	hair_pick.fit_to_longest_item = false
	hair_pick.custom_minimum_size.y = 44
	hair_pick.item_selected.connect(func(_index):
		rebuild_hair_controls()
		queue_preview()
	)
	appearance_tab.add_child(hair_pick)
	hair_controls_box = VBoxContainer.new()
	appearance_tab.add_child(hair_controls_box)
	appearance_tab.add_child(field_label("HEIGHT"))
	height_slider = HSlider.new()
	height_slider.min_value = 0.9
	height_slider.max_value = 1.1
	height_slider.step = 0.005
	height_slider.value = 1
	height_slider.custom_minimum_size.y = 32
	height_slider.value_changed.connect(func(_value): queue_preview())
	appearance_tab.add_child(height_slider)
	appearance_tab.add_child(HSeparator.new())
	controls_box = VBoxContainer.new()
	controls_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_box.add_theme_constant_override("separation", 14)
	appearance_tab.add_child(controls_box)
	var identity := stage_page("03 Identity")
	identity.add_child(label("Begin your story", 23))
	identity.add_child(field_label("STARTING PROFESSION"))
	profession_pick = preload("res://scripts/frontend_choice.gd").new()
	profession_pick.fit_to_longest_item = false
	profession_pick.custom_minimum_size.y = 44
	profession_pick.item_selected.connect(func(_index): queue_preview())
	identity.add_child(profession_pick)
	identity.add_child(field_label("CHARACTER NAME"))
	name_input = LineEdit.new()
	name_input.placeholder_text = "First name or first and last name"
	name_input.max_length = 32
	name_input.custom_minimum_size.y = 44
	identity.add_child(name_input)
	identity.add_child(field_label("BIOGRAPHY · OPTIONAL"))
	biography = TextEdit.new()
	biography.custom_minimum_size.y = 180
	biography.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	biography.placeholder_text = "Your character’s story"
	identity.add_child(biography)
	identity.add_child(hint_label("Create to save your character on the connected server."))
	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size.x = 390
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.add_theme_stylebox_override("panel", preload("res://scripts/datapad_theme.gd").box("06131e", "245363", 1, 14))
	columns.add_child(preview_frame)
	var right := VBoxContainer.new()
	preview_frame.add_child(right)
	var preview_header := HBoxContainer.new()
	right.add_child(preview_header)
	var preview_title := field_label("APPEARANCE PREVIEW")
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_header.add_child(preview_title)
	preview_header.add_child(label("DRAG TO ROTATE", 14))
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size.y = 300
	container.gui_input.connect(preview_input)
	right.add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(600, 560)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.handle_input_locally = false
	container.add_child(viewport)
	preview = Node3D.new()
	viewport.add_child(preview)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("06131e")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d6e4ee")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	preview.add_child(environment)
	preview_camera = Camera3D.new()
	preview_camera.position = Vector3(0, 1.0, 3.2)
	preview_camera.fov = 42
	preview_camera.cull_mask = 3
	preview.add_child(preview_camera)
	avatar = Avatar.new()
	avatar.rotation.y = PI
	preview.add_child(avatar)
	catalog = avatar.load_catalog()
	right.add_child(HSeparator.new())
	summary = label("Loading character preview…", 20)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size.y = 58
	right.add_child(summary)
	column.add_child(HSeparator.new())
	status_label = hint_label("Choose your species, appearance and identity.")
	column.add_child(status_label)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var previous := Button.new()
	previous.text = "Back to characters"
	previous.custom_minimum_size.y = 46
	previous.pressed.connect(func():
		if tabs.current_tab > 0: tabs.current_tab -= 1
		else: closed.emit()
	)
	actions.add_child(previous)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	var next := Button.new()
	next.text = "Continue to appearance  ›"
	next.custom_minimum_size.y = 46
	next.pressed.connect(func(): tabs.current_tab = mini(2, tabs.current_tab + 1))
	actions.add_child(next)
	create_button = Button.new()
	create_button.text = "Create character"
	create_button.custom_minimum_size = Vector2(240, 46)
	create_button.visible = false
	create_button.pressed.connect(submit)
	actions.add_child(create_button)
	tabs.tab_changed.connect(func(index):
		previous.text = "Back to characters" if index == 0 else "‹  Previous step"
		next.visible = index < 2
		next.text = "Continue to appearance  ›" if index == 0 else "Continue to identity  ›"
		create_button.visible = index == 2
	)
	set_options({})
	set_backend_state(false)

func stage_page(title: String) -> VBoxContainer:
	var scroll := preload("res://scripts/frontend_scroll.gd").new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	return content

func field_label(text: String) -> Label:
	var result := label(text, 16)
	result.add_theme_color_override("font_color", Color("65deee"))
	return result

func hint_label(text: String) -> Label:
	var result := label(text, 18)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_color_override("font_color", Color("8db8c5"))
	return result

func label(text: String, size := 17) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	return result

func set_options(value: Dictionary) -> void:
	options = value
	updating = true
	species_pick.clear()
	var species: Array = options.get("species", [])
	if species.is_empty():
		var seen := {}
		for id in catalog.get("races", {}):
			var key := str(id).rsplit("_", true, 1)[0]
			if not seen.has(key):
				seen[key] = true
				species.append({"id": key, "label": key.capitalize()})
	for entry in species:
		var id: String = entry.get("id", entry.get("species", "")) if entry is Dictionary else str(entry)
		var title: String = entry.get("label", entry.get("name", id.capitalize())) if entry is Dictionary else id.capitalize()
		species_pick.add_item(title)
		species_pick.set_item_metadata(species_pick.item_count - 1, id)
	profession_pick.clear()
	for entry in options.get("professions", []):
		var id: String = entry.get("id", "")
		profession_pick.add_item(str(entry.get("label", entry.get("name", id))))
		profession_pick.set_item_metadata(profession_pick.item_count - 1, id)
	updating = false
	rebuild_sexes()

func rebuild_sexes() -> void:
	if updating or species_pick.item_count == 0:
		return
	updating = true
	sex_pick.clear()
	var species: String = species_pick.get_selected_metadata()
	for sex in ["male", "female"]:
		var id: String = species + "_" + str(sex)
		if catalog.get("races", {}).has(id) or options.get("races", {}).has(id):
			sex_pick.add_item(sex.capitalize())
			sex_pick.set_item_metadata(sex_pick.item_count - 1, sex)
	updating = false
	select_race()

func select_race() -> void:
	if updating or species_pick.item_count == 0 or sex_pick.item_count == 0:
		return
	updating = true
	race_id = str(species_pick.get_selected_metadata()) + "_" + str(sex_pick.get_selected_metadata())
	race_options = options.get("races", {}).get(race_id, catalog.get("races", {}).get(race_id, {}))
	customization.clear()
	hair_customization.clear()
	for child in controls_box.get_children():
		controls_box.remove_child(child)
		child.queue_free()
	var height: Dictionary = race_options.get("height", {})
	height_slider.min_value = float(height.get("min", race_options.get("height_min", 0.9)))
	height_slider.max_value = float(height.get("max", race_options.get("height_max", 1.1)))
	height_slider.value = float(height.get("default", 1.0))
	hair_pick.clear()
	if race_options.get("allow_bald", true):
		hair_pick.add_item("None")
		hair_pick.set_item_metadata(0, "")
	for hair in race_options.get("hair", catalog.get("races", {}).get(race_id, {}).get("hair", [])):
		hair_pick.add_item(str(hair.get("label", hair.get("name", "Style %d" % hair_pick.item_count))))
		hair_pick.set_item_metadata(hair_pick.item_count - 1, str(hair.get("template", hair.get("id", ""))))
	var default_hair: String = str(race_options.get("default_hair", catalog.get("races", {}).get(race_id, {}).get("default_hair", "")))
	for i in range(hair_pick.item_count):
		if str(hair_pick.get_item_metadata(i)).replace("/shared_", "/") == default_hair.replace("/shared_", "/"):
			hair_pick.select(i)
			break
	rebuild_hair_controls()
	var controls: Array = race_options.get("original_controls", catalog.get("races", {}).get(race_id, {}).get("customizations", []))
	var seen := {}
	var main_colors: Array = avatar.main_palette_variables(str(catalog.get("races", {}).get(race_id, {}).get("body", "")))
	for control in controls:
		if control.get("is_scale", false) or not control.get("supported", true) or control.get("group", "") == "hair" or int(control.get("source", {}).get("IS_VAR_HAIR_COLOR", 0)) == 1:
			continue
		var variables: Array = control.get("variables", [])
		if str(control.get("type", "")) == "color" and not variables.is_empty() and not str(variables[0]) in main_colors:
			continue
		var signature := ",".join(variables)
		if variables.is_empty() or seen.has(signature):
			continue
		seen[signature] = true
		add_original_control(control)
	updating = false
	refresh_preview()


func descriptor(variable: String, hair_scope := false) -> Dictionary:
	var candidates: Array = selected_hair().get("appearance_controls", []) if hair_scope else race_options.get("appearance_controls", [])
	for entry in candidates:
		if str(entry.get("id", "")).get_file() == variable:
			return entry
	var palette: Dictionary = selected_hair().get("palette_variables", {}).get(variable, {}) if hair_scope else catalog.get("races", {}).get(race_id, {}).get("palette_variables", {}).get(variable, {})
	return {"id": palette.get("variable_path", "/shared_owner/" + variable), "min": palette.get("min", 0), "max": palette.get("max", 255), "default": palette.get("default", 0), "colors": palette.get("colors", [])}

func add_original_control(control: Dictionary, force_hair := false) -> void:
	var variables: Array = control.get("variables", [])
	var paired := variables.size() == 2 and str(control.get("type", "")) != "color"
	var is_hair: bool = force_hair or control.get("group", "") == "hair" or int(control.get("source", {}).get("IS_VAR_HAIR_COLOR", 0)) == 1
	var first := descriptor(str(variables[0]), is_hair)
	var first_id: String = first.id
	var second_id: String = str(descriptor(str(variables[1]), is_hair).id) if paired else ""
	var initial := 0.5 if paired else float(first.get("default", 0))
	var values: Dictionary = hair_customization if is_hair else customization
	values[first_id] = 0 if paired else int(initial)
	if paired:
		values[second_id] = 0
	var box := VBoxContainer.new()
	(hair_controls_box if is_hair else controls_box).add_child(box)
	box.add_child(label(str(control.get("name", "Appearance")).replace("color_", "").replace("_", " ").capitalize(), 20))
	var row := HBoxContainer.new()
	box.add_child(row)
	var slider := HSlider.new()
	slider.min_value = 0 if paired else float(first.get("min", 0))
	slider.max_value = 1 if paired else float(first.get("max", 255))
	slider.step = 1.0 / 255.0 if paired else 1
	slider.value = (slider.min_value + slider.max_value - initial) if not paired and control.get("reverse", false) else initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 32
	row.add_child(slider)
	var number := label("50%" if paired else str(int(initial)), 18)
	number.custom_minimum_size.x = 54
	row.add_child(number)
	var swatch: ColorRect
	var colors: Array = first.get("colors", [])
	if colors.is_empty():
		colors = catalog.get("races", {}).get(race_id, {}).get("palette_variables", {}).get(str(variables[0]), {}).get("colors", [])
	if not colors.is_empty():
		swatch = ColorRect.new()
		swatch.custom_minimum_size = Vector2(28, 22)
		row.add_child(swatch)
		set_swatch(swatch, colors, int(initial))
	slider.value_changed.connect(func(value):
		var mapped: float = (slider.min_value + slider.max_value - value) if control.get("reverse", false) else value
		if paired:
			values[first_id] = roundi(maxf(0, 1 - mapped * 2) * 255)
			values[second_id] = roundi(maxf(0, mapped * 2 - 1) * 255)
		else:
			values[first_id] = int(mapped)
		number.text = "%d%%" % roundi(value * 100) if paired else str(int(value))
		if not colors.is_empty():
			set_swatch(swatch, colors, int(value))
		queue_preview()
	)

func set_swatch(swatch: ColorRect, colors: Array, index: int) -> void:
	var color: Array = colors[clampi(index, 0, colors.size() - 1)]
	swatch.color = Color(float(color[0]), float(color[1]), float(color[2]), 1)

func payload() -> Dictionary:
	return {"name": name_input.text.strip_edges(), "species": str(species_pick.get_selected_metadata()), "sex": str(sex_pick.get_selected_metadata()), "profession": str(profession_pick.get_selected_metadata()) if profession_pick.item_count > 0 else "", "height": height_slider.value, "customization": customization.duplicate(), "hair_template": str(hair_pick.get_selected_metadata()) if hair_pick.item_count > 0 else "", "hair_customization": hair_customization.duplicate(), "biography": biography.text}

func queue_preview() -> void:
	if updating or refresh_pending:
		return
	refresh_pending = true
	call_deferred("refresh_preview")

func refresh_preview() -> void:
	refresh_pending = false
	if race_id.is_empty():
		return
	var values := payload()
	var signature := race_id + "|" + str(values.hair_template) + "|" + str(values.profession)
	var result: Dictionary
	if signature != rendered_signature:
		result = avatar.configure(race_id, values)
		rendered_signature = signature
	else:
		avatar.apply_customization(values)
		result = avatar.report
	if not str(result.get("error", "")).is_empty():
		summary.text = str(result.error)
	else:
		var height: float = avatar.height_meters
		preview_camera.position = Vector3(0, height * 0.52, height * 1.8)
		preview_camera.look_at(Vector3(0, height * 0.5, 0))
		var profession := profession_pick.get_item_text(profession_pick.selected) if profession_pick.item_count > 0 else "Choose a profession"
		summary.text = "%s · %s\n%s · %.2f m" % [species_pick.get_item_text(species_pick.selected), sex_pick.get_item_text(sex_pick.selected), profession, height]
	set_backend_state(backend_ready)

func preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		avatar.rotation.y += event.relative.x * 0.01

func set_backend_state(ready: bool) -> void:
	var became_ready := ready and not backend_ready
	backend_ready = ready
	if create_button != null:
		create_button.disabled = not ready or working or profession_pick.item_count == 0 or not str(avatar.report.get("error", "")).is_empty()
		if not ready:
			status_label.text = "Waiting for the connected server. You can still customize your preview."
		elif became_ready and not working:
			status_label.text = "Connected to server. Complete your identity, then create your character."

func set_working(value: bool, message := "") -> void:
	working = value
	if not message.is_empty():
		status_label.text = message
	set_backend_state(backend_ready)

func submit() -> void:
	if name_input.text.strip_edges().length() < 3:
		status_label.text = "Enter a character name with at least three letters."
		return
	create_requested.emit(payload())

func _process(delta: float) -> void:
	if is_visible_in_tree() and avatar != null:
		avatar.update_motion(delta)

func select_race_id(id: String) -> void:
	var parts := id.rsplit("_", true, 1)
	if parts.size() != 2:
		return
	for i in range(species_pick.item_count):
		if str(species_pick.get_item_metadata(i)) == parts[0]:
			species_pick.select(i)
			rebuild_sexes()
			break
	for i in range(sex_pick.item_count):
		if str(sex_pick.get_item_metadata(i)) == parts[1]:
			sex_pick.select(i)
			select_race()
			break

func selected_hair() -> Dictionary:
	if hair_pick.item_count == 0:
		return {}
	var template: String = str(hair_pick.get_selected_metadata())
	for hair in race_options.get("hair", catalog.get("races", {}).get(race_id, {}).get("hair", [])):
		if str(hair.get("template", hair.get("id", ""))) == template:
			return hair
	return {}

func rebuild_hair_controls() -> void:
	for child in hair_controls_box.get_children():
		hair_controls_box.remove_child(child)
		child.queue_free()
	hair_customization.clear()
	var selected := selected_hair()
	var controls: Array = selected.get("appearance_controls", [])
	if controls.is_empty():
		for variable in selected.get("palette_variables", {}):
			controls.append({"id": str(variable), "label": "Hair color", "type": "color"})
	var main_colors: Array = avatar.main_palette_variables(str(selected.get("model", "")))
	for control in controls:
		if control.get("type", "") == "color" and not str(control.id).get_file() in main_colors:
			continue
		var title := str(control.get("label", "color"))
		if not title.to_lower().begins_with("hair"): title = "Hair " + title
		add_original_control({"name": title, "variables": [str(control.id).get_file()], "type": control.get("type", "color")}, true)
