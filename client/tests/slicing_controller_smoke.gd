extends SceneTree
const Controller=preload("res://slicing/controller.gd")
const Fixture=preload("res://tests/slicing_board_smoke.gd")
class Session extends Node:
	var live:=true
	var session_id:="native-owned"
class Bag extends Node3D:
	signal item_held_changed(item:Dictionary)
	var assets=preload("res://scripts/inventory_assets.gd").new()
	var body:CharacterBody3D
	var rig:XROrigin3D
	var held_item:Dictionary={"id":"101","template":"object/tangible/slicing/slicing_laser_knife.iff","tool_kind":"slicing"}
	var held_model:Node3D
	var held_revision:=1
	var is_open:=false
	var action_pending:=false
	var side:="right"
	func held_controller()->XRController3D:return rig.get_node("LeftHand" if side=="left" else "RightHand")
class Services extends Node:
	var host:Node
	var rows:Array=[]
	var last_error:=""
	func identity_payload()->Dictionary:return {"account":"fixture","character_id":"500","session_id":"native-owned","position":[0,0,0],"zone":"tatooine","building_id":"0","cell_index":0}
	func terminal_records()->Array:return rows
	func world(point:Array)->Vector3:return Vector3(float(point[0]),float(point[1]),-float(point[2]))
	func accept_response(response:Dictionary,_resolve:bool)->bool:
		if response.get("character_id","")!="500":return false
		host.slicing.observe(response);return true
class Host extends Node3D:
	var datapad_epoch:=1
	var datapad_character_id:="500"
	var world_ready:=true
	var session_leaving:=false
	var services:Services
	var slicing:Node3D
	var player:CharacterBody3D
	var stage:Node3D
	var inventory_drops:Node3D
	var gameplay_session:Session
	var owned:Dictionary={"id":"202","template":"object/weapon/melee/knife/knife_stone.iff","name":"Crafted knife","sliceable":true,"slice_kind":"weapon"}
	var statistics_refreshes:=0
	func sync_inventory_equipment(force_statistics:=false)->void:
		if force_statistics:statistics_refreshes+=1
	var calls:Array=[]
	var reply:Dictionary={}
	func source_position_at(point:Vector3)->Vector3:return Vector3(point.x,point.y,-point.z)
	func owned_inventory_item(id:String)->Dictionary:return owned if id==str(owned.id) else {}
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return reply.duplicate(true)
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
static func response(active:bool,status:="active")->Dictionary:
	return {"ok":true,"source_kind":"core3_services","character_id":"500","state":{"character_id":"500","slicing":{"active":active,"status":status,"attempt_id":"native-puzzle-123","target_kind":"item","target_id":"202","tool_id":"101","anchor_position":[0,1.25,.65],"heading_radians":0,"cell_size":.1,"abandon_distance":2.5,"remaining_seconds":180,"challenge":Fixture.fixture(3,2)}}}
func _initialize()->void:call_deferred("run")
func settle()->void:
	for i in range(3):await process_frame
