extends SceneTree
const SliceFixture=preload("res://tests/slicing_controller_smoke.gd")
class Host extends SliceFixture.Host:
	var inventory_snapshot:Dictionary={}
class Body extends CharacterBody3D:
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app);app.stage=Node3D.new();app.add_child(app.stage)
	var rig:=XROrigin3D.new();app.add_child(rig)
	var head:=XRCamera3D.new();head.name="XRCamera3D";head.position.y=1.7;rig.add_child(head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;rig.add_child(hand)
	app.player=Body.new();rig.add_child(app.player)
	var bag:=preload("res://scripts/xr_inventory.gd").new();app.add_child(bag);bag.configure(rig,app.player);bag.set_process(false);bag.set_allowed(true)
	app.owned.template="object/tangible/container/loot/player_loot_crate.iff";app.owned.name="Native locked loot crate"
	var target:Dictionary=app.owned.duplicate(true);target.container_id="bag"
	bag.set_snapshot({"inventory":{"id":"bag","capacity":80,"occupied":1},"items":[target]})
	var shoulder:=Transform3D(Basis.IDENTITY,Vector3(-.19,1.54,.12))
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},shoulder)
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,.9,{},shoulder)
	check(bag.is_open and bag.bag_hand_side()=="right","Dominant hand grabs backpack at offhand shoulder")
	var hit:Dictionary={"surface":0,"pixel":Vector2(60,140)}
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,.9,hit,shoulder)
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,.9,.9,hit,shoulder)
	check(bag.held_item.get("id","")=="202" and bag.held_hand_side()=="left","Offhand retrieves secondary item while dominant hand holds bag")
	bag.set_open(false)
	app.services=SliceFixture.Services.new();app.services.host=app;app.add_child(app.services)
	app.gameplay_session=SliceFixture.Session.new();app.add_child(app.gameplay_session)
	var slicing:=preload("res://slicing/controller.gd").new();app.slicing=slicing;app.add_child(slicing);slicing.setup(app,bag);slicing.set_process(false);slicing.set_allowed(true)
	var knife:Dictionary={"id":"101","template":"object/tangible/slicing/slicing_laser_knife.iff","tool_kind":"slicing","equipped":true,"equipped_slots":["hold_r"]}
	app.inventory_snapshot={"equipment":[knife]};slicing.update_equipped_tool()
	check(slicing.owns_tool() and slicing.current_tool().id=="101" and slicing.tool_hand()==rig.get_node("RightHand") and bag.held_item.id=="202","Equipped knife remains separately usable while inventory target is held offhand")
	check(is_instance_valid(slicing.equipped_model) and slicing.tip().is_finite(),"Equipped knife uses original source model and physical tool tip")
	bag.held_model.global_position=Vector3(0,1,-.5)
	var target_model:=bag.held_model.get_child(0) as MeshInstance3D
	var contact:=target_model.to_global(target_model.mesh.get_aabb().get_center())
	var selected:Dictionary=slicing.target_at(contact)
	check(selected.get("id","")=="202","Knife can select target still held in secondary hand")
	app.reply=SliceFixture.response(true);slicing.begin(selected,contact,head.global_transform)
	for i in 3:await process_frame
	check(slicing.active() and bag.held_item.is_empty() and slicing.current_tool().get("id","")=="101","Native accepted lock frees target hand while keeping equipped knife available")
	slicing.reset();app.inventory_snapshot={"equipment":[]};bag.set_hip_tool(knife);slicing.hip_drawn=true;slicing.update_equipped_tool()
	check(slicing.current_tool().get("id","")=="101","Drawn native hip knife uses same independent tool path")
	var inspect:=preload("res://scout/creature_inspection.gd").new();app.add_child(inspect);inspect.set_physics_process(false)
	var chin:=Transform3D(Basis.IDENTITY,head.global_position+Vector3(0,-.15,-.09))
	check(inspect.sample(.3,head.global_transform,chin,.9,0,"201",true).is_empty(),"Brief chin contact does not inspect")
	check(inspect.sample(.36,head.global_transform,chin,.9,0,"201",true)=="201","Sustained free-hand pondering targets gazed creature")
	check(inspect.sample(2,head.global_transform,chin,.9,0,"201",true).is_empty(),"Holding pondering pose does not repeatedly request inspect")
	inspect.sample(.1,head.global_transform,chin,.9,0,"201",false)
	check(inspect.sample(.7,head.global_transform,chin,.9,.9,"201",true).is_empty(),"Closed trigger fist cannot be confused with pondering gesture")
	check(inspect.sample(.7,head.global_transform,chin,.9,0,"201",true)=="201","Fresh eligible chin gesture rearms after interruption")
	var actor:=preload("res://combat/live_actor.gd").new();app.add_child(actor);actor.set_process(false);actor.report={"appearance_status":"complete"};actor.record={"id":"201","name":"Native creature","dead":false,"kind":"creature","health":10,"max_health":10};actor.make_label(Vector3.ZERO)
	for relation in ["neutral","attackable","friendly","hostile"]:
		actor.record.relation=relation;actor.refresh_label()
		check(actor.label.modulate==preload("res://scripts/wrist_radar.gd").COLORS[relation] and actor.get_radar_contact().relation==relation,"Native "+relation+" gives matching nametag and minimap relation")
	actor.label.set_meta("spice_hostile_illusion",true);actor.record.relation="friendly";actor.refresh_label()
	check(actor.label.modulate==Color("ff2020") and actor.get_radar_contact().relation=="friendly","Relationship refresh preserves owner-only spice illusion without changing native relation")
	actor.label.remove_meta("spice_hostile_illusion");actor.refresh_label()
	check(actor.label.modulate==Color("00ff00"),"Cleared illusion restores latest native relationship color")
	var pad:=preload("res://scripts/xr_datapad.gd").new();app.add_child(pad);pad.configure(rig,app.player);pad.set_process(false);pad.set_allowed(true);pad.set_open(true);pad.ui.expanded=true;pad.resize_map(true);pad.global_position=Vector3(-.3,1,-.5);pad.orient_expanded_panels(head.global_position)
	for surface:Dictionary in pad.surfaces:
		check(surface.mesh.global_basis.z.dot((head.global_position-surface.mesh.global_position).normalized())>.999,"Expanded panel faces actual head from its own screen centre")
	var surface:Dictionary=pad.surfaces[0];var aim:Vector3=-surface.mesh.global_basis.z
	var fingertip:Vector3=surface.mesh.global_position-aim*.6
	var ray:Dictionary=pad.find_hit({"tip":fingertip,"direction":aim})
	check(not ray.is_empty() and Vector3(ray.world).distance_to(fingertip+aim*.6)<.001,"Long-range datapad hit remains collinear with actual fingertip ray")
	var report:Dictionary={"checks":checks,"errors":errors,"renderer":"dummy","headset_validated":false,"native_transport":"mocked","original_assets":true}
	FileAccess.open("res://../runtime/evidence/core5-client-interactions.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));app.free();await process_frame;quit(0 if errors.is_empty() else 1)
