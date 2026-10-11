extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const State=preload("res://combat/weapon_state.gd")
var errors:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var rig:=Rig.new();root.add_child(rig);rig.set_process(false);rig.set_physics_process(false);rig.assets.load_catalog()
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	for key in ["pistol_cdef","carbine_e11","rifle_e11","rifle_t21","heavy_rocket_launcher"]:
		var profile:Dictionary=catalog.weapons[key]
		var state:=State.new();check(state.configure(profile,profile.core3.certificationsRequired),"Real weapon profile configures: "+key)
		var visual:Node3D=rig.make_visual(profile);rig.add_child(visual)
		var record:Dictionary=rig.weapon_presentation(state,visual);var hud:Node3D=record.readout
		check(is_equal_approx(rad_to_deg(hud.rotation.x),-30) and hud.position.z>record.bounds.end.z,key+" indicator mounts on original rear at 30 degrees")
		check(visual.find_children("*","Label3D",true,false).is_empty(),key+" has no held stat text")
		var gun_pose:=visual.transform;var bounds:AABB=record.bounds
		state.rounds=int(profile.capacity)/2;state.mode="semi";hud.update_state(state,true)
		check(hud.visible and is_equal_approx(hud.report.fraction,float(state.rounds)/int(profile.capacity)),key+" capacity follows remaining shots")
		check(hud.report.mode_color==hud.SEMI_COLOR,key+" single shot is blue")
		state.mode="auto";hud.update_state(state,true)
		check(hud.report.mode_color==hud.RAPID_COLOR and hud.report.mode_bright,key+" automatic is steady red")
		state.mode="burst";var pulses:=0;var was_on:=false
		for frame in range(120):
			state.clock=frame*.01;hud.update_state(state,true)
			if hud.report.mode_bright and not was_on:pulses+=1
			was_on=hud.report.mode_bright
		check(pulses==3,key+" burst uses three red flashes")
		state.rounds=0;hud.update_state(state,true);check(not hud.fill.visible,key+" empty capacity has no fill")
		state.rounds=int(profile.capacity);hud.update_state(state,true);check(hud.report.fraction==1,key+" refill restores full bar")
		hud.update_state(state,false);check(not hud.visible,key+" holstered indicator hides")
		check(visual.transform==gun_pose and rig.visual_bounds(visual)==bounds,key+" readout never changes weapon pose or collision bounds")
		state.profile.charge_limited=true;state.profile.charges=40;state.rounds=40;state.profile.capacity=20
		hud.update_state(state,true);state.profile.charges=30;state.rounds=30;hud.update_state(state,true)
		check(hud.report.capacity==40 and is_equal_approx(hud.report.fraction,.75),key+" native charge bar depletes independently of magazine size")
		state.profile.kind="melee";hud.update_state(state,true);check(not hud.visible,key+" melee has no ammunition stats")
		visual.free()
	var charges:=State.new();var charged_profile:Dictionary=catalog.weapons.heavy_rocket_launcher.duplicate(true)
	charged_profile.charges=12;charges.configure(charged_profile,charged_profile.core3.certificationsRequired)
	var charged_visual:Node3D=rig.make_visual(charged_profile);rig.add_child(charged_visual)
	var charged_record:=rig.weapon_presentation(charges,charged_visual)
	check(charged_record.readout.report.capacity==12 and charged_record.readout.report.remaining==12,"Initial native charges override uninitialized magazine count")
	charged_visual.free()
	rig.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","headset_tested":false};print(JSON.stringify(report))
	FileAccess.open("res://../runtime/evidence/weapon-readout-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
