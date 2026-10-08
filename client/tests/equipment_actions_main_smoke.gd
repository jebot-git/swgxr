extends SceneTree
## Mutation failure/lifecycle tests with explicit mocked responses; no server claims.
class Harness extends "res://scripts/main.gd":
	var reply: Dictionary={}
	var calls: Array=[]
	var refreshed_stats:=0
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func api(method: HTTPClient.Method,path: String,payload: Dictionary={}) -> Dictionary:
		calls.append({"method":method,"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return reply.duplicate(true)
	func sync_inventory_equipment(force_statistics := false) -> void:
		if force_statistics: refreshed_stats+=1
class Player extends CharacterBody3D:
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
var checks:=0
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app:=Harness.new(); root.add_child(app)
	var origin:=XROrigin3D.new(); app.add_child(origin)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; origin.add_child(head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; origin.add_child(hand)
	app.player=Player.new(); origin.add_child(app.player)
	app.inventory=load("res://scripts/xr_inventory.gd").new(); app.add_child(app.inventory); app.inventory.configure(origin,app.player); app.inventory.set_process(false); app.inventory.set_allowed(true)
	app.inventory.item_held_changed.connect(app.inventory_held_changed)
	app.datapad_character_id="fixture"; app.datapad_account="fixture"; app.world_ready=true
	var item: Dictionary={"id":"item","template":"object/tangible/food/foraged/foraged_fruit_s1.iff","container_id":"bag","name":"Charge test","use_count":2,"quantity":1,"consumable":true,"consume_available":true}
	var snapshot: Dictionary={"source_kind":"core3_inventory","backend":"core3","character_id":"fixture","inventory":{"id":"bag","capacity":80,"occupied":1},"items":[item],"equipment":[]}
	app.inventory_snapshot=snapshot.duplicate(true); app.update_inventory_presentation(); app.inventory.take_item(item)
	check(not app.inventory.held_item.is_empty(),"Original source item held for action test")
	app.reply={"ok":false,"error":"No free inventory slot"}
	await app.equip_inventory_item(item,0)
	check(app.inventory.held_item.get("id","")=="item" and not app.inventory.action_pending,"Equip rejection retains held item and unlocks input")
	check(app.inventory.ui.status=="No free inventory slot" and app.inventory_snapshot==snapshot,"Rejected equip displays native reason and leaves snapshot unchanged")
	var after:=snapshot.duplicate(true); after.items[0].use_count=1
	app.reply={"ok":true,"source_kind":"core3_inventory_consume","mutation":{"success":true},"inventory":after}
	await app.consume_inventory_item(item)
	check(app.inventory.held_item.use_count==1 and app.inventory_snapshot.items[0].use_count==1,"Successful consume keeps authoritative remaining charge in hand")
	check(app.refreshed_stats==1 and not app.inventory.held_trigger_armed,"Successful consume refreshes equipment bonuses and requires a fresh trigger")
	app.reply={"ok":false,"error":"Treatment cooldown"}
	await app.consume_inventory_item(app.inventory.held_item)
	check(app.inventory.held_item.use_count==1 and app.inventory_snapshot.items[0].use_count==1,"Rejected consume never decrements local charge")
	check(app.inventory.ui.status=="Treatment cooldown","Native consumption rejection is presented")
	app.reply={"ok":true,"source_kind":"core3_inventory_consume","mutation":{"success":true},"inventory":{"character_id":"another_character","items":[]}}
	await app.consume_inventory_item(app.inventory.held_item)
	check(app.inventory.held_item.use_count==1,"Mismatched character response never clears held item")
	app.reply={"ok":true,"source_kind":"core3_inventory_consume","mutation":{"success":false},"inventory":after}
	await app.consume_inventory_item(app.inventory.held_item)
	check(app.inventory.held_item.use_count==1,"HTTP200 without committed mutation is rejected")
	var calls_before:=app.calls.size()
	app.inventory_request_pending=true
	await app.consume_inventory_item(app.inventory.held_item)
	check(app.calls.size()==calls_before and app.inventory.action_pending,"Concurrent request stays locked without a second mutation")
	app.inventory_request_pending=false; app.inventory.set_busy(false)
	after.items=[]; after.inventory.occupied=0
	app.reply={"ok":true,"source_kind":"core3_inventory_consume","mutation":{"success":true},"inventory":after}
	await app.consume_inventory_item(app.inventory.held_item)
	check(app.inventory.held_item.is_empty() and not app.inventory_request_pending,"Final authoritative charge removal clears the hand")
	check(app.calls.filter(func(call):return call.method==HTTPClient.METHOD_POST).size()==6,"Failures never automatically retry mutations")
	check(app.calls.filter(func(call):return call.method==HTTPClient.METHOD_POST).all(func(call):return call.payload.item_id=="item"),"Actions carry original item ID to the mutation endpoint")
	app.inventory_snapshot=snapshot.duplicate(true); app.update_inventory_presentation(); app.inventory.take_item(item)
	var equipped:=snapshot.duplicate(true); equipped.items[0].equipped=true; equipped.items[0].container_id="fixture"; equipped.equipment=[equipped.items[0]]; equipped.inventory.occupied=0
	app.reply={"ok":true,"source_kind":"core3_inventory_equip","mutation":{"success":true},"inventory":equipped}
	await app.equip_inventory_item(item,1)
	check(app.inventory.held_item.is_empty() and app.inventory_snapshot.equipment.size()==1,"Confirmed equip clears hand and adopts authoritative current equipment")
	check(app.calls[-1].payload.arrangement==1,"Selected original arrangement reaches Core3 unchanged")
	app.combat_rig=load("res://combat/ranged_rig.gd").new(); app.add_child(app.combat_rig)
	app.combat_rig.abilities.character_id="fixture"
	app.combat_rig.abilities.ham=[80.0,100.0,100.0,100.0,100.0,100.0,70.0,100.0,100.0]
	var mutation: Dictionary={"success":true,"before_stats":{"source_kind":"core3_player_stats","ham":[100,100,100,100,100,100,100,100,100]},"after_stats":{"source_kind":"core3_player_stats","ham":[125,100,100,100,100,100,80,100,100],"max_ham":[130,100,100,100,100,100,100,100,100]}}
	app.apply_inventory_stat_delta(mutation)
	check(app.combat_rig.abilities.ham[0]==105 and app.combat_rig.abilities.ham[6]==50,"Confirmed native benefit and mind cost apply to local prediction without refilling previous expenditure")
	var saved: Array=app.combat_rig.abilities.ham.duplicate()
	mutation.success=false; app.apply_inventory_stat_delta(mutation)
	check(app.combat_rig.abilities.ham==saved,"Rejected native action cannot heal predicted pools")
	mutation.success=true; mutation.after_stats.ham[0]=NAN; app.apply_inventory_stat_delta(mutation)
	check(app.combat_rig.abilities.ham==saved,"Malformed benefit rejected atomically")
	# Use the real bag's equipped view and grip request; no item is transferred
	# into a local hand before the native equipment mutation confirms it.
	var instrument:Dictionary={"id":"horn","name":"Slitherhorn","template":"object/tangible/instrument/slitherhorn.iff","container_id":"fixture","equipped":true,"equipped_slots":["hold_r"],"unequip_available":true}
	var worn:Dictionary=snapshot.duplicate(true);worn.items=[instrument];worn.equipment=[instrument]
	app.inventory_snapshot=worn;app.update_inventory_presentation();app.inventory.ui.container_id="@equipment";app.inventory.ui.set_snapshot(worn);app.inventory.ui.select_item(instrument)
	check(app.inventory.ui.items.size()==1 and app.inventory.ui.unequip_button.visible and not app.inventory.ui.unequip_button.disabled,"Equipped instrument is reachable in VR bag with enabled return action")
	app.inventory.unequip_requested.connect(app.unequip_inventory_item)
	app.reply={"ok":false,"error":"Inventory full"};app.inventory.take_item(instrument,"left")
	check(app.inventory.held_item.is_empty() and app.inventory.action_pending,"Equipped grip waits for native removal rather than fabricating a held instrument")
	await process_frame;await process_frame;await process_frame
	check(app.inventory.held_item.is_empty() and app.inventory_snapshot.equipment.size()==1 and not app.inventory_request_pending,"Failed removal preserves native equipment and allows retry")
	var returned:Dictionary=worn.duplicate(true);returned.equipment=[];returned.items[0].equipped=false;returned.items[0].equipped_slots=[];returned.items[0].container_id="bag"
	app.reply={"ok":true,"source_kind":"core3_inventory_unequip","mutation":{"success":true},"inventory":returned}
	app.inventory.take_item(instrument,"left");await process_frame;await process_frame
	check(app.inventory.held_item.get("id","")=="horn" and app.inventory.held_hand_side()=="left" and app.inventory_snapshot.equipment.is_empty(),"Confirmed removal returns original instrument to requesting tracked hand")
	check(app.calls.filter(func(call):return call.path=="/inventory/unequip").size()==2,"One explicit attempt per grip; rejected removal is never automatically repeated")
	var report: Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"server_mocked":true,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/equipment-actions-main-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); app.queue_free(); await process_frame; quit(0 if errors.is_empty() else 1)
