extends SceneTree
class Player extends CharacterBody3D:
	var captured := Vector2.ZERO
	func set_interface_capture(move: bool,turn: bool) -> void: captured=Vector2(float(move),float(turn))
class NativeSession extends Node:
	var live := true
	var session_id := "native-zone-session"
class SourceStage extends Node3D:
	var current_cell: Dictionary={"cell_id":"100:2","building_object_id":"100"}
class Host extends Node3D:
	var datapad_character_id := "fixture"
	var datapad_account := "fixture"
	var datapad_epoch := 1
	var world_ready := true
	var inventory_request_pending := false
	var inventory_snapshot: Dictionary={}
	var player: CharacterBody3D
	var live_combat: Node
	var stage: Node3D
	var calls: Array=[]
	var reply: Dictionary={}
	func source_position_at(value: Vector3) -> Vector3: return value
	func api(method: HTTPClient.Method,path: String,payload: Dictionary={}) -> Dictionary:
		calls.append({"method":method,"path":path,"payload":payload})
		await get_tree().process_frame
		return reply.duplicate(true)
	func reconcile_inventory_presentations() -> void: pass
	func update_inventory_presentation() -> void: pass
	func refresh_inventory() -> void: pass
var checks:=0
var errors: Array[String]=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: errors.append(message);push_error(message)
func _initialize() -> void: call_deferred("run")
func snapshot(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/artisan-"+name+".json"))
func run() -> void:
	var host:=Host.new();root.add_child(host)
	var rig:=XROrigin3D.new();host.add_child(rig)
	var head:=XRCamera3D.new();head.name="XRCamera3D";rig.add_child(head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;rig.add_child(hand)
	host.player=Player.new();rig.add_child(host.player)
	var bag:=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);bag.configure(rig,host.player);bag.set_process(false);bag.set_allowed(true)
	var craft:=preload("res://scripts/crafting_controller.gd").new();host.add_child(craft);craft.setup(host,bag);craft.set_process(false)
	var selected:=snapshot("selected");craft.state=selected.state.duplicate(true);host.datapad_character_id=craft.state.character_id
	craft.held_id=str(craft.state.tool_id)
	for slot in craft.state.schematic.slots: craft.allocations.append([])
	craft.set_visible_ui(true);craft.rebuild()
	check(absf(craft.surfaces[1].mesh.rotation.y)>0.4 and absf(craft.preview_root.rotation.y)>0.4,"Both spaced side panes tilt inward for wrist readability")
	check(absf(craft.surfaces[1].mesh.position.x)>=0.42,"Side panes leave readable gap around center list")
	craft.update_scroll_inputs(Vector2(0,-0.8),Vector2.ZERO,{},0.2)
	check(craft.ui.offset==1 and host.player.captured.y==1,"Main-hand Y scrolls schematics without pointer hover and captures turn input")
	craft.update_scroll_inputs(Vector2.ZERO,Vector2.ZERO,{},0.2)
	check(host.player.captured==Vector2.ZERO,"Neutral main stick releases crafting capture")
	var saved_state:Dictionary=craft.state.duplicate(true)
	host.reply={"ok":true,"state":saved_state.duplicate(true)}
	craft.poll()
	craft.select_schematic(1)
	check(not craft.pending_selection.is_empty(),"Recipe click queues while actual async status poll is in flight")
	for frame in range(6):await process_frame
	check(host.calls.size()==2 and host.calls[1].path=="/crafting/select" and host.calls[1].payload.index==int(saved_state.schematics[1].index),"Completed status drains queued original recipe identity into native select")
	check(craft.preview!=null and craft.pending_selection.is_empty() and not craft.selecting,"Selected recipe response rebuilds preview and releases selection gate")
	host.calls.clear()

	craft.ui.selected=0
	craft.state={"stage":1,"schematics":saved_state.schematics,"prototype_template":"","inventory":[]}
	craft.rebuild()
	check(craft.preview!=null and craft.preview_template()==saved_state.schematics[0].template,"Opening recipes displays first original item even before native recipe selection")
	craft.state=saved_state;craft.rebuild()
	check(craft.surfaces.size()==2 and craft.preview!=null,"Source result preview and two holographic panels load")
	check(craft.surfaces[1].mesh.position.x<0 and craft.preview_root.position.x>0,"Right-handed ingredients are on inner side; preview on outer side")
	check(craft.materials.grid_mode and craft.ingredient_viewport.get_node("Models").get_child_count()==mini(12,craft.state.inventory.size()),"Filtered grid renders original resource models for every visible item")
	check(craft.materials.row_at(craft.materials.cell_rect(5).get_center())==5 and craft.materials.row_at(Vector2(173,100))==-1,"Grid hit testing resolves second row and excludes cell gaps")
	if craft.state.inventory.size()>12:
		craft.materials.scroll(1)
		check(craft.materials.offset==4 and craft.materials.row_at(craft.materials.cell_rect(4).get_center())==4,"Grid scroll keeps model and input indices aligned")
	check(craft.slots.size()==craft.state.schematic.slots.size() and not craft.ready_to_assemble(),"Required ingredient cubes start empty")
	check(not craft.place_resource(-1,0),"Invalid drag cannot allocate")
	var resource:=0
	for i in range(craft.state.inventory.size()):
		if craft.compatible(craft.state.inventory[i],0): resource=i;break
	craft.materials.offset=(resource/4)*4
	craft.refresh_material_page()
	var hit: Dictionary={"surface":1,"pixel":craft.materials.cell_rect(resource).get_center()}
	craft.update_hand(0.8,Transform3D.IDENTITY,hit)
	check(craft.dragging==resource and craft.selected_resource==resource,"Grip picks ingredient from filtered holographic grid")
	craft.update_hand(0.0,Transform3D(Basis.IDENTITY,craft.slots[0].global_position),{})
	check(craft.allocations[0].size()==1,"Grip release over cube fills matching slot")
	for slot: Dictionary in craft.state.schematic.slots:
		for i in range(craft.state.inventory.size()):
			if craft.compatible(craft.state.inventory[i],int(slot.index)) and craft.place_resource(i,int(slot.index)):break
	check(craft.ready_to_assemble(),"All required slots enable assembly")
	var original_qty: int=craft.state.inventory[resource].quantity
	craft.state.inventory[resource].quantity=1
	check(not craft.place_resource(resource,0),"Insufficient quantities cannot fill a slot")
	craft.state.inventory[resource].quantity=original_qty
	craft.select_resource(resource)
	check(craft.slots[0].get_children().any(func(child):return child.has_meta("quality_bar")),"Selected resource quality appears as slot bars")
	craft.state=snapshot("assembled").state.duplicate(true);craft.rebuild()
	check(craft.knobs.size()==craft.state.rows.size() and craft.points.size()==craft.knobs.size(),"Native experimentation rows have matching knobs")
	check(not craft.ingredient_images.visible,"Ingredient model overlay is hidden during experimentation")
	if craft.knobs.size()>1:
		var midpoint: Vector3=(craft.knobs[0].global_position+craft.knobs[1].global_position)/2
		craft.update_hand(0.8,Transform3D(Basis.IDENTITY,midpoint),{})
		check(craft.grabbed_knob==-1,"Gripping between spaced knobs does not accidentally select either")
		craft.update_hand(0,Transform3D.IDENTITY,{})
		craft.update_hand(0.8,Transform3D(Basis.IDENTITY,craft.knobs[1].global_position),{})
		check(craft.grabbed_knob==1,"Direct grip selects the intended adjacent knob")
		craft.update_hand(0,Transform3D.IDENTITY,{})
	craft.update_hand(0.8,Transform3D(Basis.IDENTITY,craft.knobs[0].global_position),{})
	craft.update_hand(0.8,Transform3D(Basis(Vector3.FORWARD,deg_to_rad(30)),craft.knobs[0].global_position),{})
	check(craft.points[0]==1,"Clockwise physical wrist rotation allocates one point")
	craft.update_hand(0.8,Transform3D(Basis.IDENTITY,craft.knobs[0].global_position),{})
	check(craft.points[0]==0,"Reverse physical wrist rotation returns the allocated point")
	craft.update_hand(0,Transform3D.IDENTITY,{})
	craft.set_points(0,100)
	check(craft.points[0]<=craft.state.points and craft.points[0]<=craft.state.rows[0].point_limit,"Knob allocation clamps to row and learned point limits")
	for i in range(craft.points.size()):craft.set_points(i,100)
	var total:=0
	for n in craft.points: total+=int(n)
	check(total<=craft.state.points,"All knobs share the same allowance")
	craft.set_points(0,0);check(craft.points[0]==0,"Counterclockwise allocation can release points")
	host.reply={"ok":true,"state":{"source_kind":"core3_crafting","character_id":host.datapad_character_id,"session_id":"","stage":0,"server_time":0,"jobs":[]}}
	host.live_combat=NativeSession.new();host.add_child(host.live_combat)
	host.stage=SourceStage.new();host.add_child(host.stage)
	craft.held_changed({})
	await process_frame;await process_frame
	check(host.calls.size()==1 and host.calls[0].path=="/crafting/cancel" and not craft.is_open,"Stashing assembled tool requests authoritative refund and closes panes")
	check(host.calls[0].payload.session_id==snapshot("assembled").state.session_id,"Cancellation retains the correct draft identity")
	check(host.calls[0].payload.live_session_id=="native-zone-session","Live zone identity does not overwrite the original crafting session")
	check(host.calls[0].payload.building_id=="100" and host.calls[0].payload.cell_index==2,"Crafting carries the actual original interior cell")
	craft.state={"jobs":[{"tool_id":"test","due":Time.get_unix_time_from_system()+30}]};craft.held_id="test";craft.clock_offset=0;craft.update_timers()
	check(bag.crafting_timers.test>=29 and bag.ui.crafting_timers.has("test"),"Countdown is visible on held tool and bag tile")
	craft.state={};host.free()
	var report: Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"mocked_tracking":true,"gpu_validation":false,"live_core3":false}
	FileAccess.open("res://../runtime/evidence/artisan-crafting-client.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
