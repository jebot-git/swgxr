extends SceneTree
## Capacity audit only. Full-entry Vulkan validation must check renderer errors.
const SLOT_BYTES := 16
const INSTANCE_SLOTS := 16
const ACTOR_AND_TRANSIENT_RESERVE := 4096
const SOURCE := "https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/storage_rd/material_storage.cpp"

func _initialize() -> void:
	var config := ConfigFile.new()
	var errors: Array[String] = []
	if config.load("res://project.godot") != OK:
		push_error("Project configuration unreadable")
		quit(1)
		return
	var global_slots := 0
	for name: String in config.get_section_keys("shader_globals"):
		var definition: Dictionary = config.get_value("shader_globals",name)
		var type := str(definition.type)
		if type.begins_with("sampler"): continue
		global_slots += 2 if type in ["color","mat2"] else (3 if type in ["mat3","transform_2d"] else (4 if type in ["mat4","transform"] else 1))
	var slots := int(ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size"))
	var capacity := int((slots-global_slots)/INSTANCE_SLOTS)
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/tatooine_world/world.json"))
	var stage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/mos_eisley/scene.json"))
	var world_count := int(world.statistics.instances)
	var retained_count: int = stage.instances.size()
	var conservative_required: int = world_count+retained_count+ACTOR_AND_TRANSIENT_RESERVE
	if capacity < conservative_required:
		errors.append("Instance shader buffer cannot cover imported world plus actor/transient reserve")
	var report := {"test":"shader_instance_budget","passed":errors.is_empty(),"errors":errors,"gpu_allocation_tested":false,"godot_commit":Engine.get_version_info().get("hash",""),"buffer_slots":slots,"slot_bytes":SLOT_BYTES,"slots_per_geometry_instance":INSTANCE_SLOTS,"global_slots":global_slots,"capacity_instances":capacity,"gpu_bytes":slots*SLOT_BYTES,"cpu_value_bytes":slots*SLOT_BYTES,"cpu_usage_bytes":slots*4,"cpu_dirty_region_bytes":1+int(slots/1024),"whole_world_instance_records":world_count,"retained_stage_records":retained_count,"actor_and_transient_instance_reserve":ACTOR_AND_TRANSIENT_RESERVE,"conservative_required_instances":conservative_required,"remaining_capacity":capacity-conservative_required,"formula":"floor((buffer_slots - global_slots) / 16); GPU_bytes = buffer_slots * 16","source_urls":[SOURCE,"https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/storage_rd/material_storage.h","https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/shader_language.h","https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-rendering-limits-global-shader-variables-buffer-size"],"scope":"Uniform storage only; not a draw-call/LOD/frame-time capacity claim. Retained records conservatively double-count objects filtered by the streamer."}
	FileAccess.open("res://../runtime/evidence/shader-instance-budget.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SHADER_INSTANCE_BUDGET "+JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
