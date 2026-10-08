extends SceneTree
## Runtime pose regression using original assets; not live headset validation.
const Inventory = preload("res://scripts/xr_inventory.gd")
class Player extends CharacterBody3D:
	var feedback=preload("res://combat/player_feedback.gd").new()
	func set_interface_capture(_move: bool, _turn: bool) -> void: pass
var errors: Array[String]=[]
var checks:=0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: errors.append(message);push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var head:=XRCamera3D.new();head.name="XRCamera3D";head.position=Vector3(0,1.5,0.65);rig.add_child(head)
	var trackers: Array=[]
	for side in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.name=side+"_hand";tracker.type=XRServer.TRACKER_CONTROLLER
		tracker.hand=XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		XRServer.add_tracker(tracker);trackers.append(tracker)
		var hand:=XRController3D.new();hand.name=side.capitalize()+"Hand";hand.tracker=tracker.name;hand.pose="grip";rig.add_child(hand)
	var player:=Player.new();rig.add_child(player)
	var bag:=Inventory.new();world.add_child(bag);bag.configure(rig,player);bag.set_process(false);bag.set_allowed(true);bag.set_open(true)
	var max_error:=0.0
	for side in ["left","right"]:
		bag.offhand=side;bag.rebuild_bag()
		var hand: XRController3D=rig.get_node(side.capitalize()+"Hand")
		for pitch in [-1.2,0.0,1.2]:
			hand.transform=Transform3D(Basis.from_euler(Vector3(pitch,0.4,0.8)),Vector3(-0.35 if side=="left" else 0.35,1.45,-0.25))
			head.position+=Vector3(.06,0,-.025)
			rig.rotation.y+=.3
			bag.refresh_hand_presentations()
			var expected_panel:Transform3D=Transform3D(Basis.IDENTITY,bag.bag_ui_anchor)*bag.surfaces[0].mesh.transform
			check((bag.bag_model.global_transform.affine_inverse()*bag.surfaces[0].mesh.global_transform).is_equal_approx(expected_panel),"Screen stays attached to original bag geometry across head/hand/origin changes")
			check(bag.surfaces[0].mesh.global_basis.y.is_equal_approx(Vector3.UP),"Inventory screen cannot roll with controller")
			check(bag.surfaces[1].mesh.global_basis.y.is_equal_approx(Vector3.UP),"Tilted info pane stays upright with bag")
			max_error=maxf(max_error,(bag.bag_model.global_transform*bag.bag_corner).distance_to(hand.global_position))
			check(bag.bag_model.global_basis.y.is_equal_approx(Vector3.UP),"Bag stays vertical despite %s controller pitch/roll"%side)
			check(bag.bag_model.global_basis.z.dot((head.global_position-hand.global_position).slide(Vector3.UP).normalized())>0.9999,"Original bag front faces player for %s hand"%side)
		var mesh: MeshInstance3D=bag.bag_model.get_child(0)
		var touches:=false
		for surface in range(mesh.mesh.get_surface_count()):
			for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if (mesh.transform*vertex).distance_to(bag.bag_corner)<0.00001: touches=true
		check(touches,"Corner grip touches original geometry, not empty space above a side pocket")
		check((bag.bag_corner.x<0)==(side=="left"),"Opposite handedness uses opposite upper corner without mirroring geometry")
	check(max_error<0.00001,"Upper corner stays attached to grip for both hands")
	rig.transform=Transform3D.IDENTITY
	bag.offhand="left";bag.clear_model(bag.bag_model);bag.bag_model=null;bag.rebuild_bag()
	var left: XRController3D=rig.get_node("LeftHand")
	var main: XRController3D=rig.get_node("RightHand")
	var grip:=Transform3D(Basis(Vector3.RIGHT,deg_to_rad(65)),Vector3(0.3,1.25,-0.2))
	var aim:=Transform3D(Basis(Vector3.UP,-0.55),grip.origin+Vector3(0,0,-0.12))
	trackers[1].set_pose("grip",grip,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	trackers[1].set_pose("aim",aim,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var left_grip:=Transform3D(Basis.from_euler(Vector3(0.9,-0.4,0.6)),Vector3(-0.4,1.45,-0.2))
	trackers[0].set_pose("grip",left_grip,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await process_frame
	for template in ["object/tangible/crafting/station/weapon_tool.iff","object/weapon/ranged/pistol/pistol_cdef.iff"]:
		bag.take_item({"id":"pose-test","template":template})
		check(bag.held_model.global_position.is_equal_approx(main.global_position),"Pickup keeps grip position, not displaced aim origin")
		check(bag.held_model.global_basis.is_equal_approx(aim.basis),"Pickup uses runtime aim, correcting the 65-degree controller grip offset")
		bag.clear_held()
	bag.take_item({"id":"pose-test","template":"object/tangible/crafting/station/weapon_tool.iff"})
	rig.global_transform=Transform3D(Basis(Vector3.UP,0.8),Vector3(2,0,-1))
	bag.refresh_hand_presentations()
	check(bag.held_model.global_basis.is_equal_approx((rig.global_transform*aim).basis),"Origin turns preserve runtime item orientation")
	check((bag.bag_model.global_transform*bag.bag_corner).distance_to(left.global_position)<0.00001,"Locomotion preserves bag corner contact")
	check(main.transform.is_equal_approx(grip),"Presentation never rotates or moves the tracked controller")
	check(RenderingServer.frame_pre_draw.is_connected(bag.refresh_hand_presentations),"Final hand poses refresh immediately before rendering")
	var drops: Array=[];bag.item_drop_requested.connect(func(_item,pose):drops.append(pose))
	bag.set_open(false);bag.main_grip_armed=false
	var fresh:=Transform3D(grip.basis,main.global_position+Vector3(0.1,0,0))
	bag.update_gestures(true,head.global_transform,left.global_transform,0,0,{},fresh)
	check(drops.size()==1 and drops[0].origin.is_equal_approx(fresh.origin) and drops[0].basis.is_equal_approx((rig.global_transform*aim).basis),"Release retains corrected orientation at current grip position")
	var tracked:=preload("res://scripts/tracked_avatar.gd").new();world.add_child(tracked);tracked.set_process(false);tracked.body=player;tracked.camera=head;tracked.rig=rig
	var raw_before:=main.global_transform;var body_before:=player.global_transform;var head_before:=head.global_transform
	for id in ["yarrock","muon_gold"]:
		player.feedback.spice.observe(preload("res://tests/spice_smoke.gd").envelope(id,"withdrawal",900,1))
		check(tracked.hand_target(main,"right")!=raw_before,"Empty tracked-avatar hand has local spice tremor: "+id)
		bag.take_item({"id":"spice-tool","template":"object/tangible/crafting/station/weapon_tool.iff"});bag.refresh_hand_presentations()
		check(bag.held_model.global_transform.is_equal_approx(bag.item_hand_pose(main,raw_before)) and bag.held_model.global_transform!=Transform3D((rig.global_transform*aim).basis,raw_before.origin),"Original held crafting tool shares visual hand tremor: "+id)
		check(main.global_transform==raw_before and player.global_transform==body_before and head.global_transform==head_before,"Spice hand tremor leaves raw controller, HMD and physics body unchanged")
		bag.clear_held()
	player.feedback.spice.reset();tracked.free()
	if "--capture" in OS.get_cmdline_user_args():
		rig.global_transform=Transform3D.IDENTITY;bag.set_open(true);bag.refresh_hand_presentations()
		for surface: Dictionary in bag.surfaces:surface.mesh.visible=false
		bag.held_status.visible=false;bag.dot.visible=false
		var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("101b27");environment.environment=settings;world.add_child(environment)
		for hand in [left,main]:
			var marker:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=0.012;sphere.height=0.024;marker.mesh=sphere
			var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("71efff");marker.material_override=material;world.add_child(marker);marker.global_position=hand.global_position
		var caption:=Label.new();caption.text="Original bag and crafting tool · cyan markers = grip positions\nDesktop Vulkan · mocked controller tracking";caption.position=Vector2(24,24);world.add_child(caption)
		head.current=true;head.fov=65
		for i in range(6):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/inventory-hand-poses-vulkan.png")
	var report: Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"maximum_corner_error_m":max_error,"mocked_tracking":true,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/inventory-hand-poses.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	world.free()
	for tracker in trackers:XRServer.remove_tracker(tracker)
	quit(0 if errors.is_empty() else 1)
