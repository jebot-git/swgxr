extends "res://scripts/xr_datapad.gd"
## Presentation-only bag handling. Authoritative mutations are requested from Core3.
signal refresh_requested
signal backpack_presentation_changed(hidden: bool, template: String)
signal item_take_requested(item: Dictionary)
signal item_ready_for_use(item: Dictionary)
signal item_held_changed(item: Dictionary)
signal item_drop_requested(item: Dictionary, pose: Transform3D)
signal stack_split_requested(item: Dictionary, amount: int)
signal equip_requested(item: Dictionary, arrangement: int)
signal unequip_requested(item: Dictionary, side: String)
signal consume_requested(item: Dictionary)
signal tool_context_requested(tool: Dictionary)
signal crafting_requested(tool: Dictionary)
signal vehicle_deed_requested(item: Dictionary)
signal scout_requested(tool: Dictionary)
signal bounty_droid_requested(item: Dictionary)
var crafting_timers: Dictionary = {}
signal survey_requested(tool: Dictionary, resource_id: String)
signal deploy_requested(tool: Dictionary, pose: Transform3D)
signal tool_holster_requested(tool: Dictionary)
signal tool_pickup_requested(candidate: Dictionary)
signal return_tool_requested(tool: Dictionary)
const SurveyUI = preload("res://scripts/survey_tool_ui.gd")
const InventoryUI = preload("res://scripts/inventory_ui.gd")
const EquipmentHologram = preload("res://scripts/equipment_hologram.gd")
const InventoryAssets = preload("res://scripts/inventory_assets.gd")
var assets := InventoryAssets.new()
var world_pickup_provider: Callable
var external_grab_blocker: Callable
var external_item_release: Callable
var external_use_active := false
var hologram: Node3D
var loadout_request:Callable
var loadout_pending:=false
var ability_stick_down:=true
var equipment_avatar: Node3D
var current_equipment: Array = []
var held_trigger_armed := false
var held_status: Label3D
var hologram_context_key := ""
const EQUIPMENT_WALKAWAY_DISTANCE := 1.5
var hologram_open_position := Vector3.INF
var survey_ui: Control
var survey_surface := -1
var resource_surface := -1
var resource_panel: Control
var resource_preview_viewport: SubViewport
var resource_preview_key := ""
var tool_follower := SwgWristDatapad.new()
var hip_tool: Dictionary = {}
var hip_model: Node3D
var hip_candidate := false
var offhand_occupied := false
var snapshot: Dictionary = {}
var interaction_active := false
var shoulder_candidate := false
var grip_armed := false
var main_grip_armed := false
var held_item: Dictionary = {}
var equipment_drag:Dictionary={}
var equipment_drag_model:Node3D
var equipment_grip_armed:=false
var held_side := ""
var open_bag_side := ""
var open_bag_binding := ""
var cross_shoulder_armed := false
var off_hip_grip_armed := false
var held_revision := 0
var action_pending := false
# Read-only snapshots must not unlock a gesture awaiting authoritative mutation.
var mutation_pending := false
var bag_template := ""
var bag_material_key := ""
var bag_corner := Vector3.ZERO
var bag_ui_anchor := Vector3.ZERO
var bag_corner_side := ""
var bag_model: Node3D
var held_model: Node3D
var slot_viewport: SubViewport
var slot_scene: Node3D
var preview_viewport: SubViewport
var preview_scene: Node3D
var scroll_time := 0.0
var pointers_suspended := false

func configure(origin: XROrigin3D, player: CharacterBody3D, side := "left") -> void:
	rig=origin; body=player; offhand="right" if side=="right" else "left"; process_priority=121
	assets.configure()
	RenderingServer.frame_pre_draw.connect(refresh_hand_presentations)
	hologram=EquipmentHologram.new(); add_child(hologram); hologram.top_level=true; hologram.visible=false
	hologram.loadout_proposed.connect(request_loadout)
	held_status=Label3D.new(); add_child(held_status); held_status.top_level=true; held_status.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	held_status.font_size=24; held_status.pixel_size=0.00035; held_status.width=620; held_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	held_status.billboard=BaseMaterial3D.BILLBOARD_ENABLED; held_status.modulate=Color("c9fbff"); held_status.outline_size=3; held_status.visible=false
	ui=InventoryUI.new()
	add_surface(ui,Vector2i(1024,640),Vector2(0.56,0.35))
	add_surface(ui.configure_details(),Vector2i(420,640),Vector2(0.23,0.35))
	ui.unequip_requested.connect(func(item):unequip_requested.emit(item,""))
	for surface: Dictionary in surfaces: surface.viewport.gui_embed_subwindows=true
	survey_ui=SurveyUI.new(); survey_ui.configure()
	add_surface(survey_ui,Vector2i(1050,680),Vector2(0.46,0.30)); survey_surface=surfaces.size()-1
	surfaces[survey_surface].mesh.top_level=true
	surfaces[survey_surface].viewport.gui_embed_subwindows=true
	resource_panel=preload("res://scripts/survey_resource_panel.gd").new();resource_panel.configure()
	add_surface(resource_panel,Vector2i(480,680),Vector2(0.22,0.30));resource_surface=surfaces.size()-1
	surfaces[resource_surface].mesh.top_level=true
	resource_preview_viewport=create_model_viewport(Vector2i(440,190))
	var resource_image:=TextureRect.new();resource_panel.add_child(resource_image);resource_image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	resource_image.position=Vector2(20,125);resource_image.size=Vector2(440,190);resource_image.texture=resource_preview_viewport.get_texture()
	survey_ui.resource_details_changed.connect(update_resource_details)
	survey_ui.tool_slot_requested.connect(func():
		if is_instance_valid(rig): show_equipment_hologram(rig.get_node("XRCamera3D").global_transform))
	surfaces[0].mesh.position.y=0.235
	surfaces[1].mesh.position=Vector3(0.405,0.235,0.03)
	surfaces[1].mesh.rotation.y=deg_to_rad(-25)
	slot_viewport=create_model_viewport(Vector2i(1024,640))
	slot_scene=slot_viewport.get_node("Models")
	var images:=TextureRect.new(); images.mouse_filter=Control.MOUSE_FILTER_IGNORE
	images.texture=slot_viewport.get_texture(); images.size=Vector2(1024,640); ui.add_child(images)
	preview_viewport=create_model_viewport(Vector2i(380,230))
	preview_scene=preview_viewport.get_node("Models")
	var preview:=TextureRect.new(); preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	preview.texture=preview_viewport.get_texture(); preview.position=Vector2(20,100); preview.size=Vector2(380,230); ui.detail.add_child(preview)
	ui.page_changed.connect(rebuild_slots)
	ui.selection_changed.connect(rebuild_preview)
	ui.split_requested.connect(func(item,amount): stack_split_requested.emit(item,amount))
	dot=MeshInstance3D.new(); var sphere:=SphereMesh.new(); sphere.radius=0.0025; sphere.height=0.005; dot.mesh=sphere
	var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=Color("baffff"); dot.material_override=material; add_child(dot)
	sync_presentation()

