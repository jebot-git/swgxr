extends SceneTree
var errors:Array[String]=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var origin:Node3D=load("res://xr/player_rig.tscn").instantiate();world.add_child(origin)
	var head:Node3D=origin.get_node("XRCamera3D");head.position=Vector3(.2,1.7,.1)
	var body:CharacterBody3D=origin.get_node("PlayerBody");body.set_physics_process(false)
	var bag:=preload("res://scripts/xr_inventory.gd").new();world.add_child(bag);bag.configure(origin,body);bag.set_process(false);bag.set_allowed(true)
	var weapon:=preload("res://combat/ranged_rig.gd").new();world.add_child(weapon);weapon.origin=origin;weapon.head=head;weapon.set_process(false);weapon.set_physics_process(false)
	var draws:Array=[];bag.tool_pickup_requested.connect(func(item):draws.append(item))
	bag.set_hip_tool({"id":"fixture-tool","template":"object/tangible/survey_tool/survey_tool_mineral.iff","tool_kind":"survey"})
	for dominant:String in ["right","left"]:
		weapon.dominant=dominant;bag.offhand="left" if dominant=="right" else "right"
		origin.rotation.y=.7;head.rotation=Vector3.ZERO
		var tool_pose:Transform3D=bag.hip_transform();var weapon_pose:Transform3D=weapon.grab_transform(1)
		var right_axis:Vector3=origin.global_basis.x
		check(signf((tool_pose.origin-head.global_position).dot(right_axis))==(-1.0 if bag.offhand=="left" else 1.0),"Production tool point follows offhand setting: "+dominant)
		check(signf((weapon_pose.origin-head.global_position).dot(right_axis))==(-1.0 if dominant=="left" else 1.0),"Production weapon point follows dominant setting: "+dominant)
		head.rotation=Vector3(.8,1.1,.25)
		check(bag.hip_transform().is_equal_approx(tool_pose) and weapon.grab_transform(1).is_equal_approx(weapon_pose),"Head rotation cannot shift or rotate either production grab zone: "+dominant)
		var before:int=draws.size()
		bag.set_busy(false);bag.main_grip_armed=false
		bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},tool_pose)
		bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,.9,{},tool_pose)
		check(draws.size()==before+1 and draws.back().get("gathering_hip",false),"Fresh opposite-hand grip recovers tool at mirrored production point: "+dominant)
		bag.set_busy(false)
	print(JSON.stringify({"checks":checks,"errors":errors,"passed":errors.is_empty(),"live_xr":false}));world.queue_free();await process_frame;await process_frame;quit(0 if errors.is_empty() else 1)