func run()->void:
	var app:=Host.new();root.add_child(app);app.stage=Node3D.new();app.add_child(app.stage);app.player=CharacterBody3D.new();app.add_child(app.player)
	app.gameplay_session=Session.new();app.add_child(app.gameplay_session)
	var bag:=Bag.new();app.add_child(bag);bag.body=app.player;bag.assets.configure();bag.rig=XROrigin3D.new();app.add_child(bag.rig)
	var camera:=Camera3D.new();camera.name="XRCamera3D";bag.rig.add_child(camera)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;bag.rig.add_child(hand)
	bag.held_model=Node3D.new();bag.add_child(bag.held_model);bag.held_model.add_child(bag.assets.instance(str(bag.held_item.template),.28))
	app.inventory_drops=preload("res://scripts/local_inventory_drops.gd").new();app.add_child(app.inventory_drops);app.inventory_drops.configure(bag.assets)
	app.services=Services.new();app.services.host=app;app.add_child(app.services)
	var controller:=Controller.new();app.slicing=controller;app.add_child(controller);controller.setup(app,bag);controller.set_process(false);controller.set_allowed(true)
	check(controller.tip().is_finite() and controller.tip().z<0,"Original knife barrel endpoint points along runtime-neutral hand aim")
	bag.side="left";bag.held_revision+=1
	check(controller.owns_tool() and controller.tip().is_finite(),"Same held-tool path accepts offhand without requiring weapon hand")
	var target_pose:=Transform3D(Basis.IDENTITY,Vector3(0,1,-.5))
	check(app.inventory_drops.drop(app.owned,target_pose),"Original owned target drop created")
	app.inventory_drops.records["202"].body.freeze=true
	var target:Dictionary=controller.target_at(target_pose.origin)
	check(target.get("id","")=="202","Knife-tip physical contact selects owned eligible target")
	app.owned.sliceable=false;app.owned.slice_block_reason="Only crafted items can be sliced"
	check(controller.target_at(target_pose.origin).is_empty() and controller.error=="Only crafted items can be sliced","Native eligibility and reason block otherwise identical uncrafted target")
	app.owned.sliceable=true
	app.reply=response(true)
	var head:=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
	controller.sample_input(target_pose.origin,.8,true,head);check(app.calls.is_empty(),"Held trigger on tool acquisition cannot initiate slicing")
	controller.sample_input(target_pose.origin,0,true,head);controller.sample_input(target_pose.origin,.8,true,head)
	await settle()
	check(app.calls.size()==1 and app.calls[0].path=="/services/slicing_begin" and app.calls[0].payload.target_position==[0.0,1.0,.5] and app.calls[0].payload.tool_id=="101","Fresh physical trigger dispatches owned target/tool and source-space contact")
	check(controller.active() and app.inventory_drops.records["202"].body.freeze and app.inventory_drops.records["202"].slicing_reserved,"Native accepted attempt freezes original item beneath grid")
	check(app.inventory_drops.nearest(app.inventory_drops.records["202"].body.global_position).is_empty() and app.inventory_drops.pickup_candidate(target_pose).is_empty(),"Active slice target cannot be picked up from frozen reserved proxy")
	check(is_equal_approx(controller.grid.global_position.y,1.25) and app.inventory_drops.records["202"].body.global_position.y<controller.grid.global_position.y,"Native anchor places cube at chest height with original target below")
	controller.board.touch({"color":0,"end":0});controller.board.extend([1,0,0]);controller.board.extend([2,0,0]);controller.board.touch({"color":0,"end":1})
	var before:Array=controller.board.paths();controller.observe(response(true))
	check(controller.board.paths()==before,"Same native status heartbeat preserves local wire progress")
	app.reply={"ok":false,"error":"connection interrupted"};await controller.request("complete",{"paths":before})
	check(controller.uncertain and controller.active() and controller.locked_target=="202","Uncertain completion never invents success or releases native target lock")
	app.reply=response(false,"failed");await controller.request("status")
	check(not controller.active() and controller.locked_target.is_empty() and not app.inventory_drops.records.has("202") and controller.error.contains("failed"),"Confirmed native failure clears frozen proxy and returns inventory presentation")
	app.services.rows=[{"id":"303","kind":"mission","position":Vector3(0,0,-1),"ui_anchors":[Transform3D(Basis.IDENTITY,Vector3(0,1,-1))]}]
	check(controller.target_at(Vector3(0,1,-1)).get("id","")=="303","Mission terminal uses source screen physical contact")
	app.services.rows[0].sliceable=false;app.services.rows[0].slice_block_reason="slicing_terminal_cooldown"
	check(controller.target_at(Vector3(0,1,-1)).is_empty() and controller.error=="slicing_terminal_cooldown","Native terminal eligibility and reason prevent starting a blocked terminal")
	app.services.rows[0].sliceable=true
	app.reply=response(true);controller.uncertain=false;controller.state={};controller.error="";var count:=app.calls.size()
	controller.begin({"id":"303","kind":"terminal","position":Vector3(0,0,-1)},Vector3(0,1,-1),head)
	await settle()
	check(app.calls.size()==count+1 and app.calls.back().payload.target_kind=="terminal" and not app.calls.back().payload.has("target_position"),"Terminal slicing uses native terminal target without item-proxy contact field")
	# Final endpoint dispatches one candidate; repeats and unknown responses cannot replay it.
	controller.reset();controller.observe(response(true));app.reply={"ok":false,"error":"connection interrupted"}
	count=app.calls.size()
	for color in range(2):
		var ends:Array=controller.board.pairs[color].ends
		for local in [controller.board.endpoint_position(ends[0])+Vector3.LEFT*.08,controller.board.endpoint_position(ends[0]),controller.board.center(ends[0].cell),controller.board.center(ends[1].cell),controller.board.endpoint_position(ends[1])]:
			controller.sample_input(controller.grid.to_global(local),0,true,head)
	controller.sample_input(controller.grid.to_global(controller.board.endpoint_position(controller.board.pairs[1].ends[1])),0,true,head)
	await settle()
	check(app.calls.size()==count+1 and app.calls.back().path=="/services/slicing_complete" and app.calls.back().payload.paths.size()==2,"Finishing final pipe submits all candidate paths exactly once")
	check(controller.submitted and controller.uncertain and controller.active(),"Uncertain final submission remains locked until authoritative status")
	var receipt:String=app.calls.back().payload.request_id
	app.reply=response(true);await controller.request("status")
	check(not controller.submitted and controller.board.complete(),"Active native status retains solved preview and allows receipt-safe recovery")
	app.reply=response(false,"succeeded");controller.sample_input(Vector3.ZERO,0,true,head);await settle()
	check(app.calls.back().path=="/services/slicing_complete" and app.calls.back().payload.request_id==receipt and not controller.active(),"Lost completion retries the same receipt and accepts native success")
	controller.observe(response(true));controller.board.wires={0:Fixture.line(3,0),1:Fixture.line(3,1)}
	app.reply=response(true);app.reply.ok=false;app.reply.mutation={"success":false,"status":"active","error":"candidate_rejected"}
	controller.sample_input(Vector3.ZERO,0,true,head);await settle();count=app.calls.size()
	controller.sample_input(Vector3.ZERO,0,true,head);await settle()
	check(controller.active() and not controller.submitted and not controller.uncertain and app.calls.size()==count,"Definitive native rejection allows editing without burning or repeatedly resubmitting unchanged candidate")
	controller.sample_input(controller.grid.to_global(controller.board.endpoint_position(controller.board.pairs[0].ends[0])),0,true,head)
	check(not controller.board.complete(),"Rejected complete candidate can detach an endpoint to edit")
	# Local display expiry is only a countdown; native polling decides the outcome.
	controller.reset();var timed:=response(true);timed.state.slicing.remaining_seconds=1
	controller.observe(timed);controller.received_at=Time.get_ticks_msec()-2000;controller.poll=10;count=app.calls.size()
	controller._process(0.0)
	check(controller.active() and app.calls.size()==count,"Display countdown reaching zero does not locally invent failure")
	app.reply=response(false,"expired");controller.poll=0;controller._process(0.0);await settle()
	check(app.calls.back().path=="/services/slicing_status" and not controller.active() and controller.error.contains("Time expired"),"Native status confirms timer failure and releases target")
	controller.observe(response(true));app.reply=response(false,"walked_away");app.player.global_position=Vector3(3,0,0);count=app.calls.size();controller.poll=0
	controller._process(0.0);controller._process(0.0);await settle()
	check(app.calls.size()==count+1 and app.calls.back().path=="/services/slicing_status" and not controller.active() and controller.error.contains("Too far away"),"Native watchdog confirms walkaway from player origin rather than incorrectly burning by visual anchor distance")
	app.player.global_position=Vector3.ZERO
	var completed:=response(false,"succeeded");controller.equipment_updated(completed);controller.equipment_updated(completed)
	check(app.statistics_refreshes==1,"Confirmed slicing success requests one forced equipment-stat refresh per attempt")
	controller.error="Slice complete";controller.held_changed({})
	check(controller.error.is_empty() and not controller.notice.visible,"Switching away from knife clears inactive completion notice")
	controller.uncertain=true;controller.error="Checking CoreCU";controller.held_changed({})
	check(controller.error=="Checking CoreCU","Switching tool preserves uncertain outcome notice")
	# A request from a previous character must not restore its attempt after reset.
	controller.reset();app.reply=response(true);controller.request("status");controller.reset();await settle()
	check(not controller.active() and not controller.busy and controller.locked_target.is_empty(),"Late response after reset cannot restore old character puzzle or item lock")
	controller.reset();check(not controller.active() and not controller.busy and controller.locked_target.is_empty(),"Character reset releases local presentation and fences session state")
	app.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"original_assets":true,"mocked_transport":true,"renderer":"dummy","headset_validated":false}));quit(0 if errors.is_empty() else 1)