func create_model_viewport(pixels: Vector2i) -> SubViewport:
	var target:=SubViewport.new(); target.size=pixels; target.transparent_bg=true; target.own_world_3d=true
	target.render_target_update_mode=SubViewport.UPDATE_DISABLED; target.gui_disable_input=true; add_child(target)
	var models:=Node3D.new(); models.name="Models"; target.add_child(models)
	var camera:=Camera3D.new(); target.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=pixels.y; camera.position=Vector3(0,0,500); camera.far=1000; camera.current=true
	return target

func set_snapshot(value: Dictionary) -> void:
	snapshot=value.duplicate(true)
	ui.set_snapshot(snapshot)
	action_pending=mutation_pending; ui.set_pending(action_pending)
	if is_open: rebuild_bag()

func set_allowed(value: bool) -> void:
	if allowed==value: return
	allowed=value
	if not value: cancel_interaction()

func sync_presentation() -> void:
	var show_survey: bool=is_survey_held() and not is_open and not (is_instance_valid(hologram) and hologram.active)
	var show_bag_ui: bool=is_open and not show_survey and not (is_instance_valid(hologram) and hologram.active)
	for index in range(surfaces.size()):
		var surface: Dictionary=surfaces[index]
		var show_surface: bool=show_survey if index in [survey_surface,resource_surface] else show_bag_ui
		var mode:=SubViewport.UPDATE_WHEN_VISIBLE if show_surface else SubViewport.UPDATE_DISABLED
		if surface.mesh.visible!=show_surface: surface.mesh.visible=show_surface
		if surface.viewport.render_target_update_mode!=mode: surface.viewport.render_target_update_mode=mode
	if is_instance_valid(dot) and not show_bag_ui: dot.visible=false
	if is_instance_valid(held_status): held_status.visible=not held_item.is_empty() and not held_status.text.is_empty() and not hologram.active and not is_survey_held()
	if is_instance_valid(survey_ui): survey_ui.set_active(show_survey)
	if not show_survey and is_instance_valid(resource_preview_viewport): resource_preview_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if is_instance_valid(hip_model): hip_model.visible=allowed and str(hip_tool.get("id",""))!=str(held_item.get("id",""))
	visible=is_open or not held_item.is_empty() or not equipment_drag.is_empty() or hologram.active or (allowed and not hip_tool.is_empty())
	interaction_active=is_open or not held_item.is_empty() or not equipment_drag.is_empty() or hologram.active or shoulder_candidate or hip_candidate
	if not show_bag_ui:
		if is_instance_valid(slot_viewport): slot_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		if is_instance_valid(preview_viewport): preview_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

func set_open(value: bool) -> void:
	if is_open==value: return
	if value:open_bag_side=bag_hand_side();open_bag_binding=offhand
	is_open=value
	if not value:open_bag_side=""
	if value:
		set_external_use_active(false)
		follower.reset(); released_trigger=false; main_grip_armed=false
		rebuild_bag(); rebuild_slots(); rebuild_preview(ui.detail_item)
		refresh_requested.emit(); opened.emit()
	else:
		cancel_press(); clear_hover(); stick_captured=false; apply_capture()
		clear_model(bag_model); bag_model=null
		backpack_presentation_changed.emit(false,bag_template)
		if not held_item.is_empty(): item_ready_for_use.emit(held_item.duplicate(true))
	sync_pointers(); sync_presentation()

func sync_pointers() -> void:
	var suspend:bool=is_open or not held_item.is_empty() or not equipment_drag.is_empty() or hologram.active
	if suspend==pointers_suspended: return
	pointers_suspended=suspend
	preload("res://scripts/pointer_capture.gd").suspend(self,rig,suspend)

func cancel_interaction() -> void:
	# Cancellation never means a world-drop request.
	shoulder_candidate=false; hip_candidate=false; grip_armed=false; main_grip_armed=false; off_hip_grip_armed=false;cross_shoulder_armed=false
	clear_equipment_drag(); clear_held(); set_open(false); sync_pointers(); sync_presentation()

func main_side() -> String: return "right" if offhand=="left" else "left"
func held_hand_side() -> String: return held_side if held_side in ["left","right"] else main_side()
func bag_hand_side() -> String:
	if is_open and open_bag_binding==offhand and open_bag_side in ["left","right"]:return open_bag_side
	return main_side() if not held_item.is_empty() and held_hand_side()==offhand else offhand
func controller_for(side:String) -> XRController3D: return rig.get_node(side.capitalize()+"Hand") as XRController3D
func held_controller() -> XRController3D: return controller_for(held_hand_side())
func tool_pointer_controller() -> XRController3D: return controller_for("right" if held_hand_side()=="left" else "left")

func shoulder_contains(head: Transform3D, hand_position: Vector3) -> bool:
	var forward:=(-head.basis.z).slide(Vector3.UP).normalized()
	if forward.length_squared()<0.5: forward=-rig.global_basis.z.slide(Vector3.UP).normalized()
	var right:=forward.cross(Vector3.UP)
	var shoulder:=head.origin+right*(-0.19 if offhand=="left" else 0.19)-Vector3.UP*0.16-forward*0.12
	return hand_position.distance_to(shoulder)<0.24

