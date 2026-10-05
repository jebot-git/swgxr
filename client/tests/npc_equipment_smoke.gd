extends SceneTree
## Actual source instruments + band skeletons; no mocked replacement meshes.
const NPCs = preload("res://scripts/ambient_npcs.gd")
const EXPECTED := {"doikk_nats":"fizz","figrin_dan":"kloo_horn","nalan_cheel":"bandfill","tedn_dahai":"fanfar","tech_mor":""}
var errors: Array[String] = []
var members: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)

func has_collider(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D: return true
	for child in node.get_children():
		if has_collider(child): return true
	return false

func run() -> void:
	var npcs := NPCs.new()
	root.add_child(npcs)
	npcs.set_process(false)
	check(npcs.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json")),"NPC source catalog missing")
	var references: Array = []
	var actors: Array = []
	var first_item := {}
	var first_actor: Node3D
	for entry: Dictionary in npcs.manifest.instances:
		var mobile := str(entry.mobile)
		if not EXPECTED.has(mobile) or str(entry.get("building_object_id",""))!="1082874": continue
		npcs.instantiate_entry(entry)
		check(npcs.records.has(str(entry.id)),"Source NPC did not instantiate: "+mobile)
		if not npcs.records.has(str(entry.id)): continue
		var record: Dictionary = npcs.records[str(entry.id)]
		var actor: Node3D = record.avatar
		actors.append(weakref(actor))
		actor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.skeleton.force_update_all_bone_transforms()
		await process_frame
		var required := 0 if str(EXPECTED[mobile]).is_empty() else 1
		check(record.equipment.size()==required,"Wrong authored rigid item count: "+mobile)
		check(record.equipment_failures.is_empty(),"Rigid equipment failed: "+mobile)
		check(actor.skeleton.get_bone_count()==53,"Equipment changed original skeleton: "+mobile)
		check(actor.global_position.is_equal_approx(npcs.to_global(npcs.vec(entry.position))),"Equipment moved authored NPC placement: "+mobile)
		var motion := false
		var equipment_evidence: Array = []
		for item: Dictionary in record.equipment:
			var attachment: BoneAttachment3D = item.attachment
			var instance: MeshInstance3D = item.instance
			references.append(weakref(attachment))
			references.append(weakref(instance))
			check(not attachment.override_pose,"Equipment attachment overrides source bone pose")
			check(attachment.get_parent()==actor.skeleton,"Equipment is not owned by original skeleton")
			check(not has_collider(attachment),"Ambient equipment gained gameplay collision")
			check(instance.mesh!=null and instance.mesh.get_surface_count()>0,"Empty original equipment mesh")
			check(str(item.source.template).ends_with(str(EXPECTED[mobile])+".iff"),"Wrong source instrument: "+mobile)
			check(item.source.bone=="hold_r" and not str(item.source.get("source_arrangement","")).is_empty(),"Source slot/bone provenance lost")
			var expected: Transform3D = actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(item.bone_index) * item.local_transform
			check(instance.global_transform.is_equal_approx(expected),"Source attachment transform mismatch: "+mobile)
			var before := instance.global_transform
			actor.animation_player.advance(0.37)
			actor.skeleton.force_update_all_bone_transforms()
			await process_frame
			expected = actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(item.bone_index) * item.local_transform
			check(instance.global_transform.is_equal_approx(expected),"Equipment failed to inherit animated bone transform: "+mobile)
			motion = not instance.global_transform.is_equal_approx(before)
			check(motion,"Instrument did not follow original band clip: "+mobile)
			equipment_evidence.append({"template":item.source.template,"bone":item.source.bone,"source_arrangement":item.source.source_arrangement,"local_transform":str(item.local_transform),"motion_inherited":motion,"surfaces":instance.mesh.get_surface_count()})
			if first_item.is_empty():
				first_item = item
				first_actor = actor
		members.append({"mobile":mobile,"rigid_items":record.equipment.size(),"source_position":entry.position,"animation":record.animation,"equipment":equipment_evidence})
	check(members.size()==5,"Five authored cantina band members were not checked")
	check(not first_item.is_empty(),"No original instrument available for cache/validation tests")
	if not first_item.is_empty():
		var duplicate := npcs.equipment.attach(first_actor,[first_item.source],npcs.catalog_path.get_base_dir(),true)
		check(duplicate.items.size()==1 and duplicate.items[0].instance.mesh==first_item.instance.mesh,"Repeated equipment did not share native mesh/material resources")
		npcs.equipment.release(duplicate.items)
		var bad: Dictionary = first_item.source.duplicate(true)
		bad.bone = "missing_source_bone"
		var rejected := npcs.equipment.attach(first_actor,[bad],npcs.catalog_path.get_base_dir(),true)
		check(rejected.items.is_empty() and rejected.failures.size()==1,"Missing source bone was silently guessed")
	check(npcs.report.failures.is_empty(),"Runtime reported source attachment failures")
	var cache_before: Dictionary = npcs.equipment.statistics()
	check(cache_before.attached_items==4,"Unexpected authored equipment ownership count")
	npcs.update_observer(Vector3(100000,100000,100000))
	await process_frame
	await process_frame
	for reference: WeakRef in references: check(reference.get_ref()==null,"Equipment outlived NPC residency")
	for reference: WeakRef in actors: check(reference.get_ref()==null,"NPC outlived residency removal")
	check(npcs.equipment.statistics().attached_items==0,"Equipment cache references leaked on residency removal")
	var result := {"test":"source_npc_rigid_equipment","passed":errors.is_empty(),"errors":errors,"members":members,"cache":cache_before,"after_unload":npcs.equipment.statistics(),"gpu_tested":false,"live_core3_equipment":false,"tech_mor_policy":"Source outfit has no held item; no instrument invented"}
	FileAccess.open("res://../runtime/evidence/npc-equipment-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("NPC_EQUIPMENT_SMOKE "+JSON.stringify(result))
	npcs.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
