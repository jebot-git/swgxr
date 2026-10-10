extends SceneTree
## Reported tester regressions with synthetic poses and original asset catalogs.
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var ui:=preload("res://scripts/xr_services.gd").new();root.add_child(ui)
	var bounds:=AABB(Vector3(-.7,0,-.5),Vector3(1.4,2,1.5))
	for kind in ["bank","bazaar"]:
		var record:Dictionary={"kind":kind,"position":Vector3.ZERO,"ui_anchors":[Transform3D(Basis.IDENTITY,Vector3(0,1.3,.1))],"pick_geometry":{"bounds":bounds},"pick_pose":Transform3D.IDENTITY}
		var pose:Transform3D=ui.terminal_pose(record,Vector3(0,1.4,.5),Vector3(0,1.7,2))
		check(pose.origin.z>=1.12-.001,kind+" hologram clears the full keyboard/casing, not only the glass")
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel)
	var requests:Array=[];panel.action_requested.connect(func(action,body):requests.append(body))
	for index in range(4):
		panel.configure({"id":"10","kind":"bazaar","listings":[],"search_scope":"galaxy"},{})
		panel.page=4;panel.click_at(Vector2(30+index*137,80))
		check(requests.back().search_scope==panel.SEARCH_SCOPES[index] and requests.back().page==0,"Scope button sends native filter and resets pagination: "+panel.SEARCH_SCOPES[index])
	var wheel:=preload("res://space/command_wheel.gd").new();root.add_child(wheel)
	wheel.open(Transform3D.IDENTITY,[{"id":"land","label":"Land at Coronet","available":true}]);wheel.show_dialogue("Corellia station: Select your intended spaceport.");wheel.choose(Vector2(0,1))
	check(wheel.dialogue.visible and "Corellia station" in wheel.dialogue.text and wheel.dialogue.position.x==0,"Station dialogue remains visible at wheel centre while selecting reply")
	wheel.close();wheel.open(Transform3D.IDENTITY,[]);check(not wheel.dialogue.visible,"Unrelated command wheel clears old station dialogue")
	var effects:=preload("res://space/hyperspace.gd").new();root.add_child(effects)
	var eye:=Camera3D.new();root.add_child(eye);effects.setup(eye)
	check(effects.assets.catalog.get("seat_poses",{}).size()==20,"Original chair pose is available for every player race/sex")
	for position in [Vector3(0,1.7,0),Vector3(.2,1.3,-.15)]:
		eye.transform=Transform3D(Basis.from_euler(Vector3(.2,.7,.1)),position)
		var before:=eye.transform;effects._process(.016)
		check(effects.global_transform.is_equal_approx(eye.global_transform) and eye.transform==before,"Hyperspace follows translated/rotated centre-eye frame without changing tracking")
	var nav:=preload("res://space/navigation_controls.gd").new();root.add_child(nav)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/jtl/catalog.json"))
	nav.configure(catalog,{"station":"pilot"})
	var jump_ids:Array=[];nav.jump_requested.connect(func(id):jump_ids.append(id))
	for index in nav.destinations.item_count:
		if str(nav.destinations.get_item_metadata(index))!="space_corellia_4":continue
		nav.destinations.select(index);nav.update_description();nav.jump.pressed.emit()
		check(jump_ids.back()=="space_corellia_4" and "Talus Secta" in nav.info.text and "Shared Corellia/Talus" in nav.info.text,"Talus jump point retains exact native ID and explains the shared sector")
	var audio:=preload("res://space/audio.gd").new();root.add_child(audio)
	audio.observe({"zone":"space_tatooine","template":"object/ship/player/player_sorosuub_space_yacht.iff","speed_mps":30,"max_speed_mps":60})
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline and (audio.music.stream==null or audio.layers.run.player.stream==null or audio.layers.interior.player.stream==null):await create_timer(.02).timeout
	check(audio.music.stream!=null and audio.layers.run.player.stream!=null and audio.layers.interior.player.stream!=null,"Original sector music, yacht engine and cabin ambience decode through production audio cache")
	check(audio.desired.run.gain==.5 and audio.desired.idle.gain==.5,"Engine mix follows acknowledged native speed")
	for node in [ui,panel,wheel,effects,eye,nav,audio]:node.queue_free()
	await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"tracking":"synthetic","xr":false,"renderer":"dummy","physical_audio_validated":false}));quit(0 if failures.is_empty() else 1)
