extends SceneTree
## Original NPC appearances/placements with actual starport and terrain imports.
## Ambient presentation only; no live server NPC authority or AI behavior.
const NPCs = preload("res://scripts/ambient_npcs.gd")
const StageLoader = preload("res://scripts/stage_loader.gd")
const Terrain = preload("res://scripts/terrain_stream.gd")
const World = preload("res://scripts/world_stream.gd")
var errors: Array[String] = []
var started := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)

func run() -> void:
	started = Time.get_ticks_msec()
	var interface := XRServer.find_interface("OpenXR")
	check(interface == null or not interface.is_initialized(), "NPC test requires --xr-mode off")
	var loader := StageLoader.new()
	var stage: Node3D = loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	root.add_child(stage)
	var terrain := Terrain.new()
	root.add_child(terrain)
	check(terrain.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"), loader.vec(loader.report.origin)), "Terrain configure failed")
	var world := World.new()
	root.add_child(world)
	check(world.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"), stage), "World configure failed")
	var observer: Vector3 = loader.vec(loader.report.spawn)
	terrain.update_observer(observer)
	world.update_observer(observer)
	var deadline := Time.get_ticks_msec() + 60000
	while not terrain.ready_near(observer) or not world.report.get("ready", false):
		if Time.get_ticks_msec() > deadline:
			check(false, "Original terrain/world loading timed out")
			break
		await process_frame
	for i in range(3):
		await physics_frame
	var npcs := NPCs.new()
	root.add_child(npcs)
	check(npcs.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json"), stage, terrain), "Original NPC catalog or placement manifest missing")
	npcs.update_observer(observer)
	deadline = Time.get_ticks_msec() + 60000
	while not npcs.report.ready:
		if Time.get_ticks_msec() > deadline:
			check(false, "Ambient NPC loading timed out")
			break
		await process_frame
	check(npcs.records.size() > 0 and npcs.records.size() <= npcs.max_instances, "Nearby source NPCs absent or resident budget exceeded")
	check(npcs.report.failures.is_empty(), "Original NPC appearance configuration failed")
	check(int(npcs.report.compatible_placements) == int(npcs.report.source_placements), "An authored NPC appearance remains unsupported")
	var source_cities := {}
	for entry: Dictionary in npcs.manifest.get("instances", []):
		source_cities[entry.source_file] = true
	check(source_cities.size() == 7, "Tatooine city placement coverage incomplete")
	var starport: Array = []
	var animation_changes := 0
	var heads_visible := true
	var source_records: Array = []
	var references: Array = []
	for record: Dictionary in npcs.records.values():
		var actor: Node3D = record.avatar
		var entry: Dictionary = record.entry
		references.append(weakref(actor))
		check(actor.skeleton.get_bone_count() > 0 and actor.meshes.size() > 0, "NPC lacks its original skinned model")
		check(actor.get_meta("source").template == entry.template, "NPC template provenance lost")
		var q: Array = entry.quaternion
		check(actor.quaternion.angle_to(Quaternion(q[0],q[1],q[2],q[3])) < 0.001, "Source NPC heading was changed")
		for mesh: MeshInstance3D in actor.meshes:
			heads_visible = heads_visible and mesh.layers == 1
			var expected := 0.0 if str(entry.cell_id).is_empty() else 1.0
			check(is_equal_approx(float(mesh.get_instance_shader_parameter("swg_indoor")), expected), "NPC indoor lighting flag disagrees with source cell")
		if str(entry.cell_id) == "1106368:4":
			starport.append(entry.mobile)
			var membership: Dictionary = stage.classify_world(actor.global_position + Vector3.UP * 0.25)
			check(str(membership.get("cell_id", "")) == "1106368:4", "Starport NPC cell-local transform was not reconstructed correctly")
		if actor.animation_player != null and not str(record.animation).is_empty():
			var previous: Array[Quaternion] = []
			for bone in range(actor.skeleton.get_bone_count()):
				previous.append(actor.skeleton.get_bone_pose_rotation(bone))
			actor.animation_player.advance(0.37)
			var changed := false
			for bone in range(actor.skeleton.get_bone_count()):
				changed = changed or previous[bone].angle_to(actor.skeleton.get_bone_pose_rotation(bone)) > 0.001
			if changed:
				animation_changes += 1
		check(actor.find_children("*", "CollisionObject3D", true, false).is_empty(), "Ambient NPC accidentally installed gameplay collision")
		source_records.append({"mobile":entry.mobile,"template":entry.template,"cell_id":entry.cell_id,"animation":record.animation,"mood_restored":record.mood_restored,"ground_adjustment":record.ground_adjustment})
	for mobile in ["chassis_dealer", "ecik", "trainer_shipwright"]:
		check(starport.has(mobile), "Original starport NPC missing: " + mobile)
	check(heads_visible, "Ambient NPC heads were hidden by first-person camera layers")
	check(animation_changes > 0, "Original ambient animations did not change source skeleton poses")
	var resident := npcs.records.size()
	npcs.update_observer(Vector3(20000, 0, 20000))
	await process_frame
	await process_frame
	check(npcs.records.is_empty() and npcs.pending.is_empty(), "NPC retirement retained distant actors")
	for reference in references:
		check(reference.get_ref() == null, "Retired NPC node leaked")
	# Load a second real city, exercising different templates and source cells
	# rather than merely counting distant records in the placement manifest.
	var second_city := {}
	for entry: Dictionary in npcs.candidates:
		if str(entry.source_file).ends_with("tatooine_bestine.lua") and str(entry.cell_id).is_empty():
			second_city = entry
			break
	check(not second_city.is_empty(), "No compatible exterior Bestine source NPC")
	var bestine_resident := 0
	if not second_city.is_empty():
		var bestine: Vector3 = npcs.vec(second_city.position)
		terrain.update_observer(bestine)
		world.update_observer(bestine)
		deadline = Time.get_ticks_msec() + 60000
		while not terrain.ready_near(bestine) or not world.report.get("ready", false):
			if Time.get_ticks_msec() > deadline:
				check(false, "Bestine source environment streaming timed out")
				break
			await process_frame
		npcs.update_observer(bestine)
		deadline = Time.get_ticks_msec() + 60000
		while not npcs.report.ready:
			if Time.get_ticks_msec() > deadline:
				check(false, "Bestine original NPC appearance loading timed out")
				break
			await process_frame
		bestine_resident = npcs.records.size()
		check(bestine_resident > 0 and bestine_resident <= npcs.max_instances, "Bestine NPC residency absent or unbounded")
		for record: Dictionary in npcs.records.values():
			check(str(record.entry.source_file).ends_with("tatooine_bestine.lua"), "Mos Eisley NPC retained during Bestine visit")
		check(npcs.report.failures.is_empty(), "Another city's original NPC appearance failed to instantiate")
	# Dense original Jawa weights must reach the real streaming path rather than
	# being dropped, truncated, or tested only on an isolated native fixture.
	var jawa_entry := {}
	for entry: Dictionary in npcs.candidates:
		if str(entry.template) == "object/mobile/jawa_male.iff" and str(entry.cell_id).is_empty():
			jawa_entry = entry
			break
	check(not jawa_entry.is_empty(), "Original Jawa appearance missing from compatible placements")
	var jawa_checked := false
	if not jawa_entry.is_empty():
		var jawa_position: Vector3 = npcs.vec(jawa_entry.position)
		terrain.update_observer(jawa_position)
		world.update_observer(jawa_position)
		deadline = Time.get_ticks_msec() + 60000
		while not terrain.ready_near(jawa_position) or not world.report.get("ready", false):
			if Time.get_ticks_msec() > deadline:
				check(false, "Jawa source environment streaming timed out")
				break
			await process_frame
		npcs.update_observer(jawa_position)
		deadline = Time.get_ticks_msec() + 60000
		while not npcs.report.ready:
			if Time.get_ticks_msec() > deadline:
				check(false, "Jawa original appearance loading timed out")
				break
			await process_frame
		check(npcs.records.has(str(jawa_entry.id)), "Source Jawa omitted by runtime")
		if npcs.records.has(str(jawa_entry.id)):
			var jawa: Node3D = npcs.records[str(jawa_entry.id)].avatar
			var binding: Node = jawa.get_meta("virtual_skin_binding", null)
			check(binding != null, "Original dense Jawa skin weights lack their exact virtual binding")
			if binding != null:
				check(binding.report.valid and int(binding.report.virtual_bones) > 0, "Jawa virtual skin binding invalid")
				jawa.animation_player.advance(0.37)
				binding.update_bindings()
				check(binding.report.valid, "Jawa skin binding failed after source animation")
				jawa_checked = true
		check(npcs.report.failures.is_empty(), "Jawa source region contained an invalid NPC")
	terrain.update_observer(observer)
	world.update_observer(observer)
	deadline = Time.get_ticks_msec() + 60000
	while not terrain.ready_near(observer) or not world.report.get("ready", false):
		if Time.get_ticks_msec() > deadline:
			check(false, "Starport environment reload timed out")
			break
		await process_frame
	npcs.update_observer(observer)
	deadline = Time.get_ticks_msec() + 60000
	while not npcs.report.ready:
		if Time.get_ticks_msec() > deadline:
			check(false, "NPC reload timed out")
			break
		await process_frame
	check(npcs.records.size() == resident, "Returning to source area changed deterministic NPC residency")
	var output := {"test":"original_ambient_npc_streaming", "passed":errors.is_empty(), "hardware_tested":false,
		"elapsed_ms":Time.get_ticks_msec()-started,"errors":errors,"cities":source_cities.size(),"resident":resident,
		"starport_mobiles":starport,"bestine_resident":bestine_resident,"jawa_exact_skin_binding":jawa_checked,"animated_source_skeletons":animation_changes,"records":source_records,"stream_report":npcs.report}
	FileAccess.open("res://../runtime/evidence/ambient-npc-smoke.json", FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	print(JSON.stringify(output))
	npcs.queue_free(); world.queue_free(); terrain.queue_free(); stage.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
