extends SceneTree
## Real disposable Core3 corpse rewards; source appearance, mocked hand poses.
var Host=load("res://tests/gathering_live_host.gd")
class Player extends CharacterBody3D:
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
var errors:Array[String]=[]
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func settle(app:Node) -> void:
	while app.inventory_request_pending or app.gathering.busy or app.corpse_gathering.busy: await create_timer(0.02).timeout
	await process_frame
func resource_total(snapshot:Dictionary,choice:Dictionary) -> int:
	var amount:=0
	for item:Dictionary in snapshot.get("items",[]):
		if str(item.get("template",""))!=str(choice.get("container_template","")): continue
		for attribute:Dictionary in item.get("attributes",[]):
			if attribute.get("name","")=="resource_name" and str(attribute.get("value",""))==str(choice.name): amount+=int(item.get("quantity",0)); break
	return amount
func run() -> void:
	create_timer(180).timeout.connect(func():push_error("Corpse main HTTP timeout");quit(2))
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/corpse-fixture.json"))
	if fixture.is_empty() or not str(fixture.account).begins_with("invtest"):push_error("Disposable fixture required");quit(2);return
	var app:Node=Host.new();root.add_child(app);app.datapad_account=fixture.account;app.datapad_character_id=fixture.id
	app.xr_origin=XROrigin3D.new();app.add_child(app.xr_origin)
	var head:=XRCamera3D.new();head.name="XRCamera3D";app.xr_origin.add_child(head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;app.xr_origin.add_child(hand)
	app.player=Player.new();app.add_child(app.player)
	app.stage=Node3D.new();app.stage.set_meta("manifest",{"origin":[3600,5,-4780]});app.add_child(app.stage)
	app.loader.report={"origin":[3600,5,-4780]};head.position=Vector3(0,1.7,0)
	app.inventory=load("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(app.xr_origin,app.player);app.inventory.set_process(false)
	app.gathering=load("res://scripts/resource_gathering.gd").new();app.add_child(app.gathering);app.gathering.configure(app,app.inventory);app.gathering.set_process(false)
	app.corpse_gathering=load("res://scripts/corpse_gathering_controller.gd").new();app.add_child(app.corpse_gathering);app.corpse_gathering.configure(app,app.inventory);app.corpse_gathering.set_process(false);app.corpse_gathering.ui.set_process(false)
	app.world_ready=true
	await app.refresh_inventory();app.inventory.set_allowed(true)
	var service:Node=app.corpse_gathering
	check(await service.refresh(),"Current real native corpse query succeeds")
	service.visuals.sync_visuals()
	var corpse:Dictionary={}
	for record:Dictionary in service.visuals.states.values():
		if record.get("harvest_available",false) and record.get("loot_available",false) and service.visuals.visuals.has(str(record.id)):
			corpse=record
	check(not corpse.is_empty(),"Fresh native harvestable and lootable source corpse fixture is visible")
	if not corpse.is_empty():
		# Earlier controlled fixtures may share exactly this source spawn point.
		# Isolate this native identity for deterministic hand hit selection.
		service.visuals.set_states([corpse]);service.visuals.sync_visuals()
		var visual:Dictionary=service.visuals.visuals[str(corpse.id)]
		var bounds:AABB=visual.node.global_transform*visual.bounds
		var point:=Vector3(bounds.get_center().x,bounds.end.y+0.18,bounds.get_center().z)
		var hand:=Transform3D(Basis.IDENTITY,point)
		service.set_allowed(true)
		service.ui.sample(true,true,hand,head.global_transform,0,0)
		service.ui.sample(true,true,hand,head.global_transform,0.9,0);await settle(app)
		check(str(service.ui.corpse.get("id",""))==str(corpse.id) and not service.ui.context.is_empty() and not service.ui.pending and service.ui.visible,"Fresh empty-hand trigger inspects actual corpse through HTTP")
		check(service.ui.choices.size()>0 and service.ui.choice_nodes.size()==service.ui.choices.size(),"Native organic choices displayed above original corpse")
		var choice:Dictionary={};var index:=-1
		for n in range(service.ui.choices.size()):
			if service.ui.choices[n].get("available",false):choice=service.ui.choices[n];index=n;break
		check(index>=0,"At least one source-native organic choice available")
		if index>=0:
			var before:=resource_total(app.inventory_snapshot,choice)
			var grab:=Transform3D(Basis.IDENTITY,service.ui.choice_nodes[index].global_position)
			service.ui.sample(true,true,grab,head.global_transform,0,0)
			service.ui.sample(true,true,grab,head.global_transform,0,0.9);await settle(app)
			var after:=resource_total(app.inventory_snapshot,choice)
			check(after-before==int(choice.quantity),"Fresh hologram grip grants exactly source native yield to real inventory")
			check(not service.ui.context.get("harvest_available",true) and not service.ui.pending,"Successful harvest marks native corpse and refreshes choices")
		var loot_ids:Array=[]
		for item:Dictionary in service.ui.context.get("loot",{}).get("items",[]):loot_ids.append(str(item.id))
		check(not loot_ids.is_empty(),"Native fixture includes loot items for second-trigger transfer")
		service.ui.sample(true,true,hand,head.global_transform,0,0)
		service.ui.sample(true,true,hand,head.global_transform,0.9,0);await settle(app)
		for id:String in loot_ids:check(not app.owned_inventory_item(id).is_empty(),"Second fresh corpse trigger transfers original loot item into inventory")
		check(not service.ui.context.get("loot_available",true) and int(service.ui.context.get("loot",{}).get("credits",-1))==0,"Second trigger confirms native credits/loot exhausted")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"real_core3_http":true,"fixture":fixture.id,"corpse_id":corpse.get("id",""),"renderer":"dummy","hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/corpse-main-http-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));app.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
