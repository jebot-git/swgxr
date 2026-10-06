extends SceneTree
class Inventory extends Node:
	var held_item:Dictionary={}
	var is_open:=false
	var finishes:Array=[]
	func finish_item_action(success:bool)->void:finishes.append(success);held_item={}
	func set_open(value:bool)->void:is_open=value
	func set_busy(_value:bool,_message:String)->void:pass
class Datapad extends Node:
	var ui:Node
	var is_open:=false
class UI extends Node:
	var status:=""
	func set_status(value:String)->void:status=value
class Rig extends Node:
	func stow()->void:pass
class Placement extends Node:
	var records:Dictionary={}
	var placed:Dictionary={}
	func blocks_interactions()->bool:return false
class Services extends Node:
	var state_age:=0.0
	var allowed:=true
	var busy:=false
	var ui:Node
	var poll_clock:=0.0
	var state:Dictionary={}
	var calls:Array=[]
	var fail:=false
	func identity_payload()->Dictionary:return {"building_id":"456","cell_index":2}
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],-p[2])
	func request(action:String,payload:Dictionary)->Dictionary:
		calls.append({"action":action,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		if fail:return {"ok":false,"error":"Unconfirmed"}
		return {"ok":true,"mutation":{"success":true,"request_id":payload.request_id}}
class App extends Node:
	var datapad_epoch:=1
	var datapad_character_id:="101"
	var world_ready:=true
	var loading_stage:=false
	var session_leaving:=false
	var xr_requested:=false
	var player:CharacterBody3D
	var inventory:Inventory
	var services:Services
	var datapad:Datapad
	var combat_rig:Rig
	var vendor_placement:Placement
	func owned_inventory_item(id:String)->Dictionary:return {"id":id} if id=="301" else {}
	func update_inventory_presentation()->void:pass
var checks:=0
var failures:Array=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var app:=App.new();root.add_child(app)
	app.player=CharacterBody3D.new();app.add_child(app.player)
	app.inventory=Inventory.new();app.add_child(app.inventory)
	app.services=Services.new();app.add_child(app.services)
	app.datapad=Datapad.new();app.add_child(app.datapad);app.datapad.ui=UI.new();app.datapad.add_child(app.datapad.ui)
	app.combat_rig=Rig.new();app.add_child(app.combat_rig)
	app.vendor_placement=Placement.new();app.add_child(app.vendor_placement)
	var bazaar:Dictionary={"id":"12","kind":"bazaar","position":[0,0,0],"building_id":"456","cell_index":2}
	app.services.state={"terminals":[bazaar]}
	var row:Dictionary={"id":"21","kind":"vendor","owner_id":"101","template":"object/mobile/vendor/human_male.iff","position":[0,0,0],"building_id":"456","cell_index":2,"customization":{"/shared_owner/blend_nosedepth_0":0},"customization_controls":[{"id":"/shared_owner/blend_nosedepth_0","allowed":[0,64,128,255],"pair":"/shared_owner/blend_nosedepth_1"},{"id":"/shared_owner/blend_nosedepth_1","allowed":[0,64,128,255],"pair":"/shared_owner/blend_nosedepth_0"}]}
	var item:Dictionary={"id":"301","name":"Owned item","template":"object/tangible/mission/mission_datadisk.iff"}
	var widget:=preload("res://scripts/vendor_commerce.gd").new();app.add_child(widget);widget.setup(app);widget.set_process(false)
	var hand:=Transform3D(Basis.IDENTITY,Vector3(0,.9,0))
	check(widget.try_drop(item,hand),"Releasing owned item onto nearby bazaar opens sale draft")
	check(widget.mode=="sale" and app.services.calls.is_empty(),"Opening draft never transfers item or credits")
	check(app.inventory.finishes==[true],"Native item remains in inventory while temporary held presentation clears")
	widget.change_slider(0,.18);widget.change_slider(1,.18)
	check(widget.price==20000,"Bazaar sliders respect original 20000 price limit")
	var knob_pose:=Transform3D(widget.root_ui.global_basis,widget.knob.global_position)
	widget.editor_frame(true,knob_pose,0,0);widget.editor_frame(true,knob_pose,1,0)
	knob_pose.basis=widget.root_ui.global_basis*Basis(Vector3.BACK,deg_to_rad(35))
	widget.editor_frame(true,knob_pose,1,0)
	check(not widget.galactic_search,"Counterclockwise physical knob disables galactic search")
	widget.close();check(app.services.calls.is_empty(),"Cancelling sale draft does not list or consume the item")
	widget.open_sale(bazaar,item);widget.price=120;widget.galactic_search=false
	await widget.submit()
	check(app.services.calls.size()==1 and app.services.calls[0].action=="bazaar_sell" and not app.services.calls[0].payload.galactic_search,"Confirmation submits actual item and proposed search setting")
	check(widget.mode.is_empty() and app.datapad.ui.status=="Item listed for sale.","Matching native receipt closes draft")
	widget.open_sale(row,item);widget.change_slider(0,.18);widget.change_slider(1,.18)
	check(widget.price==99999999,"Vendor price limit is independent of bazaar limit")
	widget.close();app.vendor_placement.records={"21":row};app.services.state.terminals=[]
	var foreign:=row.duplicate(true);foreign.owner_id="999";app.vendor_placement.records={"21":foreign}
	check(widget.try_drop(item,hand) and widget.mode.is_empty(),"Foreign vendor consumes no item and opens no stock draft")
	app.vendor_placement.records={"21":row}
	widget.gesture_frame(true,hand,hand,Vector2.ZERO,Vector2.ZERO)
	widget.gesture_frame(true,hand,hand,Vector2.ONE,Vector2.ONE)
	check(widget.mode=="customize" and app.services.calls.size()==1,"Both triggers take precedence over simultaneous grips")
	check(widget.preview!=null and widget.preview.mesh.get_blend_shape_count()>0,"Original full-color vendor mesh retains source morphs")
	widget.change_slider(0,.18)
	check(widget.draft["/shared_owner/blend_nosedepth_0"]==255 and widget.draft["/shared_owner/blend_nosedepth_1"]==0,"Editing one original morph clears its exclusive partner")
	var morph_index:int=widget.preview.find_blend_shape_by_name("blend_nosedepth_0")
	check(morph_index>=0 and is_equal_approx(widget.preview.get_blend_shape_value(morph_index),1),"Colored preview visibly receives the proposed morph")
	widget.close();check(app.services.calls.size()==1,"Discarding customization does not mutate native appearance")
	widget.gesture_frame(true,hand,hand,Vector2.ZERO,Vector2.ZERO);widget.gesture_frame(true,hand,hand,Vector2.ONE,Vector2.ZERO)
	widget.gesture_frame(true,hand,hand,Vector2.ONE,Vector2.ZERO)
	check(app.services.calls.size()==2 and app.services.calls.back().action=="vendor_recover","Fresh two-hand grip submits exactly one recovery")
	await process_frame;await process_frame
	widget.gesture_frame(true,hand,hand,Vector2.ONE,Vector2.ZERO)
	check(app.services.calls.size()==2,"Held grips cannot repeat recovery after response")
	widget.open_customization(row);widget.change_slider(0,0);await widget.submit()
	check(app.services.calls.back().action=="vendor_customize" and app.services.calls.back().payload.customization["/shared_owner/blend_nosedepth_0"]==128,"Customization sends original vendor variable values")
	app.services.fail=true;widget.open_sale(bazaar,item);await widget.submit()
	var failed:Dictionary=app.services.calls.back().payload.duplicate(true)
	widget.open_sale(bazaar,item);widget.change_slider(0,.18);await widget.submit()
	check(app.services.calls.back().payload==failed,"Uncertain retry preserves exact proposal and receipt instead of issuing a duplicate sale")
	app.services.fail=false
	widget.open_sale(bazaar,item);widget.editor_frame(false,hand,0,0)
	check(widget.mode.is_empty(),"Tracking loss dismisses local sale proposal")
	var count:=app.services.calls.size();app.services.busy=true;widget.open_sale(bazaar,item);await widget.submit();widget.close();app.services.busy=false;await process_frame
	check(app.services.calls.size()==count,"Busy services never queue a delayed sale after cancellation")
	widget.reset();check(widget.uncertain.is_empty(),"Character reset clears old receipts and gestures")
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel)
	var actions:Array=[];panel.action_requested.connect(func(action,payload):actions.append({"action":action,"payload":payload}))
	panel.configure({"id":"21","kind":"vendor","listings":[{"id":"31","price":99999,"buy_eligible":true}]},{"cash":200000});panel.selected=0;panel.confirm()
	check(actions.size()==1 and actions[0].action=="vendor_buy","Vendor browser routes purchase to vendor price limits")
	panel.queue_free();app.queue_free();await process_frame;await process_frame
	print(JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty(),"native":"mocked","tracking":"mocked","renderer":"headless dummy"}));quit(0 if failures.is_empty() else 1)
