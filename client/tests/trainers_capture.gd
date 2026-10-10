extends SceneTree
## Source trainer text/skills; mocked player eligibility. Desktop Vulkan, never live XR.
const ServicePanel=preload("res://scripts/service_panel.gd")
const TrainerFixture=preload("res://tests/trainer_services_smoke.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,950);root.content_scale_size=Vector2i(1280,950)
	var host:=Control.new();root.add_child(host)
	var background:=ColorRect.new();host.add_child(background);background.color=Color("030b13");background.size=Vector2(1280,950)
	var caption:=Label.new();host.add_child(caption);caption.text="ORIGINAL TRAINER TEXT / SKILLS · MOCK PLAYER ELIGIBILITY · DESKTOP VULKAN · XR DISABLED";caption.position=Vector2(20,16)
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/services/trainers.json"))
	var professions: Array=["combat_marksman","combat_marksman","science_medic","crafting_artisan"]
	for index in range(4):
		var panel:=ServicePanel.new();host.add_child(panel);panel.position=Vector2(20+(index%2)*630,54+(index/2)*440);panel.scale=Vector2.ONE*0.71
		var record: Dictionary=TrainerFixture.source_trainer(professions[index])
		for metadata: Dictionary in source.trainers.values():
			if metadata.profession==professions[index]: record.trainer_text=metadata.greeting;break
		var selected_id:=""
		if index==1:
			selected_id="combat_marksman_pistol_01"
			for skill: Dictionary in record.skills:
				if skill.id==selected_id: skill.eligible=true;skill.xp_available=skill.xp_cost+150;skill.xp_name="Pistol"
		elif index==2: selected_id="science_medic_injury_01"
		elif index==3:
			selected_id="crafting_artisan_novice"
			for skill: Dictionary in record.skills:
				if skill.id==selected_id: skill.learned=true;skill.eligible=false
		panel.configure(record,{"cash":12000,"bank":80000})
		for row_index in range(panel.rows.size()):
			if panel.rows[row_index].id==selected_id: panel.selected=row_index;panel.offset=maxi(0,row_index-4);break
		panel.message="Preview — training and credit deductions require CoreCU confirmation"
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/trainers-ui-vulkan.png"))
	print("Original trainer UI captured with mocked player eligibility; Forward+ Vulkan, XR disabled.")
	host.free();quit()
