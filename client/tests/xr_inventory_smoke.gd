extends SceneTree
const Inventory = preload("res://scripts/xr_inventory.gd")
class Player extends CharacterBody3D:
	var move_captured:=false
	var turn_captured:=false
	func set_interface_capture(move: bool, turn: bool) -> void: move_captured=move; turn_captured=turn
var errors: Array[String]=[]
var checks:=0
var drops: Array=[]
var takes: Array=[]
var ready_items: Array=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	var rig:=XROrigin3D.new(); world.add_child(rig)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; rig.add_child(head); head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; rig.add_child(hand)
	var player:=Player.new(); rig.add_child(player)
	var bag:=Inventory.new(); world.add_child(bag); bag.configure(rig,player); bag.set_process(false)
	bag.item_drop_requested.connect(func(item,pose): drops.append({"item":item,"pose":pose}))
	bag.item_take_requested.connect(func(item): takes.append(item))
	bag.item_ready_for_use.connect(func(item): ready_items.append(item))
	var templates: Array=bag.assets.catalog.get("items",{}).keys()
	check(not templates.is_empty(),"Original inventory model catalog exists")
	var template: String=templates[0] if not templates.is_empty() else "missing"
	var item: Dictionary={"id":"item1","template":template,"name":"Original source item","quantity":10,"container_id":"inventory","split_supported":true,"split_available":true,"split_max_quantity":9}
	var snapshot: Dictionary={"source_kind":"core3_inventory","inventory":{"id":"inventory","capacity":80,"occupied":42},"containers":[{"id":"container","parent_id":"inventory","capacity":30,"occupied":1}],"items":[]}
	for i in range(40):
		var entry:=item.duplicate(); entry.id="item%d"%i; snapshot.items.append(entry)
	snapshot.items.append({"id":"nested","container_id":"container","template":template,"name":"Nested source item"})
	snapshot.items[0].is_container=true; snapshot.items[0].id="container"
	var original:=snapshot.duplicate(true)
	bag.set_snapshot(snapshot); bag.set_allowed(true)
	check(bag.ui.items.size()==40 and bag.ui.visible_items().size()==32,"Container-filtered grid has exactly32 visible slots")
	check(bag.slot_scene.get_child_count()<=32,"Shared slot viewport bounds rendered item models")
	check(bag.ui.snapshot.count==42 and bag.ui.snapshot.capacity==80,"Authoritative recursive occupancy preserved")
	var pose:=Transform3D(Basis.IDENTITY,Vector3(-0.19,1.54,0.12))
	bag.update_gestures(true,head.global_transform,pose,0.9,0,{})
	check(not bag.is_open,"Held grip on initial tracking cannot pull backpack")
	bag.update_gestures(true,head.global_transform,pose,0,0,{})
	bag.update_gestures(true,head.global_transform,pose,0.9,0,{})
	check(bag.is_open and bag.interaction_active,"Fresh grip at offhand shoulder pulls backpack")
	check(is_instance_valid(bag.bag_model),"No equipped bag resolves original generic NPC backpack")
	var hit: Dictionary={"surface":0,"pixel":Vector2(80,155)}
	bag.update_gestures(true,head.global_transform,pose,0.9,0,hit)
	bag.update_gestures(true,head.global_transform,pose,0.9,0.9,hit)
	check(not bag.held_item.is_empty() and takes.size()==1,"Fresh pointing main-hand grip takes original item presentation")
	bag.update_gestures(true,head.global_transform,pose,0.9,0,hit)
	check(bag.held_item.is_empty() and drops.is_empty(),"Release while bag open returns item without backend mutation")
	bag.update_gestures(true,head.global_transform,pose,0.9,0.9,hit)
	bag.update_gestures(true,head.global_transform,pose,0,0.9,{})
	check(not bag.is_open and not bag.held_item.is_empty() and ready_items.size()==1,"Stowing bag preserves main item and signals ready for use")
	var release_pose:=Transform3D(Basis(Vector3.UP,0.6),Vector3(0.4,1.2,-0.5))
	bag.held_model.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,0,0))
	bag.update_gestures(true,head.global_transform,pose,0,0,{},release_pose)
	check(drops.size()==1 and drops[0].pose.is_equal_approx(release_pose),"Drop uses current tracked release pose rather than previous-frame model pose")
	check(drops.size()==1 and bag.action_pending and not bag.held_item.is_empty(),"Stowed release requests authoritative drop and retains pending presentation")
	bag.finish_item_action(false)
	bag.update_gestures(true,head.global_transform,pose,0,0,{})
	check(drops.size()==1 and not bag.held_item.is_empty(),"Rejected drop never repeats every frame")
	bag.set_allowed(false)
	check(not bag.is_open and bag.held_item.is_empty() and drops.size()==1,"Menu cancellation clears presentation without a drop")
	check(snapshot==original,"Presentation never mutates supplied inventory snapshot")
	bag.ui.scroll_rows(1)
	check(bag.ui.first_row==1 and bag.ui.visible_items().size()==32,"Stick paging advances one row beyond first32items")
	bag.ui.open_container("container")
	check(bag.ui.items.size()==1 and bag.ui.items[0].id=="nested","Container navigation uses source owner IDs")
	bag.ui.parent_container()
	check(bag.ui.container_id=="inventory","Container parent returns to root")
	bag.ui.select_item(item)
	check(bag.ui.split_slider.max_value==9 and not bag.ui.split_button.disabled,"Supported stack slider range excludes zero/full quantity")
	bag.ui.set_pending(true)
	check(bag.ui.split_button.disabled and not bag.ui.split_slider.editable,"Pending authoritative mutation locks split controls")
	var unavailable:=item.duplicate(); unavailable.split_available=false; unavailable.split_block_reason="No room"; bag.ui.set_pending(false); bag.ui.select_item(unavailable)
	check(bag.ui.split_button.disabled,"Full container disables split based on backend capacity decision")
	# Actual native hit testing plus SubViewport trigger dispatch to a real slot.
	bag.set_allowed(true); bag.set_open(true)
	bag.ui.first_row=0; bag.ui.set_snapshot(snapshot)
	bag.global_transform=Transform3D.IDENTITY
	for i in range(2): await process_frame
	var surface: Dictionary=bag.surfaces[0]
	var pixel:=Vector2(205,155)
	var local:=Vector3((pixel.x/surface.viewport.size.x-0.5)*surface.meters.x,(0.5-pixel.y/surface.viewport.size.y)*surface.meters.y,0)
	var actual: Dictionary=bag.find_hit({"tip":surface.mesh.global_transform*(local+Vector3(0,0,0.15)),"direction":-surface.mesh.global_basis.z})
	check(not actual.is_empty() and actual.surface==0,"Native finger ray reaches inventory slot")
	bag.update_pointer(actual,0.0); bag.update_pointer(actual,0.9); await process_frame
	bag.update_pointer(actual,0.0); await process_frame
	check(bag.ui.selected_id=="item1","Fresh trigger dispatch selects actual slot through SubViewport")
	bag.update_stick_capture(Vector2(0,-1),actual,0.016)
	check(bag.ui.selected_id=="item2" and bag.ui.first_row==0 and not player.move_captured and player.turn_captured,"Pointed joystick highlights next item and captures only pointing-hand stick")
	bag.update_stick_capture(Vector2.ZERO,{},0.016)
	check(not player.move_captured and not player.turn_captured,"Neutral stick releases input capture")
	var source_mesh:=bag.assets.model(template)
	check(source_mesh!=null and source_mesh==bag.assets.model(template),"Repeated original templates share immutable mesh/material resources")
	check(bag.assets.model("object/nonexistent.iff")==null,"Missing model stays unavailable, no replacement mesh")
	var original_transforms: Array=[rig.transform,head.transform,player.transform]
	bag.update_gestures(false,head.global_transform,pose,0.9,0.9,{})
	check(not bag.interaction_active and not bag.is_open and original_transforms==[rig.transform,head.transform,player.transform],"Tracking loss cancels without moving tracked head/body")
	check(bag.slot_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED and bag.preview_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Closed inventory stops both model viewport renders")
	var original_bag_template:=bag.assets.backpack_template({})
	var original_bag_mesh:=bag.assets.model(original_bag_template)
	check(original_bag_mesh!=null and original_bag_mesh.surface_get_material(0) is ShaderMaterial and original_bag_mesh.surface_get_material(0).get_shader_parameter("main_texture")!=null,"Original backpack retains character palette/texture material pipeline")
	bag.set_allowed(true)
	var recovered:=item.duplicate(true); recovered.local_state="dropped"
	bag.world_pickup_provider=func(_pose): return recovered
	bag.update_gestures(true,head.global_transform,Transform3D(Basis.IDENTITY,Vector3(0,1,-1)),0,0,{})
	bag.update_gestures(true,head.global_transform,Transform3D(Basis.IDENTITY,Vector3(0,1,-1)),0,0.9,{})
	check(not bag.held_item.is_empty() and not bag.held_item.has("local_state") and recovered.local_state=="dropped","World pickup presents owned item without mutating provider state")
	check(bag.blocks_combat(),"Ordinary held item blocks weapon controls")
	bag.set_external_use_active(true)
	check(bag.external_use_active and not bag.blocks_combat() and not bag.held_model.visible,"Explicit supported weapon handoff releases combat and hides duplicate inventory mesh")
	bag.set_busy(true,"Dropping…")
	check(bag.blocks_combat(),"Pending authoritative action blocks delegated combat")
	bag.set_busy(false)
	bag.set_open(true)
	check(not bag.external_use_active and bag.held_model.visible and bag.blocks_combat(),"Reopening bag revokes external use and restores held visual")
	bag.cancel_interaction()
	var reserved:=item.duplicate(true); reserved.local_state="dropped"; bag.ui.select_item(reserved)
	check(bag.ui.split_button.disabled,"Session dropped item reserves capacity and disables stack split")
	bag.set_open(true); bag.ui.set_snapshot({"inventory":{"id":"inventory","capacity":80,"occupied":1},"items":[reserved]})
	bag.update_gestures(true,head.global_transform,pose,0.9,0,hit)
	bag.update_gestures(true,head.global_transform,pose,0.9,0.9,hit)
	check(bag.held_item.is_empty(),"Reserved dropped slot cannot duplicate physical item into hand")
	bag.cancel_interaction()
	var equipped_snapshot:=snapshot.duplicate(true)
	equipped_snapshot.equipped_backpack={"id":"equippedbag","template":original_bag_template,"is_container":true}
	equipped_snapshot.containers.append({"id":"equippedbag","parent_id":"character","capacity":30,"occupied":1,"equipped":true})
	equipped_snapshot.items.append({"id":"bagitem","container_id":"equippedbag","template":template,"name":"Equipped bag contents"})
	bag.set_snapshot(equipped_snapshot)
	check(bag.ui.container_switch.item_count==2,"Equipped backpack gets explicit container selector without synthetic root slot")
	bag.ui.container_switch.item_selected.emit(1)
	check(bag.ui.items.size()==1 and bag.ui.items[0].id=="bagitem","Equipped backpack contents reachable despite parent character outside inventory")
	bag.ui.parent_container()
	check(bag.ui.container_id=="inventory" and bag.ui.items.size()==40,"Equipped backpack parent navigation returns to inventory root")
	bag.set_open(true)
	check(bag.bag_template==original_bag_template and is_instance_valid(bag.bag_model) and bag.bag_model.get_child(0).mesh==original_bag_mesh,"Equipped backpack presentation uses the source model from snapshot")
	equipped_snapshot.equipped_backpack.template="object/unavailable_equipped_backpack.iff"
	bag.set_snapshot(equipped_snapshot)
	check(bag.bag_template=="object/unavailable_equipped_backpack.iff" and bag.bag_model==null,"Unavailable equipped backpack never silently becomes the generic model")
	bag.cancel_interaction()
	# Exercise root's synchronous signal -> annotated snapshot path.
	bag.set_snapshot(snapshot); bag.set_open(true)
	bag.item_held_changed.connect(func(_held):
		if not bag.get_meta("simulate_refresh",false): return
		var annotated: Dictionary=snapshot.duplicate(true)
		for entry: Dictionary in annotated.items:
			if str(entry.id)==str(bag.held_item.get("id","")): entry.local_state="held"
		bag.set_snapshot(annotated))
	bag.set_meta("simulate_refresh",true)
	var same_bag: Node3D=bag.bag_model
	var left: Node3D=rig.get_node("LeftHand"); left.position=Vector3(-0.4,1.2,-0.5)
	var right_hand: Node3D=rig.get_node("RightHand"); right_hand.position=Vector3(0.3,1.25,-0.55)
	bag.set_snapshot(snapshot)
	check(bag.bag_model==same_bag and (bag.bag_model.global_transform*bag.bag_corner).is_equal_approx(left.global_position),"Unchanged bag mesh is reused and immediately corner-anchored during async snapshot refresh")
	bag.take_item(item)
	check(bag.ui.detail_item.get("local_state","")=="held" and bag.ui.split_button.disabled,"Reentrant annotated snapshot cannot be overwritten by unreserved selected item")
	check(bag.held_model.global_transform.is_equal_approx(right_hand.global_transform),"New held model starts at tracked hand before any rendering frame")
	bag.cancel_interaction(); bag.set_meta("simulate_refresh",false)
	var deed_calls:Array=[]
	bag.vehicle_deed_requested.connect(func(value): deed_calls.append(value))
	bag.held_item={"id":"original_vehicle_deed","template":"object/tangible/deed/vehicle_deed/speederbike_deed.iff"}
	bag.update_held_trigger(0,head.global_transform);bag.update_held_trigger(0.9,head.global_transform);bag.update_held_trigger(0.9,head.global_transform)
	check(deed_calls.size()==1 and bag.action_pending,"Held original vehicle deed trigger requests one native registration and waits for acknowledgement")
	bag.set_busy(false);bag.held_item={"id":"recipe","template":"object/tangible/loot/loot_schematic/vehicle_schematic.iff"}
	bag.update_held_trigger(0,head.global_transform);bag.update_held_trigger(0.9,head.global_transform)
	check(deed_calls.size()==1 and not bag.action_pending,"Recipe loot schematics cannot be mistaken for vehicle deeds")
	var camo_calls:Array=[];var consume_calls:Array=[]
	bag.scout_requested.connect(func(value):camo_calls.append(value));bag.consume_requested.connect(func(value):consume_calls.append(value))
	bag.held_item={"id":"kit","template":"object/tangible/scout/camokit/camokit_tatooine.iff","tool_kind":"camouflage","consumable":true,"consume_available":true}
	bag.update_held_trigger(0,head.global_transform);bag.update_held_trigger(.9,head.global_transform);bag.update_held_trigger(.9,head.global_transform)
	check(camo_calls.size()==1 and consume_calls.is_empty() and bag.action_pending,"Kit trigger enters only native conceal route and cannot double-consume")
	bag.set_busy(false,"Rejected native use");bag.update_held_trigger(.9,head.global_transform)
	check(camo_calls.size()==1 and bag.held_item.id=="kit","Rejected kit use retains held item and requires fresh trigger release")
	bag.held_item={};bag.cancel_interaction()
	if "--capture" in OS.get_cmdline_user_args():
		check(RenderingServer.get_current_rendering_method()=="forward_plus" and DisplayServer.get_name()!="headless","Inventory preview uses Forward+ Vulkan")
		var fixture:=snapshot.duplicate(true); fixture.items=[]
		for i in range(40):
			var entry:=item.duplicate(); entry.id="fixture%d"%i; entry.template=templates[i%templates.size()]; entry.name=str(entry.template).get_file().get_basename().replace("_"," "); fixture.items.append(entry)
		fixture.items[1].template="object/missing_model.iff"
		bag.ui.first_row=0
		var caption: String="Desktop asset preview · synthetic slot arrangement"
		if "--live-snapshot" in OS.get_cmdline_user_args():
			fixture=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/inventory-live-snapshot.json"))
			check(fixture.get("source_kind","")=="core3_inventory" and not fixture.get("items",[]).is_empty(),"Live preview uses actual read-only Core3 inventory snapshot")
			caption="Local Core3 inventory snapshot · desktop rendering"
		bag.set_snapshot(fixture); bag.set_open(true); bag.global_transform=Transform3D.IDENTITY; bag.ui.select_item(fixture.items[0]); bag.ui.status=caption
		if is_instance_valid(bag.bag_model): bag.bag_model.position=Vector3(-0.4,-0.035,0.08)
		var camera:=Camera3D.new(); world.add_child(camera); camera.position=Vector3(0.1,0.19,1.03); camera.fov=48; camera.make_current()
		var environment:=WorldEnvironment.new(); var settings:=Environment.new(); settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("071119"); environment.environment=settings; world.add_child(environment)
		root.size=Vector2i(1440,900)
		for i in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/"+("inventory-live-preview.png" if "--live-snapshot" in OS.get_cmdline_user_args() else "inventory-preview.png")))
	var result: Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"headset_tested":false,"gpu_tested":"--capture" in OS.get_cmdline_user_args(),"stats":bag.statistics()}
	print(JSON.stringify(result)); FileAccess.open("res://../runtime/evidence/"+("xr-inventory-render.json" if result.gpu_tested else "xr-inventory-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	call_deferred("finish",world,0 if errors.is_empty() else 1)
func finish(world: Node,code: int) -> void: world.free(); quit(code)
