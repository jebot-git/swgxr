extends VBoxContainer
signal skill_selected(detail: Dictionary)
var catalog: Dictionary = {}
var learned: Array = []
var known := false
var experience: Dictionary = {}
var experience_known := false
var selected_skill_id := ""
var xp_controls: Dictionary = {}
var selector: OptionButton
var progress: Label
var scroll: ScrollContainer
var tree: VBoxContainer
var profession_index := 0
var buttons: Dictionary = {}
var forget_skills: Dictionary = {}
var available_skill_points := -1
var forgetting_available := true
var forgetting_reason := ""

func _ready() -> void:
	selector = OptionButton.new()
	selector.custom_minimum_size.y = 44
	selector.get_popup().max_size = Vector2i(840, 320)
	selector.item_selected.connect(show_profession)
	add_child(selector)
	progress = Label.new()
	add_child(progress)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	tree = VBoxContainer.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tree)
	var path := "res://../runtime/assets/professions/catalog.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: configure(parsed)
	else: progress.text = "Profession definitions unavailable"

func configure(data: Dictionary) -> void:
	catalog = data
	selector.clear()
	for profession in data.get("professions", []): selector.add_item(str(profession.label))
	if selector.item_count > 0: show_profession(mini(profession_index, selector.item_count - 1))

func set_learned(skills: Array, complete: bool) -> void:
	if learned == skills and known == complete: return
	forget_skills.clear()
	learned = skills.duplicate()
	known = complete
	if not catalog.is_empty(): show_profession(profession_index)

func set_forget_skills(values: Array, points: int = -1) -> void:
	forget_skills.clear()
	available_skill_points = points
	for value in values:
		if not value is Dictionary or not value.get("skill_id") is String or not value.get("eligible") is bool: continue
		var points_value:Variant=value.get("refunded_points")
		if not (points_value is int or points_value is float) or not is_finite(float(points_value)) or float(points_value)<0 or float(points_value)>250 or float(points_value)!=floorf(float(points_value)):continue
		forget_skills[value.skill_id] = value.duplicate(true)
		forget_skills[value.skill_id].refunded_points = int(points_value)
	refresh_selected()

func refresh_selected() -> void:
	if profession_index >= catalog.get("professions", []).size(): return
	for node: Dictionary in catalog.professions[profession_index].nodes:
		if str(node.id) == selected_skill_id: select_skill(node); return

func set_forgetting_available(value:bool,reason:String="")->void:
	forgetting_available=value;forgetting_reason=reason;refresh_selected()

func forget_status(id: String) -> Dictionary:
	var result: Dictionary = {"eligible":false,"reason":"Awaiting current character skills","refunded_points":0}
	if not known or not id in learned: return result
	if not forgetting_available:
		result.reason=forgetting_reason;result.refunded_points=int(forget_skills.get(id,{}).get("refunded_points",0));return result
	for profession: Dictionary in catalog.get("professions", []):
		for node: Dictionary in profession.get("nodes", []):
			if str(node.get("id", "")) in learned and id in node.get("requires", []):
				result.reason = "Forget dependent skills first: " + str(node.get("label", node.id))
				return result
	if not forget_skills.has(id):
		result.reason = "Checking whether this skill can be forgotten"
		return result
	return forget_skills[id].duplicate(true)

func set_experience(values: Dictionary, complete := true) -> void:
	var clean: Dictionary = {}
	for key in values:
		var value: Variant = values[key]
		if not key is String or not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) > 2147483647.0 or float(value) != floorf(float(value)):
			complete = false
			break
		clean[key] = int(value)
	if not complete: clean.clear()
	if experience == clean and experience_known == complete: return
	experience = clean
	experience_known = complete
	# Live snapshots update the bars in place, retaining focus and scroll position.
	for id in xp_controls: update_xp(xp_controls[id])
	if profession_index < catalog.get("professions", []).size():
		for node: Dictionary in catalog.professions[profession_index].nodes:
			if str(node.id) == selected_skill_id: select_skill(node); break

func xp_progress(node: Dictionary) -> Dictionary:
	var cost := maxi(0, int(node.get("xp_cost", 0)))
	var amount := maxi(0, int(experience.get(str(node.get("xp_type", "")), 0)))
	return {"known":experience_known,"current":amount,"required":cost,
		"ratio":clampf(float(amount)/float(cost),0.0,1.0) if cost>0 and experience_known else (1.0 if cost==0 else 0.0)}

func update_xp(entry: Dictionary) -> void:
	var value := xp_progress(entry.node)
	entry.bar.value = value.ratio * 100.0
	entry.label.text = "No XP required" if value.required == 0 else ("%d / %d XP" % [value.current,value.required] if value.known else "XP unavailable")
	entry.bar.modulate = Color("75efe2") if value.ratio>=1.0 else Color("88bfd1")

func state(node: Dictionary) -> String:
	if not known: return "Unknown"
	if str(node.id) in learned: return "Learned"
	var required: Array = node.get("requires", [])
	var count := 0
	for id in required:
		if id in learned: count += 1
	var needed := int(node.get("requires_count", 0))
	if needed <= 0: needed = required.size()
	for id in node.get("excludes", []):
		if id in learned: return "Locked"
	return "Prerequisites met" if count >= needed else "Locked"

