extends SceneTree
## Replay recorded real Core3 appearance onto an original tracked rig; no live XR.
class Harness extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var proof:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/image-design-native.json"))
	check(proof.get("passed",false),"Recorded native consent/payment proof passed")
	var before:Dictionary={};var after:Dictionary={}
	for row:Dictionary in proof.get("responses",[]):
		var response:Dictionary=row.get("response",{})
		if before.is_empty() and response.get("state",{}).has("appearance"):before=response.state.appearance
		if response.get("mutation",{}).get("committed",false):
			after=response.state.appearance;break
	check(not before.is_empty() and not after.is_empty(),"Native before/after appearances present")
	if before.is_empty() or after.is_empty():quit(1);return
	var app:=Harness.new();root.add_child(app);app.xr_requested=true
	app.xr_origin=load("res://xr/player_rig.tscn").instantiate();app.add_child(app.xr_origin)
	app.player=app.xr_origin.get_node("PlayerBody");app.player.set_physics_process(false)
	var head:XRCamera3D=app.xr_origin.get_node("XRCamera3D");head.position=Vector3(0,1.7,0)
	app.asset_status=Label.new();app.add_child(app.asset_status)
	app.tracked_avatar=load("res://scripts/tracked_avatar.gd").new();app.add_child(app.tracked_avatar)
	app.avatar=load("res://scripts/avatar.gd").new();app.tracked_avatar.add_child(app.avatar)
	var initial:Dictionary=before.duplicate(true);var hair:Dictionary=initial.get("hair",{}) if initial.get("hair") is Dictionary else {}
	initial.hair_template=hair.get("template","");initial.hair_customization=hair.get("customization",{})
	check(app.avatar.configure(str(initial.race),initial,initial.equipment).get("error","")=="","Original source avatar builds")
	check(app.tracked_avatar.configure(app.avatar,app.xr_origin),"Tracked rig configures")
	app.tracked_avatar.set_process(false);app.tracked_avatar.set_physics_process(false)
	app.vr_settings.standing_eye_height=1.72;app.tracked_avatar.set_standing_eye_height(1.72)
	var avatar_id:int=app.avatar.get_instance_id();var tracked_id:int=app.tracked_avatar.get_instance_id();var skeleton_id:int=app.avatar.skeleton.get_instance_id()
	var body_pose:Transform3D=app.player.transform;var head_pose:Transform3D=head.transform
	var hidden:Array=[str(initial.equipment[0].id)];app.avatar.set_equipment_visual_hidden(hidden,[])
	app.apply_native_appearance(after)
	check(app.avatar.get_instance_id()==avatar_id and app.tracked_avatar.get_instance_id()==tracked_id,"Avatar and tracked node references preserved")
	check(app.avatar.skeleton.get_instance_id()!=skeleton_id and app.tracked_avatar.skeleton==app.avatar.skeleton,"IK binds rebuilt original skeleton")
	check(app.avatar.report.get("equipment_complete",false),"Native arrangement metadata resolves all worn equipment")
	check(is_equal_approx(float(app.avatar.appearance.height),float(after.height)),"Native committed height reaches avatar")
	check(app.avatar.hidden_equipment_ids==hidden,"Held equipment hiding survives appearance change")
	check(is_equal_approx(app.tracked_avatar.standing_eye_height,1.72),"Standing height calibration survives new body appearance")
	check(app.player.transform==body_pose and head.transform==head_pose,"Appearance never moves physics body or HMD")
	var stable_id:int=app.avatar.skeleton.get_instance_id();app.apply_native_appearance(after)
	check(app.avatar.skeleton.get_instance_id()==stable_id,"Repeated status never rebuilds unchanged avatar")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"source":"recorded actual native CoreCU image design","renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/entertainment/image-avatar.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	app.free();await process_frame;quit(0 if failures.is_empty() else 1)
