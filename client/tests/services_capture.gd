extends SceneTree
## Desktop Vulkan visual inspection with explicitly mocked service data, XR disabled.
const ServicePanel=preload("res://scripts/service_panel.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,1000)
	root.content_scale_size=Vector2i(1280,1000)
	var host:=Control.new();root.add_child(host)
	var background:=ColorRect.new();background.color=Color("030b13");background.size=Vector2(1280,1000);host.add_child(background)
	var label:=Label.new();host.add_child(label);label.text="SERVICE UI • MOCK DATA • DESKTOP VULKAN • XR DISABLED";label.position=Vector2(20,12);label.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));label.add_theme_font_size_override("font_size",20)
	var data: Array=[
		{"id":"bank","kind":"bank","name":"GALACTIC BANK"},
		{"id":"bazaar","kind":"bazaar","name":"GALACTIC BAZAAR","listings":[{"id":"1","name":"FWG5 pistol","price":3200,"description":"Certified pistol\nCondition: 1000 / 1000\nLocation: Mos Eisley","buy_eligible":true},{"id":"2","name":"E-11 blaster rifle","price":480,"buy_eligible":true},{"id":"3","name":"Vibroblade","price":750,"buy_eligible":true}]},
		{"id":"travel","kind":"boarding","name":"SELECT SHUTTLE TICKET"},
		{"id":"payment","kind":"payment","name":"DIRECT PAYMENT","recipient_name":"Varek Solun"}]
	data[1].categories=preload("res://tests/bazaar_tree_smoke.gd").source_categories()
	for index in range(4):
		var panel:=ServicePanel.new();host.add_child(panel);panel.position=Vector2(20+(index%2)*630,54+(index/2)*465);panel.scale=Vector2.ONE*0.71
		panel.configure(data[index],{"cash":12500,"bank":89000},[{"id":"31","arrival":"Mos Espa","planet":"tatooine","usable":true},{"id":"32","arrival":"Bestine","planet":"tatooine","usable":true}])
		if index==1:
			for category_index in range(panel.category_rows.size()):
				if int(panel.category_rows[category_index].id)==131072:
					panel.select_category(category_index);break
			data[1].category_id=131072
			panel.configure(data[1],{"cash":12500,"bank":89000})
		panel.selected=0;panel.message="Preview data — no native mutation performed"
		if index in [0,3]: panel.slider.configure(12500,2500)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/services-ui-vulkan.png"))
	host.free()
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();world.add_child(env);env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("07101a")
	var rig:=XROrigin3D.new();world.add_child(rig)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";rig.add_child(camera);camera.position=Vector3(0,0.1,0.7);camera.current=true
	var body:=CharacterBody3D.new();world.add_child(body)
	var services:=preload("res://scripts/xr_services.gd").new();world.add_child(services);services.configure(rig,body);services.set_process(false);services.set_allowed(true)
	services.set_wallet({"cash":12500,"bank":89000});services.set_wallet_held(true)
	services.wallet_mount.rotation=Vector3(-0.8,0,0.2)
	var caption:=Label.new();root.add_child(caption);caption.text="ORIGINAL CREDIT CHIP · MOCK BALANCES · DESKTOP VULKAN · XR DISABLED";caption.position=Vector2(20,20)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/services-wallet-vulkan.png"))
	print("Desktop Vulkan services UI and original wallet model captured; mock balances; XR disabled.")
	world.free();caption.free()
	var mission_host:=Control.new();root.add_child(mission_host)
	var mission_background:=ColorRect.new();mission_host.add_child(mission_background);mission_background.color=Color("030b13");mission_background.size=Vector2(1280,1000)
	var mission_caption:=Label.new();mission_host.add_child(mission_caption);mission_caption.text="MISSION AVAILABILITY · MOCK SOURCE ROWS · DESKTOP VULKAN · XR DISABLED";mission_caption.position=Vector2(20,20)
	for index in range(2):
		var mission_panel:=ServicePanel.new();mission_host.add_child(mission_panel);mission_panel.position=Vector2(20+630*index,80);mission_panel.scale=Vector2.ONE*0.71
		var offer: Dictionary={"id":"mission-fixture","name":"Destroy a worrt lair" if index==0 else "Deliver a parcel","description":"Preview of an original mission offer.","target":"worrt lair" if index==0 else "delivery recipient","difficulty":5,"reward":450,"position":[3810,0,-4780],"planet":"tatooine","supported":index==0,"blocked_reason":"This original mission needs an interaction not yet available in the VR prototype.","active":false}
		mission_panel.configure({"id":"mission-terminal","kind":"mission","name":"MISSION TERMINAL","missions":[offer]}, {"cash":12500,"bank":89000})
		mission_panel.selected=0;mission_panel.message="Mock source row — no mission accepted"
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/services-missions-vulkan.png"))
	mission_host.free();quit()
