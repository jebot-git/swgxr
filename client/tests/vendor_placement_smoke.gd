extends SceneTree
class DragUI extends Control:
	func draggable_entry_at(_point:Vector2)->Dictionary:return {"id":"301","type":"vendor"}
class Session extends Node:
	var live:=true
	var session_id:="owned"
class Datapad extends Node3D:
	signal vendor_draw_requested(entry:Dictionary,pose:Transform3D)
	var ui:Control
	var is_open:=true
	func set_open(value:bool)->void:is_open=value
class Inventory extends Node:
	var held_item:Dictionary={}
class Rig extends Node:
	var stowed:=0
	func stow()->void:stowed+=1
class Services extends Node:
	var app:Node
	var busy:=false
	var allowed:=true
	var state_age:=0.0
	var poll_clock:=0.0
	var state:Dictionary={"vendor_placement":{"eligible":true,"building_id":"456","cell_index":2,"max_distance":4}}
	var calls:Array=[]
	var fail:=false
	func identity_payload()->Dictionary:return {"building_id":"456","cell_index":2}
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],-p[2])
	func source(p:Vector3)->Array:return [p.x,p.y,-p.z]
	func request(action:String,payload:Dictionary)->Dictionary:
		calls.append({"action":action,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		if fail:return {"ok":false,"error":"Unconfirmed native response"}
		var result:Dictionary=app.receipt([],app.vendor_placement.native_sequence+1)
		result.mutation={"success":true,"placed":true,"vendor_id":payload.vendor_id}
		var placed:Dictionary=app.vendor();placed.position=payload.placement_position;placed.heading_radians=payload.placement_heading
		result.state.placed_vendors=[placed]
		app.vendor_placement.observe(result);return result
class App extends Node:
	var datapad_character_id:="101"
	var datapad_epoch:=1
	var world_ready:=true
	var loading_stage:=false
	var session_leaving:=false
	var xr_requested:=false
	var live_combat:Node
	var gameplay_session:Session
	var vendor_placement:Node
	var player:CharacterBody3D
	var datapad:Datapad
	var inventory:Inventory
	var combat_rig:Rig
	var services:Services
	var menu:Control
	func vendor()->Dictionary:return {"id":"301","template":"object/tangible/vendor/vendor_terminal_bulky.iff","name":"Owned vendor","category":"vendors","type":"vendor","deletable":false}
	func receipt(items:Array,sequence:int)->Dictionary:
		return {"ok":true,"source_kind":"core3_services","character_id":"101","state":{"vendors":items,"placed_vendors":[]},"live_response":{"session_id":"owned","sequence":sequence}}
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var app:=App.new();root.add_child(app)
	app.player=CharacterBody3D.new();app.add_child(app.player)
	app.gameplay_session=Session.new();app.add_child(app.gameplay_session)
	app.datapad=Datapad.new();app.add_child(app.datapad);app.datapad.ui=preload("res://scripts/datapad_ui.gd").new();app.datapad.add_child(app.datapad.ui);app.datapad.ui.set_anchors_preset(Control.PRESET_TOP_LEFT);app.datapad.ui.size=Vector2(900,625)
	app.inventory=Inventory.new();app.add_child(app.inventory)
	app.combat_rig=Rig.new();app.add_child(app.combat_rig)
	app.services=Services.new();app.services.app=app;app.add_child(app.services)
	app.menu=Control.new();app.add_child(app.menu);app.menu.hide()
	var controller:=preload("res://scripts/vendor_placement.gd").new();app.vendor_placement=controller;app.add_child(controller);controller.setup(app);controller.set_process(false)
	controller.floor_query=func(hand:Transform3D):return {"position":Vector3(hand.origin.x,0,hand.origin.z),"normal":Vector3.UP}
	controller.observe(app.receipt([app.vendor()],1))
	check(controller.vendors.size()==1 and app.datapad.ui.vendors.size()==1,"Owned vendor is projected by its original ID")
	app.datapad.ui.set_entries([]);app.datapad.ui.set_entries(app.datapad.ui.entries)
	check(app.datapad.ui.entries.size()==1,"Datapad refresh preserves exactly one vendor reference")
	check(not app.datapad.ui.can_delete(app.vendor()),"Vendor reference cannot be deleted as a local datapad entry")
	var hand:=Transform3D(Basis(Vector3.UP,.4),Vector3(1,1.2,0))
	check(controller.draw_vendor(app.vendor(),hand),"Original source model can be pulled into a hologram")
	check(controller.visual.scale==Vector3.ONE and controller.mount.global_position==Vector3(1,0,0),"Preview retains authored metre scale and snaps to floor")
	check(is_equal_approx(controller.pose.placement_heading,-.4),"Hand yaw uses source heading convention")
	controller.placement_frame(true,hand,1,1)
	check(app.services.calls.is_empty(),"Trigger already down when drawing cannot place")
	controller.placement_frame(true,hand,0,0)
	check(controller.held.is_empty() and app.services.calls.is_empty(),"Grip release cancels without native mutation")
	controller.draw_vendor(app.vendor(),hand);controller.placement_frame(false,hand,1,1)
	check(controller.held.is_empty() and app.services.calls.is_empty(),"Tracking loss cancels without mutation")
	app.inventory.held_item={"id":"other"}
	check(not controller.draw_vendor(app.vendor(),hand),"Preview cannot replace a held item")
	app.inventory.held_item={}
	controller.draw_vendor(app.vendor(),hand)
	app.services.state.vendor_placement.eligible=false;controller.placement_frame(true,hand,1,0);controller.placement_frame(true,hand,1,1)
	check(not controller.valid_pose and app.services.calls.is_empty(),"Unauthorized building cannot submit")
	app.services.state.vendor_placement.eligible=true;app.services.state.vendor_placement.cell_index=3;controller.update_pose(hand)
	check(not controller.valid_pose,"Stale room permissions cannot authorize placement")
	app.services.state.vendor_placement.cell_index=2;app.services.state_age=9;controller.update_pose(hand)
	check(not controller.valid_pose,"Stale authority cannot authorize placement")
	app.services.state_age=0
	var distant:=hand;distant.origin.x=5;controller.update_pose(distant)
	check(not controller.valid_pose,"Preview cannot exceed native four metre reach")
	controller.floor_query=func(_hand):return {"position":Vector3(1,0,0),"normal":Vector3.RIGHT}
	controller.update_pose(hand);check(not controller.valid_pose,"Wall hits do not count as floors")
	controller.floor_query=func(_hand):return {}
	controller.update_pose(hand);check(not controller.valid_pose,"Missing collision cannot authorize placement")
	controller.floor_query=func(p):return {"position":Vector3(p.origin.x,0,p.origin.z),"normal":Vector3.UP}
	app.services.busy=true;controller.placement_frame(true,hand,1,0);controller.placement_frame(true,hand,1,1);controller.placement_frame(true,hand,0,0)
	app.services.busy=false;await process_frame
	check(controller.held.is_empty() and app.services.calls.is_empty(),"Busy service does not queue a placement after cancellation")
	controller.draw_vendor(app.vendor(),hand);controller.placement_frame(true,hand,1,0);controller.placement_frame(true,hand,1,1)
	controller.placement_frame(true,hand,1,1)
	check(app.services.calls.size()==1 and controller.busy,"Fresh trigger submits exactly one request")
	controller.placement_frame(true,hand,0,0)
	check(controller.held.is_empty() and controller.busy,"Release after submission hides preview without pretending to undo commit")
	await process_frame;await process_frame
	check(not controller.busy and controller.vendors.is_empty() and controller.placed.size()==1,"Confirmed native snapshot replaces hologram with original placed model")
	check(controller.status=="Vendor placed.","Placement success requires native matching receipt")
	controller.observe(app.receipt([app.vendor()],1));check(controller.vendors.is_empty(),"Old live snapshot cannot resurrect placed vendor")
	controller.observe(app.receipt([app.vendor()],3));app.services.fail=true
	controller.draw_vendor(app.vendor(),hand);controller.placement_frame(true,hand,1,0);controller.placement_frame(true,hand,1,1)
	await process_frame;await process_frame
	check(not controller.draw_vendor(app.vendor(),hand),"Ambiguous reply requires fresh authority before redrawing")
	controller.observe(app.receipt([app.vendor()],4))
	check(controller.draw_vendor(app.vendor(),hand),"Fresh native unplaced state permits retry")
	controller.reset();check(controller.held.is_empty() and controller.placed.is_empty() and app.datapad.ui.vendors.is_empty(),"Reset clears preview, placed presentation and vendor references")
	# Exercise production floor ray against real Godot collision, without a headset.
	controller.floor_query=Callable()
	var floor_body:=StaticBody3D.new();root.add_child(floor_body)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(8,.2,8);shape.shape=box;floor_body.add_child(shape);floor_body.position.y=-.1
	await physics_frame;await physics_frame
	var hit:=controller.floor_at(hand)
	check(not hit.is_empty() and absf(hit.position.y)<.01,"Actual physics floor ray finds supporting geometry")
	check(controller.unobstructed(Vector3(1,0,0)),"Supporting floor does not falsely occlude placement")
	var wall:=StaticBody3D.new();root.add_child(wall);wall.position=Vector3(.5,.5,0)
	var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(.1,1,1);wall_shape.shape=wall_box;wall.add_child(wall_shape)
	await physics_frame;await physics_frame
	check(not controller.unobstructed(Vector3(1,0,0)),"Actual wall collision blocks preview eligibility")
	wall.queue_free()
	var pad:=preload("res://scripts/xr_datapad.gd").new();root.add_child(pad);pad.set_process(false);pad.ui=DragUI.new();pad.add_child(pad.ui);pad.is_open=true
	var drawn:Array=[];var parcels:Array=[]
	pad.vendor_draw_requested.connect(func(entry,_pose):drawn.append(entry));pad.parcel_draw_requested.connect(func(entry,_pose):parcels.append(entry))
	var surface:Dictionary={"surface":0,"pixel":Vector2(50,50)}
	pad.update_parcel_drag(surface,Transform3D.IDENTITY,0,true);pad.update_parcel_drag(surface,Transform3D.IDENTITY,.8,true)
	pad.update_parcel_drag({},Transform3D(Basis.IDENTITY,Vector3(.07,0,0)),.8,true)
	pad.update_parcel_drag({},Transform3D(Basis.IDENTITY,Vector3(.09,0,0)),.8,true)
	check(drawn.size()==1 and parcels.is_empty(),"Datapad grip pull dispatches one vendor preview, never a parcel")
	pad.is_open=false;pad.ui=null;pad.free()
	floor_body.queue_free();app.queue_free();await process_frame;await process_frame
	print(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"mode":"headless dummy renderer, mocked tracking and actual local floor collision"}));quit(0 if failures.is_empty() else 1)