func update_gestures(tracked: bool, head: Transform3D, hand: Transform3D, off_grip: float, main_grip: float, hit: Dictionary, main_pose: Variant = null) -> void:
	if not allowed or not tracked or (external_grab_blocker.is_valid() and bool(external_grab_blocker.call())):
		cancel_interaction(); return
	var main_hand:=controller_for(main_side())
	var current_main_pose: Transform3D=main_pose if main_pose is Transform3D else main_hand.global_transform
	if is_instance_valid(hologram.ability_editor) and hologram.ability_editor.active:return
	if update_equipment_drag(head,hand,current_main_pose,off_grip,main_grip):return
	if main_grip<.35:cross_shoulder_armed=true
	elif main_grip>=.65 and cross_shoulder_armed:
		cross_shoulder_armed=false
		if not is_open and not action_pending and (held_item.is_empty() or held_hand_side()!=main_side()) and shoulder_contains(head,current_main_pose.origin):
			set_open(true);open_bag_side=main_side();open_bag_binding=offhand;grip_armed=false;main_grip_armed=false
			sync_presentation();return
	var main_hip:=not hip_tool.is_empty() and current_main_pose.origin.distance_to(hip_transform().origin)<0.20
	var off_hip:=not hip_tool.is_empty() and hand.origin.distance_to(hip_transform().origin)<0.20
	hip_candidate=main_hip or off_hip
	if off_grip<.35:off_hip_grip_armed=true
	elif off_grip>=.65 and off_hip_grip_armed:
		off_hip_grip_armed=false
		if off_hip and not offhand_occupied and held_item.is_empty() and not is_open and not action_pending:
			begin_mutation("Retrieving tool…")
			tool_pickup_requested.emit({"gathering_hip":true,"item":hip_tool.duplicate(true),"hand":offhand})
			sync_presentation();return
	var holding_off:=held_hand_side()==offhand if not held_item.is_empty() else (is_open and bag_hand_side()==main_side())
	var item_pose:Transform3D=hand if holding_off else current_main_pose
	var item_hand:XRController3D=controller_for(offhand) if holding_off else main_hand
	var item_grip:float=off_grip if holding_off else main_grip
	var bag_main:=bag_hand_side()==main_side()
	var bag_pose:Transform3D=current_main_pose if bag_main else hand
	var bag_grip:float=main_grip if bag_main else off_grip
	if is_instance_valid(hologram) and hologram.active:hologram.update_hand(item_pose.origin)
	var was_open:=is_open
	shoulder_candidate=(bag_main or not offhand_occupied) and not is_open and shoulder_contains(head,bag_pose.origin)
	if bag_grip<0.35:
		grip_armed=true
		if is_open:set_open(false)
	elif bag_grip>=0.65 and grip_armed:
		grip_armed=false
		if shoulder_candidate:set_open(true)
	if item_grip<0.35:
		var fresh_release:=not main_grip_armed
		main_grip_armed=true
		if not held_item.is_empty() and not action_pending and fresh_release:
			if external_item_release.is_valid() and bool(external_item_release.call(held_item.duplicate(true),item_hand_pose(item_hand,item_pose))):sync_presentation();return
			var slot: Dictionary=hologram.highlighted if is_instance_valid(hologram) and hologram.active else {}
			if not slot.is_empty():
				if bool(slot.get("available",false)):
					if slot.get("prototype_tool_slot",false):
						begin_mutation("Holstering tool…"); tool_holster_requested.emit(held_item.duplicate(true))
					else:
						begin_mutation("Equipping item…"); equip_requested.emit(held_item.duplicate(true),int(slot.get("index",0)))
				else: set_busy(false,str(slot.get("block_reason","Cannot equip here.")))
			elif is_open or was_open:
				if held_item.get("gathering_hip",false): begin_mutation("Returning holstered tool to inventory…"); return_tool_requested.emit(held_item.duplicate(true))
				else: clear_held()
			else:
				set_external_use_active(false)
				begin_mutation("Placing tool…" if is_survey_held() else "Dropping item…")
				if is_survey_held(): deploy_requested.emit(held_item.duplicate(true),item_pose)
				else:
					item_drop_requested.emit(held_item.duplicate(true),item_hand_pose(item_hand,item_pose))
	elif item_grip>=0.65 and main_grip_armed:
		main_grip_armed=false
		if is_open and not action_pending and held_item.is_empty() and not hit.is_empty() and int(hit.get("surface",-1))==0:
			var item: Dictionary=ui.item_at(hit.pixel)
			if not item.is_empty() and str(item.get("local_state","")) not in ["held","dropped"]: take_item(item,offhand if holding_off else main_side())
		elif not is_open and held_item.is_empty() and not action_pending and (main_hip or world_pickup_provider.is_valid()):
			var item: Variant={"gathering_hip":true,"item":hip_tool.duplicate(true)} if main_hip else world_pickup_provider.call(item_pose)
			if item is Dictionary and not item.is_empty():
				if item.get("gathering_hip",false) or item.has("gathering_deployment"):
					begin_mutation("Retrieving tool…"); tool_pickup_requested.emit(item.duplicate(true)); sync_presentation(); return
				var recovered: Dictionary=item.duplicate(true); recovered.erase("local_state"); take_item(recovered)
				if not held_item.is_empty(): item_ready_for_use.emit(held_item.duplicate(true))
	sync_pointers(); sync_presentation()

