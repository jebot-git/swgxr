extends SceneTree
const Main = preload("res://scripts/main.gd")
class Harness extends Main:
	func _ready() -> void: pass
var app: Harness
func _initialize() -> void: call_deferred("run")
func run() -> void:
	app = Harness.new()
	root.add_child(app)
	app.args = {"offline":true,"desktop":true,"combat-lab":true,"no-world":true,"no-terrain":true}
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
	var output := ProjectSettings.globalize_path("res://../runtime/evidence/combat-original-dl44.png")
	root.get_texture().get_image().save_png(output)
	var flash: Transform3D = app.combat_rig.muzzle_pose(0)
	flash.basis *= Basis(Vector3.RIGHT,-PI/2)
	var asset: Dictionary = app.combat_rig.assets.catalog.weapons.pistol_dl44
	app.combat_rig.rounds_sim.effects.play(asset.effects.fire,flash)
	await create_timer(0.035).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/combat-original-muzzle-flash.png"))
	app.combat_rig.draw(1)
	app.combat_rig.weapons[1].visual.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY,Vector3(0.18,-0.18,-0.35))
	app.combat_rig.update_visuals()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/combat-original-e11.png"))
	print("COMBAT_RENDER_CAPTURE · desktop only · " + output)
	app.queue_free()
	await create_timer(0.12).timeout
	quit()
