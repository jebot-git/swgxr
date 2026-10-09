extends SceneTree
const CombatAssets = preload("res://combat/original_assets.gd")
const EntertainmentAssets = preload("res://entertainment/assets.gd")
const CombatEffects = preload("res://combat/effect_player.gd")
const EntertainmentEffects = preload("res://entertainment/effects.gd")
var checks := 0
var failures: Array[String] = []
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var combat := CombatAssets.new()
	var entertainment := EntertainmentAssets.new()
	check(combat.load_catalog() and entertainment.load_catalog(),"Original combat and entertainment catalogs load")
	var world := Node3D.new()
	root.add_child(world)
	var eye := Camera3D.new()
	world.add_child(eye)
	var effects := EntertainmentEffects.new()
	world.add_child(effects)
	effects.configure(entertainment,eye)
	var shots := CombatEffects.new()
	world.add_child(shots)
	shots.configure(combat,eye)
	check(shots.manager==effects.manager,"Entertainment-first initialization and combat share one world budget")
	var manager: Node3D = effects.manager
	manager.set_process(false)
	manager.set_view(Transform3D.IDENTITY,100,1.4)
	var combat_programs: Array = manager.styles.keys()
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,0,-5))
	for path: String in entertainment.catalog.effects:
		check(effects.play(path,pose),"Original performer effect accepted: "+path)
		manager.advance(2)
	for path: String in entertainment.catalog.particles:
		manager.burst(path,pose,1.0,"impact",effects.resources)
		manager.advance(2)
	var stats: Dictionary = manager.statistics()
	check(stats.evicted_programs>0,"More than thirty-two source paths use bounded idle LRU eviction")
	check(stats.styles<=48 and stats.source_programs<=32 and stats.render_nodes<=48,"All native style/program/node caps stay unchanged")
	check(effects.resources.textures.size()<=16,"Entertainment CPU texture cache remains bounded")
	for key: String in manager.transient_programs:
		for compiled: Dictionary in manager.styles[key]: manager.batch.emit_burst(int(compiled.id),pose,1)
	var keys_before: Array = manager.styles.keys()
	var refused := false
	for path: String in entertainment.catalog.particles:
		var key := str(effects.resources.get_instance_id())+":"+path+":impact"
		if manager.styles.has(key): continue
		refused = manager.compile_source(path,"impact",effects.resources).is_empty()
		break
	check(refused and manager.styles.keys()==keys_before,"Fully occupied style budget drops a new effect without evicting active programs")
	manager.advance(2)
	for key: String in combat_programs: check(manager.styles.has(key),"Original combat source remains pinned: "+key)
	var original: Array = manager.compile_source("appearance/pt_bolt_red.prt","tracer")
	var style: Dictionary = original[0]
	var tracer: int = manager.batch.create_tracer(int(style.id),pose)
	check(tracer>=0 and not manager.batch.can_replace_style(int(style.id)),"Live tracer protects native style from replacement")
	check(manager.batch.replace_style(int(style.id),style.definition)==-1,"Native replacement rejects active tracer style")
	manager.batch.release_tracer(tracer)
	check(manager.batch.can_replace_style(int(style.id)),"Released tracer permits style reuse")
	manager.batch.emit_burst(int(style.id),pose,1)
	check(not manager.batch.can_replace_style(int(style.id)),"Live particle protects native style from replacement")
	manager.advance(2)
	check(manager.batch.can_replace_style(int(style.id)),"Expired particle permits style reuse")
	var far := Transform3D(Basis.IDENTITY,Vector3(0,0,-200))
	var example: String = entertainment.catalog.effects.keys()[0]
	check(not effects.play(example,far),"Distant entertainment follows shared native distance culling")
	var behind := Transform3D(Basis.IDENTITY,Vector3(0,0,25))
	check(not effects.play(example,behind),"Offscreen entertainment follows shared native frustum culling")
	check(manager.statistics().dynamic_lights==0,"No dynamic entertainer lights")
	var result := {"checks":checks,"failures":failures,"statistics":manager.statistics(),"renderer":"headless dummy; no GPU or headset validation"}
	print(JSON.stringify(result))
	var file := FileAccess.open("res://../runtime/evidence/entertainer-effect-tests.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result,"\t"))
	world.queue_free()
	manager.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
