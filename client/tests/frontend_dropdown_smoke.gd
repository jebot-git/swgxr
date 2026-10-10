extends SceneTree
const Choice=preload("res://scripts/frontend_choice.gd")
const Creator=preload("res://scripts/creation_panel.gd")
const Menu=preload("res://scripts/xr_menu.gd")
class Ray extends XRToolsFunctionPointer:
	func _enter_tree() -> void:pass
	func _exit_tree() -> void:pass
	func _ready() -> void:pass
	func _physics_process(_delta: float) -> void:pass
var failures: Array[String]=[]
var checks:=0
var menu: Node3D
var space: Node3D
var pointer: Node3D
var body: StaticBody3D
var last:=Vector2.ZERO
func ray() -> Node3D:
	var result=load("res://addons/godot-xr-tools/functions/function_pointer.tscn").instantiate()
	result.set_script(Ray)
	return result
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func location(pixel: Vector2) -> Vector3:
	return body.to_global(Vector3((pixel.x/menu.screen.viewport_size.x-.5)*menu.screen.screen_size.x,(.5-pixel.y/menu.screen.viewport_size.y)*menu.screen.screen_size.y,0))
func move(pixel: Vector2) -> void:
	XRToolsPointerEvent.moved(pointer,body,location(pixel),location(last));last=pixel
	await process_frame
func down() -> void:
	XRToolsPointerEvent.pressed(pointer,body,location(last));await process_frame
func up() -> void:
	XRToolsPointerEvent.released(pointer,body,location(last));await process_frame
func click_at(pixel: Vector2) -> void:
	await move(pixel);await down();await up()
func click(control: Control) -> void:await click_at(control.get_global_rect().get_center())
func settle() -> void:
	for _frame in range(4):await process_frame
