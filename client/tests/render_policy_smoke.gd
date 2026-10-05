extends SceneTree
const Policy = preload("res://scripts/render_policy.gd")
func _initialize() -> void:
	var errors: Array[String] = []
	for descriptor in [["forward_plus","vulkan",false,true],["mobile","vulkan",false,false],["gl_compatibility","opengl3",false,false],["forward_plus","d3d12",false,false],["forward_plus","metal",false,false],["gl_compatibility","dummy",true,true]]:
		var result := Policy.assess(descriptor[0],descriptor[1],descriptor[2])
		if result.supported != descriptor[3]: errors.append(str(descriptor))
	var current := Policy.current()
	if not current.supported: errors.append("Unsupported actual renderer")
	print(JSON.stringify({"test":"render_policy","passed":errors.is_empty(),"errors":errors,"actual":current}))
	quit(0 if errors.is_empty() else 1)
