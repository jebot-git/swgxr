extends SceneTree
## Original skill definitions; synthetic XP. Optional desktop Vulkan capture.
const Trees = preload("res://scripts/profession_trees.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var panel := PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,20)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var title := Label.new()
	title.text = "DATAPAD SKILLS · ORIGINAL DEFINITIONS · MOCK XP · XR DISABLED"
	title.add_theme_font_size_override("font_size",18)
	layout.add_child(title)
	var view := Trees.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(view)
	var index := -1
	for i in view.catalog.get("professions",[]).size():
		if view.catalog.professions[i].id=="combat_marksman": index=i
	check(index>=0,"Original Marksman definitions available")
	if index<0: quit(1); return
	view.show_profession(index)
	view.set_learned(["combat_marksman_novice"],true)
	var rifle: Dictionary=view.xp_controls.combat_marksman_rifle_01.node
	var rifle2: Dictionary=view.xp_controls.combat_marksman_rifle_02.node
	check(view.xp_controls.combat_marksman_rifle_01.label.text=="XP unavailable","Unknown XP does not imply zero")
	view.set_experience({"combat_rangedspecialize_rifle":500,"combat_rangedspecialize_pistol":1500,"combat_general":150},true)
	check(is_equal_approx(view.xp_progress(rifle).ratio,0.5),"Original1000XP cost displays half progress")
	check(view.xp_controls.combat_marksman_rifle_01.label.text=="500 / 1000 XP","Exact pool and requirement shown")
	check(view.state(rifle2)=="Locked" and is_equal_approx(view.xp_progress(rifle2).ratio,0.1),"Prerequisite-locked box still shows its own XP requirement")
	check(view.xp_controls.combat_marksman_pistol_01.bar.value==100.0,"Excess XP fill clamps at100percent")
	check(view.xp_controls.combat_marksman_pistol_01.label.text=="1500 / 1000 XP","Excess XP total remains truthful")
	check(not view.xp_controls.has("combat_marksman_novice"),"Learned boxes omit XP bar")
	check(view.xp_controls.combat_marksman_master.label.text=="No XP required","Zero cost avoids misleading0/0")
	check(view.xp_controls.combat_marksman_rifle_01.bar.mouse_filter==Control.MOUSE_FILTER_IGNORE and view.xp_controls.combat_marksman_rifle_01.label.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Overlay preserves finger/button click routing")
	view.select_skill(rifle2)
	var old_button: Button=view.buttons.combat_marksman_rifle_02
	await process_frame
	view.scroll.scroll_vertical=50
	var old_scroll:=view.scroll.scroll_vertical
	view.set_experience({"combat_rangedspecialize_rifle":250},true)
	check(view.buttons.combat_marksman_rifle_02==old_button and view.selected_skill_id==str(rifle2.id),"Live XP refresh retains controls and selected skill")
	check(view.scroll.scroll_vertical==old_scroll,"Live XP refresh preserves scrolling")
	check(is_equal_approx(view.xp_progress(rifle).ratio,0.25),"Spending shared XP decreases all dependent bars")
	check(view.xp_controls.combat_marksman_pistol_01.bar.value==0,"Absent type in complete native map means zero")
	view.set_experience({"combat_rangedspecialize_rifle":-4},true)
	check(not view.experience_known and view.xp_controls.combat_marksman_rifle_01.label.text=="XP unavailable","Malformed XP cannot create misleading progress")
	view.set_experience({},false)
	view.set_learned([],false)
	check(view.state(rifle)=="Unknown" and not view.experience_known,"Character reset clears skills and XP")
	view.set_learned(["combat_marksman_novice","combat_marksman_rifle_01"],true)
	view.set_experience({"combat_rangedspecialize_rifle":2300,"combat_rangedspecialize_pistol":800,"combat_rangedspecialize_carbine":150,"combat_general":420},true)
	check(not view.xp_controls.has("combat_marksman_rifle_01"),"Native learned update removes completed box bar")
	view.scroll.scroll_vertical=0
	var report: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"xp":"synthetic","definitions":"original source catalog","live_xr_tested":false}
	FileAccess.open("res://../runtime/evidence/profession-xp-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	if "--capture-xp" in OS.get_cmdline_user_args():
		for i in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/profession-xp-vulkan.png"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