func take_item(item: Dictionary, side := "") -> void:
	if item.get("equipped",false):
		if not item.get("unequip_available",false):set_busy(false,str(item.get("unequip_block_reason","This item cannot be removed.")));return
		begin_mutation("Removing equipment in CoreCU…")
		unequip_requested.emit(item.duplicate(true),side if side in ["left","right"] else main_side())
		return
	var presentation:=assets.instance(str(item.get("template","")),0.28,item.get("customization",{}))
	# Manufacturing schematics are native datapad records with no source mesh.
	# Display a labeled holographic record, never claim it is original geometry.
	if presentation==null and item.get("type","")=="manufacturing_blueprint":
		presentation=MeshInstance3D.new();var card:=QuadMesh.new();card.size=Vector2(.18,.22);presentation.mesh=card
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.03,.24,.32);presentation.material_override=material
		var label:=Label3D.new();presentation.add_child(label);label.text="BLUEPRINT\n"+str(item.get("name","Manufacturing schematic"));label.font_size=18;label.pixel_size=.0006;label.position.z=.001;label.width=250;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if presentation==null: return # Never fabricate missing original geometry.
	held_trigger_armed=false
	held_status.text=""
	held_revision+=1
	held_side=side if side in ["left","right"] else main_side()
	main_grip_armed=false
	held_item=item.duplicate(true)
	if str(hip_tool.get("id",""))==str(held_item.get("id","")): held_item["gathering_hip"]=true
	held_model=Node3D.new();held_model.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; add_child(held_model); held_model.add_child(presentation)
	var hand:=held_controller()
	if hand!=null: held_model.global_transform=item_hand_pose(hand,hand.global_transform)
	# Remove any local world drop before the single annotated-snapshot refresh.
	item_take_requested.emit(held_item.duplicate(true))
	item_held_changed.emit(held_item.duplicate(true))
	if held_item.is_empty(): return # A reentrant ownership refresh may cancel it.
	var annotated: Dictionary=held_item.duplicate(true)
	for current: Dictionary in ui.snapshot.get("items",[]):
		if str(current.get("id",""))==str(held_item.get("id","")): annotated=current.duplicate(true); break
	annotated["local_state"]="held"
	ui.select_item(annotated); sync_pointers(); sync_presentation()
	if not str(held_item.get("tool_kind","")).is_empty():
		tool_follower.reset(); cancel_press(); clear_hover(); released_trigger=false
		if is_survey_held(): survey_ui.set_context({"tool_id":str(held_item.get("id",""))}); survey_ui.set_pending(true,"Reading current planet resources…")
		tool_context_requested.emit(held_item.duplicate(true))

func finish_item_action(success: bool, message := "") -> void:
	mutation_pending=false; action_pending=false; ui.set_pending(false)
	if success:
		set_busy(false);clear_held()
	else:
		main_grip_armed=true # A failed drop must not repeat until squeezed/released again.
		set_busy(false,message if not message.is_empty() else "Item action was not confirmed. Check inventory before retrying.")
	sync_pointers(); sync_presentation()

func clear_held() -> void:
	if is_instance_valid(held_status): held_status.text=""; held_status.visible=false
	held_trigger_armed=false
	close_equipment_hologram()
	set_external_use_active(false)
	var was_held:=not held_item.is_empty()
	held_revision+=1
	clear_model(held_model); held_model=null; held_item={}; held_side=""; action_pending=false; mutation_pending=false
	if was_held: item_held_changed.emit({})

func clear_model(node: Node) -> void:
	if is_instance_valid(node): node.get_parent().remove_child(node); node.queue_free()

func rebuild_bag() -> void:
	var equipped: Variant=snapshot.get("equipped_backpack")
	var next_template:=assets.backpack_template(equipped if equipped is Dictionary else {})
	var customization: Dictionary=equipped.get("customization",{}) if equipped is Dictionary else {}
	var material_key:=JSON.stringify(customization)
	if is_instance_valid(bag_model) and bag_template==next_template and bag_material_key==material_key and bag_corner_side==bag_hand_side():
		pose_bag(); return
	clear_model(bag_model); bag_model=null
	bag_template=next_template; bag_material_key=material_key; bag_corner_side=bag_hand_side()
	var model:=assets.instance(bag_template,0.36,customization)
	if model!=null:
		bag_model=Node3D.new();bag_model.top_level=true;bag_model.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; add_child(bag_model); bag_model.add_child(model)
		var bounds: AABB=model.transform*model.mesh.get_aabb()
		bag_ui_anchor=Vector3(bounds.get_center().x,bounds.end.y,bounds.end.z+0.015)
		# The original backpack is Y-up, with its outer/front face along +Z.
		# Mirror only the corner selection for the other hand, never the mesh.
		var corner:=Vector3(bounds.position.x if bag_hand_side()=="left" else bounds.end.x,bounds.end.y,bounds.get_center().z)
		var closest:=INF
		# Side pockets can make the AABB corner empty space. Anchor to original
		# geometry in the upper band so the hand actually touches the bag.
		for surface in range(model.mesh.get_surface_count()):
			var vertices: PackedVector3Array=model.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3=model.transform*vertex
				if point.y<bounds.end.y-bounds.size.y*0.15: continue
				var distance:=point.distance_squared_to(corner)
				if distance<closest: closest=distance;bag_corner=point
		pose_bag()
	backpack_presentation_changed.emit(model!=null,bag_template)

func pose_bag() -> void:
	if not is_instance_valid(bag_model) or not is_instance_valid(rig): return
	var hand:=controller_for(bag_hand_side())
	var head:=rig.get_node_or_null("XRCamera3D") as Node3D
	if hand==null or head==null: return
	# A hanging bag stays vertical regardless of controller pitch/roll. Its top
	# corner is the actual grip pivot, instead of a world-space downward offset.
	var front: Vector3=(head.global_position-hand.global_position).slide(Vector3.UP)
	if front.length_squared()<0.0001: front=bag_model.global_basis.z.slide(Vector3.UP)
	if front.length_squared()<0.0001: front=Vector3.BACK
	front=front.normalized()
	var basis:=Basis(Vector3.UP.cross(front),Vector3.UP,front)
	bag_model.global_transform=Transform3D(basis,hand.global_position-basis*bag_corner)
	# The screen rises from the original bag top/front, not the rolled grip.
	# Bag is top-level so moving this UI parent cannot move its source anchor.
	global_transform=bag_model.global_transform*Transform3D(Basis.IDENTITY,bag_ui_anchor)

func item_hand_pose(controller: XRController3D, grip: Transform3D) -> Transform3D:
	# Match the weapon path: runtime aim supplies orientation, grip supplies the
	# physical hand position. Never bake a Quest/SteamVR-specific controller tilt.
	var pose:=grip
	var tracker=XRServer.get_tracker(controller.tracker)
	var aim: XRPose=tracker.get_pose("aim") if tracker!=null else null
	if aim!=null and aim.has_tracking_data:
		pose.basis=(rig.global_transform*aim.get_adjusted_transform()).basis.orthonormalized()
	else:
		pose.basis=(grip.basis*XRTools.get_palm_offset(XRTools.HandOffsetMode.HAND_OFFSET_AUTO,controller).basis).orthonormalized()
	if is_instance_valid(body) and body.get("feedback")!=null:
		var head:Node3D=rig.get_node_or_null("XRCamera3D")
		if head!=null:pose=body.feedback.spice.hand_pose(pose,head.global_transform,"left" if controller.name=="LeftHand" else "right")
	return pose

