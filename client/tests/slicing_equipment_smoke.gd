extends SceneTree
## Real main/rig refresh paths with mocked HTTP and original source geometry.
class Harness extends "res://scripts/main.gd":
	var reply:Dictionary={}
	var calls:=0
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func api(_method:HTTPClient.Method,_path:String,_payload:Dictionary={})->Dictionary:
		calls+=1;await get_tree().process_frame;return reply.duplicate(true)
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	var profile:Dictionary=fixture.weapons.pistol_cdef.duplicate(true)
	profile.source_kind="core3_weapon_instance";profile.item_id="202";profile.certified=true
	var app:=Harness.new();root.add_child(app);app.datapad_character_id="500";app.datapad_account="fixture"
	app.player=CharacterBody3D.new();app.add_child(app.player)
	var head:=Camera3D.new();app.player.add_child(head);head.position.y=1.7
	app.combat_rig=preload("res://combat/ranged_rig.gd").new();app.add_child(app.combat_rig)
	check(app.combat_rig.configure(head,app.player,[]),"Original combat rig initializes without synthetic equipment")
	app.combat_rig.set_process(false);app.combat_rig.set_physics_process(false)
	app.inventory_snapshot={"equipment":[{"id":"202","template":profile.template,"equipped_slots":["hold_r"]}]}
	app.reply={"ok":true,"backend":"core3","weapons":[profile],"player_combat":fixture.player_combat}
	await app.sync_inventory_equipment(true)
	check(app.combat_rig.weapons.size()==1,"Main equipment refresh installs owner profile into actual weapon state")
	var state=app.combat_rig.weapons[0].state
	state.rounds=1;state.next_shot=state.clock+.5
	var sliced:=profile.duplicate(true);sliced.capacity+=7;sliced.rpm*=1.2;sliced.core3.minDamage*=1.25;sliced.core3.maxDamage*=1.25
	sliced.profession.rpm_scale=1.4
	app.reply.weapons=[sliced]
	var count:=app.calls;await app.sync_inventory_equipment(true)
	check(app.calls==count+1 and app.combat_rig.weapons[0].state==state,"Forced completion/equip refresh reloads same item ID and reuses actual combat state")
	check(state.profile.capacity==sliced.capacity and is_equal_approx(state.core.minDamage,sliced.core3.minDamage) and is_equal_approx(state.effective_rpm(),sliced.rpm*1.4),"Sliced capacity, damage and wearable profession speed reach runtime combat calculations")
	check(state.rounds==1 and state.next_shot>state.clock,"Stat refresh preserves spent ammunition and pending shot cooldown")
	# Unequipped sliced item cannot gain a holster; later native equip refreshes it.
	app.inventory_snapshot.equipment=[];await app.sync_inventory_equipment(true)
	check(app.combat_rig.weapons[0].inventory_only,"Inventory-only sliced target stays unavailable for combat")
	app.inventory_snapshot.equipment=[{"id":"202","template":profile.template}];await app.sync_inventory_equipment(true)
	check(not app.combat_rig.weapons[0].inventory_only and state.profile.capacity==sliced.capacity,"Later equip restores sliced owner profile even for a previously cached item ID")
	var native_path:="res://../runtime/evidence/slicing-native-envelope.json"
	if FileAccess.file_exists(native_path):
		var native:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(native_path))
		var native_board=preload("res://slicing/board.gd").new()
		check(native.begin.source_kind=="core3_services" and native_board.configure(native.begin.state.slicing.challenge),"Actual native generated challenge parses through client board validator")
		for pair:Dictionary in native_board.pairs:
			for endpoint:Dictionary in pair.ends:
				var point:Vector3=native_board.endpoint_position(endpoint)
				check(is_equal_approx(point.dot(Vector3(native_board.cell(endpoint.face))),native_board.size*native_board.cell_size*.5),"Actual native endpoint face maps to the correct outside cube wall")
		var observer=preload("res://slicing/controller.gd").new();app.add_child(observer);observer.app=app;observer.allowed=true
		observer.grid=preload("res://slicing/grid_view.gd").new();observer.add_child(observer.grid)
		app.services=preload("res://scripts/services_controller.gd").new();app.add_child(app.services);app.services.app=app
		app.datapad_character_id=str(native.begin.character_id)
		observer.observe(native.begin)
		check(observer.active() and observer.grid.visible,"Native begin envelope opens controller using authoritative challenge")
		observer.observe(native.complete)
		check(not observer.active() and observer.error=="Slice complete","Native succeeded envelope clears puzzle through normal observer")
		# Exercise the service-to-slicing hook after inventory adoption, with a
		# mocked equipment completion layered on the verified native envelope.
		app.slicing=observer;var completion:Dictionary=native.complete.duplicate(true)
		completion.state.slicing.target_kind="item"
		completion.state.inventory={"source_kind":"core3_inventory","character_id":app.datapad_character_id,"equipment":[{"id":"202","template":profile.template}],"items":[]}
		count=app.calls
		check(app.services.accept_response(completion,false),"Current native service envelope accepts owned completion inventory")
		await process_frame;await process_frame
		check(app.calls==count+1 and not app.combat_rig.weapons[0].inventory_only and state.profile.capacity==sliced.capacity,"Service completion refresh hook consumes newly adopted inventory before forcing actual weapon profiles")
		app.services.accept_response(completion,false);await process_frame
		check(app.calls==count+1,"Repeated completion snapshot does not repeatedly fetch combat profiles")
	app.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"transport":"mocked; native envelope replay when available","renderer":"dummy","headset_validated":false}));quit(0 if errors.is_empty() else 1)
