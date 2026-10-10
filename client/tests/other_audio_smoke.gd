extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func wait_sound(mixer:Node,sound:String)->bool:
	for i in range(100):
		if mixer.active.any(func(p):return p.get_meta("source_sound","")==sound and p.playing):return true
		await create_timer(.02).timeout
	return false
func run()->void:
	AudioServer.set_bus_volume_db(0,-80)
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true
	var mixer:=root.get_node("SWGSpatialAudio");mixer.configure(camera,null,"stereo",true)
	var ui:=root.get_node("SWGUIAudio")
	var button:=Button.new();root.add_child(button);button.pressed.emit()
	for i in range(60):
		await create_timer(.02).timeout
		if ui.played>0:break
	check(ui.played>0,"Original UI select cue plays through actual button signal")
	var actor:=preload("res://combat/live_actor.gd").new();world.add_child(actor)
	var assets:=preload("res://scripts/inventory_assets.gd").new();assets.configure()
	var row:Dictionary={"id":"audio_rat","template":"object/mobile/womp_rat.iff","kind":"creature","dead":false,"health":100,"max_health":100,"name":"Womp rat"}
	check(actor.configure(row,"audio-fixture",assets,assets,ProjectSettings.globalize_path("res://../runtime/assets/combat_population/tatooine_entities/catalog.json")),"Actual original creature model loads")
	actor.apply_record(row,Transform3D(Basis.IDENTITY,Vector3(1,0,-2)),1,true)
	actor.set_process(false);actor.set_physics_process(false)
	check(actor.mobile_sound.animation_driven,"Imported original frame messages enable animation-timed audio")
	actor.visual.animation_player.play("walk")
	actor.visual.animation_player.advance(.8)
	check(await wait_sound(mixer,"sound/cr_generic_small_fs_walk.snd"),"Original walk clip dispatches its footstep to spatial playback")
	actor.free();mixer.clear()
	var steps:=preload("res://audio/player_footsteps.gd").new();world.add_child(steps)
	steps.observe(Vector3.ZERO,"object/creature/player/human_male.iff",true,true)
	steps.observe(Vector3(.9,0,0),"object/creature/player/human_male.iff",true,true)
	check(await wait_sound(mixer,"sound/fs_out_sand_crunch.snd"),"Actual player travel plays source footstep without driving tracked pose")
	steps.observe(Vector3(8,0,0),"object/creature/player/human_male.iff",true,true)
	check(steps.emitter.events.is_empty(),"Teleport does not emit a burst of footsteps")
	steps.observe(Vector3(8.9,0,0),"object/creature/player/human_male.iff",false,true)
	check(steps.emitter.events.is_empty(),"Airborne travel stays silent")
	steps.free();mixer.clear()
	var environment:=preload("res://scripts/environment_presentation.gd").new();world.add_child(environment)
	var planets:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/planets/catalog.json"))
	check(environment.configure(planets.planets.tatooine.environment),"Original environmental audio loads")
	var terrain:=preload("res://scripts/terrain_stream.gd").new();world.add_child(terrain)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/terrain/tatooine.json"))
	# Controlled water coverage with the production source evaluator, no renderer claim.
	source.global_water_enabled=true;source.global_water_height=1000
	terrain.source_manifest=source;terrain.evaluator.configure(source);terrain.configured=true
	environment.bind_world(terrain,null);environment.set_active(true)
	for i in range(100):
		environment.refresh_water_audio();await create_timer(.02).timeout
		if environment.water_audio.playing:break
	check(environment.water_audio.playing and environment.water_audio.stream.get_length()>0,"Original WATR cue plays for wet terrain neighborhood")
	environment.indoors=true;environment.refresh_water_audio()
	check(not environment.water_audio.playing,"Indoor observer suppresses exterior water audio")
	environment.free();terrain.free()
	var space:=preload("res://space/audio.gd").new();world.add_child(space)
	var ship:Dictionary={"id":"ship","zone":"space_tatooine","template":"object/ship/player/player_sorosuub_space_yacht.iff","position":[0,0,0],"speed_mps":0,"max_speed_mps":100}
	space.observe(ship)
	for i in range(100):
		await create_timer(.02).timeout
		if space.layers.idle.player.playing and space.layers.interior.player.playing and space.music.playing:break
	check(space.layers.idle.player.playing and space.layers.interior.player.playing and space.music.playing,"Ship idle/interior and original Tatooine entry music play")
	ship.speed_mps=50;space.observe(ship)
	check(await wait_sound(mixer,str(space.catalog.ships[ship.template].accel)),"Ship acceleration recording plays on actual speed transition")
	var event:Dictionary={"id":"shot1","kind":"projectile","projectile_type":1,"position":[0,0,1],"age_seconds":0}
	var count:int=space.effects_played;space.observe(ship,[event,event])
	var fire:String=space.catalog.projectiles["1"][0]
	check(await wait_sound(mixer,fire),"Native projectile type selects original ship firing effect")
	var after:int=space.effects_played;space.observe(ship,[event]);await create_timer(.1).timeout
	check(space.effects_played==after and after>count,"Repeated native ship event does not repeat sound")
	space.observe(ship,[{"id":"hit1","kind":"hit","hit_type":0,"position":[0,0,1],"age_seconds":0}])
	check(await wait_sound(mixer,str(space.catalog.hits["0"][0])),"Native shield contact selects original impact effect")
	mixer.clear();space.free();world.free();button.free();await process_frame
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"audio_driver":AudioServer.get_driver_name(),"xr":false,"renderer":"dummy","hardware_listening_tested":false}
	print(JSON.stringify(result));FileAccess.open("res://../runtime/evidence/swg-motion-20261010/other-audio.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	quit(0 if failures.is_empty() else 1)
