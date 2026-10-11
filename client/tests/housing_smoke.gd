extends SceneTree
class Services extends Node:
	var peers:Array=[]
	func source(p:Vector3)->Array:return [p.x,p.y,-p.z]
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],-p[2])
	func identity_payload()->Dictionary:return {"account":"fixture","character_id":"42","zone":"tatooine","position":[0,0,0],"building_id":"0","cell_index":0,"session_id":"fixture-session"}
class Host extends Node3D:
	var world_stream:Node
	var datapad_character_id:="42"
	var datapad_epoch:=1
	var services:Node
	var stage:Node3D
	var xr_origin:XROrigin3D
	var player:CharacterBody3D
	var inventory_snapshot:Dictionary={}
	var calls:Array=[]
	var response:Dictionary={}
	var change_epoch:=false
	func api(_method:int,path:String,data:Dictionary)->Dictionary:
		calls.append({"path":path,"data":data.duplicate(true)})
		await get_tree().process_frame
		if change_epoch:datapad_epoch+=1
		return response.duplicate(true)
	func reconcile_inventory_presentations()->void:pass
	func update_inventory_presentation()->void:pass
class Stream extends Node:
	var authored:Dictionary={}
	var bases:Dictionary={}
	func has_authored_object(id:String)->bool:return authored.has(id)
	func authored_basis(id:String)->Variant:return bases.get(id)
