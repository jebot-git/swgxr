extends SceneTree
# Run with godot --headless --xr-mode off --path client --script res://../tools/pets/verify_bounds.gd.
const MOUNTS:=["bantha_hue","dewback_hue","cu_pa_hue","carrion_spat_hue","falumpaset_hue","gronda_hue","bol_hue","thune_hue","brackaset_hue","snorbal_hue","kaadu_hue"]
var failures:Array=[]
var checks:=0
func _initialize()->void:call_deferred("run")
func run()->void:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/pets/body_bounds.json"))
	for name:String in MOUNTS:
		var template:="object/mobile/"+name+".iff"
		if not catalog.templates.has(template):failures.append({"missing_template":template});continue
		var source:Dictionary=catalog.templates[template]
		var avatar=load("res://scripts/avatar.gd").new()
		root.add_child(avatar)
		avatar.load_catalog(ProjectSettings.globalize_path("res://../"+source.source_catalog))
		for scale_value:float in [0.5,1.0,1.37]:
			avatar.configure(template,{"height":scale_value})
			avatar.animation_player.stop()
			avatar.skeleton.reset_bone_poses()
			avatar.skeleton.force_update_all_bone_transforms()
			var bone:int=avatar.skeleton.find_bone(source.head_bone)
			var actual:Vector3=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(bone).origin
			var expected:=Vector3(source.head_position[0],source.head_position[1],-source.head_position[2])*scale_value
			checks+=1
			if actual.distance_to(expected)>0.002:failures.append({"template":template,"scale":scale_value,"actual":str(actual),"expected":str(expected)})
		avatar.free()
	var result:={"checks":checks,"failures":failures,"headless":true,"purpose":"Original source head bounds agree with production Godot avatar skeleton and grounding at three scales"}
	FileAccess.open("res://../runtime/pets/bounds-godot-tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