func run() -> void:
	root.size=Vector2i(1440,900)
	space=Node3D.new();root.add_child(space)
	var camera:=XRCamera3D.new();space.add_child(camera)
	var host:=Control.new();space.add_child(host)
	var background:=ColorRect.new();background.color=Color("030b13");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.add_child(background)
	var creator:=Creator.new();host.add_child(creator)
	creator.set_options({"professions":[{"id":"combat_marksman","label":"Marksman"},{"id":"combat_brawler","label":"Brawler"},{"id":"crafting_artisan","label":"Artisan"},{"id":"outdoors_scout","label":"Scout"},{"id":"social_entertainer","label":"Entertainer"},{"id":"science_medic","label":"Medic"}]})
	creator.select_race_id("human_male")
	creator.name_input.text="Dropdown fixture"
	menu=Menu.new();space.add_child(menu);menu.configure(host,camera)
	pointer=ray();space.add_child(pointer);pointer.set_process(false);pointer.set_physics_process(false)
	body=menu.screen.get_node("StaticBody3D")
	await settle()
	XRToolsPointerEvent.entered(pointer,body,location(Vector2(40,40)))
	for pair in [[0,creator.species_pick],[0,creator.sex_pick],[1,creator.hair_pick],[2,creator.profession_pick]]:
		creator.tabs.current_tab=pair[0];await settle()
		var choice=pair[1]
		await click(choice)
		check(choice.is_open(),"Actual XRTools touch+mouse opens creator selector on stage %d"%pair[0])
		check(Rect2(Vector2.ZERO,Vector2(1440,900)).encloses(choice.popup.get_global_rect()),"Dropdown stays inside XR canvas")
		check(choice.popup.size.y<=320,"Dropdown list has bounded height")
		choice.close_popup()
	await click(creator.profession_pick)
	var row: Button=creator.profession_pick.rows.get_child(1)
	await click(row)
	check(not creator.profession_pick.is_open() and creator.payload().profession=="combat_brawler","Pointer selection preserves actual native profession metadata/payload")
	creator.hide()
	var flight:=preload("res://space/settings_panel.gd").new();host.add_child(flight);flight.position=Vector2(100,100);flight.size=Vector2(700,500)
	var prefs:=preload("res://space/preferences.gd").new();prefs.path="res://../runtime/evidence/livec-20261010/flight-test.cfg"
	flight.setup(prefs);await settle()
	var modes=flight.get_child(1);await click(modes);await settle();await click(modes.rows.get_child(2));await settle()
	check(prefs.mode=="physical_hotas" and flight.get_child(2).visible,"Flight dropdown selects physical HOTAS through actual XRTools events")
	var devices=flight.get_child(2).get_child(0);await click(devices);await settle();await click(devices.rows.get_child(0))
	check(prefs.device==-1,"Default joystick selection retains sentinel instead of binding device zero")
	flight.queue_free();await settle()
	var inventory:=preload("res://scripts/inventory_ui.gd").new();host.add_child(inventory)
	var snapshot:Dictionary={"inventory":{"id":"1"},"containers":[{"id":"1","capacity":80,"occupied":0}],"items":[],"equipment":[]}
	inventory.set_snapshot(snapshot);await settle()
	await click(inventory.container_switch);await settle()
	inventory.set_snapshot(snapshot);await settle()
	check(inventory.container_switch.is_open(),"Unchanged inventory polling preserves open dropdown")
	await click(inventory.container_switch.rows.get_child(1));await settle()
	check(inventory.container_id=="@equipment" and not inventory.container_switch.is_open(),"Inventory container dropdown selects equipped items through XRTools events")
	inventory.queue_free();await settle();creator.show()
	var pick:=Choice.new();host.add_child(pick);pick.position=Vector2(1080,810);pick.size=Vector2(280,44)
	for index in range(50):pick.add_item("Long choice %02d"%index,index+100);pick.set_item_metadata(index,"native_%d"%index)
	var selections: Array=[];pick.item_selected.connect(func(index):selections.append(index))
	await click(pick)
	check(pick.is_open() and pick.popup.get_global_rect().end.y<=888,"Lower-edge selector opens upward with margins")
	var before:=pick.scroll.scroll_vertical
	menu.scroll_pointer(last,1,.25);await settle()
	check(pick.scroll.scroll_vertical>before,"Controller route scrolls active dropdown")
	var still:=pick.scroll.scroll_vertical;menu.scroll_pointer(last,.2,1)
	check(pick.scroll.scroll_vertical==still,"Controller deadzone avoids drift")
	menu.scroll_pointer(last,1,.0005);menu.scroll_pointer(last,1,.0005);menu.scroll_pointer(last,1,.001)
	check(pick.scroll.scroll_vertical>still,"Fractional controller scroll accumulates across high-rate frames")
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true
	wheel.position=pick.popup.get_global_rect().get_center();wheel.global_position=wheel.position
	await move(wheel.position)
	menu.screen.get_node("Viewport").push_input(wheel,true);await settle()
	check(pick.scroll.scroll_vertical>still,"Mouse wheel scrolls same bounded canvas list")
	var press_point:=pick.popup.get_global_rect().position+Vector2(45,180)
	await move(press_point);await down();await move(press_point-Vector2(0,80));await move(press_point-Vector2(0,360));await up()
	check(pick.scroll.scroll_vertical>still and selections.is_empty() and pick.is_open(),"Dragging continues outside list without selecting item")
	await click_at(Vector2(20,20))
	check(not pick.is_open() and selections.is_empty(),"Outside click dismisses without selecting/clicking through")
	pick.disabled=true;await click(pick);check(not pick.is_open(),"Disabled selector never opens")
	pick.disabled=false;pick.clear();await click(pick);check(not pick.is_open() and pick.selected==-1,"Empty selector never opens")
	pick.add_item("Enabled",31);pick.add_item("Disabled",32);pick.set_item_disabled(1,true)
	pick.set_item_metadata(0,{"id":"source"});pick.select(0)
	check(pick.get_selected_id()==31 and pick.get_selected_metadata()=={"id":"source"} and selections.is_empty(),"Programmatic selection preserves metadata and does not emit")
	await click(pick);await click(pick.rows.get_child(1));check(pick.is_open() and selections.is_empty(),"Disabled item cannot be selected")
	var first_pointer:=pointer
	pointer=ray();space.add_child(pointer);pointer.set_process(false);pointer.set_physics_process(false)
	XRToolsPointerEvent.entered(pointer,body,location(last))
	await click(pick.rows.get_child(0))
	check(not pick.is_open() and selections==[0],"Second XRTools ray selects once while first ray remains on surface")
	XRToolsPointerEvent.exited(pointer,body,location(last));pointer.queue_free();pointer=first_pointer
	await click(pick)
	var lost_hand:=XRController3D.new();space.add_child(lost_hand)
	pointer.reparent(lost_hand)
	menu._process(.01)
	check(not pick.is_open(),"Loss of hovered controller tracking cancels dropdown and input gesture")
	pointer.reparent(space);lost_hand.queue_free()
	XRToolsPointerEvent.entered(pointer,body,location(last));await click(pick)
	menu.set_input_active(false)
	check(not pick.is_open() and not menu.screen.enabled and not menu.keyboard.enabled,"Focus loss closes list and disables XR input")
	check(not menu.scroll_pointer(last,1,1),"Inactive menu does not scroll")
	menu.set_input_active(true);await move(pick.get_global_rect().get_center());await down()
	menu.set_input_active(false)
	check(not pick.is_open(),"Focus loss while trigger held cannot activate a control on synthetic release")
	menu.set_input_active(true);await click(pick)
	check(pick.is_open(),"Focus restoration permits explicit reopening")
	pick.hide();await settle();check(not pick.is_open(),"Hidden owning page/control dismisses canvas list")
	pick.queue_free();await settle()
	creator.tabs.current_tab=1;await settle()
	var page: ScrollContainer=creator.tabs.get_child(1)
	page.scroll_vertical=0
	var point:=page.get_global_rect().position+Vector2(15,250)
	await move(point)
	menu.scroll_pointer(point,1,.3);await settle()
	check(page.scroll_vertical>0,"Controller scroll reaches long appearance page when no list is open")
	page.scroll_vertical=0;await settle();await move(point);await down();await move(point-Vector2(0,100));await up()
	check(page.scroll_vertical>0,"Pointer drag scrolls page whitespace without choosing controls")
	page.scroll_vertical=0;await settle()
	var slider_point:=creator.height_slider.get_global_rect().get_center()
	await move(slider_point);await down();await move(slider_point+Vector2(30,-20));await up()
	check(page.scroll_vertical==0 and not page.held,"Dragging a height slider does not drag the appearance page")
	await move(slider_point)
	check(not menu.scroll_pointer(slider_point,1,.2) and page.scroll_vertical==0,"Stick does not move page behind a hovered slider")
	await click(creator.hair_pick);creator.tabs.current_tab=2;await settle()
	check(not creator.hair_pick.is_open(),"Changing creation stage closes detached dropdown overlay")
	var identity_page: ScrollContainer=creator.tabs.get_child(2)
	await move(creator.biography.get_global_rect().get_center());await down()
	check(not identity_page.held,"Text editing does not start page drag")
	await up()
	await click(creator.profession_pick)
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
	menu.screen.get_node("Viewport").push_input(escape,true)
	check(not creator.profession_pick.is_open(),"Escape dismisses dropdown before closing menu")
	await click(creator.profession_pick);menu.set_open(false)
	check(not creator.profession_pick.is_open(),"Closing menu dismisses all frontend dropdowns")
	menu.set_open(true);creator.tabs.current_tab=0;await settle()
	# Same content must remain bounded on the narrower desktop inspection canvas.
	menu.screen.viewport_size=Vector2(1280,900);await settle()
	await click(creator.species_pick)
	check(Rect2(Vector2.ZERO,Vector2(1280,900)).encloses(creator.species_pick.popup.get_global_rect()),"Dropdown remains bounded at 1280x900")
	creator.species_pick.close_popup();menu.screen.viewport_size=Vector2(1440,900);await settle()
	await click(creator.species_pick);menu.scroll_pointer(last,1,.2);await settle()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			if DisplayServer.get_name()=="headless":check(false,"Capture requires actual Forward+ Vulkan renderer")
			else:
				await RenderingServer.frame_post_draw
				menu.screen.get_node("Viewport").get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"server_requests":0,"xr":"off; actual XRTools event dispatch with mocked rays"}))
	space.queue_free();await settle();quit(0 if failures.is_empty() else 1)