func refresh_hand_presentations() -> void:
	if not is_instance_valid(rig): return
	pose_bag()
	var main:=held_controller()
	if main!=null and is_instance_valid(held_model): held_model.global_transform=item_hand_pose(main,main.global_transform)
	if is_instance_valid(equipment_drag_model):equipment_drag_model.global_transform=controller_for(main_side()).global_transform

func rebuild_slots() -> void:
	if not is_instance_valid(slot_scene): return
	for child in slot_scene.get_children(): child.free()
	ui.unavailable.clear()
	var items: Array=ui.visible_items()
	for index in range(items.size()):
		var item: Dictionary=items[index]
		if str(item.get("local_state","")) in ["held","dropped"]: continue
		var model:=assets.instance(str(item.get("template","")),72,item.get("customization",{}))
		if model==null: ui.unavailable[str(item.get("id",""))]=true; continue
		var cell:=Node3D.new(); slot_scene.add_child(cell)
		var pixel: Vector2=InventoryUI.GRID_ORIGIN+Vector2(index%8,index/8)*InventoryUI.CELL+Vector2(59,48)
		cell.position=Vector3(pixel.x-512,320-pixel.y,0); cell.rotation=Vector3(-0.12,0.65,0); cell.add_child(model)
	ui.queue_redraw()
	if is_open and not hologram.active: slot_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func rebuild_preview(item: Dictionary) -> void:
	if not is_instance_valid(preview_scene): return
	for child in preview_scene.get_children(): child.free()
	if not item.is_empty():
		var model:=assets.instance(str(item.get("template","")),190,item.get("customization",{}))
		if model!=null:
			var turntable:=Node3D.new(); preview_scene.add_child(turntable); turntable.rotation=Vector3(-0.12,0.65,0); turntable.add_child(model)
	if is_open and not hologram.active: preview_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func update_stick_capture(stick: Vector2, hit: Dictionary, delta: float) -> void:
	if not slider_dragger.capture.is_empty():
		stick_captured=stick.length()>.15;apply_capture();return
	if stick.length()<0.15: stick_captured=false; scroll_time=0
	if not hit.is_empty() and preload("res://scripts/frontend_choice.gd").scroll_active(surfaces[int(hit.surface)].viewport,-stick.y,delta):
		stick_captured=stick.length()>.15;apply_capture();return
	if is_survey_held() and not hologram.active and not hit.is_empty() and int(hit.get("surface",-1)) in [survey_surface,resource_surface] and stick.length()>0.2:
		stick_captured=true; resource_panel.scroll(stick,delta) if int(hit.get("surface",-1))==resource_surface else survey_ui.scroll(stick,delta)
	elif hologram.active and absf(stick.y)>0.5:
		stick_captured=true; scroll_time-=delta
		if scroll_time<=0: hologram.scroll_page(-1 if stick.y>0 else 1); scroll_time=0.22
	elif is_open and not hit.is_empty() and absf(stick.y)>0.5:
		stick_captured=true; scroll_time-=delta
		if scroll_time<=0:
			if int(hit.surface)==0: ui.navigate(-1 if stick.y>0 else 1,hit.pixel)
			else: ui.detail_text.get_v_scroll_bar().value-=stick.y*80
			scroll_time=0.18
	apply_capture()

func _process(delta: float) -> void:
	if not is_instance_valid(rig): cancel_interaction(); return
	var off: XRController3D=rig.get_node("LeftHand" if offhand=="left" else "RightHand")
	var main: XRController3D=rig.get_node("RightHand" if offhand=="left" else "LeftHand")
	var tracker=XRServer.get_tracker("head")
	var head_pose: XRPose=tracker.get_pose("default") if tracker!=null else null
	var tracked:=head_pose!=null and head_pose.has_tracking_data and HandInput.controller_tracked(off) and HandInput.controller_tracked(main)
	var camera: Camera3D=rig.get_node("XRCamera3D")
	sample_equipment_distance(camera.global_position,head_pose!=null and head_pose.has_tracking_data)
	var bag_pointer:XRController3D=controller_for("right" if bag_hand_side()=="left" else "left")
	var hit:=find_hit(tool_pointer_pose(bag_pointer)) if is_open and tracked and not hologram.active else {}
	var right:XRController3D=controller_for("right")
	sample_ability_editor(right.is_button_pressed("primary_click"),main.global_transform,main.get_float("grip"),main.get_float("trigger"),tracked and allowed,tool_pointer_pose(main))
	var slider_consumed:=slider_frame(hit,bag_pointer.global_transform,bag_pointer.get_float("grip"),bag_pointer.get_float("trigger"),tracked and not action_pending and held_item.is_empty())
	update_gestures(tracked,camera.global_transform,off.global_transform,off.get_float("grip") if tracked and not vehicle_hand_busy(offhand) else 0,main.get_float("grip") if tracked and not vehicle_hand_busy("left" if offhand=="right" else "right") else 0,{} if slider_consumed or (not hit.is_empty() and preload("res://scripts/frontend_choice.gd").active(surfaces[int(hit.surface)].viewport)) else hit,main.global_transform)
	if is_open:
		pose_bag()
		if not slider_consumed:update_pointer(hit,bag_pointer.get_float("trigger"))
		update_stick_capture(main.get_vector2("primary"),hit,delta)
	elif stick_captured or hologram.active: update_stick_capture(main.get_vector2("primary"),{},delta)
	if is_survey_held() and not is_open and not hologram.active and tracked and allowed:
		var up:=Vector3.UP; var facing:=rig.global_basis.z.slide(up).normalized()
		if facing.length_squared()<0.5: facing=Vector3.BACK
		var mount:=Transform3D(Basis(up.cross(facing),up,facing),held_controller().global_position+Vector3.UP*0.22)
		var followed: Dictionary=tool_follower.follow(mount,camera.global_position,delta)
		if followed.get("valid",false): set_survey_transform(followed.transform)
		var pointer:=tool_pointer_controller()
		var tool_hit:=find_hit(tool_pointer_pose(pointer))
		update_pointer(tool_hit,pointer.get_float("trigger")); update_stick_capture(main.get_vector2("primary"),tool_hit,delta)
	if is_instance_valid(hip_model): hip_model.global_transform=hip_transform()
	if tracked and allowed: update_held_trigger(held_controller().get_float("trigger"),camera.global_transform)
	refresh_hand_presentations()
	held_status.global_position=held_controller().global_position+Vector3(0,0.10,0)

