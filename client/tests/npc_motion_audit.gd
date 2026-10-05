extends SceneTree
const Actor=preload("res://combat/live_actor.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var row:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/evidence/alpha-grounding-regression/scientist-native-row.json")))
	var actor:=Actor.new();root.add_child(actor);actor.configure(row,"recorded",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"));actor.apply_record(row,Transform3D.IDENTITY,0.1,true);actor.set_process(false)
	var av=actor.visual
	var passed:=true
	for speed:float in [0.0,1.0,3.0,7.0,20.0,0.0]:
		var low:=INF;var high:=-INF
		for i:int in range(120):
			av.update_motion(1.0/60,speed,{"grounded":true,"velocity":Vector3(0,0,-speed)})
			av.animation_player.advance(1.0/60);av.skeleton.force_update_all_bone_transforms()
			var y:float=(av.skeleton.global_transform*av.skeleton.get_bone_global_pose(av.skeleton.find_bone("ltoe")).origin).y
			low=minf(low,y);high=maxf(high,y)
		passed=passed and low>=-0.05
		print(JSON.stringify({"speed":speed,"motion":av.motion_state,"low":low,"high":high}))
	print(JSON.stringify({"passed":passed,"source_template":row.template,"renderer":"dummy","headset_tested":false}));actor.free();quit(0 if passed else 1)
