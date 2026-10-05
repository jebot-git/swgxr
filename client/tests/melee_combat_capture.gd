extends SceneTree
const Main = preload("res://scripts/main.gd")
class Harness extends Main:
	func _ready() -> void: pass
var app: Harness
func _initialize() -> void: call_deferred("run")
func run() -> void:
	app = Harness.new()
	root.add_child(app)
	app.args = {"offline":true,"desktop":true,"combat-lab":true,"combat-sidearm":"knife_survival","combat-longarm":"2h_sword_maul","no-world":true,"no-terrain":true}
	app.screenshot_path = "capture-harness" # Disable live mouse input/capture during evidence.
	app.stage_path = ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json")
	app.configure_inputs()
	app.make_environment()
	app.player = app.PlayerScript.new()
	app.add_child(app.player)
	app.make_ui()
	await app.enter_stage(true)
	for i in range(50): await physics_frame
	app.player.testing = true
	app.player.active = false
	app.combat_rig.set_physics_process(false)
	app.combat_rig.set_allowed(true)
	app.combat_rig.draw(0)
	var camera: Camera3D = app.player.get_camera()
	var pose := camera.global_transform * Transform3D(Basis.IDENTITY,Vector3(0.16,-0.18,-0.32))
	app.combat_rig.weapons[0].visual.global_transform = pose
	app.combat_rig.update_visuals()
	app.hud.visible = false
	# Source geometry, original reticle art and original effect textures in actual stage.
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../runtime/evidence/combat-original-melee-knife.png")
	root.get_texture().get_image().save_png(output)
	app.combat_rig.draw(1)
	app.combat_rig.weapons[1].visual.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY,Vector3(0.18,-0.18,-0.35))
	app.combat_rig.update_visuals()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/combat-original-melee-maul.png"))
	# Exercise the melee head-ray against actual source-stage collision as well.
	camera.look_at(app.combat_target.global_position)
	var state=app.combat_rig.weapons[0].state
	state.sample_swing(0.01,true,false,"standing",Vector3.ZERO)
	state.sample_swing(0.01,true,false,"standing",Vector3.ZERO)
	var strike:Dictionary={}
	for i in range(1,25):
		var sample:Dictionary=state.sample_swing(0.01,true,false,"standing",Vector3(i*0.02,0,0))
		if not sample.is_empty(): strike=sample
	assert(not strike.is_empty())
	var result:Dictionary=app.combat_rig.rounds_sim.strike_melee(strike,camera.global_transform,pose)
	assert(result.get("collider")==app.combat_target and app.combat_target.hit_count==1)
	var report:Dictionary={"passed":true,"test":"melee_actual_stage_vulkan","original_models":["knife_survival","2h_sword_maul"],"head_ray_hit":true,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/melee-render.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MELEE_RENDER_CAPTURE · desktop only · " + output)
	app.queue_free()
	await create_timer(0.12).timeout
	quit()