func set_survey_transform(pose: Transform3D) -> void:
	surfaces[survey_surface].mesh.global_transform=pose
	# Literal left side, as on the original resource-information view.
	surfaces[resource_surface].mesh.global_transform=pose*Transform3D(Basis(Vector3.UP,deg_to_rad(25)),Vector3(-0.405,0,0.025))

func update_resource_details(resource: Dictionary) -> void:
	resource_panel.set_resource(resource)
	var template:=str(resource.get("container_template",""))
	var key:=str(resource.get("id",""))+":"+template
	if key==resource_preview_key: return
	resource_preview_key=key
	var models:=resource_preview_viewport.get_node("Models")
	for child in models.get_children():child.free()
	var model:=assets.instance(template,155) if not template.is_empty() else null
	resource_panel.unavailable.visible=model==null
	if model!=null:
		var pivot:=Node3D.new();models.add_child(pivot);pivot.rotation=Vector3(-0.15,0.55,0);pivot.add_child(model)
	resource_preview_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _exit_tree() -> void:
	preload("res://scripts/pointer_capture.gd").suspend(self,rig,false)
	if RenderingServer.frame_pre_draw.is_connected(refresh_hand_presentations): RenderingServer.frame_pre_draw.disconnect(refresh_hand_presentations)
	cancel_interaction()
	if is_instance_valid(body): body.set_interface_capture(false,false)

func set_held_visual_enabled(value: bool) -> void:
	if is_instance_valid(held_model): held_model.visible=value

func begin_mutation(message: String) -> void:
	mutation_pending=true
	set_busy(true,message)

func set_busy(value: bool, message := "") -> void:
	if not value: mutation_pending=false
	action_pending=value
	ui.status=message
	ui.set_pending(value)
	if is_instance_valid(survey_ui) and is_survey_held(): survey_ui.set_pending(value,message)
	if is_instance_valid(held_status): held_status.text=message; held_status.visible=not held_item.is_empty() and not message.is_empty() and not hologram.active and not is_survey_held()
	if is_instance_valid(hologram): hologram.set_status(message)

func blocks_services() -> bool:
	# Hovering over a shoulder/hip is not ownership of the free hand.
	return is_open or not held_item.is_empty() or not equipment_drag.is_empty() or hologram.active or action_pending

func blocks_combat() -> bool:
	if not allowed: return false
	if not hip_tool.is_empty() and is_instance_valid(rig):
		# Only the weapon hand competes with a tool grab. Resting the free hand
		# near its hip must not prevent drawing the opposite-side weapon.
		var hand:=controller_for(main_side())
		if HandInput.controller_tracked(hand) and hand.global_position.distance_to(hip_transform().origin)<0.20:return true
	if is_open or action_pending or hologram.active or not equipment_drag.is_empty(): return true
	if not held_item.is_empty() and not str(held_item.get("tool_kind","")).is_empty(): return true
	# A released offhand near its shoulder is only a candidate. The real bag
	# draw claims ownership through is_open above, never through idle proximity.
	return not held_item.is_empty() and (bool(held_item.get("equippable",false)) or bool(held_item.get("consumable",false)) or not external_use_active)

func set_external_use_active(value: bool) -> void:
	external_use_active=value and not is_open and not action_pending and not held_item.is_empty() and not bool(held_item.get("equippable",false)) and not bool(held_item.get("consumable",false))
	set_held_visual_enabled(not external_use_active)

func statistics() -> Dictionary:
	return {"open":is_open,"interaction_active":interaction_active,"pending":action_pending,"held_id":held_item.get("id",""),"slot_models":slot_scene.get_child_count() if is_instance_valid(slot_scene) else 0,"max_slot_models":32,"preview_models":preview_scene.get_child_count() if is_instance_valid(preview_scene) else 0,"assets":assets.statistics()}

func set_equipment_context(source: Node3D, equipment: Array) -> void:
	equipment_avatar=source; current_equipment=equipment.duplicate(true)
	if not equipment_drag.is_empty() and not current_equipment.any(func(item):return str(item.get("id",""))==str(equipment_drag.get("id",""))):clear_equipment_drag()
	if not is_instance_valid(hologram) or not hologram.active:return
	var key:=equipment_context_key()
	if key==hologram_context_key: return
	var pose: Transform3D=hologram.global_transform
	var prior_page: int=hologram.page
	var was_abilities:bool=is_instance_valid(hologram.ability_editor) and hologram.ability_editor.active
	var was_browsing:bool=hologram.browsing
	hologram.configure(equipment_avatar,current_equipment+([hip_tool] if not hip_tool.is_empty() else []))
	hologram.offhand=offhand
	var display_item: Dictionary=held_item.duplicate(true); display_item["tool_hip_displaced_ids"]=[str(hip_tool.get("id",""))] if not hip_tool.is_empty() else []
	var shown:bool=hologram.show_equipment(Transform3D.IDENTITY) if was_browsing else hologram.show_item(display_item,Transform3D.IDENTITY)
	if not shown:close_equipment_hologram();return
	hologram.global_transform=pose
	hologram.page=prior_page
	if was_abilities:hologram.ability_editor.toggle()
	hologram.ability_editor.pending=loadout_pending
	hologram_context_key=key
	# Fresh candidate and comparison are recomputed from current hand next sample.

func equipment_context_key() -> String:
	if not is_instance_valid(equipment_avatar): return ""
	var meshes: Array=[]
	for mesh in equipment_avatar.meshes: meshes.append(mesh.get_instance_id())
	return str(equipment_avatar.get_instance_id())+JSON.stringify([current_equipment,held_item,hip_tool,equipment_avatar.appearance,meshes])

