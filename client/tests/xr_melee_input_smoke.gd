extends "res://tests/xr_combat_input_smoke.gd"
func run() -> void:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/combat/catalog.json"))
	var origin:XROrigin3D=load("res://xr/player_rig.tscn").instantiate()
	var head_tracker:=XRPositionalTracker.new(); head_tracker.name="head"; head_tracker.type=XRServer.TRACKER_HEAD
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(head_tracker); trackers.append(head_tracker)
	var left:=controller("left"); var right:=controller("right")
	root.add_child(origin)
	var head:XRCamera3D=origin.get_node("XRCamera3D")
	var body=origin.get_node("PlayerBody"); body.set_physics_process(false); body.on_ground=true
	var rig:=Rig.new(); origin.add_child(rig)
	check(rig.configure(head,body,[catalog.weapons.knife_survival,catalog.weapons["2h_sword_maul"]],"right",origin),"Tracked melee rig")
	rig.set_physics_process(false); rig.set_process(false); rig.set_allowed(true)
	await process_frame
	pose(right,rig.grab_transform(1)); await process_frame; rig._physics_process(0.01)
	right.set_input("grip",0.9); await process_frame; rig._physics_process(0.01)
	check(rig.selected==0,"Dominant grip draws original knife from source hip mount")
	var hand:=Transform3D(Basis.IDENTITY,Vector3(0.25,1.3,-0.4))
	pose(right,hand); await process_frame; rig._physics_process(0.01)
	pose(left,hand); left.set_input("grip",0.9); await process_frame; rig._physics_process(0.01)
	check(rig.two_hands,"Nearby offhand grip engages knife support")
	var attached:Transform3D=rig.hand_target("left")
	pose(left,Transform3D(Basis(Vector3.UP,1),Vector3(-0.8,0.4,0.5)))
	await process_frame; rig._physics_process(0.01)
	check(rig.two_hands and rig.hand_target("left").is_equal_approx(attached),"Knife support hand stays attached while grip held")
	right.set_input("trigger",0.9); await process_frame; rig._physics_process(0.01)
	for i in range(30):
		origin.position.x+=0.05; origin.rotate_y(0.02)
		await process_frame; rig._physics_process(0.01)
	check(rig.weapons[0].state.fired==0,"Virtual movement and turning cannot charge melee travel")
	origin.transform=Transform3D.IDENTITY
	for i in range(18):
		hand.origin.x+=0.02; pose(right,hand)
		await process_frame; rig._physics_process(0.01)
	check(rig.weapons[0].state.fired==1,"Tracked motion qualifies while combat ready")
	check(rig.reticle.global_position.is_equal_approx(head.global_position-head.global_basis.z*3),"Tracked head owns melee reticle")
	right.invalidate_pose("grip"); await process_frame; rig._physics_process(0.01)
	check(rig.selected==-1 and not rig.reticle.visible,"Tracking loss stows and clears melee gate")
	right.set_input("grip",0); right.set_input("trigger",0); left.set_input("grip",0)
	pose(right,rig.grab_transform(2)); await process_frame; rig._physics_process(0.01)
	right.set_input("grip",0.9); await process_frame; rig._physics_process(0.01)
	check(rig.selected==1,"Dominant shoulder grip draws original maul")
	hand.origin=Vector3(0.25,1.3,-0.4); pose(right,hand); await process_frame; rig._physics_process(0.01)
	var support:=Transform3D(Basis.IDENTITY,rig.support_point(1)); pose(left,support)
	left.set_input("grip",0.9); await process_frame; rig._physics_process(0.01)
	check(rig.two_hands,"Maul hilt supports two hands")
	support.origin+=Vector3(0.08,0,0.03); pose(left,support); await process_frame; rig._physics_process(0.01)
	var weapon_pose:Transform3D=rig.weapons[1].visual.global_transform
	check((-weapon_pose.basis.y).normalized().dot((support.origin-hand.origin).normalized())>0.999,"Original melee hilt axis follows support grip")
	check(weapon_pose.origin.is_equal_approx(origin.get_node("RightHand").global_position),"Melee handle remains at dominant tracked hand")
	origin.queue_free(); await create_timer(0.2).timeout
	for tracker in trackers: XRServer.remove_tracker(tracker)
	var report:Dictionary={"test":"xr_melee_input","passed":errors.is_empty(),"checks":checks,"errors":errors,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/xr-melee-input-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); quit(0 if errors.is_empty() else 1)
