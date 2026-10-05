extends SceneTree
## One actual authored placement per exported primary weapon; ambient visuals only.
const NPCs = preload("res://scripts/ambient_npcs.gd")
var errors: Array[String] = []
var evidence: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)

func run() -> void:
	var npcs := NPCs.new()
	root.add_child(npcs)
	npcs.set_process(false)
	check(npcs.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json")),"NPC source catalog missing")
	var seen := {}
	var eligible := 0
	for entry: Dictionary in npcs.manifest.instances:
		if not entry.has("source_primary_weapon"): continue
		var descriptor: Dictionary = npcs.catalog.races.get(str(entry.appearance_id),{})
		var sources: Array = []
		for source: Dictionary in descriptor.get("rigid_equipment",[]):
			if str(source.get("template","")).begins_with("object/weapon/"): sources.append(source)
		if sources.is_empty(): continue
		eligible += 1
		var key := str(sources[0].template)
		if seen.has(key): continue
		seen[key] = true
		npcs.instantiate_entry(entry)
		check(npcs.records.has(str(entry.id)),"Authored weapon NPC failed to instantiate: "+str(entry.mobile))
		if not npcs.records.has(str(entry.id)): continue
		var record: Dictionary = npcs.records[str(entry.id)]
		var actor: Node3D = record.avatar
		await process_frame
		check(record.equipment_failures.is_empty(),"Authored primary equipment failed: "+key)
		var found := false
		for item: Dictionary in record.equipment:
			if str(item.source.template)!=key: continue
			found = true
			check(item.instance.mesh.get_surface_count()>0,"Primary weapon mesh is empty")
			check(not item.attachment.override_pose,"Primary weapon overrides original NPC skeleton")
			var expected: Transform3D = actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(item.bone_index) * item.local_transform
			check(item.instance.global_transform.is_equal_approx(expected),"Primary weapon differs from authored bone/transform")
			evidence.append({"mobile":entry.mobile,"appearance_id":entry.appearance_id,"template":key,"bone":item.source.bone,"source_primary_weapon":entry.source_primary_weapon,"surfaces":item.instance.mesh.get_surface_count()})
		check(found,"Declared primary weapon did not attach: "+key)
		npcs.equipment.release(record.equipment)
		actor.queue_free()
		npcs.records.erase(str(entry.id))
		await process_frame
	check(eligible>0 and evidence.size()>0,"No source primary weapon placements were exercised")
	check(npcs.report.failures.is_empty(),"Runtime reported authored equipment failures")
	check(npcs.equipment.statistics().attached_items==0,"Primary weapon residency references leaked")
	var result := {"test":"authored_npc_primary_weapon_equipment","passed":errors.is_empty(),"errors":errors,"eligible_placements":eligible,"unique_weapons_checked":evidence.size(),"equipment":evidence,"gpu_tested":false,"live_core3_equipment":false,"selection_scope":"deterministic original primary weapon-set choice for ambient presentation"}
	FileAccess.open("res://../runtime/evidence/npc-weapon-equipment-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("NPC_WEAPON_EQUIPMENT_SMOKE "+JSON.stringify(result))
	npcs.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
