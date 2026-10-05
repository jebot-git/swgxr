extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1480,950);root.content_scale_size=root.size
	var background:=ColorRect.new();root.add_child(background);background.color=Color("030b13");background.size=root.size
	var caption:=Label.new();root.add_child(caption);caption.position=Vector2(20,12);caption.text="MISSION PARCEL UI · MOCK DIALOGUE · ORIGINAL MODEL · DESKTOP VULKAN · XR DISABLED"
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel);panel.position=Vector2(20,65);panel.scale=Vector2.ONE*.92
	panel.configure({"id":"500","kind":"delivery","name":"MISSION CONTACT","mission_id":"401","dialogue":"Thank you for coming. I need this parcel delivered to my contact. Keep it safe, and present it to the recipient when you arrive.\n\nAre you ready to take the parcel?","confirm_action":"delivery_pickup"},{"cash":400,"bank":800})
	panel.message="Preview only · no mission accepted"
	var datapad:=preload("res://scripts/datapad_ui.gd").new();root.add_child(datapad);datapad.set_anchors_preset(Control.PRESET_TOP_LEFT);datapad.position=Vector2(850,65);datapad.size=Vector2(900,625);datapad.scale=Vector2.ONE*.65
	var detail:=datapad.take_detail_panel();root.add_child(detail);detail.position=Vector2(850,505);detail.size=Vector2(900,625);detail.scale=Vector2.ONE*.65
	datapad.set_mission_parcels([{"id":"301","mission_id":"401","receiver_id":"501","category":"data","type":"mission_parcel","name":"Mission parcel","template":"object/tangible/mission/mission_datadisk.iff","deletable":false,"description":"Original mission item carried by this character."}]);datapad.set_owned_missions([{"id":"401"}]);datapad.select_category("data");datapad.select_entry(0)
	for _frame in range(12):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/mission-parcels-vulkan.png"))
	print(JSON.stringify({"renderer":"Forward+ Vulkan","xr":"off","mock_dialogue":true,"original_parcel_model":true}));quit()
