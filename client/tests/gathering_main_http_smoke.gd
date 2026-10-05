extends SceneTree
## Explicit disposable Core3 fixture; real stage floors + models, mocked gestures.
var Host=load("res://tests/gathering_live_host.gd")
const Stage=preload("res://scripts/cell_stage.gd")
const Loader=preload("res://scripts/stage_loader.gd")
class Player extends CharacterBody3D:
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
var errors:Array[String]=[]
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func wait_action(app:Node) -> void:
	while app.inventory_request_pending or app.gathering.busy or (is_instance_valid(app.corpse_gathering) and app.corpse_gathering.busy): await create_timer(0.02).timeout
	await process_frame
func vertex(values:Array,index:int) -> Vector3:
	return Vector3(values[index*3],values[index*3+1],values[index*3+2])
func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Gathering main HTTP timeout"); quit(2))
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/gathering-fixture.json"))
	if fixture.is_empty() or not str(fixture.account).begins_with("invtest"): push_error("Disposable gathering fixture required"); quit(2); return
	var app:Node=Host.new(); root.add_child(app)
	app.datapad_account=fixture.account; app.datapad_character_id=fixture.id
	app.xr_origin=XROrigin3D.new(); app.add_child(app.xr_origin)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; app.xr_origin.add_child(head); head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; app.xr_origin.add_child(hand)
	app.player=Player.new(); app.add_child(app.player)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/mos_eisley/scene.json"))
	app.stage=Stage.new(); app.stage.set_meta("manifest",manifest); app.stage.classifier.configure(manifest.cells); app.add_child(app.stage); app.stage.set_physics_process(false)
	app.loader=Loader.new(); app.loader.report={"origin":manifest.origin}
	var floors:=Node3D.new(); app.add_child(floors); app.loader.install_floors(floors,manifest.cells)
	app.inventory=load("res://scripts/xr_inventory.gd").new(); app.add_child(app.inventory); app.inventory.configure(app.xr_origin,app.player); app.inventory.set_process(false)
	app.inventory.item_held_changed.connect(app.inventory_held_changed)
	app.gathering=load("res://scripts/resource_gathering.gd").new(); app.add_child(app.gathering); app.gathering.configure(app,app.inventory); app.gathering.set_process(false)
	app.world_ready=true; app.gathering.world_tools.set_context(app.stage,app.player)
	await physics_frame; await physics_frame
	var center:=Vector3.ZERO; var found:=false
	for cell:Dictionary in manifest.cells.values():
		if not cell.get("is_exterior",false): continue
		var values:Array=cell.get("floor_vertices",[])
		for triangle:Dictionary in cell.get("floor_triangles",[]):
			if triangle.get("fallthrough",false) or float(triangle.normal[1])<0.999: continue
			var point:Vector3=(vertex(values,int(triangle.indices[0]))+vertex(values,int(triangle.indices[1]))+vertex(values,int(triangle.indices[2])))/3
			app.player.position=point
			var support:Dictionary=app.gathering.world_tools.ground_placement(Transform3D(Basis.IDENTITY,point+Vector3.UP*1.2))
			if support.get("valid",false): center=support.position; found=true; break
		if found: break
	check(found,"Original outdoor FLR supports chest-height tool deployment")
	if not found: app.queue_free(); quit(1); return
	app.player.position=center; head.position=center+Vector3.UP*1.7
	await app.refresh_inventory(); app.inventory.set_allowed(true)
	check(app.inventory_snapshot.get("source_kind","")=="core3_inventory","Real inventory snapshot received")
	var tool:Dictionary={}
	for item:Dictionary in app.inventory_snapshot.get("items",[]):
		if item.get("tool_kind","")=="survey": tool=item; break
	if tool.is_empty() and app.gathering.hip_item().get("tool_kind","")=="survey": tool=app.gathering.hip_item()
	check(not tool.is_empty(),"Disposable source survey tool available")
	if not tool.is_empty():
		app.inventory.take_item(tool); await wait_action(app)
		check(app.inventory.is_survey_held() and app.inventory.survey_ui.active,"Original held tool automatically opens survey UI")
		check(app.inventory.survey_ui.context.get("source_kind","")=="core3_gathering" and app.inventory.survey_ui.context.get("range_m",0)>0,"Current native range and resources reached held UI")
		app.inventory.update_held_trigger(0,head.global_transform); app.inventory.update_held_trigger(0.9,head.global_transform); await wait_action(app)
		var scan:Dictionary=app.inventory.survey_ui.result
		check(not scan.get("spots",[]).is_empty() and not app.inventory.action_pending,"Fresh held trigger receives native survey grid and unlocks input")
		var count:int=app.gathering.state.deployments.size()
		await app.gathering.deploy(app.inventory.held_item,Transform3D(Basis.IDENTITY,center+Vector3.UP*1.2))
		check(app.inventory.held_item.is_empty() and app.gathering.state.deployments.size()==count+1,"Native deployment removes inventory/held tool only after acknowledgement")
		app.gathering.world_tools.sync_visuals()
		var deployed:Dictionary={}
		for entry:Dictionary in app.gathering.state.deployments:
			if str(entry.tool_id)==str(tool.id): deployed=entry
		check(not deployed.is_empty(),"Canonical generation-qualified deployment returned")
		if not deployed.is_empty():
			var visual:Dictionary=app.gathering.world_tools.visuals.get(str(deployed.id),{})
			check(not visual.is_empty(),"Actual backend deployment renders original tool over actual FLR")
			if not visual.is_empty():
				var float_point:Vector3=visual.node.global_position
				check(float_point.distance_to(center+Vector3.UP*1.2)<0.015,"Native ground coordinates render tool at chest height")
				var candidate:Dictionary=app.inventory_pickup_candidate(Transform3D(Basis.IDENTITY,visual.node.to_global(visual.center)))
				check(candidate.get("gathering_deployment",{}).get("id","")==deployed.id,"Main pickup provider targets floating original model")
				await app.gathering.pickup(candidate); await wait_action(app)
				check(str(app.inventory.held_item.get("id",""))==str(tool.id) and app.gathering.state.deployments.size()==count,"Confirmed native collection restores source tool to the hand")
		app.inventory.clear_held()
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"real_core3_http":true,"fixture":fixture.id,"source_position":app.gathering.source_position(center),"renderer":"dummy","hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/gathering-main-http-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); app.inventory.cancel_interaction(); app.queue_free(); await process_frame; quit(0 if errors.is_empty() else 1)
