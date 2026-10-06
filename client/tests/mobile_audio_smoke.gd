extends SceneTree
## Original local audio and real mixer capture; no headset or GPU claim.
const Emitter=preload("res://audio/mobile_emitter.gd")
var failures:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:create_timer(45).timeout.connect(func():quit(2));call_deferred("run")
func wait_for_sound(mixer:Node,sound:String)->void:
	for i in range(200):
		if mixer.active.any(func(p):return p.get_meta("source_sound","")==sound):return
		await create_timer(.02).timeout
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true
	var mixer:=preload("res://audio/spatial_audio.gd").new();world.add_child(mixer);mixer.configure(camera,null,"stereo",true)
	var master_volume:=AudioServer.get_bus_volume_db(0);AudioServer.set_bus_volume_db(0,-80)
	var capture:=AudioEffectCapture.new();capture.buffer_length=1
	var effects_bus:=AudioServer.get_bus_index("SWG Effects")
	var effect_index:=AudioServer.get_bus_effect_count(effects_bus);AudioServer.add_bus_effect(effects_bus,capture)
	var car:=Emitter.new();world.add_child(car);car.position=Vector3(-2,0,-2)
	car.observe("object/mobile/vehicle/landspeeder_x31.iff",0,true)
	var definition:Dictionary=mixer.mobile.binding(car.source_template)
	var slots:Dictionary=mixer.mobile.vehicle_slots(definition,0)
	check(str(definition.kind)=="vehicle" and slots.idle=="sound/veh_flashspeeder_idle_lp.snd","X31 resolves exact original saddle sound mapping")
	await wait_for_sound(mixer,slots.idle)
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")==slots.idle and p.stream.loop),"Original idle sample decodes and plays continuously")
	capture.clear_buffer();await create_timer(.35).timeout
	var energy:=0.0
	for frame:Vector2 in capture.get_buffer(capture.get_frames_available()):energy+=frame.length_squared()
	check(energy>0.00001,"Original vehicle audio produces nonzero mixed audio")
	car.position=Vector3(3,0,-1);await create_timer(.08).timeout
	check(mixer.active.any(func(p):return p.global_position.distance_to(car.global_position)<.001),"Engine source follows rendered vehicle position")
	car.observe(car.source_template,4,true)
	await wait_for_sound(mixer,slots.run)
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")==slots.run),"Motion selects original running loop")
	check(not mixer.active.any(func(p):return p.get_meta("source_sound","")==slots.idle),"Running vehicle retires idle loop")
	await wait_for_sound(mixer,slots.accel)
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")==slots.accel),"Start of motion plays original acceleration effect")
	car.observe(car.source_template,0,true)
	await wait_for_sound(mixer,slots.decel)
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")==slots.decel),"Stopping plays original deceleration effect")
	var actor:=preload("res://combat/live_actor.gd").new();world.add_child(actor)
	var assets:=preload("res://scripts/inventory_assets.gd").new();assets.configure()
	var row:Dictionary={"id":"test_r2","template":"object/mobile/r2.iff","kind":"creature","droid":true,"dead":false,"health":100,"max_health":100,"name":"Original R2"}
	actor.configure(row,"mocked-source-record",assets,assets,ProjectSettings.globalize_path("res://../runtime/assets/combat_population/native_current/catalog.json"))
	actor.apply_record(row,Transform3D(Basis.IDENTITY,Vector3(1,0,-2)),1,true)
	var droid:Node3D=actor.mobile_sound
	check(is_instance_valid(droid) and droid.source_template==row.template,"Production live actor creates its original droid audio emitter")
	var robot:Dictionary=mixer.mobile.binding(droid.source_template)
	await wait_for_sound(mixer,robot.ambient[0])
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")==robot.ambient[0]),"Original R2 ambient variant bank is audible")
	var repeat_due:=0.0
	for channel:Dictionary in mixer.mobile.channels.values():
		if channel.sound==robot.ambient[0] and is_instance_valid(channel.get("player")):
			repeat_due=float(channel.due)-mixer.mobile.clock-channel.player.stream.get_length()
	check(repeat_due>=3.5 and repeat_due<=10,"Droid ambient uses original 4–10 second repeat delay")
	actor.apply_record(row,Transform3D(Basis.IDENTITY,Vector3(2,0,-2)),.5)
	await wait_for_sound(mixer,robot.events.footstep)
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")==robot.events.footstep),"Moving player droid plays its original CSND movement sound")
	actor.apply_record(row,Transform3D(Basis.IDENTITY,Vector3(2,0,-2)),1);await create_timer(.2).timeout
	check(not mixer.active.any(func(p):return p.get_meta("source_sound","")==robot.events.footstep),"Stopped droid retires movement source")
	car.hide();await create_timer(.2).timeout
	check(not mixer.mobile.channels.values().any(func(c):return c.emitter==car),"Hidden entity retires every attached channel")
	row.health=90;actor.apply_record(row,actor.goal,1)
	await wait_for_sound(mixer,robot.events.hitlight)
	check(mixer.active.any(func(p):return p.get_meta("source_sound","")==robot.events.hitlight),"Observed native droid damage plays original hit effect")
	droid.fresh_until=0;await create_timer(.2).timeout
	check(mixer.mobile.channels.is_empty(),"Stale native entity is silent")
	for i in range(24):
		var extra:=Emitter.new();world.add_child(extra);extra.position=Vector3(i%5,0,-2)
		extra.observe(car.source_template,0,true)
	await create_timer(.4).timeout
	check(mixer.mobile.channels.size()<=16 and mixer.active.size()<=32,"Crowded vehicle audio obeys shared voice budget")
	for emitter:Node in get_nodes_in_group("swg_mobile_audio"):emitter.free()
	await create_timer(.2).timeout
	check(mixer.mobile.channels.is_empty() and mixer.active.is_empty(),"Recall/despawn frees audio voices")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"mixed_energy":energy,"renderer":"headless dummy","hardware_listening_tested":false,"cache":mixer.mobile.cache.statistics()}
	FileAccess.open("res://../runtime/evidence/core4-review/audio.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	mixer.clear();AudioServer.remove_bus_effect(effects_bus,effect_index);AudioServer.set_bus_volume_db(0,master_volume)
	world.free();await process_frame;quit(0 if failures.is_empty() else 1)
