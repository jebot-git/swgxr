extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1060,760);root.content_scale_size=root.size
	var background:=ColorRect.new();root.add_child(background);background.color=Color("07141e");background.size=Vector2(root.size)
	var title:=Label.new();root.add_child(title);title.position=Vector2(30,20);title.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));title.add_theme_font_size_override("font_size",19);title.text="GCW RECRUITER · DESKTOP VULKAN INSPECTION\nOriginal reward art · mocked native state · no live headset"
	var panel:=preload("res://gcw/panel.gd").new();root.add_child(panel);panel.position=Vector2(100,110)
	var reward:Dictionary={"id":"imperial:armor:stormtrooper_bicep_l","name":"Stormtrooper bicep armor","description":"Original Imperial armor. Inspect the item before confirming its native faction-point cost.","template":"object/tangible/wearables/armor/stormtrooper/armor_stormtrooper_bicep_l.iff","cost_faction_points":1000,"eligible":true}
	var record:Dictionary={"id":"42","kind":"recruiter","name":"Imperial recruiter","faction":"imperial","status":1,"rank":1,"rank_name":"Lance corporal","next_rank_name":"Corporal","promotion_cost_faction_points":400,"can_promote":false,"promotion_reason":"Additional faction standing required.","gcw":{"status_name":"combatant"},"can_join":false,"reason":"Already enlisted","recruiter_text":"Serve the Empire and earn faction rewards.","rewards":[reward]}
	var preview_path:="res://../runtime/evidence/gcw-native-preview.json"
	if FileAccess.file_exists(preview_path):
		var native:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(preview_path));record=native.terminal;title.text="GCW RECRUITER · DESKTOP VULKAN INSPECTION\nRecorded native recruiter and original reward art · no live headset"
	panel.configure(record,{"cash":1000,"bank":2000});panel.selected=2 if record.has("rank") else 1;panel.refresh_details();panel.queue_redraw()
	for i in range(12):await process_frame
	await RenderingServer.frame_post_draw
	var passed:=panel.preview_ready and root.get_texture().get_image().save_png("res://../runtime/evidence/gcw-vulkan.png")==OK
	var report:Dictionary={"passed":passed,"renderer":RenderingServer.get_current_rendering_method(),"original_reward":true,"native_api":"recorded" if FileAccess.file_exists(preview_path) else "mocked","live_xr":false};FileAccess.open("res://../runtime/evidence/gcw-vulkan.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));panel.free();await process_frame;quit(0 if passed else 1)
