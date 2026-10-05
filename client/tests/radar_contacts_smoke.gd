extends SceneTree
const Contacts = preload("res://scripts/radar_contacts.gd")
class AmbientFixture extends Node3D:
	var manifest := {"instances":[]}
	var records := {}
class MobFixture extends Node3D:
	var state: Dictionary = {}
	func get_radar_contact() -> Dictionary: return state
var checks := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func ids(contacts: Array) -> Array:
	return contacts.map(func(c): return c.id)
func run() -> void:
	var source := AmbientFixture.new()
	root.add_child(source)
	source.manifest.instances = [
		{"id":"center","position":[0,0,0]},
		{"id":"edge","position":[64,0,0]},
		{"id":"outside","position":[64.01,0,0]},
		{"id":"corner","position":[50,0,50]},
		{"id":"above","position":[0,20,-8]},
		{"id":"negative","position":[-63.9,0,0]},
		{"id":"far_moving","position":[1000,0,1000]},
		{"id":"invalid","position":[0,1]},
	]
	var provider := Contacts.new()
	provider.configure(source)
	var found: Array[Dictionary] = provider.query(Vector3.ZERO,64)
	check(ids(found)==["center","above","negative","edge"],"Inclusive circular64m range, negative tiles and deterministic near-first order")
	check(found.all(func(c): return c.relation=="neutral"),"Authored inhabitants do not invent hostility")
	check(found[1].position.y==20,"Vertical position preserved for height cues")
	check(provider.query(Vector3.ZERO,1000).size()==4,"Requested range is bounded to64m")
	check(provider.query(Vector3.INF,64).is_empty() and provider.query(Vector3.ZERO,-1).is_empty(),"Invalid observer/range rejected")
	var moving := Node3D.new()
	source.add_child(moving)
	moving.position = Vector3(2,0,0)
	moving.visible = false
	source.records.far_moving = {"avatar":moving}
	found = provider.query(Vector3.ZERO,64)
	check(ids(found).has("far_moving"),"Hidden loaded avatar overrides authored position across tile boundary")
	moving.position = Vector3(2000,0,0)
	check(not ids(provider.query(Vector3.ZERO,64)).has("far_moving"),"Moving contact leaves radar immediately")
	var mob := MobFixture.new()
	root.add_child(mob)
	mob.add_to_group("swg_radar_contacts")
	mob.state = {"id":"center","position":Vector3(3,0,1),"kind":"mob","relation":"hostile","alive":true}
	found = provider.query(Vector3.ZERO,64)
	check(found[0].id=="center" and found[0].kind=="mob" and found[0].relation=="hostile","Explicit moving mob relationship overrides neutral placement")
	check(ids(found).count("center")==1,"An entity appears only once")
	mob.state.alive = false
	check(not ids(provider.query(Vector3.ZERO,64)).has("center"),"Dead dynamic entity suppresses its stale authored contact")
	mob.state.alive = true
	mob.state.radar_visible = false
	check(not ids(provider.query(Vector3.ZERO,64)).has("center"),"Explicit radar eligibility respected")
	mob.state.radar_visible = true
	mob.state.kind = "player"
	check(not ids(provider.query(Vector3.ZERO,64)).has("center"),"Player/prop contacts are not reclassified as NPCs")
	mob.remove_from_group("swg_radar_contacts")
	source.position = Vector3(100,0,200)
	check(ids(provider.query(source.position,64)).has("edge"),"World origin/parent transform changes rebuild the spatial index")
	source.records.clear()
	source.position = Vector3.ZERO
	source.manifest.instances = []
	for i in range(200): source.manifest.instances.append({"id":"dense_%03d"%i,"position":[i*0.1,0,0]})
	provider.configure(source)
	found = provider.query(Vector3.ZERO,64)
	check(found.size()==128 and found[-1].id=="dense_127","Dense populations retain nearest128 contacts")
	# Validate against actual source placements without building any rendered avatars.
	source.manifest = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/ambient_npcs/placements.json"))
	provider.configure(source)
	var cantina := Vector3(-183.188476,-0.894991,28.903808)
	found = provider.query(cantina,64)
	var expected := 0
	for entry: Dictionary in source.manifest.instances:
		var offset := Vector2(float(entry.position[0])-cantina.x,float(entry.position[2])-cantina.z)
		if offset.length_squared()<=4096: expected += 1
	check(expected>0 and found.size()==mini(expected,128),"Actual cantina query matches exhaustive authored placement count")
	check(int(provider.report.visited)<int(provider.report.indexed),"Actual query visits nearby spatial tiles rather than all Tatooine placements")
	var actual := provider.report.duplicate()
	provider.clear()
	check(provider.query(cantina,64).is_empty(),"Clear removes previous character/world contacts")
	var report := {"test":"radar_contacts","passed":failures.is_empty(),"checks":checks,"failures":failures,"actual_cantina":actual,"gpu_validated":false,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/radar-contacts-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	source.queue_free(); mob.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