func add_skill(parent: Node, node: Dictionary) -> void:
	var button := Button.new()
	button.text = str(node.label) + "\n" + state(node) + ("\n" if state(node) != "Learned" else "")
	button.custom_minimum_size = Vector2(160, 82)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 16)
	button.modulate = Color(0.45, 1, 0.85) if state(node) == "Learned" else Color.WHITE if state(node) == "Prerequisites met" else Color(0.65, 0.75, 0.8)
	button.pressed.connect(func(): select_skill(node))
	parent.add_child(button)
	buttons[node.id] = button
	if state(node) != "Learned":
		var bar := ProgressBar.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.show_percentage = false
		button.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_left = 7; bar.offset_right = -7; bar.offset_top = -21; bar.offset_bottom = -4
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color("08202a"))
		label.add_theme_constant_override("outline_size", 3)
		bar.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		xp_controls[node.id] = {"bar":bar,"label":label,"node":node}
		update_xp(xp_controls[node.id])

func show_profession(index: int) -> void:
	if index < 0 or index >= catalog.get("professions", []).size(): return
	profession_index = index
	selector.select(index)
	for child in tree.get_children(): child.free()
	buttons.clear()
	xp_controls.clear()
	var profession: Dictionary = catalog.professions[index]
	var nodes: Array = profession.nodes
	var owned := nodes.filter(func(node): return str(node.id) in learned).size()
	progress.text = "%d / %d learned · select a box for requirements" % [owned, nodes.size()] if known else "Character skills unavailable · browsing requirements"
	var branches := {}
	var master := {}
	var novice := {}
	var other: Array = []
	for node: Dictionary in nodes:
		var suffix := str(node.id).trim_prefix(str(profession.id) + "_")
		if suffix == "master": master = node
		elif suffix == "novice": novice = node
		elif suffix.right(3) in ["_01", "_02", "_03", "_04"]:
			var branch := suffix.left(-3)
			if not branches.has(branch): branches[branch] = []
			branches[branch].append(node)
		else: other.append(node)
	if not master.is_empty(): add_skill(tree, master)
	var columns := HBoxContainer.new()
	tree.add_child(columns)
	for branch in branches:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		branches[branch].sort_custom(func(a, b): return str(a.id) > str(b.id))
		for node in branches[branch]:
			var arrow := Label.new()
			arrow.text = "^"
			arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(arrow)
			add_skill(column, node)
	if not novice.is_empty(): add_skill(tree, novice)
	for node in other: add_skill(tree, node)
	var selected := nodes.filter(func(node): return str(node.id)==selected_skill_id)
	if not nodes.is_empty(): select_skill(selected[0] if not selected.is_empty() else nodes[0])

func select_skill(node: Dictionary) -> void:
	selected_skill_id = str(node.id)
	var requirements: PackedStringArray = []
	for id in node.get("requires", []): requirements.append(str(catalog.get("labels", {}).get(id, id)))
	var description := str(node.get("description", ""))
	description += "\n\nPrerequisites: " + (", ".join(requirements) if not requirements.is_empty() else "None")
	if int(node.get("requires_count", 0)) > 0: description += " (any %d)" % int(node.requires_count)
	description += "\nXP: %d %s\nCredits: %d\nSkill points: %d" % [int(node.xp_cost), str(node.xp_type).replace("_", " "), int(node.credits), int(node.points)]
	if state(node) != "Learned" and int(node.xp_cost)>0:
		var value := xp_progress(node)
		description += "\nCurrent XP: %d / %d" % [value.current,value.required] if value.known else "\nCurrent XP unavailable"
		description += "\nXP is a shared pool for this experience type; training spends it."
	if not node.get("excludes", []).is_empty():
		var excluded: PackedStringArray = []
		for id in node.excludes: excluded.append(str(catalog.get("labels", {}).get(id, id)))
		description += "\nIncompatible with: " + ", ".join(excluded)
	var modifiers: PackedStringArray = []
	for key: String in node.get("modifiers", {}):
		if key.begins_with("private_"): continue
		var label: String={"healing_dance_mind":"Dance healing / inspiration","healing_music_mind":"Music healing / inspiration","healing_wound_treatment":"Wound Medpack effectiveness","healing_wound_speed":"Wound treatment / enhancement recovery"}.get(key,key.replace("_", " ").capitalize())
		var amount:=float(node.modifiers[key])
		modifiers.append(label + (" %+d" % int(amount) if is_equal_approx(amount,roundf(amount)) else " %+.1f" % amount))
	if not modifiers.is_empty(): description += "\n\n" + "\n".join(modifiers)
	if not node.get("certificates", []).is_empty():
		var certificates: PackedStringArray = []
		for value: String in node.certificates: certificates.append(value.trim_prefix("cert_").replace("_", " "))
		description += "\n\nCertificates: " + ", ".join(certificates)
	if node.id == "combat_marksman_master": description += "\n\nAbility: Lethal Shot"
	if node.id == "combat_brawler_master": description += "\n\nAbility: Melee Assault"
	skill_selected.emit({"skill_id":str(node.id), "name":node.label, "description":description, "state":state(node), "forget":forget_status(str(node.id)), "skill_points":available_skill_points})

func navigate(steps:int)->void:
	if steps==0 or buttons.is_empty():return
	var ids:=buttons.keys()
	var current:=ids.find(selected_skill_id)
	var index:=clampi(0 if current<0 else current+steps,0,ids.size()-1)
	for node:Dictionary in catalog.professions[profession_index].nodes:
		if str(node.id)==str(ids[index]):
			select_skill(node)
			buttons[ids[index]].grab_focus()
			scroll.ensure_control_visible(buttons[ids[index]])
			break
