extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true
	var mixer:=preload("res://audio/spatial_audio.gd").new();world.add_child(mixer);mixer.configure(camera,null,"stereo",true)
	AudioServer.set_bus_volume_db(0,-80)
	var actor:=preload("res://combat/live_actor.gd").new();world.add_child(actor)
	actor.record={"id":"7","template":"object/mobile/womp_rat.iff","kind":"creature","dead":false,"health":100,"max_health":100}
	actor.mobile_sound=preload("res://audio/mobile_emitter.gd").new();actor.add_child(actor.mobile_sound)
	actor.mobile_sound.observe(actor.record.template,0,true)
	var definition:Dictionary=mixer.mobile.binding(actor.record.template)
	check(definition.events.attacklight=="sound/cr_womprat_attack_light.snd","Original creature attack binding is retained")
	var event:Dictionary={"id":"7","event":"attack","sequence":1}
	actor.apply_combat_event(event,1);actor.apply_combat_event(event,1)
	check(actor.mobile_sound.events==["attacklight"],"Repeated native sync emits one attack cue")
	for i in range(80):
		await create_timer(.025).timeout
		if mixer.played>0:break
	check(mixer.played>0,"Original creature attack sample decodes and plays")
	var played:int=mixer.played
	event.sequence=2;actor.apply_combat_event(event,1)
	for i in range(80):
		await create_timer(.025).timeout
		if mixer.played>played:break
	check(mixer.played>played,"A subsequent attack is audible while the prior tail exists")
	actor.apply_combat_event(event,0)
	check(actor.mobile_sound.events.is_empty(),"Old scene events do not replay")
	actor.mobile_sound.observe("object/mobile/stormtrooper.iff",0,true)
	event.sequence=3;event.weapon_template="object/weapon/ranged/pistol/pistol_cdef.iff";actor.apply_combat_event(event,1)
	for i in range(80):
		await create_timer(.025).timeout
		if mixer.active.any(func(p):return p.get_meta("source_sound","")=="sound/wep_fire_blaster.snd"):break
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")=="sound/wep_fire_blaster.snd"),"Native NPC attack selects its equipped weapon's original fire sound")
	actor.record.template="object/mobile/stormtrooper.iff"
	actor.finish_death_audio();actor.free()
	for i in range(80):
		await create_timer(.025).timeout
		if mixer.active.any(func(p):return p.get_meta("source_sound","")=="voice/sound/voice_pl_strmtrpr_death.snd"):break
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")=="voice/sound/voice_pl_strmtrpr_death.snd"),"Death tail survives live mesh replacement")
	var environment:=preload("res://scripts/environment_presentation.gd").new();world.add_child(environment)
	var planets:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/planets/catalog.json"))
	check(environment.configure(planets.planets.tatooine.environment),"Ground environment and original game music banks load")
	environment.set_active(true);environment.observe_native_music({"in_combat":false})
	environment.observe_native_music({"in_combat":true})
	for i in range(80):
		await create_timer(.025).timeout
		if environment.game_audio.cues.enter.has(environment.report.get("music","")):break
	check(environment.game_audio.cues.enter.has(environment.report.get("music","")),"Native combat entry plays original GMUS ENTR cue")
	environment.observe_native_music({"in_combat":true,"incapacitated":true})
	for i in range(80):
		await create_timer(.025).timeout
		if environment.game_audio.cues.incapacitated.has(environment.report.get("music","")):break
	check(environment.game_audio.cues.incapacitated.has(environment.report.get("music","")),"Native incap state plays original INCP cue")
	var count:int=environment.report.music_events;environment.observe_native_music({"in_combat":true,"incapacitated":true})
	await create_timer(.1).timeout
	check(environment.report.music_events==count,"Unchanged native posture does not restart music")
	check(mixer.active.size()<=32 and mixer.mobile.channels.size()<=16,"Entity effects stay within shared audio limits")
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","xr":false,"actual_original_audio_decoded":true}
	print(JSON.stringify(result));FileAccess.open("res://../runtime/evidence/swg-motion-20261010/npc-combat-audio.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	world.free();await process_frame;quit(0 if failures.is_empty() else 1)
