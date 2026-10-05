extends SceneTree
## Regression for the source-assigned outfits missing from four live band members.
const NPCs = preload("res://scripts/ambient_npcs.gd")
const EXPECTED := {"doikk_nats":4,"nalan_cheel":4,"tech_mor":4,"tedn_dahai":4,"figrin_dan":3}
var errors: Array[String] = []
var evidence: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func run() -> void:
	var npcs := NPCs.new()
	root.add_child(npcs)
	npcs.set_process(false)
	check(npcs.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json")),"NPC catalog could not be loaded")
	var seen := {}
	for entry: Dictionary in npcs.manifest.get("instances",[]):
		var mobile := str(entry.mobile)
		if not EXPECTED.has(mobile) or str(entry.get("building_object_id",""))!="1082874": continue
		seen[mobile] = true
		npcs.instantiate_entry(entry)
		check(npcs.records.has(str(entry.id)),"Band member failed to instantiate: "+mobile)
		if not npcs.records.has(str(entry.id)): continue
		var record: Dictionary = npcs.records[str(entry.id)]
		var actor: Node3D = record.avatar
		var equipment := 0
		for part: Dictionary in actor.loaded_parts:
			if part.scope=="equipment": equipment+=1
		check(equipment==int(EXPECTED[mobile]),"Wrong original clothing count for %s: %d" % [mobile,equipment])
		check(actor.skeleton.get_bone_count()==53,"Original Bith skeleton changed: "+mobile)
		for mesh: MeshInstance3D in actor.meshes:
			check(mesh.skin!=null and mesh.skin.get_bind_count()>0,"Missing skin binding: "+mobile)
			check(mesh.get_node_or_null(mesh.skeleton)==actor.skeleton,"Clothing/body points at the wrong skeleton: "+mobile)
			check(mesh.mesh!=null and mesh.mesh.get_surface_count()>0,"Empty NPC mesh: "+mobile)
		check(actor.animation_player!=null and not str(record.animation).is_empty(),"Source band animation missing: "+mobile)
		var changed := false
		if actor.animation_player!=null:
			var before: Array[Quaternion] = []
			for bone in range(actor.skeleton.get_bone_count()): before.append(actor.skeleton.get_bone_pose_rotation(bone))
			actor.animation_player.advance(0.37)
			for bone in range(actor.skeleton.get_bone_count()):
				changed = changed or before[bone].angle_to(actor.skeleton.get_bone_pose_rotation(bone))>0.001
		check(changed,"Original band clip did not animate skeleton: "+mobile)
		evidence.append({"mobile":mobile,"appearance_id":entry.appearance_id,"equipment_parts":equipment,"mesh_instances":actor.meshes.size(),"bones":actor.skeleton.get_bone_count(),"animation":record.animation,"animation_changed":changed})
	check(seen.size()==EXPECTED.size(),"The five original cantina band placements were not all checked")
	check(npcs.report.failures.is_empty(),"NPC runtime reported appearance failures")
	var result := {"test":"actual_cantina_band_source_outfits","passed":errors.is_empty(),"errors":errors,"members":evidence,"headset_tested":false,"gpu_tested":false}
	FileAccess.open("res://../runtime/evidence/cantina-npc-outfits.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("CANTINA_NPC_OUTFITS "+JSON.stringify(result))
	npcs.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
