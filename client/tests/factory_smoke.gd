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
	var panel:Node3D=housing.factory_panel;panel.set_process(false);housing.harvester_panel.set_process(false)
	var deed:Dictionary={"id":"100","template":"object/tangible/deed/factory_deed/factory_clothing_deed.iff","structure_template":"object/installation/manufacture/clothing_factory.iff","name":"Equipment factory","type":"factory_deed","category":"data","deletable":false}
	var blueprint:Dictionary={"id":"101","template":"object/manufacture_schematic/generic_schematic.iff","name":"A source blueprint","type":"manufacturing_blueprint","category":"data","deletable":false}
	var resource:Dictionary={"id":"200","template":"object/resource_container/inorganic_minerals.iff","name":"Steel","quantity":100}
	var energy:Dictionary={"id":"201","template":"object/resource_container/energy_solid.iff","name":"Energy","quantity":100}
	host.inventory_snapshot={"source_kind":"core3_inventory","character_id":"42","items":[deed,resource,energy]}
	housing.state={"deeds":[deed],"blueprints":[blueprint]};host.datapad.ui.set_harvesting_deeds([deed]);host.datapad.ui.set_factory_blueprints([blueprint]);host.datapad.ui.set_entries([])
	check(host.datapad.ui.entries.any(func(row):return row.id=="100") and host.datapad.ui.entries.any(func(row):return row.id=="101"),"Factory deeds and native source blueprints survive unrelated datapad refresh")
	housing.draw_harvester(deed,Transform3D.IDENTITY)
	check(bag.held_item.get("id")=="100" and is_instance_valid(housing.preview),"Factory deed draws original placement hologram")
	check(not housing.preview.get_meta("hologram_valid",true),"Unchecked factory placement begins invalid")
	var before:=host.calls.size();housing.try_drop(deed,Transform3D.IDENTITY)
	check(host.calls.size()==before and bag.held_item.is_empty(),"Releasing deed cancels preview without consuming deed")
	var row:Dictionary={"id":"400","template":deed.structure_template,"position":[0,0,0],"quaternion":[0,0,0,1],"factory":true,"admin":true,"owner_id":"42"}
	var detail:Dictionary={"id":"400","active":false,"cash":500,"maintenance":200,"power":10,"power_rate":25,"maintenance_rate":30,"blueprint":{},"requirements":[{"name":"Steel","quantity":10}],"input":[resource],"output":[{"id":"700","template":"object/factory/factory_crate_clothing.iff","name":"Output crate","quantity":1}]}
	host.reply={"ok":true,"source_kind":"core3_services","character_id":"42","state":{"character_id":"42","housing":{"structures":[row],"items":[],"deeds":[deed],"blueprints":[blueprint]},"inventory":host.inventory_snapshot},"mutation":{"success":true,"factory":detail}}
	panel.open_structure(row);await process_frame;await process_frame
	check(panel.is_open and panel.ui.rows.size()==1 and panel.output.rows.size()==1,"Factory opens separate native input and output inventories")
	check(panel.surfaces[1].mesh.position.x<0 and panel.surfaces[2].mesh.position.x>0,"Upkeep and energy left, output right")
	check(panel.inputs.get_child_count()>0 and panel.outputs.get_child_count()>0,"Both inventories display original item geometry")
	check(panel.slider.max_value==500,"Upkeep slider is capped by native cash")
	host.datapad.set_open(true);housing.allowed=true;panel._process(.01)
	check(panel.is_open,"Factory stays available while choosing datapad source blueprint")
	housing.allowed=false;panel._process(.01)
	check(not panel.is_open,"Disabled factory closes even while source datapad is open")
	housing.allowed=true;panel.open_structure(row);await process_frame;await process_frame
	housing.draw_blueprint(blueprint,Transform3D.IDENTITY)
	check(not host.datapad.is_open and bag.held_item.get("id")=="101" and is_instance_valid(bag.held_model),"Datapad source blueprint draws labeled holographic record")
	check(panel.try_drop(blueprint,Transform3D(Basis.IDENTITY,panel.blueprint_slot.global_position)),"Source slot accepts blueprint drop")
	await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("factory_blueprint") and host.calls[-1].payload.item_id=="101" and bag.held_item.is_empty(),"Blueprint insertion uses native id and clears only confirmed held record")
	bag.take_item(resource);before=host.calls.size()
	panel.try_drop(resource,Transform3D(Basis.IDENTITY,panel.blueprint_slot.global_position));await process_frame
	check(host.calls.size()==before and bag.held_item.get("id")=="200","Source slot rejects ordinary ingredients without losing held item")
	panel.try_drop(resource,Transform3D(Basis.IDENTITY,panel.surfaces[0].mesh.global_position));await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("factory_input") and host.calls[-1].payload.item_id=="200" and bag.held_item.is_empty(),"Dropping ingredients sends whole native input object")
	panel.withdraw_input(0);await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("factory_withdraw") and host.calls[-1].payload.item_id=="200","Input withdrawal preserves object identity")
	panel.collect_output(0);await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("factory_collect") and host.calls[-1].payload.item_id=="700","Output collection uses separate native output identity")
	panel.slider.value=123;panel.pay_maintenance();await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("factory_deposit") and host.calls[-1].payload.amount==123,"Maintenance uses selected credit amount")
	bag.take_item(energy);panel.try_drop(energy,Transform3D(Basis.IDENTITY,panel.power_slot.global_position));await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("factory_power") and host.calls[-1].payload.item_id=="201" and bag.held_item.is_empty(),"Energy slot fuels via native whole stack")
	panel.operate("active",{"active":true});await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("factory_active") and host.calls[-1].payload.active,"Factory starts only through server operation")
	panel.operate("remove_blueprint");await process_frame;await process_frame
	check(host.calls[-1].path.ends_with("factory_remove_blueprint"),"Source removal requests return to datapad")
	await housing.recover_factory(row,Vector3.ZERO,Vector3(.1,0,0))
	check(host.calls[-1].path.ends_with("factory_recover") and host.calls[-1].payload.has("left_hand") and host.calls[-1].payload.has("right_hand"),"Factory recovery sends both tracked hand positions")
	panel.structure_id="400";panel.set_open(true);bag.take_item(resource);host.reply={"ok":false,"error":"Timeout"}
	panel.try_drop(resource,Transform3D(Basis.IDENTITY,panel.surfaces[0].mesh.global_position));await process_frame;await process_frame
	var receipt:String=host.calls[-1].payload.request_id
	check(bag.held_item.get("id")=="200","Unconfirmed input retains held presentation")
	panel.try_drop(resource,Transform3D(Basis.IDENTITY,panel.surfaces[0].mesh.global_position));await process_frame;await process_frame
	check(host.calls[-1].payload.request_id==receipt,"Unknown transfer retries with same native receipt")
	host.reply={"ok":true,"source_kind":"core3_services","character_id":"other","state":{"character_id":"other"},"mutation":{"success":true,"factory":detail}}
	panel.try_drop(resource,Transform3D(Basis.IDENTITY,panel.surfaces[0].mesh.global_position));await process_frame;await process_frame
	check(bag.held_item.get("id")=="200","Foreign character response cannot confirm a factory transfer")
	bag.clear_held();panel.latched_input=0;panel.latched_output=0;panel.latched_blueprint=true;before=host.calls.size();panel._process(.01)
	check(panel.latched_input==-1 and panel.latched_output==-1 and not panel.latched_blueprint and host.calls.size()==before,"Tracking loss clears pull gestures without operations")
	panel.close();before=host.calls.size();panel.withdraw_input(0);await process_frame
	check(host.calls.size()==before,"Closed factory cannot launch stale withdrawal")
	if "--capture" in OS.get_cmdline_user_args():
		panel.structure_id="400";panel.allowed=true;panel.set_open(true);detail.blueprint=blueprint;detail.active=true;panel.observe({"mutation":{"factory":detail}})
		bag.clear_held();bag.hide();housing.scenery.hide();host.datapad.hide()
		var camera:Camera3D=host.xr_origin.get_node("XRCamera3D");camera.current=true;camera.fov=65;camera.position+=Vector3(0,-.05,-.1)
		host.xr_origin.get_node("LeftHand").hide();host.xr_origin.get_node("RightHand").hide()
		var environment:=WorldEnvironment.new();host.add_child(environment);environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("07121c")
		root.size=Vector2i(1600,1000)
		for frame in range(12):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/factories-desktop-vulkan.png")
		print("Saved desktop Vulkan evidence; fixture backend, no headset validation")
	housing.reset();check(host.datapad.ui.factory_blueprints.is_empty() and host.datapad.ui.harvesting_deeds.is_empty(),"Character reset clears native factory datapad entries")
	host.free();var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"native_execution":false,"tracking":"mocked","renderer":"desktop Forward+ Vulkan" if "--capture" in OS.get_cmdline_user_args() else "headless dummy"}
	FileAccess.open("res://../runtime/evidence/factories-capture.json" if "--capture" in OS.get_cmdline_user_args() else "res://../runtime/evidence/factories-client.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
