extends SceneTree
class DragUI extends Control:
	func draggable_entry_at(_pixel:Vector2)->Dictionary:return {"id":"301","mission_id":"401","type":"mission_parcel"}
class Session extends Node:
	var live:=true
	var session_id:="owned"
class Datapad extends Node3D:
	signal parcel_draw_requested(entry:Dictionary,pose:Transform3D)
	var ui:Control
	var is_open:=true
	func set_open(value:bool)->void:is_open=value
class Inventory extends Node:
	var assets:=preload("res://scripts/inventory_assets.gd").new()
	var held_item:Dictionary={}
class Rig extends Node:
	var stowed:=0
	func stow()->void:stowed+=1
class Services extends Node:
	var app:Node
	var ui:Node
	var busy:=false
	var allowed:=true
	var state_age:=0.0
	var state:Dictionary={}
	var calls:Array=[]
	var fail:=false
	func identity_payload()->Dictionary:return {"building_id":"0","cell_index":0}
	func world(position:Array)->Vector3:return Vector3(position[0],position[1],-position[2])
	func request(action:String,payload:Dictionary)->Dictionary:
		calls.append({"action":action,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		if fail:return {"ok":false,"error":"Unconfirmed native response"}
		var result:Dictionary=app.receipt([],app.mission_parcels.native_sequence+1)
		result.mutation={"success":true};app.mission_parcels.observe(result);return result
class App extends Node:
	var datapad_account:="fixture"
	var datapad_character_id:="101"
	var datapad_epoch:=1
	var world_ready:=true
	var loading_stage:=false
	var session_leaving:=false
	var xr_requested:=false
	var live_combat:Node
	var gameplay_session:Session
	var mission_parcels:Node
	var player:CharacterBody3D
	var datapad:Datapad
	var inventory:Inventory
	var combat_rig:Rig
	var services:Services
	var menu:Control
	func receipt(items:Array,sequence:int)->Dictionary:
		return {"ok":true,"source_kind":"core3_services","character_id":"101","state":{"character_id":"101","parcels":items,"delivery_contacts":services.state.get("delivery_contacts",[])},"live_response":{"session_id":"owned","sequence":sequence}}
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func parcel()->Dictionary:return {"id":"301","mission_id":"401","receiver_id":"501","template":"object/tangible/mission/mission_datadisk.iff","name":"Delivery parcel","stage":"deliver","type":"mission_parcel","category":"data"}
func _initialize()->void:create_timer(25).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var app:=App.new();root.add_child(app)
	app.player=CharacterBody3D.new();app.add_child(app.player);app.player.position=Vector3(0,0,1)
	app.gameplay_session=Session.new();app.add_child(app.gameplay_session)
	app.datapad=Datapad.new();app.add_child(app.datapad);app.datapad.ui=preload("res://scripts/datapad_ui.gd").new();app.datapad.add_child(app.datapad.ui);app.datapad.ui.set_anchors_preset(Control.PRESET_TOP_LEFT);app.datapad.ui.size=Vector2(900,625)
	app.inventory=Inventory.new();app.add_child(app.inventory);app.inventory.assets.configure()
	app.combat_rig=Rig.new();app.add_child(app.combat_rig)
	app.services=Services.new();app.services.app=app;app.add_child(app.services)
	app.menu=Control.new();app.add_child(app.menu);app.menu.hide()
	app.services.state={"delivery_contacts":[{"id":"501","mission_id":"401","role":"receiver","stage":"deliver","position":[0,0,0],"building_id":"0","cell_index":0}]}
	var parcels:=preload("res://scripts/mission_parcels.gd").new();app.mission_parcels=parcels;app.add_child(parcels);parcels.setup(app);parcels.set_process(false)
	parcels.observe(app.receipt([parcel()],1))
	check(parcels.parcels.size()==1 and app.datapad.ui.mission_parcels.size()==1,"Native owned item is projected into datapad by the same original object ID")
	app.datapad.ui.set_entries([{"id":"waypoint1","category":"waypoints"}])
	check(app.datapad.ui.entries.any(func(row):return row.get("type","")=="mission_parcel"),"Ordinary datapad refresh preserves confirmed native parcel projection")
	var hand:=Transform3D(Basis.IDENTITY,Vector3(0,1.1,.2))
	var forged:=parcel();forged.id="999"
	check(not parcels.draw_parcel(forged,hand),"A stale or invented datapad entry cannot create a held native parcel")
	app.inventory.held_item={"id":"other"}
	check(not parcels.draw_parcel(parcel(),hand),"Drawing parcel cannot replace another held inventory item")
	app.inventory.held_item={}
	check(parcels.draw_parcel(parcel(),hand) and parcels.visual.mesh.get_faces().size()==183,"Grip draw uses the supplied original 61-triangle mission datadisk model")
	check(not app.datapad.is_open and app.combat_rig.stowed==1 and parcels.blocks_interactions(),"Held parcel closes datapad and reserves hand from weapon/inventory actions")
	parcels.delivery_frame(true,hand,.8,.8)
	check(app.services.calls.is_empty(),"Trigger held during extraction cannot instantly deliver")
	parcels.delivery_frame(true,hand,.8,0)
	parcels.delivery_frame(true,Transform3D(Basis.IDENTITY,Vector3(3,1.1,0)),.8,.8)
	check(app.services.calls.is_empty(),"Delivery needs parcel physically presented near correct receiver")
	parcels.delivery_frame(true,hand,.8,0);parcels.delivery_frame(true,hand,.8,.8)
	for _frame in range(3):await process_frame
	check(app.services.calls.size()==1 and app.services.calls[0].action=="delivery_complete" and app.services.calls[0].payload.parcel_id=="301","Presented parcel sends the exact owned native item/mission/NPC for completion")
	check(parcels.held.is_empty() and parcels.parcels.is_empty() and app.datapad.ui.mission_parcels.is_empty(),"Native committed completion clears hand and datapad together")
	parcels.observe(app.receipt([parcel()],1))
	check(parcels.parcels.is_empty(),"Older service receipt cannot resurrect delivered item")
	parcels.observe(app.receipt([parcel()],3));parcels.draw_parcel(parcel(),hand)
	parcels.delivery_frame(true,hand,0,0)
	check(parcels.held.is_empty() and parcels.parcels.size()==1,"Release returns presentation to datapad without a world drop or native item mutation")
	parcels.draw_parcel(parcel(),hand);app.services.fail=true
	await parcels.deliver(app.services.state.delivery_contacts[0])
	var retry:Dictionary=app.services.calls.back().payload
	check(not parcels.held.is_empty() and not parcels.receipt.is_empty(),"Unconfirmed completion retains item and stable mutation receipt")
	await parcels.deliver(app.services.state.delivery_contacts[0])
	check(app.services.calls.back().payload.request_id==retry.request_id,"Explicit retry reuses request ID instead of risking duplicate native reward")
	parcels.observe(app.receipt([],4))
	check(parcels.held.is_empty() and parcels.parcels.is_empty() and parcels.receipt.is_empty(),"Mission cancellation removes held and datapad representations from authoritative empty state")
	var craft:=parcel();craft.id="302";craft.mission_id="402";craft.mission_kind="crafting"
	parcels.observe(app.receipt([craft],5))
	check(parcels.parcels.has("302"),"Crafting mission items share the same owned-object presentation path")
	app.services.fail=false
	app.datapad.ui.select_category("data")
	check(app.datapad.ui.cancel_mission_button.visible and not app.datapad.ui.cancel_mission_button.disabled and not app.datapad.ui.delete_button.visible,"Owned mission parcel exposes explicit Cancel mission, never generic Delete")
	parcels.draw_parcel(craft,hand)
	app.datapad.ui.cancel_mission_button.pressed.emit()
	for _frame in range(3):await process_frame
	check(app.services.calls.back().action=="mission_abort" and app.services.calls.back().payload.mission_id=="402","Datapad Cancel mission routes exact owned objective to native services abort")
	check(parcels.held.is_empty() and parcels.parcels.is_empty() and not app.datapad.ui.cancel_mission_button.visible,"Authoritative cancellation clears held original item and datapad cancel action together")
	parcels.observe(app.receipt([craft],5))
	check(parcels.parcels.is_empty(),"Stale pre-cancel reply cannot restore a held mission item")
	var native_mission:Dictionary={"id":"403","category":"data","source":"core3_datapad_container","name":"Original mission"}
	app.datapad.ui.set_entries([native_mission]);app.datapad.ui.set_owned_missions([{"id":"403"}]);app.datapad.ui.select_category("data")
	check(app.datapad.ui.cancellable_mission_id(native_mission)=="403" and app.datapad.ui.cancel_mission_button.visible,"Original native mission entry can be cancelled before pickup using authoritative active mission ID")
	check(app.datapad.ui.cancellable_mission_id({"id":"999","mission_id":"999"}).is_empty() and app.datapad.ui.cancellable_mission_id({"id":"403","reference_only":true}).is_empty(),"Unowned and reference-only entries cannot invoke mission cancellation")

	# Actual holographic panel dispatch keeps read/dialogue separate from pickup.
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel)
	var actions:Array=[];panel.action_requested.connect(func(action,payload):actions.append({"action":action,"payload":payload}))
	panel.configure({"id":"500","kind":"delivery","mission_id":"401","dialogue":"Original mission contact text","confirm_action":"delivery_pickup"},{})
	check(actions.is_empty() and panel.delivery_dialogue.text=="Original mission contact text","Opening giver dialogue never grants a parcel")
	panel.confirm()
	check(actions.size()==1 and actions[0].action=="delivery_pickup" and actions[0].payload.npc_id=="500","Separate Confirm submits original giver and objective")
	panel.configure({"id":"501","kind":"delivery","mission_id":"401","confirm_action":"delivery_complete"},{})
	panel.confirm()
	check(actions.size()==1,"Receiver dialogue cannot bypass held-parcel gesture with a generic button")
	var pad:=preload("res://scripts/xr_datapad.gd").new();root.add_child(pad);pad.set_process(false);pad.ui=DragUI.new();pad.add_child(pad.ui);pad.is_open=true
	var drawn:Array=[];pad.parcel_draw_requested.connect(func(entry,_pose):drawn.append(entry))
	var hit:Dictionary={"surface":0,"pixel":Vector2(50,50)}
	pad.update_parcel_drag(hit,Transform3D.IDENTITY,0,true)
	pad.update_parcel_drag(hit,Transform3D.IDENTITY,.8,true)
	pad.update_parcel_drag(hit,Transform3D(Basis.IDENTITY,Vector3(.03,0,0)),.8,true)
	check(drawn.is_empty(),"Grip must pull away from the datapad rather than extracting on accidental press")
	pad.update_parcel_drag({},Transform3D(Basis.IDENTITY,Vector3(.07,0,0)),.8,true)
	pad.update_parcel_drag({},Transform3D(Basis.IDENTITY,Vector3(.09,0,0)),.8,true)
	check(drawn.size()==1 and drawn[0].id=="301","Six-centimeter grip drag extracts exactly one pointed native parcel")
	pad.update_parcel_drag(hit,Transform3D.IDENTITY,0,true);pad.update_parcel_drag({"surface":1,"pixel":Vector2.ZERO},Transform3D.IDENTITY,.8,true)
	pad.update_parcel_drag({},Transform3D(Basis.IDENTITY,Vector3(.09,0,0)),.8,true)
	check(drawn.size()==1,"Info pane and unrelated surfaces cannot draw the selected parcel")
	# Bypass xr_datapad exit cleanup because this gesture-only harness has no viewports.
	pad.is_open=false;pad.ui=null;pad.free()
	panel.free();app.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_transport":"mocked","original_parcel_model":true,"xr":"off"}
	FileAccess.open("res://../runtime/evidence/mission-parcels-client.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