func show_equipment_hologram(head: Transform3D = Transform3D.IDENTITY) -> bool:
	if held_item.is_empty() or action_pending: return false
	if not is_instance_valid(equipment_avatar):
		set_busy(false,"Current character appearance is unavailable."); return false
	set_external_use_active(false)
	hologram.configure(equipment_avatar,current_equipment+([hip_tool] if not hip_tool.is_empty() else []))
	hologram.offhand=offhand
	hologram_context_key=equipment_context_key()
	var display_item: Dictionary=held_item.duplicate(true)
	display_item["tool_hip_displaced_ids"]=[str(hip_tool.get("id",""))] if not hip_tool.is_empty() else []
	var shown: bool=hologram.show_item(display_item,head)
	if shown:hologram_open_position=head.origin
	if not shown: set_busy(false,str(hologram.report.get("error","Cannot display equipment.")))
	cancel_press(); clear_hover(); dot.visible=false; stick_captured=false; apply_capture(); sync_presentation()
	return shown

func browse_equipment(head:Transform3D)->bool:
	if action_pending or not held_item.is_empty() or not equipment_drag.is_empty() or not is_instance_valid(equipment_avatar):return false
	hologram.configure(equipment_avatar,current_equipment)
	hologram.offhand=offhand
	hologram_context_key=equipment_context_key()
	equipment_grip_armed=false
	var shown:bool=hologram.show_equipment(head)
	if shown:hologram_open_position=head.origin
	sync_pointers();sync_presentation()
	return shown

func clear_equipment_drag()->void:
	clear_model(equipment_drag_model);equipment_drag_model=null;equipment_drag={}
	equipment_grip_armed=false

func update_equipment_drag(head:Transform3D,off_pose:Transform3D,main_pose:Transform3D,off_grip:float,main_grip:float)->bool:
	if equipment_drag.is_empty() and not (hologram.active and hologram.browsing):return false
	if action_pending:return true
	if main_grip<.35:equipment_grip_armed=true
	if equipment_drag.is_empty():
		var target:Dictionary=hologram.equipped_at(main_pose.origin)
		if main_grip>=.65 and equipment_grip_armed and not target.is_empty():
			equipment_grip_armed=false
			if not target.get("unequip_available",false):return true
			var model:=assets.instance(str(target.get("template","")),.22,target.get("customization",{}))
			if model==null:hologram.set_status("Original item appearance is unavailable.");return true
			equipment_drag=target.duplicate(true);equipment_drag_model=model;add_child(model);model.global_transform=main_pose
			var preview_material:=ShaderMaterial.new();preview_material.shader=preload("res://shaders/equipment_hologram.gdshader");model.material_override=preview_material
			hologram.close();grip_armed=off_grip<.35
	else:
		equipment_drag_model.global_transform=main_pose
		if off_grip<.35:
			grip_armed=true
			if is_open:set_open(false)
		elif off_grip>=.65 and grip_armed and shoulder_contains(head,off_pose.origin):
			grip_armed=false;set_open(true)
		if main_grip<.35:
			var inside:bool=is_open and is_instance_valid(bag_model) and bag_model.global_position.distance_to(main_pose.origin)<=.30
			var item:=equipment_drag.duplicate(true);clear_equipment_drag()
			if inside:
				begin_mutation("Returning equipment to inventory…");unequip_requested.emit(item,"")
			else:browse_equipment(head) # Cancel without changing native equipment.
	sync_pointers();sync_presentation()
	return true

func sample_equipment_distance(head_position:Vector3,head_tracked:bool)->void:
	if not head_tracked or not hologram_open_position.is_finite():return
	if not hologram.active and equipment_drag.is_empty():return
	var offset:=head_position-hologram_open_position
	offset.y=0 # Crouching and standing do not dismiss a world-anchored panel.
	if offset.length()<=EQUIPMENT_WALKAWAY_DISTANCE:return
	clear_equipment_drag()
	# Consume a simultaneous grip release; dismissing UI must not drop a held item.
	main_grip_armed=true;held_trigger_armed=false
	cancel_press();clear_hover();dot.visible=false
	close_equipment_hologram()

func close_equipment_hologram() -> void:
	if is_instance_valid(hologram): hologram.close()
	hologram_open_position=Vector3.INF
	stick_captured=false;apply_capture();sync_pointers();sync_presentation()

func update_held_trigger(trigger: float, head: Transform3D) -> void:
	if is_instance_valid(hologram.ability_editor) and hologram.ability_editor.active:return
	if held_item.is_empty() or not allowed or is_open or held_item.get("tool_kind","") in ["fishing","slicing"] or not str(held_item.get("structure_template","")).is_empty(): return
	if trigger<0.35: held_trigger_armed=true; return
	if trigger<0.55 or not held_trigger_armed or action_pending: return
	held_trigger_armed=false
	if preload("res://bounty/presentation.gd").droid_item(held_item):
		bounty_droid_requested.emit(held_item.duplicate(true))
	elif is_vehicle_deed(held_item) or is_pet_deed(held_item):
		begin_mutation("Registering deed in datapad…"); vehicle_deed_requested.emit(held_item.duplicate(true))
	elif bool(held_item.get("medical_item",false)) or bool(held_item.get("wound_medpack",false)):
		begin_mutation("Applying medical supply…");consume_requested.emit(held_item.duplicate(true))
	elif preload("res://scout/ranger_input.gd").is_kit(held_item):
		begin_mutation("Applying camouflage…");scout_requested.emit(held_item.duplicate(true))
	elif not str(held_item.get("tool_kind","")).is_empty():
		if hologram.active: close_equipment_hologram()
		elif str(held_item.get("tool_kind",""))=="crafting": crafting_requested.emit(held_item.duplicate(true))
		elif str(held_item.get("tool_kind","")) in ["camp","trap","grenade"]: scout_requested.emit(held_item.duplicate(true))
		elif is_survey_held():
			if survey_ui.selected_resource_id.is_empty(): set_busy(false,"Select an available resource first."); return
			begin_mutation("Surveying…"); survey_requested.emit(held_item.duplicate(true),survey_ui.selected_resource_id)
		else: show_equipment_hologram(head)
	elif bool(held_item.get("equippable",false)):
		if hologram.active: close_equipment_hologram()
		else: show_equipment_hologram(head)
	elif bool(held_item.get("consumable",false)):
		if not bool(held_item.get("consume_available",false)):
			set_busy(false,str(held_item.get("consume_block_reason","Cannot use this item."))); return
		begin_mutation("Using one unit…"); consume_requested.emit(held_item.duplicate(true))

