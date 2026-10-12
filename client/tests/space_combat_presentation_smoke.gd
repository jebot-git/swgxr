extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,10000,0);camera.current=true
	var mixer:=root.get_node("SWGSpatialAudio");mixer.configure(camera,null,"stereo",true)
	var audio:=preload("res://space/audio.gd").new();root.add_child(audio)
	var ship:Dictionary={"zone":"space_tatooine","template":"object/ship/player/player_tie_light_duty.iff","position":[20,30,40],"max_speed_mps":100,"speed_mps":50,"audio_chassis":"player_prototype_tiefighter","engine_component":"eng_crafted_incom_fusialthrust"}
	var bindings:Dictionary=audio.catalog.engine_bindings[ship.audio_chassis]
	ship.engine_component=bindings.keys()[0]
	var pose:=Transform3D(Basis(Vector3.UP,.7),Vector3(20,30,-40))
	var event:Dictionary={"id":"audio1","kind":"hit","hit_type":0,"position":[20,30,40],"age_seconds":0}
	audio.observe(ship,[event,event],pose,Transform3D(Basis.IDENTITY,Vector3(0,10000,0)))
	check(not audio.pending_effects.is_empty(),"Original shield sound queued")
	for effect:Dictionary in audio.pending_effects:check(effect.position.distance_to(camera.position)<.01,"Space sound uses cockpit world frame, not world origin")
	var count:=audio.pending_effects.size()
	for i in range(120):
		await create_timer(.01).timeout
		if audio.effects_played>0:break
	check(audio.effects_played>0,"Original combat sample decoded and accepted by distance-limited mixer")
	audio.observe(ship,[event],pose,Transform3D(Basis.IDENTITY,Vector3(0,10000,0)))
	check(audio.pending_effects.is_empty(),"Overlapping native snapshots do not repeat sound")
	check(audio.desired.engine_0.engine.sound=="sound/eng_run_tie.snd","Installed TIE engine resolves original attachment sound")
	check(not audio.desired.engine_1.running,"Booster loop is silent while booster is inactive")
	ship.booster_active=true;audio.observe(ship,[],pose,Transform3D.IDENTITY)
	check(audio.desired.engine_1.running,"Native booster flag enables booster loop")
	ship.destroyed=true;audio.observe(ship)
	for target:Dictionary in audio.desired.values():
		if target.has("engine"):check(not target.running,"Destroyed ship silences engine/booster")
	var comm:=preload("res://space/communications.gd").new();root.add_child(comm)
	var receipts:Array=[{"id":"3","kind":"message","text":"Enemy group detected","sender":"Patrol leader"},{"id":"2","kind":"message","text":"Mission started"},{"id":"1","kind":"message","text":"Expired","age_seconds":20}]
	comm.receive(receipts);comm.receive(receipts);comm.update_view(camera.global_transform,true)
	check(comm.lines.size()==2 and comm.lines[0].text=="Mission started","Original messages preserve order, suppress stale receipts and duplicates")
	check(comm.lines[1].text.begins_with("Patrol leader: "),"NPC sender labels survive presentation")
	check(comm.visible and comm.global_position.distance_to(camera.position)<3,"Mission communications remain in cockpit view")
	comm.clear();check(not comm.visible,"Leaving JTL clears mission overlay")
	audio.queue_free();comm.queue_free();mixer.queue_free();camera.queue_free();await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"audio_device":"dummy","live_xr":false,"original_samples_accepted":count}));quit(0 if failures.is_empty() else 1)
