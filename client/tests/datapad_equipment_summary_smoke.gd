extends SceneTree
const Summary=preload("res://scripts/player_summary_ui.gd")
class Harness extends "res://scripts/main.gd":
	var reply:Dictionary={}
	var calls:Array=[]
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return reply.duplicate(true)
	func refresh_inventory()->void:pass
	func sync_inventory_equipment(_force_statistics:=false)->void:pass
class Player extends CharacterBody3D:
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app:=Harness.new();root.add_child(app)
	app.xr_origin=XROrigin3D.new();app.add_child(app.xr_origin)
	var head:=XRCamera3D.new();head.name="XRCamera3D";app.xr_origin.add_child(head);head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var controller:=XRController3D.new();controller.name=side;app.xr_origin.add_child(controller)
	app.player=Player.new();app.xr_origin.add_child(app.player)
	app.avatar=load("res://scripts/avatar.gd").new();app.add_child(app.avatar);app.avatar.configure("human_male");app.avatar.set_process(false);app.avatar.hide()
	app.datapad=load("res://scripts/xr_datapad.gd").new();app.add_child(app.datapad);app.datapad.configure(app.xr_origin,app.player);app.datapad.set_process(false)
	app.inventory=load("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(app.xr_origin,app.player);app.inventory.set_process(false);app.inventory.set_allowed(true)
	app.inventory.unequip_requested.connect(app.unequip_inventory_item)
	app.datapad.summary_ui.equipment_requested.connect(app.open_datapad_equipment)
	app.datapad_character_id="fixture";app.datapad_account="fixture"
	var item:Dictionary={"id":"knife","name":"Stone knife","template":"object/weapon/melee/knife/knife_stone.iff","container_id":"fixture","equipped":true,"equipped_slots":["hold_r"],"unequip_available":true}
	var snapshot:Dictionary={"source_kind":"core3_inventory","backend":"core3","character_id":"fixture","inventory":{"id":"bag","capacity":80,"occupied":0},"items":[item],"equipment":[item]}
	app.inventory_snapshot=snapshot.duplicate(true);app.update_inventory_presentation()
	var summary:Dictionary={"version":1,"character_id":"fixture","name":"Zevrion · UI fixture","ham":[400,250,100],"max_ham":[900,750,600],"wounds":[5,7,9],"shock_wounds":42,"wallet":{"cash":1234,"bank":5678},"faction":{"allegiance":"rebel","status_name":"on_leave","rank":2,"standings":{"imperial":-200,"rebel":500}},"homepoints":{"residence":{"status":"available","name":"House","zone":"tatooine","position":[12,4,34]},"cloning":{"status":"unset"}},"armour":{"pieces":[{"name":"Chest armour","slots":["chest2"],"rating":1,"protection_percent":{"kinetic":35,"energy":42}}]}}
	app.update_datapad_summary(summary)
	var panel:Control=app.datapad.summary_ui
	check("Health  400 / 900" in panel.fields.text and "Wounds  5" in panel.fields.text,"Native HAM current/max/wounds remain separate")
	check("Cash  1234" in panel.fields.text and "Bank  5678" in panel.fields.text,"Native cash and bank displayed separately")
	check("Chest armour" in panel.fields.text and "Kinetic  35%" in panel.fields.text,"Armour preserves per-piece native protection")
	check("Rebel · On Leave" in panel.fields.text and "Imperial  -200" in panel.fields.text,"Faction standing signs and native status retained")
	check("RESIDENCE\nHouse · Tatooine\nX 12  Z 34" in panel.fields.text and "BOUND CLONING LOCATION\nNot set" in panel.fields.text,"Residence and clone bind have distinct labels")
	check(Summary.location_text({"status":"unavailable","id":"123"})=="Location unavailable","Unloaded home reference never appears unset")
	check(not panel.bust.disabled and panel.clone.skeleton!=app.avatar.skeleton and panel.clone.report.meshes>0,"Clickable bust clones actual character meshes and independent frozen skeleton")
	var portrait:Node3D=panel.clone;app.update_datapad_summary(summary)
	check(panel.clone==portrait,"Repeated heartbeat summary does not rebuild unchanged appearance")
	var wrong_owner:=summary.duplicate(true);wrong_owner.character_id="another_character";app.update_datapad_summary(wrong_owner)
	check(panel.summary.is_empty() and panel.bust.disabled,"Other-owner summary cannot expose stats or a stale portrait")
	app.update_datapad_summary(null)
	check(panel.summary.is_empty(),"Absent native summary remains unknown rather than invented zeros")
	app.update_datapad_summary(summary)

	app.datapad.set_allowed(true);app.datapad.set_open(true)
	await process_frame;await process_frame
	var summary_surface:Dictionary=app.datapad.surfaces[2]
	var bust_pixel:Vector2=panel.bust.get_global_rect().get_center()
	var bust_local:=Vector3((bust_pixel.x/summary_surface.viewport.size.x-.5)*summary_surface.meters.x,(.5-bust_pixel.y/summary_surface.viewport.size.y)*summary_surface.meters.y,0)
	var bust_hit:Dictionary=app.datapad.find_hit({"tip":summary_surface.mesh.global_transform*(bust_local+Vector3(0,0,.15)),"direction":-summary_surface.mesh.global_basis.z})
	check(bust_hit.get("surface",-1)==2,"Rendered finger ray reaches the bust on the left summary surface")
	app.datapad.update_pointer(bust_hit,0);app.datapad.update_pointer(bust_hit,.9)
	await process_frame
	app.datapad.update_pointer(bust_hit,0)
	await process_frame
	check(not app.datapad.is_open and app.inventory.hologram.active and app.inventory.hologram.browsing and app.inventory.visible,"Click bust closes datapad and opens visible equipment hologram")
	check(app.inventory.blocks_combat() and app.inventory.interaction_active,"Equipment browse reserves controls even with empty hands")
	var marker:Vector3=app.inventory.hologram.markers.knife.global_position
	var off:=Transform3D(Basis.IDENTITY,Vector3(-.7,1,-.2));var grip:=Transform3D(Basis.IDENTITY,marker)
	app.inventory.update_gestures(true,head.global_transform,off,0,0,{},grip)
	app.inventory.update_gestures(true,head.global_transform,off,0,.9,{},grip)
	check(not app.inventory.equipment_drag.is_empty() and app.inventory.held_item.is_empty() and app.calls.is_empty() and app.inventory_snapshot.equipment.size()==1,"Grip creates only cosmetic drag; native item remains equipped")
	app.inventory.update_gestures(true,head.global_transform,off,0,0,{},grip)
	check(app.inventory.equipment_drag.is_empty() and app.inventory.hologram.browsing and app.calls.is_empty(),"Missed inventory drop cancels without a mutation")
	# Retry, open real backpack by shoulder, release into its original model.
	marker=app.inventory.hologram.markers.knife.global_position;grip.origin=marker
	app.inventory.update_gestures(true,head.global_transform,off,0,0,{},grip)
	app.inventory.update_gestures(true,head.global_transform,off,0,.9,{},grip)
	off.origin=head.position+Vector3(-.19,-.16,.12)
	app.inventory.update_gestures(true,head.global_transform,off,.9,.9,{},grip)
	check(app.inventory.is_open and is_instance_valid(app.inventory.bag_model),"Free-hand shoulder gesture opens backpack while equipment preview is held")
	grip.origin=app.inventory.bag_model.global_position;app.reply={"ok":false,"error":"Inventory full"}
	app.inventory.update_gestures(true,head.global_transform,off,.9,0,{},grip)
	check(app.calls.size()==1 and app.calls[0].path=="/inventory/unequip" and app.inventory.action_pending,"Release inside backpack makes one authoritative unequip request")
	await process_frame;await process_frame
	check(app.inventory_snapshot.equipment.size()==1 and not app.inventory.action_pending,"Server refusal preserves equipped item and unlocks interaction")
	app.inventory.set_open(false);app.inventory.browse_equipment(head.global_transform)
	marker=app.inventory.hologram.markers.knife.global_position;grip.origin=marker
	app.inventory.update_gestures(true,head.global_transform,off,0,0,{},grip);app.inventory.update_gestures(true,head.global_transform,off,0,.9,{},grip)
	app.inventory.update_gestures(true,head.global_transform,off,.9,.9,{},grip)
	var returned:=snapshot.duplicate(true);returned.items[0].equipped=false;returned.items[0].equipped_slots=[];returned.items[0].container_id="bag";returned.equipment=[]
	app.reply={"ok":true,"source_kind":"core3_inventory_unequip","mutation":{"success":true},"inventory":returned}
	grip.origin=app.inventory.bag_model.global_position;app.inventory.update_gestures(true,head.global_transform,off,.9,0,{},grip)
	await process_frame;await process_frame
	check(app.inventory_snapshot.equipment.is_empty() and app.inventory_snapshot.items[0].container_id=="bag" and app.inventory.held_item.is_empty(),"Confirmed drop adopts native inventory and leaves item in bag, not hand")
	check(app.calls.size()==2,"No automatic duplicate mutation on released grip")
	app.inventory.set_open(false);app.inventory_snapshot=snapshot.duplicate(true);app.update_inventory_presentation();app.inventory.browse_equipment(head.global_transform)
	marker=app.inventory.hologram.markers.knife.global_position;grip.origin=marker
	app.inventory.update_gestures(true,head.global_transform,off,0,0,{},grip);app.inventory.update_gestures(true,head.global_transform,off,0,.9,{},grip)
	app.inventory.update_gestures(false,head.global_transform,off,.9,.9,{},grip)
	check(app.inventory.equipment_drag.is_empty() and app.calls.size()==2,"Tracking loss cancels preview without native unequip")
	var denied:=snapshot.duplicate(true);denied.items[0].unequip_available=false;denied.equipment[0].unequip_available=false;denied.equipment[0].unequip_block_reason="Inventory full"
	app.inventory_snapshot=denied;app.update_inventory_presentation();app.inventory.browse_equipment(head.global_transform)
	marker=app.inventory.hologram.markers.knife.global_position;grip.origin=marker
	app.inventory.update_gestures(true,head.global_transform,off,0,0,{},grip);app.inventory.update_gestures(true,head.global_transform,off,0,.9,{},grip)
	check(app.inventory.equipment_drag.is_empty() and "Inventory full" in app.inventory.hologram.labels[1].text and app.calls.size()==2,"Native blocked equipment cannot begin a drag and shows its reason")
	app.inventory.cancel_interaction()
	check(head.position==Vector3(0,1.7,0) and app.avatar.skeleton!=panel.clone.skeleton,"UI leaves raw head and source avatar independent")

	# Layout and scroll operate on the separate left surface in both sizes.
	app.datapad.set_open(true)
	await process_frame;await process_frame
	check(panel.scroll.size.y>100 and panel.scroll.get_v_scroll_bar().max_value>panel.scroll.size.y,"Long native statistics remain scrollable within wrist panel")
	app.datapad.update_stick_capture(Vector2(0,-1),{"surface":2,"pixel":Vector2(50,500)},.25)
	check(panel.scroll.scroll_vertical>0,"Pointing stick scrolls left statistics independently")
	for expanded in [false,true]:
		app.datapad.resize_map(expanded)
		check(app.datapad.surfaces[2].mesh.position.x < -app.datapad.surfaces[0].meters.x*.5,"Summary remains to left without shrinking main content")
	if "--capture" in OS.get_cmdline_user_args():
		check(RenderingServer.get_current_rendering_method()=="forward_plus","Capture uses Vulkan Forward+")
		var overlay:=CanvasLayer.new();app.add_child(overlay)
		var caption:=Label.new();overlay.add_child(caption);caption.text="Desktop UI fixture · actual original character bust · synthetic statistics";caption.position=Vector2(20,8)
		root.size=Vector2i(1280,800)
		var canvas:=SubViewport.new();canvas.size=Vector2i(1920,780);canvas.transparent_bg=true;canvas.disable_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;app.add_child(canvas)
		var composite:=TextureRect.new();overlay.add_child(composite);composite.texture=canvas.get_texture();composite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;composite.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;composite.position=Vector2(0,40);composite.size=Vector2(1280,740)
		for i in range(3):
			var control:Control=app.datapad.surfaces[i].control;control.reparent(canvas);control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			control.position=Vector2(20 if i==2 else 470 if i==0 else 1380,20);control.size=Vector2(430 if i==2 else 890 if i==0 else 520,740)
		panel.scroll.scroll_vertical=0
		for i in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/datapad-equipment-summary.png"))
	var result:Dictionary={"checks":checks,"passed":errors.is_empty(),"errors":errors,"native_actions_mocked":true,"headset_tested":false,"gpu_tested":"--capture" in OS.get_cmdline_user_args()}
	FileAccess.open("res://../runtime/evidence/datapad-equipment-summary.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result))
	app.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