static func is_vehicle_deed(item: Dictionary) -> bool:
	# Learned loot schematics are a distinct Core3 type and never activate as vehicles.
	if item.get("vehicle_deed",false): return true
	var template := str(item.get("template",item.get("shared_template","")))
	return template.begins_with("object/tangible/deed/vehicle_deed/") and template.ends_with(".iff")

static func is_pet_deed(item: Dictionary) -> bool:
	var template := str(item.get("template",item.get("shared_template","")))
	return template.begins_with("object/tangible/deed/pet_deed/") and template.ends_with(".iff")

func finish_equipment_action(success: bool) -> void:
	finish_item_action(success)

func finish_consumable_action(updated_item: Dictionary, success: bool) -> void:
	mutation_pending=false; action_pending=false; ui.set_pending(false)
	# Require a new release/press after completion even if trigger stayed held.
	held_trigger_armed=false
	if success:
		if updated_item.is_empty(): clear_held()
		else:
			held_item=updated_item.duplicate(true)
			item_held_changed.emit(held_item.duplicate(true))
	sync_pointers(); sync_presentation()

func is_survey_held() -> bool:
	return str(held_item.get("tool_kind",""))=="survey"

func set_tool_context(tool_id: String, context: Dictionary) -> void:
	if context.get("hip_tool") is Dictionary: set_hip_tool(context.hip_tool)
	elif context.has("hip_tool"): set_hip_tool({})
	if tool_id!=str(held_item.get("id","")): return
	var normalized:=context.duplicate(true); normalized["tool_id"]=tool_id
	var pending_message: String=survey_ui.status.text
	survey_ui.set_context(normalized)
	if mutation_pending:
		survey_ui.set_pending(true,pending_message); ui.set_pending(true)
	else:
		action_pending=false; ui.set_pending(false); held_status.text=""
	sync_presentation()

func set_survey_result(tool_id: String, result: Dictionary) -> void:
	if tool_id!=str(held_item.get("id","")): return
	survey_ui.set_result(result); mutation_pending=false; action_pending=false; ui.set_pending(false); held_status.text=""; held_status.visible=false

func set_hip_tool(item: Dictionary) -> void:
	var same:=str(item.get("id",""))==str(hip_tool.get("id","")) and str(item.get("template",""))==str(hip_tool.get("template",""))
	hip_tool=item.duplicate(true)
	if not same:
		clear_model(hip_model); hip_model=null
		if not hip_tool.is_empty():
			var mesh:=assets.instance(str(hip_tool.get("template","")),0.18,hip_tool.get("customization",{}))
			if mesh!=null:
				hip_model=Node3D.new(); add_child(hip_model); hip_model.top_level=true; hip_model.add_child(mesh)
	if is_instance_valid(hip_model): hip_model.global_transform=hip_transform()
	if is_instance_valid(hologram) and hologram.active: set_equipment_context(equipment_avatar,current_equipment)
	sync_presentation()

func hip_transform() -> Transform3D:
	if not is_instance_valid(rig): return Transform3D.IDENTITY
	return preload("res://scripts/body_grab_anchor.gd").hip(rig.get_node("XRCamera3D"),rig,offhand)

func find_hit(finger: Dictionary) -> Dictionary:
	if finger.is_empty(): return {}
	var best: Dictionary={}
	for index in range(surfaces.size()):
		var surface: Dictionary=surfaces[index]
		if not surface.mesh.visible: continue
		var hit: Dictionary=follower.point(surface.mesh.global_transform,surface.meters,Vector2(surface.viewport.size),finger.get("ray_origin",finger.tip),finger.direction)
		if hit.get("valid",false) and (best.is_empty() or float(hit.distance)<float(best.distance)): hit.surface=index; best=hit
	return best

func tool_pointer_pose(controller: XRController3D) -> Dictionary:
	return preload("res://scripts/rendered_finger_pointer.gd").pose(avatar,"left" if controller==controller_for("left") else "right",rig,controller)

func vehicle_hand_busy(side: String)->bool:
	return is_instance_valid(body) and ((is_instance_valid(body.get("vehicles")) and body.vehicles.hand_busy(side)) or (is_instance_valid(body.get("space")) and body.space.hand_busy(side)))

func set_combat_loadout_context(value:Dictionary,callback:Callable)->void:
	loadout_request=callback
	if is_instance_valid(hologram):hologram.set_ability_context(value)

func sample_ability_editor(click:bool,pose:Transform3D,grip:float,trigger:float,tracked:bool,pointer:Dictionary={})->void:
	var edge:=click and not ability_stick_down
	ability_stick_down=click
	if not is_instance_valid(hologram) or not hologram.active:return
	if not is_instance_valid(hologram.ability_editor):return
	var button_hovered:bool=hologram.sample_mode_button(pointer,trigger,tracked and not action_pending and equipment_drag.is_empty() and not hologram.ability_editor.pending and hologram.ability_editor.drag.is_empty())
	if edge and tracked and not action_pending and equipment_drag.is_empty():hologram.ability_editor.toggle()
	hologram.ability_editor.sample(pose,grip,trigger,tracked and not action_pending and not button_hovered,pointer)
	if hologram.ability_editor.active:
		held_trigger_armed=false;equipment_grip_armed=false;main_grip_armed=false;grip_armed=false

func request_loadout(proposal:Dictionary)->void:
	if loadout_pending:return
	if not loadout_request.is_valid():
		hologram.ability_editor.finish(false,"A live CoreCU weapon snapshot is required.");return
	loadout_pending=true
	var result:Dictionary=await loadout_request.call(proposal)
	loadout_pending=false
	if is_instance_valid(hologram) and is_instance_valid(hologram.ability_editor):hologram.ability_editor.finish(result.get("success",false),str(result.get("error","CoreCU rejected the loadout.")))
