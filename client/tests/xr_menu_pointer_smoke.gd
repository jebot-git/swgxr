extends SceneTree
class Harness extends "res://scripts/main.gd":
	func _ready() -> void: pass
class CalibrationProbe extends Node3D:
	var calls := 0
	func calibrate_standing_height() -> Dictionary:
		calls += 1
		return {"valid":true,"standing_eye_height":1.83}
var app: Harness
var pointer: Node3D
var errors: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func click(control: Control) -> void:
	var screen: XRToolsViewport2DIn3D = app.xr_menu.screen
	var point := control.get_global_rect().get_center()
	check(Rect2(Vector2.ZERO,screen.viewport_size).encloses(control.get_global_rect()),control.name+" escapes menu viewport")
	var surface: Node3D = screen.get_node("StaticBody3D")
	var world_point := surface.to_global(Vector3((point.x/screen.viewport_size.x-0.5)*screen.screen_size.x,(0.5-point.y/screen.viewport_size.y)*screen.screen_size.y,0))
	XRToolsPointerEvent.entered(pointer,surface,world_point)
	XRToolsPointerEvent.moved(pointer,surface,world_point,world_point)
	await process_frame
	XRToolsPointerEvent.pressed(pointer,surface,world_point)
	await process_frame
	XRToolsPointerEvent.released(pointer,surface,world_point)
	await process_frame
	XRToolsPointerEvent.exited(pointer,surface,world_point)
func run() -> void:
	app = Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.xr_requested = true
	app.xr_initialized = true
	app.xr_focused = true
	app.vr_settings.path = "res://../runtime/evidence/menu-test-preferences.cfg"
	app.xr_origin = load("res://xr/player_rig.tscn").instantiate()
	app.add_child(app.xr_origin)
	app.player = app.xr_origin.get_node("PlayerBody")
	app.player.set_physics_process(false)
	app.make_ui()
	app.xr_menu = app.XRMenu.new()
	app.add_child(app.xr_menu)
	app.xr_menu.configure(app.ui_root,app.player.get_camera())
	app.xr_menu.set_open(true)
	pointer = Node3D.new()
	app.add_child(pointer)
	var calibration := CalibrationProbe.new()
	app.add_child(calibration)
	app.tracked_avatar = calibration
	app.world_ready = true
	for frame in range(5): await process_frame
	var smooth: Button = app.ui_root.find_child("SmoothTurn",true,false)
	var snap: Button = app.ui_root.find_child("SnapTurn",true,false)
	var calibrate: Button = app.ui_root.find_child("CalibrateHeight",true,false)
	check(smooth != null and snap != null and calibrate != null,"Required settings controls missing")
	await click(smooth)
	check(app.vr_settings.turn_mode == "smooth" and smooth.button_pressed,"3D pointer did not activate smooth turn")
	await click(snap)
	check(app.vr_settings.turn_mode == "snap" and snap.button_pressed,"3D pointer did not activate snap turn")
	await click(calibrate)
	check(calibration.calls == 1 and absf(app.vr_settings.standing_eye_height-1.83)<0.001,"3D pointer did not calibrate standing height")
	var menu: PanelContainer = app.menu
	check(menu.get_global_rect().end.y<=900.0,"Complete menu exceeds 900px surface height")
	var report := {"test":"main_menu_xrtools_pointer","passed":errors.is_empty(),"hardware_tested":false,"errors":errors,"surface_size":str(app.xr_menu.screen.viewport_size),"menu_rect":str(menu.get_global_rect()),"calibration_calls":calibration.calls}
	FileAccess.open("res://../runtime/evidence/xr-menu-pointer-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	app.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
