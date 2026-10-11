extends SceneTree
const Menu = preload("res://scripts/xr_menu.gd")
var failures: Array[String] = []
var pressed := false
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var head := XRCamera3D.new()
	world.add_child(head)
	head.position.y = 1.7
	var ui := Control.new()
	world.add_child(ui)
	var button := Button.new()
	button.position = Vector2(100,100)
	button.size = Vector2(200,80)
	button.text = "XR pointer test"
	button.pressed.connect(func(): pressed = true)
	ui.add_child(button)
	var field := LineEdit.new()
	field.position = Vector2(100,220)
	field.size = Vector2(400,70)
	ui.add_child(field)
	var menu := Menu.new()
	world.add_child(menu)
	menu.configure(ui,head)
	await process_frame
	await process_frame
	check(ui.get_viewport() == menu.screen.get_node("Viewport"), "UI not embedded in XR Tools viewport")
	check(menu.screen.collision_layer & 3 == 0, "Menu creates a world collision wall")
	var pointer := Node3D.new()
	world.add_child(pointer)
	var body: StaticBody3D = menu.screen.get_node("StaticBody3D")
	# Genuine XR Tools pointer events exercise 3D->viewport conversion and UI dispatch.
	var local := Vector3((200.0/1440.0-0.5)*2.88,(0.5-140.0/900.0)*1.8,-0.01)
	var hit := menu.screen.to_global(local)
	XRToolsPointerEvent.entered(pointer,body,hit)
	XRToolsPointerEvent.moved(pointer,body,hit,hit)
	await process_frame
	XRToolsPointerEvent.pressed(pointer,body,hit)
	await process_frame
	XRToolsPointerEvent.released(pointer,body,hit)
	await process_frame
	check(pressed, "XR pointer failed to press existing UI button")
	field.grab_focus()
	await process_frame
	check(menu.keyboard.visible and menu.keyboard.enabled, "Keyboard not shown for text focus")
	menu.keyboard_content.press_key("a","A")
	await process_frame
	check(field.text == "a", "Virtual keyboard did not reach menu field")
	menu.set_open(false)
	await process_frame
	check(not menu.visible and not menu.screen.enabled and not menu.keyboard.enabled, "Closed menu retained pointer colliders")
	menu.set_open(true)
	check(menu.screen.enabled, "Reopened menu has no pointer collider")
	var frame:=Node3D.new();world.add_child(frame)
	head.reparent(frame)
	menu.set_reference_frame(frame);menu.set_open(true)
	var relative:Transform3D=head.global_transform.affine_inverse()*menu.global_transform
	frame.position+=Vector3(20,10000,-40);frame.rotation=Vector3(.4,1.2,.3)
	menu.follow_reference_frame()
	var after:Transform3D=head.global_transform.affine_inverse()*menu.global_transform
	check(after.origin.distance_to(relative.origin)<.003 and after.basis.is_equal_approx(relative.basis),"JTL menu follows ship reference changes without leaving FOV")
	var before:Transform3D=menu.global_transform
	head.rotation.y+=.4;menu.follow_reference_frame()
	check(menu.global_transform.is_equal_approx(before),"JTL menu remains stable while player looks around")
	menu.set_reference_frame(null);before=menu.global_transform;frame.position.x+=10;menu.follow_reference_frame()
	check(menu.global_transform.is_equal_approx(before),"Leaving JTL restores world-anchored menu")
	var report := {"test":"xr_tools_menu_pointer_keyboard","success":failures.is_empty(),"errors":failures,"xr_runtime_initialized":false}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/xr-menu-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("XR_MENU_PASS " + JSON.stringify(report) if failures.is_empty() else "XR_MENU_FAIL " + JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
