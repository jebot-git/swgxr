extends SceneTree
class Harness extends "res://scripts/main.gd":
	var loading_frames := 0
	var exposed := false
	var collision_status_seen := false
	func _ready() -> void: pass
	func present_loading_frame() -> void:
		loading_frames += 1
		collision_status_seen = collision_status_seen or loading_screen.message.begins_with("Synchronizing collision")
		exposed = exposed or not loading_screen.active or player.active or player.is_physics_processing()
		await super()
var errors: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var cover := preload("res://scripts/loading_screen.gd").new()
	root.add_child(cover)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.cull_mask = 17
	var original := camera.transform
	cover.attach_head(camera)
	cover.begin("Streaming nearby scenery…")
	check(cover.active and cover.desktop_layer.visible and cover.xr_cover.visible,"Loading covers desktop and tracked-camera view")
	check(camera.cull_mask==cover.XR_LOADING_LAYER,"Loading isolates every world/hand/avatar layer even at close range")
	check(camera.transform==original and camera.get_parent()==world,"Loading never modifies camera tracking transform or hierarchy")
	cover.fail("World asset file is missing.")
	check(cover.failed and cover.xr_status.text.contains("World asset file is missing."),"Failure remains readable in the headset panel")
	cover.finish()
	check(camera.cull_mask==17 and not cover.active and not cover.xr_cover.visible,"Finishing restores the exact prior camera mask")
	var app := Harness.new()
	root.add_child(app)
	app.args = {"desktop":true,"no-world":true,"no-terrain":true}
	app.screenshot_path = "loading-test"
	app.stage_path = ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json")
	app.configure_inputs()
	app.player = app.PlayerScript.new()
	app.add_child(app.player)
	app.player.active = false
	app.player.set_physics_process(false)
	app.make_ui()
	await app.enter_stage(true)
	check(app.world_ready and not app.loading_stage and not app.loading_screen.active,"Actual-stage entry dismisses loading only after completion")
	check(app.ambient_npcs.report.get("ready",false),"Initial NPC publication finishes behind the loading screen")
	check(app.loading_frames>=4 and not app.exposed,"Blocking load phases yield while the screen covers disabled locomotion")
	check(app.collision_status_seen,"Collision synchronization is represented by a real loading status")
	app.args = {"desktop":true,"no-terrain":true,"world-manifest":"res://../runtime/does-not-exist-world.json"}
	await app.enter_stage(true)
	check(not app.world_ready and app.loading_screen.active and app.loading_screen.failed,"Required world failure cannot silently enter a partial scene")
	check(not app.player.active and not app.player.is_physics_processing(),"Failure preserves the locomotion gate")
	check(app.dismiss_loading_error() and app.menu.visible and not app.world_ready,"Failed load can return to the menu without enabling movement")
	var capture := "--capture" in OS.get_cmdline_user_args()
	if capture:
		root.size = Vector2i(1280,800)
		cover.begin("Loading Mos Eisley…\nPreparing nearby scenery and collision")
		# A close bright object must not bleed through the headset loading layer.
		var obstruction := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5,0.5,0.1)
		obstruction.mesh = box
		obstruction.position = Vector3(0,0,-0.5)
		var bright := StandardMaterial3D.new()
		bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bright.albedo_color = Color.MAGENTA
		obstruction.material_override = bright
		world.add_child(obstruction)
		camera.current = true
		for i in range(3): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/loading-desktop.png")
		cover.desktop_layer.hide()
		app.hide()
		app.ui_root.hide()
		for i in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("res://../runtime/evidence/loading-head-view.png")
		var magenta := 0
		for y in range(0,image.get_height(),8):
			for x in range(0,image.get_width(),8):
				var c := image.get_pixel(x,y)
				if c.r>0.5 and c.b>0.5 and c.g<0.2: magenta += 1
		check(magenta==0,"A bright mesh 0.5m in front is absent from the isolated headset loading view")
	var report := {"test":"loading_lifecycle","passed":errors.is_empty(),"checks":checks,"errors":errors,"loading_frames":app.loading_frames,"live_headset_tested":false,"desktop_gpu_capture":capture}
	FileAccess.open("res://../runtime/evidence/loading-screen-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	app.queue_free()
	cover.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if errors.is_empty() else 1)
