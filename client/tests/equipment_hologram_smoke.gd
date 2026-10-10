extends SceneTree
const Avatar = preload("res://scripts/avatar.gd")
const Inventory = preload("res://scripts/xr_inventory.gd")
class Player extends CharacterBody3D:
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
var checks:=0
var errors: Array[String]=[]
var equips: Array=[]
var consumes: Array=[]
var drops: Array=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	var source:=Avatar.new(); world.add_child(source); var report: Dictionary=source.configure("human_male"); source.set_process(false); source.visible=false
	check(str(report.get("error","")).is_empty(),"Original current avatar is available")
	var rig:=XROrigin3D.new(); world.add_child(rig)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; rig.add_child(head); head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; rig.add_child(hand)
	var player:=Player.new(); rig.add_child(player)
	var bag:=Inventory.new(); world.add_child(bag); bag.configure(rig,player); bag.set_process(false); bag.set_allowed(true)
	bag.equip_requested.connect(func(item,index): equips.append({"item":item,"arrangement":index}))
	bag.consume_requested.connect(func(item): consumes.append(item))
	bag.item_drop_requested.connect(func(item,pose): drops.append({"item":item,"pose":pose}))
	var template: String="object/weapon/melee/knife/knife_stone.iff"
	var incoming: Dictionary={"id":"knife","template":template,"name":"Incoming stone knife","equippable":true,"equip_available":true,"equip_arrangements":[{"index":2,"slots":["hold_r"],"available":true,"displaced_item_ids":["old"]}],"attributes":[{"name":"damage","value":"100–150"}],"container_id":"inventory"}
	var current: Dictionary={"id":"old","name":"Current weapon","template":template,"equipped_slots":["hold_r"],"attributes":[{"name":"damage","value":"80–120"}]}
	bag.set_snapshot({"inventory":{"id":"inventory","capacity":80,"occupied":1},"items":[incoming]})
	bag.set_equipment_context(source,[current]); bag.take_item(incoming)
	bag.update_held_trigger(0.9,head.global_transform)
	check(not bag.hologram.active,"Trigger already held when picking up cannot activate")
	bag.update_held_trigger(0,head.global_transform); bag.update_held_trigger(0.9,head.global_transform)
	check(bag.hologram.active and bag.hologram.report.meshes==source.meshes.size(),"Fresh trigger creates frozen current-avatar hologram including equipment/head partitions")
	check(bag.hologram.skeleton!=source.skeleton and bag.hologram.skeleton.get_bone_count()==source.skeleton.get_bone_count(),"Hologram owns independent source skeleton pose")
	var cloned: MeshInstance3D=bag.hologram.skeleton.get_children().filter(func(n): return n is MeshInstance3D)[0]
	check(cloned.mesh==source.meshes[0].mesh and cloned.get_surface_override_material(0)!=source.meshes[0].get_active_material(0),"Hologram shares immutable mesh and owns its material overrides")
	check(cloned.layers==1 and bag.hologram.skeleton.process_mode==Node.PROCESS_MODE_DISABLED,"Full visible body is local and frozen, no tracking controller mutation")
	var slot: Node3D=bag.hologram.markers.hold_r
	var candidate: Dictionary=bag.hologram.update_hand(slot.global_position)
	check(candidate.index==2 and candidate.available,"Proximity chooses original source arrangement index")
	check("80–120" in bag.hologram.labels[0].text and "100–150" in bag.hologram.labels[1].text,"Two panels compare actual current/incoming examine fields")
	var many:=incoming.duplicate(true)
	for i in range(12): many.attributes.append({"name":"skill_bonus_%d"%i,"value":str(i+1)})
	many.equip_arrangements.insert(0,{"index":1,"slots":["hold_r"],"available":false,"block_reason":"Blocked","displaced_item_ids":[]})
	bag.hologram.show_item(many,head.global_transform)
	candidate=bag.hologram.update_hand(bag.hologram.markers.hold_r.global_position)
	check(candidate.index==2,"Overlapping source arrangements prefer available alternative over blocked first entry")
	bag.update_stick_capture(Vector2(0,-1),{},0.3)
	check(bag.hologram.page==1 and bag.stick_captured,"Main stick pages comparison while hologram is active")
	bag.hologram.scroll_page(20)
	check("Skill Bonus 11" in bag.hologram.labels[1].text and bag.hologram.comparison_rows.size()==13,"Late skill/bonus attributes remain reachable without omission")
	bag.update_stick_capture(Vector2.ZERO,{},0.01)
	check(not bag.stick_captured,"Neutral stick releases comparison capture")
	bag.hologram.show_item(incoming,head.global_transform); slot=bag.hologram.markers.hold_r; bag.hologram.update_hand(slot.global_position)
	for common_slot in ["utility_belt","chest1","chest2","chest3_l","chest3_r","back","ring_l","ring_r","earring_l","earring_r","gloves","shoes","hat","eyes","mouth","neck","hair","cloak"]:
		check(bag.hologram.slot_anchor(common_slot) is Vector3,"Original humanoid slot anchor available: "+common_slot)
	check(bag.hologram.slot_anchor("hold_transport")==null,"Nonhuman arrangement remains explicitly unsupported")
	var stable_pose: Transform3D=bag.hologram.global_transform
	var before_clone: Node3D=bag.hologram.frozen
	bag.set_equipment_context(source,[current])
	check(bag.hologram.frozen==before_clone,"Unchanged equipment context avoids rebuilding active frozen avatar")
	var refreshed:=incoming.duplicate(true); refreshed.equip_arrangements[0].available=false; refreshed.equip_arrangements[0].block_reason="Capacity changed"
	bag.held_item=refreshed; bag.set_equipment_context(source,[current])
	check(bag.hologram.global_transform.is_equal_approx(stable_pose) and not bag.hologram.incoming.equip_arrangements[0].available,"Fresh server metadata updates active hologram without moving it")
	var refreshed_candidate: Dictionary=bag.hologram.update_hand(bag.hologram.markers.hold_r.global_position)
	check(not refreshed_candidate.available and "Capacity changed" in bag.hologram.labels[1].text,"Post-refresh proximity uses new eligibility and visible rejection reason")
	bag.held_item=incoming.duplicate(true); bag.set_equipment_context(source,[current]); slot=bag.hologram.markers.hold_r; bag.hologram.update_hand(slot.global_position)
	bag.set_external_use_active(true)
	check(not bag.external_use_active and bag.blocks_combat(),"Canonical held equippable reserves trigger even if old weapon delegation is requested")
	var source_transform:=source.skeleton.transform
	bag.update_gestures(true,head.global_transform,Transform3D(Basis.IDENTITY,Vector3(-1,1,-1)),0,0.9,{},Transform3D(Basis.IDENTITY,slot.global_position))
	bag.update_gestures(true,head.global_transform,Transform3D(Basis.IDENTITY,Vector3(-1,1,-1)),0,0,{},Transform3D(Basis.IDENTITY,slot.global_position))
	check(equips.size()==1 and equips[0].arrangement==2 and bag.action_pending and drops.is_empty(),"Grip release over slot requests equip before world drop")
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},Transform3D(Basis.IDENTITY,slot.global_position))
	check(equips.size()==1,"Pending equip never repeats while grip remains released")
	bag.finish_equipment_action(false)
	check(not bag.held_item.is_empty() and bag.hologram.active,"Server rejection keeps held item and hologram")
	bag.finish_equipment_action(true)
	check(bag.held_item.is_empty() and not bag.hologram.active,"Confirmed equip clears temporary item and hologram")
	var blocked:=incoming.duplicate(true); blocked.equip_arrangements[0].available=false; blocked.equip_arrangements[0].block_reason="Inventory is full"
	bag.take_item(blocked); bag.show_equipment_hologram(head.global_transform); slot=bag.hologram.markers.hold_r
	bag.main_grip_armed=false
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},Transform3D(Basis.IDENTITY,slot.global_position))
	check(equips.size()==1 and drops.is_empty() and not bag.held_item.is_empty() and bag.ui.status=="Inventory is full","Capacity-blocked release retains item without equip/drop request")
	bag.cancel_interaction()
	var consumable: Dictionary={"id":"food","template":"object/tangible/food/foraged/foraged_fruit_s1.iff","name":"Fruit","consumable":true,"consume_available":true,"quantity":1,"use_count":3}
	bag.take_item(consumable); bag.update_held_trigger(0,head.global_transform); bag.update_held_trigger(0.9,head.global_transform)
	check(consumes.size()==1 and bag.action_pending and not bag.hologram.active,"Consumable fresh trigger requests exactly one authoritative use")
	bag.update_held_trigger(0.9,head.global_transform); check(consumes.size()==1,"Held trigger does not consume repeatedly")
	var remaining:=consumable.duplicate(true); remaining.use_count=2; bag.finish_consumable_action(remaining,true)
	bag.update_held_trigger(0.9,head.global_transform)
	check(bag.held_item.use_count==2 and consumes.size()==1,"Remaining charges update held record and require fresh trigger")
	bag.update_held_trigger(0,head.global_transform); bag.update_held_trigger(0.9,head.global_transform)
	check(consumes.size()==2,"New release/press requests next single use")
	bag.finish_consumable_action({},false); bag.set_busy(false,"Cannot consume: stomach is full."); check(not bag.held_item.is_empty() and bag.held_status.visible and "stomach" in bag.held_status.text,"Rejected consume keeps item and shows held status outside closed bag")
	bag.finish_consumable_action({},true); check(bag.held_item.is_empty(),"Consumed last object clears hand")
	check(source.skeleton.transform==source_transform,"Hologram interactions leave current avatar skeleton unchanged")
	bag.take_item(incoming); bag.show_equipment_hologram(head.global_transform); bag.update_gestures(false,head.global_transform,Transform3D.IDENTITY,0.9,0.9,{})
	check(not bag.hologram.active and bag.held_item.is_empty() and drops.is_empty(),"Tracking loss cancels without accidental equip/consume/drop")
	bag.take_item(incoming);bag.show_equipment_hologram(head.global_transform)
	bag.sample_equipment_distance(head.global_position+Vector3(.5,-1.2,0),true)
	check(bag.hologram.active,"Leaning and crouching retain equipment hologram")
	bag.sample_equipment_distance(head.global_position+Vector3(2,0,0),false)
	check(bag.hologram.active,"Untracked head pose cannot trigger distance dismissal")
	bag.held_item=refreshed;bag.set_equipment_context(source,[current])
	check(bag.hologram_open_position==head.global_position,"Server equipment refresh preserves opening location")
	bag.stick_captured=true
	bag.sample_equipment_distance(head.global_position+Vector3(1.6,0,0),true)
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},Transform3D.IDENTITY)
	check(not bag.hologram.active and not bag.stick_captured and not bag.held_item.is_empty(),"Walking away closes hologram and scrolling while retaining held item")
	check(equips.size()==1 and drops.is_empty(),"Walk-away with simultaneous grip release sends no equip or drop")
	bag.clear_held();bag.browse_equipment(head.global_transform)
	bag.hologram.ability_editor.toggle()
	bag.sample_equipment_distance(head.global_position+Vector3(0,0,-1.6),true)
	check(not bag.hologram.active and not bag.hologram.ability_editor.active and not bag.pointers_suspended,"Walking away also dismisses abilities and releases UI pointer ownership")
	bag.browse_equipment(head.global_transform)
	bag.equipment_drag=current.duplicate(true);bag.hologram.close()
	bag.sample_equipment_distance(head.global_position+Vector3(-1.6,0,0),true)
	check(bag.equipment_drag.is_empty() and not bag.pointers_suspended,"Walking away cancels unfinished unequip drag even while hologram is hidden")
	bag.browse_equipment(head.global_transform);bag.begin_mutation("Pending server action")
	bag.sample_equipment_distance(head.global_position+Vector3(0,0,1.6),true)
	check(not bag.hologram.active and bag.action_pending and bag.mutation_pending,"Walk-away preserves outstanding native mutation ownership")
	bag.set_busy(false)
	if "--capture" in OS.get_cmdline_user_args():
		check(RenderingServer.get_current_rendering_method()=="forward_plus","Desktop preview uses Forward+ Vulkan")
		var caption_text: String="Desktop equipment preview · original avatar / synthetic comparison fixture"
		var preview_slot: String="hold_r"
		if "--live-snapshot" in OS.get_cmdline_user_args():
			var actual: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/equipment-fixture-snapshot.json"))
			var incoming_records: Array=actual.items.filter(func(item): return str(item.get("id",""))=="281474993609991")
			check(not incoming_records.is_empty(),"Actual Core3 fixture incoming shirt is available")
			incoming=incoming_records[0]
			var source_report: Dictionary=source.configure(str(actual.race))
			var gear_report: Dictionary=source.refresh_equipment(actual.equipment)
			check(str(source_report.get("error","")).is_empty() and bool(gear_report.get("complete",false)),"Actual source avatar displays full server equipment snapshot")
			bag.set_snapshot(actual); bag.set_equipment_context(source,actual.equipment); preview_slot="chest1"
			caption_text="Desktop equipment preview · actual local Core3 avatar and item attributes"
		bag.take_item(incoming); bag.show_equipment_hologram(head.global_transform); bag.hologram.update_hand(bag.hologram.markers[preview_slot].global_position)
		bag.held_model.visible=false
		var camera:=Camera3D.new(); world.add_child(camera); camera.position=Vector3(0,1.52,0.5); camera.fov=52; camera.make_current()
		var environment:=WorldEnvironment.new(); var settings:=Environment.new(); settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("071119"); environment.environment=settings; world.add_child(environment)
		var overlay:=CanvasLayer.new(); world.add_child(overlay); var caption:=Label.new(); overlay.add_child(caption); caption.position=Vector2(20,20); caption.text=caption_text; caption.add_theme_font_size_override("font_size",20)
		root.size=Vector2i(1440,900)
		for i in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/"+("equipment-hologram-live-preview.png" if "--live-snapshot" in OS.get_cmdline_user_args() else "equipment-hologram-preview.png")))
	var result: Dictionary={"checks":checks,"passed":errors.is_empty(),"errors":errors,"gpu_tested":"--capture" in OS.get_cmdline_user_args(),"headset_tested":false,"hologram":bag.hologram.report}
	print(JSON.stringify(result)); FileAccess.open("res://../runtime/evidence/equipment-hologram-"+("live-render" if "--live-snapshot" in OS.get_cmdline_user_args() else "render" if result.gpu_tested else "smoke")+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	call_deferred("finish",world,0 if errors.is_empty() else 1)
func finish(world: Node, code: int) -> void: world.free(); quit(code)
