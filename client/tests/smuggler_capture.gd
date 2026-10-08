extends SceneTree
## Mocked UI states, desktop Forward+ Vulkan only; no native mutation or XR claim.
const ServicePanel=preload("res://scripts/service_panel.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1024,800);root.content_scale_size=Vector2i(1024,800)
	var host:=Control.new();root.add_child(host)
	var background:=ColorRect.new();background.color=Color("030b13");background.size=Vector2(1024,800);host.add_child(background)
	var caption:=Label.new();host.add_child(caption);caption.position=Vector2(24,22);caption.text="MOCK DATA · DESKTOP VULKAN FORWARD+ · XR DISABLED";caption.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));caption.add_theme_font_size_override("font_size",20)
	var panel:=ServicePanel.new();host.add_child(panel);panel.position=Vector2(82,105)
	panel.target_id="200"
	panel.configure({"id":"payment:200","kind":"payment","name":"DIRECT PAYMENT","recipient_name":"Varek Solun"},{"cash":12500,"bank":89000,"faction_delegation":true,"faction_points":{"imperial":22000,"rebel":18500},"faction_limits":{"imperial":14000,"rebel":11666},"delegation_ratio":1.5})
	panel.slider.configure(12500,2500);panel.faction_sliders.imperial.configure(14000,3000);panel.faction_sliders.rebel.configure(11666,1500)
	panel.message="Preview balances and proposals · no credits or faction points sent"
	await capture("smuggler-wallet-vulkan.png")
	panel.configure({"id":"broker","kind":"underworld","name":"BARAK · UNDERWORLD BROKER","dialogue":"I have a parcel to move quietly. Pay the front money, collect it from my contact and deliver it within 30 minutes. No shuttle travel. Incapacitation or death loses the job, deposit and 10 Underworld reputation.","confirm_action":"underworld_accept","eligible":true,"front_money":500,"reward_credits":1000,"reward_faction":50,"reputation":250,"duration_seconds":1800},{"cash":12500,"bank":89000})
	panel.message="Preview broker offer · no mission accepted"
	await capture("smuggler-underworld-vulkan.png")
	print(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"mock_data":true,"headset_validated":false,"captures":["smuggler-wallet-vulkan.png","smuggler-underworld-vulkan.png"]}))
	host.free();quit()
func capture(filename:String)->void:
	for frame in range(8):await process_frame
	await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/"+filename))
	if result!=OK:push_error("Capture failed: "+filename);quit(1)
