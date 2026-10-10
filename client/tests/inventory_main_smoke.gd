extends SceneTree
## Real Core3 HTTP + actual bag/drop/weapon orchestration; dummy, mocked XR poses.
class Harness extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
class Player extends CharacterBody3D:
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
const Inventory=preload("res://scripts/xr_inventory.gd")
const Drops=preload("res://scripts/local_inventory_drops.gd")
const Combat=preload("res://combat/ranged_rig.gd")
var checks:=0
var errors: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: errors.append(message); push_error(message)
func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Inventory main HTTP test timed out"); quit(2))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/unarmed-fixture.json"))
	if fixture.is_empty():
		push_error("Missing real CoreCU fixture"); quit(2); return
	var app:=Harness.new(); root.add_child(app)
	app.xr_origin=XROrigin3D.new(); app.add_child(app.xr_origin)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; app.xr_origin.add_child(head); head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; app.xr_origin.add_child(hand)
	app.player=Player.new(); app.xr_origin.add_child(app.player)
	app.inventory=Inventory.new(); app.add_child(app.inventory); app.inventory.configure(app.xr_origin,app.player); app.inventory.set_process(false)
	app.inventory_drops=Drops.new(); app.add_child(app.inventory_drops); app.inventory_drops.configure(app.inventory.assets)
	app.inventory.item_take_requested.connect(app.take_inventory_item)
	app.inventory.item_held_changed.connect(app.inventory_held_changed)
	app.inventory.item_drop_requested.connect(app.drop_inventory_item)
	app.inventory.opened.connect(func():
		if is_instance_valid(app.combat_rig): app.combat_rig.stop_inventory_item())
	app.datapad_account=fixture.account; app.datapad_character_id=fixture.id
	app.world_ready=true; app.inventory.set_allowed(true)
	await app.refresh_inventory()
	check(app.inventory_snapshot.get("source_kind","")=="core3_inventory" and not app.inventory_snapshot.get("items",[]).is_empty(),"Real CoreCU read populated main inventory")
	check(not app.inventory_request_pending and not app.inventory.action_pending,"Successful HTTP read clears both pending gates")
	if app.inventory_snapshot.get("items",[]).is_empty(): app.queue_free(); await process_frame; quit(1); return
	var baseline: Dictionary=app.inventory_snapshot.duplicate(true)
	var item: Dictionary=baseline.items[0]
	app.inventory.set_open(true); app.inventory.take_item(item)
	check(app.inventory.held_item.id==item.id and app.inventory.ui.detail_item.get("local_state","")=="held","Held item updates source slot and selected detail atomically")
	check(app.inventory_snapshot==baseline,"Held item presentation leaves authoritative snapshot unchanged")
	app.inventory.clear_held()
	check(app.inventory.held_item.is_empty() and not app.inventory.ui.detail_item.has("local_state"),"Bag return releases local reservation")
	var result: Dictionary=await app.api(HTTPClient.METHOD_GET,"/weapons?account="+fixture.account.uri_encode()+"&character_id="+fixture.id.uri_encode())
	var profiles: Array=result.get("weapons",[])
	check(result.get("ok",false) and not profiles.is_empty(),"Fresh CoreCU owner-verified weapon profiles available")
	app.combat_rig=Combat.new(); app.add_child(app.combat_rig)
	check(app.combat_rig.configure(head,app.player,[]),"Combat rig accepts inventory-driven initialization without synthetic equipment")
	app.combat_rig.inventory=app.inventory; app.combat_rig.set_process(false); app.combat_rig.set_physics_process(false)
	var profile: Dictionary={}
	for entry: Dictionary in profiles:
		if str(entry.get("item_id",""))==str(item.id): profile=entry; break
	check(not profile.is_empty(),"Actual owned first item supports combat handoff")
	app.inventory.take_item(item); app.inventory.set_open(false)
	await app.ready_inventory_item(item)
	check(not app.inventory.external_use_active and app.inventory.held_model.visible and app.combat_rig.selected==-1,"Inventory-held weapon reserves trigger for equipment hologram")
	check(app.combat_rig.weapons.is_empty(),"Bag stow never grants combat equipment before a server equip")
	# Isolated render/control fixture for a confirmed equipment response; no server mutation.
	app.combat_rig.set_equipped_inventory_weapons([profile])
	check(app.combat_rig.weapons.size()==1 and app.combat_rig.weapons[0].state.profile.item_id==item.id,"Verified equipment fixture resolves original combat appearance")
	check(app.combat_rig.selected==-1 and not app.combat_rig.weapons[0].inventory_only,"Confirmed equipment is holstered, never drawn by UI action")
	app.combat_rig.set_equipped_inventory_weapons([profile])
	check(app.combat_rig.weapons.size()==1,"Repeated equipment refresh reuses combat instance")
	app.inventory.set_open(true)
	check(app.combat_rig.selected==-1 and not app.inventory.external_use_active and app.inventory.held_model.visible,"Reopening bag revokes combat and restores held model")
	app.inventory.set_open(false)
	var pose:=Transform3D(Basis.IDENTITY,Vector3(0.2,1.2,-0.4))
	app.drop_inventory_item(item,pose)
	check(app.inventory.held_item.is_empty() and app.inventory_drops.reserved_ids().has(str(item.id)),"Stowed release creates recoverable local drop and clears hand")
	check(app.inventory.ui.detail_item.get("local_state","")=="dropped" and app.combat_rig.inventory_reserved_ids.has(str(item.id)),"Dropped source remains reserved in bag and holster")
	check(app.inventory_snapshot.inventory==baseline.inventory,"Session-local drop never frees CoreCU inventory capacity")
	# Existing loadout entries must obey the same reservation, not only new bag entries.
	app.combat_rig.weapons[0].erase("inventory_only")
	app.combat_rig.set_allowed(true)
	var holster: Transform3D=app.combat_rig.holster_transform(int(profile.hands))
	app.combat_rig.sample(0.01,holster,Transform3D.IDENTITY,0,0,0,true,false)
	app.combat_rig.sample(0.01,holster,Transform3D.IDENTITY,0.9,0,0,true,false)
	check(app.combat_rig.selected==-1 and not app.combat_rig.weapons[0].visual.visible,"Reserved drop cannot also be drawn or rendered from existing holster")
	await app.split_inventory_stack(item,1)
	check(not app.inventory_request_pending and app.inventory.ui.status.contains("Recover"),"Main rejects splitting session-dropped source before any mutation")
	var candidate: Dictionary=app.inventory_pickup_candidate(pose)
	check(candidate.get("id","")==item.id and not candidate.has("local_state"),"Nearby recovery resolves current owned record")
	app.inventory.take_item(candidate)
	check(app.inventory_drops.reserved_ids().is_empty() and app.inventory.held_item.id==item.id,"Recovery consumes one proxy and retains one held instance")
	check(app.inventory.ui.detail_item.get("local_state","")=="held","Recovery updates reservation after proxy removal")
	app.inventory.set_allowed(false)
	check(app.inventory.held_item.is_empty() and app.combat_rig.inventory_reserved_ids.is_empty(),"Focus loss returns item safely without world drop")
	app.inventory.set_allowed(true)
	check(not app.combat_rig.begin_inventory_item({"id":"pistol_cdef","item_id":"fake"}),"Template-only unverified item rejected by weapon handoff")
	app.inventory.take_item(item); app.drop_inventory_item(item,pose)
	app.inventory_snapshot.items=app.inventory_snapshot.items.filter(func(row): return str(row.id)!=str(item.id))
	app.reconcile_inventory_presentations(); app.update_inventory_presentation()
	check(app.inventory_drops.reserved_ids().is_empty() and app.inventory_pickup_candidate(pose).is_empty(),"Lost ownership removes stale local drop")
	await app.refresh_inventory()
	check(app.inventory_snapshot==baseline,"Fresh CoreCU login confirms hold/drop/recover never mutated user ownership")
	app.backend_url="http://127.0.0.1:1"
	await app.refresh_inventory()
	check(not app.inventory_request_pending and not app.inventory.action_pending and not app.inventory.ui.status.is_empty(),"Read failure resolves pending state and shows server error")
	var report:={"passed":errors.is_empty(),"checks":checks,"errors":errors,"real_core3_http":true,"core3_items_unchanged":app.inventory_snapshot==baseline,"renderer":"dummy","hardware_tested":false,"fixture":fixture.id}
	FileAccess.open("res://../runtime/evidence/inventory-main-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	app.inventory.cancel_interaction(); app.combat_rig.inventory=null; app.queue_free(); await process_frame
	quit(0 if errors.is_empty() else 1)
