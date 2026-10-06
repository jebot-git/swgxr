extends SceneTree
const Fixtures=preload("res://tests/crafting_smoke.gd")
class Craft extends "res://scripts/crafting_controller.gd":
	var chosen:Array=[]
	func select_schematic(index:int)->void:chosen.append(index)
	func select_resource(index:int)->void:chosen.append(100+index)
class Pointer extends Node:
	var enabled:=true
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:create_timer(40).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var host:=Fixtures.Host.new();root.add_child(host)
	var rig:=XROrigin3D.new();host.add_child(rig)
	var head:=XRCamera3D.new();head.name="XRCamera3D";rig.add_child(head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;rig.add_child(hand)
		var pointer:=Pointer.new();pointer.name="FunctionPointer";hand.add_child(pointer)
	host.player=Fixtures.Player.new();rig.add_child(host.player)
	var bag:=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);bag.configure(rig,host.player);bag.set_process(false);bag.set_allowed(true)
	var craft:=Craft.new();host.add_child(craft);craft.setup(host,bag);craft.set_process(false);craft.set_visible_ui(true);craft.state={"stage":1}
	craft.ui.configure("Schematics",[{"name":"First"},{"name":"Second"}]);craft.materials.configure("Resources",[{"name":"Ore"}])
	for tool_side:String in ["right","left"]:
		bag.held_side=tool_side;craft.navigation_surface=-1;craft.ui.selected=-1;craft.chosen.clear()
		craft.update_scroll_inputs(Vector2.ZERO,Vector2(0,-1),{},.2)
		craft.update_scroll_inputs(Vector2.ZERO,Vector2(0,-1),{},.2)
		craft.update_scroll_inputs(Vector2.ZERO,Vector2.ZERO,{},.2)
		var free_side:="left" if tool_side=="right" else "right"
		check(craft.ui.selected==1 and craft.chosen.is_empty(),"Free joystick highlights without selecting: "+tool_side)
		check(not craft.confirm_button(tool_side),"Tool hand cannot confirm free-hand selection: "+tool_side)
		check(craft.confirm_button(free_side) and craft.chosen==[1],"Free stick click confirms highlight after neutral without pointer: "+tool_side)
		craft.update_scroll_inputs(Vector2.ZERO,Vector2(0,-1),{"surface":1},.2);craft.confirm_button(free_side)
		check(craft.chosen.back()==100,"Free click routes to highlighted material pane: "+tool_side)
	craft.set_visible_ui(false);check(not craft.confirm_button("left"),"Closed crafting UI cannot consume joystick click")
	var player=load("res://scripts/xr_player.gd").new();var handled:Array=[]
	player.interface_button_handler=func(button,side):handled.append([button,side]);return true
	player.on_ground=true;var before:Vector3=player.velocity
	player._on_controller_button("primary_click","left");check(handled==[["primary_click","left"]] and player.velocity==before,"UI-confirmed stick click cannot also jump");player.free()
	var ui:=preload("res://scripts/xr_services.gd").new();host.add_child(ui);ui.configure(rig,host.player);ui.set_process(false);ui.set_allowed(true)
	var services:=preload("res://scripts/services_controller.gd").new();host.add_child(services);services.set_process(false);services.ui=ui
	var actions:Array=[];ui.action_requested.connect(func(action,payload):actions.append([action,payload]))
	ui.terminal={"id":"12","kind":"bazaar"};ui.panel.configure(ui.terminal,{})
	ui.panel.category_rows=[{"id":1,"name":"First"},{"id":2,"name":"Second"}]
	ui.panel.navigate_at(Vector2(50,150),1);ui.panel.navigate_at(Vector2(50,150),1)
	ui.confirm_button("right")
	check(actions.size()==1 and actions[0][1].category_id==2,"Terminal stick click activates highlighted category")
	ui.confirm_button("right");check(actions.size()==1,"Pending terminal blocks duplicate confirmation")
	ui.set_pending(false);ui.panel.set_pending(false)
	check(services.blocks_combat() and not services.blocks_inventory(),"Bazaar retains combat gate while admitting inventory")
	ui.sync_pointers()
	bag.external_grab_blocker=services.blocks_inventory
	bag.held_side="";bag.held_item={};bag.offhand="left"
	var h:=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
	var shoulder:=Transform3D(Basis.IDENTITY,Vector3(-.19,1.54,.12))
	bag.update_gestures(true,h,shoulder,0,0,{})
	bag.update_gestures(true,h,shoulder,1,0,{})
	check(bag.is_open,"Shoulder grab opens actual backpack while bazaar is open")
	ui.set_inventory_focus(bag.blocks_services())
	check(ui.allowed and not ui.terminal.is_empty() and not ui.pointer_pressed and not ui.pointer_visual.visible,"Backpack owns input while terminal context stays open")
	check(not ui.confirm_button("right"),"Suspended terminal cannot consume inventory input")
	bag.set_open(false);ui.set_inventory_focus(false)
	check(ui.terminal.id=="12","Closing backpack retains bazaar identity")
	bag.set_open(true)
	ui.inventory_focus_provider=func():return bag.blocks_services()
	check(not ui.confirm_button("right") and ui.inventory_focus,"Button dispatch samples new inventory focus before the next process frame")
	ui.close_interface();check(not rig.get_node("LeftHand/FunctionPointer").enabled,"Closing bazaar cannot restore stock beam while backpack owns input")
	bag.set_open(false);ui.set_inventory_focus(false)
	check(rig.get_node("LeftHand/FunctionPointer").enabled,"Last panel restores original pointer state")
	ui.terminal={"id":"12","kind":"bazaar"}
	ui.pointer_visual.update_pointer(Vector3.ZERO,{"world":Vector3(0,0,-1)})
	check(ui.pointer_visual.visible and ui.pointer_visual.dot.visible and not ui.pointer_visual.beam.visible,"Open terminal shows contact dot with no projected beam")
	ui.terminal.kind="bank";check(services.blocks_inventory(),"Wallet/bank hand ownership remains exclusive")
	ui.terminal.kind="vendor";check(not services.blocks_inventory(),"Vendor stock browser also admits backpack")
	ui.wallet_held=true;check(services.blocks_inventory(),"Held wallet still blocks backpack grab")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"headless dummy","tracking":"mocked"}
	FileAccess.open("res://../runtime/evidence/core4-review/ui.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	host.free();await process_frame;quit(0 if failures.is_empty() else 1)
