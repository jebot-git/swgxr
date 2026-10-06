extends SceneTree
class Services extends Node:
	var peers:Array=[]
	func source(p:Vector3)->Array:return [p.x,p.y,-p.z]
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],-p[2])
	func identity_payload()->Dictionary:return {"account":"fixture","character_id":"42","position":[0,0,0],"building_id":"0","cell_index":0}
class Host extends Node3D:
	var datapad_character_id:="42"
	var datapad_epoch:=1
	var world_ready:=true
	var services:Node
	var datapad:Node3D
	var stage:Node3D
	var xr_origin:XROrigin3D
	var player:CharacterBody3D
	var inventory_snapshot:Dictionary={}
	var calls:Array=[]
	var reply:Dictionary={}
	func api(_method:int,path:String,data:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":data.duplicate(true)});await get_tree().process_frame;return reply.duplicate(true)
	func owned_inventory_item(id:String)->Dictionary:
		for item:Dictionary in inventory_snapshot.get("items",[]):
			if str(item.id)==id:return item
		return {}
	func reconcile_inventory_presentations()->void:pass
	func update_inventory_presentation()->void:pass
var checks:=0
var errors:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var host:=Host.new();root.add_child(host);host.services=Services.new();host.add_child(host.services)
	host.stage=preload("res://scripts/cell_stage.gd").new();host.add_child(host.stage)
	host.xr_origin=load("res://xr/player_rig.tscn").instantiate();host.add_child(host.xr_origin);host.player=host.xr_origin.get_node("PlayerBody");host.player.set_physics_process(false)
	host.datapad=preload("res://scripts/xr_datapad.gd").new();host.add_child(host.datapad);host.datapad.configure(host.xr_origin,host.player);host.datapad.set_process(false)
	var bag=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);bag.configure(host.xr_origin,host.player);bag.allowed=true;bag.set_process(false)
	var housing=preload("res://housing/controller.gd").new();host.add_child(housing);housing.setup(host,bag);housing.set_process(false);housing.allowed=true
	var panel:Node3D=housing.harvester_panel;panel.set_process(false)
	var deed:Dictionary={"id":"100","template":"object/tangible/deed/harvester_deed/harvester_ore_s1_deed.iff","structure_template":"object/installation/mining_ore/mining_ore_harvester_style_1.iff","name":"Mineral harvester","type":"harvesting_deed","category":"data","deletable":false}
	host.inventory_snapshot={"source_kind":"core3_inventory","character_id":"42","items":[deed]}
	housing.state={"deeds":[deed]};host.datapad.ui.set_harvesting_deeds([deed]);host.datapad.ui.set_entries([])
	check(host.datapad.ui.entries.any(func(row):return row.id=="100"),"Owned harvester deed survives unrelated datapad refresh")
	housing.draw_harvester(deed,Transform3D.IDENTITY)
	check(bag.held_item.get("id")=="100" and is_instance_valid(housing.preview),"Datapad deed draws original harvester placement hologram")
	check(not housing.preview.get_meta("hologram_valid",true),"Unchecked harvester placement begins red")
	var before:=host.calls.size();housing.try_drop(deed,Transform3D.IDENTITY)
	check(host.calls.size()==before and bag.held_item.is_empty() and housing.deed.is_empty(),"Releasing preview cancels without consumption")
	var row:Dictionary={"id":"400","template":deed.structure_template,"position":[0,0,0],"quaternion":[0,0,0,1],"harvester":true,"admin":true,"owner_id":"42"}
	housing.scenery.apply({"structures":[row],"items":[]})
	check(housing.scenery.structures.has("400"),"Deployed original harvester has stage geometry")
	var structure:Node3D=housing.scenery.structures.get("400")
	if structure!=null:
		var bodies:Array=structure.find_children("*","StaticBody3D",true,false)
		check(not bodies.is_empty() and housing.scenery.structure_from_collider(bodies[0])=="400","World click collision resolves the correct harvester")
		var meshes:Array=structure.find_children("*","MeshInstance3D",true,false)
		var mesh:MeshInstance3D=meshes[0];check(housing.scenery.touches_structure("400",mesh.to_global(mesh.mesh.get_aabb().get_center())),"Both-hand recovery uses original model bounds")
	var detail:Dictionary={"id":"400","active":false,"cash":500,"maintenance":200,"power":10,"power_rate":25,"maintenance_rate":30,"rate":6,"hopper_size":120,"hopper_capacity":10000,"resources":[{"id":"500","name":"Ore","type":"iron","density":.6}],"output":[{"id":"700","resource_id":"500","template":"object/resource_container/inorganic_minerals.iff","name":"Ore","quantity":120}]}
	host.reply={"ok":true,"source_kind":"core3_services","character_id":"42","state":{"character_id":"42","housing":{"structures":[row],"items":[],"deeds":[deed]},"inventory":host.inventory_snapshot},"mutation":{"success":true,"harvester":detail}}
	panel.open_structure(row);await process_frame;await process_frame
	check(panel.is_open and panel.ui.rows.size()==1 and panel.output.rows.size()==1,"Click opens native resource list and output grid")
	check(panel.outputs.get_child_count()>0,"Output grid renders original resource model")
	check(panel.surfaces[1].mesh.position.x<0 and panel.surfaces[2].mesh.position.x>0,"Energy and maintenance are left; output is right")
	check(panel.slider.max_value==500 and panel.power_slot.visible,"Maintenance slider limited by native cash and energy slot visible")
	panel.select_resource(0);await process_frame;await process_frame
	check(host.calls[-1].path=="/services/house_harvester_select" and host.calls[-1].payload.resource_id=="500","Selecting resource requests native selection")
	panel.slider.value=123;panel.pay_maintenance();await process_frame;await process_frame
	check(host.calls[-1].payload.amount==123,"Maintenance deposit uses selected slider amount")
	panel.collect_output(0);await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("harvester_collect") and host.calls[-1].payload.quantity==120,"Output withdrawal preserves native resource and quantity")
	var energy:Dictionary={"id":"600","template":"object/resource_container/energy_solid.iff","name":"Energy"};bag.take_item(energy)
	check(panel.try_drop(energy,Transform3D(Basis.IDENTITY,panel.power_slot.global_position)),"Dropping an energy stack into slot uses harvester deposit")
	await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("harvester_power") and host.calls[-1].payload.item_id=="600" and bag.held_item.is_empty(),"Confirmed energy deposit clears held presentation")
	await housing.recover_harvester(row,Vector3.ZERO,Vector3(.1,0,0))
	check(host.calls[-1].path.ends_with("harvester_recover") and host.calls[-1].payload.has("left_hand") and host.calls[-1].payload.has("right_hand"),"Recovery sends both hands and native structure identity")
	host.reply={"ok":false,"error":"Timeout"};await housing.request("harvester_deposit",{"structure_id":"400","amount":42})
	var receipt:String=host.calls[-1].payload.request_id
	await housing.request("harvester_deposit",{"structure_id":"400","amount":42})
	check(host.calls[-1].payload.request_id==receipt,"Unknown deposit outcome retries with the same native receipt")
	var count:int=host.calls.size();panel.close();panel.select_resource(0);await process_frame
	check(not panel.is_open and host.calls.size()==count,"Closed panel cannot launch stale selection")
	housing.reset();check(host.datapad.ui.harvesting_deeds.is_empty(),"Character reset removes virtual deed entries")
	host.free();var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"native_execution":false,"tracking":"mocked","renderer":"headless dummy"}
	FileAccess.open("res://../runtime/evidence/harvesters-client.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
