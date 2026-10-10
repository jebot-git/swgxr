extends "res://tests/xr_combat_input_smoke.gd"
const Target = preload("res://combat/training_target.gd")
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var origin:XROrigin3D=load("res://xr/player_rig.tscn").instantiate()
	var head_tracker:=XRPositionalTracker.new(); head_tracker.name="head"; head_tracker.type=XRServer.TRACKER_HEAD
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(head_tracker); trackers.append(head_tracker)
	var left:=controller("left"); var right:=controller("right")
	root.add_child(origin)
	var head:XRCamera3D=origin.get_node("XRCamera3D")
	var body=origin.get_node("PlayerBody"); body.set_physics_process(false); body.on_ground=true
	var rig:=Rig.new(); origin.add_child(rig)
	check(rig.configure(head,body,[catalog.weapons.knife_survival,catalog.weapons["2h_sword_maul"]],"right",origin),"Melee/unarmed rig")
	check(rig.configure_unarmed(catalog.unarmed),"Synthetic lab unarmed profile is explicit")
	rig.set_physics_process(false); rig.set_process(false); rig.set_allowed(true)
	var target:=Target.new(); root.add_child(target); target.position=Vector3(0,1.7,-2)
	var hand:=Transform3D(Basis.IDENTITY,Vector3(0.2,1.3,-0.3))
	var other:=Transform3D(Basis.IDENTITY,Vector3(-0.2,1.3,-0.3))
	pose(right,hand); pose(left,other)
	await physics_frame; await process_frame; rig._physics_process(0.01)
	check(not rig.reticle.visible and rig.selected==-1,"At peace hides unarmed targeting")
	check(target.hit_count==0,"Seeding empty hands cannot attack")
	check(not rig.unarmed_engaged("right") and not rig.unarmed_engaged("left"),"Both hands at peace with triggers released")
	right.set_input("trigger",0.9); await process_frame; rig._physics_process(0.01)
	check(rig.unarmed_engaged("right") and not rig.unarmed_engaged("left"),"Readiness belongs to each attacking hand")
	check(rig.hand_target("right")==null and rig.reticle.visible,"Unarmed does not attach or replace hand tracking")
	var tracked=preload("res://scripts/tracked_avatar.gd").new(); tracked.combat_rig=rig
	var fingers:Dictionary=tracked.finger_state(origin.get_node("RightHand"),"right")
	check(fingers.grip==1 and fingers.trigger==1,"Engaged fist closes avatar fingers")
	tracked.free()
	for i in range(30):
		origin.position.x+=0.02; origin.rotate_y(0.01); await process_frame; rig._physics_process(0.01)
	check(target.hit_count==0,"Virtual movement cannot charge punches")
	origin.transform=Transform3D.IDENTITY
	for i in range(24):
		hand.origin.x-=0.02; pose(right,hand); await process_frame; rig._physics_process(0.01)
	check(target.hit_count==1 and rig.unarmed.right.fired==1,"Right punch uses head target regardless of swing direction")
	left.set_input("trigger",0.9); await process_frame; rig._physics_process(0.01)
	for i in range(24):
		other.origin.y+=0.02; pose(left,other); await process_frame; rig._physics_process(0.01)
	check(target.hit_count==2 and rig.unarmed.left.fired==1,"Left punch has independent gesture gate")
	check(rig.unarmed.right.condition_damage==0 and rig.unarmed.left.condition_damage==0,"Fists incur no item durability wear")
	check(rig.unarmed.right.melee_thresholds(true)==rig.unarmed.right.melee_thresholds(false),"Fists never receive weapon support-grip bonus")
	check(rig.unarmed.right.melee_range_scale("crouched")==0.75 and rig.unarmed.right.melee_range_scale("prone")==0.5,"Unarmed retains melee posture penalties")
	check(rig.reticle.global_position.is_equal_approx(head.global_position-head.global_basis.z*3),"Unarmed reticle follows head")
	if "--capture" in OS.get_cmdline_user_args():
		pose(right,Transform3D(Basis.IDENTITY,Vector3(0.23,1.5,-0.6)))
		pose(left,Transform3D(Basis.IDENTITY,Vector3(-0.23,1.5,-0.6)))
		var environment:=WorldEnvironment.new(); var settings:=Environment.new()
		settings.background_mode=Environment.BG_COLOR; settings.background_color=Color(0.08,0.1,0.13)
		settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color.WHITE; settings.ambient_light_energy=0.8
		environment.environment=settings; root.add_child(environment)
		var light:=DirectionalLight3D.new(); root.add_child(light); light.rotation_degrees=Vector3(-35,-25,0)
		for i in range(5): await physics_frame; await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/unarmed-fists.png"))
	left.set_input("trigger",0); right.set_input("trigger",0); await process_frame; rig._physics_process(0.01)
	check(not rig.reticle.visible and not rig.unarmed_engaged("right"),"Trigger release immediately returns to peace")
	# Actual melee models use the exact same draw sockets and fitted carry path.
	for index in range(2):
		check(rig.weapons[index].visual.global_transform.is_equal_approx(rig.visual_stow_transform(index)),"Melee shares ranged visual stow rule")
		pose(right,rig.grab_transform(index+1)); right.set_input("grip",0); await process_frame; rig._physics_process(0.01)
		right.set_input("grip",0.9); await process_frame; rig._physics_process(0.01)
		check(rig.selected==index,"Melee uses ranged hip/shoulder retrieval")
		left.set_input("trigger",0.9); await process_frame; rig._physics_process(0.01)
		check(not rig.unarmed_engaged("left"),"Held weapon disables empty-hand combat")
		right.set_input("grip",0); left.set_input("trigger",0); await process_frame; rig._physics_process(0.01)
	# Refresh an actual player snapshot without accepting another player's stats.
	var live:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/melee-live-snapshot.json"))
	check(rig.configure_unarmed(live.unarmed),"Actual CoreCU player profile configures")
	check(rig.unarmed.right.profile.power==live.unarmed.power,"Actual resolved player Power preserved")
	var updated:Dictionary=live.unarmed.duplicate(true); updated.power+=20; updated.stance_recovery+=15
	check(rig.unarmed.right.refresh_player(updated),"Owned player stat refresh")
	check(rig.unarmed.right.sample_swing(0.01,true,false,"standing",Vector3.ZERO).is_empty(),"Refresh seeds a new spatial origin")
	updated.character_id="other"
	check(not rig.unarmed.right.refresh_player(updated),"Cross-player refresh rejected")
	rig.set_allowed(false)
	check(not rig.unarmed_engaged("left") and not rig.unarmed_engaged("right"),"Menu gate clears both punches")
	var original_head:=head.transform
	rig.set_allowed(true); right.set_input("trigger",0.9); await process_frame; rig._physics_process(0.01)
	check(rig.unarmed.right.fired==0 and head.transform==original_head,"Focus recovery seeds without attacking or moving tracked head")
	origin.queue_free(); target.queue_free(); await create_timer(0.2).timeout
	for tracker in trackers: XRServer.remove_tracker(tracker)
	var report:Dictionary={"test":"xr_unarmed_input","passed":errors.is_empty(),"checks":checks,"errors":errors,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/xr-unarmed-input-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); quit(0 if errors.is_empty() else 1)
