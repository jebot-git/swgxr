extends SceneTree
## Explicit disposable Core3 fixture: real equip/consume; original avatar; dummy renderer.
class Harness extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
class Player extends CharacterBody3D:
	var camera: Camera3D
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
	func get_camera() -> Camera3D: return camera
var checks:=0
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Equipment main HTTP timeout"); quit(2))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/equipment-fixture.json"))
	if fixture.is_empty(): push_error("Disposable equipment fixture required"); quit(2); return
	var app:=Harness.new(); root.add_child(app)
	var origin:=XROrigin3D.new(); app.add_child(origin)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; origin.add_child(head); head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; origin.add_child(hand)
	app.player=Player.new(); origin.add_child(app.player); app.player.camera=head
	app.inventory=load("res://scripts/xr_inventory.gd").new(); app.add_child(app.inventory); app.inventory.configure(origin,app.player); app.inventory.set_process(false)
	app.inventory.item_held_changed.connect(app.inventory_held_changed)
	app.inventory.equip_requested.connect(app.equip_inventory_item)
	app.inventory.consume_requested.connect(app.consume_inventory_item)
	app.datapad_account=fixture.account; app.datapad_character_id=fixture.id; app.world_ready=true
	var character: Dictionary=await app.api(HTTPClient.METHOD_GET,"/characters/"+fixture.id+"?account="+fixture.account.uri_encode())
	check(character.get("ok",false),"Read real disposable character appearance")
	var appearance: Dictionary=character.get("character",{}).get("appearance",{})
	app.avatar=load("res://scripts/avatar.gd").new(); app.add_child(app.avatar)
	check(app.avatar.configure("human_male",appearance,appearance.get("equipment",[])).error=="","Original fixture avatar configured")
	app.avatar.set_tracking_mode(true)
	var skeleton_id: int=app.avatar.skeleton.get_instance_id()
	var tracked_pose:=Transform3D(Basis(Vector3.UP,0.08),Vector3(0.01,0.01,0))
	app.avatar.skeleton.set_bone_pose(0,tracked_pose)
	await app.refresh_inventory(); app.inventory.set_allowed(true)
	check(app.inventory_snapshot.get("source_kind","")=="core3_inventory" and app.inventory_snapshot.has("equipment"),"Core3 full equipment metadata reached client")
	check(app.avatar.report.get("equipment_complete",false),"All original currently equipped appearances resolved")
	var shirt: Dictionary={}
	for item: Dictionary in app.inventory_snapshot.get("items",[]):
		if not item.get("equipped",false) and str(item.template).contains("/shirt/") and item.get("equip_available",false): shirt=item; break
	check(not shirt.is_empty(),"Disposable unequipped original shirt available")
	if not shirt.is_empty():
		var arrangement: Dictionary=shirt.equip_arrangements[0]
		var old_ids: Array=arrangement.displaced_item_ids.duplicate()
		app.inventory.take_item(shirt)
		app.inventory.update_held_trigger(0,head.global_transform); app.inventory.update_held_trigger(0.9,head.global_transform)
		check(app.inventory.hologram.active and app.inventory.blocks_combat(),"Fresh trigger displays local equipment hologram and reserves combat input")
		var slot: String=arrangement.slots[0]
		check(app.inventory.hologram.markers.has(slot),"Actual Core3 arrangement has original skeleton anchor")
		if app.inventory.hologram.markers.has(slot):
			var pose: Transform3D=app.inventory.hologram.markers[slot].global_transform
			app.inventory.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0.9,{},pose)
			app.inventory.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},pose)
			while app.inventory_request_pending: await create_timer(0.02).timeout
		check(app.inventory.held_item.is_empty() and not app.inventory.hologram.active,"Release onto compatible slot finishes confirmed equip")
		check(app.inventory_snapshot.equipment.any(func(row):return str(row.id)==str(shirt.id)),"Server-confirmed shirt appears in current equipment")
		for id in old_ids:
			var previous: Dictionary=app.owned_inventory_item(str(id))
			check(not previous.is_empty() and not previous.equipped and previous.container_id==app.inventory_snapshot.inventory.id,"Displaced original equipment returns to root inventory")
		check(app.avatar.report.get("equipment_complete",false) and app.avatar.skeleton.get_instance_id()==skeleton_id and app.avatar.skeleton.get_bone_pose(0).is_equal_approx(tracked_pose),"Live equip preserves tracked skeleton/pose and displays original gear")
		await app.refresh_inventory()
		check(app.inventory_snapshot.equipment.any(func(row):return str(row.id)==str(shirt.id)),"Equipment survives separate authenticated login")
	var consumable: Dictionary={}
	for item: Dictionary in app.inventory_snapshot.get("items",[]):
		if item.get("consumable",false) and item.get("consume_available",false) and item.get("consume_kind","")=="food" and (not fixture.has("consumption_test_item_id") or str(item.id)==str(fixture.consumption_test_item_id)): consumable=item; break
	check(not consumable.is_empty(),"Disposable food available for real consume")
	if not consumable.is_empty():
		app.inventory.take_item(consumable)
		app.inventory.update_held_trigger(0,head.global_transform); app.inventory.update_held_trigger(0.9,head.global_transform)
		while app.inventory_request_pending: await create_timer(0.02).timeout
		var remaining: Dictionary=app.owned_inventory_item(str(consumable.id))
		var used: bool=remaining.is_empty() or int(remaining.get("use_count",0))==int(consumable.get("use_count",0))-1
		check(used,"Fresh trigger invokes original Core3 consumption for exactly one unit/charge")
		check(app.inventory.held_item.is_empty() if remaining.is_empty() else app.inventory.held_item.get("use_count",-1)==remaining.use_count,"Held appearance reconciles consumed object/charge")
		await app.refresh_inventory()
		check(app.owned_inventory_item(str(consumable.id))==remaining,"Consumption survives separate authenticated login")
	var report: Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"real_core3_http":true,"disposable_fixture":fixture.id,"renderer":"dummy","hardware_tested":false,"equipped_item":shirt.get("id",""),"consumed_item":consumable.get("id","")}
	FileAccess.open("res://../runtime/evidence/equipment-main-http-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); app.inventory.cancel_interaction(); app.queue_free(); await process_frame; quit(0 if errors.is_empty() else 1)