var checks:=0
var errors:Array=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var host:=Host.new();root.add_child(host);host.services=Services.new();host.add_child(host.services)
	host.stage=preload("res://scripts/cell_stage.gd").new();host.add_child(host.stage)
	host.xr_origin=load("res://xr/player_rig.tscn").instantiate();host.add_child(host.xr_origin);host.player=host.xr_origin.get_node("PlayerBody");host.player.set_physics_process(false)
	var bag=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);bag.configure(host.xr_origin,host.player);bag.allowed=true;bag.set_process(false)
	var controller=preload("res://housing/controller.gd").new();host.add_child(controller);controller.setup(host,bag);controller.set_process(false);controller.allowed=true
	var template:="object/building/player/player_house_tatooine_small_style_01.iff"
	var house:Dictionary={"id":"987654","template":template,"position":[20,0,10],"quaternion":[0,0,0,1]}
	controller.scenery.apply({"structures":[house],"items":[]})
	check(controller.scenery.structures.has("987654"),"Original Tatooine house geometry loaded")
	check(host.stage.cell_regions.has("house:987654"),"Persistent house registered in shared cell/collision system")
	var model:Node3D=controller.scenery.structures.get("987654")
	if model!=null:
		var defs:Dictionary=model.get_meta("manifest").cells
		check(defs.has("987654:1") and not defs.has("1:1"),"Authored cells rebound to actual native building ID")
		var support_found:=false
		for cell:Dictionary in defs.values():
			if cell.get("is_exterior",false):continue
			var v:Array=cell.get("floor_vertices",[])
			for i:int in range(0,v.size(),3):
				var point:Vector3=model.to_global(Vector3(v[i],v[i+1],v[i+2])+Vector3.UP*.1)
				var hit:Dictionary=host.stage.ground_support.sample_support(point,["987654:1"],1,1,{})
				if hit.get("found",hit.get("valid",false)) or hit.has("height"):support_found=true;break
			if support_found:break
		check(support_found,"Original house floor supports native ground queries")
		check(not model.find_children("*","StaticBody3D",true,false).is_empty(),"Original house wall/floor collision is present")
	var furniture:Dictionary={"id":"200","template":"object/tangible/furniture/all/frn_all_chair_kitchen_s1.iff","building_id":"987654","cell_index":1,"position":[22,1,10],"quaternion":[0,0,0,1],"recoverable":true}
	controller.scenery.apply({"structures":[house],"items":[furniture]})
	check(controller.scenery.items.has("200"),"Original persistent furniture renders at native source scale")
	var chair:MeshInstance3D=controller.scenery.items.get("200")
	if chair!=null:
		check(chair.scale.is_equal_approx(Vector3.ONE) and chair.global_position.is_equal_approx(Vector3(22,1,-10)),"Furniture retains original dimensions and native position")
		check(not chair.find_children("*","StaticBody3D",true,false).is_empty(),"Placed furniture contributes collision")
		controller.scenery.fall["200"]=Vector3(22,2,-10)
		controller.scenery.apply({"structures":[house],"items":[furniture]})
		controller.scenery._process(.05)
		check(chair.global_position.y<2 and chair.global_position.y>1,"Ordinary release falls toward native floor instead of teleporting")
		for i:int in range(40):controller.scenery._process(.05)
		check(chair.global_position.is_equal_approx(Vector3(22,1,-10)),"Gravity presentation settles exactly at persisted native pose")
		furniture.position=[22,2,10];controller.scenery.apply({"structures":[house],"items":[furniture]})
		controller.scenery._process(.05)
		check(chair.global_position.y==2 and not chair.has_meta("fall_target"),"Suspended native pose remains in the air")
	var deed:Dictionary={"id":"100","template":"object/tangible/deed/player_house_deed/tatooine_house_small_deed.iff","structure_template":template,"name":"Small house deed"}
	bag.take_item(deed)
	check(not controller.deed.is_empty() and is_instance_valid(controller.preview),"Inventory deed draw creates original placement hologram")
	var no_collision:=true
	for body:StaticBody3D in controller.preview.find_children("*","StaticBody3D",true,false):no_collision=no_collision and body.collision_layer==0
	check(no_collision,"Hologram cannot block its placement ray or player")
	var proposal:Dictionary={"deed_id":"100","placement_position":[1,0,2],"rotation":1,"valid":true}
	check(controller.same_candidate(proposal,proposal),"Server approval matches exact requested placement")
	var changed:=proposal.duplicate(true);changed.rotation=2;check(not controller.same_candidate(proposal,changed),"Rotation invalidates placement approval")
	changed=proposal.duplicate(true);changed.placement_position=[3,0,2];check(not controller.same_candidate(proposal,changed),"Moving preview invalidates old approval")
	var count:int=host.calls.size();controller.try_drop(deed,Transform3D.IDENTITY)
	check(host.calls.size()==count and controller.deed.is_empty(),"Releasing blueprint cancels without server mutation or local drop")
	var native:Dictionary={"character_id":"42","housing":{"structures":[],"items":[]},"inventory":{"source_kind":"core3_inventory","character_id":"42"}}
	host.response={"ok":true,"source_kind":"core3_services","character_id":"42","state":native,"mutation":{"success":true}}
	await controller.request("status")
	check(host.calls[-1].path=="/services/house_status" and host.inventory_snapshot.get("character_id")=="42","Housing routes and inventory reconciliation use native session")
	controller.busy=true;await controller.request("place",proposal);check(host.calls[-1].path=="/services/house_status","Busy requests never queue delayed placements");controller.busy=false
	var successful_response:=host.response.duplicate(true)
	host.response={"ok":false,"error":"native_movement_speed_rejected"}
	await controller.request("preview",proposal)
	check(controller.error=="Movement was rejected. Aim at the plot again." and controller.transient_error_until>0,"Movement rejection becomes a bounded placement notice")
	controller.expire_transient_error(controller.transient_error_until)
	check(controller.error.is_empty(),"Movement notice clears without a later successful placement")
	host.response={"ok":false,"error":"Native no-build area"}
	await controller.request("preview",proposal)
	controller.expire_transient_error(Time.get_ticks_msec()+10000)
	check(controller.error=="Native no-build area","Native placement restrictions remain visible")
	controller.held_changed({})
	check(controller.error.is_empty(),"Changing held item clears stale placement errors")
	host.response=successful_response
	controller.scenery.apply({"structures":[house],"items":[furniture]})
	host.response.state.inventory.items=[{"id":"200","template":furniture.template}]
	await controller.recover_item({"item_id":"200","left_hand":[22,2,10],"right_hand":[22,2,10]})
	check(host.calls[-1].path=="/services/house_recover" and not controller.scenery.items.has("200"),"Confirmed recovery removes the original house decoration")
	check(host.inventory_snapshot.items[0].id=="200" and not bag.action_pending,"Recovered item appears in native inventory and pending interaction clears")
	host.response={"ok":false,"error":"Furniture out of reach"}
	controller.scenery.apply({"structures":[house],"items":[furniture]})
	await controller.recover_item({"item_id":"200","left_hand":[99,2,10],"right_hand":[22,2,10]})
	check(controller.scenery.items.has("200") and not bag.action_pending,"Rejected recovery retains decoration and clears pending interaction")
	host.response=successful_response
	var old:Dictionary=controller.state.duplicate(true);var forged:=host.response.duplicate(true);forged.character_id="99"
	check(not controller.observe(forged) and controller.state==old,"Foreign character state rejected")
	host.change_epoch=true;await controller.request("status");check(controller.state==old,"Previous character reply cannot replace housing state");host.change_epoch=false;controller.reset()
	check(host.stage.cell_regions.is_empty(),"Session reset unregisters all house collision and cells")
	var panel=preload("res://scripts/service_panel.gd").new();host.add_child(panel);var emitted:Array=[];panel.action_requested.connect(func(action,payload):emitted.append({"action":action,"payload":payload}))
	var terminal:Dictionary={"id":"55","kind":"house","maintenance":300,"item_count":5,"item_limit":100,"options":[{"id":"deposit","name":"Upkeep"},{"id":"add_ENTRY","name":"Entry","permission_list":"ENTRY","permission_action":"add"}]}
	panel.configure(terminal,{"cash":250,"bank":1000});panel.selected=0;panel.confirm();check(panel.slider.visible and panel.terminal.kind=="house_deposit","House upkeep opens existing grabbable slider")
	panel.slider.amount=125;panel.confirm();check(emitted[-1].action=="house_deposit" and emitted[-1].payload.amount==125,"Upkeep submits explicit native cash deposit")
	panel.terminal={};panel.configure(terminal,{"cash":250,"bank":1000});panel.selected=1;panel.confirm();check(emitted[-1].action=="house_permission_arm" and not emitted[-1].payload.has("target_id"),"Permission selection arms handshake instead of changing an arbitrary player")
	# Public source decorations must have one visual owner, including late chunks.
	host.world_stream=Stream.new();host.add_child(host.world_stream)
	var public:Dictionary=furniture.duplicate(true);public.building_id="1028590";public.recoverable=false
	host.world_stream.authored["200"]=true
	controller.scenery.apply({"structures":[],"items":[public]})
	check(not controller.scenery.items.has("200"),"Static public furniture is not rendered again by housing")
	host.world_stream.authored.clear();host.world_stream.bases["1028590"]=Basis(Vector3.UP,.7)
	controller.scenery.apply({"structures":[],"items":[public]})
	check(controller.scenery.items["200"].global_basis.is_equal_approx(Basis(Vector3.UP,.7)),"Dynamic public-building furniture inherits the original building rotation")
	host.world_stream.authored["200"]=true;controller.scenery._process(.016)
	check(not controller.scenery.items.has("200"),"Late static chunk removes duplicate visual and collision")
	host.world_stream.authored.clear();public.client_object=true
	controller.scenery.apply({"structures":[],"items":[public]})
	check(not controller.scenery.items.has("200"),"Native client scenery cannot become a duplicate house item")
	host.free()
	var result:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"headless dummy","tracking":"mocked","native_execution":false,"live_headset":false}
	var f:=FileAccess.open("res://../runtime/evidence/housing-client.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  ")+"\n");print(JSON.stringify(result));quit(0 if errors.is_empty() else 1)
