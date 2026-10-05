extends SceneTree
## Mocked XR transforms and native pointing; actual SubViewport GUI event dispatch.
const Datapad = preload("res://scripts/xr_datapad.gd")
class BodyFixture extends CharacterBody3D:
	var move_captured := false
	var turn_captured := false
	func set_interface_capture(move: bool, turn: bool) -> void:
		move_captured = move
		turn_captured = turn
class PointerFixture extends Node:
	var enabled := true
var checks := 0
var failures: Array[String] = []
var requests: Array = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func hit_button(pad: Node3D, button: Control) -> Dictionary:
	var pixel: Vector2 = button.get_global_rect().get_center()
	var surface: Dictionary = pad.surfaces[0]
	var local := Vector3((pixel.x/surface.viewport.size.x-0.5)*surface.meters.x,(0.5-pixel.y/surface.viewport.size.y)*surface.meters.y,0)
	return pad.find_hit({"tip":surface.mesh.global_transform*(local+Vector3(0,0,0.15)),"direction":-surface.mesh.global_basis.z})
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var rig := XROrigin3D.new()
	world.add_child(rig)
	rig.transform = Transform3D(Basis(Vector3.UP,0.8),Vector3(2,0,-3))
	var camera := XRCamera3D.new()
	camera.name = "XRCamera3D"
	rig.add_child(camera)
	camera.position = Vector3(0,1.7,0)
	var controllers: Array[XRController3D] = []
	for side in ["LeftHand","RightHand"]:
		var hand := XRController3D.new()
		hand.name = side
		rig.add_child(hand)
		hand.position = Vector3(-0.3 if side=="LeftHand" else 0.3,1.2,-0.4)
		hand.rotation = Vector3(0.1,0.2,0.3)
		var pointer := PointerFixture.new()
		pointer.name = "FunctionPointer"
		hand.add_child(pointer)
		controllers.append(hand)
	var body := BodyFixture.new()
	rig.add_child(body)
	var original_transforms := [rig.transform,camera.transform,controllers[0].transform,controllers[1].transform,body.transform]
	var pad := Datapad.new()
	world.add_child(pad)
	pad.configure(rig,body)
	pad.set_process(false)
	pad.set_allowed(true)
	pad.new_waypoint_requested.connect(func(point,label): requests.append({"point":point,"label":label}))
	pad.ui.set_player_position(Vector3(3528,5,-4800))
	pad.ui.set_entries([])
	check(pad.surfaces.size()==2 and not pad.is_open,"Configured closed wrist and detached details")
	check(pad.ui.category_buttons.has("poi"),"Original POI category available")
	pad.ui.select_category("poi")
	check(pad.ui.filtered_entries.size()==11 and pad.ui.filtered_entries[0].reference_only,"Original Tatooine POIs populated as reference data")
	pad.ui.select_category("pets")
	check(pad.ui.filtered_entries.is_empty(),"No invented pets from reference catalog")
	pad.update_activation(true,0.8,0.8,0.10)
	check(not pad.is_open,"Short squeeze does not open")
	pad.update_activation(true,0.8,0.8,0.16)
	check(pad.is_open and pad.visible,"Sustained offhand grip+trigger opens")
	check(not controllers[0].get_node("FunctionPointer").enabled and not controllers[1].get_node("FunctionPointer").enabled,"Default XR pointers suspended while datapad open")
	var mount: Transform3D = pad.wrist_mount(controllers[0])
	check(mount.basis.y.dot(Vector3.UP)>0.9999,"Datapad mount rises vertically rather than following palm plane")
	var original_hand_rotation := controllers[0].rotation
	controllers[0].rotation.z += 1.3
	var rolled_mount: Transform3D = pad.wrist_mount(controllers[0])
	check(rolled_mount.basis.y.dot(Vector3.UP)>0.9999,"Rolled wrist does not lay the datapad flat")
	controllers[0].rotation = original_hand_rotation
	for frame in range(60):
		var follow: Dictionary = pad.follower.follow(mount,camera.global_position,1.0/60)
		pad.global_transform = follow.transform
	check(pad.global_position.distance_to(mount.origin)<0.00001,"Wrist hinge follows fixed mount anchor")
	check(pad.global_basis.y.dot(Vector3.UP)>=cos(deg_to_rad(25.01)),"View-follow pitch retains upright display")
	var panel_top: Vector3 = pad.surfaces[0].mesh.global_transform*Vector3(0,0.125,0)
	check(panel_top.y-pad.global_position.y>0.22,"Compact display extends above wrist anchor")
	check(absf(pad.surfaces[1].mesh.rotation.y-deg_to_rad(-25))<0.00001,"Details panel tilted inward")
	for frame in range(3): await process_frame
	var hit := hit_button(pad,pad.ui.waypoint_button)
	check(not hit.is_empty() and hit.surface==0,"Native fingertip ray reaches actual waypoint button")
	pad.update_pointer(hit,0.9)
	await process_frame
	check(not pad.pressed and requests.is_empty(),"Trigger already held on opening cannot click")
	pad.update_pointer(hit,0.0)
	pad.update_pointer({},0.2)
	check(not pad.aim_latch.is_empty() and not pad.pressed,"Early analog trigger latches hover before finger curl")
	pad.update_pointer({},0.9)
	await process_frame
	check(pad.pressed and requests.is_empty(),"Fresh trigger press reaches SubViewport without premature activation")
	pad.update_pointer({},0.0)
	await process_frame
	check(not pad.pressed and requests.size()==1,"Captured click releases actual UI even if curled finger moves away")
	if requests.size()==1: check(requests[0].point==Vector3(3528,5,-4800),"UI waypoint uses actual selected player position")
	pad.update_pointer(hit,0.0)
	pad.update_pointer(hit,0.9)
	await process_frame
	pad.update_activation(false,0.8,0.8,0.02)
	await process_frame
	check(not pad.is_open and not pad.pressed and requests.size()==1,"Tracking loss closes and cancels held click")
	check(controllers[0].get_node("FunctionPointer").enabled and controllers[1].get_node("FunctionPointer").enabled,"XR pointers restored after close")
	pad.update_activation(true,0.8,0.8,0.26)
	pad.ui.select_category("poi")
	await process_frame
	var map_hit := hit_button(pad,pad.ui.map_toggle)
	check(not map_hit.is_empty(),"Actual Planet map button is hittable")
	pad.update_pointer(map_hit,0.0)
	pad.update_pointer(map_hit,0.9)
	await process_frame
	pad.update_pointer(map_hit,0.0)
	await process_frame
	check(pad.ui.map_visible and pad.ui.expanded,"SubViewport Planet map click opens expanded map")
	check(pad.surfaces[0].viewport.size==Vector2i(1260,828),"Expanded map uses1260x828viewport")
	check(pad.surfaces[0].meters.is_equal_approx(Vector2(0.70,0.46)),"Expanded physical map size")
	check(absf(pad.surfaces[0].mesh.position.y-0.23)<0.00001 and pad.global_position.distance_to(mount.origin)<0.00001,"Expansion grows above same wrist hinge")
	var touch_surface: Dictionary = pad.surfaces[0]
	var touch: Dictionary = pad.find_hit({"tip":touch_surface.mesh.global_transform*Vector3(0,0,0.005),"direction":Vector3.ZERO})
	check(not touch.is_empty() and touch.touching,"Native direct fingertip contact reaches viewport")
	var pointer_surface: Dictionary = pad.surfaces[1]
	var details_hit: Dictionary = pad.find_hit({"tip":pointer_surface.mesh.global_transform*Vector3(0,0,0.1),"direction":-pointer_surface.mesh.global_basis.z})
	check(not details_hit.is_empty() and details_hit.surface==1,"Tilted detail surface separately addressable")
	pad.update_stick_capture(Vector2(0,0.7),touch,0.016)
	check(body.turn_captured and not body.move_captured,"Pointing right stick captured while interacting")
	pad.update_stick_capture(Vector2(0,0.7),{},0.016)
	check(body.turn_captured,"Capture remains after finger leaves panel")
	if "--capture" in OS.get_cmdline_user_args():
		pad.ui.select_category("poi")
		var observer := Camera3D.new()
		observer.fov = 55
		world.add_child(observer)
		var center: Vector3 = pad.global_transform*Vector3(0.12,0.24,0)
		observer.global_position = center+pad.global_basis.z*0.65
		observer.look_at(center,pad.global_basis.y)
		observer.make_current()
		root.size = Vector2i(1280,800)
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/xr-datapad-expanded.png"))
	pad.resize_map(false)
	check(pad.surfaces[0].viewport.size==Vector2i(900,625),"Compact map restores original viewport")
	pad.ui.select_category("skills")
	await process_frame
	await process_frame
	var selector: OptionButton = pad.ui.professions.selector
	var skill_hit := hit_button(pad,selector)
	pad.update_pointer(skill_hit,0.0)
	pad.update_pointer(skill_hit,0.9)
	await process_frame
	pad.update_pointer(skill_hit,0.0)
	await process_frame
	check(selector.get_popup().visible and selector.get_popup().is_embedded(), "Profession selector opens inside wrist viewport through actual trigger click")
	check(selector.get_popup().size.y <= 320, "All 49 professions use a bounded scrolling selector")
	selector.get_popup().hide()
	var novice: Button
	for button: Button in pad.ui.professions.buttons.values():
		if button.get_global_rect().get_center().y < 530 and button.get_global_rect().get_center().y > 200:
			novice = button
			break
	check(is_instance_valid(novice), "Profession graph has visible selectable boxes in compact wrist view")
	if is_instance_valid(novice):
		pad.ui.detail_description.text = ""
		var box_hit := hit_button(pad,novice)
		pad.update_pointer(box_hit,0.0)
		pad.update_pointer(box_hit,0.9)
		await process_frame
		pad.update_pointer(box_hit,0.0)
		await process_frame
		check(pad.ui.detail_description.text.contains("Prerequisites:"), "Trigger on profession box populates detached details")
	pad.update_activation(true,0.44,0.8,0.02)
	check(not pad.is_open,"Releasing opening grip closes panel")
	pad.update_stick_capture(Vector2(0,0.7),{},0.016)
	check(body.turn_captured,"Closing while stick held retains capture to avoid accidental turning")
	pad.update_stick_capture(Vector2.ZERO,{},0.016)
	check(not body.turn_captured and not body.move_captured,"Neutral stick releases locomotion capture")
	pad.offhand = "right"
	pad.set_open(true)
	pad.update_stick_capture(Vector2(0.6,0),touch,0.016)
	check(body.move_captured and not body.turn_captured,"Reversed offhand captures pointing left stick")
	pad.update_stick_capture(Vector2.ZERO,{},0.016)
	pad.set_allowed(false)
	pad.update_activation(false,1,1,1)
	check(not pad.is_open,"Unavailable gameplay context stays closed")
	var final_transforms := [rig.transform,camera.transform,controllers[0].transform,controllers[1].transform,body.transform]
	for index in original_transforms.size(): check(original_transforms[index].is_equal_approx(final_transforms[index]),"XR/head/controller/body transform unchanged")
	var report := {"test":"xr_datapad_integration","passed":failures.is_empty(),"checks":checks,"failures":failures,"hardware_tested":false,"actual_subviewport_clicks":requests.size()}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/xr-datapad-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
